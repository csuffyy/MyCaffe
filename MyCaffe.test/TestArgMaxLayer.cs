﻿using System;
using System.Text;
using System.Collections.Generic;
using System.Linq;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using MyCaffe.basecode;
using MyCaffe.param;
using MyCaffe.common;
using MyCaffe.layers;

namespace MyCaffe.test
{
    [TestClass]
    public class TestArgMaxLayer
    {
        [TestMethod]
        public void TestSetup()
        {
            ArgMaxLayerTest test = new ArgMaxLayerTest();

            try
            {
                foreach (IArgMaxLayerTest t in test.Tests)
                {
                    t.TestSetup();
                }
            }
            finally
            {
                test.Dispose();
            }
        }

        [TestMethod]
        public void TestSetupMaxVal()
        {
            ArgMaxLayerTest test = new ArgMaxLayerTest();

            try
            {
                foreach (IArgMaxLayerTest t in test.Tests)
                {
                    t.TestSetupMaxVal();
                }
            }
            finally
            {
                test.Dispose();
            }
        }

        [TestMethod]
        public void TestSetupAxis()
        {
            ArgMaxLayerTest test = new ArgMaxLayerTest();

            try
            {
                foreach (IArgMaxLayerTest t in test.Tests)
                {
                    t.TestSetupAxis();
                }
            }
            finally
            {
                test.Dispose();
            }
        }

        [TestMethod]
        public void TestSetupAxisNegativeIndexing()
        {
            ArgMaxLayerTest test = new ArgMaxLayerTest();

            try
            {
                foreach (IArgMaxLayerTest t in test.Tests)
                {
                    t.TestSetupAxisNegativeIndexing();
                }
            }
            finally
            {
                test.Dispose();
            }
        }

        [TestMethod]
        public void TestSetupAxisMaxVal()
        {
            ArgMaxLayerTest test = new ArgMaxLayerTest();

            try
            {
                foreach (IArgMaxLayerTest t in test.Tests)
                {
                    t.TestSetupAxisMaxVal();
                }
            }
            finally
            {
                test.Dispose();
            }
        }

        [TestMethod]
        public void TestCpu()
        {
            ArgMaxLayerTest test = new ArgMaxLayerTest();

            try
            {
                foreach (IArgMaxLayerTest t in test.Tests)
                {
                    t.TestCpu();
                }
            }
            finally
            {
                test.Dispose();
            }
        }

        [TestMethod]
        public void TestCpuMaxVal()
        {
            ArgMaxLayerTest test = new ArgMaxLayerTest();

            try
            {
                foreach (IArgMaxLayerTest t in test.Tests)
                {
                    t.TestCpuMaxVal();
                }
            }
            finally
            {
                test.Dispose();
            }
        }

        [TestMethod]
        public void TestCpuTopK()
        {
            ArgMaxLayerTest test = new ArgMaxLayerTest();

            try
            {
                foreach (IArgMaxLayerTest t in test.Tests)
                {
                    t.TestCpuTopK();
                }
            }
            finally
            {
                test.Dispose();
            }
        }

        [TestMethod]
        public void TestCpuMaxValTopK()
        {
            ArgMaxLayerTest test = new ArgMaxLayerTest();

            try
            {
                foreach (IArgMaxLayerTest t in test.Tests)
                {
                    t.TestCpuMaxValTopK();
                }
            }
            finally
            {
                test.Dispose();
            }
        }

        [TestMethod]
        public void TestCpuAxis()
        {
            ArgMaxLayerTest test = new ArgMaxLayerTest();

            try
            {
                foreach (IArgMaxLayerTest t in test.Tests)
                {
                    t.TestCpuAxis();
                }
            }
            finally
            {
                test.Dispose();
            }
        }

        [TestMethod]
        public void TestCpuAxisTopK()
        {
            ArgMaxLayerTest test = new ArgMaxLayerTest();

            try
            {
                foreach (IArgMaxLayerTest t in test.Tests)
                {
                    t.TestCpuAxisTopK();
                }
            }
            finally
            {
                test.Dispose();
            }
        }

