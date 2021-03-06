<H2>Installation Instructions</H2>
To install and run <b>MyCaffe</b> you will need to do the following steps.  As a side note, we are using (and recommend) CUDA 9.0 with cuDNN 7.0.3 and Visual Studio 2017 for all of our testing.
</br>
<H3>I. CUDA - Install NVIDIA CUDA and cuDNN Libraries</H3>
Install either CUDA 9.0 (recommended) -or- CUDA 8.0 (depreciated) as shown below.
<H4>A. CUDA 9.0 - Install NVIDIA CUDA and cuDNN Libraries</H4>
1.) Install the NVIDIA CUDA 9.0 Toolkit for Windows from https://developer.nvidia.com/cuda-downloads. 
</br>2.) Install the NVIDIA cuDNN 7.0 Accelerated Libraries for CUDA 9.0 from https://developer.nvidia.com/cuDNN.
</br>3.) Create a new directory off your <b><i>$(CUDA_PATH_V9_0)</i></b> installation location  named <b><i>cudann_9.0rc-win-v7.0.3</i></b> and copy the cuDNN <b><i>cudnn.h</i></b> and <b><i>cudnn.lib</i></b> files into it.
</br>4.) Copy the <b><i>cudnn64_7.dll</i></b> file into the <b><i>$(CUDA_PATH_V9_0)\bin</i></b> directory.
</br>
<H4>B. CUDA 8.0 - Install NVIDIA CUDA and cuDNN Libraries (depreciated)</H4>
1.) Install the NVIDIA CUDA 8.0 Toolkit for Windows from https://developer.nvidia.com/cuda-downloads. 
</br>2.) Install the NVIDIA cuDNN 6.0 Accelerated Libraries for CUDA 8.0 from https://developer.nvidia.com/cuDNN.
</br>3.) Create a new directory off your <b><i>$(CUDA_PATH_V8_0)</i></b> installation location  named <b><i>cudann_8.0-win-v6.0</i></b> and copy the cuDNN <b><i>cudnn.h</i></b> and <b><i>cudnn.lib</i></b> files into it.
</br>4.) Copy the <b><i>cudnn64_6.dll</i></b> file into the <b><i>$(CUDA_PATH_V8_0)\bin</i></b> directory.
</br>
</br>NOTE: The CudaDnnDLL project points to the file directories noted above for the cuDNN include and library files.  

<H3>II. Setup Strong Names and Signing</H3>
The <b><i>MyCaffe</i></b> project, uses the following strong name key files:
</br>The <b>CudaControl</b> uses the <b><i>CudaControl.pfx</i></b> located in the <b><i>packages\CudaControl.1.0.0.372\lib\Net40\</i></b> directory.  
If you download, build the <b>CudaControl</b> repository and create a new <b><i>CudaControl.pfx</i></b> file, you should also copy it into the 
<b><i>packages\CudaControl.1.0.0.372\lib\Net40\</i></b> directory, replacing the pfx file there.  Alternatively, you can just install 
the <b>CudaControl</b> package from NuGet.
</p>
The <b><i>MyCaffe</i></b> uses the <b><i>mycaffe.sn.pfx</i></b> key file for string name signing.
</br>The <b><i>MyCaffe.basecode</i></b> uses the <b><i>mycaffe.basecode.sn.pfx</i></b> key file for string name signing.
</br>The <b><i>MyCaffe.imagedb</i></b> uses the <b><i>mycaffe.imagedb.sn.pfx</i></b> key file for string name signing.
</p>
You may want to provide your own strong names for each of the other <b>MyCaffe</b> projects.  To do this just select the project <i>Properties | Signing</i> tab and
then <i>Sign the assembly</i> with a strong name keyfile.  You can also use this method to create the <b><i>CudaControl.pfx</i></b> file mentioned above.
</br>If you change these, please do not check them in.  NOTE: The current .gitignore file ignores pfx files.

