//=============================================================================
//  Copyright (c) 2016, SignalPOP.  All rights reserved.
//
//	--CAFFE--
//  Portions Copyright (c) 2014, 2015, The Regents of the University of California (Regents)
//  All rights reserved.
//  
//  All other contributions:
//  Portions Copyright (c) 2014, 2015, the respective contributors
//  All rights reserved.
//	
//	--TSNE--
//  Portions Copyright (c) 2014, Laurens van der Maaten (Delft University of Technology)
//  All rights reserved.
//   
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//  1. Redistributions of source code must retain the above copyright
//     notice, this list of conditions and the following disclaimer.
//  2. Redistributions in binary form must reproduce the above copyright
//     notice, this list of conditions and the following disclaimer in the
//     documentation and/or other materials provided with the distribution.
//  3. All advertising materials mentioning features or use of this software
//     must display the following acknowledgement:
//     This product includes software developed by the Delft University of Technology.
//  4. Neither the name of the Delft University of Technology nor the names of 
//     its contributors may be used to endorse or promote products derived from 
//     this software without specific prior written permission.
// 
//  THIS SOFTWARE IS PROVIDED BY LAURENS VAN DER MAATEN ''AS IS'' AND ANY EXPRESS
//  OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
//  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO 
//  EVENT SHALL LAURENS VAN DER MAATEN BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, 
//  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, 
//  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR 
//  BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
//  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING 
//  IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY 
//  OF SUCH DAMAGE.
//
//	--Guassian Blur--
//	Created by AlanTatourian and Licensed by Microsoft under the Apache License, Version 2.0
//	See https://code.msdn.microsoft.com/windowsdesktop/Gaussian-blur-with-CUDA-5-df5db506
//
//  (See LICENSE.TXT for full copyright and license)
//	
//	FILE:	math.cu
//
//	DESC:	This file implements the math operations performed on the GPU.
//=============================================================================

#include "math.h"
#include "memory.h"
#include <cfloat>
#include <thrust/device_vector.h>
#include <thrust/extrema.h>
#include "tsne_g.h"
#include <vector>
#include <utility>
#include <algorithm>
#include <math.h>

//=============================================================================
//	Constants
//=============================================================================

#define M_PI       3.14159265358979323846   // pi

const int NUM_BLOCKS_MAX = 65535;
const int ADD_BLOCK_SIZE = 16;
const int NUM_SUM_COLS_THREADS_PER_BLOCK = 256;
const int MAX_SH_MEM = 512;

inline int DIVUP(int x, int y)
{
	return (x + y - 1) / y;
}


//=============================================================================
//	Private Structs & Methods
//=============================================================================

template <class T>
struct PointDist
{
	T x;
	T y;
	T d;
};

template <typename T>
bool sortPointDist(PointDist<T> a, PointDist<T> b)
{
	return a.d < b.d;
}


//=============================================================================
//  Helper Functions
//=============================================================================

template<typename T>
inline __device__ T math_atomic_add(const T val, T* address);

template<>
inline __device__ float math_atomic_add(const float val, float* address)
{
	return atomicAdd(address, val);
}

// double atomicAdd implementation taken from
// https://docs.nvidia.com/cuda/cuda-c-programming-guide/#atomicadd
template<>
inline __device__ double math_atomic_add(const double val, double* address)
{
	unsigned long long int* address_as_ull = (unsigned long long int*)address;
	unsigned long long int old = *address_as_ull;
	unsigned long long int assumed;

	do {
		assumed = old;
		old = atomicCAS(address_as_ull, assumed,
			__double_as_longlong(val +
				__longlong_as_double(assumed)));

		// Note: uses integer comparison to avoid hang in case of NaN (since NaN != NaN)
	} while (assumed != old);

	return __longlong_as_double(old);
}


template<typename T>
inline __device__ T math_atomic_min(T* address, T val);

template<>
inline __device__ float math_atomic_min(float* address, float val)
{
	int ret = __float_as_int(*address);

	while (val < __int_as_float(ret))
	{
		int old = ret;
		if ((ret = atomicCAS((int*)address, old, __float_as_int(val))) == old)
			break;
	}

	return __int_as_float(ret);
}

template<>
inline __device__ double math_atomic_min(double* address, double val)
{
	unsigned long long ret = __double_as_longlong(*address);

	while (val < __longlong_as_double(ret))
	{
		unsigned long long old = ret;
		if ((ret = atomicCAS((unsigned long long*)address, old, __double_as_longlong(val))) == old)
			break;
	}

	return __longlong_as_double(ret);
}


template<typename T>
inline __device__ T math_atomic_max(T* address, T val);

template<>
inline __device__ float math_atomic_max(float* address, float val)
{
	int ret = __float_as_int(*address);

	while (val > __int_as_float(ret))
	{
		int old = ret;
		if ((ret = atomicCAS((int*)address, old, __float_as_int(val))) == old)
			break;
	}

	return __int_as_float(ret);
}

template<>
inline __device__ double math_atomic_max(double* address, double val)
{
	unsigned long long ret = __double_as_longlong(*address);

	while (val > __longlong_as_double(ret))
	{
		unsigned long long old = ret;
		if ((ret = atomicCAS((unsigned long long*)address, old, __double_as_longlong(val))) == old)
			break;
	}

	return __longlong_as_double(ret);
}


//=============================================================================
//	Class Methods
//=============================================================================

template <class T>
void Math<T>::Connect(Memory<T>* pMem)
{
	m_pMem = pMem;
	m_pMemCol = pMem->GetMemoryCollection();
	m_pStreamCol = pMem->GetStreamCollection();
}

template void Math<double>::Connect(Memory<double>* pMem);
template void Math<float>::Connect(Memory<float>* pMem);


template <typename T>
__global__ void set_kernel(const int n, const T alpha, T* y)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		y[i] = alpha;
	}
}

template <class T>
long Math<T>::set(int nCount, long hDst, T fVal, int nIdx, int nXOff)
{
	LONG lErr;
	MemoryItem* pItem;

	if (lErr = m_pMemCol->GetData(hDst, &pItem))
		return lErr;

	if (fVal == 0 && nIdx == -1 && nXOff == 0)
	{ 
		if (lErr = pItem->SetData(0))
			return lErr;

		return 0;
	}

	T* pData = (T*)pItem->Data();

	if (nXOff > 0)
		pData += nXOff;

	if (nIdx >= 0)
	{
		if (nIdx > 0)
			pData += nIdx;

		if (lErr = cudaMemcpy(pData, &fVal, sizeof(T), cudaMemcpyHostToDevice))
			return lErr;
	}
	else
	{
		set_kernel<T><<<CAFFE_GET_BLOCKS(nCount), CAFFE_CUDA_NUM_THREADS>>>(nCount, fVal, pData);
	}

	return cudaGetLastError();
}

template long Math<double>::set(int nCount, long hDst, double fVal, int nIdx, int nXOff);
template long Math<float>::set(int nCount, long hDst, float fVal, int nIdx, int nXOff);


template <class T>
long Math<T>::get(int nCount, long hDst, int nIdx, T* pfOutput)
{
	LONG lErr;
	MemoryItem* pItem;

	if (lErr = m_pMemCol->GetData(hDst, &pItem))
		return lErr;

	if (nIdx == -1)
		return cudaMemcpy(pfOutput, pItem->Data(), sizeof(T) * nCount, cudaMemcpyDeviceToHost);	

	T* pData = (T*)pItem->Data();
	pData += nIdx;

	return cudaMemcpy(pfOutput, pData, sizeof(T), cudaMemcpyDeviceToHost);
}

template long Math<double>::get(int nCount, long hDst, int nIdx, double* pfOutput);
template long Math<float>::get(int nCount, long hDst, int nIdx, float* pfOutput);


template <class T>
long Math<T>::copy(int nCount, long hSrc, long hDst, int nSrcOffset, int nDstOffset, long hAsyncStream)
{
	LONG lErr;
	long lSize = nCount * sizeof(T);
	MemoryItem* pSrc;
	MemoryItem* pDst;

	if (lErr = m_pMemCol->GetData(hSrc, &pSrc))
		return lErr;

	if (lErr = m_pMemCol->GetData(hDst, &pDst))
		return lErr;

	T* src = (T*)pSrc->Data();
	T* dst = (T*)pDst->Data();

	if (nSrcOffset > 0)
		src += nSrcOffset;

	if (nDstOffset > 0)
		dst += nDstOffset;

	if (hAsyncStream < 0)
		return cudaMemcpy(dst, src, lSize, cudaMemcpyDeviceToDevice);

	if (hAsyncStream == 0)
		return cudaMemcpyAsync(dst, src, lSize, cudaMemcpyDeviceToDevice, cudaStreamDefault);

	cudaStream_t stream = (cudaStream_t)m_pStreamCol->GetData(hAsyncStream);

	return cudaMemcpyAsync(dst, src, lSize, cudaMemcpyDeviceToDevice, stream);
}

template long Math<double>::copy(int nCount, long hSrc, long hDst, int nSrcOffset, int nDstOffset, long hAsyncStream);
template long Math<float>::copy(int nCount, long hSrc, long hDst, int nSrcOffset, int nDstOffset, long hAsyncStream);

template<>
long Math<double>::nrm2(int n, long hA, int nAOff, double* pdfResult)
{
	LONG lErr;

	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	MemoryItem* pA;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;
	
	double* a = (double*)pA->Data();
	if (nAOff > 0)
		a += nAOff;

	return cublasDnrm2(m_cublas, n, a, 1, pdfResult);
}

template<>
long Math<float>::nrm2(int n, long hA, int nAOff, float* pfResult)
{
	LONG lErr;

	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	MemoryItem* pA;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;
	
	float* a = (float*)pA->Data();
	if (nAOff > 0)
		a += nAOff;

	return cublasSnrm2(m_cublas, n, a, 1, pfResult);
}

template<>
long Math<double>::ger(int m, int n, double fAlpha, long hA, long hB, long hC, int nAoff, int nBoff, int nCoff)
{
	LONG lErr;

	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	MemoryItem* pA;
	MemoryItem* pB;
	MemoryItem* pC;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hB, &pB))
		return lErr;

	if (lErr = m_pMemCol->GetData(hC, &pC))
		return lErr;

	double* a = (double*)pA->Data();
	double* b = (double*)pB->Data();
	double* c = (double*)pC->Data();

	if (nAoff > 0)
		a += nAoff;

	if (nBoff > 0)
		b += nBoff;

	if (nCoff > 0)
		c += nCoff;

	return cublasDger(m_cublas, m, n, &fAlpha, a, 1, b, 1, c, 1);
}

template<>
long Math<float>::ger(int m, int n, float fAlpha, long hA, long hB, long hC, int nAoff, int nBoff, int nCoff)
{
	LONG lErr;

	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	MemoryItem* pA;
	MemoryItem* pB;
	MemoryItem* pC;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hB, &pB))
		return lErr;

	if (lErr = m_pMemCol->GetData(hC, &pC))
		return lErr;

	float* a = (float*)pA->Data();
	float* b = (float*)pB->Data();
	float* c = (float*)pC->Data();

	if (nAoff > 0)
		a += nAoff;

	if (nBoff > 0)
		b += nBoff;

	if (nCoff > 0)
		c += nCoff;

	return cublasSger(m_cublas, m, n, &fAlpha, a, 1, b, 1, c, 1);
}


template <> 
long Math<double>::gemm(bool bTransA, bool bTransB, int m, int n, int k, double fAlpha, double* a, double* b, double fBeta, double* c)
{
	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	// Note that cublas follows fortran order.
	
	int lda = (!bTransA) ? k : m;
	int ldb = (!bTransB) ? n : k;

	cublasOperation_t cuTransA = (!bTransA) ? CUBLAS_OP_N : CUBLAS_OP_T;
	cublasOperation_t cuTransB = (!bTransB) ? CUBLAS_OP_N : CUBLAS_OP_T;

	return cublasDgemm(m_cublas, cuTransB, cuTransA, n, m, k, &fAlpha, b, ldb, a, lda, &fBeta, c, n);
}

template <> 
long Math<float>::gemm(bool bTransA, bool bTransB, int m, int n, int k, float fAlpha, float* a, float *b, float fBeta, float* c)
{
	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	// Note that cublas follows fortran order.
	int lda = (!bTransA) ? k : m;
	int ldb = (!bTransB) ? n : k;
	cublasOperation_t cuTransA = (!bTransA) ? CUBLAS_OP_N : CUBLAS_OP_T;
	cublasOperation_t cuTransB = (!bTransB) ? CUBLAS_OP_N : CUBLAS_OP_T;

	return cublasSgemm(m_cublas, cuTransB, cuTransA, n, m, k, &fAlpha, b, ldb, a, lda, &fBeta, c, n);
}


template <> 
long Math<double>::gemm(bool bTransA, bool bTransB, int m, int n, int k, double fAlpha, long hA, long hB, double fBeta, long hC, int nAOff, int nBOff, int nCOff)
{
	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pB;
	MemoryItem* pC;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hB, &pB))
		return lErr;

	if (lErr = m_pMemCol->GetData(hC, &pC))
		return lErr;

	double* a = (double*)pA->Data();
	double* b = (double*)pB->Data();
	double* c = (double*)pC->Data();

	if (nAOff > 0)
		a += nAOff;

	if (nBOff > 0)
		b += nBOff;

	if (nCOff > 0)
		c += nCOff;

	return gemm(bTransA, bTransB, m, n, k, fAlpha, a, b, fBeta, c);
}

template <> 
long Math<float>::gemm(bool bTransA, bool bTransB, int m, int n, int k, float fAlpha, long hA, long hB, float fBeta, long hC, int nAOff, int nBOff, int nCOff)
{
	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pB;
	MemoryItem* pC;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hB, &pB))
		return lErr;

	if (lErr = m_pMemCol->GetData(hC, &pC))
		return lErr;

	float* a = (float*)pA->Data();
	float* b = (float*)pB->Data();
	float* c = (float*)pC->Data();

	if (nAOff > 0)
		a += nAOff;

	if (nBOff > 0)
		b += nBOff;

	if (nCOff > 0)
		c += nCOff;

	return gemm(bTransA, bTransB, m, n, k, fAlpha, a, b, fBeta, c);
}


template <> 
long Math<double>::gemm2(bool bTransA, bool bTransB, int m, int n, int k, double fAlpha, long hA, long hB, double fBeta, long hC, int lda, int ldb, int ldc)
{
	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pB;
	MemoryItem* pC;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hB, &pB))
		return lErr;

	if (lErr = m_pMemCol->GetData(hC, &pC))
		return lErr;

	double* a = (double*)pA->Data();
	double* b = (double*)pB->Data();
	double* c = (double*)pC->Data();

	cublasOperation_t cuTransA = (!bTransA) ? CUBLAS_OP_N : CUBLAS_OP_T;
	cublasOperation_t cuTransB = (!bTransB) ? CUBLAS_OP_N : CUBLAS_OP_T;

	return cublasDgemm(m_cublas, cuTransA, cuTransB, m, n, k, &fAlpha, a, lda, b, ldb, &fBeta, c, ldc);
}

template <> 
long Math<float>::gemm2(bool bTransA, bool bTransB, int m, int n, int k, float fAlpha, long hA, long hB, float fBeta, long hC, int lda, int ldb, int ldc)
{
	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pB;
	MemoryItem* pC;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hB, &pB))
		return lErr;

	if (lErr = m_pMemCol->GetData(hC, &pC))
		return lErr;

	float* a = (float*)pA->Data();
	float* b = (float*)pB->Data();
	float* c = (float*)pC->Data();

	cublasOperation_t cuTransA = (!bTransA) ? CUBLAS_OP_N : CUBLAS_OP_T;
	cublasOperation_t cuTransB = (!bTransB) ? CUBLAS_OP_N : CUBLAS_OP_T;

	return cublasSgemm(m_cublas, cuTransA, cuTransB, m, n, k, &fAlpha, a, lda, b, ldb, &fBeta, c, ldc);
}

template <>
long Math<double>::gemv(bool bTransA, int m, int n, double fAlpha, double* a, double* x, double fBeta, double* y)
{
	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	cublasOperation_t cuTransA = (!bTransA) ? CUBLAS_OP_T : CUBLAS_OP_N;

	return cublasDgemv(m_cublas, cuTransA, n, m, &fAlpha, a, n, x, 1, &fBeta, y, 1);
}

template <>
long Math<float>::gemv(bool bTransA, int m, int n, float fAlpha, float* a, float* x, float fBeta, float* y)
{
	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	cublasOperation_t cuTransA = (!bTransA) ? CUBLAS_OP_T : CUBLAS_OP_N;

	return cublasSgemv(m_cublas, cuTransA, n, m, &fAlpha, a, n, x, 1, &fBeta, y, 1);
}

template <>
long Math<double>::gemv(bool bTransA, int m, int n, double fAlpha, long hA, long hX, double fBeta, long hY, int nAOffset, int nXOffset, int nYOffset)
{
	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pX;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	double* a = (double*)pA->Data();
	double* x = (double*)pX->Data();
	double* y = (double*)pY->Data();

	if (nAOffset > 0)
		a += nAOffset;

	if (nXOffset > 0)
		x += nXOffset;

	if (nYOffset > 0)
		y += nYOffset;

	return gemv(bTransA, m, n, fAlpha, a, x, fBeta, y);
}

template <>
long Math<float>::gemv(bool bTransA, int m, int n, float fAlpha, long hA, long hX, float fBeta, long hY, int nAOffset, int nXOffset, int nYOffset)
{
	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pX;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	float* a = (float*)pA->Data();
	float* x = (float*)pX->Data();
	float* y = (float*)pY->Data();

	if (nAOffset > 0)
		a += nAOffset;

	if (nXOffset > 0)
		x += nXOffset;

	if (nYOffset > 0)
		y += nYOffset;

	return gemv(bTransA, m, n, fAlpha, a, x, fBeta, y);
}


template <>
long Math<double>::axpy(int n, double fAlpha, long hX, long hY, int nXOff, int nYOff)
{
	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	LONG lErr;
	MemoryItem* pX;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	double* x = (double*)pX->Data();
	double* y = (double*)pY->Data();

	if (nXOff > 0)
		x += nXOff;

	if (nYOff > 0)
		y += nYOff;

	return cublasDaxpy(m_cublas, n, &fAlpha, x, 1, y, 1);
}

template <>
long Math<float>::axpy(int n, float fAlpha, long hX, long hY, int nXOff, int nYOff)
{
	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	LONG lErr;
	MemoryItem* pX;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	float* x = (float*)pX->Data();
	float* y = (float*)pY->Data();

	if (nXOff > 0)
		x += nXOff;

	if (nYOff > 0)
		y += nYOff;

	return cublasSaxpy(m_cublas, n, &fAlpha, x, 1, y, 1);
}

template <>
long Math<double>::axpby(int n, double fAlpha, long hX, double fBeta, long hY)
{
	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	LONG lErr;
	MemoryItem* pX;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	if (lErr = cublasDscal(m_cublas, n, &fBeta, (double*)pY->Data(), 1))
		return lErr;

	return cublasDaxpy(m_cublas, n, &fAlpha, (double*)pX->Data(), 1, (double*)pY->Data(), 1);
}

template <>
long Math<float>::axpby(int n, float fAlpha, long hX, float fBeta, long hY)
{
	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	LONG lErr;
	MemoryItem* pX;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	if (lErr = cublasSscal(m_cublas, n, &fBeta, (float*)pY->Data(), 1))
		return lErr;

	return cublasSaxpy(m_cublas, n, &fAlpha, (float*)pX->Data(), 1, (float*)pY->Data(), 1);
}


template <>
long Math<double>::scal(int n, double fAlpha, long hX, int nXOff, long hStream)
{
	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	LONG lErr;
	cudaStream_t initial_stream = NULL;

	if (hStream != 0)
	{
		cudaStream_t stream = m_pMem->GetStream(hStream);

		if (lErr = cublasGetStream(m_cublas, &initial_stream))
			return lErr;

		if (lErr = cublasSetStream(m_cublas, stream))
			return lErr;
	}

	MemoryItem* pX;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	double* x = (double*)pX->Data();
	if (nXOff > 0)
		x += nXOff;

	lErr = cublasDscal(m_cublas, n, &fAlpha, x, 1);

	if (initial_stream != NULL)
		cublasSetStream(m_cublas, initial_stream);

	return lErr;
}

template <>
long Math<float>::scal(int n, float fAlpha, long hX, int nXOff, long hStream)
{
	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	LONG lErr;
	cudaStream_t initial_stream = NULL;

	if (hStream != 0)
	{
		cudaStream_t stream = m_pMem->GetStream(hStream);

		if (lErr = cublasGetStream(m_cublas, &initial_stream))
			return lErr;

		if (lErr = cublasSetStream(m_cublas, stream))
			return lErr;
	}

	MemoryItem* pX;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	float* x = (float*)pX->Data();
	if (nXOff > 0)
		x += nXOff;

	lErr = cublasSscal(m_cublas, n, &fAlpha, x, 1);

	if (initial_stream != NULL)
		cublasSetStream(m_cublas, initial_stream);

	return lErr;
}


template <>
long Math<double>::dot(int n, long hX, long hY, double* pOut, int nXOff, int nYOff)
{
	if (pOut == NULL)
		return ERROR_PARAM_NULL;

	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	LONG lErr;
	MemoryItem* pX;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	double* x = (double*)pX->Data();
	double* y = (double*)pY->Data();

	if (nXOff > 0)
		x += nXOff;

	if (nYOff > 0)
		y += nYOff;

	return cublasDdot(m_cublas, n, x, 1, y, 1, (double*)pOut);
}

template <>
long Math<float>::dot(int n, long hX, long hY, float* pOut, int nXOff, int nYOff)
{
	if (pOut == NULL)
		return ERROR_PARAM_NULL;

	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	LONG lErr;
	MemoryItem* pX;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	float* x = (float*)pX->Data();
	float* y = (float*)pY->Data();

	if (nXOff > 0)
		x += nXOff;

	if (nYOff > 0)
		y += nYOff;

	return cublasSdot(m_cublas, n, x, 1, y, 1, (float*)pOut);
}

template <>
long Math<double>::asum(int n, long hX, double* pOut, int nXOff)
{
	if (pOut == NULL)
		return ERROR_PARAM_NULL;

	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	LONG lErr;
	MemoryItem* pX;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	double* x = (double*)pX->Data();

	if (nXOff > 0)
		x += nXOff;

	return cublasDasum(m_cublas, n, x, 1, (double*)pOut);
}

template <>
long Math<float>::asum(int n, long hX, float* pOut, int nXOff)
{
	if (pOut == NULL)
		return ERROR_PARAM_NULL;

	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	LONG lErr;
	MemoryItem* pX;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	float* x = (float*)pX->Data();

	if (nXOff > 0)
		x += nXOff;

	return cublasSasum(m_cublas, n, x, 1, (float*)pOut);
}

template <>
long Math<double>::asum(int n, double* x, double* pOut)
{
	return cublasDasum(m_cublas, n, x, 1, pOut);
}

template <>
long Math<float>::asum(int n, float* x, float* pOut)
{
	return cublasSasum(m_cublas, n, x, 1, pOut);
}


template <>
long Math<double>::scale(int n, double fAlpha, long hX, long hY, int nXOff, int nYOff)
{
	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	LONG lErr;
	MemoryItem* pX;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	double* x = (double*)pX->Data();
	double* y = (double*)pY->Data();

	if (nXOff > 0)
		x += nXOff;

	if (nYOff > 0)
		y += nYOff;

	if (lErr = cublasDcopy(m_cublas, n, x, 1, y, 1))
		return lErr;

	return cublasDscal(m_cublas, n, &fAlpha, y, 1);
}


template <>
long Math<float>::scale(int n, float fAlpha, long hX, long hY, int nXOff, int nYOff)
{
	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	LONG lErr;
	MemoryItem* pX;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	float* x = (float*)pX->Data();
	float* y = (float*)pY->Data();

	if (nXOff > 0)
		x += nXOff;

	if (nYOff > 0)
		y += nYOff;

	if (lErr = cublasScopy(m_cublas, n, x, 1, y, 1))
		return lErr;

	return cublasSscal(m_cublas, n, &fAlpha, y, 1);
}

template <typename T>
__global__ void add_scalar_kernel(const int n, const T alpha, T* y)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		y[i] += alpha;
	}
}

template <>
long Math<double>::add_scalar(int n, double fAlpha, long hY, int nYOff)
{
	LONG lErr;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	double* y = (double*)pY->Data();
	if (nYOff > 0)
		y += nYOff;

	add_scalar_kernel<double><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, fAlpha, y);

	return cudaGetLastError();
}

template <>
long Math<float>::add_scalar(int n, float fAlpha, long hY, int nYOff)
{
	LONG lErr;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	float* y = (float*)pY->Data();
	if (nYOff > 0)
		y += nYOff;

	add_scalar_kernel<float><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, fAlpha, y);

	return cudaGetLastError();
}


template <typename T>
__global__ void add_kernel(const int n, T* a, T* b, T* y, T fAlpha)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		y[i] = a[i] + (b[i] * fAlpha);
	}
}

template <>
long Math<double>::add(int n, long hA, long hB, long hY, double dfAlpha)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pB;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hB, &pB))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	add_kernel<double><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, (double*)pA->Data(), (double*)pB->Data(), (double*)pY->Data(), dfAlpha);

	return cudaGetLastError();
}

template <>
long Math<float>::add(int n, long hA, long hB, long hY, float fAlpha)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pB;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hB, &pB))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	add_kernel<float><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, (float*)pA->Data(), (float*)pB->Data(), (float*)pY->Data(), fAlpha);

	return cudaGetLastError();
}

template<>
long Math<float>::add(int n, float* a, float* b, float* c)
{
	add_kernel<float><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, a, b, c, 1.0);

	return cudaGetLastError();
}


template<>
long Math<double>::add(int n, double* a, double* b, double* c)
{
	add_kernel<double><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, a, b, c, 1.0);

	return cudaGetLastError();
}


template <typename T>
__global__ void add2_kernel(const int n, T* a, T* b, T* y, T fAlphaA, T fAlphaB)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		y[i] = (a[i] * fAlphaA) + (b[i] * fAlphaB);
	}
}

template <class T>
long Math<T>::add2(int n, long hA, long hB, long hY, T dfAlphaA, T dfAlphaB, int nAOff, int nBOff, int nYOff)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pB;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hB, &pB))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	T* a = (T*)pA->Data();
	T* b = (T*)pB->Data();
	T* y = (T*)pY->Data();

	if (nAOff > 0)
		a += nAOff;

	if (nBOff > 0)
		b += nBOff;

	if (nYOff > 0)
		y += nYOff;

	add2_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, a, b, y, dfAlphaA, dfAlphaB);

	return cudaGetLastError();
}

template long Math<double>::add2(int n, long hA, long hB, long hY, double dfAlphaA, double dfAlphaB, int nAOff, int nBOff, int nYOff);
template long Math<float>::add2(int n, long hA, long hB, long hY, float dfAlphaA, float dfAlphaB, int nAOff, int nBOff, int nYOff);


template <typename T>
__global__ void compare_signs_kernel(const int n, T* a, T* b, T* y)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		if (a[i] < T(0.0))
		{
			if (b[i] < T(0.0))
				y[i] = T(1.0);
			else
				y[i] = T(0.0);
		}
		else if (a[i] > T(0.0))
		{
			if (b[i] > T(0.0))
				y[i] = T(1.0);
			else
				y[i] = T(0.0);
		}
		else
		{
			if (b[i] == T(0.0))
				y[i] = T(1.0);
			else
				y[i] = T(0.0);
		}
	}
}

template <>
long Math<double>::compare_signs(int n, long hA, long hB, long hY)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pB;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hB, &pB))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	compare_signs_kernel<double><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, (double*)pA->Data(), (double*)pB->Data(), (double*)pY->Data());

	return cudaGetLastError();
}

template <>
long Math<float>::compare_signs(int n, long hA, long hB, long hY)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pB;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hB, &pB))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	compare_signs_kernel<float><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, (float*)pA->Data(), (float*)pB->Data(), (float*)pY->Data());

	return cudaGetLastError();
}


template <class T>
long Math<T>::maxval(int n, long hA, T* pOut, int nAOff)
{
	LONG lErr;
	MemoryItem* pA;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	T* a = (T*)pA->Data();

	if (nAOff > 0)
		a += nAOff;

	thrust::device_ptr<T> d_ptr = thrust::device_pointer_cast(a);
	*pOut = *(thrust::max_element(d_ptr, d_ptr + n));

	return cudaGetLastError();
}

template long Math<double>::maxval(int n, long hA, double* pOut, int nAOff);
template long Math<float>::maxval(int n, long hA, float* pOut, int nAOff);


template <class T>
long Math<T>::minval(int n, long hA, T* pOut, int nAOff)
{
	LONG lErr;
	MemoryItem* pA;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	T* a = (T*)pA->Data();

	if (nAOff > 0)
		a += nAOff;

	thrust::device_ptr<T> d_ptr = thrust::device_pointer_cast(a);
	*pOut = *(thrust::min_element(d_ptr, d_ptr + n));

	return cudaGetLastError();
}

template long Math<double>::minval(int n, long hA, double* pOut, int nAOff);
template long Math<float>::minval(int n, long hA, float* pOut, int nAOff);


template <class T>
__global__ void minmax_kernel(const T* d_data, T* d_min, T* d_max, const size_t n, const T MIN, const T MAX)
{
	// Load a segment of the input vector into shared memory
	__shared__ T sharedMin[MAX_SH_MEM];
	__shared__ T sharedMax[MAX_SH_MEM];
	int tid = threadIdx.x;
	int gid = (blockDim.x * blockIdx.x) + tid;

	sharedMin[tid] = MIN;
	sharedMax[tid] = MAX;

	while (gid < n)
	{
		sharedMin[tid] = min(sharedMin[tid], d_data[gid]);
		sharedMax[tid] = max(sharedMax[tid], d_data[gid]);
		gid += gridDim.x * blockDim.x;
	}
	__syncthreads();

	gid = (blockDim.x * blockIdx.x) + tid;
	for (unsigned int s = blockDim.x / 2; s > 0; s >>= 1)
	{
		if (tid < s && gid < n)
		{
			sharedMin[tid] = min(sharedMin[tid], sharedMin[tid + s]);
			sharedMax[tid] = max(sharedMax[tid], sharedMax[tid + s]);
		}

		__syncthreads();
	}

	if (tid == 0)
	{
		math_atomic_min(d_min, sharedMin[0]);
		math_atomic_max(d_max, sharedMax[0]);
	}
}

template <class T>
long Math<T>::minmaxval(int n, long hA, long hWork1, long hWork2, T* pMin, T* pMax, int nAOff)
{
	int nBlocks = DIVUP(n, MAX_SH_MEM);
	if (nBlocks > NUM_BLOCKS_MAX)
		nBlocks = NUM_BLOCKS_MAX;

	int nSize = nBlocks * MAX_SH_MEM;

	if (hA == 0 || hWork1 == 0 || hWork2 == 0)
	{
		*pMin = (T)nSize;
		*pMax = (T)nSize;
		return 0;
	}

	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pW1;
	MemoryItem* pW2;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hWork1, &pW1))
		return lErr;

	if (lErr = m_pMemCol->GetData(hWork2, &pW2))
		return lErr;

	T* a = (T*)pA->Data();
	T* w1 = (T*)pW1->Data();
	T* w2 = (T*)pW2->Data();

	if (nAOff > 0)
		a += nAOff;

	T fMin = (sizeof(T) == sizeof(float)) ? FLT_MAX : DBL_MAX;
	T fMax = (sizeof(T) == sizeof(float)) ? -FLT_MAX : -DBL_MAX;

	int nRemaining = n;
	int nCount = 0;
	T fMinFinal = fMin;
	T fMaxFinal = fMax;
	T fMin1;
	T fMax1;

	if (nSize > n)
		nSize = n;

	if (n > 1)
	{
		while (nCount < n)
		{
			if (lErr = cudaMemset(w1, 0, nSize))
				return lErr;

			if (lErr = cudaMemset(w2, 0, nSize))
				return lErr;

			minmax_kernel<T> << <nBlocks, MAX_SH_MEM >> > (a, w1, w2, nSize, fMin, fMax);

			if (lErr = cudaGetLastError())
				return lErr;

			if (lErr = cudaMemcpy(&fMin1, w1, sizeof(T), cudaMemcpyDeviceToHost))
				return lErr;

			if (lErr = cudaMemcpy(&fMax1, w2, sizeof(T), cudaMemcpyDeviceToHost))
				return lErr;

			fMinFinal = min(fMinFinal, fMin1);
			fMaxFinal = max(fMaxFinal, fMax1);

			a += nSize;
			nCount += nSize;
			nRemaining -= nSize;

			if (nRemaining < nSize)
				nSize = nRemaining;
		}
	}
	else
	{
		if (lErr = cudaMemcpy(&fMinFinal, a, sizeof(T), cudaMemcpyDeviceToHost))
			return lErr;

		if (lErr = cudaMemcpy(&fMaxFinal, a, sizeof(T), cudaMemcpyDeviceToHost))
			return lErr;
	}

	*pMin = fMinFinal;
	*pMax = fMaxFinal;

	return cudaGetLastError();
}