        /// <summary>
        /// This test fails.
        /// </summary>
        [TestMethod]
        public void TestCpuAxisMaxValTopK()
        {
            ArgMaxLayerTest test = new ArgMaxLayerTest();

            try
            {
                foreach (IArgMaxLayerTest t in test.Tests)
                {
                    t.TestCpuAxisMaxValTopK();
                }
            }
            finally
            {
                test.Dispose();
            }
        }
    }


    interface IArgMaxLayerTest : ITest
    {
        void TestSetup();
        void TestSetupMaxVal();
        void TestSetupAxis();
        void TestSetupAxisNegativeIndexing();
        void TestSetupAxisMaxVal();
        void TestCpu();
        void TestCpuMaxVal();
        void TestCpuTopK();
        void TestCpuMaxValTopK();
        void TestCpuAxis();
        void TestCpuAxisTopK();
        void TestCpuAxisMaxValTopK();
    }

    class ArgMaxLayerTest : TestBase
    {
        public ArgMaxLayerTest(EngineParameter.Engine engine = EngineParameter.Engine.DEFAULT)
            : base("ArgMax Layer Test", TestBase.DEFAULT_DEVICE_ID, engine)
        {
        }

        protected override ITest create(common.DataType dt, string strName, int nDeviceID, EngineParameter.Engine engine)
        {
            if (dt == common.DataType.DOUBLE)
                return new ArgMaxLayerTest<double>(strName, nDeviceID, engine);
            else
                return new ArgMaxLayerTest<float>(strName, nDeviceID, engine);
        }
    }

    class ArgMaxLayerTest<T> : TestEx<T>, IArgMaxLayerTest
    {
        int m_nTopK;

        public ArgMaxLayerTest(string strName, int nDeviceID, EngineParameter.Engine engine)
            : base(strName, new List<int>() { 10, 10, 20, 20 }, nDeviceID)
        {
            m_engine = engine;
            m_nTopK = 5;
        }

        public int TopK
        {
            get { return m_nTopK; }            
        }

        public void TestSetup()
        {
            LayerParameter p = new LayerParameter(LayerParameter.LayerType.ARGMAX);
            ArgMaxLayer<T> layer = new ArgMaxLayer<T>(m_cuda, m_log, p);

            layer.Setup(BottomVec, TopVec);

            m_log.CHECK_EQ(Bottom.shape(0), Top.shape(0), "The top and bottom shape(0) should be equal.");
            m_log.CHECK_EQ(1, Top.shape(1), "The top channels should equal 1.");
        }


        public void TestSetupMaxVal()
        {
            LayerParameter p = new LayerParameter(LayerParameter.LayerType.ARGMAX);
            p.argmax_param.out_max_val = true;
            ArgMaxLayer<T> layer = new ArgMaxLayer<T>(m_cuda, m_log, p);

            layer.Setup(BottomVec, TopVec);

            m_log.CHECK_EQ(Top.num, Bottom.num, "The top num and bottom num should be equal.");
            m_log.CHECK_EQ(2, Top.channels, "The top channels should equal 2.");
        }

        public void TestSetupAxis()
        {
            LayerParameter p = new LayerParameter(LayerParameter.LayerType.ARGMAX);
            p.argmax_param.axis = 0;
            ArgMaxLayer<T> layer = new ArgMaxLayer<T>(m_cuda, m_log, p);

            layer.Setup(BottomVec, TopVec);

            m_log.CHECK_EQ(Top.shape(0), p.argmax_param.top_k, "The top shape(0) and top_k should be equal.");
            m_log.CHECK_EQ(Top.shape(1), Bottom.shape(0), "The top shape(1) and bottom shape(0) should be equal.");
            m_log.CHECK_EQ(Top.shape(2), Bottom.shape(2), "The top and bottom shape(2) should be equal.");
            m_log.CHECK_EQ(Top.shape(3), Bottom.shape(3), "The top and bottom shape(3) should be equal.");
        }

