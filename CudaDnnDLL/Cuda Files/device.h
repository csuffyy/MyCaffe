//=============================================================================
//	FILE:	device.h
//
//	DESC:	This file implements the class used to manage the underlying
//			device.
//=============================================================================
#ifndef __DEVICE_CU__
#define __DEVICE_CU__

#include "util.h"
#include "memory.h"
#include "math.h"


//=============================================================================
//	Flags
//=============================================================================

const int DEVINIT_NONE    = 0x0000;
const int DEVINIT_CUBLAS  = 0x0001;
const int DEVINIT_CURAND  = 0x0002;
const int DEVINIT_SETSEED = 0x0004;
const int DEVINIT_RESETDEVICE = 0x0008;

const int DEVPROP_DEVICECOUNT			= 1;
const int DEVPROP_NAME					= 2;
const int DEVPROP_MULTIGPUBOARDGROUPID	= 3;


//-----------------------------------------------------------------------------
//	Device Class
//
//	The device class implements manages underying GPU device.
//-----------------------------------------------------------------------------
template <class T>
class Device
{
	protected:
		Memory<T> m_memory;
		Math<T> m_math;
		cublasHandle_t m_cublas;
		curandGenerator_t m_curand;
		long m_lSeed;
		int m_nDevice;
		HANDLE m_hEventSrc;

		long verifyInput(long lInput, T* pfInput, long lMin, long lMax, bool bExact = false);
		long verifyOutput(long* plOutput, T** ppfOutput);
		long setOutput(long hHandle, long* plOutput, T** ppfOutput);
		long setOutput(T fVal, long* plOutput, T** ppfOutput);

	public:
		Device();
		~Device();

		long GetDeviceName(int nDevice, LPTSTR* pszDevice);
		long GetDeviceP2PInfo(int nDevice, LPTSTR* pszDevice);
		long GetDeviceInfo(int nDevice, LPTSTR* pszDevice, bool bVerbose);

		long SetDevice(int nDevice, int nFlags = DEVINIT_CUBLAS | DEVINIT_CURAND | DEVINIT_SETSEED, long lSeed = 0);
		int GetDevice();
		long ResetDevice();
		long SynchronizeDevice();

		long GetMemory(long hHandle, MemoryItem** ppItem)
		{
			return m_memory.GetMemory(hHandle, ppItem);
		}

		HostBuffer<T>* GetHostBuffer(long hHandle)
		{
			return m_memory.GetHostBuffer(hHandle);
		}

		cudaStream_t GetStream(long hStream)
		{
			return m_memory.GetStream(hStream);
		}

		long GetDeviceName(long lInput, LONG* pfInput, LPTSTR* ppfOutput);
		long GetDeviceP2PInfo(long lInput, LONG* pfInput, LPTSTR* ppfOutput);
		long GetDeviceInfo(long lInput, LONG* pfInput, LPTSTR* ppfOutput);

