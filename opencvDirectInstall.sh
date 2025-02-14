#!/bin/bash

echo "This is intended to be a universal OpenCV installation script, which supports installing on Anaconda Python too"
echo "Additionally, FFmpeg will be compiled from source and OpenCV will be linked to this ffmpeg. Press Enter to Continue"
if [[ ! -n $CIINSTALL ]]; then
    read -r temp
fi

spatialPrint() {
    echo ""
    echo ""
    echo "$1"
	echo "================================"
}

execute () {
	echo "$ $*"
	OUTPUT=$($@ 2>&1)
	if [ $? -ne 0 ]; then
        echo "$OUTPUT"
        echo ""
        echo "Failed to Execute $*" >&2
        exit 1
    fi
}

if [[ -n $(echo $SHELL | grep "zsh") ]] ; then
    SHELLRC=~/.zshrc
elif [[ -n $(echo $SHELL | grep "bash") ]] ; then
    SHELLRC=~/.bashrc
elif [[ -n $(echo $SHELL | grep "ksh") ]] ; then
    SHELLRC=~/.kshrc
else
    echo "Unidentified shell $SHELL"
    exit # Ain't nothing I can do to help you buddy :P
fi

# Speed up the process
# Env Var NUMJOBS overrides automatic detection
if [[ -n $NUMJOBS ]]; then
    MJOBS=$NUMJOBS
elif [[ -f /proc/cpuinfo ]]; then
    MJOBS=$(grep -c processor /proc/cpuinfo)
elif [[ "$OSTYPE" == "darwin"* ]]; then
	MJOBS=$(sysctl -n machdep.cpu.thread_count)
else
    MJOBS=4
fi


execute sudo apt-get update
execute sudo apt-get install build-essential curl g++ cmake cmake-curses-gui git pkg-config checkinstall -y
execute sudo apt-get install libopenblas-dev liblapack-dev libatlas-base-dev gfortran -y

spatialPrint "Image manipulation libraries"
execute sudo apt-get install libpng-dev libjpeg-dev libtiff5-dev zlib1g-dev libwebp-dev libopenexr-dev libgdal-dev -y

if [[ $(which python) = *"conda"* || (-n $CIINSTALL) ]] ; then
    PIP="pip install"   # Even though we've forced usage of bash, if conda exists, it will derive it since the parent shell is zsh/ksh/....with conda in the path
else
    execute sudo apt-get install python3 python3-dev python python-dev -y
    execute sudo apt-get install python3-tk python-tk -y
    if [[ ! -n $CIINSTALL ]]; then sudo apt-get install python3-pip python-pip -y; fi
    PIP="sudo pip3 install"
fi
execute $PIP --upgrade numpy pip
execute $PIP --upgrade setuptools
spatialPrint "Also installing skimage, dlib and moviepy as CV libraries"
$PIP cython msgpack moviepy scikit-image
$PIP dlib