template long Math<double>::minmaxval(int n, long hA, long hWork1, long hWork2, double* pMin, double* pMax, int nAOff);
template long Math<float>::minmaxval(int n, long hA, long hWork1, long hWork2, float* pMin, float* pMax, int nAOff);


template <class T>
__global__ void naninf_kernel(const T* d_data, T* d_nan, T* d_inf, const size_t n)
{
	// Load a segment of the input vector into shared memory
	__shared__ T sharedNan[MAX_SH_MEM];
	__shared__ T sharedInf[MAX_SH_MEM];
	int tid = threadIdx.x;
	int gid = (blockDim.x * blockIdx.x) + tid;

	sharedNan[tid] = 0;
	sharedInf[tid] = 0;

	while (gid < n)
	{
		sharedNan[tid] = isnan(d_data[gid]);
		sharedInf[tid] = isinf(d_data[gid]);
		gid += gridDim.x * blockDim.x;
	}
	__syncthreads();

	gid = (blockDim.x * blockIdx.x) + tid;
	for (unsigned int s = blockDim.x / 2; s > 0; s >>= 1)
	{
		if (tid < s && gid < n)
		{
			sharedNan[tid] = sharedNan[tid] + sharedNan[tid + s];
			sharedInf[tid] = sharedInf[tid] + sharedInf[tid + s];
		}

		__syncthreads();
	}

	if (tid == 0)
	{
		math_atomic_add(sharedNan[0], d_nan);
		math_atomic_add(sharedInf[0], d_inf);
	}
}

template <class T>
long Math<T>::naninfval(int n, long hA, long hWork1, long hWork2, T* pNan, T* pInf, int nAOff)
{
	int nBlocks = DIVUP(n, MAX_SH_MEM);
	if (nBlocks > NUM_BLOCKS_MAX)
		nBlocks = NUM_BLOCKS_MAX;

	int nSize = nBlocks * MAX_SH_MEM;

	if (hA == 0 || hWork1 == 0 || hWork2 == 0)
	{
		*pNan = 0;
		*pInf = 0;
		return 0;
	}

	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pW1;
	MemoryItem* pW2;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hWork1, &pW1))
		return lErr;

	if (lErr = m_pMemCol->GetData(hWork2, &pW2))
		return lErr;

	T* a = (T*)pA->Data();
	T* w1 = (T*)pW1->Data();
	T* w2 = (T*)pW2->Data();

	if (nAOff > 0)
		a += nAOff;

	int nRemaining = n;
	int nCount = 0;
	T fNanFinal = 0;
	T fInfFinal = 0;
	T fNan1;
	T fInf1;

	if (nSize > n)
		nSize = n;

	if (n > 1)
	{
		while (nCount < n)
		{
			if (lErr = cudaMemset(w1, 0, nSize))
				return lErr;

			if (lErr = cudaMemset(w2, 0, nSize))
				return lErr;

			naninf_kernel<T> << <nBlocks, MAX_SH_MEM >> > (a, w1, w2, nSize);

			if (lErr = cudaGetLastError())
				return lErr;

			if (lErr = cudaMemcpy(&fNan1, w1, sizeof(T), cudaMemcpyDeviceToHost))
				return lErr;

			if (lErr = cudaMemcpy(&fInf1, w2, sizeof(T), cudaMemcpyDeviceToHost))
				return lErr;

			fNanFinal += fNan1;
			fInfFinal += fInf1;

			a += nSize;
			nCount += nSize;
			nRemaining -= nSize;

			if (nRemaining < nSize)
				nSize = nRemaining;
		}
	}
	else if (n == 1)
	{
		T fVal;
		if (lErr = cudaMemcpy(&fVal, a, sizeof(T), cudaMemcpyDeviceToHost))
			return lErr;

		if (isnan(fVal))
			fNanFinal = 1;

		if (isinf(fVal))
			fInfFinal = 1;
	}

	*pNan = fNanFinal;
	*pInf = fInfFinal;

	return cudaGetLastError();
}

template long Math<double>::naninfval(int n, long hA, long hWork1, long hWork2, double* pNan, double* pInf, int nAOff);
template long Math<float>::naninfval(int n, long hA, long hWork1, long hWork2, float* pNan, float* pInf, int nAOff);



template <typename T>
__global__ void width_kernel(const int n, const T* mean, const T* minv, const T* maxv, T fAlpha, T* width)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		width[i] = max(maxv[i] - mean[i], mean[i] - minv[i]) + fAlpha;
	}
}

template <class T>
long Math<T>::width(int n, long hMean, long hMin, long hMax, T fAlpha, long hWidth)
{
	LONG lErr;
	MemoryItem* pMean;
	MemoryItem* pMin;
	MemoryItem* pMax;
	MemoryItem* pWidth;

	if (lErr = m_pMemCol->GetData(hMean, &pMean))
		return lErr;

	if (lErr = m_pMemCol->GetData(hMin, &pMin))
		return lErr;

	if (lErr = m_pMemCol->GetData(hMax, &pMax))
		return lErr;

	if (lErr = m_pMemCol->GetData(hWidth, &pWidth))
		return lErr;

	width_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, (T*)pMean->Data(), (T*)pMin->Data(), (T*)pMax->Data(), fAlpha, (T*)pWidth->Data());

	return cudaGetLastError();	
}

template long Math<double>::width(int n, long hMean, long hMax, long hMin, double fAlpha, long hWidth);
template long Math<float>::width(int n, long hMean, long hMax, long hMin, float fAlpha, long hWidth);


template <typename T>
__global__ void contains_point_kernel(const int n, const T* mean, const T* width, const T* x, T* out)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		out[i] = (((mean[i] - width[i]) > x[i]) || ((mean[i] + width[i]) < x[i])) ? 1 : 0;
	}
}

template <class T>
long Math<T>::contains_point(int n, long hMean, long hWidth, long hX, long hWork, T* pOut, int nXOff)
{
	LONG lErr;
	MemoryItem* pMean;
	MemoryItem* pWidth;
	MemoryItem* pWork;
	MemoryItem* pX;

	if (lErr = m_pMemCol->GetData(hMean, &pMean))
		return lErr;

	if (lErr = m_pMemCol->GetData(hWidth, &pWidth))
		return lErr;

	if (lErr = m_pMemCol->GetData(hWork, &pWork))
		return lErr;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	T* mean = (T*)pMean->Data();
	T* wid = (T*)pWidth->Data();
	T* x = (T*)pX->Data();
	T* out = (T*)pWork->Data();

	if (nXOff > 0)
		x += nXOff;

	contains_point_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, mean, wid, x, out);

	if (lErr = cudaGetLastError())
		return lErr;

	if (lErr = asum(n, hWork, pOut))
		return lErr;

	if (*pOut == T(0))
		*pOut = T(1);
	else
		*pOut = T(0);

	return 0;
}

template long Math<double>::contains_point(int n, long hMean, long hWidth, long hX, long hWork, double* pOut, int nXOff);
template long Math<float>::contains_point(int n, long hMean, long hWidth, long hX, long hWork, float* pOut, int nXOff);



template <typename T>
__global__ void denan_kernel(const int n, T* x, const T fReplacement)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		x[i] = (isnan(x[i]) || isinf(x[i])) ? fReplacement : x[i];
	}
}

template <class T>
long Math<T>::denan(int n, long hX, T fReplacement)
{
	LONG lErr;
	MemoryItem* pX;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	T* x = (T*)pX->Data();

	denan_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, x, fReplacement);

	return cudaGetLastError();
}

template long Math<double>::denan(int n, long hX, double dfReplacement);
template long Math<float>::denan(int n, long hX, float fReplacement);


template <typename T>
__global__ void sub_kernel(const int n, T* a, T* b, T* y)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		y[i] = a[i] - b[i];
	}
}

template <>
long Math<double>::sub(int n, long hA, long hB, long hY, int nAOff, int nBOff, int nYOff)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pB;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hB, &pB))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	double* a = (double*)pA->Data();
	double* b = (double*)pB->Data();
	double* y = (double*)pY->Data();

	if (nAOff > 0)
		a += nAOff;

	if (nBOff > 0)
		b += nBOff;

	if (nYOff > 0)
		y += nYOff;

	sub_kernel<double><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, a, b, y);

	return cudaGetLastError();
}

template <>
long Math<float>::sub(int n, long hA, long hB, long hY, int nAOff, int nBOff, int nYOff)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pB;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hB, &pB))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	float* a = (float*)pA->Data();
	float* b = (float*)pB->Data();
	float* y = (float*)pY->Data();

	if (nAOff > 0)
		a += nAOff;

	if (nBOff > 0)
		b += nBOff;

	if (nYOff > 0)
		y += nYOff;

	sub_kernel<float><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, a, b, y);

	return cudaGetLastError();
}



template <typename T>
__global__ void sub_and_dot_kernel(const int nN, int len, T* a, T* b, T* y)
{
	int i = blockIdx.x * blockDim.x + threadIdx.x;

	if (i < nN)
	{
		T tmp = a[i] - b[i%len];
		y[i] = tmp*tmp;
	}
}

template <class T>
long Math<T>::sub_and_dot(int n, int nN, int nLen, long hA, long hB, long hY, int nAOff, int nBOff, int nYOff)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pB;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hB, &pB))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	T* a = (T*)pA->Data();
	T* b = (T*)pB->Data();
	T* y = (T*)pY->Data();

	if (nAOff > 0)
		a += nAOff;

	if (nBOff > 0)
		b += nBOff;

	if (nYOff > 0)
		y += nYOff;

	sub_and_dot_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(nN, nLen, a, b, y);

	return cudaGetLastError();
}

template long Math<float>::sub_and_dot(int n, int nN, int nLen, long hA, long hB, long hY, int nAOff, int nBOff, int nYOff);
template long Math<double>::sub_and_dot(int n, int nN, int nLen, long hA, long hB, long hY, int nAOff, int nBOff, int nYOff);


template <typename T>
__global__ void mul_scalar_kernel(const int n, const T alpha, T* y)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		y[i] *= alpha;
	}
}

template <>
long Math<double>::mul_scalar(int n, double fAlpha, long hY)
{
	LONG lErr;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	mul_scalar_kernel<double><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, fAlpha, (double*)pY->Data());

	return cudaGetLastError();
}

template <>
long Math<float>::mul_scalar(int n, float fAlpha, long hY)
{
	LONG lErr;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	mul_scalar_kernel<float><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, fAlpha, (float*)pY->Data());

	return cudaGetLastError();
}


template <typename T>
__global__ void mul_kernel(const int n, T* a, T* b, T* y)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		y[i] = a[i] * b[i];
	}
}

template <>
long Math<double>::mul(int n, long hA, long hB, long hY, int nAOff, int nBOff, int nYOff)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pB;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hB, &pB))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	double* a = (double*)pA->Data();
	double* b = (double*)pB->Data();
	double* y = (double*)pY->Data();

	if (nAOff > 0)
		a += nAOff;

	if (nBOff > 0)
		b += nBOff;

	if (nYOff > 0)
		y += nYOff;

	mul_kernel<double><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, a, b, y);

	return cudaGetLastError();
}

template <>
long Math<float>::mul(int n, long hA, long hB, long hY, int nAOff, int nBOff, int nYOff)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pB;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hB, &pB))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	float* a = (float*)pA->Data();
	float* b = (float*)pB->Data();
	float* y = (float*)pY->Data();

	if (nAOff > 0)
		a += nAOff;

	if (nBOff > 0)
		b += nBOff;

	if (nYOff > 0)
		y += nYOff;

	mul_kernel<float><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, a, b, y);

	return cudaGetLastError();
}


template <typename T>
__global__ void div_kernel(const int n, T* a, T* b, T* y)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		y[i] = a[i] / b[i];
	}
}

template <>
long Math<double>::div(int n, long hA, long hB, long hY)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pB;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hB, &pB))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	div_kernel<double><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, (double*)pA->Data(), (double*)pB->Data(), (double*)pY->Data());

	return cudaGetLastError();
}

template <>
long Math<float>::div(int n, long hA, long hB, long hY)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pB;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hB, &pB))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	div_kernel<float><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, (float*)pA->Data(), (float*)pB->Data(), (float*)pY->Data());

	return cudaGetLastError();
}


template <typename T>
__global__ void abs_kernel(const int n, T* a, T* y)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		y[i] = abs(a[i]);
	}
}

template <>
long Math<double>::abs(int n, long hA, long hY)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	abs_kernel<double><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, (double*)pA->Data(), (double*)pY->Data());

	return cudaGetLastError();
}

template <>
long Math<float>::abs(int n, long hA, long hY)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	abs_kernel<float><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, (float*)pA->Data(), (float*)pY->Data());

	return cudaGetLastError();
}


template <typename T>
__global__ void exp_kernel(const int n, T* a, T* y, T fBeta)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		y[i] = exp(fBeta * a[i]);
	}
}

template <>
long Math<double>::exp(int n, long hA, long hY, int nAOff, int nYOff, double dfBeta)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	double* a = (double*)pA->Data();
	double* y = (double*)pY->Data();

	if (nAOff > 0)
		a += nAOff;

	if (nYOff > 0)
		y += nYOff;

	exp_kernel<double><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, a, y, dfBeta);

	return cudaGetLastError();
}

template <>
long Math<float>::exp(int n, long hA, long hY, int nAOff, int nYOff, float fBeta)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	float* a = (float*)pA->Data();
	float* y = (float*)pY->Data();

	if (nAOff > 0)
		a += nAOff;

	if (nYOff > 0)
		y += nYOff;

	exp_kernel<float><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, a, y, fBeta);

	return cudaGetLastError();
}


template <typename T>
__global__ void log_kernel(const int n, T* a, T* y, T fBeta)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		y[i] = log(fBeta * a[i]);
	}
}

template <typename T>
long Math<T>::log(int n, long hA, long hY, T fBeta)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	log_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, (T*)pA->Data(), (T*)pY->Data(), fBeta);

	return cudaGetLastError();
}

template long Math<double>::log(int n, long hA, long hY, double dfBeta);
template long Math<float>::log(int n, long hA, long hY, float dfBeta);



template <typename T>
__global__ void powx_kernel(const int n, T* a, T fAlpha, T* y)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		y[i] = pow(a[i], fAlpha);
	}
}

template <>
long Math<double>::powx(int n, long hA, double fAlpha, long hY)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	powx_kernel<double><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, (double*)pA->Data(), fAlpha, (double*)pY->Data());

	return cudaGetLastError();
}

template <>
long Math<float>::powx(int n, long hA, float fAlpha, long hY)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	powx_kernel<float><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, (float*)pA->Data(), fAlpha, (float*)pY->Data());

	return cudaGetLastError();
}



template <typename T>
__global__ void sign_kernel(const int n, T* x, T* y)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		y[i] = (T(0) < x[i]) - (x[i] < T(0));
	}
}

template <typename T>
long Math<T>::sign(int n, long hX, long hY, int nXOff, int nYOff)
{
	LONG lErr;
	MemoryItem* pX;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	T* x = (T*)pX->Data();
	T* y = (T*)pY->Data();

	if (nXOff > 0)
		x += nXOff;

	if (nYOff > 0)
		y += nYOff;

	sign_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, x, y);

	return cudaGetLastError();
}

template long Math<double>::sign(int n, long hA, long hY, int nXOff, int nYOff);
template long Math<float>::sign(int n, long hA, long hY, int nXOff, int nYOff);



template <typename T>
__global__ void sqrt_kernel(const int n, T* x, T* y)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		y[i] = sqrt(x[i]);
	}
}

template <typename T>
long Math<T>::sqrt(int n, long hX, long hY)
{
	LONG lErr;
	MemoryItem* pX;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	sqrt_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, (T*)pX->Data(), (T*)pY->Data());

	return cudaGetLastError();
}

template long Math<double>::sqrt(int n, long hA, long hY);
template long Math<float>::sqrt(int n, long hA, long hY);


template <class T>
long Math<T>::sumsq(int n, long hW, long hA, int nAOff, T* pOut)
{
	LONG lErr;

	if (lErr = mul(n, hA, hA, hW, nAOff, nAOff))
		return lErr;

	return asum(n, hW, pOut);
}

template long Math<double>::sumsq(int n, long hW, long hA, int nAOff, double* pOut);
template long Math<float>::sumsq(int n, long hW, long hA, int nAOff, float* pOut);


template <class T>
long Math<T>::sumsqdiff(int n, long hW, long hA, long hB, int nAOff, int nBOff, T* pOut)
{
	LONG lErr;

	if (lErr = sub(n, hA, hB, hW, nAOff, nBOff))
		return lErr;

	if (lErr = mul(n, hW, hW, hW))
		return lErr;

	return asum(n, hW, pOut);
}

template long Math<double>::sumsqdiff(int n, long hW, long hA, long hB, int nAOff, int nBOff, double* pOut);
template long Math<float>::sumsqdiff(int n, long hW, long hA, long hB, int nAOff, int nBOff, float* pOut);


template <class T>
long Math<T>::sumsqdiff(int n, T* w, T* x, T* y, T* pOut, cudaStream_t stream)
{
	LONG lErr;

	if (stream != NULL)
		sub_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS, 0, stream>>>(n, x, y, w);
	else
		sub_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, x, y, w);

	if (lErr = cudaGetLastError())
		return lErr;

	if (stream != NULL)
		mul_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS, 0, stream>>>(n, w, w, w);
	else
		mul_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, w, w, w);

	if (lErr = cudaGetLastError())
		return lErr;

	return asum(n, w, pOut);
}

template long Math<double>::sumsqdiff(int n, double* w, double* x, double* y, double* pOut, cudaStream_t stream);
template long Math<float>::sumsqdiff(int n, float* w, float* x, float* y, float* pOut, cudaStream_t stream);


template <typename T>
__global__ void reciprocol_kernel(const int n, T* x, T* y)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		y[i] = (x[i] == 0) ? 0 : (1.0 / x[i]);
	}
}

template <typename T>
long Math<T>::reciprocol(int n, long hX, long hY)
{
	LONG lErr;
	MemoryItem* pX;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	reciprocol_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, (T*)pX->Data(), (T*)pY->Data());

	return cudaGetLastError();
}

template long Math<double>::reciprocol(int n, long hA, long hY);
template long Math<float>::reciprocol(int n, long hA, long hY);



template <typename T>
__global__ void student_kernel(const int n, T* x, T* y)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		T fVal = 1.0 + x[i];
		y[i] = (fVal == 0) ? 0 : 1.0 / fVal;
	}
}

template <typename T>
long Math<T>::student(int n, long hX, long hY)
{
	LONG lErr;
	MemoryItem* pX;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	student_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, (T*)pX->Data(), (T*)pY->Data());

	return cudaGetLastError();
}

template long Math<double>::student(int n, long hA, long hY);
template long Math<float>::student(int n, long hA, long hY);



template <typename T>
__global__ void logistic1_kernel(const int n, T* x, T* y)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		y[i] = (1 + tanh(x[i] / 2)) / 2;
	}
}

template <typename T>
long Math<T>::logistic1(int n, long hX, long hY)
{
	LONG lErr;
	MemoryItem* pX;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	logistic1_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, (T*)pX->Data(), (T*)pY->Data());

	return cudaGetLastError();
}

template long Math<double>::logistic1(int n, long hA, long hY);
template long Math<float>::logistic1(int n, long hA, long hY);



template <typename T>
__global__ void logistic2_kernel(const int n, T* x, T* y)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		y[i] = 1 / (1 + exp(-x[i]));
	}
}

template <typename T>
long Math<T>::logistic2(int n, long hX, long hY)
{
	LONG lErr;
	MemoryItem* pX;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	logistic2_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, (T*)pX->Data(), (T*)pY->Data());

	return cudaGetLastError();
}

template long Math<double>::logistic2(int n, long hA, long hY);
template long Math<float>::logistic2(int n, long hA, long hY);


template <typename T>
__global__ void channel_max_kernel(const int num, const int channels, const int spatial_dim, const T* x, T* y)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<num * spatial_dim; i += blockDim.x * gridDim.x)
	{
		int n = i / spatial_dim;
		int s = i % spatial_dim;
		T val = -FLT_MAX;

		for (int c=0; c<channels; c++)
		{
			val = max(x[(n * channels + c) * spatial_dim + s], val);
		}

		y[i] = val;
	}
}

template <typename T> 
long Math<T>::channel_max(int n, int nOutNum, int nChannels, int nInNum, long hX, long hY)
{
	LONG lErr;
	MemoryItem* pX;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	channel_max_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(nOutNum, nChannels, nInNum, (T*)pX->Data(), (T*)pY->Data());

	return cudaGetLastError();
}

template long Math<double>::channel_max(int n, int nOutNum, int nChannels, int nInNum, long hX, long hY);
template long Math<float>::channel_max(int n, int nOutNum, int nChannels, int nInNum, long hX, long hY);



template <typename T>
__global__ void channel_sub_kernel(const int count, const int num, const int channels, const int spatial_dim, const T* x, T* y)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<count; i += blockDim.x * gridDim.x)
	{
		int n = i / channels / spatial_dim;
		int s = i % spatial_dim;
		y[i] -= x[n * spatial_dim + s];
	}
}

template <typename T> 
long Math<T>::channel_sub(int n, int nOutNum, int nChannels, int nInNum, long hX, long hY)
{
	LONG lErr;
	MemoryItem* pX;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	channel_sub_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, nOutNum, nChannels, nInNum, (T*)pX->Data(), (T*)pY->Data());

	return cudaGetLastError();
}

template long Math<double>::channel_sub(int n, int nOutNum, int nChannels, int nInNum, long hX, long hY);
template long Math<float>::channel_sub(int n, int nOutNum, int nChannels, int nInNum, long hX, long hY);


template <typename T>
__global__ void channel_sum_kernel(const int num, const int channels, const int spatial_dim, const T* x, T* y)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<num * spatial_dim; i += blockDim.x * gridDim.x)
	{
		int n = i / spatial_dim;
		int s = i % spatial_dim;
		T val = 0;

		for (int c=0; c<channels; c++)
		{
			val += x[(n * channels + c) * spatial_dim + s];
		}

		y[i] = val;
	}
}

template <typename T> 
long Math<T>::channel_sum(int n, int nOutNum, int nChannels, int nInNum, long hX, long hY)
{
	LONG lErr;
	MemoryItem* pX;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	channel_sum_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(nOutNum, nChannels, nInNum, (T*)pX->Data(), (T*)pY->Data());

	return cudaGetLastError();
}

template long Math<double>::channel_sum(int n, int nOutNum, int nChannels, int nInNum, long hX, long hY);
template long Math<float>::channel_sum(int n, int nOutNum, int nChannels, int nInNum, long hX, long hY);


template <typename T>
__global__ void channel_div_kernel(const int count, const int num, const int channels, const int spatial_dim, const T* x, T* y)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<count; i += blockDim.x * gridDim.x)
	{
		int n = i / channels / spatial_dim;
		int s = i % spatial_dim;
		y[i] /= x[n * spatial_dim + s];
	}
}

template <typename T>
__global__ void channel_div2_kernel(const int count, const int num, const int channels, const int spatial_dim, const T* x, T* y)
{
	for (int i = blockIdx.x * blockDim.x + threadIdx.x; i<count; i += blockDim.x * gridDim.x)
	{
		int n = i / spatial_dim;
		int s = i % spatial_dim;

		for (int c = 0; c<channels; c++)
		{
			y[(n * channels + c) * spatial_dim + s] /= x[i];
		}
	}
}

template <typename T> 
long Math<T>::channel_div(int n, int nOutNum, int nChannels, int nInNum, long hX, long hY, int nMethod)
{
	LONG lErr;
	MemoryItem* pX;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	if (nMethod == 2)
		channel_div2_kernel<T> << <CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS >> >(n, nOutNum, nChannels, nInNum, (T*)pX->Data(), (T*)pY->Data());
	else
		channel_div_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, nOutNum, nChannels, nInNum, (T*)pX->Data(), (T*)pY->Data());

	return cudaGetLastError();
}

template long Math<double>::channel_div(int n, int nOutNum, int nChannels, int nInNum, long hX, long hY, int nMethod);
template long Math<float>::channel_div(int n, int nOutNum, int nChannels, int nInNum, long hX, long hY, int nMethod);


template <typename T>
__global__ void channel_mul_kernel(const int count, const int num, const int channels, const int spatial_dim, const T* x, T* y)
{
	for (int i = blockIdx.x * blockDim.x + threadIdx.x; i<count; i += blockDim.x * gridDim.x)
	{
		int n = i / channels / spatial_dim;
		int s = i % spatial_dim;
		y[i] *= x[n * spatial_dim + s];
	}
}

template <typename T>
__global__ void channel_mul2_kernel(const int count, const int num, const int channels, const int spatial_dim, const T* x, T* y)
{
	for (int i = blockIdx.x * blockDim.x + threadIdx.x; i<count; i += blockDim.x * gridDim.x)
	{
		int n = i / spatial_dim;
		int s = i % spatial_dim;

		for (int c = 0; c<channels; c++)
		{
			y[(n * channels + c) * spatial_dim + s] *= x[i];
		}
	}
}

template <typename T>
long Math<T>::channel_mul(int n, int nOutNum, int nChannels, int nInNum, long hX, long hY, int nMethod)
{
	LONG lErr;
	MemoryItem* pX;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	if (nMethod == 2)
		channel_mul2_kernel<T> << <CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS >> >(n, nOutNum, nChannels, nInNum, (T*)pX->Data(), (T*)pY->Data());
	else
		channel_mul_kernel<T> << <CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS >> >(n, nOutNum, nChannels, nInNum, (T*)pX->Data(), (T*)pY->Data());

	return cudaGetLastError();
}

template long Math<double>::channel_mul(int n, int nOutNum, int nChannels, int nInNum, long hX, long hY, int nMethod);
template long Math<float>::channel_mul(int n, int nOutNum, int nChannels, int nInNum, long hX, long hY, int nMethod);


template <typename T>
__global__ void channel_dot_kernel(const int num, const int channels, const int spatial_dim, const T* x, const T* a, T* y)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<num * spatial_dim; i += blockDim.x * gridDim.x)
	{
		int n = i / spatial_dim;
		int s = i % spatial_dim;
		T val = 0;

		for (int c=0; c<channels; c++)
		{
			int nIdx = (n * channels + c) * spatial_dim + s;
			val += (x[nIdx] * a[nIdx]);
		}

		y[i] = val;
	}
}

template <typename T> 
long Math<T>::channel_dot(int n, int nOutNum, int nChannels, int nInNum, long hX, long hA, long hY)
{
	LONG lErr;
	MemoryItem* pX;
	MemoryItem* pA;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	channel_dot_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(nOutNum, nChannels, nInNum, (T*)pX->Data(), (T*)pA->Data(), (T*)pY->Data());

	return cudaGetLastError();
}

template long Math<double>::channel_dot(int n, int nOutNum, int nChannels, int nInNum, long hX, long hA, long hY);
template long Math<float>::channel_dot(int n, int nOutNum, int nChannels, int nInNum, long hX, long hA, long hY);


template<typename T>
__global__ void im2col_kernel(int n, T* data_im, int height, int width, int kernel_h, int kernel_w, int pad_h, int pad_w, int stride_h, int stride_w, int dilation_h, int dilation_w, int height_col, int width_col, T* data_col)
{
	for (int index=blockIdx.x * blockDim.x + threadIdx.x; index<n; index += blockDim.x * gridDim.x)
	{
		int h_index = index / width_col;
		int h_col = h_index % height_col;
		int w_col = index % width_col;
		int c_im = h_index / height_col;
		int c_col = c_im * kernel_h * kernel_w;
		int h_offset = h_col * stride_h - pad_h;
		int w_offset = w_col * stride_w - pad_w;

		T* data_col_ptr = data_col;
		data_col_ptr += (c_col * height_col + h_col) * width_col + w_col;

		T* data_im_ptr = data_im;
		data_im_ptr += (c_im * height + h_offset) * width + w_offset;

		for (int i=0; i<kernel_h; i++)
		{
			for (int j=0; j<kernel_w; j++)
			{
				int h_im = h_offset + i * dilation_h;
				int w_im = w_offset + j * dilation_w;

				*data_col_ptr = (h_im >= 0 && w_im >= 0 && h_im < height && w_im < width) ?
								data_im_ptr[i * dilation_h * width + j * dilation_w] : 0;

				data_col_ptr += height_col * width_col;
			}
		}
	}
}

template<typename T>
long Math<T>::im2col(long hDataIm, int nDataImOffset, int nChannels, int nHeight, int nWidth, int nKernelH, int nKernelW, int nPadH, int nPadW, int nStrideH, int nStrideW, int nDilationH, int nDilationW, long hDataCol, int nDataColOffset)
{
	LONG lErr;
	MemoryItem* pDataIm;
	MemoryItem* pDataCol;

	if (lErr = m_pMemCol->GetData(hDataIm, &pDataIm))
		return lErr;

	if (lErr = m_pMemCol->GetData(hDataCol, &pDataCol))
		return lErr;

	// We are going to launch channels * height_col * width_col kernels, each
	// kernel responsible for copying a single-channel grid.
	int height_col = (nHeight + 2 * nPadH - (nDilationH * (nKernelH - 1) + 1)) / nStrideH + 1;
	int width_col = (nWidth + 2 * nPadW - (nDilationW * (nKernelW - 1) + 1)) / nStrideW + 1;
	int num_kernels = nChannels * height_col * width_col;

	T* data_im = (T*)pDataIm->Data();
	T* data_col = (T*)pDataCol->Data();

	if (nDataImOffset > 0)
		data_im += nDataImOffset;

	if (nDataColOffset > 0)
		data_col += nDataColOffset;

	im2col_kernel<T><<<CAFFE_GET_BLOCKS(num_kernels), CAFFE_CUDA_NUM_THREADS>>>(num_kernels, data_im, nHeight, nWidth, nKernelH, nKernelW, nPadH, nPadW, nStrideH, nStrideW, nDilationH, nDilationW, height_col, width_col, data_col);

	return cudaGetLastError();
}

template long Math<double>::im2col(long hDataIm, int nDataImOffset, int nChannels, int nHeight, int nWidth, int nKernelH, int nKernelW, int nPadH, int nPadW, int nStrideH, int nStrideW, int nDilationH, int nDilationW, long hDataCol, int nDataColOffset);
template long Math<float>::im2col(long hDataIm, int nDataImOffset, int nChannels, int nHeight, int nWidth, int nKernelH, int nKernelW, int nPadH, int nPadW, int nStrideH, int nStrideW, int nDilationH, int nDilationW, long hDataCol, int nDataColOffset);


template<typename T>
__global__ void col2im_kernel(int n, T* data_col, int height, int width, int kernel_h, int kernel_w, int pad_h, int pad_w, int stride_h, int stride_w, int dilation_h, int dilation_w, int height_col, int width_col, T* data_im)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		T fVal = 0;
		int w_im = i % width + pad_w;
		int h_im = (i / width) % height + pad_h;
		int c_im = i / (width * height);
		int kernel_extent_w = (kernel_w - 1) * dilation_w + 1;
		int kernel_extent_h = (kernel_h - 1) * dilation_h + 1;
		// cmopute the start and end of the output
		int w_col_start = (w_im < kernel_extent_w) ? 0 : (w_im - kernel_extent_w) / stride_w + 1;
		int w_col_end = min(w_im / stride_w + 1, width_col);
		int h_col_start = (h_im < kernel_extent_h) ? 0 : (h_im - kernel_extent_h) / stride_h + 1;
		int h_col_end = min(h_im / stride_h + 1, height_col);

		// TODO: use LCM of stride and dilation to avoid unnecessary loops
		for (int h_col = h_col_start; h_col < h_col_end; h_col += 1)
		{
			for (int w_col = w_col_start; w_col < w_col_end; w_col += 1)
			{
				int h_k = (h_im - h_col * stride_h);
				int w_k = (w_im - w_col * stride_w);

				if (h_k % dilation_h == 0 && w_k % dilation_w == 0)
				{
					h_k /= dilation_h;
					w_k /= dilation_w;

					int data_col_index = (((c_im * kernel_h + h_k) * kernel_w + w_k) *
						                  height_col + h_col) * width_col + w_col;
					fVal += data_col[data_col_index];
				}
			}
		}

		data_im[i] = fVal;
	}
}

