#!/bin/bash
# This script is used to:
# 1. build libVsiSupportLibrary.so and libtim-vx.so
# 2. update libVsiSupportLibrary.so and libtim-vx.so to vendor/nxp/fsl-proprietary/gpu-viv and generate commit message automatically
# Pre-condition:
# Need source/lunch under android source code root directory firstly.
# Need install cmake and android-ndk.
# Need setup a branch to track remote branch and local branch name must be same as remote one.
# export ndk_root=<ndk_root_dir>
# export timxvx_version=<timvx git version>
# export timvx_remote=<timvx git remote>

sl_dir=`pwd`
build_dir=${sl_dir}/nnsl_out

function check_android_top()
{
    if [ -z $OUT ] && [ -z $ANDROID_BUILD_TOP ];then
        echo "ENV is not ready! Please go to android source code root directory:"
        echo "source build/envsetup.sh"
        echo "lunch"
        exit 1
    fi
}

function check_android_ndk()
{
    if [ -z $ndk_root ];then
        echo "Please export ndk_root=<ndk_root_dir> firstly!"
        echo "Note: This script is verified with android-ndk-r26b."
        echo "Visit https://developer.android.com/ndk/downloads to download ndk toolchain."
        exit 1
    fi
    cmake_file=${ndk_root}/build/cmake/android.toolchain.cmake
}

function clean_build_dir()
{
    rm -rf $build_dir
    mkdir -p $build_dir
}

function check_abi()
{
    if [ "$abi" == "32" ];then
        sl_abi=" -DANDROID_ABI=armeabi-v7a"
        lib_abi=lib
    elif [ "$abi" == "64" ];then
        sl_abi=" -DANDROID_ABI=arm64-v8a"
        lib_abi=lib64
    else
        echo "abi only support 32/64"
        exit 1
    fi

    prebuild_sdk=$ANDROID_BUILD_TOP/vendor/nxp/fsl-proprietary
    prebuild_lib=$prebuild_sdk/gpu-viv/$lib_abi/
    prebuild_timvx=$build_dir/tim-vx-install/$lib_abi/lib/libtim-vx.so
    prebuild_supportlib=$build_dir/support-lib-install/$lib_abi/libVsiSupportLibrary.so
}

function prepare_env()
{
    check_android_top
    check_android_ndk
    clean_build_dir
}

function make_sl_timvx()
{
    check_abi
    echo "@@Make binary for lib$abi"
    sl_cmd="cmake -B $build_dir -S $sl_dir -DCMAKE_TOOLCHAIN_FILE=$cmake_file \
    -DANDROID_PLATFORM=android-34 \
	-DCMAKE_CXX_FLAGS=-DNDEBUG \
	-DEXT_VIV_SDK=${prebuild_sdk}\
    -DTIM_VX_TAG=${timxvx_version}\
    -DEXT_TIM_VX=${timvx_remote}\
	$sl_abi"

    echo $sl_cmd
    eval $sl_cmd
    cd $build_dir
    make tim-vx VsiSupportLibrary
}

function build_sl_timvx()
{
    prepare_env

    if [ -z $timxvx_version ];then
        timxvx_version="lf-6.6.23_2.0.0"
    fi
    if [ -z $timvx_remote ];then
        timvx_remote="https://github.com/nxp-imx/tim-vx-imx.git"
    fi

    if [ -z $abi ];then
        for abi in 32 64; do
            make_sl_timvx
        done
    else
        make_sl_timvx
    fi
}

# Auto generate a commit which contains current branch and commit info.
# Commit message format is as below:
# This update libVsiSupportLibrary/libtim-vx binary based on:
#
# ssh://bitbucket.sw.nxp.com/aitec/nn-sl-imx
# Source branch: <git branch>
# Source commit: <git commit HEAD>
# <git short commit message>

# ssh://bitbucket.sw.nxp.com/aitec/tim-vx-imx
# Source branch: <git branch>
# Source commit: <git commit HEAD>
# <git short commit message>

function gen_git_commit_message()
{
    commit_id=`git rev-parse HEAD`
    commit_branch=`git rev-parse --abbrev-ref HEAD`
    temp_message_file=${GIT_NAME}_message

    git_remote_url=$(git remote -v |grep fetch| awk '{print $2}')
    git_short_log=$(git log --pretty=oneline --abbrev-commit -1)

    echo -e  "$git_remote_url\nSource branch: ${commit_branch}\nSource commit: ${commit_id}\n$git_short_log\n"  >$temp_message_file

    cat $temp_message_file >> $temp_file
    rm -rf $temp_message_file
}

function auto_commit()
{
    temp_file=$sl_dir/temp_message
    echo -e "Update libVsiSupportLibrary/libtim-vx binary\n" >$temp_file
    echo -e "This update libVsiSupportLibrary/libtim-vx binary based on:\n" >>$temp_file

    cd $sl_dir
    gen_git_commit_message
    if [ -d $build_dir/deps/tim-vx ];then
        cd $build_dir/deps/tim-vx
        gen_git_commit_message
    fi

    cd $prebuild_sdk
    git add *
    git commit -s -F ${temp_file}

    rm -rf ${temp_file}
}

function cp_sl_timvx()
{
    check_abi
    echo "@@Update binary for lib$abi"
    if [ -f $prebuild_timvx ];then
        cp $prebuild_timvx       $prebuild_lib
    fi
    if [ -f $prebuild_supportlib ];then
        cp $prebuild_supportlib  $prebuild_lib
    fi
}

function update_sl_timvx()
{
    if [ -z $abi ];then
        for abi in 32 64; do
            cp_sl_timvx
        done
    else
        cp_sl_timvx
    fi
    auto_commit
}

function help() {
bn=`basename $0`

cat << EOF

Usage: $bn <option>
options:
  -h                displays this help message
  -abi              abi can be 32/64.
  -build            build libVsiSupportLibrary.so and libtim-vx.so
  -update           update libVsiSupportLibrary.so and libtim-vx.so to vendor/nxp/fsl-proprietary/gpu-viv
                    and generate commit message automatically

Below is an example:
export ndk_root=<ndk_root_dir>
export timxvx_version="lf-6.6.23_2.0.0"
export timvx_remote="https://github.com/nxp-imx/tim-vx-imx.git"


# build and update 64 bit libVsiSupportLibrary.so and libtim-vx.so
$bn -abi 64 -build
$bn -abi 64 -update
# build and update 32+64 bit libVsiSupportLibrary.so and libtim-vx.so
$bn -build
$bn -update
EOF
}

if [ $# -eq 0 ]; then
    echo "no parameter specified, will directly exit after displaying help message"
    help; exit 1;
fi

while [ $# -gt 0 ]; do
    case $1 in
        -h)         help; exit ;;
        -abi)       abi=$2;shift;;
        -build)     build_sl_timvx;;
        -update)    update_sl_timvx;;
        *)  echo "$1 is not an illegal option"
            help; exit;;
    esac
    shift
done