		long SetDevice(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long SetRandomSeed(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long GetDevice(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long ResetDevice(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long SynchronizeDevice(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long GetDeviceProperty(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long CheckMemoryAttributes(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long GetDeviceMemory(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long CanAccessPeer(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long EnablePeerAccess(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long DisablePeerAccess(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long AllocMemory(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long FreeMemory(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long GetMemory(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long SetMemory(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long SetMemoryAt(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		
		long AllocHostBuffer(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long FreeHostBuffer(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long GetHostMemory(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long SetHostMemory(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long FreeHost(T* pf)
		{
			if (!m_memory.IsHostBuffer(pf))
				return m_memory.FreeHost(pf);

			return 0;
		}

		long FreeHost(LPTSTR pf)
		{
			return m_memory.FreeHost(pf);
		}

		long AllocHost(long lCount, T** ppDst, T* pSrc, bool bSrcOnDevice = false)
		{
			return m_memory.AllocHost(lCount, ppDst, pSrc, bSrcOnDevice);
		}

		long CreateMemoryPointer(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long FreeMemoryPointer(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long CreateStream(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long FreeStream(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long SynchronizeStream(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long SynchronizeThread(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long CreateMemoryTest(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long FreeMemoryTest(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long RunMemoryTest(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		ncclHandle<T>* GetNccl(long hNccl);
		long SetNccl(ncclHandle<T>* pNccl, long* plOutput, T** ppfOutput);

		long CreateNCCL(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long FreeNCCL(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long NcclInitSingleProcess(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long NcclInitMultiProcess(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long NcclBroadcast(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long NcclAllReduce(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long CreateCuDNN(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long FreeCuDNN(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long CreateTensorDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long FreeTensorDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long SetTensorDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long AddTensor(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long CreateFilterDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long FreeFilterDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long SetFilterDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long CreateConvolutionDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long FreeConvolutionDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long SetConvolutionDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long GetConvolutionInfo(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long ConvolutionForward(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long ConvolutionBackwardBias(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long ConvolutionBackwardFilter(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long ConvolutionBackwardData(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long CreatePoolingDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long FreePoolingDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long SetPoolingDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long PoolingForward(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long PoolingBackward(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long CreateDropoutDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long FreeDropoutDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long SetDropoutDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long GetDropoutInfo(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long DropoutForward(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long DropoutBackward(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long CreateLRNDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long FreeLRNDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long SetLRNDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long TanhForward(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long TanhBackward(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long SigmoidForward(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long SigmoidBackward(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long ReLUForward(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long ReLUBackward(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long SoftmaxForward(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long SoftmaxBackward(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long LRNForwardCC(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long LRNBackwardCC(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long LCNForwardCC(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long LCNBackwardCC(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long CreatePCA(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long FreePCA(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long RunPCA(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long CreateTsneGaussianPerplexity(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long FreeTsneGaussianPerplexity(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long FindTsneGaussianPerplexity(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long CreateTsne(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long FreeTsne(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long ComputeTsneGradient(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long EvaluateTsneError(long lInput, T* pfInput, long* plOutput, T** ppfOutput);


		//---------------------------------------------------------------------------
		//	Math functions
		//---------------------------------------------------------------------------

		long cuda_set(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_get(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_copy(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_gemm(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_gemm2(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_gemv(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_axpy(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_axpby(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_scal(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_dot(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_asum(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_scale(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_add_scalar(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_add(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_add2(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_sub(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_mul_scalar(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_sub_and_dot(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_mul(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_div(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_abs(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_exp(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_log(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_powx(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_sign(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_sqrt(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_reciprocol(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_student(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_logistic1(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_logistic2(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_compare_signs(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_maxval(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_minval(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_minmaxval(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_sumsq(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_sumsqdiff(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_width(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_contains_point(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_denan(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_channel_max(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_channel_sub(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_channel_sum(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_channel_div(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_channel_mul(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_channel_dot(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_im2col(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_im2col_nd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_col2im(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_col2im_nd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_rng_setseed(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_rng_uniform(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_rng_gaussian(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_rng_bernoulli(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_batchreidx_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_batchreidx_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_embed_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_embed_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_pooling_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_pooling_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_unpooling_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_unpooling_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_tanh_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_tanh_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_sigmoid_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_sigmoid_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_relu_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_relu_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_elu_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_elu_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_dropout_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_dropout_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_bnll_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_bnll_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_prelu_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_prelu_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_prelu_bwd_param(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_softmaxloss_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_softmaxloss_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_max_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_max_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_crop_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_crop_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_concat_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_concat_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_slice_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_slice_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_tile_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_tile_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_bias_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_scale_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_threshold_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_cll_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_lrn_fillscale(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_lrn_computeoutput(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_lrn_computediff(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_lstm_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_lstm_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_lstm_unit_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_lstm_unit_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_coeff_sum_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_coeff_sum_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_sigmoid_cross_entropy_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_sigmoid_cross_entropy_ignore(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_sgd_update(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_nesterov_update(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_adagrad_update(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_adadelta_update(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_adam_update(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_rmsprop_update(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_combine_data(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_mtx_set_diagonal(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_mtx_set_diagonal2(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_mtx_add_vector(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_mtx_transpose_op(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_mtx_aggregate_cols(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_mtx_aggregate_rows(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_mtx_transpose(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_mtx_meancenter_by_column(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_mtx_euclidean_dist(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_mtx_dot(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_tsne_update(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_tsne_update_grad(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_tsne_compute_exact_error(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_tsne_compute_squared_euclidean_distance(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_tsne_compute_q_matrix(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_tsne_compute_exact_gradient(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_tsne_symmetrize_matrix(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_tsne_compute_knn_bounds(long lInput, T* pfInput, long* plOutput, T** ppfOutput);

		long cuda_guassian_blur(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_hamming_diff(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
		long cuda_calc_batch_dist(long lInput, T* pfInput, long* plOutput, T** ppfOutput);
};


//=============================================================================
//	Inline Methods
//=============================================================================

template <class T>
inline long Device<T>::verifyInput(long lInput, T* pfInput, long lMin, long lMax, bool bExact)
{
	if (lInput < lMin || lInput > lMax)
		return ERROR_PARAM_OUT_OF_RANGE;

	if (lMin == 0 && lMax == 0)
		return 0;

	if (bExact && lInput != lMin && lInput != lMax)
		return ERROR_PARAM_OUT_OF_RANGE;

	if (pfInput == NULL)
		return ERROR_PARAM_NULL;

	return 0;
}

template <class T>
inline long Device<T>::verifyOutput(long* plOutput, T** ppfOutput)
{
	if (plOutput == NULL)
		return ERROR_PARAM_NULL;

	if (ppfOutput == NULL)
		return ERROR_PARAM_NULL;

	return 0;
}

template <class T>
inline long Device<T>::setOutput(long hHandle, long* plOutput, T** ppfOutput)
{
	*plOutput = 1;
	(*ppfOutput)[0] = (T)hHandle;

	return 0;
}


template <class T>
inline long Device<T>::setOutput(T fVal, long* plOutput, T** ppfOutput)
{
	*plOutput = 1;
	(*ppfOutput)[0] = fVal;

	return 0;
}


//=============================================================================
//	Device Methods
//=============================================================================

template <class T>
inline Device<T>::Device() : m_memory(), m_math()
{
	m_math.Connect(&m_memory);
	m_cublas = NULL;
	m_curand = NULL;
	m_lSeed = 0;
	m_nDevice = 0;
	m_hEventSrc = RegisterEventSource(NULL, L"CUDA.NET");
}

template <class T>
inline Device<T>::~Device()
{
	if (m_curand != NULL)
	{
		curandDestroyGenerator(m_curand);
		m_curand = NULL;
	}

	if (m_hEventSrc != NULL)
	{
		DeregisterEventSource(m_hEventSrc);
		m_hEventSrc = NULL;
	}

	if (m_cublas != NULL)
	{
		cublasDestroy(m_cublas);
		m_cublas = NULL;
	}
}

template <class T>
inline int Device<T>::GetDevice()
{
	return m_nDevice;
}

template <class T>
inline long Device<T>::ResetDevice()
{
	return cudaDeviceReset();
}

template <class T>
inline long Device<T>::SynchronizeDevice()
{
	return cudaDeviceSynchronize();
}

template <class T>
inline long Device<T>::SetRandomSeed(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;
	
	if (lErr = verifyInput(lInput, pfInput, 1, 1))
		return lErr;

	long lSeed = (long)pfInput[0];

	return m_math.rng_setseed(lSeed);
}

template <class T>
inline long Device<T>::GetDevice(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	return setOutput((long)GetDevice(), plOutput, ppfOutput);
}

template <class T>
inline long Device<T>::ResetDevice(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	return ResetDevice();
}

template <class T>
inline long Device<T>::SynchronizeDevice(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	SynchronizeDevice();
	return 0;
}

template <class T>
inline long Device<T>::GetDeviceProperty(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	long lErr;

	if (lErr = verifyInput(lInput, pfInput, 2, 2))
		return lErr;

	if (lErr = verifyOutput(plOutput, ppfOutput))
		return lErr;

	int nDeviceID = (int)pfInput[0];
	int nPropID = (int)pfInput[1];
	T fVal = 0;

	if (nPropID == DEVPROP_DEVICECOUNT)
	{
		int nCount = 0;

		if (lErr = cudaGetDeviceCount(&nCount))
			return lErr;

		fVal = (T)nCount;
	}
	else
	{
		cudaDeviceProp p;

		if (lErr = cudaGetDeviceProperties(&p, nDeviceID))
			return lErr;

		switch (nPropID)
		{
			case DEVPROP_MULTIGPUBOARDGROUPID:
				fVal = (T)p.multiGpuBoardGroupID;
				break;

			default:
				return ERROR_PARAM_OUT_OF_RANGE;
		}
	}

	return setOutput(fVal, plOutput, ppfOutput);
}

template <class T>
inline long Device<T>::CheckMemoryAttributes(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	long lErr;

	if (lErr = verifyInput(lInput, pfInput, 4, 4))
		return lErr;

	if (lErr = verifyOutput(plOutput, ppfOutput))
		return lErr;

	long hSrc = (long)pfInput[0];
	int nSrcDeviceID = (int)pfInput[1];
	long hDst = (long)pfInput[2];
	int nDstDeviceID = (int)pfInput[3];
	bool bResult = false;

	if (lErr = m_memory.CheckMemoryAttributes(hSrc, nSrcDeviceID, hDst, nDstDeviceID, &bResult))
		return lErr;

	T fVal = (bResult) ? (T)1 : (T)0;

	return setOutput(fVal, plOutput, ppfOutput);
}

template <class T>
inline long Device<T>::GetDeviceMemory(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	long lErr;

	if (lErr = verifyInput(lInput, pfInput, 1, 1))
		return lErr;

	if (lErr = verifyOutput(plOutput, ppfOutput))
		return lErr;

	int nDeviceID = (int)pfInput[0];
	T fTotal = 0;
	T fFree = 0;
	T fUsed = 0;
	bool bEstimate = false;

	if (lErr = m_memory.GetDeviceMemory(nDeviceID, &fTotal, &fFree, &fUsed, &bEstimate))
		return lErr;

	T* pfOutput = NULL;

	if (lErr = m_memory.AllocHost(4, &pfOutput, NULL, false))
		return lErr;

	pfOutput[0] = fTotal;
	pfOutput[1] = fFree;
	pfOutput[2] = fUsed;
	pfOutput[3] = (bEstimate) ? 1.0f : 0.0f;

	*ppfOutput = pfOutput;
	*plOutput = 4;

	return 0;
}


template <class T>
inline long Device<T>::CreateMemoryPointer(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 3, 3))
		return lErr;

	long hData = (long)pfInput[0];
	long lOffset = (long)pfInput[1];
	long lCount = (long)pfInput[2];

	long hHandle = 0;
	
	if (lErr = m_memory.CreateMemoryPointer(hData, lOffset, lCount, &hHandle))
		return lErr;

	if (lErr = setOutput(hHandle, plOutput, ppfOutput))
		return lErr;

	return 0;
}

template <class T>
inline long Device<T>::FreeMemoryPointer(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 1, 1))
		return lErr;

	long hHandle = (long)pfInput[0];

	return m_memory.FreeMemoryPointer(hHandle);
}


//=============================================================================
//	Memory Test Methods
//=============================================================================

template <class T>
inline long Device<T>::CreateMemoryTest(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;
	long hHandle = 0;

	if (lErr = verifyInput(lInput, pfInput, 1, 1))
		return lErr;

	if (lErr = verifyOutput(plOutput, ppfOutput))
		return lErr;

	T fPctToAllocate = pfInput[0];

	size_t szTotalNumBlocks = 0;
	T fMemAllocated = 0;
	T fMemStartAddr = 0;
	T fMemBlockSize = 0;

	if (lErr = m_memory.CreateMemoryTest(fPctToAllocate, &hHandle, &szTotalNumBlocks, &fMemAllocated, &fMemStartAddr, &fMemBlockSize))
		return lErr;

	T* pfOutput = NULL;

	if (lErr = m_memory.AllocHost(5, &pfOutput, NULL, false))
		return lErr;

	pfOutput[0] = (T)hHandle;
	pfOutput[1] = (T)szTotalNumBlocks;
	pfOutput[2] = fMemAllocated;
	pfOutput[3] = fMemStartAddr;
	pfOutput[4] = fMemBlockSize;

	*ppfOutput = pfOutput;
	*plOutput = 5;

	return 0;
}

template <class T>
inline long Device<T>::FreeMemoryTest(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 1, 1))
		return lErr;

	long hHandle = (long)pfInput[0];

	return m_memory.FreeMemoryTest(hHandle);
}


//=============================================================================
//	Cuda Methods
//=============================================================================

template <class T>
inline long Device<T>::CreateStream(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;
	long hHandle = 0;
	bool bNonBlocking = false;

	if (lInput > 0 && pfInput != NULL)
		bNonBlocking = (pfInput[0] == 1.0) ? true : false;

	if (lErr = verifyOutput(plOutput, ppfOutput))
		return lErr;

	if (lErr = m_memory.CreateStream(&hHandle, bNonBlocking))
		return lErr;

	return setOutput(hHandle, plOutput, ppfOutput);
}

template <class T>
inline long Device<T>::FreeStream(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 1, 1))
		return lErr;

	long hHandle = (long)pfInput[0];

	return m_memory.FreeStream(hHandle);
}

template <class T>
inline long Device<T>::SynchronizeStream(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 1, 1))
		return lErr;

	long hHandle = (long)pfInput[0];

	return m_memory.SynchronizeStream(hHandle);
}

template <class T>
inline long Device<T>::SynchronizeThread(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	return m_memory.SynchronizeThread();
}


//=============================================================================
//	CuDnn Methods
//=============================================================================

template <class T>
inline long Device<T>::CreateCuDNN(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;
	long hHandle = 0;
	long hStream = 0;

	if (lErr = verifyInput(lInput, pfInput, 0, 1))
		return lErr;

	if (lErr = verifyOutput(plOutput, ppfOutput))
		return lErr;

	if (lInput > 0)
		hStream = (long)pfInput[0];

	if (lErr = m_memory.CreateCuDNN(hStream, &hHandle))
		return lErr;

	return setOutput(hHandle, plOutput, ppfOutput);
}

template <class T>
inline long Device<T>::FreeCuDNN(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 1, 1))
		return lErr;

	long hHandle = (long)pfInput[0];

	return m_memory.FreeCuDNN(hHandle);
}

template <class T>
inline long Device<T>::CreateTensorDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;
	long hHandle = 0;

	if (lErr = verifyOutput(plOutput, ppfOutput))
		return lErr;

	if (lErr = m_memory.CreateTensorDesc(&hHandle))
		return lErr;

	return setOutput(hHandle, plOutput, ppfOutput);
}

template <class T>
inline long Device<T>::FreeTensorDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 1, 1))
		return lErr;

	long hHandle = (long)pfInput[0];

	return m_memory.FreeTensorDesc(hHandle);
}


template <class T>
inline long Device<T>::AddTensor(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 9, 9))
		return lErr;

	long hHandle = (long)pfInput[0];
	T fAlpha = pfInput[1];
	long hSrcDesc = (long)pfInput[2];
	long hSrc = (long)pfInput[3];
	int nSrcOffset = (int)pfInput[4];
	T fBeta = pfInput[5];
	long hDstDesc = (long)pfInput[6];
	long hDst = (long)pfInput[7];
	int nDstOffset = (int)pfInput[8];

	return m_memory.AddTensor(hHandle, fAlpha, hSrcDesc, hSrc, nSrcOffset, fBeta, hDstDesc, hDst, nDstOffset);
}


template <class T>
inline long Device<T>::CreateFilterDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;
	long hHandle = 0;

	if (lErr = verifyOutput(plOutput, ppfOutput))
		return lErr;

	if (lErr = m_memory.CreateFilterDesc(&hHandle))
		return lErr;

	return setOutput(hHandle, plOutput, ppfOutput);
}

template <class T>
inline long Device<T>::FreeFilterDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 1, 1))
		return lErr;

	long hHandle = (long)pfInput[0];

	return m_memory.FreeFilterDesc(hHandle);
}

template <class T>
inline long Device<T>::SetFilterDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 5, 5))
		return lErr;

	long hHandle = (long)pfInput[0];
	int n = (int)pfInput[1];
	int c = (int)pfInput[2];
	int h = (int)pfInput[3];
	int w = (int)pfInput[4];

	return m_memory.SetFilterDesc(hHandle, n, c, h, w);
}

template <class T>
inline long Device<T>::CreateConvolutionDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;
	long hHandle = 0;

	if (lErr = verifyOutput(plOutput, ppfOutput))
		return lErr;

	if (lErr = m_memory.CreateConvolutionDesc(&hHandle))
		return lErr;

	return setOutput(hHandle, plOutput, ppfOutput);
}

template <class T>
inline long Device<T>::FreeConvolutionDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 1, 1))
		return lErr;

	long hHandle = (long)pfInput[0];

	return m_memory.FreeConvolutionDesc(hHandle);
}

template <class T>
inline long Device<T>::SetConvolutionDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 5, 5))
		return lErr;

	long hHandle = (long)pfInput[0];
	int hPad = (int)pfInput[1];
	int wPad = (int)pfInput[2];
	int hStride = (int)pfInput[3];
	int wStride = (int)pfInput[4];

	return m_memory.SetConvolutionDesc(hHandle, hPad, wPad, hStride, wStride);
}

template <class T>
inline long Device<T>::GetConvolutionInfo(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 6, 6))
		return lErr;

	if (lErr = verifyOutput(plOutput, ppfOutput))
		return lErr;

	long hHandle = (long)pfInput[0];
	long hBottomDesc = (long)pfInput[1];
	long hFilter = (long)pfInput[2];
	long hConvDesc = (long)pfInput[3];
	long hTopDesc = (long)pfInput[4];
	long lWsLimitInBytes = (long)pfInput[5];
	long algoFwd = 0;
	long lWsSizeFwd = 0;
	long algoBwdFilter = 0;
	long lWsSizeBwdFilter = 0;
	long algoBwdData = 0;
	long lWsSizeBwdData = 0;

	if (lErr = m_memory.GetConvolutionInfo(hHandle, hBottomDesc, hFilter, hConvDesc, hTopDesc, lWsLimitInBytes, &algoFwd, &lWsSizeFwd, &algoBwdFilter, &lWsSizeBwdFilter, &algoBwdData, &lWsSizeBwdData))
		return lErr;

	T* pOutput = NULL;
	if (lErr = m_memory.AllocHost(6, &pOutput, NULL, false))
		return lErr;

	pOutput[0] = (T)algoFwd;
	pOutput[1] = (T)lWsSizeFwd;
	pOutput[2] = (T)algoBwdFilter;
	pOutput[3] = (T)lWsSizeBwdFilter;
	pOutput[4] = (T)algoBwdData;
	pOutput[5] = (T)lWsSizeBwdData;

	*plOutput = 6;
	*ppfOutput = pOutput;

	return 0;
}

template <class T>
inline long Device<T>::ConvolutionForward(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 17, 17))
		return lErr;

	long hHandle = (long)pfInput[0];
	T fAlpha = pfInput[1];
	long hBottomDesc = (long)pfInput[2];
	long hBottomData = (long)pfInput[3];
	int nBottomOffset = (int)pfInput[4];
	long hFilterDesc = (long)pfInput[5];
	long hWeight = (long)pfInput[6];
	int nWeightOffset = (int)pfInput[7];
	long hConvDesc = (long)pfInput[8];
	long algo = (long)pfInput[9];
	long hWorkspace = (long)pfInput[10];
	int nWorkspaceOffset = (int)pfInput[11];
	long lWorkspaceSize = (long)pfInput[12];
	T fBeta = pfInput[13];
	long hTopDesc = (long)pfInput[14];
	long hTopData = (long)pfInput[15];
	int nTopOffset = (int)pfInput[16];

	return m_memory.ConvolutionForward(hHandle, fAlpha, hBottomDesc, hBottomData, nBottomOffset, hFilterDesc, hWeight, nWeightOffset, hConvDesc, algo, hWorkspace, nWorkspaceOffset, lWorkspaceSize, fBeta, hTopDesc, hTopData, nTopOffset);
}

template <class T>
inline long Device<T>::ConvolutionBackwardBias(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 9, 9))
		return lErr;

	long hHandle = (long)pfInput[0];
	T fAlpha = pfInput[1];
	long hTopDesc = (long)pfInput[2];
	long hTopDiff = (long)pfInput[3];
	int nTopOffset = (int)pfInput[4];
	T fBeta = pfInput[5];
	long hBiasDesc = (long)pfInput[6];
	long hBiasDiff = (long)pfInput[7];
	int nBiasOffset = (int)pfInput[8];

	return m_memory.ConvolutionBackwardBias(hHandle, fAlpha, hTopDesc, hTopDiff, nTopOffset, fBeta, hBiasDesc, hBiasDiff, nBiasOffset);
}

template <class T>
inline long Device<T>::ConvolutionBackwardFilter(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 17, 17))
		return lErr;

	long hHandle = (long)pfInput[0];
	T fAlpha = pfInput[1];
	long hBottomDesc = (long)pfInput[2];
	long hBottomData = (long)pfInput[3];
	int nBottomOffset = (int)pfInput[4];
	long hTopDesc = (long)pfInput[5];
	long hTopDiff = (long)pfInput[6];
	int nTopOffset = (int)pfInput[7];
	long hConvDesc = (long)pfInput[8];
	long algo = (long)pfInput[9];
	long hWorkspace = (long)pfInput[10];
	int nWorkspaceOffset = (int)pfInput[11];
	long lWorkspaceSize = (long)pfInput[12];
	T fBeta = pfInput[13];
	long hFilterDesc = (long)pfInput[14];
	long hWeightDiff = (long)pfInput[15];
	int nWeightOffset = (int)pfInput[16];

	return m_memory.ConvolutionBackwardFilter(hHandle, fAlpha, hBottomDesc, hBottomData, nBottomOffset, hTopDesc, hTopDiff, nTopOffset, hConvDesc, algo, hWorkspace, nWorkspaceOffset, lWorkspaceSize, fBeta, hFilterDesc, hWeightDiff, nWeightOffset);
}

template <class T>
inline long Device<T>::ConvolutionBackwardData(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 17, 17))
		return lErr;

	long hHandle = (long)pfInput[0];
	T fAlpha = pfInput[1];
	long hFilterDesc = (long)pfInput[2];
	long hWeight = (long)pfInput[3];
	int nWeightOffset = (int)pfInput[4];
	long hTopDesc = (long)pfInput[5];
	long hTopDiff = (long)pfInput[6];
	int nTopOffset = (int)pfInput[7];
	long hConvDesc = (long)pfInput[8];
	long algo = (long)pfInput[9];
	long hWorkspace = (long)pfInput[10];
	int nWorkspaceOffset = (int)pfInput[11];
	long lWorkspaceSize = (long)pfInput[12];
	T fBeta = pfInput[13];
	long hBottomDesc = (long)pfInput[14];
	long hBottomDiff = (long)pfInput[15];
	int nBottomOffset = (int)pfInput[16];

	return m_memory.ConvolutionBackwardData(hHandle, fAlpha, hFilterDesc, hWeight, nWeightOffset, hTopDesc, hTopDiff, nTopOffset, hConvDesc, algo, hWorkspace, nWorkspaceOffset, lWorkspaceSize, fBeta, hBottomDesc, hBottomDiff, nBottomOffset );
}


template <class T>
inline long Device<T>::CreatePoolingDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;
	long hHandle = 0;

	if (lErr = verifyOutput(plOutput, ppfOutput))
		return lErr;

	if (lErr = m_memory.CreatePoolingDesc(&hHandle))
		return lErr;

	return setOutput(hHandle, plOutput, ppfOutput);
}

template <class T>
inline long Device<T>::FreePoolingDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 1, 1))
		return lErr;

	long hHandle = (long)pfInput[0];

	return m_memory.FreePoolingDesc(hHandle);
}

template <class T>
inline long Device<T>::SetPoolingDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 8, 8))
		return lErr;

	long hHandle = (long)pfInput[0];
	PoolingMethod nMethod = (PoolingMethod)(int)pfInput[1];
	int h = (int)pfInput[2];
	int w = (int)pfInput[3];
	int hPad = (int)pfInput[4];
	int wPad = (int)pfInput[5];
	int hStride = (int)pfInput[6];
	int wStride = (int)pfInput[7];

	return m_memory.SetPoolingDesc(hHandle, nMethod, h, w, hPad, wPad, hStride, wStride);
}

template <class T>
inline long Device<T>::PoolingForward(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 8, 8))
		return lErr;

	long hHandle = (long)pfInput[0];
	long hPoolingDesc = (long)pfInput[1];
	T fAlpha = pfInput[2];
	long hBottomDesc = (long)pfInput[3];
	long hBottomData = (long)pfInput[4];
	T fBeta = pfInput[5];
	long hTopDesc = (long)pfInput[6];
	long hTopData = (long)pfInput[7];

	return m_memory.PoolingForward(hHandle, hPoolingDesc, fAlpha, hBottomDesc, hBottomData, fBeta, hTopDesc, hTopData);
}

template <class T>
inline long Device<T>::PoolingBackward(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 12, 12))
		return lErr;

	long hHandle = (long)pfInput[0];
	long hPoolingDesc = (long)pfInput[1];
	T fAlpha = pfInput[2];
	long hTopDataDesc = (long)pfInput[3];
	long hTopData = (long)pfInput[4];
	long hTopDiffDesc = (long)pfInput[5];
	long hTopDiff = (long)pfInput[6];
	long hBottomDataDesc = (long)pfInput[7];
	long hBottomData = (long)pfInput[8];
	T fBeta = pfInput[9];
	long hBottomDiffDesc = (long)pfInput[10];
	long hBottomDiff = (long)pfInput[11];

	return m_memory.PoolingBackward(hHandle, hPoolingDesc, fAlpha, hTopDataDesc, hTopData, hTopDiffDesc, hTopDiff, hBottomDataDesc, hBottomData, fBeta, hBottomDiffDesc, hBottomDiff);
}


template <class T>
inline long Device<T>::cuda_batchreidx_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 5, 5))
		return lErr;

	int nCount = (int)pfInput[0];
	int nInnerDim = (int)pfInput[1];
	long hBottomData = (long)pfInput[2];
	long hPermutData = (long)pfInput[3];
	long hTopData = (long)pfInput[4];

	return m_math.batchreidx_fwd(nCount, nInnerDim, hBottomData, hPermutData, hTopData);
}


template <class T>
inline long Device<T>::cuda_batchreidx_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 7, 7))
		return lErr;

	int nCount = (int)pfInput[0];
	int nInnerDim = (int)pfInput[1];
	long hTopDiff = (long)pfInput[2];
	long hTopIdx = (long)pfInput[3];
	long hBegins = (long)pfInput[4];
	long hCounts = (long)pfInput[5];
	long hBottomDiff = (long)pfInput[6];

	return m_math.batchreidx_bwd(nCount, nInnerDim, hTopDiff, hTopIdx, hBegins, hCounts, hBottomDiff);
}


template <class T>
inline long Device<T>::cuda_embed_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 7, 7))
		return lErr;

	int nCount = (int)pfInput[0];
	long hBottomData = (long)pfInput[1];
	long hWeight = (int)pfInput[2];
	int nM = (int)pfInput[3];
	int nN = (int)pfInput[4];
	int nK = (int)pfInput[5];
	long hTopData = (long)pfInput[6];

	return m_math.embed_fwd(nCount, hBottomData, hWeight, nM, nN, nK, hTopData);
}


template <class T>
inline long Device<T>::cuda_embed_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 7, 7))
		return lErr;

	int nCount = (int)pfInput[0];
	long hBottomData = (long)pfInput[1];
	long hTopDiff = (int)pfInput[2];
	int nM = (int)pfInput[3];
	int nN = (int)pfInput[4];
	int nK = (int)pfInput[5];
	long hWeightDiff = (long)pfInput[6];

	return m_math.embed_bwd(nCount, hBottomData, hTopDiff, nM, nN, nK, hWeightDiff);
}


template <class T>
inline long Device<T>::cuda_pooling_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 18, 18))
		return lErr;

	int nMethod = (int)pfInput[0];
	int nCount = (int)pfInput[1];
	long hBottomData = (long)pfInput[2];
	int nNum = (int)pfInput[3];
	int nChannels = (int)pfInput[4];
	int h = (int)pfInput[5];
	int w = (int)pfInput[6];
	int hPooled = (int)pfInput[7];
	int wPooled = (int)pfInput[8];
	int hKernel = (int)pfInput[9];
	int wKernel = (int)pfInput[10];
	int hStride = (int)pfInput[11];
	int wStride = (int)pfInput[12];
	int hPad = (int)pfInput[13];
	int wPad = (int)pfInput[14];
	long hTopData = (long)pfInput[15];
	long hMask = (long)pfInput[16];
	long hTopMask = (long)pfInput[17];

	return m_math.pooling_fwd(nMethod, nCount, hBottomData, nNum, nChannels, h, w, hPooled, wPooled, hKernel, wKernel, hStride, wStride, hPad, wPad, hTopData, hMask, hTopMask);
}

template <class T>
inline long Device<T>::cuda_pooling_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 18, 18))
		return lErr;

	int nMethod = (int)pfInput[0];
	int nCount = (int)pfInput[1];
	long hTopDiff = (long)pfInput[2];
	int nNum = (int)pfInput[3];
	int nChannels = (int)pfInput[4];
	int h = (int)pfInput[5];
	int w = (int)pfInput[6];
	int hPooled = (int)pfInput[7];
	int wPooled = (int)pfInput[8];
	int hKernel = (int)pfInput[9];
	int wKernel = (int)pfInput[10];
	int hStride = (int)pfInput[11];
	int wStride = (int)pfInput[12];
	int hPad = (int)pfInput[13];
	int wPad = (int)pfInput[14];
	long hBottomDiff = (long)pfInput[15];
	long hMask = (long)pfInput[16];
	long hTopMask = (long)pfInput[17];

	return m_math.pooling_bwd(nMethod, nCount, hTopDiff, nNum, nChannels, h, w, hPooled, wPooled, hKernel, wKernel, hStride, wStride, hPad, wPad, hBottomDiff, hMask, hTopMask);
}


template <class T>
inline long Device<T>::cuda_unpooling_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 17, 17))
		return lErr;

	int nMethod = (int)pfInput[0];
	int nCount = (int)pfInput[1];
	long hBottomData = (long)pfInput[2];
	int nNum = (int)pfInput[3];
	int nChannels = (int)pfInput[4];
	int h = (int)pfInput[5];
	int w = (int)pfInput[6];
	int hUnPooled = (int)pfInput[7];
	int wUnPooled = (int)pfInput[8];
	int hKernel = (int)pfInput[9];
	int wKernel = (int)pfInput[10];
	int hStride = (int)pfInput[11];
	int wStride = (int)pfInput[12];
	int hPad = (int)pfInput[13];
	int wPad = (int)pfInput[14];
	long hTopData = (long)pfInput[15];
	long hBottomMask = (long)pfInput[16];

	return m_math.unpooling_fwd(nMethod, nCount, hBottomData, nNum, nChannels, h, w, hUnPooled, wUnPooled, hKernel, wKernel, hStride, wStride, hPad, wPad, hTopData, hBottomMask);
}

template <class T>
inline long Device<T>::cuda_unpooling_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 17, 17))
		return lErr;

	int nMethod = (int)pfInput[0];
	int nCount = (int)pfInput[1];
	long hTopDiff = (long)pfInput[2];
	int nNum = (int)pfInput[3];
	int nChannels = (int)pfInput[4];
	int h = (int)pfInput[5];
	int w = (int)pfInput[6];
	int hUnPooled = (int)pfInput[7];
	int wUnPooled = (int)pfInput[8];
	int hKernel = (int)pfInput[9];
	int wKernel = (int)pfInput[10];
	int hStride = (int)pfInput[11];
	int wStride = (int)pfInput[12];
	int hPad = (int)pfInput[13];
	int wPad = (int)pfInput[14];
	long hBottomDiff = (long)pfInput[15];
	long hBottomMask = (long)pfInput[16];

	return m_math.unpooling_bwd(nMethod, nCount, hTopDiff, nNum, nChannels, h, w, hUnPooled, wUnPooled, hKernel, wKernel, hStride, wStride, hPad, wPad, hBottomDiff, hBottomMask);
}


template <class T>
inline long Device<T>::CreateDropoutDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;
	long hHandle = 0;

	if (lErr = verifyOutput(plOutput, ppfOutput))
		return lErr;

	if (lErr = m_memory.CreateDropoutDesc(&hHandle))
		return lErr;

	return setOutput(hHandle, plOutput, ppfOutput);
}


template <class T>
inline long Device<T>::FreeDropoutDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 1, 1))
		return lErr;

	long hHandle = (long)pfInput[0];

	return m_memory.FreeDropoutDesc(hHandle);
}

template <class T>
inline long Device<T>::SetDropoutDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 5, 5))
		return lErr;

	long hHandle = (long)pfInput[0];
	long hDropoutDesc = (long)pfInput[1];
	T fDropout = pfInput[2];
	long hStates = (long)pfInput[3];
	long lSeed = (long)pfInput[4];

	return m_memory.SetDropoutDesc(hHandle, hDropoutDesc, fDropout, hStates, lSeed);
}

template <class T>
inline long Device<T>::DropoutForward(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 7, 7))
		return lErr;

	long hHandle = (long)pfInput[0];
	long hDropoutDesc = (long)pfInput[1];
	long hBottomDesc = (long)pfInput[2];
	long hBottom = (long)pfInput[3];
	long hTopDesc = (long)pfInput[4];
	long hTop = (long)pfInput[5];
	long hReserved = (long)pfInput[6];

	return m_memory.DropoutForward(hHandle, hDropoutDesc, hBottomDesc, hBottom, hTopDesc, hTop, hReserved);
}

template <class T>
inline long Device<T>::DropoutBackward(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 7, 7))
		return lErr;

	long hHandle = (long)pfInput[0];
	long hDropoutDesc = (long)pfInput[1];
	long hTopDesc = (long)pfInput[2];
	long hTop = (long)pfInput[3];
	long hBottomDesc = (long)pfInput[4];
	long hBottom = (long)pfInput[5];
	long hReserved = (long)pfInput[6];

	return m_memory.DropoutBackward(hHandle, hDropoutDesc, hTopDesc, hTop, hBottomDesc, hBottom, hReserved);
}


template <class T>
inline long Device<T>::CreateLRNDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;
	long hHandle = 0;

	if (lErr = verifyOutput(plOutput, ppfOutput))
		return lErr;

	if (lErr = m_memory.CreateLRNDesc(&hHandle))
		return lErr;

	return setOutput(hHandle, plOutput, ppfOutput);
}

template <class T>
inline long Device<T>::FreeLRNDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 1, 1))
		return lErr;

	long hHandle = (long)pfInput[0];

	return m_memory.FreeLRNDesc(hHandle);
}

template <class T>
inline long Device<T>::SetLRNDesc(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 5, 5))
		return lErr;

	long hHandle = (long)pfInput[0];
	unsigned int nSize = (unsigned int)pfInput[1];
	T fAlpha = pfInput[2];
	T fBeta = pfInput[3];
	T fK = pfInput[4];

	return m_memory.SetLRNDesc(hHandle, nSize, fAlpha, fBeta, fK);
}


template <class T>
inline long Device<T>::TanhForward(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 7, 7))
		return lErr;

	long hHandle = (long)pfInput[0];
	T fAlpha = pfInput[1];
	long hBottomDesc = (long)pfInput[2];
	long hBottomData = (long)pfInput[3];
	T fBeta = pfInput[4];
	long hTopDesc = (long)pfInput[5];
	long hTopData = (long)pfInput[6];

	return m_memory.TanhForward(hHandle, fAlpha, hBottomDesc, hBottomData, fBeta, hTopDesc, hTopData);
}

template <class T>
inline long Device<T>::TanhBackward(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 11, 11))
		return lErr;

	long hHandle = (long)pfInput[0];
	T fAlpha = pfInput[1];
	long hTopDataDesc = (long)pfInput[2];
	long hTopData = (long)pfInput[3];
	long hTopDiffDesc = (long)pfInput[4];
	long hTopDiff = (long)pfInput[5];
	long hBottomDataDesc = (long)pfInput[6];
	long hBottomData = (long)pfInput[7];
	T fBeta = pfInput[8];
	long hBottomDiffDesc = (long)pfInput[9];
	long hBottomDiff = (long)pfInput[10];

	return m_memory.TanhBackward(hHandle, fAlpha, hTopDataDesc, hTopData, hTopDiffDesc, hTopDiff, hBottomDataDesc, hBottomData, fBeta, hBottomDiffDesc, hBottomDiff);
}

template <class T>
inline long Device<T>::cuda_tanh_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 3, 3))
		return lErr;

	int nCount = (int)pfInput[0];
	long hBottomData = (long)pfInput[1];
	long hTopData = (long)pfInput[2];

	return m_math.tanh_fwd(nCount, hBottomData, hTopData);
}

template <class T>
inline long Device<T>::cuda_tanh_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 4, 4))
		return lErr;

	int nCount = (int)pfInput[0];
	long hTopDiff = (long)pfInput[1];
	long hTopData = (long)pfInput[2];
	long hBottomDiff = (long)pfInput[3];

	return m_math.tanh_bwd(nCount, hTopDiff, hTopData, hBottomDiff);
}


template <class T>
inline long Device<T>::SigmoidForward(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 7, 7))
		return lErr;

	long hHandle = (long)pfInput[0];
	T fAlpha = pfInput[1];
	long hBottomDesc = (long)pfInput[2];
	long hBottomData = (long)pfInput[3];
	T fBeta = pfInput[4];
	long hTopDesc = (long)pfInput[5];
	long hTopData = (long)pfInput[6];

	return m_memory.SigmoidForward(hHandle, fAlpha, hBottomDesc, hBottomData, fBeta, hTopDesc, hTopData);
}

template <class T>
inline long Device<T>::SigmoidBackward(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 11, 11))
		return lErr;

	long hHandle = (long)pfInput[0];
	T fAlpha = pfInput[1];
	long hTopDataDesc = (long)pfInput[2];
	long hTopData = (long)pfInput[3];
	long hTopDiffDesc = (long)pfInput[4];
	long hTopDiff = (long)pfInput[5];
	long hBottomDataDesc = (long)pfInput[6];
	long hBottomData = (long)pfInput[7];
	T fBeta = pfInput[8];
	long hBottomDiffDesc = (long)pfInput[9];
	long hBottomDiff = (long)pfInput[10];

	return m_memory.SigmoidBackward(hHandle, fAlpha, hTopDataDesc, hTopData, hTopDiffDesc, hTopDiff, hBottomDataDesc, hBottomData, fBeta, hBottomDiffDesc, hBottomDiff);
}

template <class T>
inline long Device<T>::CreatePCA(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;
	long hHandle = 0;

	if (lErr = verifyInput(lInput, pfInput, 7, 9))
		return lErr;

	if (lErr = verifyOutput(plOutput, ppfOutput))
		return lErr;

	int nMaxIterations = (int)pfInput[0];
	int nM = (int)pfInput[1];
	int nN = (int)pfInput[2];
	int nK = (int)pfInput[3];
	long hData = (long)pfInput[4];
	long hScoresResult = (long)pfInput[5];
	long hLoadsResult = (long)pfInput[6];
	long hResiduals = 0;
	long hEigenvalues = 0;

	if (lInput > 7)
		hResiduals = (long)pfInput[7];

	if (lInput > 8)
		hEigenvalues = (long)pfInput[8];

	if (lErr = m_memory.CreatePCA(nMaxIterations, nM, nN, nK, hData, hScoresResult, hLoadsResult, hResiduals, hEigenvalues, &m_math, &hHandle))
		return lErr;

	return setOutput(hHandle, plOutput, ppfOutput);
}

template <class T>
inline long Device<T>::FreePCA(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 1, 1))
		return lErr;

	long hHandle = (long)pfInput[0];

	return m_memory.FreePCA(hHandle);
}

template <class T>
inline long Device<T>::RunPCA(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 1, 2))
		return lErr;

	if (lErr = verifyOutput(plOutput, ppfOutput))
		return lErr;

	long hHandle = (long)pfInput[0];
	int nSteps = 1;
	bool bDone = FALSE;
	int nCurrentIteration = 0;
	int nCurrentK = 0;

	if (lInput > 1)
		nSteps = (int)pfInput[1];

	if (lErr = m_memory.RunPCA(hHandle, nSteps, &bDone, &nCurrentIteration, &nCurrentK))
		return lErr;

	T* pfOutput = NULL;
	
	if (lErr = m_memory.AllocHost(3, &pfOutput, NULL, false))
		return lErr;

	pfOutput[0] = (bDone) ? T(0) : T(1);
	pfOutput[1] = T(nCurrentIteration);
	pfOutput[2] = T(nCurrentK);

	*plOutput = 3;
	*ppfOutput = pfOutput;

	return 0;
}


template <class T>
inline long Device<T>::CreateTsneGaussianPerplexity(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;
	long hHandle = 0;

	if (lErr = verifyInput(lInput, pfInput, 9, 9))
		return lErr;

	if (lErr = verifyOutput(plOutput, ppfOutput))
		return lErr;

	unsigned int nN = (unsigned int)pfInput[0];
	unsigned int nD = (unsigned int)pfInput[1];
	unsigned int nK = (unsigned int)pfInput[2];
	long hX = (long)pfInput[3];			// on gpu
	long hCurP = (long)pfInput[4];		// on gpu
	long hValP = (long)pfInput[5];		// on gpu
	long hRowP = (long)pfInput[6];		// on host
	long hColP = (long)pfInput[7];		// on host
	T fPerplexity = pfInput[8];

	if (lErr = m_memory.CreateTsneGaussianPerplexity(nN, nD, nK, hX, hCurP, hValP, hRowP, hColP, fPerplexity, &m_math, &hHandle))
		return lErr;

	return setOutput(hHandle, plOutput, ppfOutput);
}

template <class T>
inline long Device<T>::FreeTsneGaussianPerplexity(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 1, 1))
		return lErr;

	long hHandle = (long)pfInput[0];

	return m_memory.FreeTsneGaussianPerplexity(hHandle);
}

template <class T>
inline long Device<T>::FindTsneGaussianPerplexity(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 1, 1))
		return lErr;

	if (lErr = verifyOutput(plOutput, ppfOutput))
		return lErr;

	long hHandle = (long)pfInput[0];
	bool bDone = FALSE;
	int nCurrentIteration = 0;
	int nMaxIteration = 0;

	if (lErr = m_memory.FindTsneGaussianPerplexity(hHandle, &bDone, &nCurrentIteration, &nMaxIteration))
		return lErr;

	T* pfOutput = NULL;
	
	if (lErr = m_memory.AllocHost(3, &pfOutput, NULL, false))
		return lErr;

	pfOutput[0] = (bDone) ? T(0) : T(1);
	pfOutput[1] = T(nCurrentIteration);
	pfOutput[2] = T(nMaxIteration);

	*plOutput = 3;
	*ppfOutput = pfOutput;

	return 0;
}


template <class T>
inline long Device<T>::CreateTsne(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;
	long hHandle = 0;

	if (lErr = verifyInput(lInput, pfInput, 8, 8))
		return lErr;

	if (lErr = verifyOutput(plOutput, ppfOutput))
		return lErr;

	unsigned int nN = (unsigned int)pfInput[0];
	unsigned int nD = (unsigned int)pfInput[1];
	long hY = (long)pfInput[2];
	long hValP = (long)pfInput[3];
	long hRowP = (long)pfInput[4];
	long hColP = (long)pfInput[5];
	long hdC = (long)pfInput[6];
	T fTheta = pfInput[7];

	if (lErr = m_memory.CreateTsne(nN, nD, hY, hValP, hRowP, hColP, hdC, fTheta, &m_math, &hHandle))
		return lErr;

	return setOutput(hHandle, plOutput, ppfOutput);
}

template <class T>
inline long Device<T>::FreeTsne(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 1, 1))
		return lErr;

	long hHandle = (long)pfInput[0];

	return m_memory.FreeTsne(hHandle);
}


template <class T>
inline long Device<T>::ComputeTsneGradient(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 2, 2))
		return lErr;

	long hHandle = (long)pfInput[0];
	bool bValPUpdated = (pfInput[1] == 1) ? true : false;

	return m_memory.ComputeTsneGradient(hHandle, bValPUpdated);
}


template <class T>
inline long Device<T>::EvaluateTsneError(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 1, 1))
		return lErr;

	if (lErr = verifyOutput(plOutput, ppfOutput))
		return lErr;

	long hHandle = (long)pfInput[0];
	T fErr;

	if (lErr = m_memory.EvaluateTsneError(hHandle, &fErr))
		return lErr;

	return setOutput(fErr, plOutput, ppfOutput);
}


template <class T>
inline ncclHandle<T>* Device<T>::GetNccl(long hNccl)
{
	return m_memory.GetNCCL(hNccl);
}

template <class T>
inline long Device<T>::SetNccl(ncclHandle<T>* pNccl, long* plOutput, T** ppfOutput)
{
	LONG lErr;
	long hHandle = 0;

	if (lErr = verifyOutput(plOutput, ppfOutput))
		return lErr;

	pNccl->Update(&m_memory, &m_math);

	if (lErr = m_memory.SetNCCL(pNccl, &hHandle))
		return lErr;

	return setOutput(hHandle, plOutput, ppfOutput);
}


template <class T>
inline long Device<T>::CreateNCCL(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;
	long hHandle = 0;

	if (lErr = verifyInput(lInput, pfInput, 9, 9))
		return lErr;

	if (lErr = verifyOutput(plOutput, ppfOutput))
		return lErr;

	int nGpuId = (int)pfInput[0];
	int nCount = (int)pfInput[1];
	int nRank = (int)pfInput[2];
	int nGuidCount = (int)pfInput[3];

	if (nGuidCount != 5)
		return ERROR_PARAM_OUT_OF_RANGE;

	unsigned long g1 = (unsigned long)pfInput[4];
	unsigned long g2 = (unsigned long)pfInput[5];
	unsigned long g3 = (unsigned long)pfInput[6];
	unsigned long g4 = (unsigned long)pfInput[7];
	unsigned long g5 = (unsigned long)pfInput[8];

	char szGuid[128];
	snprintf(szGuid, 128, "nccl-%08x-%04x-%04x-%04x-%012x", g1, g2, g3, g4, g5);

	if (lErr = m_memory.CreateNCCL(nGpuId, nCount, nRank, szGuid, &m_math, &hHandle))
		return lErr;

	return setOutput(hHandle, plOutput, ppfOutput);
}

template <class T>
inline long Device<T>::FreeNCCL(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 1, 1))
		return lErr;

	long hNccl = (long)pfInput[0];

	return m_memory.FreeNCCL(hNccl);
}

template <class T>
inline long Device<T>::NcclInitSingleProcess(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 4, INT_MAX))
		return lErr;

	long lBufferCount = (long)pfInput[0];
	int nCount = (int)pfInput[1];
	if (nCount != lInput - 2)
		return ERROR_PARAM_OUT_OF_RANGE;

	long* rgHandles = new long[nCount];
	if (rgHandles == NULL)
		return ERROR_MEMORY_OUT;

	for (int i = 0; i < nCount; i++)
	{
		rgHandles[i] = (long)pfInput[i + 2];
	}

	lErr = m_memory.NcclInitSingleProcess(lBufferCount, rgHandles, nCount);
	delete rgHandles;

	return lErr;
}

template <class T>
inline long Device<T>::NcclInitMultiProcess(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 2, 2))
		return lErr;

	long lBufferCount = (long)pfInput[0];
	long hNccl = (long)pfInput[1];

	return m_memory.NcclInitMultiProcess(lBufferCount, hNccl);
}

template <class T>
inline long Device<T>::NcclBroadcast(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 4, 4))
		return lErr;

	long hNccl = (long)pfInput[0];
	long hStream = (long)pfInput[1];
	long hX = (long)pfInput[2];
	int nCount = (int)pfInput[3];

	return m_memory.NcclBroadcast(hNccl, hStream, hX, nCount);
}

template <class T>
inline long Device<T>::NcclAllReduce(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 6, 6))
		return lErr;

	long hNccl = (long)pfInput[0];
	long hStream = (long)pfInput[1];
	long hX = (long)pfInput[2];
	int nCount = (int)pfInput[3];
	NCCL_OP op = (NCCL_OP)(int)pfInput[4];
	T fScale = pfInput[5];

	return m_memory.NcclAllReduce(hNccl, hStream, hX, nCount, op, fScale);
}


template <class T>
inline long Device<T>::cuda_sigmoid_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 3, 3))
		return lErr;

	int nCount = (int)pfInput[0];
	long hBottomData = (long)pfInput[1];
	long hTopData = (long)pfInput[2];

	return m_math.sigmoid_fwd(nCount, hBottomData, hTopData);
}

template <class T>
inline long Device<T>::cuda_sigmoid_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 4, 4))
		return lErr;

	int nCount = (int)pfInput[0];
	long hTopDiff = (long)pfInput[1];
	long hTopData = (long)pfInput[2];
	long hBottomDiff = (long)pfInput[3];

	return m_math.sigmoid_bwd(nCount, hTopDiff, hTopData, hBottomDiff);
}


template <class T>
inline long Device<T>::ReLUForward(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 7, 7))
		return lErr;

	long hHandle = (long)pfInput[0];
	T fAlpha = pfInput[1];
	long hBottomDesc = (long)pfInput[2];
	long hBottomData = (long)pfInput[3];
	T fBeta = pfInput[4];
	long hTopDesc = (long)pfInput[5];
	long hTopData = (long)pfInput[6];

	return m_memory.ReLUForward(hHandle, fAlpha, hBottomDesc, hBottomData, fBeta, hTopDesc, hTopData);
}

template <class T>
inline long Device<T>::ReLUBackward(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 11, 11))
		return lErr;

	long hHandle = (long)pfInput[0];
	T fAlpha = pfInput[1];
	long hTopDataDesc = (long)pfInput[2];
	long hTopData = (long)pfInput[3];
	long hTopDiffDesc = (long)pfInput[4];
	long hTopDiff = (long)pfInput[5];
	long hBottomDataDesc = (long)pfInput[6];
	long hBottomData = (long)pfInput[7];
	T fBeta = pfInput[8];
	long hBottomDiffDesc = (long)pfInput[9];
	long hBottomDiff = (long)pfInput[10];

	return m_memory.ReLUBackward(hHandle, fAlpha, hTopDataDesc, hTopData, hTopDiffDesc, hTopDiff, hBottomDataDesc, hBottomData, fBeta, hBottomDiffDesc, hBottomDiff);
}


template <class T>
inline long Device<T>::SoftmaxForward(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 7, 7))
		return lErr;

	long hHandle = (long)pfInput[0];
	T fAlpha = pfInput[1];
	long hBottomDesc = (long)pfInput[2];
	long hBottomData = (long)pfInput[3];
	T fBeta = pfInput[4];
	long hTopDesc = (long)pfInput[5];
	long hTopData = (long)pfInput[6];

	return m_memory.SoftmaxForward(hHandle, fAlpha, hBottomDesc, hBottomData, fBeta, hTopDesc, hTopData);
}

template <class T>
inline long Device<T>::SoftmaxBackward(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 9, 9))
		return lErr;

	long hHandle = (long)pfInput[0];
	T fAlpha = pfInput[1];
	long hTopDataDesc = (long)pfInput[2];
	long hTopData = (long)pfInput[3];
	long hTopDiffDesc = (long)pfInput[4];
	long hTopDiff = (long)pfInput[5];
	T fBeta = pfInput[6];
	long hBottomDiffDesc = (long)pfInput[7];
	long hBottomDiff = (long)pfInput[8];

	return m_memory.SoftmaxBackward(hHandle, fAlpha, hTopDataDesc, hTopData, hTopDiffDesc, hTopDiff, fBeta, hBottomDiffDesc, hBottomDiff);
}


template <class T>
inline long Device<T>::LRNForwardCC(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 8, 8))
		return lErr;

	long hHandle = (long)pfInput[0];
	long hNormDesc = (long)pfInput[1];
	T fAlpha = pfInput[2];
	long hBottomDesc = (long)pfInput[3];
	long hBottomData = (long)pfInput[4];
	T fBeta = pfInput[5];
	long hTopDesc = (long)pfInput[6];
	long hTopData = (long)pfInput[7];

	return m_memory.LRNForwardCC(hHandle, hNormDesc, fAlpha, hBottomDesc, hBottomData, fBeta, hTopDesc, hTopData);
}

template <class T>
inline long Device<T>::LRNBackwardCC(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 12, 12))
		return lErr;

	long hHandle = (long)pfInput[0];
	long hNormDesc = (long)pfInput[1];
	T fAlpha = pfInput[2];
	long hTopDataDesc = (long)pfInput[3];
	long hTopData = (long)pfInput[4];
	long hTopDiffDesc = (long)pfInput[5];
	long hTopDiff = (long)pfInput[6];
	long hBottomDataDesc = (long)pfInput[7];
	long hBottomData = (long)pfInput[8];
	T fBeta = pfInput[9];
	long hBottomDiffDesc = (long)pfInput[10];
	long hBottomDiff = (long)pfInput[11];

	return m_memory.LRNBackwardCC(hHandle, hNormDesc, fAlpha, hTopDataDesc, hTopData, hTopDiffDesc, hTopDiff, hBottomDataDesc, hBottomData, fBeta, hBottomDiffDesc, hBottomDiff);
}

template <class T>
inline long Device<T>::LCNForwardCC(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 10, 10))
		return lErr;

	long hHandle = (long)pfInput[0];
	long hNormDesc = (long)pfInput[1];
	T fAlpha = pfInput[2];
	long hBottomDesc = (long)pfInput[3];
	long hBottomData = (long)pfInput[4];
	long hTemp1 = (long)pfInput[5];
	long hTemp2 = (long)pfInput[6];
	T fBeta = pfInput[7];
	long hTopDesc = (long)pfInput[8];
	long hTopData = (long)pfInput[9];

	return m_memory.LCNForwardCC(hHandle, hNormDesc, fAlpha, hBottomDesc, hBottomData, hTemp1, hTemp2, fBeta, hTopDesc, hTopData);
}