template<typename T>
long Math<T>::col2im(long hDataCol, int nDataColOffset, int nChannels, int nHeight, int nWidth, int nKernelH, int nKernelW, int nPadH, int nPadW, int nStrideH, int nStrideW, int nDilationH, int nDilationW, long hDataIm, int nDataImOffset)
{
	LONG lErr;
	MemoryItem* pDataIm;
	MemoryItem* pDataCol;

	if (lErr = m_pMemCol->GetData(hDataIm, &pDataIm))
		return lErr;

	if (lErr = m_pMemCol->GetData(hDataCol, &pDataCol))
		return lErr;

	// To avoid involving atomic operations, we will launch one kernel per
	// bottom dimension, and then in the kernel add up the top dimensions.
	int height_col = (nHeight + 2 * nPadH - (nDilationH * (nKernelH - 1) + 1)) / nStrideH + 1;
	int width_col = (nWidth + 2 * nPadW - (nDilationW * (nKernelW - 1) + 1)) / nStrideW + 1;
	int num_kernels = nChannels * nHeight * nWidth;

	T* data_col = (T*)pDataCol->Data();
	T* data_im = (T*)pDataIm->Data();

	if (nDataColOffset > 0)
		data_col += nDataColOffset;

	if (nDataImOffset > 0)
		data_im += nDataImOffset;

	col2im_kernel<T><<<CAFFE_GET_BLOCKS(num_kernels), CAFFE_CUDA_NUM_THREADS>>>(num_kernels, data_col, nHeight, nWidth, nKernelH, nKernelW, nPadH, nPadW, nStrideH, nStrideW, nDilationH, nDilationW, height_col, width_col, data_im);

	return cudaGetLastError();
}

template long Math<double>::col2im(long hDataCol, int nDataColOffset, int nChannels, int nHeight, int nWidth, int nKernelH, int nKernelW, int nPadH, int nPadW, int nStrideH, int nStrideW, int nDilationH, int nDilationW, long hDataIm, int nDataImOffset);
template long Math<float>::col2im(long hDataCol, int nDataColOffset, int nChannels, int nHeight, int nWidth, int nKernelH, int nKernelW, int nPadH, int nPadW, int nStrideH, int nStrideW, int nDilationH, int nDilationW, long hDataIm, int nDataImOffset);



template<typename T, int num_axes>
__global__ void im2col_nd_kernel(int n, T* data_im, T* im_shape, T* col_shape, T* kernel_shape, T* pad, T* stride, T* dilation, T* data_col)
{
	int d_temp[num_axes];
	int d_iter[num_axes];

	__shared__ int shared_dilation[num_axes];
	__shared__ int shared_kernel_shape[num_axes];
	__shared__ int shared_pad[num_axes];
	__shared__ int shared_stride[num_axes];
	__shared__ int shared_col_shape[num_axes + 1];
	__shared__ int shared_im_shape[num_axes + 1];

	if (threadIdx.x < num_axes)
	{
		shared_dilation[threadIdx.x] = (int)dilation[threadIdx.x];
		shared_kernel_shape[threadIdx.x] = (int)kernel_shape[threadIdx.x];
		shared_pad[threadIdx.x] = (int)pad[threadIdx.x];
		shared_stride[threadIdx.x] = (int)stride[threadIdx.x];
	}

	if (threadIdx.x < num_axes + 1)
	{
		shared_col_shape[threadIdx.x] = (int)col_shape[threadIdx.x];
		shared_im_shape[threadIdx.x] = (int)im_shape[threadIdx.x];
	}

	__syncthreads();

	int i;
	for (int index=blockIdx.x * blockDim.x + threadIdx.x; index<n; index += blockDim.x * gridDim.x)
	{
		// Initialize channels_in, computed in the loop below, with itermediate
		// computations used to compute the spatial indices.
		int channel_in = index;
		int channel_out = 1;

		for (i = num_axes - 1; i>=0; i--)
		{
			d_temp[i] = channel_in % shared_col_shape[i + 1];
			channel_in /= shared_col_shape[i + 1];
			channel_out *= shared_kernel_shape[i];
		}

		channel_out *= channel_in;
		int data_col_inc = 1;

		for (i = 0; i<num_axes; i++)
		{
			channel_out *= shared_col_shape[i + 1];
			channel_out += d_temp[i];
			d_temp[i] = d_temp[i] * shared_stride[i] - shared_pad[i];
			channel_in *= shared_im_shape[i + 1];
			channel_in += d_temp[i];
			data_col_inc *= shared_col_shape[i + 1];
			d_iter[i] = 0;
		}

		T* data_col_ptr = data_col + channel_out;
		const T* data_im_ptr = data_im + channel_in;
		bool bIncremented;

		do {
			bool in_range = true;

			for (i = 0; i<num_axes; i++)
			{
				int d_iter_im = d_iter[i] * shared_dilation[i] + d_temp[i];
				in_range &= d_iter_im >= 0 && d_iter_im < shared_im_shape[i + 1];

				if (!in_range)
					break;
			}

			if (in_range)
			{
				int data_im_offset = d_iter[0] * shared_dilation[0];

				for (i=1; i<num_axes; i++)
				{
					data_im_offset *= shared_im_shape[i + 1];
					data_im_offset += d_iter[i] * shared_dilation[i];
				}

				*data_col_ptr = data_im_ptr[data_im_offset];
			}
			else
			{
				*data_col_ptr = 0;
			}

			data_col_ptr += data_col_inc;
			bIncremented = false;

			for (i = num_axes - 1; i>=0; i--)
			{
				int d_max = shared_kernel_shape[i];
				if (d_iter[i] == d_max - 1)
				{
					d_iter[i] = 0;
				}
				else
				{
					d_iter[i]++;
					bIncremented = true;
					break;
				}
			}
		} while (bIncremented);
	}
}

template <typename T>
long Math<T>::im2col_nd(long hDataIm, int nDataImOffset, int nNumSpatialAxes, int nNumKernels, int nChannelAxis, long hImShape, long hColShape, long hKernelShape, long hPad, long hStride, long hDilation, long hDataCol, int nDataColOffset)
{
	if (nNumSpatialAxes >= CAFFE_CUDA_NUM_THREADS)
		return ERROR_PARAM_OUT_OF_RANGE;

	LONG lErr;
	MemoryItem* pDataIm;
	MemoryItem* pDataCol;
	MemoryItem* pImShape;
	MemoryItem* pColShape;
	MemoryItem* pKernelShape;
	MemoryItem* pPad;
	MemoryItem* pStride;
	MemoryItem* pDilation;

	if (lErr = m_pMemCol->GetData(hDataIm, &pDataIm))
		return lErr;

	if (lErr = m_pMemCol->GetData(hDataCol, &pDataCol))
		return lErr;

	if (lErr = m_pMemCol->GetData(hImShape, &pImShape))
		return lErr;

	if (lErr = m_pMemCol->GetData(hColShape, &pColShape))
		return lErr;

	if (lErr = m_pMemCol->GetData(hKernelShape, &pKernelShape))
		return lErr;

	if (lErr = m_pMemCol->GetData(hPad, &pPad))
		return lErr;

	if (lErr = m_pMemCol->GetData(hStride, &pStride))
		return lErr;

	if (lErr = m_pMemCol->GetData(hDilation, &pDilation))
		return lErr;

	T* data_im = (T*)pDataIm->Data();
	T* data_col = (T*)pDataCol->Data();
	T* im_shape = (T*)pImShape->Data();
	T* col_shape = (T*)pColShape->Data();
	T* kernel_shape = (T*)pKernelShape->Data();
	T* pad = (T*)pPad->Data();
	T* stride = (T*)pStride->Data();
	T* dilation = (T*)pDilation->Data();

	if (nDataImOffset > 0)
		data_im += nDataImOffset;

	if (nDataColOffset > 0)
		data_col += nDataColOffset;

	if (nChannelAxis > 0)
	{
		im_shape += nChannelAxis;
		col_shape += nChannelAxis;
	}

	switch (nNumSpatialAxes)
	{
		case 1:
			im2col_nd_kernel<T, 1><<<CAFFE_GET_BLOCKS(nNumKernels), CAFFE_CUDA_NUM_THREADS>>>(nNumKernels, data_im, im_shape, col_shape, kernel_shape, pad, stride, dilation, data_col);
			break;

		case 2:
			im2col_nd_kernel<T, 2><<<CAFFE_GET_BLOCKS(nNumKernels), CAFFE_CUDA_NUM_THREADS>>>(nNumKernels, data_im, im_shape, col_shape, kernel_shape, pad, stride, dilation, data_col);
			break;

		case 3:
			im2col_nd_kernel<T, 3><<<CAFFE_GET_BLOCKS(nNumKernels), CAFFE_CUDA_NUM_THREADS>>>(nNumKernels, data_im, im_shape, col_shape, kernel_shape, pad, stride, dilation, data_col);
			break;

		case 4:
			im2col_nd_kernel<T, 4><<<CAFFE_GET_BLOCKS(nNumKernels), CAFFE_CUDA_NUM_THREADS>>>(nNumKernels, data_im, im_shape, col_shape, kernel_shape, pad, stride, dilation, data_col);
			break;

		case 5:
			im2col_nd_kernel<T, 5><<<CAFFE_GET_BLOCKS(nNumKernels), CAFFE_CUDA_NUM_THREADS>>>(nNumKernels, data_im, im_shape, col_shape, kernel_shape, pad, stride, dilation, data_col);
			break;

		case 6:
			im2col_nd_kernel<T, 6><<<CAFFE_GET_BLOCKS(nNumKernels), CAFFE_CUDA_NUM_THREADS>>>(nNumKernels, data_im, im_shape, col_shape, kernel_shape, pad, stride, dilation, data_col);
			break;

		case 7:
			im2col_nd_kernel<T, 7><<<CAFFE_GET_BLOCKS(nNumKernels), CAFFE_CUDA_NUM_THREADS>>>(nNumKernels, data_im, im_shape, col_shape, kernel_shape, pad, stride, dilation, data_col);
			break;

		case 8:
			im2col_nd_kernel<T, 8><<<CAFFE_GET_BLOCKS(nNumKernels), CAFFE_CUDA_NUM_THREADS>>>(nNumKernels, data_im, im_shape, col_shape, kernel_shape, pad, stride, dilation, data_col);
			break;

		case 9:
			im2col_nd_kernel<T, 9><<<CAFFE_GET_BLOCKS(nNumKernels), CAFFE_CUDA_NUM_THREADS>>>(nNumKernels, data_im, im_shape, col_shape, kernel_shape, pad, stride, dilation, data_col);
			break;

		case 10:
			im2col_nd_kernel<T, 10><<<CAFFE_GET_BLOCKS(nNumKernels), CAFFE_CUDA_NUM_THREADS>>>(nNumKernels, data_im, im_shape, col_shape, kernel_shape, pad, stride, dilation, data_col);
			break;

		default:
			return ERROR_PARAM_OUT_OF_RANGE;
	}

	return cudaGetLastError();
}

template long Math<double>::im2col_nd(long hDataIm, int nDataImOffset, int nNumSpatialAxes, int nNumKernels, int nChannelAxis, long hImShape, long hColShape, long hKernelShape, long hPad, long hStride, long hDilation, long hDataCol, int nDataColOffset);
template long Math<float>::im2col_nd(long hDataIm, int nDataImOffset, int nNumSpatialAxes, int nNumKernels, int nChannelAxis, long hImShape, long hColShape, long hKernelShape, long hPad, long hStride, long hDilation, long hDataCol, int nDataColOffset);


template<typename T, int num_axes>
__global__ void col2im_nd_kernel(int n, T* data_col, T* im_shape, T* col_shape, T* kernel_shape, T* pad, T* stride, T* dilation, T* data_im)
{
	int d_im[num_axes];
	int d_col_iter[num_axes];
	int d_col_start[num_axes];
	int d_col_end[num_axes];

	__shared__ int shared_dilation[num_axes];
	__shared__ int shared_kernel_shape[num_axes];
	__shared__ int shared_pad[num_axes];
	__shared__ int shared_stride[num_axes];
	__shared__ int shared_col_shape[num_axes + 1];
	__shared__ int shared_im_shape[num_axes + 1];

	if (threadIdx.x < num_axes)
	{
		shared_dilation[threadIdx.x] = (int)dilation[threadIdx.x];
		shared_kernel_shape[threadIdx.x] = (int)kernel_shape[threadIdx.x];
		shared_pad[threadIdx.x] = (int)pad[threadIdx.x];
		shared_stride[threadIdx.x] = (int)stride[threadIdx.x];
	}

	if (threadIdx.x < num_axes + 1)
	{
		shared_col_shape[threadIdx.x] = (int)col_shape[threadIdx.x];
		shared_im_shape[threadIdx.x] = (int)im_shape[threadIdx.x];
	}

	__syncthreads();

	int i;
	for (int index=blockIdx.x * blockDim.x + threadIdx.x; index<n; index += blockDim.x * gridDim.x)
	{
		// Initialize channel_in, computed in the loop below, with intermediate
		// computations used to compute the spatial indices.
		int c_im = index;
		
		// Calculate d_im (image dimensions).
		for (i = num_axes - 1; i>=0; i--)
		{
			d_im[i] = c_im % shared_im_shape[i + 1] + shared_pad[i];
			c_im /= shared_im_shape[i + 1];
		}

		// Calculate col start/end indices.
		bool bDone = false;
		for (i=0; i<num_axes; i++)
		{
			int kernel_extent = shared_dilation[i] * (shared_kernel_shape[i] - 1) + 1;

			d_col_iter[i] = (d_im[i] < kernel_extent) ? 0 :
				            (d_im[i] - kernel_extent) / shared_stride[i] + 1;
			d_col_start[i] = d_col_iter[i];
			d_col_end[i] = min(d_im[i] / shared_stride[i] + 1, shared_col_shape[i+1]);

			if (d_col_start[i] >= d_col_end[i])
			{
				// Skip computation if the dimension is 0 at any spatial axis --
				// final val will be 0.
				data_im[index] = 0;
				bDone = true;
				break;
			}
		}

		if (bDone)
			continue;

		// Loop over the col to compute the output val.
		T fVal = 0;
		bool bIncremented = true;
		bool bSkip = false;

		do {
			// Compute the final offset.
			int final_offset = 0;
			int kernel_shape_prod = 1;
			int kernel_index;

			for (i = num_axes - 1; i>=0; i--)
			{
				kernel_index = d_im[i] - d_col_iter[i] * shared_stride[i];
				if (kernel_index % shared_dilation[i])
				{
					bSkip = true;
					break;
				}
				else
				{
					kernel_index /= shared_dilation[i];
					final_offset += kernel_index * kernel_shape_prod;
					kernel_shape_prod *= shared_kernel_shape[i];
				}
			}

			if (!bSkip)
			{
				final_offset += kernel_shape_prod * c_im;

				for (i = 0; i<num_axes; i++)
				{
					final_offset *= shared_col_shape[i + 1];
					final_offset += d_col_iter[i];
				}

				fVal += data_col[final_offset];
			}

			bSkip = false;
			bIncremented = false;

			for (i = num_axes - 1; i>=0; i--)
			{
				int d_max = d_col_end[i];
				if (d_col_iter[i] == d_max - 1)
				{
					d_col_iter[i] = d_col_start[i];
				}
				else
				{
					d_col_iter[i]++;
					bIncremented = true;
					break;
				}
			}
		} while (bIncremented);

		data_im[index] = fVal;
	}
}

template <typename T>
long Math<T>::col2im_nd(long hDataCol, int nDataColOffset, int nNumSpatialAxes, int nImCount, int nChannelAxis, long hImShape, long hColShape, long hKernelShape, long hPad, long hStride, long hDilation, long hDataIm, int nDataImOffset)
{
	if (nNumSpatialAxes >= CAFFE_CUDA_NUM_THREADS)
		return ERROR_PARAM_OUT_OF_RANGE;

	LONG lErr;
	MemoryItem* pDataIm;
	MemoryItem* pDataCol;
	MemoryItem* pImShape;
	MemoryItem* pColShape;
	MemoryItem* pKernelShape;
	MemoryItem* pPad;
	MemoryItem* pStride;
	MemoryItem* pDilation;

	if (lErr = m_pMemCol->GetData(hDataIm, &pDataIm))
		return lErr;

	if (lErr = m_pMemCol->GetData(hDataCol, &pDataCol))
		return lErr;

	if (lErr = m_pMemCol->GetData(hImShape, &pImShape))
		return lErr;

	if (lErr = m_pMemCol->GetData(hColShape, &pColShape))
		return lErr;

	if (lErr = m_pMemCol->GetData(hKernelShape, &pKernelShape))
		return lErr;

	if (lErr = m_pMemCol->GetData(hPad, &pPad))
		return lErr;

	if (lErr = m_pMemCol->GetData(hStride, &pStride))
		return lErr;

	if (lErr = m_pMemCol->GetData(hDilation, &pDilation))
		return lErr;

	T* data_im = (T*)pDataIm->Data();
	T* data_col = (T*)pDataCol->Data();
	T* im_shape = (T*)pImShape->Data();
	T* col_shape = (T*)pColShape->Data();
	T* kernel_shape = (T*)pKernelShape->Data();
	T* pad = (T*)pPad->Data();
	T* stride = (T*)pStride->Data();
	T* dilation = (T*)pDilation->Data();

	if (nDataImOffset > 0)
		data_im += nDataImOffset;

	if (nDataColOffset > 0)
		data_col += nDataColOffset;

	if (nChannelAxis > 0)
	{
		im_shape += nChannelAxis;
		col_shape += nChannelAxis;
	}

	switch (nNumSpatialAxes)
	{
		case 1:
			col2im_nd_kernel<T, 1><<<CAFFE_GET_BLOCKS(nImCount), CAFFE_CUDA_NUM_THREADS>>>(nImCount, data_col, im_shape, col_shape, kernel_shape, pad, stride, dilation, data_im);
			break;

		case 2:
			col2im_nd_kernel<T, 2><<<CAFFE_GET_BLOCKS(nImCount), CAFFE_CUDA_NUM_THREADS>>>(nImCount, data_col, im_shape, col_shape, kernel_shape, pad, stride, dilation, data_im);
			break;

		case 3:
			col2im_nd_kernel<T, 3><<<CAFFE_GET_BLOCKS(nImCount), CAFFE_CUDA_NUM_THREADS>>>(nImCount, data_col, im_shape, col_shape, kernel_shape, pad, stride, dilation, data_im);
			break;

		case 4:
			col2im_nd_kernel<T, 4><<<CAFFE_GET_BLOCKS(nImCount), CAFFE_CUDA_NUM_THREADS>>>(nImCount, data_col, im_shape, col_shape, kernel_shape, pad, stride, dilation, data_im);
			break;

		case 5:
			col2im_nd_kernel<T, 5><<<CAFFE_GET_BLOCKS(nImCount), CAFFE_CUDA_NUM_THREADS>>>(nImCount, data_col, im_shape, col_shape, kernel_shape, pad, stride, dilation, data_im);
			break;

		case 6:
			col2im_nd_kernel<T, 6><<<CAFFE_GET_BLOCKS(nImCount), CAFFE_CUDA_NUM_THREADS>>>(nImCount, data_col, im_shape, col_shape, kernel_shape, pad, stride, dilation, data_im);
			break;

		case 7:
			col2im_nd_kernel<T, 7><<<CAFFE_GET_BLOCKS(nImCount), CAFFE_CUDA_NUM_THREADS>>>(nImCount, data_col, im_shape, col_shape, kernel_shape, pad, stride, dilation, data_im);
			break;

		case 8:
			col2im_nd_kernel<T, 8><<<CAFFE_GET_BLOCKS(nImCount), CAFFE_CUDA_NUM_THREADS>>>(nImCount, data_col, im_shape, col_shape, kernel_shape, pad, stride, dilation, data_im);
			break;

		case 9:
			col2im_nd_kernel<T, 9><<<CAFFE_GET_BLOCKS(nImCount), CAFFE_CUDA_NUM_THREADS>>>(nImCount, data_col, im_shape, col_shape, kernel_shape, pad, stride, dilation, data_im);
			break;

		case 10:
			col2im_nd_kernel<T, 10><<<CAFFE_GET_BLOCKS(nImCount), CAFFE_CUDA_NUM_THREADS>>>(nImCount, data_col, im_shape, col_shape, kernel_shape, pad, stride, dilation, data_im);
			break;

		default:
			return ERROR_PARAM_OUT_OF_RANGE;
	}

	return cudaGetLastError();
}

template long Math<double>::col2im_nd(long hDataCol, int nDataColOffset, int nNumSpatialAxes, int nImCount, int nChannelAxis, long hImShape, long hColShape, long hKernelShape, long hPad, long hStride, long hDilation, long hDataIm, int nDataImOffset);
template long Math<float>::col2im_nd(long hDataCol, int nDataColOffset, int nNumSpatialAxes, int nImCount, int nChannelAxis, long hImShape, long hColShape, long hKernelShape, long hPad, long hStride, long hDilation, long hDataIm, int nDataImOffset);


template <>
long Math<double>::rng_setseed(long lSeed)
{
	LONG lErr;

	if (lErr = curandSetPseudoRandomGeneratorSeed(m_curand, lSeed))
		return lErr;

	return curandSetGeneratorOffset(m_curand, 0);
}

template <>
long Math<float>::rng_setseed(long lSeed)
{
	LONG lErr;

	if (lErr = curandSetPseudoRandomGeneratorSeed(m_curand, lSeed))
		return lErr;

	return curandSetGeneratorOffset(m_curand, 0);
}


template <>
long Math<double>::rng_uniform(int n, double fMin, double fMax, long hY)
{
	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	LONG lErr;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	if (lErr = curandGenerateUniformDouble(m_curand, (double*)pY->Data(), n))
		return lErr;

	double fRange = fMax - fMin;
	if (fRange != 1.0)
	{
		if (lErr = cublasDscal(m_cublas, n, &fRange, (double*)pY->Data(), 1))
			return lErr;
	}

	if (fMin != 0)
		add_scalar_kernel<double><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, fMin, (double*)pY->Data());

	return cudaGetLastError();
}


template <>
long Math<float>::rng_uniform(int n, float fMin, float fMax, long hY)
{
	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	LONG lErr;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	if (lErr = curandGenerateUniform(m_curand, (float*)pY->Data(), n))
		return lErr;

	float fRange = fMax - fMin;
	if (fRange != 1.0)
	{
		if (lErr = cublasSscal(m_cublas, n, &fRange, (float*)pY->Data(), 1))
			return lErr;
	}

	if (fMin != 0)
		add_scalar_kernel<float><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, fMin, (float*)pY->Data());

	return cudaGetLastError();
}


template <>
long Math<double>::rng_gaussian(int n, double fMu, double fSigma, long hY)
{
	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	LONG lErr;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	if (((n % 2) != 0) && ((n+1) * sizeof(double)) <= pY->Size())
		n++;

	return curandGenerateNormalDouble(m_curand, (double*)pY->Data(), n, fMu, fSigma);
}


template <>
long Math<float>::rng_gaussian(int n, float fMu, float fSigma, long hY)
{
	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	LONG lErr;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	if (((n % 2) != 0) && ((n+1) * sizeof(float)) <= pY->Size())
		n++;

	return curandGenerateNormal(m_curand, (float*)pY->Data(), n, fMu, fSigma);
}


template <>
long Math<double>::rng_bernoulli(int n, double fNonZeroProb, long hY)
{
	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	LONG lErr;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	return ERROR_BASE; // not implemented. 
}

template <>
long Math<float>::rng_bernoulli(int n, float fNonZeroProb, long hY)
{
	if (m_cublas == NULL)
		return ERROR_CUBLAS_NULL;

	LONG lErr;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	return ERROR_BASE; // not implemented. 
}


template<typename T>
__global__ void batchreidx_fwd_kernel(int nCount, const int inner_dim, const T* in, const T* permut, T* out)
{
	for (int index = blockIdx.x * blockDim.x + threadIdx.x; index<nCount; index += blockDim.x * gridDim.x)
	{
		int n = index / inner_dim;
		int in_n = (int)permut[n];
		out[index] = in[in_n * inner_dim + index % inner_dim];
	}
}

template <class T>
long Math<T>::batchreidx_fwd(int n, int nInnerDim, long hBottomData, long hPermutData, long hTopData)
{
	LONG lErr;
	MemoryItem* pBottomData;
	MemoryItem* pPermutData;
	MemoryItem* pTopData;

	if (lErr = m_pMemCol->GetData(hBottomData, &pBottomData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hPermutData, &pPermutData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTopData, &pTopData))
		return lErr;

	T* bottom_data = (T*)pBottomData->Data();
	T* permut_data = (T*)pPermutData->Data();
	T* top_data = (T*)pTopData->Data();

	batchreidx_fwd_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, nInnerDim, bottom_data, permut_data, top_data);

	return cudaGetLastError();
}

template long Math<double>::batchreidx_fwd(int n, int nInnerDim, long hBottomData, long hPermutData, long hTopData);
template long Math<float>::batchreidx_fwd(int n, int nInnerDim, long hBottomData, long hPermutData, long hTopData);


template<typename T>
__global__ void batchreidx_bwd_kernel(int nCount, const int inner_dim, const T* in, const T* top_indexes, const T* begins, const T* counts, T* out)
{
	for (int index = blockIdx.x * blockDim.x + threadIdx.x; index<nCount; index += blockDim.x * gridDim.x)
	{
		int n = index / inner_dim;
		out[index] = 0;
		int lower = (int)begins[n];
		int upper = lower + (int)counts[n];

		for (int i = lower; i < upper; i++)
		{
			int in_n = (int)top_indexes[i];
			out[index] += in[in_n * inner_dim + index % inner_dim];
		}
	}
}

template <class T>
long Math<T>::batchreidx_bwd(int n, int nInnerDim, long hTopDiff, long hTopIdx, long hBegins, long hCounts, long hBottomDiff)
{
	LONG lErr;
	MemoryItem* pTopDiff;
	MemoryItem* pTopIdx;
	MemoryItem* pBegins;
	MemoryItem* pCounts;
	MemoryItem* pBottomDiff;

	if (lErr = m_pMemCol->GetData(hTopDiff, &pTopDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTopIdx, &pTopIdx))
		return lErr;

	if (lErr = m_pMemCol->GetData(hBegins, &pBegins))
		return lErr;

	if (lErr = m_pMemCol->GetData(hCounts, &pCounts))
		return lErr;

	if (lErr = m_pMemCol->GetData(hBottomDiff, &pBottomDiff))
		return lErr;

	T* top_diff = (T*)pTopDiff->Data();
	T* top_idx = (T*)pTopIdx->Data();
	T* begins = (T*)pBegins->Data();
	T* counts = (T*)pCounts->Data();
	T* bottom_diff = (T*)pBottomDiff->Data();

	batchreidx_bwd_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, nInnerDim, top_diff, top_idx, begins, counts, bottom_diff);

	return cudaGetLastError();
}

template long Math<double>::batchreidx_bwd(int n, int nInnerDim, long hTopDiff, long hTopIdx, long hBegins, long hCounts, long hBottomDiff);
template long Math<float>::batchreidx_bwd(int n, int nInnerDim, long hTopDiff, long hTopIdx, long hBegins, long hCounts, long hBottomDiff);


template<typename T>
__global__ void embed_fwd_kernel(int nCount, const T* bottom_data, const T* weight, int M, int N, int K, T* top_data)
{
	for (int top_index = blockIdx.x * blockDim.x + threadIdx.x; top_index<nCount; top_index += blockDim.x * gridDim.x)
	{
		const int n = top_index / N;
		const int d = top_index % N;
		const int index = (int)bottom_data[n];
		const int weight_index = index * N + d;
		top_data[top_index] = weight[weight_index];
	}
}

template <class T>
long Math<T>::embed_fwd(int n, long hBottomData, long hWeight, int nM, int nN, int nK, long hTopData)
{
	LONG lErr;
	MemoryItem* pBottomData;
	MemoryItem* pWeight;
	MemoryItem* pTopData;

	if (lErr = m_pMemCol->GetData(hBottomData, &pBottomData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hWeight, &pWeight))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTopData, &pTopData))
		return lErr;

	T* bottom_data = (T*)pBottomData->Data();
	T* weight = (T*)pWeight->Data();
	T* top_data = (T*)pTopData->Data();

	embed_fwd_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, bottom_data, weight, nM, nN, nK, top_data);

	return cudaGetLastError();
}

template long Math<double>::embed_fwd(int nCount, long hBottomData, long hWeight, int nM, int nN, int nK, long hTopData);
template long Math<float>::embed_fwd(int nCount, long hBottomData, long hWeight, int nM, int nN, int nK, long hTopData);


template<typename T>
__global__ void embed_bwd_kernel(int nCount, const T* bottom_data, const T* top_diff, int M, int N, int K, T* weight_diff)
{
	for (int top_index = blockIdx.x * blockDim.x + threadIdx.x; top_index<nCount; top_index += blockDim.x * gridDim.x)
	{
		const int n = top_index / N;
		const int d = top_index % N;
		const int index = (int)bottom_data[n];
		const int weight_index = index * N + d;
		math_atomic_add(top_diff[top_index], weight_diff + weight_index);
	}
}

template <class T>
long Math<T>::embed_bwd(int n, long hBottomData, long hTopDiff, int nM, int nN, int nK, long hWeightDiff)
{
	LONG lErr;
	MemoryItem* pBottomData;
	MemoryItem* pTopDiff;
	MemoryItem* pWeightDiff;

	if (lErr = m_pMemCol->GetData(hBottomData, &pBottomData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTopDiff, &pTopDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hWeightDiff, &pWeightDiff))
		return lErr;

	T* bottom_data = (T*)pBottomData->Data();
	T* top_diff = (T*)pTopDiff->Data();
	T* weight_diff = (T*)pWeightDiff->Data();

	embed_bwd_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, bottom_data, top_diff, nM, nN, nK, weight_diff);

	return cudaGetLastError();
}

template long Math<double>::embed_bwd(int nCount, long hBottomData, long hWeight, int nM, int nN, int nK, long hTopData);
template long Math<float>::embed_bwd(int nCount, long hBottomData, long hWeight, int nM, int nN, int nK, long hTopData);


template<typename T>
__global__ void pooling_fwd_max_kernel(int nCount, T* bottom_data, int num, int channels, int height, int width, int pooled_height, int pooled_width, int kernel_h, int kernel_w, int stride_h, int stride_w, int pad_h, int pad_w, T* top_data, T* mask, T* top_mask)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<nCount; i += blockDim.x * gridDim.x)
	{
		int pw = i % pooled_width;
		int ph = (i / pooled_width) % pooled_height;
		int c = (i / pooled_width / pooled_height) % channels;
		int n = i / pooled_width / pooled_height / channels;
		int hstart = ph * stride_h - pad_h;
		int wstart = pw * stride_w - pad_w;
		const int hend = min(hstart + kernel_h, height);
		const int wend = min(wstart + kernel_w, width);
		hstart = max(hstart, 0);
		wstart = max(wstart, 0);
		T maxval = (T)-FLT_MAX;
		int maxidx = -1;
		const T* const bottom_slice = bottom_data + (n * channels + c) * height * width;

		for (int h=hstart; h<hend; h++)
		{
			for (int w=wstart; w<wend; w++)
			{
				if (bottom_slice[h * width + w] > maxval)
				{
					maxidx = h * width + w;
					maxval = bottom_slice[maxidx];
				}
			}
		}

		top_data[i] = maxval;

		if (mask != NULL)
			mask[i] = maxidx;
		else
			top_mask[i] = maxidx;
	}
}


template<typename T>
__global__ void pooling_fwd_ave_kernel(int nCount, T* bottom_data, int num, int channels, int height, int width, int pooled_height, int pooled_width, int kernel_h, int kernel_w, int stride_h, int stride_w, int pad_h, int pad_w, T* top_data)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<nCount; i += blockDim.x * gridDim.x)
	{
		int pw = i % pooled_width;
		int ph = (i / pooled_width) % pooled_height;
		int c = (i / pooled_width / pooled_height) % channels;
		int n = i / pooled_width / pooled_height / channels;
		int hstart = ph * stride_h - pad_h;
		int wstart = pw * stride_w - pad_w;
		int hend = min(hstart + kernel_h, height + pad_h);
		int wend = min(wstart + kernel_w, width + pad_w);
		const int pool_size = (hend - hstart) * (wend - wstart);
		hstart = max(hstart, 0);
		wstart = max(wstart, 0);
		hend = min(hend, height);
		wend = min(wend, width);
		T aveval = 0;
		const T* const bottom_slice = bottom_data + (n * channels + c) * height * width;

		for (int h=hstart; h<hend; h++)
		{
			for (int w=wstart; w<wend; w++)
			{
				aveval += bottom_slice[h * width + w];
			}
		}

		top_data[i] = aveval / pool_size;
	}
}


