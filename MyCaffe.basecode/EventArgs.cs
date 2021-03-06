﻿using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

/// <summary>
/// The MyCaffe.basecode contains all generic types used throughout MyCaffe.
/// </summary>

namespace MyCaffe.basecode
{
    /// <summary>
    /// The LogProgressArg is passed as an argument to the Log::OnProgress event.
    /// </summary>
    public class LogProgressArg : EventArgs
    {
        string m_strSrc;
        double m_dfProgress = 0;

        /// <summary>
        /// The LogProgressArg constructor.
        /// </summary>
        /// <param name="strSrc">Specifies the Log source name.</param>
        /// <param name="dfProgress">Specifies the progress value.</param>
        public LogProgressArg(string strSrc, double dfProgress)
        {
            m_strSrc = strSrc;
            m_dfProgress = dfProgress;
        }

        /// <summary>
        /// Returns the Log source name.
        /// </summary>
        public string Source
        {
            get { return m_strSrc; }
        }

        /// <summary>
        /// Returns the progress value.
        /// </summary>
        public double Progress
        {
            get { return m_dfProgress; }
        }
    }

    /// <summary>
    /// The LogArg is passed as an argument to the Log::OnWriteLine event.
    /// </summary>
    public class LogArg : LogProgressArg
    {
        string m_strMsg;
        object m_tag = null;
        bool m_bError;

        /// <summary>
        /// The LogArg constructor.
        /// </summary>
        /// <param name="strSrc">Specifies the Log source name.</param>
        /// <param name="strMsg">Specifies the message written when calling the Log::WriteLine function (which triggers the event).</param>
        /// <param name="dfProgress">Specifies the progress value specifies when setting the Log::Progress value.</param>
        /// <param name="bError">Specifies whether or not the message is the result of a call from Log::WriteError.</param>
        public LogArg(string strSrc, string strMsg, double dfProgress = 0.0, bool bError = false)
            : base(strSrc, dfProgress)
        {
            m_strMsg = strMsg;
            m_bError = bError;
        }

        /// <summary>
        /// Returns the message logged.
        /// </summary>
        public string Message
        {
            get { return m_strMsg; }
        }

        /// <summary>
        /// Returns whether or not this is an error message.
        /// </summary>
        public bool Error
        {
            get { return m_bError; }
        }

        public object Tag /** @private */
        {
            get { return m_tag; }
            set { m_tag = value; }
        }
    }

    /// <summary>
    /// The CalculateImageMeanArgs is passed as an argument to the CaffeImageDatabase::OnCalculateImageMean event.
    /// </summary>
    public class CalculateImageMeanArgs : EventArgs
    {
        SimpleDatum[] m_rgImg;
        SimpleDatum m_mean;
        bool m_bCancelled = false;

        /// <summary>
        /// The CalculateImageMeanArgs constructor.
        /// </summary>
        /// <param name="rgImg">Specifies the list of images from which the mean should be calculated.</param>
        public CalculateImageMeanArgs(SimpleDatum[] rgImg)
        {
            m_rgImg = rgImg;
        }

        /// <summary>
        /// Specifies the list of images from which the mean should be calculated.
        /// </summary>
        public SimpleDatum[] Images
        {
            get { return m_rgImg; }
        }

        /// <summary>
        /// Get/set the image mean calculated from the <i>Images</i>.
        /// </summary>
        public SimpleDatum ImageMean
        {
            get { return m_mean; }
            set { m_mean = value; }
        }

        /// <summary>
        /// Get/set a flag indicating to cancel the operation.
        /// </summary>
        public bool Cancelled
        {
            get { return m_bCancelled; }
            set { m_bCancelled = value; }
        }
    }

    /// <summary>
    /// The OverrideProjectArgs is passed as an argument to the OnOverrideModel and OnOverrideSolver events fired by the ProjectEx class.
    /// </summary>
    public class OverrideProjectArgs : EventArgs
    {
        RawProto m_proto;

        /// <summary>
        /// The OverrideProjectArgs constructor.
        /// </summary>
        /// <param name="proto">Specifies the RawProtot.</param>
        public OverrideProjectArgs(RawProto proto)
        {
            m_proto = proto;
        }

        /// <summary>
        /// Get/set the RawProto used.
        /// </summary>
        public RawProto Proto
        {
            get { return m_proto; }
            set { m_proto = value; }
        }
    }
}