        public void TestSetupAxisNegativeIndexing()
        {
            LayerParameter p = new LayerParameter(LayerParameter.LayerType.ARGMAX);
            p.argmax_param.axis = -2;
            ArgMaxLayer<T> layer = new ArgMaxLayer<T>(m_cuda, m_log, p);

            layer.Setup(BottomVec, TopVec);

            m_log.CHECK_EQ(Top.shape(0), Bottom.shape(0), "The top shape(0) and bottom shape(0) should be equal.");
            m_log.CHECK_EQ(Top.shape(1), Bottom.shape(1), "The top shape(1) and bottom shape(1) should be equal.");
            m_log.CHECK_EQ(Top.shape(2), p.argmax_param.top_k, "The top shape(2) and top_k should be equal.");
            m_log.CHECK_EQ(Top.shape(3), Bottom.shape(3), "The top and bottom shape(3) should be equal.");
        }

        public void TestSetupAxisMaxVal()
        {
            LayerParameter p = new LayerParameter(LayerParameter.LayerType.ARGMAX);
            p.argmax_param.axis = 2;
            ArgMaxLayer<T> layer = new ArgMaxLayer<T>(m_cuda, m_log, p);

            layer.Setup(BottomVec, TopVec);

            m_log.CHECK_EQ(Top.shape(0), Bottom.shape(0), "The top shape(0) and bottom shape(0) should be equal.");
            m_log.CHECK_EQ(Top.shape(1), Bottom.shape(1), "The top shape(1) and bottom shape(1) should be equal.");
            m_log.CHECK_EQ(Top.shape(2), p.argmax_param.top_k, "The top shape(2) and top_k should be equal.");
            m_log.CHECK_EQ(Top.shape(3), Bottom.shape(3), "The top and bottom shape(3) should be equal.");
        }

        public void TestCpu()
        {
            LayerParameter p = new LayerParameter(LayerParameter.LayerType.ARGMAX);
            ArgMaxLayer<T> layer = new ArgMaxLayer<T>(m_cuda, m_log, p);

            layer.Setup(BottomVec, TopVec);
            layer.Forward(BottomVec, TopVec);

            // Now, check values
            double[] rgBottomData = convert(Bottom.update_cpu_data());
            double[] rgTopData = convert(Top.update_cpu_data());
            int nMaxInd;
            double dfMaxVal;
            int nNum = Bottom.shape(0);
            int nDim = Bottom.count() / nNum;

            for (int i = 0; i < nNum; i++)
            {
                m_log.CHECK_GE(rgTopData[i], 0, "The top value at " + i.ToString() + " should be >= 0.");
                m_log.CHECK_LE(rgTopData[i], nDim, "The top value at " + i.ToString() + " should be <= nDim (" + nDim.ToString() + ")");
                nMaxInd = (int)rgTopData[i];
                dfMaxVal = rgBottomData[i * nDim + nMaxInd];

                for (int j = 0; j < nDim; j++)
                {
                    m_log.CHECK_LE(rgBottomData[i * nDim + j], dfMaxVal, "the values are not as expected.");
                }
            }
        }

        public void TestCpuMaxVal()
        {
            LayerParameter p = new LayerParameter(LayerParameter.LayerType.ARGMAX);
            p.argmax_param.out_max_val = true;
            ArgMaxLayer<T> layer = new ArgMaxLayer<T>(m_cuda, m_log, p);

            layer.Setup(BottomVec, TopVec);
            layer.Forward(BottomVec, TopVec);

            // Now, check values
            double[] rgBottomData = convert(Bottom.update_cpu_data());
            double[] rgTopData = convert(Top.update_cpu_data());
            int nMaxInd;
            double dfMaxVal;
            int nNum = Bottom.shape(0);
            int nDim = Bottom.count() / nNum;

            for (int i = 0; i < nNum; i++)
            {
                m_log.CHECK_GE(rgTopData[i], 0, "The top value at " + i.ToString() + " should be >= 0.");
                m_log.CHECK_LE(rgTopData[i], nDim, "The top value at " + i.ToString() + " should be <= nDim (" + nDim.ToString() + ")");
                nMaxInd = (int)rgTopData[i * 2];
                dfMaxVal = rgTopData[i * 2 + 1];

                m_log.CHECK_EQ(rgBottomData[i * nDim + nMaxInd], dfMaxVal, "the values are not as expected.");

                for (int j = 0; j < nDim; j++)
                {
                    m_log.CHECK_LE(rgBottomData[i * nDim + j], dfMaxVal, "the values are not as expected.");
                }
            }
        }