template<typename T>
__global__ void pooling_fwd_sto_train_kernel(int nCount, T* bottom_data, int num, int channels, int height, int width, int pooled_height, int pooled_width, int kernel_h, int kernel_w, int stride_h, int stride_w, int pad_h, int pad_w, T* top_data, T* rand_idx)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<nCount; i += blockDim.x * gridDim.x)
	{
		int pw = i % pooled_width;
		int ph = (i / pooled_width) % pooled_height;
		int c = (i / pooled_width / pooled_height) % channels;
		int n = i / pooled_width / pooled_height / channels;
		int hstart = ph * stride_h;
		int hend = min(hstart + kernel_h, height);
		int wstart = pw * stride_w;
		int wend = min(wstart + kernel_w, width);
		T cumsum = 0;
		const T* const bottom_slice = bottom_data + (n * channels + c) * height * width;

		// First pass: get the sum;
		for (int h=hstart; h<hend; h++)
		{
			for (int w=wstart; w<wend; w++)
			{
				cumsum += bottom_slice[h * width + w];
			}
		}

		const T thres = rand_idx[i] * cumsum;
		// Second pass: get value and set index.
		cumsum = 0;
		for (int h=hstart; h<hend; h++)
		{
			for (int w=wstart; w<wend; w++)
			{
				cumsum += bottom_slice[h * width + w];
				if (cumsum >= thres)
				{
					rand_idx[i] = ((n * channels + c) * height + h) * width + w;
					top_data[i] = bottom_slice[h * width + w];
					return;
				}
			}
		}
	}
}


template<typename T>
__global__ void pooling_fwd_sto_test_kernel(int nCount, T* bottom_data, int num, int channels, int height, int width, int pooled_height, int pooled_width, int kernel_h, int kernel_w, int stride_h, int stride_w, int pad_h, int pad_w, T* top_data)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<nCount; i += blockDim.x * gridDim.x)
	{
		int pw = i % pooled_width;
		int ph = (i / pooled_width) % pooled_height;
		int c = (i / pooled_width / pooled_height) % channels;
		int n = i / pooled_width / pooled_height / channels;
		int hstart = ph * stride_h;
		int hend = min(hstart + kernel_h, height);
		int wstart = pw * stride_w;
		int wend = min(wstart + kernel_w, width);

		// We set cumsum to be 0 to avoid divide by zero problems.
		T cumsum = 0;
		T cumvalues = 0;
		const T* const bottom_slice = bottom_data + (n * channels + c) * height * width;

		// First pass: get the sum;
		for (int h=hstart; h<hend; h++)
		{
			for (int w=wstart; w<wend; w++)
			{
				cumsum += bottom_slice[h * width + w];
				cumvalues += bottom_slice[h * width + w] * bottom_slice[h * width + w];
			}
		}

		top_data[i] = (cumsum > 0.0) ? cumvalues / cumsum : 0.0;
	}
}


template <class T>
long Math<T>::pooling_fwd(int nMethod, int n, long hBottomData, int nNum, int nChannels, int h, int w, int hPooled, int wPooled, int hKernel, int wKernel, int hStride, int wStride, int hPad, int wPad, long hTopData, long hMask, long hTopMask)
{
	LONG lErr;
	MemoryItem* pBottomData;
	MemoryItem* pTopData;
	MemoryItem* pMask = NULL;
	MemoryItem* pTopMask = NULL;
	T* mask = NULL;
	T* top_mask = NULL;
	T* rand_idx = NULL;

	if (lErr = m_pMemCol->GetData(hBottomData, &pBottomData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTopData, &pTopData))
		return lErr;

	if (hMask != 0)
	{
		if (lErr = m_pMemCol->GetData(hMask, &pMask))
			return lErr;

		mask = (T*)pMask->Data();
		rand_idx = mask;	// parameter doubles as rand_idx.
	}

	if (hTopMask != 0)
	{
		if (lErr = m_pMemCol->GetData(hTopMask, &pTopMask))
			return lErr;

		top_mask = (T*)pTopMask->Data();
	}

	T* bottom_data = (T*)pBottomData->Data();
	T* top_data = (T*)pTopData->Data();

	switch (nMethod)
	{
		case POOLING_METHOD_MAX:
			pooling_fwd_max_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, bottom_data, nNum, nChannels, h, w, hPooled, wPooled, hKernel, wKernel, hStride, wStride, hPad, wPad, top_data, mask, top_mask);
			break;

		case POOLING_METHOD_AVE:
			pooling_fwd_ave_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, bottom_data, nNum, nChannels, h, w, hPooled, wPooled, hKernel, wKernel, hStride, wStride, hPad, wPad, top_data);
			break;

		case POOLING_METHOD_STO_TRAIN:
			pooling_fwd_sto_train_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, bottom_data, nNum, nChannels, h, w, hPooled, wPooled, hKernel, wKernel, hStride, wStride, hPad, wPad, top_data, rand_idx);
			break;

		case POOLING_METHOD_STO_TEST:
			pooling_fwd_sto_test_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, bottom_data, nNum, nChannels, h, w, hPooled, wPooled, hKernel, wKernel, hStride, wStride, hPad, wPad, top_data);
			break;
	}

	return cudaGetLastError();
}

template long Math<double>::pooling_fwd(int nMethod, int nCount, long hBottomData, int nNum, int nChannels, int h, int w, int hPooled, int wPooled, int hKernel, int wKernel, int hStride, int wStride, int hPad, int wPad, long hTopData, long hMask, long hTopMask);
template long Math<float>::pooling_fwd(int nMethod, int nCount, long hBottomData, int nNum, int nChannels, int h, int w, int hPooled, int wPooled, int hKernel, int wKernel, int hStride, int wStride, int hPad, int wPad, long hTopData, long hMask, long hTopMask);


template<typename T>
__global__ void pooling_bwd_max_kernel(int nCount, T* top_diff, int num, int channels, int height, int width, int pooled_height, int pooled_width, int kernel_h, int kernel_w, int stride_h, int stride_w, int pad_h, int pad_w, T* bottom_diff, T* mask, T* top_mask)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<nCount; i += blockDim.x * gridDim.x)
	{
		// find out the local index
		// find out the local offset
		int w = i % width;
		int h = (i / width) % height;
		int c = (i / width / height) % channels;
		int n = i / width / height / channels;
		int phstart = (h + pad_h < kernel_h) ? 0 : (h + pad_h - kernel_h) / stride_h + 1;
		int phend = min((h + pad_h) / stride_h + 1, pooled_height);
		int pwstart = (w + pad_w < kernel_w) ? 0 : (w + pad_w - kernel_w) / stride_w + 1;
		int pwend = min((w + pad_w) / stride_w + 1, pooled_width);
		T gradient = 0;
		int offset = (n * channels + c) * pooled_height * pooled_width;
		const T* const top_diff_slice = top_diff + offset;
		const int nCompare = h * width + w;

		if (mask != NULL)
		{
			const T* const mask_slice = mask + offset;

			for (int ph = phstart; ph<phend; ph++)
			{
				for (int pw = pwstart; pw<pwend; pw++)
				{
					int nIdx = ph * pooled_width + pw;

					if (mask_slice[nIdx] == nCompare)
						gradient += top_diff_slice[nIdx];
				}
			}
		}
		else
		{
			const T* const top_mask_slice = top_mask + offset;

			for (int ph = phstart; ph<phend; ph++)
			{
				for (int pw = pwstart; pw<pwend; pw++)
				{
					int nIdx = ph * pooled_width + pw;

					if (top_mask_slice[nIdx] == nCompare)
						gradient += top_diff_slice[nIdx];
				}
			}
		}

		bottom_diff[i] = gradient;
	}
}


template<typename T>
__global__ void pooling_bwd_ave_kernel(int nCount, T* top_diff, int num, int channels, int height, int width, int pooled_height, int pooled_width, int kernel_h, int kernel_w, int stride_h, int stride_w, int pad_h, int pad_w, T* bottom_diff)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<nCount; i += blockDim.x * gridDim.x)
	{
		// find out the local index
		// find out the local offset
		int w = i % width + pad_w;
		int h = (i / width) % height + pad_h;
		int c = (i / width / height) % channels;
		int n = i / width / height / channels;
		int phstart = (h < kernel_h) ? 0 : (h - kernel_h) / stride_h + 1;
		int phend = min(h / stride_h + 1, pooled_height);
		int pwstart = (w < kernel_w) ? 0 : (w - kernel_w) / stride_w + 1;
		int pwend = min(w / stride_w + 1, pooled_width);
		T gradient = 0;
		const T* const top_diff_slice = top_diff + (n * channels + c) * pooled_height * pooled_width;

		for (int ph = phstart; ph<phend; ph++)
		{
			for (int pw = pwstart; pw<pwend; pw++)
			{
				// figure out the pooling size
				int hstart = ph * stride_h - pad_h;
				int wstart = pw * stride_w - pad_w;
				int hend = min(hstart + kernel_h, height + pad_h);
				int wend = min(wstart + kernel_w, width + pad_w);
				int pool_size = (hend - hstart) * (wend - wstart);
				gradient += top_diff_slice[ph * pooled_width + pw] / pool_size;
			}
		}

		bottom_diff[i] = gradient;
	}
}


template<typename T>
__global__ void pooling_bwd_sto_kernel(int nCount, T* top_diff, int num, int channels, int height, int width, int pooled_height, int pooled_width, int kernel_h, int kernel_w, int stride_h, int stride_w, int pad_h, int pad_w, T* bottom_diff, T* rand_idx)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<nCount; i += blockDim.x * gridDim.x)
	{
		// find out the local index
		// find out the local offset
		int w = i % width;
		int h = (i / width) % height;
		int c = (i / width / height) % channels;
		int n = i / width / height / channels;
		int phstart = (h < kernel_h) ? 0 : (h - kernel_h) / stride_h + 1;
		int phend = min(h / stride_h + 1, pooled_height);
		int pwstart = (w < kernel_w) ? 0 : (w - kernel_w) / stride_w + 1;
		int pwend = min(w / stride_w + 1, pooled_width);
		T gradient = 0;
		int offset = (n * channels + c) * pooled_height * pooled_width;
		const T* const rand_idx_slice = rand_idx + offset;
		const T* const top_diff_slice = top_diff + offset;

		for (int ph = phstart; ph<phend; ph++)
		{
			for (int pw = pwstart; pw<pwend; pw++)
			{
				int nIdx = ph * pooled_width + pw;

				if (i == (int)rand_idx_slice[nIdx])
					gradient += top_diff_slice[nIdx];
			}
		}

		bottom_diff[i] = gradient;
	}
}


template <class T>
long Math<T>::pooling_bwd(int nMethod, int n, long hTopDiff, int nNum, int nChannels, int h, int w, int hPooled, int wPooled, int hKernel, int wKernel, int hStride, int wStride, int hPad, int wPad, long hBottomDiff, long hMask, long hTopMask)
{
	LONG lErr;
	MemoryItem* pBottomDiff;
	MemoryItem* pTopDiff;
	MemoryItem* pMask = NULL;
	MemoryItem* pTopMask = NULL;
	T* mask = NULL;
	T* top_mask = NULL;
	T* rand_idx = NULL;

	if (lErr = m_pMemCol->GetData(hBottomDiff, &pBottomDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTopDiff, &pTopDiff))
		return lErr;

	if (hMask != 0)
	{
		if (lErr = m_pMemCol->GetData(hMask, &pMask))
			return lErr;

		mask = (T*)pMask->Data();
		rand_idx = mask;	// parameter doubles as rand_idx.
	}

	if (hTopMask != 0)
	{
		if (lErr = m_pMemCol->GetData(hTopMask, &pTopMask))
			return lErr;

		top_mask = (T*)pTopMask->Data();
	}

	T* bottom_diff = (T*)pBottomDiff->Data();
	T* top_diff = (T*)pTopDiff->Data();

	switch (nMethod)
	{
		case POOLING_METHOD_MAX:
			pooling_bwd_max_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, top_diff, nNum, nChannels, h, w, hPooled, wPooled, hKernel, wKernel, hStride, wStride, hPad, wPad, bottom_diff, mask, top_mask);
			break;

		case POOLING_METHOD_AVE:
			pooling_bwd_ave_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, top_diff, nNum, nChannels, h, w, hPooled, wPooled, hKernel, wKernel, hStride, wStride, hPad, wPad, bottom_diff);
			break;

		case POOLING_METHOD_STO_TRAIN:
			pooling_bwd_sto_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, top_diff, nNum, nChannels, h, w, hPooled, wPooled, hKernel, wKernel, hStride, wStride, hPad, wPad, bottom_diff, rand_idx);
			break;
	}

	return cudaGetLastError();
}

template long Math<double>::pooling_bwd(int nMethod, int nCount, long hTopDiff, int nNum, int nChannels, int h, int w, int hPooled, int wPooled, int hKernel, int wKernel, int hStride, int wStride, int hPad, int wPad, long hBottomDiff, long hMask, long hTopMask);
template long Math<float>::pooling_bwd(int nMethod, int nCount, long hTopDiff, int nNum, int nChannels, int h, int w, int hPooled, int wPooled, int hKernel, int wKernel, int hStride, int wStride, int hPad, int wPad, long hBottomDiff, long hMask, long hTopMask);


template<typename T>
__global__ void unpooling_fwd_max_kernel(int nCount, T* bottom_data, int num, int channels, int height, int width, int unpooled_height, int unpooled_width, int kernel_h, int kernel_w, int stride_h, int stride_w, int pad_h, int pad_w, T* top_data, T* bottom_mask)
{
	for (int i = blockIdx.x * blockDim.x + threadIdx.x; i<nCount; i += blockDim.x * gridDim.x)
	{
		int pw = i % width;
		int ph = (i / width) % height;
		int c = (i / width / height) % channels;
		int n = i / width / height / channels;

		int uph = max(0, min(ph * stride_h - pad_h, unpooled_height - 1));
		int upw = max(0, min(pw * stride_w - pad_w, unpooled_width - 1));
		int unpooled_index = uph * unpooled_width + upw;

		top_data += (n * channels + c) * unpooled_height * unpooled_width;
		if (bottom_mask)
		{
			const int mask_index = (int)bottom_mask[i];
			top_data[mask_index] = bottom_data[i];
		}
		else
		{
			top_data[unpooled_index] = bottom_data[i];
		}
	}
}


template<typename T>
__global__ void unpooling_fwd_ave_kernel(int nCount, T* bottom_data, int num, int channels, int height, int width, int unpooled_height, int unpooled_width, int kernel_h, int kernel_w, int stride_h, int stride_w, int pad_h, int pad_w, T* top_data)
{
	for (int i = blockIdx.x * blockDim.x + threadIdx.x; i<nCount; i += blockDim.x * gridDim.x)
	{
		// find the local index and local offset
		int w = i % unpooled_width + pad_w;
		int h = (i / unpooled_width) % unpooled_height + pad_h;
		int c = (i / unpooled_width / unpooled_height) % channels;
		int n = i / unpooled_width / unpooled_height / channels;
		int hstart = (h < kernel_h) ? 0 : (h - kernel_h) / stride_h + 1;
		int hend = min(h / stride_h + 1, height);
		int wstart = (w < kernel_w) ? 0 : (w - kernel_w) / stride_w + 1;
		int wend = min(w / stride_w + 1, width);
		T distval = 0;
		bottom_data += (n * channels + c) * height * width;

		for (int ph = hstart; ph < hend; ph++)
		{
			for (int pw = wstart; pw < wend; pw++)
			{
				// figure out the pooling size.
				int hstart = ph * stride_h - pad_h;
				int wstart = pw * stride_w - pad_w;
				int hend = min(hstart + kernel_h, unpooled_height + pad_h);
				int wend = min(wstart + kernel_w, unpooled_width + pad_w);
				int pool_size = (hend - hstart) * (wend - wstart);
				distval += bottom_data[ph * width + pw] / pool_size;
			}
		}

		top_data[i] = distval;
	}
}


template <class T>
long Math<T>::unpooling_fwd(int nMethod, int n, long hBottomData, int nNum, int nChannels, int h, int w, int hUnPooled, int wUnPooled, int hKernel, int wKernel, int hStride, int wStride, int hPad, int wPad, long hTopData, long hBottomMask)
{
	LONG lErr;
	MemoryItem* pBottomData;
	MemoryItem* pTopData;
	MemoryItem* pBottomMask = NULL;
	T* bottom_mask = NULL;

	if (lErr = m_pMemCol->GetData(hBottomData, &pBottomData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTopData, &pTopData))
		return lErr;

	if (hBottomMask != 0)
	{
		if (lErr = m_pMemCol->GetData(hBottomMask, &pBottomMask))
			return lErr;

		bottom_mask = (T*)pBottomMask->Data();
	}

	T* bottom_data = (T*)pBottomData->Data();
	T* top_data = (T*)pTopData->Data();

	switch (nMethod)
	{
		case POOLING_METHOD_MAX:
			unpooling_fwd_max_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, bottom_data, nNum, nChannels, h, w, hUnPooled, wUnPooled, hKernel, wKernel, hStride, wStride, hPad, wPad, top_data, bottom_mask);
			break;

		case POOLING_METHOD_AVE:
			unpooling_fwd_ave_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, bottom_data, nNum, nChannels, h, w, hUnPooled, wUnPooled, hKernel, wKernel, hStride, wStride, hPad, wPad, top_data);
			break;

		default:
			return ERROR_PARAM_OUT_OF_RANGE;
	}

	return cudaGetLastError();
}

template long Math<double>::unpooling_fwd(int nMethod, int nCount, long hBottomData, int nNum, int nChannels, int h, int w, int hUnPooled, int wUnPooled, int hKernel, int wKernel, int hStride, int wStride, int hPad, int wPad, long hTopData, long hBottomMask);
template long Math<float>::unpooling_fwd(int nMethod, int nCount, long hBottomData, int nNum, int nChannels, int h, int w, int hUnPooled, int wUnPooled, int hKernel, int wKernel, int hStride, int wStride, int hPad, int wPad, long hTopData, long hBottomMask);


template<typename T>
__global__ void unpooling_bwd_max_kernel(int nCount, T* top_diff, int num, int channels, int height, int width, int unpooled_height, int unpooled_width, int kernel_h, int kernel_w, int stride_h, int stride_w, int pad_h, int pad_w, T* bottom_diff, T* bottom_mask)
{
	for (int i = blockIdx.x * blockDim.x + threadIdx.x; i<nCount; i += blockDim.x * gridDim.x)
	{
		// Find the local index and local offset.
		int pw = i % width;
		int ph = (i / width) % height;
		int c = (i / width / height) % channels;
		int n = i / width / height / channels;

		int uph = max(0, min(ph * stride_h - pad_h, unpooled_height - 1));
		int upw = max(0, min(pw * stride_w - pad_w, unpooled_width - 1));
		int unpooled_index = uph * unpooled_width + upw;

		top_diff += (n * channels + c) * unpooled_height * unpooled_width;
		if (bottom_mask)
		{
			const int mask_index = (int)bottom_mask[i];
			bottom_diff[mask_index] = top_diff[i];
		}
		else
		{
			bottom_diff[unpooled_index] = top_diff[i];
		}
	}
}

template<typename T>
__global__ void unpooling_bwd_ave_kernel(int nCount, T* top_diff, int num, int channels, int height, int width, int unpooled_height, int unpooled_width, int kernel_h, int kernel_w, int stride_h, int stride_w, int pad_h, int pad_w, T* bottom_diff)
{
	for (int i = blockIdx.x * blockDim.x + threadIdx.x; i<nCount; i += blockDim.x * gridDim.x)
	{
		int pw = i % width;
		int ph = (i / width) % height;
		int c = (i / width / height) % channels;
		int n = i / width / height / channels;
		int hstart = ph * stride_h - pad_h;
		int wstart = pw * stride_w - pad_w;
		int hend = min(hstart + kernel_h, unpooled_height + pad_h);
		int wend = min(wstart + kernel_w, unpooled_width + pad_w);
		int pool_size = (hend - hstart) * (wend - wstart);

		hstart = max(hstart, 0);
		wstart = max(wstart, 0);
		hend = min(hend, unpooled_height);
		wend = min(wend, unpooled_width);
		T gradient = 0;

		top_diff += (n * channels + c) * unpooled_height * unpooled_width;

		for (int h = hstart; h < hend; h++)
		{
			for (int w = wstart; w < wend; w++)
			{
				gradient += top_diff[h * unpooled_width + w];
			}
		}

		bottom_diff[i] = gradient / pool_size;
	}
}

template <class T>
long Math<T>::unpooling_bwd(int nMethod, int n, long hTopDiff, int nNum, int nChannels, int h, int w, int hUnPooled, int wUnPooled, int hKernel, int wKernel, int hStride, int wStride, int hPad, int wPad, long hBottomDiff, long hBottomMask)
{
	LONG lErr;
	MemoryItem* pBottomDiff;
	MemoryItem* pTopDiff;
	MemoryItem* pBottomMask = NULL;
	T* bottom_mask = NULL;

	if (lErr = m_pMemCol->GetData(hBottomDiff, &pBottomDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTopDiff, &pTopDiff))
		return lErr;

	if (hBottomMask != 0)
	{
		if (lErr = m_pMemCol->GetData(hBottomMask, &pBottomMask))
			return lErr;

		bottom_mask = (T*)pBottomMask->Data();
	}

	T* bottom_diff = (T*)pBottomDiff->Data();
	T* top_diff = (T*)pTopDiff->Data();

	switch (nMethod)
	{
	case POOLING_METHOD_MAX:
		unpooling_bwd_max_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, top_diff, nNum, nChannels, h, w, hUnPooled, wUnPooled, hKernel, wKernel, hStride, wStride, hPad, wPad, bottom_diff, bottom_mask);
		break;

	case POOLING_METHOD_AVE:
		unpooling_bwd_ave_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, top_diff, nNum, nChannels, h, w, hUnPooled, wUnPooled, hKernel, wKernel, hStride, wStride, hPad, wPad, bottom_diff);
		break;

	default:
		return ERROR_PARAM_OUT_OF_RANGE;
	}

	return cudaGetLastError();
}

template long Math<double>::unpooling_bwd(int nMethod, int nCount, long hTopDiff, int nNum, int nChannels, int h, int w, int hUnPooled, int wUnPooled, int hKernel, int wKernel, int hStride, int wStride, int hPad, int wPad, long hBottomDiff, long hBottomMask);
template long Math<float>::unpooling_bwd(int nMethod, int nCount, long hTopDiff, int nNum, int nChannels, int h, int w, int hUnPooled, int wUnPooled, int hKernel, int wKernel, int hStride, int wStride, int hPad, int wPad, long hBottomDiff, long hBottomMask);


template<typename T>
__global__ void tanh_fwd_kernel(int n, T* in, T* out)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		out[i] = tanh(in[i]);
	}
}

template <class T>
long Math<T>::tanh_fwd(int n, long hBottomData, long hTopData)
{
	LONG lErr;
	MemoryItem* pBottomData;
	MemoryItem* pTopData;

	if (lErr = m_pMemCol->GetData(hBottomData, &pBottomData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTopData, &pTopData))
		return lErr;

	T* bottom_data = (T*)pBottomData->Data();
	T* top_data = (T*)pTopData->Data();

	tanh_fwd_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, bottom_data, top_data);

	return cudaGetLastError();
}

template long Math<double>::tanh_fwd(int nCount, long hBottomData, long hTopData);
template long Math<float>::tanh_fwd(int nCount, long hBottomData, long hTopData);


template<typename T>
__global__ void tanh_bwd_kernel(int n, T* in_diff, T* out_data, T* out_diff)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		T tanhx = out_data[i];
		out_diff[i] = in_diff[i] * (1 - tanhx * tanhx);
	}
}

template <class T>
long Math<T>::tanh_bwd(int n, long hTopDiff, long hTopData, long hBottomDiff)
{
	LONG lErr;
	MemoryItem* pTopDiff;
	MemoryItem* pTopData;
	MemoryItem* pBottomDiff;

	if (lErr = m_pMemCol->GetData(hTopDiff, &pTopDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTopData, &pTopData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hBottomDiff, &pBottomDiff))
		return lErr;

	T* top_diff = (T*)pTopDiff->Data();
	T* top_data = (T*)pTopData->Data();
	T* bottom_diff = (T*)pBottomDiff->Data();

	tanh_bwd_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, top_diff, top_data, bottom_diff);

	return cudaGetLastError();
}

template long Math<double>::tanh_bwd(int nCount, long hTopDiff, long hTopData, long hBottomDiff);
template long Math<float>::tanh_bwd(int nCount, long hTopDiff, long hTopData, long hBottomDiff);


template<typename T>
__global__ void sigmoid_fwd_kernel(int n, T* in, T* out)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		out[i] = 0.5 * tanh(0.5 * in[i]) + 0.5;
	}
}

template <class T>
long Math<T>::sigmoid_fwd(int n, long hBottomData, long hTopData)
{
	LONG lErr;
	MemoryItem* pBottomData;
	MemoryItem* pTopData;

	if (lErr = m_pMemCol->GetData(hBottomData, &pBottomData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTopData, &pTopData))
		return lErr;

	T* bottom_data = (T*)pBottomData->Data();
	T* top_data = (T*)pTopData->Data();

	sigmoid_fwd_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, bottom_data, top_data);

	return cudaGetLastError();
}

template long Math<double>::sigmoid_fwd(int nCount, long hBottomData, long hTopData);
template long Math<float>::sigmoid_fwd(int nCount, long hBottomData, long hTopData);


template<typename T>
__global__ void sigmoid_bwd_kernel(int n, T* in_diff, T* out_data, T* out_diff)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		T sigmoidx = out_data[i];
		out_diff[i] = in_diff[i] * sigmoidx * (1 - sigmoidx);
	}
}

template <class T>
long Math<T>::sigmoid_bwd(int n, long hTopDiff, long hTopData, long hBottomDiff)
{
	LONG lErr;
	MemoryItem* pTopDiff;
	MemoryItem* pTopData;
	MemoryItem* pBottomDiff;

	if (lErr = m_pMemCol->GetData(hTopDiff, &pTopDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTopData, &pTopData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hBottomDiff, &pBottomDiff))
		return lErr;

	T* top_diff = (T*)pTopDiff->Data();
	T* top_data = (T*)pTopData->Data();
	T* bottom_diff = (T*)pBottomDiff->Data();

	sigmoid_bwd_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, top_diff, top_data, bottom_diff);

	return cudaGetLastError();
}

template long Math<double>::sigmoid_bwd(int nCount, long hTopDiff, long hTopData, long hBottomDiff);
template long Math<float>::sigmoid_bwd(int nCount, long hTopDiff, long hTopData, long hBottomDiff);


template<typename T>
__global__ void relu_fwd_kernel(int n, T* in, T* out, T negative_slope)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		out[i] = (in[i] > 0) ? in[i] : in[i] * negative_slope;
	}
}

template <class T>
long Math<T>::relu_fwd(int n, long hBottomData, long hTopData, T fNegativeSlope)
{
	LONG lErr;
	MemoryItem* pBottomData;
	MemoryItem* pTopData;

	if (lErr = m_pMemCol->GetData(hBottomData, &pBottomData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTopData, &pTopData))
		return lErr;

	T* bottom_data = (T*)pBottomData->Data();
	T* top_data = (T*)pTopData->Data();

	relu_fwd_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, bottom_data, top_data, fNegativeSlope);

	return cudaGetLastError();
}

template long Math<double>::relu_fwd(int nCount, long hBottomData, long hTopData, double fNegativeSlope);
template long Math<float>::relu_fwd(int nCount, long hBottomData, long hTopData, float fNegativeSlope);


template<typename T>
__global__ void relu_bwd_kernel(int n, T* in_diff, T* in_data, T* out_diff, T negative_slope)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		out_diff[i] = in_diff[i] * ((in_data[i] > 0) + (in_data[i] <= 0) * negative_slope);
	}
}

template <class T>
long Math<T>::relu_bwd(int n, long hTopDiff, long hTopData, long hBottomDiff, T fNegativeSlope)
{
	LONG lErr;
	MemoryItem* pTopDiff;
	MemoryItem* pTopData;
	MemoryItem* pBottomDiff;

	if (lErr = m_pMemCol->GetData(hTopDiff, &pTopDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTopData, &pTopData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hBottomDiff, &pBottomDiff))
		return lErr;

	T* top_diff = (T*)pTopDiff->Data();
	T* top_data = (T*)pTopData->Data();
	T* bottom_diff = (T*)pBottomDiff->Data();

	relu_bwd_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, top_diff, top_data, bottom_diff, fNegativeSlope);

	return cudaGetLastError();
}

template long Math<double>::relu_bwd(int nCount, long hTopDiff, long hTopData, long hBottomDiff, double dfNegativeSlope);
template long Math<float>::relu_bwd(int nCount, long hTopDiff, long hTopData, long hBottomDiff, float fNegativeSlope);




template<typename T>
__global__ void elu_fwd_kernel(int n, T* in, T* out, T alpha)
{
	for (int i = blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		out[i] = (in[i] > 0) ? in[i] :  alpha * (exp(in[i]) - 1);
	}
}

template <class T>
long Math<T>::elu_fwd(int n, long hBottomData, long hTopData, T fAlpha)
{
	LONG lErr;
	MemoryItem* pBottomData;
	MemoryItem* pTopData;

	if (lErr = m_pMemCol->GetData(hBottomData, &pBottomData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTopData, &pTopData))
		return lErr;

	T* bottom_data = (T*)pBottomData->Data();
	T* top_data = (T*)pTopData->Data();

	elu_fwd_kernel<T> << <CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS >> >(n, bottom_data, top_data, fAlpha);

	return cudaGetLastError();
}

template long Math<double>::elu_fwd(int nCount, long hBottomData, long hTopData, double fAlpha);
template long Math<float>::elu_fwd(int nCount, long hBottomData, long hTopData, float fAlpha);


template<typename T>
__global__ void elu_bwd_kernel(int n, T* in_diff, T* out_data, T* in_data, T* out_diff, T alpha)
{
	for (int i = blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		out_diff[i] = in_data[i] > 0 ? in_diff[i] : in_diff[i] * (out_data[i] + alpha);
	}
}

template <class T>
long Math<T>::elu_bwd(int n, long hTopDiff, long hTopData, long hBottomData, long hBottomDiff, T fAlpha)
{
	LONG lErr;
	MemoryItem* pTopDiff;
	MemoryItem* pTopData;
	MemoryItem* pBottomData;
	MemoryItem* pBottomDiff;

	if (lErr = m_pMemCol->GetData(hTopDiff, &pTopDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTopData, &pTopData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hBottomData, &pBottomData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hBottomDiff, &pBottomDiff))
		return lErr;

	T* top_diff = (T*)pTopDiff->Data();
	T* top_data = (T*)pTopData->Data();
	T* bottom_data = (T*)pBottomData->Data();
	T* bottom_diff = (T*)pBottomDiff->Data();

	elu_bwd_kernel<T> << <CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS >> >(n, top_diff, top_data, bottom_data, bottom_diff, fAlpha);

	return cudaGetLastError();
}

template long Math<double>::elu_bwd(int nCount, long hTopDiff, long hTopData, long hBottomData, long hBottomDiff, double fAlpha);
template long Math<float>::elu_bwd(int nCount, long hTopDiff, long hTopData, long hBottomData, long hBottomDiff, float fAlpha);


template<typename T>
__global__ void dropout_fwd_kernel(int n, T* in, T* mask, unsigned int uiThreshold, T fScale, T* out)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		out[i] = in[i] * (mask[i] > uiThreshold) * fScale;
	}
}

template <class T>
long Math<T>::dropout_fwd(int n, long hBottomData, long hMask, unsigned int uiThreshold, T fScale, long hTopData)
{
	LONG lErr;
	MemoryItem* pBottomData;
	MemoryItem* pMask;
	MemoryItem* pTopData;

	if (lErr = m_pMemCol->GetData(hBottomData, &pBottomData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hMask, &pMask))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTopData, &pTopData))
		return lErr;

	T* bottom_data = (T*)pBottomData->Data();
	T* mask = (T*)pMask->Data();
	T* top_data = (T*)pTopData->Data();

	dropout_fwd_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, bottom_data, mask, uiThreshold, fScale, top_data);

	return cudaGetLastError();
}