<H3>III. Restore NuGet Packages Used</H3>
The <b>MyCaffe</b> projects use several NuGet Packages. You will need to restore these packages before building.  To restore the NuGet Packages, 
right click the <b><i>MyCaffe</i></b> solution and select the '<i>Restore NuGet Packages</i>' menu item.
</br>
</br>The <b><i>MyCaffe</i></b> project uses the following NuGet Packages:
</br>a.) <b>Google.Protobuf</b> by Google Inc., version 3.3.0
</br>b.) <b>CudaControl</b> by SignalPop, version 0.9.0.372 (available on NuGet, or build from CudaControl repository.)  NOTE: when using the CudaControl repository,
you must register the CudaControl.dll (run '<b><i>regsvr32 CudaControl.dll</i></b>' from a CMD window run with Administrative privileges).
</br>
</br>The <b><i>MyCaffe.app</i></b> project uses the following NuGet Packages:
  </br>a.) <b>EntityFramework</b> by Microsoft, version 6.1.3
</br>
</br>The <b><i>MyCaffe.imagedb</i></b> project uses the following NuGet Packages:
  </br>a.) <b>EntityFramework</b> by Microsoft, version 6.1.3
  </br>b.) <b>Microsoft.SqlServer.Types</b> by Microsoft, version 14.0.314.76
</br>
</br>The <b><i>MyCaffe.test</i></b> project uses the following NuGet Packages:
  </br>a.) <b>EntityFramework</b> by Microsoft, version 6.1.3  
  </br>b.) <b>HDF5DotNet.x64</b> by The HDF Group, version 1.8.9
<H3>IV. Required Software</H3>
<b>MyCaffe</b> requires the following software.
</br>
</br>a.) Microsoft Visual Studio 2017 or Visual Studio 2015
</br>b.) Microsoft SQL or Microsoft SQL Express
</br>Both 'a' and 'b' are available from Microsoft at www.microsoft.com.
</br>
</br>c.) nccl64_134.dll - If you plan on running multi-GPU training sessions, you will need the <b><i>nccl64_134.dll</i></b>, which must be placed
in a directory that is visible by your executable files.  This library can be built from the MyCaffe\NCCL repository.  Alternatively, it is installed
by the <b>CudaControl</b> NuGet package and placed in the <i>packages\CudaControl.1.0.0.271\lib\Net40</i> directory.  You should copy the library into
a directory that is visible by your executable files.  NOTE: The automated multi-GPU tests use GPU's 1-4 where the monitor is plugged into GPU 0.
</br>
<H3>V. Create The Database</H3>
<b>MyCaffe</b> uses Microsoft SQL (or Microsoft SQL Express) as its underlying database.  You will need to create the database with the following steps:
</br>1.) Run the <b>MyCaffe.app.exe</b> test application and select the '<i>Database | Create Database</i>' menu item.
</br>2.) From the <i>Create Database</i> dialog, selecd the location where you want to create the database and select the <i>OK</i> button.
</br>3.) Next, load the <b>MNIST</b> data by selecting the '<i>Database | Load MNIST...'</i> menu item and follow the steps to get the data files.
</br>4.) Next, load the <b>CIFAR-10</b> data by selecting the '<i>Database | Load CIFAR-10...'</i> menu item and follow the steps to get the data files.
</br>NOTE: The automated tests expect that both the MNIST and CIFAR-10 datasets have already been loaded into the database.
<H2>Test Installation Instructions</H2>
To install data used by the Automated Tests, you will need to install the following files:
</br>
</br>See <a href=".\MyCaffe.test\test_data\models\bvlc_nin\INSTALL.md">Installing BVLC NIN Model</a>
</br>See <a href=".\MyCaffe.test\test_data\models\voc_fcns32\INSTALL.md">Installing BLVC_FCN Model</a>
</br>
</br>Both of these models are used by the <b><i>TestPersistCaffe.cs</i></b> auto tests.