if [[ ! -n $(cat $SHELLRC | grep '# ffmpeg-build-script') ]]; then
    spatialPrint "Building FFmpeg now"
    execute sudo apt-get -qq remove x264 libx264-dev ffmpeg -y
    execute sudo apt-get --purge remove libav-tools -y
    execute sudo apt-get install libasound2-dev -y
    execute sudo mkdir -p /opt/ffmpeg-build-script 
    execute sudo chmod ugo+w /opt/ffmpeg-build-script
    (
        cd /opt/ffmpeg-build-script
        git clone --quiet https://github.com/markus-perl/ffmpeg-build-script.git .
        # Build libraries with --enable-shared so that they can be used by OpenCV
        sed -i 's/--disable-shared/--enable-shared/g' build-ffmpeg
        sed -i 's/--enable-shared\ \\/--enable-shared\ --cc="gcc -fPIC"\ \\/g' build-ffmpeg
        # Build libaom as a shared library
        sed -i 's/execute cmake -DENABLE_TESTS=0 -DCMAKE_INSTALL_PREFIX:PATH=${WORKSPACE} $PACKAGES\/av1/execute cmake -DENABLE_TESTS=0 -DBUILD_SHARED_LIBS=1 -DCMAKE_INSTALL_PREFIX:PATH=${WORKSPACE} $PACKAGES\/av1/g' build-ffmpeg
        # Build libx265 as a shared library
        sed -i 's/execute cmake -DCMAKE_INSTALL_PREFIX:PATH=${WORKSPACE} -DENABLE_SHARED:bool=off ./execute cmake -DCMAKE_INSTALL_PREFIX:PATH=${WORKSPACE} -DENABLE_SHARED:bool=on ./g' build-ffmpeg
        # Build vidstab as a shared library. Although by default vidstab is built as a shared library, this is just additional precaution
        sed -i 's/execute cmake -DCMAKE_INSTALL_PREFIX:PATH=${WORKSPACE} ./execute cmake -DCMAKE_INSTALL_PREFIX:PATH=${WORKSPACE} -DBUILD_SHARED_LIBS=1 ./g' build-ffmpeg
        
        AUTOINSTALL=yes ./build-ffmpeg --build
        echo "Adding ffmpeg's libraries to LD_LIBRARY_PATH"
        {
            echo ""
            echo "# ffmpeg-build-script"
            echo "export LD_LIBRARY_PATH=$(pwd)/workspace/lib:\$LD_LIBRARY_PATH"
            echo "export PKG_CONFIG_PATH=$(pwd)/workspace/lib/pkgconfig:\$(pkg-config --variable pc_path pkg-config)"
            echo "export PKG_CONFIG_LIBDIR=$(pwd)/workspace/lib/:\$PKG_CONFIG_LIBDIR"

        } >> $SHELLRC
    )
    source $SHELLRC
fi

spatialPrint "GUI and openGL extensions"
execute sudo apt-get install qt5-default libqt5opengl5-dev libx11-dev libgtk-3-dev libgtkglext1-dev -y
execute sudo apt-get install libvtk6-dev libvtk6-qt-dev -y

spatialPrint "Video manipulation libraries"
execute sudo apt-get install libxine2-dev  -y

spatialPrint "Codecs"
# execute sudo apt-get install libswscale-dev libavformat-dev libavutil-dev libavcodec-dev -y
execute sudo apt-get install libfaac-dev libmp3lame-dev -y
execute sudo apt-get install libopencore-amrnb-dev libopencore-amrwb-dev -y
execute sudo apt-get install yasm libtheora-dev libvorbis-dev libxvidcore-dev -y
execute sudo apt-get install libv4l-dev v4l-utils libdc1394-22-dev libdc1394-utils libgphoto2-dev -y  # Uncommend if you want to enable other backends

spatialPrint "Java"
execute sudo apt-get install -y ant default-jdk

spatialPrint "Parallelism libraries"
execute sudo apt-get install libeigen3-dev libtbb-dev -y

spatialPrint "Optional Dependencies"
execute sudo apt-get install libprotobuf-dev protobuf-compiler -y
execute sudo apt-get install libgoogle-glog-dev libgflags-dev -y
execute sudo apt-get install libhdf5-dev -y
# execute sudo apt-get install doxygen sphinx-common texlive-latex-extra -y
execute sudo apt-get install libfreetype6-dev libharfbuzz-dev -y

spatialPrint "Finally download and install opencv"
git config --global http.postBuffer 1048576000
if [[ ! -d "opencv" ]]; then
	git clone https://github.com/Itseez/opencv
else
# Putting the git pull commands in paranthesis runs it in a subshell and avoids having to do cd ..
    (
        cd opencv || exit
        # Note: Any changes to the opencv directory, if you're a developer developing for opencv, will be lost with the below command
        git checkout master -f
        git pull origin master
    )
fi
if [[ ! -d "opencv_contrib" ]]; then
	git clone https://github.com/Itseez/opencv_contrib
else
    (
        cd opencv_contrib || exit
        git checkout master -f
        git pull origin master
    )