template long Math<double>::dropout_fwd(int n, long hBottomData, long hMask, unsigned int uiThreshold, double fScale, long hTopData);
template long Math<float>::dropout_fwd(int n, long hBottomData, long hMask, unsigned int uiThreshold, float fScale, long hTopData);


template<typename T>
__global__ void dropout_bwd_kernel(int n, T* in_diff, T* mask, unsigned int uiThreshold, T fScale, T* out_diff)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		out_diff[i] = in_diff[i] * fScale * (mask[i] > uiThreshold);
	}
}

template <class T>
long Math<T>::dropout_bwd(int n, long hTopDiff, long hMask, unsigned int uiThreshold, T fScale, long hBottomDiff)
{
	LONG lErr;
	MemoryItem* pBottomDiff;
	MemoryItem* pMask;
	MemoryItem* pTopDiff;

	if (lErr = m_pMemCol->GetData(hTopDiff, &pTopDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hMask, &pMask))
		return lErr;

	if (lErr = m_pMemCol->GetData(hBottomDiff, &pBottomDiff))
		return lErr;

	T* top_diff = (T*)pTopDiff->Data();
	T* mask = (T*)pMask->Data();
	T* bottom_diff = (T*)pBottomDiff->Data();

	dropout_bwd_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, top_diff, mask, uiThreshold, fScale, bottom_diff);

	return cudaGetLastError();
}

template long Math<double>::dropout_bwd(int n, long hTopDiff, long hMask, unsigned int uiThreshold, double fScale, long hBottomDiff);
template long Math<float>::dropout_bwd(int n, long hTopDiff, long hMask, unsigned int uiThreshold, float fScale, long hBottomDiff);


template<typename T>
__global__ void bnll_fwd_kernel(int n, T* in, T* out)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		out[i] = (in[i] > 0) ?
			         in[i] + log(1. + exp(-in[i])) :
		             log(1. + exp(in[i]));
	}
}

template <class T>
long Math<T>::bnll_fwd(int n, long hBottomData, long hTopData)
{
	LONG lErr;
	MemoryItem* pBottomData;
	MemoryItem* pTopData;

	if (lErr = m_pMemCol->GetData(hBottomData, &pBottomData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTopData, &pTopData))
		return lErr;

	T* bottom_data = (T*)pBottomData->Data();
	T* top_data = (T*)pTopData->Data();

	bnll_fwd_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, bottom_data, top_data);

	return cudaGetLastError();
}

template long Math<double>::bnll_fwd(int nCount, long hBottomData, long hTopData);
template long Math<float>::bnll_fwd(int nCount, long hBottomData, long hTopData);


template<typename T>
__global__ void bnll_bwd_kernel(int n, T* in_diff, T* in_data, T* out_diff)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		T expval = exp(min(in_data[i], 50.));	// 50 = kBNLL_THRESHOLD
		out_diff[i] = in_diff[i] * expval / (expval + 1.);
	}
}

template <class T>
long Math<T>::bnll_bwd(int n, long hTopDiff, long hBottomData, long hBottomDiff)
{
	LONG lErr;
	MemoryItem* pTopDiff;
	MemoryItem* pBottomData;
	MemoryItem* pBottomDiff;

	if (lErr = m_pMemCol->GetData(hTopDiff, &pTopDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hBottomData, &pBottomData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hBottomDiff, &pBottomDiff))
		return lErr;

	T* top_diff = (T*)pTopDiff->Data();
	T* bottom_data = (T*)pBottomData->Data();
	T* bottom_diff = (T*)pBottomDiff->Data();

	bnll_bwd_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, top_diff, bottom_data, bottom_diff);

	return cudaGetLastError();
}

template long Math<double>::bnll_bwd(int nCount, long hTopDiff, long hBottomData, long hBottomDiff);
template long Math<float>::bnll_bwd(int nCount, long hTopDiff, long hBottomData, long hBottomDiff);


template<typename T>
__global__ void prelu_fwd_kernel(int n, int channels, int dim, T* in, T* out, T* slope_data, int div_factor)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		int c = (i / dim) % channels / div_factor;
		out[i] = (in[i] > 0) ? in[i] : in[i] * slope_data[c];
	}
}

template <class T>
long Math<T>::prelu_fwd(int n, int nChannels, int nDim, long hBottomData, long hTopData, long hSlopeData, int nDivFactor)
{
	LONG lErr;
	MemoryItem* pBottomData;
	MemoryItem* pTopData;
	MemoryItem* pSlopeData;

	if (lErr = m_pMemCol->GetData(hBottomData, &pBottomData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTopData, &pTopData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hSlopeData, &pSlopeData))
		return lErr;

	T* bottom_data = (T*)pBottomData->Data();
	T* top_data = (T*)pTopData->Data();
	T* slope_data = (T*)pSlopeData->Data();

	prelu_fwd_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, nChannels, nDim, bottom_data, top_data, slope_data, nDivFactor);

	return cudaGetLastError();
}

template long Math<double>::prelu_fwd(int nCount, int nChannels, int nDim, long hBottomData, long hTopData, long hSlopeData, int nDivFactor);
template long Math<float>::prelu_fwd(int nCount, int nChannels, int nDim, long hBottomData, long hTopData, long hSlopeData, int nDivFactor);


template<typename T>
__global__ void prelu_bwd_kernel(int n, int channels, int dim, T* in_diff, T* in_data, T* out_diff, T* slope_data, int div_factor)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		int c = (i / dim) % channels / div_factor;
		out_diff[i] = in_diff[i] * ((in_data[i] > 0) + (in_data[i] <= 0) * slope_data[c]);
	}
}

template <class T>
long Math<T>::prelu_bwd(int n, int nChannels, int nDim, long hTopDiff, long hBottomData, long hBottomDiff, long hSlopeData, int nDivFactor)
{
	LONG lErr;
	MemoryItem* pTopDiff;
	MemoryItem* pBottomData;
	MemoryItem* pBottomDiff;
	MemoryItem* pSlopeData;

	if (lErr = m_pMemCol->GetData(hTopDiff, &pTopDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hBottomData, &pBottomData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hBottomDiff, &pBottomDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hSlopeData, &pSlopeData))
		return lErr;

	T* top_diff = (T*)pTopDiff->Data();
	T* bottom_data = (T*)pBottomData->Data();
	T* bottom_diff = (T*)pBottomDiff->Data();
	T* slope_data = (T*)pSlopeData->Data();

	prelu_bwd_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, nChannels, nDim, top_diff, bottom_data, bottom_diff, slope_data, nDivFactor);

	return cudaGetLastError();
}

template long Math<double>::prelu_bwd(int nCount, int nChannels, int nDim, long hTOpDiff, long hBottomData, long hBottomDiff, long hSlopeData, int nDivFactor);
template long Math<float>::prelu_bwd(int nCount, int nChannels, int nDim, long hTOpDiff, long hBottomData, long hBottomDiff, long hSlopeData, int nDivFactor);


template<typename T>
__global__ void prelu_bwd_param_kernel(int n, int rows, int rowPitch, T* in_diff, T* in_data, T* out_diff)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		out_diff[i] = in_diff[i] * in_data[i] * (in_data[i] <= 0);
		
		for (int k=1; k<rows; k++)
		{
			int nIdx = i + k*rowPitch;
			out_diff[i] += in_diff[nIdx] * in_data[nIdx] * (in_data[nIdx] <= 0);
		}
	}
}

template <class T>
long Math<T>::prelu_bwd_param(int n, int nNum, int nTopOffset, long hTopDiff, long hBottomData, long hBackBuffDiff)
{
	LONG lErr;
	MemoryItem* pTopDiff;
	MemoryItem* pBottomData;
	MemoryItem* pBuffDiff;

	if (lErr = m_pMemCol->GetData(hTopDiff, &pTopDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hBottomData, &pBottomData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hBackBuffDiff, &pBuffDiff))
		return lErr;

	T* top_diff = (T*)pTopDiff->Data();
	T* bottom_data = (T*)pBottomData->Data();
	T* buff_diff = (T*)pBuffDiff->Data();

	prelu_bwd_param_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, nNum, nTopOffset, top_diff, bottom_data, buff_diff);

	return cudaGetLastError();
}

template long Math<double>::prelu_bwd_param(int n, int nNum, int nTopOffset, long hTopDiff, long hBottomData, long hBackBuffDiff);
template long Math<float>::prelu_bwd_param(int n, int nNum, int nTopOffset, long hTopDiff, long hBottomData, long hBackBuffDiff);


template<typename T>
__global__ void softmaxloss_fwd_param_kernel(int nthreads, const T* prob_data, const T* label, T* loss, int num, int dim, int spatial_dim, T* counts)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<nthreads; i += blockDim.x * gridDim.x)
	{
		int n = i / spatial_dim;
		int s = i % spatial_dim;
		int label_value = (int)label[n * spatial_dim + s];

		loss[i] = -log(max(prob_data[n * dim + label_value * spatial_dim + s], (T)FLT_MIN));
		counts[i] = 1;
	}
}

template<typename T>
__global__ void softmaxloss_fwd_param_kernel1(int nthreads, const T* prob_data, const T* label, T* loss, int num, int dim, int spatial_dim, T* counts, int nIgnoreLabel)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<nthreads; i += blockDim.x * gridDim.x)
	{
		int n = i / spatial_dim;
		int s = i % spatial_dim;
		int label_value = (int)label[n * spatial_dim + s];

		if (label_value == nIgnoreLabel)
		{
			loss[i] = 0;
			counts[i] = 0;
		}
		else
		{
			loss[i] = -log(max(prob_data[n * dim + label_value * spatial_dim + s], (T)FLT_MIN));
			counts[i] = 1;
		}
	}
}

template <class T> 
long Math<T>::softmaxloss_fwd(int n, long hProbData, long hLabels, long hLossData, int nOuterNum, int nDim, int nInnerNum, long hCounts, int nIgnoreLabel)
{
	LONG lErr;
	MemoryItem* pProbData;
	MemoryItem* pLabels;
	MemoryItem* pLossData;
	MemoryItem* pCounts;

	if (lErr = m_pMemCol->GetData(hProbData, &pProbData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hLabels, &pLabels))
		return lErr;

	if (lErr = m_pMemCol->GetData(hLossData, &pLossData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hCounts, &pCounts))
		return lErr;

	T* prob_data = (T*)pProbData->Data();
	T* labels = (T*)pLabels->Data();
	T* loss_data = (T*)pLossData->Data();
	T* counts = (T*)pCounts->Data();

	if (nIgnoreLabel == -1)
		softmaxloss_fwd_param_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, prob_data, labels, loss_data, nOuterNum, nDim, nInnerNum, counts);
	else
		softmaxloss_fwd_param_kernel1<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, prob_data, labels, loss_data, nOuterNum, nDim, nInnerNum, counts, nIgnoreLabel);

	return cudaGetLastError();
}

template long Math<double>::softmaxloss_fwd(int n, long hProbData, long hLabels, long hLossData, int nOuterNum, int nDim, int nInnerNum, long hCounts, int nIgnoreLabel);
template long Math<float>::softmaxloss_fwd(int n, long hProbData, long hLabels, long hLossData, int nOuterNum, int nDim, int nInnerNum, long hCounts, int nIgnoreLabel);


template<typename T>
__global__ void softmaxloss_bwd_param_kernel(int nthreads, const T* top, const T* label, T* bottom_diff, int num, int dim, int spatial_dim, T* counts)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<nthreads; i += blockDim.x * gridDim.x)
	{
		int n = i / spatial_dim;
		int s = i % spatial_dim;
		int label_value = (int)label[n * spatial_dim + s];

		bottom_diff[n * dim + label_value * spatial_dim + s] -= 1;
		counts[i] = 1;
	}
}

template<typename T>
__global__ void softmaxloss_bwd_param_kernel1(int nthreads, const T* top, const T* label, T* bottom_diff, int num, int dim, int spatial_dim, T* counts, int nIgnoreLabel)
{
	int channels = dim / spatial_dim;

	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<nthreads; i += blockDim.x * gridDim.x)
	{
		int n = i / spatial_dim;
		int s = i % spatial_dim;
		int label_value = (int)label[n * spatial_dim + s];

		if (label_value == nIgnoreLabel)
		{
			for (int c=0; c<channels; c++)
			{
				bottom_diff[n * dim + c * spatial_dim + s] = 0;
			}

			counts[i] = 0;
		}
		else
		{
			bottom_diff[n * dim + label_value * spatial_dim + s] -= 1;
			counts[i] = 1;
		}
	}
}

template <class T> 
long Math<T>::softmaxloss_bwd(int n, long hTopData, long hLabels, long hBottomDiff, int nOuterNum, int nDim, int nInnerNum, long hCounts, int nIgnoreLabel)
{
	LONG lErr;
	MemoryItem* pTopData;
	MemoryItem* pLabels;
	MemoryItem* pBottomDiff;
	MemoryItem* pCounts;

	if (lErr = m_pMemCol->GetData(hTopData, &pTopData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hLabels, &pLabels))
		return lErr;

	if (lErr = m_pMemCol->GetData(hBottomDiff, &pBottomDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hCounts, &pCounts))
		return lErr;

	T* top_data = (T*)pTopData->Data();
	T* labels = (T*)pLabels->Data();
	T* bottom_diff = (T*)pBottomDiff->Data();
	T* counts = (T*)pCounts->Data();

	if (nIgnoreLabel == -1)
		softmaxloss_bwd_param_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, top_data, labels, bottom_diff, nOuterNum, nDim, nInnerNum, counts);
	else
		softmaxloss_bwd_param_kernel1<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, top_data, labels, bottom_diff, nOuterNum, nDim, nInnerNum, counts, nIgnoreLabel);

	return cudaGetLastError();
}

template long Math<double>::softmaxloss_bwd(int n, long hTopData, long hLabels, long hBottomDiff, int nOuterNum, int nDim, int nInnerNum, long hCounts, int nIgnoreLabel);
template long Math<float>::softmaxloss_bwd(int n, long hTopData, long hLabels, long hBottomDiff, int nOuterNum, int nDim, int nInnerNum, long hCounts, int nIgnoreLabel);


template<typename T>
__global__ void max_fwd_kernel(int nthreads, const T* bottom_data_a, const T* bottom_data_b, int blob_idx, T* top_data, T* mask)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<nthreads; i += blockDim.x * gridDim.x)
	{
		T maxval = -FLT_MAX;
		int maxidx = -1;

		if (bottom_data_a[i] > bottom_data_b[i])
		{
			// only update for very first bottom_data blob (blob_idx == 0)
			if (blob_idx == 0)
			{
				maxval = bottom_data_a[i];
				top_data[i] = maxval;
				maxidx = blob_idx;
				mask[i] = maxidx;
			}
		}
		else
		{
			maxval = bottom_data_b[i];
			top_data[i] = maxval;
			maxidx = blob_idx + 1;
			mask[i] = maxidx;
		}
	}
}

template <class T>
long Math<T>::max_fwd(int n, long hA, long hB, int nIdx, long hY, long hMask)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pB;
	MemoryItem* pY;
	MemoryItem* pMask;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hB, &pB))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	if (lErr = m_pMemCol->GetData(hMask, &pMask))
		return lErr;

	T* a = (T*)pA->Data();
	T* b = (T*)pB->Data();
	T* y = (T*)pY->Data();
	T* mask = (T*)pMask->Data();

	max_fwd_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, a, b, nIdx, y, mask);

	return cudaGetLastError();
}

template long Math<double>::max_fwd(int n, long hA, long hB, int nIdx, long hY, long hMask);
template long Math<float>::max_fwd(int n, long hA, long hB, int nIdx, long hY, long hMask);



template<typename T>
__global__ void max_bwd_kernel(int nthreads, const T* top_diff, int blob_idx, T* mask, T* bottom_diff)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<nthreads; i += blockDim.x * gridDim.x)
	{
		T gradient = 0;

		if (mask[i] == blob_idx)
			gradient += top_diff[i];
		
		bottom_diff[i] = gradient;
	}
}

template <class T>
long Math<T>::max_bwd(int n, long hX, int nIdx, long hMask, long hY)
{
	LONG lErr;
	MemoryItem* pX;
	MemoryItem* pY;
	MemoryItem* pMask;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	if (lErr = m_pMemCol->GetData(hMask, &pMask))
		return lErr;

	T* x = (T*)pX->Data();
	T* y = (T*)pY->Data();
	T* mask = (T*)pMask->Data();

	max_bwd_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, x, nIdx, mask, y);

	return cudaGetLastError();
}

template long Math<double>::max_bwd(int n, long hX, int nIdx, long hMask, long hY);
template long Math<float>::max_bwd(int n, long hX, int nIdx, long hMask, long hY);


template <typename T>
__device__ int compute_uncropped_index(int index, const int ndims, const T* src_strides, const T* dst_strides, const T* offsets)
{
	int dst_index = index;
	int src_index = 0;
	
	for (int i = 0; i < ndims; i++)
	{
		int coord = dst_index / (int)dst_strides[i];
		dst_index -= coord * (int)dst_strides[i];
		src_index += (int)src_strides[i] * (coord + (int)offsets[i]);
	}

	return src_index;
}

template <typename T>
__global__ void crop_fwd_kernel(const int n, const int ndims, const T* src_strides, const T* dst_strides, const T* offsets, const T* src, T* dst)
{
	for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < n; i += blockDim.x * gridDim.x)
	{
		int src_index = compute_uncropped_index(i, ndims, src_strides, dst_strides, offsets);
		dst[i] = src[src_index];
	}
}

template <class T>
long Math<T>::crop_fwd(int nCount, int nNumAxes, long hSrcStrides, long hDstStrides, long hOffsets, long hBottomData, long hTopData)
{
	LONG lErr;
	MemoryItem* pSrcStrides;
	MemoryItem* pDstStrides;
	MemoryItem* pOffsets;
	MemoryItem* pBottomData;
	MemoryItem* pTopData;

	if (lErr = m_pMemCol->GetData(hSrcStrides, &pSrcStrides))
		return lErr;

	if (lErr = m_pMemCol->GetData(hDstStrides, &pDstStrides))
		return lErr;

	if (lErr = m_pMemCol->GetData(hOffsets, &pOffsets))
		return lErr;

	if (lErr = m_pMemCol->GetData(hBottomData, &pBottomData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTopData, &pTopData))
		return lErr;

	T* srcStrides = (T*)pSrcStrides->Data();
	T* dstStrides = (T*)pDstStrides->Data();
	T* offsets = (T*)pOffsets->Data();
	T* bottom_data = (T*)pBottomData->Data();
	T* top_data = (T*)pTopData->Data();

	crop_fwd_kernel<T><<<CAFFE_GET_BLOCKS(nCount), CAFFE_CUDA_NUM_THREADS>>>(nCount, nNumAxes, srcStrides, dstStrides, offsets, bottom_data, top_data);

	return cudaGetLastError();
}

template long Math<double>::crop_fwd(int nCount, int nNumAxes, long hSrcStrides, long hDstStrides, long hOffsets, long hBottomData, long hTopData);
template long Math<float>::crop_fwd(int nCount, int nNumAxes, long hSrcStrides, long hDstStrides, long hOffsets, long hBottomData, long hTopData);


template <typename T>
__global__ void crop_bwd_kernel(const int n, const int ndims, const T* src_strides, const T* dst_strides, const T* offsets, T* src, const T* dst)
{
	for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < n; i += blockDim.x * gridDim.x)
	{
		int src_index = compute_uncropped_index(i, ndims, src_strides, dst_strides, offsets);
		src[src_index] = dst[i];
	}
}

template <class T>
long Math<T>::crop_bwd(int nCount, int nNumAxes, long hSrcStrides, long hDstStrides, long hOffsets, long hBottomDiff, long hTopDiff)
{
	LONG lErr;
	MemoryItem* pSrcStrides;
	MemoryItem* pDstStrides;
	MemoryItem* pOffsets;
	MemoryItem* pBottomDiff;
	MemoryItem* pTopDiff;

	if (lErr = m_pMemCol->GetData(hSrcStrides, &pSrcStrides))
		return lErr;

	if (lErr = m_pMemCol->GetData(hDstStrides, &pDstStrides))
		return lErr;

	if (lErr = m_pMemCol->GetData(hOffsets, &pOffsets))
		return lErr;

	if (lErr = m_pMemCol->GetData(hBottomDiff, &pBottomDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTopDiff, &pTopDiff))
		return lErr;

	T* srcStrides = (T*)pSrcStrides->Data();
	T* dstStrides = (T*)pDstStrides->Data();
	T* offsets = (T*)pOffsets->Data();
	T* bottom_diff = (T*)pBottomDiff->Data();
	T* top_diff = (T*)pTopDiff->Data();

	crop_bwd_kernel<T><<<CAFFE_GET_BLOCKS(nCount), CAFFE_CUDA_NUM_THREADS>>>(nCount, nNumAxes, srcStrides, dstStrides, offsets, bottom_diff, top_diff);

	return cudaGetLastError();
}

template long Math<double>::crop_bwd(int nCount, int nNumAxes, long hSrcStrides, long hDstStrides, long hOffsets, long hBottomDiff, long hTopDiff);
template long Math<float>::crop_bwd(int nCount, int nNumAxes, long hSrcStrides, long hDstStrides, long hOffsets, long hBottomDiff, long hTopDiff);


template<typename T>
__global__ void concat_fwd_kernel(int nthreads, const T* in_data, int num_concats, int concat_size, int top_concat_axis, int bottom_concat_axis, int offset_concat_axis, T* out_data)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<nthreads; i += blockDim.x * gridDim.x)
	{
		int total_concat_size = concat_size * bottom_concat_axis;
		int concat_num = i / total_concat_size;
		int concat_index = i % total_concat_size;
		int top_index = concat_index + (concat_num * top_concat_axis + offset_concat_axis) * concat_size;
		
		out_data[top_index] = in_data[i];
	}
}

template <class T> 
long Math<T>::concat_fwd(int n, long hBottomData, int nNumConcats, int nConcatInputSize, int nTopConcatAxis, int nBottomConcatAxis, int nOffsetConcatAxis, long hTopData)
{
	LONG lErr;
	MemoryItem* pBottomData;
	MemoryItem* pTopData;

	if (lErr = m_pMemCol->GetData(hBottomData, &pBottomData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTopData, &pTopData))
		return lErr;

	T* bottom_data = (T*)pBottomData->Data();
	T* top_data = (T*)pTopData->Data();

	concat_fwd_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, bottom_data, nNumConcats, nConcatInputSize, nTopConcatAxis, nBottomConcatAxis, nOffsetConcatAxis, top_data);

	return cudaGetLastError();
}


template long Math<double>::concat_fwd(int n, long hBottomData, int nNumConcats, int nConcatInputSize, int nTopConcatAxis, int nBottomConcatAxis, int nOffsetConcatAxis, long hTopData);
template long Math<float>::concat_fwd(int n, long hBottomData, int nNumConcats, int nConcatInputSize, int nTopConcatAxis, int nBottomConcatAxis, int nOffsetConcatAxis, long hTopData);


template<typename T>
__global__ void concat_bwd_kernel(int nthreads, const T* in_data, int num_concats, int concat_size, int top_concat_axis, int bottom_concat_axis, int offset_concat_axis, T* out_data)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<nthreads; i += blockDim.x * gridDim.x)
	{
		int total_concat_size = concat_size * bottom_concat_axis;
		int concat_num = i / total_concat_size;
		int concat_index = i % total_concat_size;
		int top_index = concat_index + (concat_num * top_concat_axis + offset_concat_axis) * concat_size;
		
		out_data[i] = in_data[top_index];
	}
}

template <class T> 
long Math<T>::concat_bwd(int n, long hTopDiff, int nNumConcats, int nConcatInputSize, int nTopConcatAxis, int nBottomConcatAxis, int nOffsetConcatAxis, long hBottomDiff)
{
	LONG lErr;
	MemoryItem* pBottomDiff;
	MemoryItem* pTopDiff;

	if (lErr = m_pMemCol->GetData(hTopDiff, &pTopDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hBottomDiff, &pBottomDiff))
		return lErr;

	T* top_diff = (T*)pTopDiff->Data();
	T* bottom_diff = (T*)pBottomDiff->Data();

	concat_bwd_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, top_diff, nNumConcats, nConcatInputSize, nTopConcatAxis, nBottomConcatAxis, nOffsetConcatAxis, bottom_diff);

	return cudaGetLastError();
}

template long Math<double>::concat_bwd(int n, long hTopDiff, int nNumConcats, int nConcatInputSize, int nTopConcatAxis, int nBottomConcatAxis, int nOffsetConcatAxis, long hBottomDiff);		 
template long Math<float>::concat_bwd(int n, long hTopDiff, int nNumConcats, int nConcatInputSize, int nTopConcatAxis, int nBottomConcatAxis, int nOffsetConcatAxis, long hBottomDiff);


template<typename T>
__global__ void slice_fwd_kernel(int nthreads, const T* in_data, int num_slices, int slice_size, int bottom_slice_axis, int top_slice_axis, int offset_slice_axis, T* out_data)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<nthreads; i += blockDim.x * gridDim.x)
	{
		int total_slice_size = slice_size * top_slice_axis;
		int slice_num = i / total_slice_size;
		int slice_index = i % total_slice_size;
		int bottom_index = slice_index + (slice_num * bottom_slice_axis + offset_slice_axis) * slice_size;
		
		out_data[i] = in_data[bottom_index];
	}
}

template <class T> 
long Math<T>::slice_fwd(int n, long hBottomData, int nNumSlices, int nSliceInputSize, int nBottomSliceAxis, int nTopSliceAxis, int nOffsetSliceAxis, long hTopData)
{
	LONG lErr;
	MemoryItem* pBottomData;
	MemoryItem* pTopData;

	if (lErr = m_pMemCol->GetData(hBottomData, &pBottomData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTopData, &pTopData))
		return lErr;

	T* bottom_data = (T*)pBottomData->Data();
	T* top_data = (T*)pTopData->Data();

	slice_fwd_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, bottom_data, nNumSlices, nSliceInputSize, nBottomSliceAxis, nTopSliceAxis, nOffsetSliceAxis, top_data);

	return cudaGetLastError();
}

template long Math<double>::slice_fwd(int n, long hBottomData, int nNumSlices, int nSliceInputSize, int nBottomSliceAxis, int nTopSliceAxis, int nOffsetSliceAxis, long hTopData);
template long Math<float>::slice_fwd(int n, long hBottomData, int nNumSlices, int nSliceInputSize, int nBottomSliceAxis, int nTopSliceAxis, int nOffsetSliceAxis, long hTopData);


template <typename T>
__global__ void slice_bwd_kernel(int nthreads, const T* in_data, int num_slices, int slice_size, int bottom_slice_axis, int top_slice_axis, int offset_slice_axis, T* out_data)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<nthreads; i += blockDim.x * gridDim.x)
	{
		int total_slice_size = slice_size * top_slice_axis;
		int slice_num = i / total_slice_size;
		int slice_index = i % total_slice_size;
		int bottom_index = slice_index + (slice_num * bottom_slice_axis + offset_slice_axis) * slice_size;
		
		out_data[bottom_index] = in_data[i];
	}
}

template <class T> 
long Math<T>::slice_bwd(int n, long hTopDiff, int nNumSlices, int nSliceInputSize, int nBottomSliceAxis, int nTopSliceAxis, int nOffsetSliceAxis, long hBottomDiff)
{
	LONG lErr;
	MemoryItem* pBottomDiff;
	MemoryItem* pTopDiff;

	if (lErr = m_pMemCol->GetData(hTopDiff, &pTopDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hBottomDiff, &pBottomDiff))
		return lErr;

	T* top_diff = (T*)pTopDiff->Data();
	T* bottom_diff = (T*)pBottomDiff->Data();

	slice_bwd_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, top_diff, nNumSlices, nSliceInputSize, nBottomSliceAxis, nTopSliceAxis, nOffsetSliceAxis, bottom_diff);

	return cudaGetLastError();
}

template long Math<double>::slice_bwd(int n, long hTopDiff, int nNumSlices, int nSliceInputSize, int nBottomSliceAxis, int nTopSliceAxis, int nOffsetSliceAxis, long hBottomDiff);
template long Math<float>::slice_bwd(int n, long hTopDiff, int nNumSlices, int nSliceInputSize, int nBottomSliceAxis, int nTopSliceAxis, int nOffsetSliceAxis, long hBottomDiff);


template<typename T>
__global__ void tile_fwd_kernel(int nthreads, const T* bottom_data, int tile_size, int num_tiles, int bottom_tile_axis, T* top_data)
{
	for (int i = blockIdx.x * blockDim.x + threadIdx.x; i<nthreads; i += blockDim.x * gridDim.x)
	{
		const int d = i % tile_size;
		const int b = (i / tile_size / num_tiles) % bottom_tile_axis;
		const int n = i / tile_size / num_tiles / bottom_tile_axis;
		const int bottom_index = (n * bottom_tile_axis + b) * tile_size + d;
		top_data[i] = bottom_data[bottom_index];
	}
}

template <class T>
long Math<T>::tile_fwd(int n, long hBottomData, int nInnerDim, int nTiles, int nBottomTileAxis, long hTopData)
{
	LONG lErr;
	MemoryItem* pBottomData;
	MemoryItem* pTopData;

	if (lErr = m_pMemCol->GetData(hBottomData, &pBottomData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTopData, &pTopData))
		return lErr;

	T* bottom_data = (T*)pBottomData->Data();
	T* top_data = (T*)pTopData->Data();

	tile_fwd_kernel<T> << <CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS >> >(n, bottom_data, nInnerDim, nTiles, nBottomTileAxis, top_data);

	return cudaGetLastError();
}

template long Math<double>::tile_fwd(int n, long hBottomData, int nInnerDim, int nTiles, int nBottomTileAxis, long hTopData);
template long Math<float>::tile_fwd(int n, long hBottomData, int nInnerDim, int nTiles, int nBottomTileAxis, long hTopData);


template <typename T>
__global__ void tile_bwd_kernel(int nthreads, const T* top_diff, int tile_size, int num_tiles, int bottom_tile_axis, T* bottom_diff)
{
	for (int i = blockIdx.x * blockDim.x + threadIdx.x; i<nthreads; i += blockDim.x * gridDim.x)
	{
		const int d = i % tile_size;
		const int b = (i / tile_size) % bottom_tile_axis;
		const int n = i / tile_size / bottom_tile_axis;
		bottom_diff[i] = 0;
		int top_index = (n * num_tiles * bottom_tile_axis + b) * tile_size + d;
		
		for (int t = 0; t < num_tiles; t++)
		{
			bottom_diff[i] += top_diff[top_index];
			top_index += bottom_tile_axis * tile_size;
		}
	}
}

template <class T>
long Math<T>::tile_bwd(int n, long hTopDiff, int nTileSize, int nTiles, int nBottomTileAxis, long hBottomDiff)
{
	LONG lErr;
	MemoryItem* pBottomDiff;
	MemoryItem* pTopDiff;

	if (lErr = m_pMemCol->GetData(hTopDiff, &pTopDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hBottomDiff, &pBottomDiff))
		return lErr;

	T* top_diff = (T*)pTopDiff->Data();
	T* bottom_diff = (T*)pBottomDiff->Data();

	tile_bwd_kernel<T> << <CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS >> >(n, top_diff, nTileSize, nTiles, nBottomTileAxis, bottom_diff);

	return cudaGetLastError();
}

template long Math<double>::tile_bwd(int n, long hTopDiff, int nTileSize, int nTiles, int nBottomTileAxis, long hBottomDiff);
template long Math<float>::tile_bwd(int n, long hTopDiff, int nTileSize, int nTiles, int nBottomTileAxis, long hBottomDiff);


template <typename T>
__global__ void bias_fwd_kernel(int n, const T* in, const T* bias, int bias_dim, int inner_dim, T* out)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		int bias_index = (i / inner_dim) % bias_dim;
		out[i] = in[i] + bias[bias_index];
	}
}

template <class T>
long Math<T>::bias_fwd(int n, long hBottomData, long hBiasData, int nBiasDim, int nInnerDim, long hTopData)
{
	LONG lErr;
	MemoryItem* pBottomData;
	MemoryItem* pBiasData;
	MemoryItem* pTopData;

	if (lErr = m_pMemCol->GetData(hBottomData, &pBottomData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hBiasData, &pBiasData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTopData, &pTopData))
		return lErr;

	T* bottom_data = (T*)pBottomData->Data();
	T* bias_data = (T*)pBiasData->Data();
	T* top_data = (T*)pTopData->Data();

	bias_fwd_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, bottom_data, bias_data, nBiasDim, nInnerDim, top_data);

	return cudaGetLastError();
}