template <class T>
inline long Device<T>::LCNBackwardCC(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 11, 11))
		return lErr;

	long hHandle = (long)pfInput[0];
	long hNormDesc = (long)pfInput[1];
	T fAlpha = pfInput[2];
	long hBottomDataDesc = (long)pfInput[3];
	long hBottomData = (long)pfInput[4];
	long hTopDiff = (long)pfInput[5];
	long hTemp1 = (long)pfInput[6];
	long hTemp2 = (long)pfInput[7];
	T fBeta = pfInput[8];
	long hBottomDiffDesc = (long)pfInput[9];
	long hBottomDiff = (long)pfInput[10];

	return m_memory.LCNBackwardCC(hHandle, hNormDesc, fAlpha, hBottomDataDesc, hBottomData, hTopDiff, hTemp1, hTemp2, fBeta, hBottomDiffDesc, hBottomDiff);
}


template <class T>
inline long Device<T>::cuda_relu_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 4, 4))
		return lErr;

	int nCount = (int)pfInput[0];
	long hBottomData = (long)pfInput[1];
	long hTopData = (long)pfInput[2];
	T fNegativeSlope = pfInput[3];

	return m_math.relu_fwd(nCount, hBottomData, hTopData, fNegativeSlope);
}

template <class T>
inline long Device<T>::cuda_relu_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 5, 5))
		return lErr;

	int nCount = (int)pfInput[0];
	long hTopDiff = (long)pfInput[1];
	long hTopData = (long)pfInput[2];
	long hBottomDiff = (long)pfInput[3];
	T fNegativeSlope = pfInput[4];

	return m_math.relu_bwd(nCount, hTopDiff, hTopData, hBottomDiff, fNegativeSlope);
}