        public void TestCpuTopK()
        {
            LayerParameter p = new LayerParameter(LayerParameter.LayerType.ARGMAX);
            p.argmax_param.top_k = (uint)m_nTopK;
            ArgMaxLayer<T> layer = new ArgMaxLayer<T>(m_cuda, m_log, p);

            layer.Setup(BottomVec, TopVec);
            layer.Forward(BottomVec, TopVec);

            // Now, check values
            double[] rgBottomData = convert(Bottom.update_cpu_data());
            int nMaxInd;
            double dfMaxVal;
            int nNum = Bottom.shape(0);
            int nDim = Bottom.count() / nNum;

            for (int i = 0; i < nNum; i++)
            {
                double dfTop = convert(Top.data_at(new List<int>() { i, 0, 0, 0 }));
                m_log.CHECK_GE(dfTop, 0, "The top value at " + i.ToString() + " should be >= 0.");
                m_log.CHECK_LE(dfTop, nDim, "The top value at " + i.ToString() + " should be <= nDim (" + nDim.ToString() + ")");

                for (int j = 0; j < m_nTopK; j++)
                {
                    nMaxInd = (int)convert(Top.data_at(new List<int>() { i, 0, j, 0 }));
                    dfMaxVal = rgBottomData[i * nDim + nMaxInd];

                    int nCount = 0;

                    for (int k = 0; k < nDim; k++)
                    {
                        if (rgBottomData[i * nDim + k] > dfMaxVal)
                            nCount++;
                    }

                    m_log.CHECK_EQ(j, nCount, "The values are not as expected.");
                }
            }
        }

        public void TestCpuMaxValTopK()
        {
            LayerParameter p = new LayerParameter(LayerParameter.LayerType.ARGMAX);
            p.argmax_param.out_max_val = true;
            p.argmax_param.top_k = (uint)m_nTopK;
            ArgMaxLayer<T> layer = new ArgMaxLayer<T>(m_cuda, m_log, p);

            layer.Setup(BottomVec, TopVec);
            layer.Forward(BottomVec, TopVec);

            // Now, check values
            double[] rgBottomData = convert(Bottom.update_cpu_data());
            int nMaxInd;
            double dfMaxVal;
            int nNum = Bottom.shape(0);
            int nDim = Bottom.count() / nNum;

            for (int i = 0; i < nNum; i++)
            {
                double dfTop = convert(Top.data_at(new List<int>() { i, 0, 0, 0 }));
                m_log.CHECK_GE(dfTop, 0, "The top value at " + i.ToString() + " should be >= 0.");
                m_log.CHECK_LE(dfTop, nDim, "The top value at " + i.ToString() + " should be <= nDim (" + nDim.ToString() + ")");

                for (int j = 0; j < m_nTopK; j++)
                {
                    nMaxInd = (int)convert(Top.data_at(new List<int>() { i, 0, j, 0 }));
                    dfMaxVal = convert(Top.data_at(new List<int>() { i, 1, j, 0 }));

                    m_log.CHECK_EQ(rgBottomData[i * nDim + nMaxInd], dfMaxVal, "The values are not as expected.");

                    int nCount = 0;

                    for (int k = 0; k < nDim; k++)
                    {
                        if (rgBottomData[i * nDim + k] > dfMaxVal)
                            nCount++;
                    }

                    m_log.CHECK_EQ(j, nCount, "The values are not as expected.");
                }
            }
        }

        public void TestCpuAxis()
        {
            LayerParameter p = new LayerParameter(LayerParameter.LayerType.ARGMAX);
            p.argmax_param.axis = 0;
            ArgMaxLayer<T> layer = new ArgMaxLayer<T>(m_cuda, m_log, p);

            layer.Setup(BottomVec, TopVec);
            layer.Forward(BottomVec, TopVec);

            // Now, check values
            int nMaxInd;
            double dfMaxVal;
            List<int> rgShape = Bottom.shape();

            for (int i = 0; i < rgShape[1]; i++)
            {
                for (int j = 0; j < rgShape[2]; j++)
                {
                    for (int k = 0; k < rgShape[3]; k++)
                    {
                        nMaxInd = (int)convert(Top.data_at(new List<int>() { 0, i, j, k }));
                        dfMaxVal = convert(Bottom.data_at(new List<int>() { nMaxInd, i, j, k }));

                        m_log.CHECK_GE(nMaxInd, 0, "The max index should be >= 0.");
                        m_log.CHECK_LE(nMaxInd, rgShape[0], "The max index should be <= the shape(0).");

                        for (int l = 0; l < rgShape[0]; l++)
                        {
                            double dfVal = convert(Bottom.data_at(new List<int>() { l, i, j, k }));
                            m_log.CHECK_LE(dfVal, dfMaxVal, "The value is not as expected.");
                        }
                    }
                }
            }
        }