template long Math<double>::bias_fwd(int n, long hBottomData, long hBiasData, int nBiasDim, int nInnerDim, long hTopData);
template long Math<float>::bias_fwd(int n, long hBottomData, long hBiasData, int nBiasDim, int nInnerDim, long hTopData);


template <typename T>
__global__ void scale_fwd_kernel(int n, const T* in, const T* scale, int scale_dim, int inner_dim, T* out)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		int scale_index = (i / inner_dim) % scale_dim;
		out[i] = in[i] * scale[scale_index];
	}
}

template <typename T>
__global__ void scale_fwd_bias_kernel(int n, const T* in, const T* scale, const T* bias, int scale_dim, int inner_dim, T* out)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		int scale_index = (i / inner_dim) % scale_dim;
		out[i] = in[i] * scale[scale_index] + bias[scale_index];
	}
}

template <class T>
long Math<T>::scale_fwd(int n, long hX, long hScaleData, int nScaleDim, int nInnerDim, long hY, long hBiasData)
{
	LONG lErr;
	MemoryItem* pX;
	MemoryItem* pScaleData;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hScaleData, &pScaleData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	T* x = (T*)pX->Data();
	T* scale_data = (T*)pScaleData->Data();
	T* y = (T*)pY->Data();
	
	if (hBiasData == 0)
	{
		scale_fwd_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, x, scale_data, nScaleDim, nInnerDim, y);
	}
	else
	{
		MemoryItem* pBiasData = NULL;

		if (lErr = m_pMemCol->GetData(hBiasData, &pBiasData))
			return lErr;

		T* bias_data = (T*)pBiasData->Data();

		scale_fwd_bias_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, x, scale_data, bias_data, nScaleDim, nInnerDim, y);
	}

	return cudaGetLastError();
}

template long Math<double>::scale_fwd(int n, long hX, long hScaleData, int nScaleDim, int nInnerDim, long hY, long hBiasData);
template long Math<float>::scale_fwd(int n, long hX, long hScaleData, int nScaleDim, int nInnerDim, long hY, long hBiasData);


template <typename T>
__global__ void threshold_fwd_kernel(int n, const T threshold, const T* in, T* out)
{
	for (int i = blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		out[i] = in[i] > threshold ? 1 : 0;
	}
}

template <class T>
long Math<T>::threshold_fwd(int n, T fThreshold, long hX, long hY)
{
	LONG lErr;
	MemoryItem* pX;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	T* x = (T*)pX->Data();
	T* y = (T*)pY->Data();

	threshold_fwd_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, fThreshold, x, y);

	return cudaGetLastError();
}

template long Math<double>::threshold_fwd(int n, double dfThreshold, long hX, long hY);
template long Math<float>::threshold_fwd(int n, float dfThreshold, long hX, long hY);


template <typename T>
__global__ void cll_bwd_kernel_legacy(const int nCount, const int nChannels, const T fMargin, const T fAlpha, const T* y, const T* diff, const T* dist_sq, T* btm_diff)
{
	for (int i = blockIdx.x * blockDim.x + threadIdx.x; i<nCount; i += blockDim.x * gridDim.x)
	{
		int n = i / nChannels;	// the num index, to access y and dist_sq

		if ((int)y[n])	// similar pairs
		{
			btm_diff[i] = fAlpha * diff[i];
		}
		else // dissimilar pairs
		{
			T mdist = (fMargin - dist_sq[n]);
			T beta = -fAlpha;

			if (mdist > T(0.0))
				btm_diff[i] = beta;
			else
				btm_diff[i] = T(0.0);
		}
	}
}

template <typename T>
__global__ void cll_bwd_kernel(const int nCount, const int nChannels, const T fMargin, const T fAlpha, const T* y, const T* diff, const T* dist_sq, T* btm_diff)
{
	for (int i = blockIdx.x * blockDim.x + threadIdx.x; i<nCount; i += blockDim.x * gridDim.x)
	{
		int n = i / nChannels;	// the num index, to access y and dist_sq

		if ((int)y[n])	// similar pairs
		{
			btm_diff[i] = fAlpha * diff[i];
		}
		else // dissimilar pairs
		{
			T dist = sqrt(dist_sq[n]);
			T mdist = (fMargin - dist);
			T beta = -fAlpha * mdist / (dist + T(1e-4)) * diff[i];

			if (mdist > T(0.0))
				btm_diff[i] = beta;
			else
				btm_diff[i] = T(0.0);
		}
	}
}

template <class T>
long Math<T>::cll_bwd(int nCount, int nChannels, T fMargin, bool bLegacyVersion, T fAlpha, long hY, long hDiff, long hDistSq, long hBottomDiff)
{
	LONG lErr;
	MemoryItem* pY;
	MemoryItem* pDiff;
	MemoryItem* pDistSq;
	MemoryItem* pBottomDiff;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	if (lErr = m_pMemCol->GetData(hDiff, &pDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hDistSq, &pDistSq))
		return lErr;

	if (lErr = m_pMemCol->GetData(hBottomDiff, &pBottomDiff))
		return lErr;

	T* y = (T*)pY->Data();
	T* diff = (T*)pDiff->Data();
	T* dist_sq = (T*)pDistSq->Data();
	T* btm_diff = (T*)pBottomDiff->Data();

	if (bLegacyVersion)
		cll_bwd_kernel_legacy<T><<<CAFFE_GET_BLOCKS(nCount), CAFFE_CUDA_NUM_THREADS>>>(nCount, nChannels, fMargin, fAlpha, y, diff, dist_sq, btm_diff);
	else
		cll_bwd_kernel<T><<<CAFFE_GET_BLOCKS(nCount), CAFFE_CUDA_NUM_THREADS>>>(nCount, nChannels, fMargin, fAlpha, y, diff, dist_sq, btm_diff);

	return cudaGetLastError();
}

template long Math<double>::cll_bwd(int nCount, int nChannels, double fMargin, bool bLegacyVersion, double fAlpha, long hY, long hDiff, long hDistSq, long hBottomDiff);
template long Math<float>::cll_bwd(int nCount, int nChannels, float fMargin, bool bLegacyVersion, float fAlpha, long hY, long hDiff, long hDistSq, long hBottomDiff);


template <typename T>
__global__ void lrn_fillscale_kernel(int nthreads, const T* in, int num, int channels, int height, int width, int size, T alpha_over_size, T k, T* scale)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<nthreads; i += blockDim.x * gridDim.x)
	{
		// find out the local offset
		int w = i % width;
		int h = (i / width) % height;
		int n = i / width / height;
		int offset = (n * channels * height + h) * width + w;
		int step = height * width;
		const T* const in_off = in + offset;
		T* const scale_off = scale + offset;
		int head = 0;
		int pre_pad = (size - 1) / 2;
		int post_pad = size - pre_pad - 1;
		int idx;
		T accum_scale = 0;

		// fill the scale at [n, :, h, w]
		// accumulate values.
		while (head < post_pad && head < channels)
		{
			idx = head * step;
			accum_scale += in_off[idx] * in_off[idx];
			head++;
		}

		// both add and subtract
		while (head < channels)
		{
			idx = head * step;
			accum_scale += in_off[idx] * in_off[idx];
			if (head - size >= 0)
			{
				idx = (head - size) * step;
				accum_scale -= in_off[idx] * in_off[idx];
			}

			scale_off[(head - post_pad) * step] = k + accum_scale * alpha_over_size;
			head++;
		}

		// subtract only
		while (head < channels + post_pad)
		{
			if (head - size >= 0)
			{
				idx = (head - size) * step;
				accum_scale -= in_off[idx] * in_off[idx];
			}

			scale_off[(head - post_pad) * step] = k + accum_scale * alpha_over_size;
			head++;
		}
	}
}

template <class T> 
long Math<T>::lrn_fillscale(int n, long hBottomData, int nNum, int nChannels, int nHeight, int nWidth, int nSize, T fA, T fB, long hScaleData)
{
	LONG lErr;
	MemoryItem* pBottomData;
	MemoryItem* pScaleData;

	if (lErr = m_pMemCol->GetData(hBottomData, &pBottomData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hScaleData, &pScaleData))
		return lErr;

	T* bottom_data = (T*)pBottomData->Data();
	T* scale_data = (T*)pScaleData->Data();

	lrn_fillscale_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, bottom_data, nNum, nChannels, nHeight, nWidth, nSize, fA, fB, scale_data);

	return cudaGetLastError();
}

template long Math<double>::lrn_fillscale(int n, long hBottomData, int nNum, int nChannels, int nHeight, int nWidth, int nSize, double fA, double fB, long hScaleData);
template long Math<float>::lrn_fillscale(int n, long hBottomData, int nNum, int nChannels, int nHeight, int nWidth, int nSize, float fA, float fB, long hScaleData);


template <typename T>
__global__ void lrn_computeoutput_kernel(int nthreads, const T* in, const T* scale, T negative_beta, T* out)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<nthreads; i += blockDim.x * gridDim.x)
	{
		out[i] = in[i] * pow(scale[i], negative_beta);
	}
}

template <class T> 
long Math<T>::lrn_computeoutput(int n, long hBottomData, long hScaleData, T fA, long hTopData)
{
	LONG lErr;
	MemoryItem* pBottomData;
	MemoryItem* pScaleData;
	MemoryItem* pTopData;

	if (lErr = m_pMemCol->GetData(hBottomData, &pBottomData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hScaleData, &pScaleData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTopData, &pTopData))
		return lErr;

	T* bottom_data = (T*)pBottomData->Data();
	T* scale_data = (T*)pScaleData->Data();
	T* top_data = (T*)pTopData->Data();

	lrn_computeoutput_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, bottom_data, scale_data, fA, top_data);

	return cudaGetLastError();
}

template long Math<double>::lrn_computeoutput(int n, long hBottomData, long hScaleData, double fA, long hTopData);
template long Math<float>::lrn_computeoutput(int n, long hBottomData, long hScaleData, float fA, long hTopData);


template <typename T>
__global__ void lrn_computediff_kernel(int nthreads, const T* bottom_data, const T* top_data, const T* scale, const T* top_diff, int num, int channels, int height, int width, int size, T negative_beta, T cache_ratio, T* bottom_diff)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<nthreads; i += blockDim.x * gridDim.x)
	{
		// find out the local offset
		int w = i % width;
		int h = (i / width) % height;
		int n = i / width / height;
		int offset = (n * channels * height + h) * width + w;
		int step = height * width;
		const T* const bottom_off = bottom_data + offset;
		const T* const top_off = top_data + offset;
		const T* const scale_off = scale + offset;
		const T* const top_diff_off = top_diff + offset;
		T* bottom_diff_off = bottom_diff + offset;
		int head = 0;
		int pre_pad = size - (size + 1) / 2;
		int post_pad = size - pre_pad - 1;
		int idx;
		T accum_ratio = 0;

		// accumulate values.
		while (head < post_pad && head < channels)
		{
			idx = head * step;
			accum_ratio += top_diff_off[idx] * top_off[idx] / scale_off[idx];
			head++;
		}

		// both add and subtract
		while (head < channels)
		{
			idx = head * step;
			accum_ratio += top_diff_off[idx] * top_off[idx] / scale_off[idx];

			if (head - size >= 0)
			{
				idx = (head - size) * step;
				accum_ratio -= top_diff_off[idx] * top_off[idx] / scale_off[idx];
			}

			idx = (head - post_pad) * step;
			bottom_diff_off[idx] = top_diff_off[idx] * pow(scale_off[idx], negative_beta) - cache_ratio * bottom_off[idx] * accum_ratio;
			head++;
		}

		// subtract only
		while (head < channels + post_pad)
		{
			if (head - size >= 0)
			{
				idx = (head - size) * step;
				accum_ratio -= top_diff_off[idx] * top_off[idx] / scale_off[idx];
			}

			idx = (head - post_pad) * step;
			bottom_diff_off[idx] = top_diff_off[idx] * pow(scale_off[idx], negative_beta) - cache_ratio * bottom_off[idx] * accum_ratio;
			head++;
		}
	}
}

template <class T> 
long Math<T>::lrn_computediff(int n, long hBottomData, long hTopData, long hScaleData, long hTopDiff, int nNum, int nChannels, int nHeight, int nWidth, int nSize, T fB, T fA, long hBottomDiff)
{
	LONG lErr;
	MemoryItem* pBottomData;
	MemoryItem* pTopData;
	MemoryItem* pScaleData;
	MemoryItem* pTopDiff;
	MemoryItem* pBottomDiff;

	if (lErr = m_pMemCol->GetData(hBottomData, &pBottomData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTopData, &pTopData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hScaleData, &pScaleData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTopDiff, &pTopDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hBottomDiff, &pBottomDiff))
		return lErr;

	T* bottom_data = (T*)pBottomData->Data();
	T* top_data = (T*)pTopData->Data();
	T* scale_data = (T*)pScaleData->Data();
	T* top_diff = (T*)pTopDiff->Data();
	T* bottom_diff = (T*)pBottomDiff->Data();

	lrn_computediff_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, bottom_data, top_data, scale_data, top_diff, nNum, nChannels, nHeight, nWidth, nSize, fB, fA, bottom_diff);

	return cudaGetLastError();
}

template long Math<double>::lrn_computediff(int n, long hBottomData, long hTopData, long hScaleData, long hTopDiff, int nNum, int nChannels, int nHeight, int nWidth, int nSize, double fB, double fA, long hBottomDiff);
template long Math<float>::lrn_computediff(int n, long hBottomData, long hTopData, long hScaleData, long hTopDiff, int nNum, int nChannels, int nHeight, int nWidth, int nSize, float fB, float fA, long hBottomDiff);


template <typename T>
__device__ T sigmoid(const T x)
{
	return T(1) / (T(1) + exp(-x));
}

template <typename T>
__device__ T tanh(const T x)
{
	return T(2) * sigmoid(T(2) * x) - T(1);
}

template <typename T>
__global__ void clip_add_kernel(const int nthreads, const int dim, int t, const T* clip, const T* add_vec, T* data)
{
	for (int idx=blockIdx.x * blockDim.x + threadIdx.x; idx<nthreads; idx += blockDim.x * gridDim.x)
	{
		const int n = idx / dim;
		const T clip_t = clip ? clip[n] : T(t > 0);
		data[idx] += clip_t * add_vec[idx];
	}
}

template <typename T>
__global__ void activation_fwd_kernel(const int nthreads, const int H, const T* pre_gate, T* gate)
{
	for (int idx=blockIdx.x * blockDim.x + threadIdx.x; idx<nthreads; idx += blockDim.x * gridDim.x)
	{
		const int d = idx % (4 * H);
		gate[idx] = d < 3 * H ? sigmoid(pre_gate[idx]) : tanh(pre_gate[idx]);
	}
}

template <typename T>
__global__ void activation_bwd_kernel(const int nthreads, const int H, const T clip_threshold, const T* gate, const T* gate_diff, T* pre_gate_diff)
{
	for (int idx=blockIdx.x * blockDim.x + threadIdx.x; idx<nthreads; idx += blockDim.x * gridDim.x)
	{
		const int d = idx % (4 * H);
		const T gate_val = gate[idx];

		if (d < 3 * H)
			pre_gate_diff[idx] = gate_diff[idx] * gate_val * (T(1) - gate_val);
		else
			pre_gate_diff[idx] = gate_diff[idx] * (T(1) - gate_val * gate_val);

		if (clip_threshold > T(0))
		{
			if (pre_gate_diff[idx] < -clip_threshold)
				pre_gate_diff[idx] = -clip_threshold;
			else if (pre_gate_diff[idx] > clip_threshold)
				pre_gate_diff[idx] = clip_threshold;
		}
	}
}

template <typename T>
__global__ void lstm_fwd_kernel(const int nthreads, const int H, const int t, const T* c_prev, const T* gate, const T* clip, T* c_t, T* h_t)
{
	for (int idx=blockIdx.x * blockDim.x + threadIdx.x; idx<nthreads; idx += blockDim.x * gridDim.x)
	{
		const int n = idx / H;
		const int d = idx % H;
		const T* offset = gate + 4*H*n;
		const T i_t = offset[d];
		const T f_t = offset[H + d];
		const T o_t = offset[2*H + d];
		const T g_t = offset[3*H + d];
		const T c_t_1 = c_prev[idx];
		const T clip_t = clip ? clip[n] : T(t > 0);
		c_t[idx] = clip_t * f_t * c_t_1 + i_t * g_t;
		h_t[idx] = o_t * tanh(c_t[idx]);
	}
}


template <typename T>
__global__ void lstm_bwd_kernel(const int nthreads, const int H, const int t, const T* c_prev, const T* gate, const T* c_t, const T* clip, T* dc_t, T* dh_t, T* dc_prev, T* gate_diff)
{
	for (int idx=blockIdx.x * blockDim.x + threadIdx.x; idx<nthreads; idx += blockDim.x * gridDim.x)
	{
		const int n = idx / H;
		const int d = idx % H;
		const T* gate_t = gate + 4*H*n;
		const T i_t = gate_t[d];
		const T f_t = gate_t[H + d];
		const T o_t = gate_t[2*H + d];
		const T g_t = gate_t[3*H + d];
		const T c_t_1 = c_prev[idx];
		const T c = c_t[idx];
		const T tanh_c = tanh(c);
		const T clip_t = clip ? clip[n] : T(t > 0);
		T* dc_t_1 = dc_prev + idx;
		T* gate_diff_t = gate_diff + 4*H*n;
		T* di_t = gate_diff_t + d;
		T* df_t = gate_diff_t + H + d;
		T* do_t = gate_diff_t + 2*H + d;
		T* dg_t = gate_diff_t + 3*H + d;

		// Output gate: tanh(c(t)) * h_diff(t)
		*do_t = dh_t[idx] * tanh_c;
		// Cell state: o(t) * tanh'(c(t)) * h_diff(t) + f(t+1) * c_diff(t+1)
		dc_t[idx] += dh_t[idx] * o_t * (T(1) - tanh_c * tanh_c);
		// c_diff(t-1) += f(t) * c_diff(t)
		*dc_t_1 = clip_t * dc_t[idx] * f_t;
		// Forget gate: c(t-1) * c_diff(t)
		*df_t = clip_t * dc_t[idx] * c_t_1;
		// Input gate: g(t) * c_diff(t)
		*di_t = dc_t[idx] * g_t;
		// Input modulation gate: i(t) * c_diff(t)
		*dg_t = dc_t[idx] * i_t;
	}
}


template <class T>
long Math<T>::lstm_fwd(int t, int nN, int nH, long hWeight_h, long hWeight_i, long hClipData, int nClipOffset, long hTopData, int nTopOffset, long hCellData, int nCellOffset, long hPreGateData, int nPreGateOffset, long hGateData, int nGateOffset, long hHT1Data, int nHT1Offset, long hCT1Data, int nCT1Offset, long hHtoGateData)
{
	LONG lErr;
	int nCount;
	MemoryItem* pWeight_h;
	MemoryItem* pWeight_i;
	MemoryItem* pClipData = NULL;
	MemoryItem* pTopData;
	MemoryItem* pCellData;
	MemoryItem* pPreGateData;
	MemoryItem* pGateData;
	MemoryItem* pHT1Data;
	MemoryItem* pCT1Data;
	MemoryItem* pHtoGateData;

	if (lErr = m_pMemCol->GetData(hWeight_h, &pWeight_h))
		return lErr;

	if (lErr = m_pMemCol->GetData(hWeight_i, &pWeight_i))
		return lErr;

	if (hClipData > 0)
	{
		if (lErr = m_pMemCol->GetData(hClipData, &pClipData))
			return lErr;
	}

	if (lErr = m_pMemCol->GetData(hTopData, &pTopData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hCellData, &pCellData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hPreGateData, &pPreGateData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hGateData, &pGateData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hHT1Data, &pHT1Data))
		return lErr;

	if (lErr = m_pMemCol->GetData(hCT1Data, &pCT1Data))
		return lErr;

	if (lErr = m_pMemCol->GetData(hHtoGateData, &pHtoGateData))
		return lErr;

	T* weight_h = (T*)pWeight_h->Data();
	T* weight_i = (T*)pWeight_i->Data();
	T* clip_t = (pClipData == NULL) ? NULL : ((T*)pClipData->Data()) + nClipOffset;
	T* h_t = ((T*)pTopData->Data()) + nTopOffset;
	T* c_t = ((T*)pCellData->Data()) + nCellOffset;
	T* pre_gate_t = ((T*)pPreGateData->Data()) + nPreGateOffset;
	T* gate_t = ((T*)pGateData->Data()) + nGateOffset;
	T* h_t_1 = (t > 0) ? h_t + nHT1Offset : ((T*)pHT1Data->Data()) + nHT1Offset;
	T* c_t_1 = (t > 0) ? c_t + nCT1Offset : ((T*)pCT1Data->Data()) + nCT1Offset;
	T* h_to_gate = (T*)pHtoGateData->Data();

	if (lErr = gemm(false, true, nN, 4 * nH, nH, T(1.0), h_t_1, weight_h, T(0.0), h_to_gate))
		return lErr;

	nCount = 4 * nN * nH;
	clip_add_kernel<T><<<CAFFE_GET_BLOCKS(nCount), CAFFE_CUDA_NUM_THREADS>>>(nCount, 4 * nH, t, clip_t, h_to_gate, pre_gate_t);

	if (lErr = cudaGetLastError())
		return lErr;

	nCount = 4 * nN * nH;
	activation_fwd_kernel<T><<<CAFFE_GET_BLOCKS(nCount), CAFFE_CUDA_NUM_THREADS>>>(nCount, nH, pre_gate_t, gate_t);

	nCount = nN * nH;
	lstm_fwd_kernel<T><<<CAFFE_GET_BLOCKS(nCount), CAFFE_CUDA_NUM_THREADS>>>(nCount, nH, t, c_t_1, gate_t, clip_t, c_t, h_t);

	return cudaGetLastError();
}

template long Math<double>::lstm_fwd(int t, int nN, int nH, long hWeight_h, long hWeight_i, long hClipData, int nClipOffset, long hTopData, int nTopOffset, long hCellData, int nCellOffset, long hPreGateData, int nPreGateOffset, long hGateData, int nGateOffset, long hHT1Data, int nHT1Offset, long hCT1Data, int nCT1Offset, long hHtoGateData);
template long Math<float>::lstm_fwd(int t, int nN, int nH, long hWeight_h, long hWeight_i, long hClipData, int nClipOffset, long hTopData, int nTopOffset, long hCellData, int nCellOffset, long hPreGateData, int nPreGateOffset, long hGateData, int nGateOffset, long hHT1Data, int nHT1Offset, long hCT1Data, int nCT1Offset, long hHtoGateData);



template <class T>
long Math<T>::lstm_bwd(int t, int nN, int nH, T fClip, long hWeight_h, long hClipData, int nClipOffset, long hTopDiff, int nTopOffset, long hCellData, long hCellDiff, int nCellOffset, long hPreGateDiff, int nPreGateOffset, long hGateData, long hGateDiff, int nGateOffset, long hCT1Data, int nCT1Offset, long hDHT1Diff, int nDHT1Offset, long hDCT1Diff, int nDCT1Offset, long hHtoHData)
{
	LONG lErr;
	int nCount;
	MemoryItem* pWeight_h;
	MemoryItem* pClipData = NULL;
	MemoryItem* pTopDiff;
	MemoryItem* pCellData;
	MemoryItem* pCellDiff;
	MemoryItem* pPreGateDiff;
	MemoryItem* pGateData;
	MemoryItem* pGateDiff;
	MemoryItem* pCT1Data;
	MemoryItem* pDHT1Diff;
	MemoryItem* pDCT1Diff;
	MemoryItem* pHtoHData;

	if (lErr = m_pMemCol->GetData(hWeight_h, &pWeight_h))
		return lErr;

	if (hClipData > 0)
	{
		if (lErr = m_pMemCol->GetData(hClipData, &pClipData))
			return lErr;
	}

	if (lErr = m_pMemCol->GetData(hTopDiff, &pTopDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hCellData, &pCellData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hCellDiff, &pCellDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hPreGateDiff, &pPreGateDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hGateData, &pGateData))
		return lErr;

	if (lErr = m_pMemCol->GetData(hGateDiff, &pGateDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hCT1Data, &pCT1Data))
		return lErr;

	if (lErr = m_pMemCol->GetData(hDHT1Diff, &pDHT1Diff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hDCT1Diff, &pDCT1Diff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hHtoHData, &pHtoHData))
		return lErr;

	T* weight_h = (T*)pWeight_h->Data();
	T* clip_t = (pClipData == NULL) ? NULL : ((T*)pClipData->Data()) + nClipOffset;
	T* dh_t = ((T*)pTopDiff->Data()) + nTopOffset;
	T* dc_t = ((T*)pCellDiff->Data()) + nCellOffset;
	T* gate_diff_t = ((T*)pGateDiff->Data()) + nGateOffset;
	T* pre_gate_diff_t = ((T*)pPreGateDiff->Data()) + nPreGateOffset;
	T* dh_t_1 = ((T*)pDHT1Diff->Data()) + nDHT1Offset;
	T* dc_t_1 = ((T*)pDCT1Diff->Data()) + nDCT1Offset;
	T* c_t = ((T*)pCellData->Data()) + nCellOffset;
	T* c_t_1 = ((T*)pCT1Data->Data()) + nCT1Offset;
	T* gate_t = ((T*)pGateData->Data()) + nGateOffset;
	T* h_to_h = (T*)pHtoHData->Data();

	nCount = nN * nH;
	lstm_bwd_kernel<T><<<CAFFE_GET_BLOCKS(nCount), CAFFE_CUDA_NUM_THREADS>>>(nCount, nH, t, c_t_1, gate_t, c_t, clip_t, dc_t, dh_t, dc_t_1, gate_diff_t);

	if (lErr = cudaGetLastError())
		return lErr;

	nCount = 4 * nN * nH;
	activation_bwd_kernel<T><<<CAFFE_GET_BLOCKS(nCount), CAFFE_CUDA_NUM_THREADS>>>(nCount, nH, fClip, gate_t, gate_diff_t, pre_gate_diff_t);

	if (lErr = cudaGetLastError())
		return lErr;

	// Backprop errors to previous time step.
	if (lErr = gemm(false, false, nN, nH, 4 * nH, T(1.), pre_gate_diff_t, weight_h, T(0.), h_to_h))
		return lErr;

	nCount = nN * nH;
	clip_add_kernel<T><<<CAFFE_GET_BLOCKS(nCount), CAFFE_CUDA_NUM_THREADS>>>(nCount, nH, t, clip_t, h_to_h, dh_t_1);

	return cudaGetLastError();
}

template long Math<double>::lstm_bwd(int t, int nN, int nH, double fClip, long hWeight_h, long hClipData, int nClipOffset, long hTopDiff, int nTopOffset, long hCellData, long hCellDiff, int nCellOffset, long hPreGateDiff, int nPreGateOffset, long hGateData, long hGateDiff, int nGateOffset, long hCT1Data, int nCT1Offset, long hDHT1Diff, int nDHT1Offset, long hDCT1Diff, int nDCT1Offset, long hHtoHData);
template long Math<float>::lstm_bwd(int t, int nN, int nH, float fClip, long hWeight_h, long hClipData, int nClipOffset, long hTopDiff, int nTopOffset, long hCellData, long hCellDiff, int nCellOffset, long hPreGateDiff, int nPreGateOffset, long hGateData, long hGateDiff, int nGateOffset, long hCT1Data, int nCT1Offset, long hDHT1Diff, int nDHT1Offset, long hDCT1Diff, int nDCT1Offset, long hHtoHData);


template <typename T>
__global__ void lstm_acts_fwd_kernel(const int nthreads, const int dim, const T* x, T* x_acts)
{
	for (int idx = blockIdx.x * blockDim.x + threadIdx.x; idx<nthreads; idx += blockDim.x * gridDim.x)
	{
		const int x_dim = 4 * dim;
		const int d = idx % x_dim;

		if (d < 3 * dim)
			x_acts[idx] = sigmoid(x[idx]);
		else
			x_acts[idx] = tanh(x[idx]);
	}
}

template <typename T>
__global__ void lstm_unit_fwd_kernel(const int nthreads, const int dim, const T* c_prev, const T* x, const T* cont, T* c, T* h)
{
	for (int idx = blockIdx.x * blockDim.x + threadIdx.x; idx<nthreads; idx += blockDim.x * gridDim.x)
	{
		const int n = idx/ dim;
		const int d = idx % dim;
		const T* x_offset = x + 4 * dim * n;
		const T i = x_offset[d];
		const T f = x_offset[1 * dim + d];
		const T o = x_offset[2 * dim + d];
		const T g = x_offset[3 * dim + d];
		const T c_prev1 = c_prev[idx];
		const T c1 = cont[n] * f * c_prev1 + i * g;
		c[idx] = c1;
		const T tanh_c = tanh(c1);
		h[idx] = o * tanh_c;
	}
}

template <class T>
long Math<T>::lstm_unit_fwd(int nCount, int nHiddenDim, int nXCount, long hX, long hX_acts, long hC_prev, long hCont, long hC, long hH)
{
	LONG lErr;
	MemoryItem* pX;
	MemoryItem* pX_acts;
	MemoryItem* pC_prev;
	MemoryItem* pCont;
	MemoryItem* pC;
	MemoryItem* pH;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hX_acts, &pX_acts))
		return lErr;

	if (lErr = m_pMemCol->GetData(hC_prev, &pC_prev))
		return lErr;

	if (lErr = m_pMemCol->GetData(hCont, &pCont))
		return lErr;

	if (lErr = m_pMemCol->GetData(hC, &pC))
		return lErr;

	if (lErr = m_pMemCol->GetData(hH, &pH))
		return lErr;

	T* x = (T*)pX->Data();
	T* x_acts = (T*)pX_acts->Data();
	T* c_prev = (T*)pC_prev->Data();
	T* cont = (T*)pCont->Data();
	T* c = (T*)pC->Data();
	T* h = (T*)pH->Data();

	lstm_acts_fwd_kernel<T> <<<CAFFE_GET_BLOCKS(nXCount), CAFFE_CUDA_NUM_THREADS >>>(nXCount, nHiddenDim, x, x_acts);

	if (lErr = cudaGetLastError())
		return lErr;

	lstm_unit_fwd_kernel<T> << <CAFFE_GET_BLOCKS(nCount), CAFFE_CUDA_NUM_THREADS >> > (nCount, nHiddenDim, c_prev, x_acts, cont, c, h);

	return cudaGetLastError();
}

template long Math<double>::lstm_unit_fwd(int nCount, int nHiddenDim, int nXCount, long hX, long hX_acts, long hC_prev, long hCont, long hC, long hH);
template long Math<float>::lstm_unit_fwd(int nCount, int nHiddenDim, int nXCount, long hX, long hX_acts, long hC_prev, long hCont, long hC, long hH);




template <typename T>
__global__ void lstm_unit_bwd_kernel(const int nthreads, const int dim, const T* c_prev, const T* x, const T* c, const T* h, const T* cont, const T* c_diff, const T* h_diff, T* c_prev_diff, T* x_diff)
{
	for (int idx = blockIdx.x * blockDim.x + threadIdx.x; idx<nthreads; idx += blockDim.x * gridDim.x)
	{
		const int n = idx / dim;
		const int d = idx % dim;
		const T* x_offset = x + 4 * dim * n;
		const T i = x_offset[d];
		const T f = x_offset[1 * dim + d];
		const T o = x_offset[2 * dim + d];
		const T g = x_offset[3 * dim + d];
		const T c_prev1 = c_prev[idx];
		const T c1 = c[idx];
		const T tanh_c = tanh(c1);
		T* c_prev_diff1 = c_prev_diff + idx;
		T* x_diff_offset = x_diff + 4 * dim * n;
		T* i_diff = x_diff_offset + d;
		T* f_diff = x_diff_offset + 1 * dim + d;
		T* o_diff = x_diff_offset + 2 * dim + d;
		T* g_diff = x_diff_offset + 3 * dim + d;
		const T c_term_diff = c_diff[idx] + h_diff[idx] * o * (1 - tanh_c * tanh_c);
		const T cont_n = cont[n];
		
		*c_prev_diff1 = cont_n * c_term_diff * f;
		*i_diff = c_term_diff * g;
		*f_diff = cont_n * c_term_diff * c_prev1;
		*o_diff = h_diff[idx] * tanh_c;
		*g_diff = c_term_diff * i;
	}
}