template <class T>
inline long Device<T>::cuda_elu_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 4, 4))
		return lErr;

	int nCount = (int)pfInput[0];
	long hBottomData = (long)pfInput[1];
	long hTopData = (long)pfInput[2];
	T fAlpha = pfInput[3];

	return m_math.elu_fwd(nCount, hBottomData, hTopData, fAlpha);
}

template <class T>
inline long Device<T>::cuda_elu_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 6, 6))
		return lErr;

	int nCount = (int)pfInput[0];
	long hTopDiff = (long)pfInput[1];
	long hTopData = (long)pfInput[2];
	long hBottomData = (long)pfInput[3];
	long hBottomDiff = (long)pfInput[4];
	T fAlpha = pfInput[5];

	return m_math.elu_bwd(nCount, hTopDiff, hTopData, hBottomData, hBottomDiff, fAlpha);
}


template <class T>
inline long Device<T>::cuda_dropout_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 6, 6))
		return lErr;

	int nCount = (int)pfInput[0];
	long hBottomData = (long)pfInput[1];
	long hMask = (long)pfInput[2];
	unsigned int uiThreshold = (unsigned int)pfInput[3];
	T fScale = pfInput[4];
	long hTopData = (long)pfInput[5];

	return m_math.dropout_fwd(nCount, hBottomData, hMask, uiThreshold, fScale, hTopData);
}

