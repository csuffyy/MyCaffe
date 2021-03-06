﻿using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.ComponentModel;
using MyCaffe.basecode;
using MyCaffe.common;

namespace MyCaffe.param
{
    /// <summary>
    /// This layer produces N >= 1 top blobs.  DummyDataParameter must specify 1 or 
    /// shape fields, and 0, 1 or N data fillers.
    /// This layer is initialized with the ReLUParameter.
    /// </summary>
    [TypeConverter(typeof(ExpandableObjectConverter))]
    public class DummyDataParameter : LayerParameterBase
    {
        List<FillerParameter> m_rgFillers = new List<FillerParameter>();
        List<BlobShape> m_rgShape = new List<BlobShape>();
        List<uint> m_rgNum = new List<uint>();
        List<uint> m_rgChannels = new List<uint>();
        List<uint> m_rgHeight = new List<uint>();
        List<uint> m_rgWidth = new List<uint>();

        /** @copydoc LayerParameterBase */
        public DummyDataParameter()
        {
        }

        /// <summary>
        /// If 0 data fillers are specified, ConstantFiller
        /// </summary>
        [Description("Specifies the data fillers used to fill the data.  If no data fillers are specified, the constant filler is used.")]
        public List<FillerParameter> data_filler
        {
            get { return m_rgFillers; }
            set { m_rgFillers = value; }
        }

        /// <summary>
        /// Specifies the shape of the dummy data where:
        ///   shape(0) = num
        ///   shape(1) = channels
        ///   shape(2) = height
        ///   shape(3) = width
        /// </summary>
        [Description("Specifies the shape of the dummy data where: shape(0) = num; shape(1) = channels; shape(2) = height; shape(3) = width.")]
        public List<BlobShape> shape
        {
            get { return m_rgShape; }
            set { m_rgShape = value; }
        }

        /// <summary>
        /// <b>DEPRECIATED</b> - 4D dimensions, use 'shape' instead.
        /// </summary>
        [Description("DEPRECIATED: use 'shape(0)' instead.")]
        public List<uint> num
        {
            get { return m_rgNum; }
            set { m_rgNum = value; }
        }

        /// <summary>
        /// <b>DEPRECIATED</b> - 4D dimensions, use 'shape' instead.
        /// </summary>
        [Description("DEPRECIATED: use 'shape(1)' instead.")]
        public List<uint> channels
        {
            get { return m_rgChannels; }
            set { m_rgChannels = value; }
        }

        /// <summary>
        /// <b>>DEPRECIATED</b> - 4D dimensions, use 'shape' instead.
        /// </summary>
        [Description("DEPRECIATED: use 'shape(2)' instead.")]
        public List<uint> height
        {
            get { return m_rgHeight; }
            set { m_rgHeight = value; }
        }

        /// <summary>
        /// <b>DEPRECIATED</b> - 4D dimensions, use 'shape' instead.
        /// </summary>
        [Description("DEPRECIATED: use 'shape(3)' instead.")]
        public List<uint> width
        {
            get { return m_rgWidth; }
            set { m_rgWidth = value; }
        }

        /** @copydoc LayerParameterBase::Load */
        public override object Load(System.IO.BinaryReader br, bool bNewInstance = true)
        {
            RawProto proto = RawProto.Parse(br.ReadString());
            DummyDataParameter p = FromProto(proto);

            if (!bNewInstance)
                Copy(p);

            return p;
        }

        /** @copydoc LayerParameterBase::Copy */
        public override void Copy(LayerParameterBase src)
        {
            DummyDataParameter p = (DummyDataParameter)src;
            m_rgFillers = Utility.Clone<FillerParameter>(p.m_rgFillers);
            m_rgShape = Utility.Clone<BlobShape>(p.m_rgShape);
            m_rgNum = Utility.Clone<uint>(p.m_rgNum);
            m_rgChannels = Utility.Clone<uint>(p.m_rgChannels);
            m_rgHeight = Utility.Clone<uint>(p.m_rgHeight);
            m_rgWidth = Utility.Clone<uint>(p.m_rgWidth);
        }

        /** @copydoc LayerParameterBase::Clone */
        public override LayerParameterBase Clone()
        {
            DummyDataParameter p = new DummyDataParameter();
            p.Copy(this);
            return p;
        }

        /** @copydoc LayerParameterBase::ToProto */
        public override RawProto ToProto(string strName)
        {
            RawProtoCollection rgChildren = new RawProtoCollection();

            foreach (FillerParameter fp in data_filler)
            {
                rgChildren.Add(fp.ToProto("data_filler"));
            }

            foreach (BlobShape bs in shape)
            {
                rgChildren.Add(bs.ToProto("shape"));
            }

            rgChildren.Add<uint>("num", num);
            rgChildren.Add<uint>("channels", channels);
            rgChildren.Add<uint>("height", height);
            rgChildren.Add<uint>("width", width);

            return new RawProto(strName, "", rgChildren);
        }

        /// <summary>
        /// Parses the parameter from a RawProto.
        /// </summary>
        /// <param name="rp">Specifies the RawProto to parse.</param>
        /// <returns>A new instance of the parameter is returned.</returns>
        public static DummyDataParameter FromProto(RawProto rp)
        {
            DummyDataParameter p = new DummyDataParameter();
            RawProtoCollection rgp;
            
            rgp = rp.FindChildren("data_filler");
            foreach (RawProto child in rgp)
            {
                p.data_filler.Add(FillerParameter.FromProto(child));
            }

            rgp = rp.FindChildren("shape");
            foreach (RawProto child in rgp)
            {
                p.shape.Add(BlobShape.FromProto(child));
            }

            p.num = rp.FindArray<uint>("num");
            p.channels = rp.FindArray<uint>("channels");
            p.height = rp.FindArray<uint>("height");
            p.width = rp.FindArray<uint>("width");

            return p;
        }
    }
}