fi

cd opencv
# Check out the latest tag, which has to be the version you check out in contrib too
latest_tag="$(git tag | egrep -v '-' | tail -1)"
echo "Installing OpenCV Version: $latest_tag"
git checkout -f $latest_tag
(
    cd ../opencv_contrib
    git checkout -f $latest_tag
)
# rm -rf build
mkdir -p build
cd build

py2Ex=$(which python2)
py2In=$(python2 -c "from distutils.sysconfig import get_python_inc; print(get_python_inc())")
py2Pack=$(python2 -c "from distutils.sysconfig import get_python_lib; print(get_python_lib())")
py3Ex=$(which python3)
py3In=$(python3 -c "from distutils.sysconfig import get_python_inc; print(get_python_inc())")
py3Pack=$(python3 -c "from distutils.sysconfig import get_python_lib; print(get_python_lib())")

# Anaconda no longer has the malformed MKL library, (if you are using an older Anaconda, use earlier versions of this file)
# However, the font and pangoft libraries still cause problems. Hence, need to rename them
if [[ -n $(echo $PATH | grep 'conda') ]] ; then
    echo "Some of your Conda libraries will be renamed so that QT windows display properly"
    CONDA_PATH=$(echo "$PATH" | tr ':' '\n' | grep "conda[2-9]\?" | head -1 | tr '/' '\n' | head -n -1 | tr '\n' '/')
    (
        cd $CONDA_PATH
        cd lib

        for f in libfontconfig.so*; do
            mv -- "$f" "${f/.so/.so_renamed}"
        done

        for f in libpangoft2-1.0.so*; do
            mv -- "$f" "${f/.so/.so_renamed}"
        done
    )
fi


# Build tiff on as opencv supports tiff4, which is older version, which ubuntu has dropped

cmake -D CMAKE_BUILD_TYPE=RELEASE \
 -D CMAKE_INSTALL_PREFIX=/usr/local \
 -D OPENCV_EXTRA_MODULES_PATH=../../opencv_contrib/modules \
 -D PYTHON2_EXECUTABLE="$py2Ex" \
 -D PYTHON2_INCLUDE_DIR="$py2In" \
 -D PYTHON2_PACKAGES_PATH="$py2Pack" \
 -D PYTHON3_EXECUTABLE="$py3Ex" \
 -D PYTHON3_INCLUDE_DIR="$py3In" \
 -D PYTHON3_PACKAGES_PATH="$py3Pack" \
 -D PYTHON_DEFAULT_EXECUTABLE="$py3Ex" \
 -D WITH_FFMPEG=1 \
 -D WITH_V4L=1 \
 -D WITH_LIBV4L=1 \
 -D WITH_TBB=1 \
 -D WITH_IPP=1 \
 -D ENABLE_FAST_MATH=1 \
 -D BUILD_EXAMPLES=0 \
 -D BUILD_DOCS=0 \
 -D BUILD_PERF_TESTS=0 \
 -D BUILD_TESTS=0 \
 -D WITH_QT=1 \
 -D WITH_OPENGL=1 \
 -D ENABLE_CXX11=1 \
 -D WITH_NVCUVID=0 \
 -D BUILD_TIFF=ON \
 -D WITH_CUDA=0 \
 -D WITH_CUBLAS=0 \
 -D WITH_CUFFT=0 \
 -D CUDA_FAST_MATH=0 ..
#  -D BUILD_opencv_java=0 \
#  -D WITH_VTK=0 \
#  -D BUILD_opencv_freetype=ON \

# De-comment the next line if you would like an interactive cmake menu to check if everything is alright and make some tweaks
# ccmake ..

spatialPrint "Making and installing"
make -j $MJOBS
sudo checkinstall -y

spatialPrint "Finishing off installation"
sudo sh -c 'echo "/usr/local/lib" > /etc/ld.so.conf.d/opencv.conf'
sudo ldconfig

echo "The installation just completed. If it shows an error in the end, kindly post an issue on the git repo"