template <class T>
inline long Device<T>::cuda_dropout_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 6, 6))
		return lErr;

	int nCount = (int)pfInput[0];
	long hTopDiff = (long)pfInput[1];
	long hMask = (long)pfInput[2];
	unsigned int uiThreshold = (unsigned int)pfInput[3];
	T fScale = pfInput[4];
	long hBottomDiff = (long)pfInput[5];

	return m_math.dropout_bwd(nCount, hTopDiff, hMask, uiThreshold, fScale, hBottomDiff);
}

template <class T>
inline long Device<T>::cuda_bnll_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 3, 3))
		return lErr;

	int nCount = (int)pfInput[0];
	long hBottomData = (long)pfInput[1];
	long hTopData = (long)pfInput[2];

	return m_math.bnll_fwd(nCount, hBottomData, hTopData);
}

template <class T>
inline long Device<T>::cuda_bnll_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 4, 4))
		return lErr;

	int nCount = (int)pfInput[0];
	long hTopDiff = (long)pfInput[1];
	long hBottomData = (long)pfInput[2];
	long hBottomDiff = (long)pfInput[3];

	return m_math.bnll_bwd(nCount, hTopDiff, hBottomData, hBottomDiff);
}


template <class T>
inline long Device<T>::cuda_prelu_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 7, 7))
		return lErr;

	int nCount = (int)pfInput[0];
	int nChannels = (int)pfInput[1];
	int nDim = (int)pfInput[2];
	long hBottomData = (long)pfInput[3];
	long hTopData = (long)pfInput[4];
	long hSlopeData = (long)pfInput[5];
	int nDivFactor = (int)pfInput[6];

	return m_math.prelu_fwd(nCount, nChannels, nDim, hBottomData, hTopData, hSlopeData, nDivFactor);
}