        public void TestCpuAxisTopK()
        {
            LayerParameter p = new LayerParameter(LayerParameter.LayerType.ARGMAX);
            p.argmax_param.axis = 2;
            p.argmax_param.top_k = (uint)m_nTopK;
            ArgMaxLayer<T> layer = new ArgMaxLayer<T>(m_cuda, m_log, p);

            layer.Setup(BottomVec, TopVec);
            layer.Forward(BottomVec, TopVec);

            // Now, check values
            int nMaxInd;
            double dfMaxVal;
            List<int> rgShape = Bottom.shape();

            for (int i = 0; i < rgShape[0]; i++)
            {
                for (int j = 0; j < rgShape[1]; j++)
                {
                    for (int k = 0; k < rgShape[3]; k++)
                    {
                        for (int m = 0; m < m_nTopK; m++)
                        {
                            nMaxInd = (int)convert(Top.data_at(new List<int>() { i, j, m, k }));
                            dfMaxVal = convert(Bottom.data_at(new List<int>() { i, j, nMaxInd, k }));

                            m_log.CHECK_GE(nMaxInd, 0, "The max index should be >= 0.");
                            m_log.CHECK_LE(nMaxInd, rgShape[2], "The max index should be <= the shape(2).");

                            int nCount = 0;

                            for (int l = 0; l < rgShape[2]; l++)
                            {
                                double dfVal = convert(Bottom.data_at(new List<int>() { i, j, l, k }));

                                if (dfVal > dfMaxVal)
                                    nCount++;
                            }

                            m_log.CHECK_EQ(m, nCount, "The value is not expected.");
                        }
                    }
                }
            }
        }

        public void TestCpuAxisMaxValTopK()
        {
            LayerParameter p = new LayerParameter(LayerParameter.LayerType.ARGMAX);
            p.argmax_param.top_k = (uint)m_nTopK;
            p.argmax_param.out_max_val = true;
            ArgMaxLayer<T> layer = new ArgMaxLayer<T>(m_cuda, m_log, p);

            layer.Setup(BottomVec, TopVec);
            layer.Forward(BottomVec, TopVec);

            // Now, check values
            double[] rgBottomData = convert(Bottom.mutable_cpu_data);
            int nMaxIdx;
            double dfMaxVal;
            int nNum = Bottom.num;
            int nDim = Bottom.count() / nNum;

            for (int i = 0; i < nNum; i++)
            {
                double dfTop = convert(Top.data_at(i, 0, 0, 0));
                m_log.CHECK_GE(dfTop, 0, "Top at " + i.ToString() + " should be >= 0.");
                m_log.CHECK_LE(dfTop, nDim, "Top at " + i.ToString() + " should be <= " + nDim.ToString()); 

                for (int j = 0; j < m_nTopK; j++)
                {
                    nMaxIdx = (int)convert(Top.data_at(i, 0, j, 0));
                    dfMaxVal = convert(Top.data_at(i, 1, j, 0));

                    double dfBottom = rgBottomData[i * nDim + nMaxIdx];
                    m_log.CHECK_EQ(dfBottom, dfMaxVal, "The max values do not match!");

                    int nCount = 0;

                    for (int k = 0; k < nDim; k++)
                    {
                        dfBottom = rgBottomData[i * nDim + k];

                        if (dfBottom > dfMaxVal)
                            nCount++;
                    }

                    m_log.CHECK_EQ(j, nCount, "The number of items over max should equal " + j.ToString());
                }
            }
        }
    }
}
