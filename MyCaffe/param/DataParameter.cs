﻿using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.ComponentModel;
using MyCaffe.basecode;

namespace MyCaffe.param
{
    /// <summary>
    /// Specifies the parameter for the data layer.
    /// </summary>
    /// <remarks>
    /// Note: given the new use of the Transformation Parameter, the
    /// depreciated elements of the DataParameter have been removed.
    /// </remarks>
    public class DataParameter : LayerParameterBase
    {
        /// <summary>
        /// Defines the database type to use.
        /// </summary>
        public enum DB
        {
            /// <summary>
            /// Specifies to use the CaffeImageDatabase.  Currently this is the only option.
            /// </summary>
            IMAGEDB = 0
        }

        string m_strSource = null;
        uint m_nBatchSize;
        DB m_backend = DB.IMAGEDB;
        uint m_nPrefetch = 4;
        bool? m_bEnableRandomSelection = null;
        bool? m_bEnablePairSelection = null;
        bool m_bDisplayTiming = false;
        bool m_bLoadMultipleLabels = false;

        /// <summary>
        /// This event is, optionally, called to verify the batch size of the DataParameter.
        /// </summary>
        public event EventHandler<VerifyBatchSizeArgs> OnVerifyBatchSize;

        /** @copydoc LayerParameterBase */
        public DataParameter()
        {
        }

        /// <summary>
        /// Specifies the data source.
        /// </summary>
        [Description("Specifies the data 'source' within the database.  Some sources are used for training whereas others are used for testing.  Each dataset has both a training and testing data source.")]
        public string source
        {
            get { return m_strSource; }
            set { m_strSource = value; }
        }

        /// <summary>
        /// Specifies the batch size.
        /// </summary>
        [Description("Specifies the batch size of images to collect and train on each iteration of the network.  NOTE: Setting the training netorks batch size >= to the testing net batch size will conserve memory by allowing the training net to share its gpu memory with the testing net.")]
        public virtual uint batch_size
        {
            get { return m_nBatchSize; }
            set
            {
                if (OnVerifyBatchSize != null)
                {
                    VerifyBatchSizeArgs args = new VerifyBatchSizeArgs(value);
                    OnVerifyBatchSize(this, args);
                    if (args.Error != null)
                        throw args.Error;
                }

                m_nBatchSize = value;
            }
        }

        /// <summary>
        /// Specifies the backend database.
        /// </summary>
        /// <remarks>
        /// NOTE: Currently only the IMAGEDB is supported, which is a separate
        /// component used to load and manage all images within a given dataset.
        /// </remarks>
        [Description("Specifies the backend database type.  Currently only the IMAGEDB database type is supported.  However protofiles specifying the 'LMDB' backend are converted into the 'IMAGEDB' type.")]
        public DB backend
        {
            get { return m_backend; }
            set { m_backend = value; }
        }

        /// <summary>
        /// Prefetch queue (Number of batches to prefetch to host memory, increase if
        /// data access bandwidth varies).
        /// </summary>
        [Description("Specifies the number of batches to prefetch to host memory.  Increase this value if data access bandwidth varies.")]
        public uint prefetch
        {
            get { return m_nPrefetch; }
            set { m_nPrefetch = value; }
        }

        /// <summary>
        /// (\b optional, default = null) Specifies whether or not to randomly query images from the data source.  When enabled, images are queried in sequence which can often have poorer training results.
        /// </summary>
        [Category("Data Selection"), Description("Specifies whether or not to randomly query images from the data source.  When false, images are queried in sequence which can often have poorer training results.")]
        public bool? enable_random_selection
        {
            get { return m_bEnableRandomSelection; }
            set { m_bEnableRandomSelection = value; }
        }

        /// <summary>
        /// (\b optional, default = null) Specifies whether or not to select images in a pair sequence.  When enabled, the first image queried is queried using the 'random' selection property, and then the second image queried is the image just after the first image queried (even if queried randomly).
        /// </summary>
        [Category("Data Selection"), Description("Specifies whether or not to select images in a pair sequence.  When enabled, the first image queried is queried using the 'random' selection property, and then the second image queried is the image just after the first image queried (even if queried randomly).")]
        public bool? enable_pair_selection
        {
            get { return m_bEnablePairSelection; }
            set { m_bEnablePairSelection = value; }
        }

        /// <summary>
        /// (\b optional, default = false) Specifies whether or not to display the timing of each image read.
        /// </summary>
        [Category("Debugging"), Description("Specifies whether or not to display the timing of each image read.")]
        public bool display_timing
        {
            get { return m_bDisplayTiming; }
            set { m_bDisplayTiming = value; }
        }

        /// <summary>
        /// (\b optional, default = false) Specifies whether multiple labels should be loaded or not for each input.  When true, the data criteria is loaded as the multiple label set.  Multiple labels are used in tasks such as segmentation learning.  
        /// </summary>
        [Category("Labels"), Description("Specifies whether multiple labels should be loaded or not for each input.When true, the data criteria is loaded as the multiple label set.Multiple labels are used in tasks such as segmentation learning.")]
        public bool load_multiple_labels
        {
            get { return m_bLoadMultipleLabels; }
            set { m_bLoadMultipleLabels = value; }
        }