template <class T>
inline long Device<T>::cuda_prelu_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 8, 8))
		return lErr;

	int nCount = (int)pfInput[0];
	int nChannels = (int)pfInput[1];
	int nDim = (int)pfInput[2];
	long hTopDiff = (long)pfInput[3];
	long hBottomData = (long)pfInput[4];
	long hBottomDiff = (long)pfInput[5];
	long hSlopeData = (long)pfInput[6];
	int nDivFactor = (int)pfInput[7];

	return m_math.prelu_bwd(nCount, nChannels, nDim, hTopDiff, hBottomData, hBottomDiff, hSlopeData, nDivFactor);
}

template <class T>
inline long Device<T>::cuda_prelu_bwd_param(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 6, 6))
		return lErr;

	int nCDim = (int)pfInput[0];
	int nNum = (int)pfInput[1];
	int nTopOffset = (int)pfInput[2];
	long hTopDiff = (long)pfInput[3];
	long hBottomData = (long)pfInput[4];
	long hBackBuffDiff = (long)pfInput[5];

	return m_math.prelu_bwd_param(nCDim, nNum, nTopOffset, hTopDiff, hBottomData, hBackBuffDiff);
}


template <class T>
inline long Device<T>::cuda_softmaxloss_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 8, 9))
		return lErr;

	int nCount = (int)pfInput[0];
	long hProbData = (long)pfInput[1];
	long hLabels = (long)pfInput[2];
	long hLossData = (long)pfInput[3];
	int nOuterNum = (int)pfInput[4];
	int nDim = (int)pfInput[5];
	int nInnerNum = (int)pfInput[6];
	long hCounts = (long)pfInput[7];
	int nIgnoreLabel = -1;

	if (lInput > 8)
		nIgnoreLabel = (int)pfInput[8];

	return m_math.softmaxloss_fwd(nCount, hProbData, hLabels, hLossData, nOuterNum, nDim, nInnerNum, hCounts, nIgnoreLabel);
}