template <typename T>
__global__ void lstm_acts_bwd_kernel(const int nthreads, const int dim, const T* x_acts, const T* x_acts_diff, T* x_diff)
{
	for (int idx = blockIdx.x * blockDim.x + threadIdx.x; idx<nthreads; idx += blockDim.x * gridDim.x)
	{
		const int x_dim = 4 * dim;
		const int d = idx % x_dim;
		const T x_act = x_acts[idx];

		if (d < 3 * dim)
			x_diff[idx] = x_acts_diff[idx] * x_act * (T(1) - x_act);
		else
			x_diff[idx] = x_acts_diff[idx] * (T(1) - x_act * x_act);
	}
}

template <class T>
long Math<T>::lstm_unit_bwd(int nCount, int nHiddenDim, int nXCount, long hC_prev, long hX_acts, long hC, long hH, long hCont, long hC_diff, long hH_diff, long hC_prev_diff, long hX_acts_diff, long hX_diff)
{
	LONG lErr;
	MemoryItem* pC_prev;
	MemoryItem* pX_acts;
	MemoryItem* pC;
	MemoryItem* pH;
	MemoryItem* pCont;
	MemoryItem* pC_diff;
	MemoryItem* pH_diff;
	MemoryItem* pC_prev_diff;
	MemoryItem* pX_acts_diff;
	MemoryItem* pX_diff;


	if (lErr = m_pMemCol->GetData(hC_prev, &pC_prev))
		return lErr;

	if (lErr = m_pMemCol->GetData(hX_acts, &pX_acts))
		return lErr;

	if (lErr = m_pMemCol->GetData(hC, &pC))
		return lErr;

	if (lErr = m_pMemCol->GetData(hH, &pH))
		return lErr;

	if (lErr = m_pMemCol->GetData(hCont, &pCont))
		return lErr;

	if (lErr = m_pMemCol->GetData(hC_diff, &pC_diff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hH_diff, &pH_diff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hC_prev_diff, &pC_prev_diff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hX_acts_diff, &pX_acts_diff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hX_diff, &pX_diff))
		return lErr;

	T* c_prev = (T*)pC_prev->Data();
	T* x_acts = (T*)pX_acts->Data();
	T* c = (T*)pC->Data();
	T* h = (T*)pH->Data();
	T* cont = (T*)pCont->Data();
	T* c_diff = (T*)pC_diff->Data();
	T* h_diff = (T*)pH_diff->Data();
	T* c_prev_diff = (T*)pC_prev_diff->Data();
	T* x_acts_diff = (T*)pX_acts_diff->Data();
	T* x_diff = (T*)pX_diff->Data();

	lstm_unit_bwd_kernel<T> <<<CAFFE_GET_BLOCKS(nCount), CAFFE_CUDA_NUM_THREADS>>> (nCount, nHiddenDim, c_prev, x_acts, c, h, cont, c_diff, h_diff, c_prev_diff, x_acts_diff);

	if (lErr = cudaGetLastError())
		return lErr;

	lstm_acts_bwd_kernel<T> <<<CAFFE_GET_BLOCKS(nXCount), CAFFE_CUDA_NUM_THREADS>>>(nXCount, nHiddenDim, x_acts, x_acts_diff, x_diff);

	return cudaGetLastError();
}

template long Math<double>::lstm_unit_bwd(int nCount, int nHiddenDim, int nXCount, long hC_prev, long hX_acts, long hC, long hH, long hCont, long hC_diff, long hH_diff, long hC_prev_diff, long hX_acts_diff, long hX_diff);
template long Math<float>::lstm_unit_bwd(int nCount, int nHiddenDim, int nXCount, long hC_prev, long hX_acts, long hC, long hH, long hCont, long hC_diff, long hH_diff, long hC_prev_diff, long hX_acts_diff, long hX_diff);


template <typename T>
__global__ void coeff_sum_fwd_kernel(const int nthreads, const int dim, const int num_offset, const T coeff, const T* coeff_data, const T* in, T* out)
{
	for (int idx=blockIdx.x * blockDim.x + threadIdx.x; idx<nthreads; idx += blockDim.x * gridDim.x)
	{
		int n = num_offset + idx / dim;
		T other_coeff = (coeff_data != NULL) ? coeff_data[n] : T(1);
		T final_coeff = coeff * other_coeff;
		T result = in[idx] * final_coeff;

		if (num_offset == 0)
			out[idx] = result;
		else
			out[idx] += result;
	}
}

template <class T>
long Math<T>::coeff_sum_fwd(int nCount, int nDim, int nNumOffset, T fCoeff, long hCoeffData, long hBottom, long hTop)
{
	LONG lErr;
	MemoryItem* pCoeffData = NULL;
	MemoryItem* pBottom;
	MemoryItem* pTop;

	if (hCoeffData != 0)
	{
		if (lErr = m_pMemCol->GetData(hCoeffData, &pCoeffData))
			return lErr;
	}

	if (lErr = m_pMemCol->GetData(hBottom, &pBottom))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTop, &pTop))
		return lErr;

	T* coeffdata = (pCoeffData == NULL) ? NULL : (T*)pCoeffData->Data();
	T* bottom = (T*)pBottom->Data();
	T* top = (T*)pTop->Data();

	coeff_sum_fwd_kernel<T><<<CAFFE_GET_BLOCKS(nCount), CAFFE_CUDA_NUM_THREADS>>>(nCount, nDim, nNumOffset, fCoeff, coeffdata, bottom, top);

	return cudaGetLastError();
}

template long Math<double>::coeff_sum_fwd(int nCount, int nDim, int nNumOffset, double fCoeff, long hCoeffData, long hBottom, long hTop);
template long Math<float>::coeff_sum_fwd(int nCount, int nDim, int nNumOffset, float fCoeff, long hCoeffData, long hBottom, long hTop);


template <typename T>
__global__ void coeff_sum_bwd_kernel(const int nthreads, const int dim, const int num_offset, const T coeff, const T* coeff_data, const T* in, T* out)
{
	for (int idx=blockIdx.x * blockDim.x + threadIdx.x; idx<nthreads; idx += blockDim.x * gridDim.x)
	{
		int n = num_offset + idx / dim;
		T other_coeff = (coeff_data != NULL) ? coeff_data[n] : T(1);
		T final_coeff = coeff * other_coeff;
		T result = in[idx] * final_coeff;
		out[idx] = result;
	}
}

template <class T>
long Math<T>::coeff_sum_bwd(int nCount, int nDim, int nNumOffset, T fCoeff, long hCoeffData, long hTopDiff, long hBottomDiff)
{
	LONG lErr;
	MemoryItem* pCoeffData = NULL;
	MemoryItem* pBottomDiff;
	MemoryItem* pTopDiff;

	if (hCoeffData != 0)
	{
		if (lErr = m_pMemCol->GetData(hCoeffData, &pCoeffData))
			return lErr;
	}

	if (lErr = m_pMemCol->GetData(hTopDiff, &pTopDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hBottomDiff, &pBottomDiff))
		return lErr;

	T* coeffdata = (pCoeffData == NULL) ? NULL : (T*)pCoeffData->Data();
	T* topdiff = (T*)pTopDiff->Data();
	T* bottomdiff = (T*)pBottomDiff->Data();

	coeff_sum_bwd_kernel<T><<<CAFFE_GET_BLOCKS(nCount), CAFFE_CUDA_NUM_THREADS>>>(nCount, nDim, nNumOffset, fCoeff, coeffdata, topdiff, bottomdiff);

	return cudaGetLastError();
}

template long Math<double>::coeff_sum_bwd(int nCount, int nDim, int nNumOffset, double fCoeff, long hCoeffData, long hTopDiff, long hBottomDiff);
template long Math<float>::coeff_sum_bwd(int nCount, int nDim, int nNumOffset, float fCoeff, long hCoeffData, long hTopDiff, long hBottomDiff);


template <typename T>
__global__ void sigmoid_cross_entropy_kernel(const int nthreads, const T* input_data, const T* target, T* loss, T* counts)
{
	for (int i = blockIdx.x * blockDim.x + threadIdx.x; i<nthreads; i += blockDim.x * gridDim.x)
	{
		const int target_val = (int)target[i];
		const T input_val = input_data[i];
		loss[i] = input_val * (target_val - (input_val >= 0)) -
			log(1 + exp(input_val - 2 * input_val * (input_val >= 0)));
		counts[i] = 1;
	}
}

template <typename T>
__global__ void sigmoid_cross_entropy_kernel_withignore(const int nthreads, const T* input_data, const T* target, T* loss, const int ignore_label, T* counts)
{
	for (int i = blockIdx.x * blockDim.x + threadIdx.x; i<nthreads; i += blockDim.x * gridDim.x)
	{
		const int target_val = (int)target[i];

		if (target_val == ignore_label)
		{
			loss[i] = 0;
			counts[i] = 0;
		}
		else
		{
			const T input_val = input_data[i];
			loss[i] = input_val * (target_val - (input_val >= 0)) -
				log(1 + exp(input_val - 2 * input_val * (input_val >= 0)));
			counts[i] = 1;
		}
	}
}

template <class T>
long Math<T>::sigmoid_cross_entropy_fwd(int nCount, long hInput, long hTarget, long hLoss, bool bHasIgnoreLabel, int nIgnoreLabel, long hCount)
{
	LONG lErr;
	MemoryItem* pInput;
	MemoryItem* pTarget;
	MemoryItem* pLoss;
	MemoryItem* pCount;

	if (lErr = m_pMemCol->GetData(hInput, &pInput))
		return lErr;

	if (lErr = m_pMemCol->GetData(hTarget, &pTarget))
		return lErr;

	if (lErr = m_pMemCol->GetData(hLoss, &pLoss))
		return lErr;

	if (lErr = m_pMemCol->GetData(hCount, &pCount))
		return lErr;

	T* input_data = (T*)pInput->Data();
	T* target = (T*)pTarget->Data();
	T* loss_data = (T*)pLoss->Data();
	T* count_data = (T*)pCount->Data();

	if (bHasIgnoreLabel)
		sigmoid_cross_entropy_kernel_withignore<T><<<CAFFE_GET_BLOCKS(nCount), CAFFE_CUDA_NUM_THREADS>>>(nCount, input_data, target, loss_data, nIgnoreLabel, count_data);
	else
		sigmoid_cross_entropy_kernel<T> << <CAFFE_GET_BLOCKS(nCount), CAFFE_CUDA_NUM_THREADS >> >(nCount, input_data, target, loss_data, count_data);

	return cudaGetLastError();
}

template long Math<double>::sigmoid_cross_entropy_fwd(int nCount, long hInput, long hTarget, long hLoss, bool bHasIgnoreLabel, int nIgnoreLabel, long hCount);
template long Math<float>::sigmoid_cross_entropy_fwd(int nCount, long hInput, long hTarget, long hLoss, bool bHasIgnoreLabel, int nIgnoreLabel, long hCount);


template <typename T>
__global__ void sigmoid_cross_entropy_ignore_kernel(const int nthreads, const int ignore_label, const T* target, T* diff)
{
	for (int i = blockIdx.x * blockDim.x + threadIdx.x; i<nthreads; i += blockDim.x * gridDim.x)
	{
		const int target_val = (int)target[i];

		if (target_val == ignore_label)
			diff[i] = 0;
	}
}

template <class T>
long Math<T>::sigmoid_cross_entropy_ignore(int nCount, int nIgnoreLabel, long hTarget, long hData)
{
	LONG lErr;
	MemoryItem* pTarget;
	MemoryItem* pData;

	if (lErr = m_pMemCol->GetData(hTarget, &pTarget))
		return lErr;

	if (lErr = m_pMemCol->GetData(hData, &pData))
		return lErr;

	T* target = (T*)pTarget->Data();
	T* bottom_diff = (T*)pData->Data();

	sigmoid_cross_entropy_ignore_kernel<T><<<CAFFE_GET_BLOCKS(nCount), CAFFE_CUDA_NUM_THREADS>>>(nCount, nIgnoreLabel, target, bottom_diff);

	return cudaGetLastError();
}

template long Math<double>::sigmoid_cross_entropy_ignore(int nCount, int nIgnoreLabel, long hTarget, long hData);
template long Math<float>::sigmoid_cross_entropy_ignore(int nCount, int nIgnoreLabel, long hTarget, long hData);


template <typename T>
__global__ void sgd_update_kernel(int n, T* g, T* h, T momentum, T local_rate)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		g[i] = h[i] = momentum * h[i] + local_rate * g[i];
	}
}

template <class T>
long Math<T>::sgd_update(int n, long hNetParamDiff, long hHistoryData, T fMomentum, T fLearningRate)
{
	LONG lErr;
	MemoryItem* pNetParamDiff;
	MemoryItem* pHistoryData;

	if (lErr = m_pMemCol->GetData(hNetParamDiff, &pNetParamDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hHistoryData, &pHistoryData))
		return lErr;

	T* net_param_diff = (T*)pNetParamDiff->Data();
	T* history_data = (T*)pHistoryData->Data();

	sgd_update_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, net_param_diff, history_data, fMomentum, fLearningRate);

	return cudaGetLastError();
}

template long Math<double>::sgd_update(int nCount, long hNetParamDiff, long hHistoryData, double dfMomentum, double dfLearningRate);
template long Math<float>::sgd_update(int nCount, long hNetParamDiff, long hHistoryData, float fMomentum, float fLearningRate);


template <typename T>
__global__ void nesterov_update_kernel(int n, T* g, T* h, T momentum, T local_rate)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		T fHi = h[i];	
		T fHiNew = h[i] = momentum * h[i] + local_rate * g[i];
		g[i] = (1 + momentum) * fHiNew - momentum * fHi;
	}
}

template <class T>
long Math<T>::nesterov_update(int n, long hNetParamDiff, long hHistoryData, T fMomentum, T fLearningRate)
{
	LONG lErr;
	MemoryItem* pNetParamDiff;
	MemoryItem* pHistoryData;

	if (lErr = m_pMemCol->GetData(hNetParamDiff, &pNetParamDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hHistoryData, &pHistoryData))
		return lErr;

	T* net_param_diff = (T*)pNetParamDiff->Data();
	T* history_data = (T*)pHistoryData->Data();

	nesterov_update_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, net_param_diff, history_data, fMomentum, fLearningRate);

	return cudaGetLastError();
}

template long Math<double>::nesterov_update(int nCount, long hNetParamDiff, long hHistoryData, double dfMomentum, double dfLearningRate);
template long Math<float>::nesterov_update(int nCount, long hNetParamDiff, long hHistoryData, float fMomentum, float fLearningRate);


template <typename T>
__global__ void adagrad_update_kernel(int n, T* g, T* h, T delta, T local_rate)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		T fGi = g[i];
		T fHi = h[i] = h[i] + fGi * fGi;
		g[i] = local_rate * fGi / (sqrt(fHi) + delta);
	}
}

template <class T>
long Math<T>::adagrad_update(int n, long hNetParamDiff, long hHistoryData, T fDelta, T fLearningRate)
{
	LONG lErr;
	MemoryItem* pNetParamDiff;
	MemoryItem* pHistoryData;

	if (lErr = m_pMemCol->GetData(hNetParamDiff, &pNetParamDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hHistoryData, &pHistoryData))
		return lErr;

	T* net_param_diff = (T*)pNetParamDiff->Data();
	T* history_data = (T*)pHistoryData->Data();

	adagrad_update_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, net_param_diff, history_data, fDelta, fLearningRate);

	return cudaGetLastError();
}

template long Math<double>::adagrad_update(int nCount, long hNetParamDiff, long hHistoryData, double dfDelta, double dfLearningRate);
template long Math<float>::adagrad_update(int nCount, long hNetParamDiff, long hHistoryData, float fDelta, float fLearningRate);


template <typename T>
__global__ void adadelta_update_kernel(int n, T* g, T* h, T* h2, T momentum, T delta, T local_rate)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		T fGi = g[i];
		T fHi = h[i] = momentum * h[i] + (1 - momentum) * fGi * fGi;

		fGi = fGi * sqrt((h2[i] + delta) / (fHi + delta));
		h2[i] = momentum * h2[i] + (1 - momentum) * fGi * fGi;
		g[i] = local_rate * fGi;
	}
}

template <class T>
long Math<T>::adadelta_update(int n, long hNetParamDiff, long hHistoryData1, long hHistoryData2, T fMomentum, T fDelta, T fLearningRate)
{
	LONG lErr;
	MemoryItem* pNetParamDiff;
	MemoryItem* pHistoryData1;
	MemoryItem* pHistoryData2;

	if (lErr = m_pMemCol->GetData(hNetParamDiff, &pNetParamDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hHistoryData1, &pHistoryData1))
		return lErr;

	if (lErr = m_pMemCol->GetData(hHistoryData2, &pHistoryData2))
		return lErr;

	T* net_param_diff = (T*)pNetParamDiff->Data();
	T* history_data1 = (T*)pHistoryData1->Data();
	T* history_data2 = (T*)pHistoryData2->Data();

	adadelta_update_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, net_param_diff, history_data1, history_data2, fMomentum, fDelta, fLearningRate);

	return cudaGetLastError();
}

template long Math<double>::adadelta_update(int nCount, long hNetParamDiff, long hHistoryData1, long hHistoryData2, double dfMomentum, double dfDelta, double dfLearningRate);
template long Math<float>::adadelta_update(int nCount, long hNetParamDiff, long hHistoryData1, long hHistoryData2, float fMomentum, float fDelta, float fLearningRate);


template <typename T>
__global__ void adam_update_kernel(int n, T* g, T* m, T* v, T beta1, T beta2, T eps_hat, T corrected_local_rate)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		T fGi = g[i];
		T fMi = m[i] = m[i] * beta1 + fGi * (1 - beta1);
		T fVi = v[i] = v[i] * beta2 + fGi * fGi * (1 - beta2);
		g[i] = corrected_local_rate * fMi / (sqrt(fVi) + eps_hat);
	}
}

template <class T>
long Math<T>::adam_update(int n, long hNetParamDiff, long hValM, long hValV, T fBeta1, T fBeta2, T fEpsHat, T fCorrectedLearningRate)
{
	LONG lErr;
	MemoryItem* pNetParamDiff;
	MemoryItem* pValM;
	MemoryItem* pValV;

	if (lErr = m_pMemCol->GetData(hNetParamDiff, &pNetParamDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hValM, &pValM))
		return lErr;

	if (lErr = m_pMemCol->GetData(hValV, &pValV))
		return lErr;

	T* net_param_diff = (T*)pNetParamDiff->Data();
	T* val_m = (T*)pValM->Data();
	T* val_v = (T*)pValV->Data();

	adam_update_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, net_param_diff, val_m, val_v, fBeta1, fBeta2, fEpsHat, fCorrectedLearningRate);

	return cudaGetLastError();
}

template long Math<double>::adam_update(int nCount, long hNetParamDiff, long hValM, long hValV, double dfBeta1, double dfBeta2, double dfEpsHat, double dfCorrectedLearningRate);
template long Math<float>::adam_update(int nCount, long hNetParamDiff, long hValM, long hValV, float fBeta1, float fBeta2, float fEpsHat, float fCorrectedLearningRate);


template <typename T>
__global__ void rmsprop_update_kernel(int n, T* g, T* h, T rms_decay, T delta, T local_rate)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		T fGi = g[i];
		T fHi = h[i] = rms_decay * h[i] + (1 - rms_decay) * fGi * fGi;
		g[i] = local_rate * fGi / (sqrt(fHi) + delta);
	}
}

template <class T>
long Math<T>::rmsprop_update(int n, long hNetParamDiff, long hHistoryData, T fRmsDecay, T fDelta, T fLearningRate)
{
	LONG lErr;
	MemoryItem* pNetParamDiff;
	MemoryItem* pHistoryData;

	if (lErr = m_pMemCol->GetData(hNetParamDiff, &pNetParamDiff))
		return lErr;

	if (lErr = m_pMemCol->GetData(hHistoryData, &pHistoryData))
		return lErr;

	T* net_param_diff = (T*)pNetParamDiff->Data();
	T* history_data = (T*)pHistoryData->Data();

	rmsprop_update_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, net_param_diff, history_data, fRmsDecay, fDelta, fLearningRate);

	return cudaGetLastError();
}

template long Math<double>::rmsprop_update(int nCount, long hNetParamDiff, long hHistoryData, double dfRmsDecay, double dfDelta, double dfLearningRate);
template long Math<float>::rmsprop_update(int nCount, long hNetParamDiff, long hHistoryData, float fRmsDecay, float fDelta, float fLearningRate);


template <typename T>
__global__ void combine_data_kernel(int n, T* o, T* u, T updtPct, T* s, T srvrPct, T* out)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		out[i] = o[i] + ((u[i] - o[i]) * updtPct) + ((s[i] - o[i]) * srvrPct);
	}
}

template <class T> 
long Math<T>::combine_data(int nCount, long hOriginal, long hUpdated, T fUpdatedPct, long hServer, T fServerPct, long hNewData)
{
	LONG lErr;
	MemoryItem* pOriginal;
	MemoryItem* pUpdated;
	MemoryItem* pServer;
	MemoryItem* pNewData;

	if (lErr = m_pMemCol->GetData(hOriginal, &pOriginal))
		return lErr;

	if (lErr = m_pMemCol->GetData(hUpdated, &pUpdated))
		return lErr;

	if (lErr = m_pMemCol->GetData(hServer, &pServer))
		return lErr;

	if (lErr = m_pMemCol->GetData(hNewData, &pNewData))
		return lErr;

	T* original = (T*)pOriginal->Data();
	T* updated = (T*)pUpdated->Data();
	T* server = (T*)pServer->Data();
	T* newdata = (T*)pNewData->Data();

	combine_data_kernel<T><<<CAFFE_GET_BLOCKS(nCount), CAFFE_CUDA_NUM_THREADS>>>(nCount, original, updated, fUpdatedPct, server, fServerPct, newdata);

	return cudaGetLastError();
}

template long Math<double>::combine_data(int nCount, long hOriginal, long hUpdated, double fUpdatedPct, long hServer, double fServerPct, long hNewData);
template long Math<float>::combine_data(int nCount, long hOriginal, long hUpdated, float fUpdatedPct, long hServer, float fServerPct, long hNewData);


template <typename T>
__global__ void mtx_set_diagonal_kernel(int n, int height, T fVal, T* data)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		data[i + height * i] = fVal;
	}
}

template <class T>
long Math<T>::mtx_set_diagonal(int nCount, int nRows, T fVal, long hData)
{
	LONG lErr;
	MemoryItem* pData;

	if (lErr = m_pMemCol->GetData(hData, &pData))
		return lErr;

	T* data = (T*)pData->Data();

	mtx_set_diagonal_kernel<T><<<CAFFE_GET_BLOCKS(nCount), CAFFE_CUDA_NUM_THREADS>>>(nCount, nRows, fVal, data);

	return cudaGetLastError();
}

template long Math<double>::mtx_set_diagonal(int nCount, int nRows, double fVal, long hData);
template long Math<float>::mtx_set_diagonal(int nCount, int nRows, float fVal, long hData);


template <typename T>
__global__ void mtx_set_diagonal_kernel(int n, int height, T* diag, T fScaleA, T fScaleB, T* data)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		data[i + height * i] = fScaleA * data[i + height * i] + fScaleB * diag[i];
	}
}

template <class T>
long Math<T>::mtx_set_diagonal(int nCount, int nRows, long hDiag, T fScaleA, T fScaleB, long hData)
{
	LONG lErr;
	MemoryItem* pDiag;
	MemoryItem* pData;

	if (lErr = m_pMemCol->GetData(hDiag, &pDiag))
		return lErr;

	if (lErr = m_pMemCol->GetData(hData, &pData))
		return lErr;

	T* diag = (T*)pDiag->Data();
	T* data = (T*)pData->Data();
	
	mtx_set_diagonal_kernel<T><<<CAFFE_GET_BLOCKS(nCount), CAFFE_CUDA_NUM_THREADS>>>(nCount, nRows, diag, fScaleA, fScaleB, data);

	return cudaGetLastError();
}

template long Math<double>::mtx_set_diagonal(int nCount, int nRows, long hDiagonal, double fScaleA, double fScaleB, long hData);
template long Math<float>::mtx_set_diagonal(int nCount, int nRows, long hDiagonal, float fScaleA, float fScaleB, long hData);


template <typename T>
__global__ void mtx_add_col_vector_kernel(int n, int width, int height, T fScale, T* a, T* b, T* y)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		y[i] = a[i] + fScale * b[i / width];
	}
}

template <typename T>
__global__ void mtx_add_row_vector_kernel(int n, int width, int height, T fScale, T* a, T* b, T* y)
{
	for (int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		y[i] = a[i] + fScale * b[i % width];
	}
}

template <class T>
long Math<T>::mtx_add_vector(int nOrientation, int nWidth, int nHeight, T fScale, long hA, long hB, long hY)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pB;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hB, &pB))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	T* a = (T*)pA->Data();
	T* b = (T*)pB->Data();
	T* y = (T*)pY->Data();

	int nCount = nWidth * nHeight;

	if (nOrientation == ORIENTATION_COLS)
		mtx_add_col_vector_kernel<T><<<CAFFE_GET_BLOCKS(nCount), CAFFE_CUDA_NUM_THREADS>>>(nCount, nWidth, nHeight, fScale, a, b, y);
	else
		mtx_add_row_vector_kernel<T><<<CAFFE_GET_BLOCKS(nCount), CAFFE_CUDA_NUM_THREADS>>>(nCount, nWidth, nHeight, fScale, a, b, y);

	return cudaGetLastError();
}

template long Math<double>::mtx_add_vector(int nOrientation, int nWidth, int nHeight, double fScale, long hA, long hB, long hY);
template long Math<float>::mtx_add_vector(int nOrientation, int nWidth, int nHeight, float fScale, long hA, long hB, long hY);


template <typename T, bool checkBounds>
__global__ void mtx_transpose_add(T* a, T* b, T* y, int width, int height, int initialHeight, T fScaleA, T fScaleB)
{
	const int idxYA = blockIdx.y * ADD_BLOCK_SIZE + threadIdx.y;
	const int idxXA = blockIdx.x * ADD_BLOCK_SIZE + threadIdx.x;
	const int idxYB = blockIdx.y * ADD_BLOCK_SIZE + threadIdx.y;
	const int idxXB = blockIdx.x * ADD_BLOCK_SIZE + threadIdx.x;

	__shared__ T smem[ADD_BLOCK_SIZE][ADD_BLOCK_SIZE + 1];

	if (!checkBounds || (idxYB < height && idxXB < width))
	{
		const unsigned int bIdx = idxXB * initialHeight + idxYB;
		smem[threadIdx.x][threadIdx.y] = b[bIdx];
	}

	__syncthreads();

	if (!checkBounds || (idxXA < width && idxYA < height))
	{
		const int idx = idxYA * width + idxXA;
		y[idx] = fScaleA * a[idx] + fScaleB * smem[threadIdx.y][threadIdx.x];
	}
}

template <typename T, bool checkBounds>
__global__ void mtx_transpose_mul(T* a, T* b, T* y, int width, int height, int initialHeight)
{
	const int idxYA = blockIdx.y * ADD_BLOCK_SIZE + threadIdx.y;
	const int idxXA = blockIdx.x * ADD_BLOCK_SIZE + threadIdx.x;
	const int idxYB = blockIdx.y * ADD_BLOCK_SIZE + threadIdx.y;
	const int idxXB = blockIdx.x * ADD_BLOCK_SIZE + threadIdx.x;

	__shared__ T smem[ADD_BLOCK_SIZE][ADD_BLOCK_SIZE + 1];

	if (!checkBounds || (idxYB < height && idxXB < width))
	{
		const unsigned int bIdx = idxXB * initialHeight + idxYB;
		smem[threadIdx.x][threadIdx.y] = b[bIdx];
	}

	__syncthreads();

	if (!checkBounds || (idxXA < width && idxYA < height))
	{
		const int idx = idxYA * width + idxXA;
		y[idx] = a[idx] * smem[threadIdx.y][threadIdx.x];
	}
}

template <typename T, bool checkBounds>
__global__ void mtx_transpose_div(T* a, T* b, T* y, int width, int height, int initialHeight)
{
	const int idxYA = blockIdx.y * ADD_BLOCK_SIZE + threadIdx.y;
	const int idxXA = blockIdx.x * ADD_BLOCK_SIZE + threadIdx.x;
	const int idxYB = blockIdx.y * ADD_BLOCK_SIZE + threadIdx.y;
	const int idxXB = blockIdx.x * ADD_BLOCK_SIZE + threadIdx.x;

	__shared__ T smem[ADD_BLOCK_SIZE][ADD_BLOCK_SIZE + 1];

	if (!checkBounds || (idxYB < height && idxXB < width))
	{
		const unsigned int bIdx = idxXB * initialHeight + idxYB;
		smem[threadIdx.x][threadIdx.y] = b[bIdx];
	}

	__syncthreads();

	if (!checkBounds || (idxXA < width && idxYA < height))
	{
		const int idx = idxYA * width + idxXA;
		y[idx] = a[idx] / smem[threadIdx.y][threadIdx.x];
	}
}

template <class T>
long Math<T>::mtx_transpose_op(int nOp, int nWidth, int nHeight, long hA, long hB, long hY, T fScaleA, T fScaleB)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pB;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hB, &pB))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	T* a = (T*)pA->Data();
	T* b = (T*)pB->Data();
	T* y = (T*)pY->Data();

	int nNumBlocksX = DIVUP(nWidth, ADD_BLOCK_SIZE);
	int nNumBlocksY = max(1, min(DIVUP(nHeight, ADD_BLOCK_SIZE), NUM_BLOCKS_MAX));
	bool bCheckBounds = !(nWidth % ADD_BLOCK_SIZE == 0 && nHeight % ADD_BLOCK_SIZE == 0);

	if (nNumBlocksX >= NUM_BLOCKS_MAX)
		return ERROR_PARAM_OUT_OF_RANGE;

	dim3 gridSize(nNumBlocksX, nNumBlocksY, 1);
	dim3 blockSize(ADD_BLOCK_SIZE, ADD_BLOCK_SIZE, 1);

	int nNumRowsProcessed = 0;

	while (nNumRowsProcessed < nHeight)
	{
		T* a1 = a + (nNumRowsProcessed * nWidth);
		T* b1 = b + (nNumRowsProcessed);
		T* y1 = y + (nNumRowsProcessed * nWidth);

		switch (nOp)
		{
			case TRANSPOSE_OP_ADD:
				if (bCheckBounds)
					mtx_transpose_add<T, true><<<gridSize, blockSize>>>(a1, b1, y1, nWidth, nHeight - nNumRowsProcessed, nHeight, fScaleA, fScaleB);
				else
					mtx_transpose_add<T, false><<<gridSize, blockSize>>>(a1, b1, y1, nWidth, nHeight - nNumRowsProcessed, nHeight, fScaleA, fScaleB);
				break;

			case TRANSPOSE_OP_MUL:
				if (bCheckBounds)
					mtx_transpose_mul<T, true><<<gridSize, blockSize>>>(a1, b1, y1, nWidth, nHeight - nNumRowsProcessed, nHeight);
				else
					mtx_transpose_mul<T, false><<<gridSize, blockSize>>>(a1, b1, y1, nWidth, nHeight - nNumRowsProcessed, nHeight);
				break;

			case TRANSPOSE_OP_DIV:
				if (bCheckBounds)
					mtx_transpose_div<T, true><<<gridSize, blockSize>>>(a1, b1, y1, nWidth, nHeight - nNumRowsProcessed, nHeight);
				else
					mtx_transpose_div<T, false><<<gridSize, blockSize>>>(a1, b1, y1, nWidth, nHeight - nNumRowsProcessed, nHeight);
				break;
		}

		if (lErr = cudaGetLastError())
			return lErr;

		nNumRowsProcessed += gridSize.y * ADD_BLOCK_SIZE;
		gridSize.y = max(1, min(DIVUP(nHeight - nNumRowsProcessed, ADD_BLOCK_SIZE), NUM_BLOCKS_MAX));
	}

	return cudaGetLastError();
}

template long Math<double>::mtx_transpose_op(int nOp, int nWidth, int nHeight, long hA, long hB, long hY, double fScaleA, double fScaleB);
template long Math<float>::mtx_transpose_op(int nOp, int nWidth, int nHeight, long hA, long hB, long hY, float fScaleA, float fScaleB);