        /** @copydoc LayerParameterBase::Load */
        public override object Load(System.IO.BinaryReader br, bool bNewInstance = true)
        {
            RawProto proto = RawProto.Parse(br.ReadString());
            DataParameter p = FromProto(proto);

            if (!bNewInstance)
                Copy(p);

            return p;
        }

        /** @copydoc LayerParameterBase::Copy */
        public override void Copy(LayerParameterBase src)
        {
            DataParameter p = (DataParameter)src;
            m_strSource = p.m_strSource;
            m_nBatchSize = p.m_nBatchSize;
            m_backend = p.m_backend;
            m_nPrefetch = p.m_nPrefetch;
            m_bEnableRandomSelection = p.m_bEnableRandomSelection;
            m_bEnablePairSelection = p.m_bEnablePairSelection;
            m_bDisplayTiming = p.m_bDisplayTiming;
            m_bLoadMultipleLabels = p.m_bLoadMultipleLabels;
        }

        /** @copydoc LayerParameterBase::Clone */
        public override LayerParameterBase Clone()
        {
            DataParameter p = new DataParameter();
            p.Copy(this);
            return p;
        }

        /** @copydoc LayerParameterBase::ToProto */
        public override RawProto ToProto(string strName)
        {
            RawProtoCollection rgChildren = new RawProtoCollection();

            rgChildren.Add("source", "\"" + source + "\"");
            rgChildren.Add("batch_size", batch_size.ToString());
            rgChildren.Add("backend", backend.ToString());

            if (prefetch != 4)
                rgChildren.Add("prefetch", prefetch.ToString());

            rgChildren.Add("enable_random_selection", enable_random_selection.GetValueOrDefault(true).ToString());

            if (enable_pair_selection.GetValueOrDefault(false) == true)
                rgChildren.Add("enable_pair_selection", enable_pair_selection.Value.ToString());

            if (display_timing == true)
                rgChildren.Add("display_timing", display_timing.ToString());

            if (load_multiple_labels == true)
                rgChildren.Add("load_multiple_labels", load_multiple_labels.ToString());

            return new RawProto(strName, "", rgChildren);
        }

        /// <summary>
        /// Parses the parameter from a RawProto.
        /// </summary>
        /// <param name="rp">Specifies the RawProto to parse.</param>
        /// <param name="p">Optionally, specifies an instance to load.  If <i>null</i>, a new instance is created and loaded.</param>
        /// <returns>A new instance of the parameter is returned.</returns>
        public static DataParameter FromProto(RawProto rp, DataParameter p = null)
        {
            string strVal;

            if (p == null)
                p = new DataParameter();

            if ((strVal = rp.FindValue("source")) != null)
                p.source = strVal.Trim('\"');

            if ((strVal = rp.FindValue("batch_size")) != null)
                p.batch_size = uint.Parse(strVal);

            if ((strVal = rp.FindValue("backend")) != null)
            {
                switch (strVal)
                {
                    case "IMAGEDB":
                        p.backend = DB.IMAGEDB;
                        break;

                    case "LMDB":
                        p.backend = DB.IMAGEDB;
                        break;

                    default:
                        throw new Exception("Unknown 'backend' value " + strVal);
                }
            }

            if ((strVal = rp.FindValue("prefetch")) != null)
                p.prefetch = uint.Parse(strVal);

            if ((strVal = rp.FindValue("enable_random_selection")) != null)
                p.enable_random_selection = bool.Parse(strVal);

            if ((strVal = rp.FindValue("enable_pair_selection")) != null)
                p.enable_pair_selection = bool.Parse(strVal);

            if ((strVal = rp.FindValue("display_timing")) != null)
                p.display_timing = bool.Parse(strVal);

            if ((strVal = rp.FindValue("load_multiple_labels")) != null)
                p.load_multiple_labels = bool.Parse(strVal);

            return p;
        }
    }

    /// <summary>
    /// The VerifyBatchSizeArgs class defines the arguments of the OnVerifyBatchSize event.
    /// </summary>
    public class VerifyBatchSizeArgs : EventArgs
    {
        uint m_uiBatchSize;
        Exception m_err = null;

        /// <summary>
        /// VerifyBatchSizeArgs constructor.
        /// </summary>
        /// <param name="uiBatchSize"></param>
        public VerifyBatchSizeArgs(uint uiBatchSize)
        {
            m_uiBatchSize = uiBatchSize;
        }

        /// <summary>
        /// Get/set the error value.  For example if the receiver of the event determines that the batch size is in error, 
        /// then the receiver should set the error appropriately.
        /// </summary>
        public Exception Error
        {
            get { return m_err; }
            set { m_err = value; }
        }

        /// <summary>
        /// Specifies the proposed batch size that the DataLayer would like to use.
        /// </summary>
        public uint ProposedBatchSize
        {
            get { return m_uiBatchSize; }
        }
    }
}