template <class T>
inline long Device<T>::cuda_softmaxloss_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 8, 9))
		return lErr;

	int nCount = (int)pfInput[0];
	long hTopData = (long)pfInput[1];
	long hLabels = (long)pfInput[2];
	long hBottomDiff = (long)pfInput[3];
	int nOuterNum = (int)pfInput[4];
	int nDim = (int)pfInput[5];
	int nInnerNum = (int)pfInput[6];
	long hCounts = (long)pfInput[7];
	int nIgnoreLabel = -1;

	if (lInput > 8)
		nIgnoreLabel = (int)pfInput[8];

	return m_math.softmaxloss_bwd(nCount, hTopData, hLabels, hBottomDiff, nOuterNum, nDim, nInnerNum, hCounts, nIgnoreLabel);
}


template <class T>
inline long Device<T>::cuda_max_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 6, 6))
		return lErr;

	int nCount = (int)pfInput[0];
	long hA = (long)pfInput[1];
	long hB = (long)pfInput[2];
	int nIdx = (int)pfInput[3];
	long hY = (long)pfInput[4];
	long hMask = (long)pfInput[5];

	return m_math.max_fwd(nCount, hA, hB, nIdx, hY, hMask);
}

template <class T>
inline long Device<T>::cuda_max_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 5, 5))
		return lErr;

	int nCount = (int)pfInput[0];
	long hX = (long)pfInput[1];
	int nIdx = (int)pfInput[2];
	long hMask = (long)pfInput[3];
	long hY = (long)pfInput[4];

	return m_math.max_bwd(nCount, hX, nIdx, hMask, hY);
}


template <class T>
inline long Device<T>::cuda_crop_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 7, 7))
		return lErr;

	int nCount = (int)pfInput[0];
	int nNumAxes = (int)pfInput[1];
	int hSrcStrides = (long)pfInput[2];
	int hDstStrides = (long)pfInput[3];
	int hOffsets = (long)pfInput[4];
	long hBottomData = (long)pfInput[5];
	long hTopData = (long)pfInput[6];

	return m_math.crop_fwd(nCount, nNumAxes, hSrcStrides, hDstStrides, hOffsets, hBottomData, hTopData);
}


template <class T>
inline long Device<T>::cuda_crop_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 7, 7))
		return lErr;

	int nCount = (int)pfInput[0];
	int nNumAxes = (int)pfInput[1];
	int hSrcStrides = (long)pfInput[2];
	int hDstStrides = (long)pfInput[3];
	int hOffsets = (long)pfInput[4];
	long hBottomDiff = (long)pfInput[5];
	long hTopDiff = (long)pfInput[6];

	return m_math.crop_bwd(nCount, nNumAxes, hSrcStrides, hDstStrides, hOffsets, hBottomDiff, hTopDiff);
}


template <class T>
inline long Device<T>::cuda_concat_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 8, 8))
		return lErr;

	int nCount = (int)pfInput[0];
	long hBottomData = (long)pfInput[1];
	int nNumConcats = (int)pfInput[2];
	int nConcatInputSize = (int)pfInput[3];
	int nTopConcatAxis = (int)pfInput[4];
	int nBottomConcatAxis = (int)pfInput[5];
	int nOffsetConcatAxis = (int)pfInput[6];
	long hTopData = (long)pfInput[7];

	return m_math.concat_fwd(nCount, hBottomData, nNumConcats, nConcatInputSize, nTopConcatAxis, nBottomConcatAxis, nOffsetConcatAxis, hTopData);
}


template <class T>
inline long Device<T>::cuda_concat_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 8, 8))
		return lErr;

	int nCount = (int)pfInput[0];
	long hTopDiff = (long)pfInput[1];
	int nNumConcats = (int)pfInput[2];
	int nConcatInputSize = (int)pfInput[3];
	int nTopConcatAxis = (int)pfInput[4];
	int nBottomConcatAxis = (int)pfInput[5];
	int nOffsetConcatAxis = (int)pfInput[6];
	long hBottomDiff = (long)pfInput[7];

	return m_math.concat_bwd(nCount, hTopDiff, nNumConcats, nConcatInputSize, nTopConcatAxis, nBottomConcatAxis, nOffsetConcatAxis, hBottomDiff);
}


template <class T>
inline long Device<T>::cuda_slice_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 8, 8))
		return lErr;

	int nCount = (int)pfInput[0];
	long hBottomData = (long)pfInput[1];
	int nNumSlices = (int)pfInput[2];
	int nSliceInputSize = (int)pfInput[3];
	int nBottomSliceAxis = (int)pfInput[4];
	int nTopSliceAxis = (int)pfInput[5];
	int nOffsetSliceAxis = (int)pfInput[6];
	long hTopData = (long)pfInput[7];

	return m_math.slice_fwd(nCount, hBottomData, nNumSlices, nSliceInputSize, nBottomSliceAxis, nTopSliceAxis, nOffsetSliceAxis, hTopData);
}


template <class T>
inline long Device<T>::cuda_slice_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 8, 8))
		return lErr;

	int nCount = (int)pfInput[0];
	long hTopDiff = (long)pfInput[1];
	int nNumSlices = (int)pfInput[2];
	int nSliceInputSize = (int)pfInput[3];
	int nBottomSliceAxis = (int)pfInput[4];
	int nTopSliceAxis = (int)pfInput[5];
	int nOffsetSliceAxis = (int)pfInput[6];
	long hBottomDiff = (long)pfInput[7];

	return m_math.slice_bwd(nCount, hTopDiff, nNumSlices, nSliceInputSize, nBottomSliceAxis, nTopSliceAxis, nOffsetSliceAxis, hBottomDiff);
}


template <class T>
inline long Device<T>::cuda_tile_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 6, 6))
		return lErr;

	int nCount = (int)pfInput[0];
	long hBottomData = (long)pfInput[1];
	int nInnerDim = (int)pfInput[2];
	int nTiles = (int)pfInput[3];
	int nBottomTileAxis = (int)pfInput[4];
	long hTopData = (long)pfInput[5];

	return m_math.tile_fwd(nCount, hBottomData, nInnerDim, nTiles, nBottomTileAxis, hTopData);
}


template <class T>
inline long Device<T>::cuda_tile_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 6, 6))
		return lErr;

	int nCount = (int)pfInput[0];
	long hTopDiff = (long)pfInput[1];
	int nTileSize = (int)pfInput[2];
	int nTiles = (int)pfInput[3];
	int nBottomTileAxis = (int)pfInput[4];
	long hBottomDiff = (long)pfInput[5];

	return m_math.tile_bwd(nCount, hTopDiff, nTileSize, nTiles, nBottomTileAxis, hBottomDiff);
}


template <class T>
inline long Device<T>::cuda_bias_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 6, 6))
		return lErr;

	int nCount = (int)pfInput[0];
	long hBottomData = (long)pfInput[1];
	long hBiasData = (long)pfInput[2];
	int nBiasDim = (int)pfInput[3];
	int nInnerDim = (int)pfInput[4];
	long hTopData = (long)pfInput[5];

	return m_math.bias_fwd(nCount, hBottomData, hBiasData, nBiasDim, nInnerDim, hTopData);
}


template <class T>
inline long Device<T>::cuda_scale_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 6, 7))
		return lErr;

	int nCount = (int)pfInput[0];
	long hX = (long)pfInput[1];
	long hScaleData = (long)pfInput[2];
	int nScaleDim = (int)pfInput[3];
	int nInnerDim = (int)pfInput[4];
	long hY = (long)pfInput[5];
	long hBiasData = 0;

	if (lInput > 6)
		hBiasData = (long)pfInput[6];

	return m_math.scale_fwd(nCount, hX, hScaleData, nScaleDim, nInnerDim, hY, hBiasData);
}


template <class T>
inline long Device<T>::cuda_threshold_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 4, 4))
		return lErr;

	int nCount = (int)pfInput[0];
	T fThreshold = pfInput[1];
	long hX = (long)pfInput[2];
	long hY = (long)pfInput[3];

	return m_math.threshold_fwd(nCount, fThreshold, hX, hY);
}