template <typename T>
__global__ void mtx_aggregate_cols_sum_kernel(T* a, T* y, int width, int height)
{
	const int idx = blockIdx.x * blockDim.x + threadIdx.x;

	a += idx;

	if (idx < width)
	{
		T fSum = 0;

		for (int j=0; j<height; j++)
		{
			fSum += *a;
			a += width;
		}

		y[idx] = fSum;
	}
}

template <typename T>
__global__ void mtx_aggregate_cols_max_kernel(T* a, T* y, int width, int height)
{
	const int idx = blockIdx.x * blockDim.x + threadIdx.x;

	a += idx;

	if (idx < width)
	{
		T fMax = *a;
		a += width;

		for (int j=1; j<height; j++)
		{
			fMax = max(*a, fMax);
			a += width;
		}

		y[idx] = fMax;
	}
}

template <typename T>
__global__ void mtx_aggregate_cols_min_kernel(T* a, T* y, int width, int height)
{
	const int idx = blockIdx.x * blockDim.x + threadIdx.x;

	a += idx;

	if (idx < width)
	{
		T fMin = *a;
		a += width;

		for (int j=1; j<height; j++)
		{
			fMin = min(*a, fMin);
			a += width;
		}

		y[idx] = fMin;
	}
}

template <class T>
long Math<T>::mtx_aggregate_cols(int nOp, int nWidth, int nHeight, long hA, long hY)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	T* a = (T*)pA->Data();
	T* y = (T*)pY->Data();

	int nNumThreadsPerBlock = NUM_SUM_COLS_THREADS_PER_BLOCK;
	int nNumBlocks = DIVUP(nWidth, nNumThreadsPerBlock);

	if (nNumBlocks * nNumThreadsPerBlock < nWidth)
		return ERROR_PARAM_OUT_OF_RANGE;

	if (nNumBlocks >= NUM_BLOCKS_MAX)
		return ERROR_PARAM_OUT_OF_RANGE;

	switch (nOp)
	{
		case AGGREGATION_SUM:
			mtx_aggregate_cols_sum_kernel<T><<<nNumBlocks, nNumThreadsPerBlock>>>(a, y, nWidth, nHeight);
			break;

		case AGGREGATION_MAX:
			mtx_aggregate_cols_max_kernel<T><<<nNumBlocks, nNumThreadsPerBlock>>>(a, y, nWidth, nHeight);
			break;

		case AGGREGATION_MIN:
			mtx_aggregate_cols_min_kernel<T><<<nNumBlocks, nNumThreadsPerBlock>>>(a, y, nWidth, nHeight);
			break;
	}

	return cudaGetLastError();
}

template long Math<double>::mtx_aggregate_cols(int nOp, int nWidth, int nHeight, long hA, long hY);
template long Math<float>::mtx_aggregate_cols(int nOp, int nWidth, int nHeight, long hA, long hY);


template<> 
long Math<double>::mtx_aggregate_rows_sum(int nWidth, int nHeight, double* a, double* ones, double* y)
{
	double dfAlpha = 1.0;
	double dfBeta = 0.0;
	int nCols = nWidth;
	int nRows = nHeight;

	return cublasDgemv(m_cublas, CUBLAS_OP_T, nCols, nRows, &dfAlpha, a, nCols, ones, 1, &dfBeta, y, 1); 
}

template<> 
long Math<float>::mtx_aggregate_rows_sum(int nWidth, int nHeight, float* a, float* ones, float* y)
{
	float fAlpha = 1.0;
	float fBeta = 0.0;
	int nCols = nWidth;
	int nRows = nHeight;

	return cublasSgemv(m_cublas, CUBLAS_OP_T, nCols, nRows, &fAlpha, a, nCols, ones, 1, &fBeta, y, 1); 
}

template <class T>
long Math<T>::mtx_aggregate_rows(int nOp, int nWidth, int nHeight, long hA, long hOnes, long hY)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pY;
	MemoryItem* pOnes;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	if (lErr = m_pMemCol->GetData(hOnes, &pOnes))
		return lErr;

	T* a = (T*)pA->Data();
	T* y = (T*)pY->Data();
	T* ones = (T*)pOnes->Data();

	switch (nOp)
	{
		case AGGREGATION_SUM:
			return mtx_aggregate_rows_sum(nWidth, nHeight, a, ones, y);

		case AGGREGATION_MAX:
			return ERROR_NOT_IMPLEMENTED;

		case AGGREGATION_MIN:
			return ERROR_NOT_IMPLEMENTED;

		default:
			return ERROR_NOT_IMPLEMENTED;
	}
}

template long Math<double>::mtx_aggregate_rows(int nOp, int nWidth, int nHeight, long hA, long hOnes, long hY);
template long Math<float>::mtx_aggregate_rows(int nOp, int nWidth, int nHeight, long hA, long hOnes, long hY);


template <>
long Math<double>::mtx_transpose(int nWidth, int nHeight, long hA, long hY)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	double* a = (double*)pA->Data();
	double* y = (double*)pY->Data();

	int nM = nHeight;
	int nN = nWidth;
	double dfAlpha = 1.0;
	double dfBeta = 0.0;

	return cublasDgeam(m_cublas, CUBLAS_OP_T, CUBLAS_OP_N, nM, nN, &dfAlpha, a, nN, &dfBeta, a, nM, y, nM);
}


template <>
long Math<float>::mtx_transpose(int nWidth, int nHeight, long hA, long hY)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	float* a = (float*)pA->Data();
	float* y = (float*)pY->Data();

	int nM = nHeight;
	int nN = nWidth;
	float fAlpha = 1.0;
	float fBeta = 0.0;

	return cublasSgeam(m_cublas, CUBLAS_OP_T, CUBLAS_OP_N, nM, nN, &fAlpha, a, nN, &fBeta, a, nM, y, nM);
}

//-----------------------------------------------------------------------------
//	Mean center colums where the mean of each column is calculated and subtracted
//	from A and placed into Y.  The column sums are placed in B.
//
//	hA = nHeight (N) x nWidth (D) matrix.
//	hB - nWidth (D) x 1 vector for sum values.
//  hY = nHeight (N) x nWidth (D) matrix (can be inplace where hY == hA)
//
//	Output:
//	hY - mean centered (by column) data of original hA.
//-----------------------------------------------------------------------------
template <class T>
long Math<T>::mtx_meancenter_by_column(int nWidth, int nHeight, long hA, long hB, long hY, bool bNormalize)
{
	long lErr;
	int nN = nHeight;
	int nD = nWidth;


	if (lErr = copy(nD, hA, hB, 0, 0, -1))
		return lErr;

	if (hA != hY)
	{
		if (lErr = copy(nD * nN, hA, hY, 0, 0, -1))
			return lErr;
	}

	for (int i=1; i<nN; i++)
	{
		if (lErr = axpy(nD, T(1.0), hY, hB, i * nD, 0))
			return lErr;
	}

	for (int i=0; i<nN; i++)
	{
		if (lErr = axpy(nD, T(-1.0/nN), hB, hY, 0, i * nD))
			return lErr;
	}

	if (bNormalize)
	{
		T fMax;

		if (lErr = maxval(nN * nD, hY, &fMax))
			return lErr;

		if (lErr = scal(nN * nD, T(1.0/fMax), hY))
			return lErr;
	}

	return cudaGetLastError();
}

template long Math<double>::mtx_meancenter_by_column(int nWidth, int nHeight, long hA, long hB, long hY, bool bNormalize);
template long Math<float>::mtx_meancenter_by_column(int nWidth, int nHeight, long hA, long hB, long hY, bool bNormalize);


template <typename T>
__global__ void mtx_euclidean_dist_kernel(T* in_X, T* in_Y, T* out, int n, int m, int nStart, int nEnd)
{
	__shared__ T Ys[16][16];
	__shared__ T Xs[16][16];
	int bx = blockIdx.x;
	int by = blockIdx.y;
	int tx = threadIdx.x;
	int ty = threadIdx.y;
	int yBegin = by * 16 * m;
	int xBegin = bx * 16 * m;
	int yEnd = yBegin + m - 1;
	T tmp;
	T s = 0;
	int x;
	int y;

	for (y = yBegin, x = xBegin; y <= yEnd; y += 16, x += 16)
	{
		Ys[ty][tx] = in_Y[y + ty * m + tx];
		Xs[tx][ty] = in_X[x + ty * m + tx];
		__syncthreads();

		for (int k=0; k<16; k++)
		{
			tmp = Ys[ty][k] - Xs[k][tx];
			s += tmp * tmp;
		}
		__syncthreads();
	}

	int o = by * 16 * n + ty * n + bx * 16 + tx;

	if (o >= nStart && o < nEnd)
		out[o - nStart] = s;
}

template <class T>
long Math<T>::mtx_euclidean_dist(long hX, long hY, long hOut, int n, int d, int nStart, int nEnd)
{
	LONG lErr;
	MemoryItem* pX;
	MemoryItem* pY;
	MemoryItem* pOut;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	if (lErr = m_pMemCol->GetData(hOut, &pOut))
		return lErr;

	T* x = (T*)pX->Data();
	T* y = (T*)pY->Data();
	T* out = (T*)pOut->Data();

	dim3 block(16, 16);
	dim3 grid((int)ceil((float)n / (float)16), (int)ceil((float)n / (float)16));

	mtx_euclidean_dist_kernel<T><<<grid, block>>>(x, y, out, n, d, nStart, nEnd);

	return cudaGetLastError();
}

template long Math<double>::mtx_euclidean_dist(long hX, long hY, long hOut, int n, int d, int nStart, int nEnd);
template long Math<float>::mtx_euclidean_dist(long hX, long hY, long hOut, int n, int d, int nStart, int nEnd);


//------------------------------------------------------------------------------
//  Multiple matrices
//
//  C(m x n) = A(m x k) * B(k x n)
//  
//	CUBLAS uses Fortran Style matrix ordering so,
//	C++ F = D * E is actually F = E * D in Fortran Style.
//	See http://peterwittek.com/cublas-matrix-c-style.html for gmemm ordering
//------------------------------------------------------------------------------
template <>
long Math<double>::mtx_dot(int nM, int nN, int nK, long hA, long hB, long hC)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pB;
	MemoryItem* pC;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hB, &pB))
		return lErr;

	if (lErr = m_pMemCol->GetData(hC, &pC))
		return lErr;

	double* a = (double*)pA->Data();
	double* b = (double*)pB->Data();
	double* c = (double*)pC->Data();
	double dfAlpha = 1.0;
	double dfBeta = 0.0;
	int lda = nN;
	int ldb = nK;
	int ldc = nK;

	return cublasDgemm(m_cublas, CUBLAS_OP_N, CUBLAS_OP_N, nK, nM, nN, &dfAlpha, b, ldb, a, lda, &dfBeta, c, ldc);
}

template <>
long Math<float>::mtx_dot(int nM, int nN, int nK, long hA, long hB, long hC)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pB;
	MemoryItem* pC;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hB, &pB))
		return lErr;

	if (lErr = m_pMemCol->GetData(hC, &pC))
		return lErr;

	float* a = (float*)pA->Data();
	float* b = (float*)pB->Data();
	float* c = (float*)pC->Data();
	float fAlpha = 1.0;
	float fBeta = 0.0;
	int lda = nN;
	int ldb = nK;
	int ldc = nK;

	return cublasSgemm(m_cublas, CUBLAS_OP_N, CUBLAS_OP_N, nK, nM, nN, &fAlpha, b, ldb, a, lda, &fBeta, c, ldc);
}


template <typename T> 
__device__ int sgn(T val) 
{
    return (T(0) < val) - (val < T(0));
}

template <typename T>
__global__ void tsne_update_gains_kernel(unsigned int n, T* dY, T* uY, T* gains, T fGainFactor1, T fGainFactor2)
{
	for (unsigned int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		T fVal = (sgn(dY[i]) != sgn(uY[i])) ? (gains[i] + fGainFactor1) : (gains[i] * fGainFactor2);
		gains[i] = (fVal < 0.01) ? 0.01 : fVal;
	}
}

template <typename T>
__global__ void tsne_update_gradient_kernel(unsigned int n, T fMomentum, T fLearningRate, T* dY, T* uY, T* gains, T* Y)
{
	for (unsigned int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		T fVal = fMomentum * uY[i] - fLearningRate * gains[i] * dY[i];
		uY[i] = fVal;
		Y[i] += fVal;
	}
}

template <class T>
long Math<T>::tsne_update(unsigned int n, T fMomentum, T fLearningRate, long hdY, long huY, long hGains, long hY, T fGainFactor1, T fGainFactor2)
{
	LONG lErr;
	MemoryItem* pdY;
	MemoryItem* puY;
	MemoryItem* pGains;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hdY, &pdY))
		return lErr;

	if (lErr = m_pMemCol->GetData(huY, &puY))
		return lErr;

	if (lErr = m_pMemCol->GetData(hGains, &pGains))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	T* dY = (T*)pdY->Data();
	T* uY = (T*)puY->Data();
	T* gains = (T*)pGains->Data();
	T* Y = (T*)pY->Data();

	tsne_update_gains_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, dY, uY, gains, fGainFactor1, fGainFactor2);

	if (lErr = cudaGetLastError())
		return lErr;

	tsne_update_gradient_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, fMomentum, fLearningRate, dY, uY, gains, Y);

	return cudaGetLastError();
}

template long Math<double>::tsne_update(unsigned int n, double dfMomentum, double dfLearningRate, long hdY, long huY, long hGains, long hY, double dfGainFactor1, double dfGainFactor2);
template long Math<float>::tsne_update(unsigned int n, float dfMomentum, float dfLearningRate, long hdY, long huY, long hGains, long hY, float fGainFactor1, float fGainFactor2);


template <typename T>
__global__ void tsne_update_grad_kernel(unsigned int n, const T* posF, const T* negF, const T fSumQ, T* dc)
{
	for (unsigned int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		dc[i] = posF[i] - (negF[i] / fSumQ);
	}
}

template <class T>
long Math<T>::tsne_update_grad(unsigned int n, long hPosF, long hNegF, T fSumQ, long hdC)
{
	LONG lErr;
	MemoryItem* pPosF;
	MemoryItem* pNegF;
	MemoryItem* pdC;

	if (lErr = m_pMemCol->GetData(hPosF, &pPosF))
		return lErr;

	if (lErr = m_pMemCol->GetData(hNegF, &pNegF))
		return lErr;

	if (lErr = m_pMemCol->GetData(hdC, &pdC))
		return lErr;

	T* posF = (T*)pPosF->Data();
	T* negF = (T*)pNegF->Data();
	T* dc = (T*)pdC->Data();

	tsne_update_grad_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, posF, negF, fSumQ, dc);

	return cudaGetLastError();
}

template long Math<double>::tsne_update_grad(unsigned int n, long hPosF, long hNegF, double dfSumQ, long hdC);
template long Math<float>::tsne_update_grad(unsigned int n, long hPosF, long hNegF, float fSumQ, long hdC);


template <class T>
long Math<T>::tsne_compute_squared_euclidean_distance(unsigned int N, unsigned int D, long hW, long hX, T* pDD)
{
	LONG lErr;
	MemoryItem* pW;
	MemoryItem* pX;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hW, &pW))
		return lErr;

	T* w = (T*)pW->Data();
	T* x = (T*)pX->Data();
	unsigned int nXnD = 0;

	for (unsigned int n=0; n<N; ++n, nXnD += D)
	{
		unsigned int nXmD = nXnD + D;
		unsigned int nCurElm = n * N + n;
		unsigned int nCurElmSym = nCurElm + N;

		pDD[nCurElm] = T(0.0);

		for (unsigned int m = n + 1; m < N; ++m, nXmD += D, nCurElmSym += N)
		{			
			pDD[++nCurElm] = T(0.0);
			T fSumSqDiff;

			if (lErr = sumsqdiff(D, w, x + nXnD, x + nXmD, &fSumSqDiff))
				return lErr;

			pDD[nCurElm] = fSumSqDiff;
			pDD[nCurElmSym] = fSumSqDiff;
		}
	}

	return 0;
}

template long Math<double>::tsne_compute_squared_euclidean_distance(unsigned int n, unsigned int d, long hW, long hX, double* pDD);
template long Math<float>::tsne_compute_squared_euclidean_distance(unsigned int n, unsigned int d, long hW, long hX, float* pDD);


template <class T>
long Math<T>::tsne_compute_squared_euclidean_distance(unsigned int N, unsigned int D, T* x, T* pDD)
{
	const T* XnD = x;
	for (unsigned int n=0; n<N; ++n, XnD += D)
	{
		const T* XmD = XnD + D;
		T* curr_elem = &pDD[n * N + n];
		*curr_elem = T(0.0);
		T* curr_elem_sym = curr_elem + N;

		for (unsigned int m = n + 1; m < N; ++m, XmD += D, curr_elem_sym += N)
		{		
			*(++curr_elem) = T(0.0);
			for (unsigned int d=0; d<D; d++)
			{
				*curr_elem += (XnD[d] - XmD[d]) * (XnD[d] - XmD[d]);
			}
			*curr_elem_sym = *curr_elem;
		}
	}

	return 0;
}

template long Math<double>::tsne_compute_squared_euclidean_distance(unsigned int n, unsigned int d, double* x, double* pDD);
template long Math<float>::tsne_compute_squared_euclidean_distance(unsigned int n, unsigned int d, float* x, float* pDD);


template <class T>
long Math<T>::tsne_compute_q_matrix(unsigned int N, T* pDD_on_host, T* pQ_on_host, T* pfSumQ)
{
	T fSumQ = 0;
	unsigned int nN = 0;

	for (unsigned int n=0; n<N; n++)
	{
		for (unsigned int m=0; m<N; m++)
		{
			if (n != m)
			{
				T fVal = T(1.0 / (1.0 + pDD_on_host[nN + m]));
				pQ_on_host[nN + m] = fVal;
				fSumQ += fVal;
			}
			else
			{
				pQ_on_host[nN + m] = T(0.000001);
			}
		}

		nN += N;
	}

	*pfSumQ = fSumQ;

	return 0;
}

template long Math<double>::tsne_compute_q_matrix(unsigned int n, double* pDD_on_host, double* pQ_on_host, double* pfSumQ);
template long Math<float>::tsne_compute_q_matrix(unsigned int n, float* pDD_on_host, float* pQ_on_host, float* pfSumQ);


template <class T>
long Math<T>::tsne_compute_exact_gradient(unsigned int N, unsigned int D, T* pY_on_host, T* pP_on_host, T* pQ_on_host, T* pdC_on_host, T fSumQ)
{
	unsigned int nN = 0;
	unsigned int nD = 0;

	for (unsigned int n=0; n<N; n++)
	{
		unsigned int mD = 0;

		for (unsigned int m=0; m<N; m++)
		{
			if (n != m)
			{
				T fMult = (pP_on_host[nN + m] - (pQ_on_host[nN + m] / fSumQ)) * pQ_on_host[nN + m];
				
				for (unsigned int d=0; d<D; d++)
				{
					pdC_on_host[nD + d] += (pY_on_host[nD + d] - pY_on_host[mD + d]) * fMult;
				}
			}

			mD += D;
		}

		nN += N;
		nD += D;
	}

	return 0;
}

template long Math<double>::tsne_compute_exact_gradient(unsigned int N, unsigned int D, double* pY_on_host, double* pP_on_host, double* pQ_on_host, double* pdC_on_host, double dfSumQ);
template long Math<float>::tsne_compute_exact_gradient(unsigned int N, unsigned int D, float* pY_on_host, float* pP_on_host, float* pQ_on_host, float* pdC_on_host, float fSumQ);


template <typename T>
__global__ void tsne_compute_exact_error_kernel(unsigned int n, const T* p, const T* q, T* y)
{
	for (unsigned int i=blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		y[i] = p[i] * log((p[i] + 0.000001) / (q[i] + 0.000001));
	}
}

template <class T>
long Math<T>::tsne_compute_exact_error(unsigned int n, long hP, long hQ, long hY)
{
	LONG lErr;
	MemoryItem* pP;
	MemoryItem* pQ;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hP, &pP))
		return lErr;

	if (lErr = m_pMemCol->GetData(hQ, &pQ))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	T* p = (T*)pP->Data();
	T* q = (T*)pQ->Data();
	T* y = (T*)pY->Data();

	tsne_compute_exact_error_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, p, q, y);

	return cudaGetLastError();
}

template long Math<double>::tsne_compute_exact_error(unsigned int n, long hP, long hQ, long hWork);
template long Math<float>::tsne_compute_exact_error(unsigned int n, long hP, long hQ, long hWork);


template <class T>
long Math<T>::tsne_symmetrize_matrix(unsigned int N, long hRowP, long hColP, long hValP, unsigned int* pnRowCount)
{
	tsnegHandle<T>* tsne = new tsnegHandle<T>(N, 1, 0, hValP, hRowP, hColP, 0, 0);
	unsigned int nRowCount = 0;

	tsne->Initialize(m_pMem, this);
	tsne->SymmetrizeMatrix(&nRowCount);
	tsne->CleanUp();
	delete tsne;

	*pnRowCount = nRowCount;

	return 0;
}

template long Math<double>::tsne_symmetrize_matrix(unsigned int N, long hRowP, long hColP, long hValP, unsigned int* pnRowCount);
template long Math<float>::tsne_symmetrize_matrix(unsigned int N, long hRowP, long hColP, long hValP, unsigned int* pnRowCount);

template <class T>
long Math<T>::tsne_compute_knn_bounds(unsigned int n, long hData, T fPctInCircle, T* pfMinX, T* pfMinY, T* pfMaxX, T* pfMaxY)
{
	*pfMinX = 0;
	*pfMinY = 0;
	*pfMaxX = 0;
	*pfMaxY = 0;

	HostBuffer<T>* pHostBuf = m_pMem->GetHostBuffer(hData);
	if (pHostBuf == NULL)
		return ERROR_MEMORY_OUT;

	T* data = (T*)pHostBuf->Data();
	T minX = (sizeof(T) == 4) ? FLT_MAX : DBL_MAX;
	T minY = minX;
	T maxX = -minX;
	T maxY = -minY;
	T x;
	T y;

	if (fPctInCircle == T(1))
	{
		for (unsigned int i=0; i<n; i++)
		{
			x = data[i];
			y = data[i + n];
			minX = min(minX, x);
			minY = min(minY, y);
			maxX = max(maxX, x);
			maxY = max(maxY, y);
		}
	}
	else
	{		
		PointDist<T>* rgPointDistances = new PointDist<T>[n];
		PointDist<T>* rgNeighbors = new PointDist<T>[n];

		for (unsigned int i=0; i<n; i++)
		{
			T x1 = data[i];
			T y1 = data[i + n];

			for (int j=0; j<(int)n; j++)
			{
				if (i != j)
				{
					T x2 = data[j];
					T y2 = data[j + n];
					T dx = x1 - x2;
					T dy = y1 - y2;
					T fdist = std::sqrt((dx * dx) + (dy * dy));
					rgNeighbors[j].x = x2;
					rgNeighbors[j].y = y2;
					rgNeighbors[j].d = fdist;
				}
				else
				{
					rgNeighbors[j].x = x1;
					rgNeighbors[j].y = y1;
					rgNeighbors[j].d = 0;
				}
			}

			T fTotalDist = 0;

			for (int j=0; j<(int)n; j++)
			{
				fTotalDist += rgNeighbors[j].d;
			}

			rgPointDistances[i].x = x1;
			rgPointDistances[i].y = y1;
			rgPointDistances[i].d = fTotalDist;
		}

		std::sort(rgPointDistances, rgPointDistances + n, sortPointDist<T>);
		int nCount = (int)(n * fPctInCircle);

		for (int i=0; i<nCount; i++)
		{
			T x = rgPointDistances[i].x;
			T y = rgPointDistances[i].y;
			minX = min(minX, x);
			minY = min(minY, y);
			maxX = max(maxX, x);
			maxY = max(maxY, y);
		}

		delete rgPointDistances;
		delete rgNeighbors;
	}

	*pfMinX = minX;
	*pfMinY = minY;
	*pfMaxX = maxX;
	*pfMaxY = maxY;

	return 0;
}

template long Math<double>::tsne_compute_knn_bounds(unsigned int n, long hData, double fPctInCircle, double* pfMinX, double* pfMinY, double* pfMaxX, double* pfMaxY);
template long Math<float>::tsne_compute_knn_bounds(unsigned int n, long hData, float fPctInCircle, float* pfMinX, float* pfMinY, float* pfMaxX, float* pfMaxY);


template <typename T>
__global__ void gaussian_blur_kernel(const int rows, const int cols, const T* filter, const T* input, T* output)
{
	int r = blockIdx.y * blockDim.y + threadIdx.y;
	int c = blockIdx.x * blockDim.x + threadIdx.x;

	if (r >= rows || c >= cols)
		return;

	T fBlur = T(0.0);
	int width = cols - 1;
	int height = rows - 1;
	int nIdxFlt = 0;
	int nIdx;

	for (int i = -1; i <= 1; i++)
	{
		for (int j = -1; j <= 1; j++)
		{
			// Clamp the filter to the image border.
			int h = min(max(r + i, 0), height);
			int w = min(max(c + j, 0), width);

			// Blur is a product of current pixel value and weight of that pixel.
			// Remember that sum of all weights should equal 1 (hence used normalized weights).
			nIdx = h * cols + w;
			T fPixel = input[nIdx];
			T fWeight = filter[nIdxFlt];
			nIdxFlt++;

			fBlur += fPixel * fWeight;
		}
	}

	nIdx = r * cols + c;
	output[nIdx] = fBlur;
}

template <class T>
long Math<T>::gaussian_blur(int n, int nChannels, int h, int w, T fSigma, long hX, long hY)
{
	LONG lErr;
	MemoryItem* pX;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hX, &pX))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	int nDim = h * w;
	int nIdx = 0;
	T rgFilter[9];
	T fSigmaSq = fSigma * fSigma;
	T fFactor1 = T(1 / (2 * M_PI * fSigmaSq));
	T fFactor2 = 2 * fSigmaSq;
	T fExp;
	T fSum = 0;

	// Fill the covariance matrix
	for (int y = -1; y <= 1; y++)
	{
		for (int x = -1; x <= 1; x++)
		{
			fExp = ((x * x) + (y * y)) / fFactor2;
			rgFilter[nIdx] = fFactor1 * ::exp(-fExp);
			fSum += rgFilter[nIdx];
			nIdx++;
		}
	}

	// Normalize the matrix.
	for (int y = 0; y < 3; y++)
	{
		for (int x = 0; x < 3; x++)
		{
			nIdx = y * 3 + x;
			rgFilter[nIdx] /= fSum;
		}
	}

	T* pFilterDev;
	if (lErr = cudaMalloc(&pFilterDev, sizeof(T) * 9))
		return lErr;

	if (lErr = cudaMemcpy(pFilterDev, rgFilter, sizeof(T) * 9, cudaMemcpyHostToDevice))
	{
		cudaFree(pFilterDev);
		return lErr;
	}

	T* pData = (T*)pX->Data();
	T* pBlur = (T*)pY->Data();

	int BLOCK_WIDTH = 32;
	int x = static_cast<int>(ceilf(static_cast<float>(w) / BLOCK_WIDTH));
	int y = static_cast<int>(ceilf(static_cast<float>(h) / BLOCK_WIDTH));
	const dim3 grid(x, y, 1);
	const dim3 block(BLOCK_WIDTH, BLOCK_WIDTH, 1);

	// Blur each channel individually.
	for (int c = 0; c < nChannels; c++)
	{
		gaussian_blur_kernel << <grid, block >> > (h, w, pFilterDev, pData, pBlur);
		if (lErr = cudaGetLastError())
		{
			cudaFree(pFilterDev);
			return lErr;
		}

		pData += nDim;
		pBlur += nDim;
	}

	cudaFree(pFilterDev);

	return 0;
}

template long Math<double>::gaussian_blur(int n, int c, int h, int w, double dfSigma, long hX, long hY);
template long Math<float>::gaussian_blur(int n, int c, int h, int w, float fSigma, long hX, long hY);

template <typename T>
__global__ void hamming_diff_kernel(int n, const T threshold, const T* x, T* y, T* out)
{
	for (int i = blockIdx.x * blockDim.x + threadIdx.x; i<n; i += blockDim.x * gridDim.x)
	{
		out[i] =  ((x[i] > threshold) ? 1 : 0) - ((y[i] > threshold) ? 1 : 0);
	}
}

template <class T>
long Math<T>::hamming_diff(int n, T fThreshold, long hA, long hB, long hY, int nOffA, int nOffB, int nOffY)
{
	LONG lErr;
	MemoryItem* pA;
	MemoryItem* pB;
	MemoryItem* pY;

	if (lErr = m_pMemCol->GetData(hA, &pA))
		return lErr;

	if (lErr = m_pMemCol->GetData(hB, &pB))
		return lErr;

	if (lErr = m_pMemCol->GetData(hY, &pY))
		return lErr;

	T* a = (T*)pA->Data();
	T* b = (T*)pB->Data();
	T* y = (T*)pY->Data();

	if (nOffA > 0)
		a += nOffA;

	if (nOffB > 0)
		b += nOffB;

	if (nOffY > 0)
		y += nOffY;

	hamming_diff_kernel<T><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, fThreshold, a, b, y);
	
	return cudaGetLastError();
}

template long Math<double>::hamming_diff(int n, double dfThreshold, long hA, long hB, long hY, int nOffA, int nOffB, int nOffY);
template long Math<float>::hamming_diff(int n, float fThreshold, long hA, long hB, long hY, int nOffA, int nOffB, int nOffY);

template <class T>
long Math<T>::calc_batch_dist(int nDistMethod, T fThreshold, int nItemDim, long hS, long hT, long hW, const int nDim0, const int nDim1, T* rgOffsets, T* rgDist)
{
	LONG lErr;
	MemoryItem* pS;
	MemoryItem* pT;
	MemoryItem* pW;

	if (lErr = m_pMemCol->GetData(hS, &pS))
		return lErr;

	if (lErr = m_pMemCol->GetData(hT, &pT))
		return lErr;

	if (lErr = m_pMemCol->GetData(hW, &pW))
		return lErr;

	T* s = (T*)pS->Data();
	T* t = (T*)pT->Data();
	T* w = (T*)pW->Data();
	int nCreatedCount = 0;
	cudaStream_t* streams = new cudaStream_t[nDim0];
	bool bReset = true;

	if (streams == NULL)
		goto cleanup;

	for (int i = 0; i < nDim0; i++)
	{
		if (lErr = cudaStreamCreate(&streams[i]))
			goto cleanup;

		nCreatedCount++;

		if (lErr = cublasSetStream(m_cublas, streams[i]))
			goto cleanup;

		int nOffset1 = (int)rgOffsets[i * 2 + 0];
		int nOffset2 = (int)rgOffsets[i * 2 + 1];
		T* s1 = s + nOffset1;
		T* t1 = t + nOffset2;
		T* w1 = w + nOffset2;

		if (nDistMethod == DISTANCE_METHOD_HAMMING)
		{
			hamming_diff_kernel<T><<<CAFFE_GET_BLOCKS(nItemDim), CAFFE_CUDA_NUM_THREADS, 0, streams[i]>>>(nItemDim, fThreshold, s1, t1, w1);
			if (lErr = cudaGetLastError())
				goto cleanup;
		}
		else
		{
			if (lErr = sumsqdiff(nItemDim, w1, s1, t1, &rgDist[i], streams[i]))
				goto cleanup;
		}
	}

	cudaDeviceSynchronize();
	cublasSetStream(m_cublas, NULL);
	bReset = false;

	for (int i = 0; i < nDim0; i++)
	{
		int nOffset2 = (int)rgOffsets[i * 2 + 1];
		T* w1 = w + nOffset2;

		if (lErr = asum(nItemDim, w1, &rgDist[i]))
			goto cleanup;

		if (nDistMethod == DISTANCE_METHOD_EUCLIDEAN)
			rgDist[i] = ::sqrt(rgDist[i]);
	}

cleanup:
	if (bReset)
	{
		cudaDeviceSynchronize();
		cublasSetStream(m_cublas, NULL);
	}

	if (streams != NULL)
	{
		for (int j = nCreatedCount-1; j >= 0; j--)
		{
			cudaStreamDestroy(streams[j]);
		}

		delete streams;
	}

	return lErr;
}

template long Math<double>::calc_batch_dist(int nDistMethod, double fThreshold, int nItemDim, long hS, long hT, long hW, const int nDim0, const int nDim1, double* rgOffsets, double* rgDist);
template long Math<float>::calc_batch_dist(int nDistMethod, float fThreshold, int nItemDim, long hS, long hT, long hW, const int nDim0, const int nDim1, float* rgOffsets, float* rgDist);

//end math.cu