template <class T>
inline long Device<T>::cuda_cll_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 9, 9))
		return lErr;

	int nCount = (int)pfInput[0];
	int nChannels = (int)pfInput[1];
	T fMargin = pfInput[2];
	bool bLegacyVersion = (pfInput[3] != 0) ? true : false;
	T fAlpha = pfInput[4];
	long hY = (long)pfInput[5];
	long hDiff = (long)pfInput[6];
	long hDistSq = (long)pfInput[7];
	long hBottomDiff = (long)pfInput[8];

	return m_math.cll_bwd(nCount, nChannels, fMargin, bLegacyVersion, fAlpha, hY, hDiff, hDistSq, hBottomDiff);
}


template <class T>
inline long Device<T>::cuda_lrn_fillscale(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 10, 10))
		return lErr;

	int nCount = (int)pfInput[0];
	long hBottomData = (long)pfInput[1];
	int nNum = (int)pfInput[2];
	int nChannels = (int)pfInput[3];
	int nHeight = (int)pfInput[4];
	int nWidth = (int)pfInput[5];
	int nSize = (int)pfInput[6];
	T fA = pfInput[7];
	T fB = pfInput[8];
	long hScaleData = (long)pfInput[9];

	return m_math.lrn_fillscale(nCount, hBottomData, nNum, nChannels, nHeight, nWidth, nSize, fA, fB, hScaleData);
}


template <class T>
inline long Device<T>::cuda_lrn_computeoutput(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 5, 5))
		return lErr;

	int nCount = (int)pfInput[0];
	long hBottomData = (long)pfInput[1];
	long hScaleData = (long)pfInput[2];
	T fA = pfInput[3];
	long hTopData = (long)pfInput[4];

	return m_math.lrn_computeoutput(nCount, hBottomData, hScaleData, fA, hTopData);
}


template <class T>
inline long Device<T>::cuda_lrn_computediff(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 13, 13))
		return lErr;

	int nCount = (int)pfInput[0];
	long hBottomData = (long)pfInput[1];
	long hTopData = (long)pfInput[2];
	long hScaleData = (long)pfInput[3];
	long hTopDiff = (long)pfInput[4];
	int nNum = (int)pfInput[5];
	int nChannels = (int)pfInput[6];
	int nHeight = (int)pfInput[7];
	int nWidth = (int)pfInput[8];
	int nSize = (int)pfInput[9];
	T fB = pfInput[10];
	T fA = pfInput[11];
	long hBottomDiff = (long)pfInput[12];

	return m_math.lrn_computediff(nCount, hBottomData, hTopData, hScaleData, hTopDiff, nNum, nChannels, nHeight, nWidth, nSize, fB, fA, hBottomDiff);
}


template <class T>
inline long Device<T>::cuda_lstm_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 20, 20))
		return lErr;

	int t = (int)pfInput[0];
	int nN = (int)pfInput[1];
	int nH = (int)pfInput[2];
	long hWeight_h = (long)pfInput[3];
	long hWeight_i = (long)pfInput[4];
	long hClipData = (long)pfInput[5];
	int nClipOffset = (int)pfInput[6];
	long hTopData = (long)pfInput[7];
	int nTopOffset = (int)pfInput[8];
	long hCellData = (long)pfInput[9];
	int nCellOffset = (int)pfInput[10];
	long hPreGateData = (long)pfInput[11];
	int nPreGateOffset = (int)pfInput[12];
	long hGateData = (long)pfInput[13];
	int nGateOffset = (int)pfInput[14];
	long hHT1Data = (long)pfInput[15];
	int nHT1Offset = (int)pfInput[16];
	long hCT1Data = (long)pfInput[17];
	int nCT1Offset = (int)pfInput[18];
	long hHtoGateData = (long)pfInput[19];

	return m_math.lstm_fwd(t, nN, nH, hWeight_h, hWeight_i, hClipData, nClipOffset, hTopData, nTopOffset, hCellData, nCellOffset, hPreGateData, nPreGateOffset, hGateData, nGateOffset, hHT1Data, nHT1Offset, hCT1Data, nCT1Offset, hHtoGateData);
}


template <class T>
inline long Device<T>::cuda_lstm_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 24, 24))
		return lErr;

	int t = (int)pfInput[0];
	int nN = (int)pfInput[1];
	int nH = (int)pfInput[2];
	T fClip = pfInput[3];
	long hWeight_h = (long)pfInput[4];
	long hClipData = (long)pfInput[5];
	int nClipOffset = (int)pfInput[6];
	long hTopDiff = (long)pfInput[7];
	int nTopOffset = (int)pfInput[8];
	long hCellData = (long)pfInput[9];
	long hCellDiff = (long)pfInput[10];
	int nCellOffset = (int)pfInput[11];
	long hPreGateDiff = (long)pfInput[12];
	int nPreGateOffset = (int)pfInput[13];
	long hGateData = (long)pfInput[14];
	long hGateDiff = (long)pfInput[15];
	int nGateOffset = (int)pfInput[16];
	long hCT1Data = (long)pfInput[17];
	int nCT1Offset = (int)pfInput[18];
	long hDHT1Diff = (long)pfInput[19];
	int nDHT1Offset = (int)pfInput[20];
	long hDCT1Diff = (long)pfInput[21];
	int nDCT1Offset = (int)pfInput[22];
	long hHtoHData = (long)pfInput[23];

	return m_math.lstm_bwd(t, nN, nH, fClip, hWeight_h, hClipData, nClipOffset, hTopDiff, nTopOffset, hCellData, hCellDiff, nCellOffset, hPreGateDiff, nPreGateOffset, hGateData, hGateDiff, nGateOffset, hCT1Data, nCT1Offset, hDHT1Diff, nDHT1Offset, hDCT1Diff, nDCT1Offset, hHtoHData);
}


template <class T>
inline long Device<T>::cuda_lstm_unit_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 9, 9))
		return lErr;

	int nCount = (int)pfInput[0];
	int nHiddenDim = (int)pfInput[1];
	int nXCount = (int)pfInput[2];
	long hX = (long)pfInput[3];
	long hX_acts = (long)pfInput[4];
	long hC_prev = (long)pfInput[5];
	long hCont = (long)pfInput[6];
	long hC = (long)pfInput[7];
	long hH = (long)pfInput[8];

	return m_math.lstm_unit_fwd(nCount, nHiddenDim, nXCount, hX, hX_acts, hC_prev, hCont, hC, hH);
}


template <class T>
inline long Device<T>::cuda_lstm_unit_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 13, 13))
		return lErr;

	int nCount = (int)pfInput[0];
	int nHiddenDim = (int)pfInput[1];
	int nXCount = (int)pfInput[2];
	long hC_prev = (long)pfInput[3];
	long hX_acts = (long)pfInput[4];
	long hC = (long)pfInput[5];
	long hH = (long)pfInput[6];
	long hCont = (long)pfInput[7];
	long hC_diff = (long)pfInput[8];
	long hH_diff = (long)pfInput[9];
	long hC_prev_diff = (long)pfInput[10];
	long hX_acts_diff = (long)pfInput[11];
	long hX_diff = (long)pfInput[12];

	return m_math.lstm_unit_bwd(nCount, nHiddenDim, nXCount, hC_prev, hX_acts, hC, hH, hCont, hC_diff, hH_diff, hC_prev_diff, hX_acts_diff, hX_diff);
}


template <class T>
inline long Device<T>::cuda_coeff_sum_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 7, 7))
		return lErr;

	int nCount = (int)pfInput[0];
	int nDim = (int)pfInput[1];
	int nNumOffset = (int)pfInput[2];
	T fCoeff = pfInput[3];
	long hCoeffData = (long)pfInput[4];
	long hBottomData = (long)pfInput[5];
	long hTopData = (long)pfInput[6];

	return m_math.coeff_sum_fwd(nCount, nDim, nNumOffset, fCoeff, hCoeffData, hBottomData, hTopData);
}

template <class T>
inline long Device<T>::cuda_coeff_sum_bwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 7, 7))
		return lErr;

	int nCount = (int)pfInput[0];
	int nDim = (int)pfInput[1];
	int nNumOffset = (int)pfInput[2];
	T fCoeff = pfInput[3];
	long hCoeffData = (long)pfInput[4];
	long hTopDiff = (long)pfInput[5];
	long hBottomDiff = (long)pfInput[6];

	return m_math.coeff_sum_bwd(nCount, nDim, nNumOffset, fCoeff, hCoeffData, hTopDiff, hBottomDiff);
}

template <class T>
inline long Device<T>::cuda_sigmoid_cross_entropy_fwd(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 7, 7))
		return lErr;

	int nCount = (int)pfInput[0];
	long hInput = (long)pfInput[1];
	long hTarget = (long)pfInput[2];
	long hLoss = (long)pfInput[3];
	bool bHasIgnoreLabel = (pfInput[4] == 1) ? true : false;
	int nIgnoreLabel = (int)pfInput[5];
	long hCount = (long)pfInput[6];

	return m_math.sigmoid_cross_entropy_fwd(nCount, hInput, hTarget, hLoss, bHasIgnoreLabel, nIgnoreLabel, hCount);
}

template <class T>
inline long Device<T>::cuda_sigmoid_cross_entropy_ignore(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 4, 4))
		return lErr;

	int nCount = (int)pfInput[0];
	int nIgnoreLabel = (int)pfInput[1];
	long hTarget = (long)pfInput[2];
	long hData = (long)pfInput[3];

	return m_math.sigmoid_cross_entropy_ignore(nCount, nIgnoreLabel, hTarget, hData);
}


//=============================================================================
//	Math Methods
//=============================================================================

template <class T>
inline long Device<T>::cuda_set(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 3, 5))
		return lErr;

	int nCount = (int)pfInput[0];
	long hHandle = (long)pfInput[1];
	T fVal = pfInput[2];
	int nIdx = -1;
	int nXOff = 0;

	if (lInput > 3)
		nIdx = (int)pfInput[3];

	if (lInput > 4)
		nXOff = (int)pfInput[4];

	return m_math.set(nCount, hHandle, fVal, nIdx, nXOff);
}

template <class T>
inline long Device<T>::cuda_copy(long lInput, T* pfInput, long* plOutput, T** ppfOutput)
{
	LONG lErr;

	if (lErr = verifyInput(lInput, pfInput, 3, 6))
		return lErr;

	int nCount = (int)pfInput[0];
	long hSrc = (long)pfInput[1];
	long hDst = (long)pfInput[2];
	int nSrcOffset = 0;
	int nDstOffset = 0;
	long hAsyncStream = -1;

	if (lInput > 3)
		nSrcOffset = (int)pfInput[3];

	if (lInput > 4)
		nDstOffset = (int)pfInput[4];

	if (lInput > 5)
		hAsyncStream = (long)pfInput[5];

	return m_math.copy(nCount, hSrc, hDst, nSrcOffset, nDstOffset, hAsyncStream);
}

#endif // __DEVICE_CU__