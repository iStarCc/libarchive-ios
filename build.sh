#!/bin/bash

# 显示帮助信息
show_help() {
    echo "使用方法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help        显示此帮助信息"
    echo "  -c, --clean       清理所有下载的文件和构建目录"
    echo "  -k, --keep-temp   保留临时文件和构建目录"
    echo "  -v, --verbose     显示详细输出"
    echo ""
    echo "此脚本用于为iOS构建libarchive及其依赖库的XCFramework。"
    echo "它会根据config.env中的配置下载指定版本的lz4、xz、bzip2、libiconv和libarchive，"
    echo "并为x86_64和arm64架构的iOS模拟器以及arm64架构的iOS设备构建静态库。"
    exit 0
}

# 处理命令行参数
CLEAN=0
KEEP_TEMP=0
VERBOSE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        -c|--clean)
            CLEAN=1
            shift
            ;;
        -k|--keep-temp)
            KEEP_TEMP=1
            shift
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        *)
            echo "未知选项: $1"
            echo "使用 '$0 --help' 查看可用选项。"
            exit 1
            ;;
    esac
done

# 创建下载目录
DOWNLOAD_DIR="$(pwd)/downloads"
mkdir -p "$DOWNLOAD_DIR"

# 创建缓存目录
CACHE_DIR="$(pwd)/cache"
mkdir -p "$CACHE_DIR"

# 如果指定了清理选项，则清理所有文件并退出
if [ $CLEAN -eq 1 ]; then
    echo "清理所有下载的文件和构建目录..."
    rm -rf build "$CACHE_DIR"
    echo "是否清理下载目录? (y/n) "
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        rm -rf "$DOWNLOAD_DIR"
        echo "下载目录已清理。"
    fi
    echo "清理完成。"
    exit 0
fi

# 设置日志级别
if [ $VERBOSE -eq 1 ]; then
    set -x  # 启用详细输出
fi

# 检查网络连接
check_network() {
    echo "检查网络连接..."
    if ! curl -s --head https://www.google.com > /dev/null; then
        echo "警告: 无法连接到互联网。将尝试使用已下载的文件继续构建。"
        echo "如果需要下载新文件，请确保网络连接正常。"
    else
        echo "网络连接正常。"
    fi
}

# 检查磁盘空间
check_disk_space() {
    echo "检查可用磁盘空间..."
    local required_space=1000000  # 需要约1GB空间
    local available_space
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        available_space=$(df -k . | awk 'NR==2 {print $4}')
    else
        # Linux
        available_space=$(df -k . | awk 'NR==2 {print $4}')
    fi
    
    if [ "$available_space" -lt "$required_space" ]; then
        echo "错误: 磁盘空间不足。需要至少1GB可用空间，但只有$(($available_space/1024))MB。"
        exit 1
    else
        echo "磁盘空间充足: $(($available_space/1024))MB可用。"
    fi
}

# 检查必要的工具是否已安装
check_required_tools() {
    echo "检查必要的工具..."
    local missing_tools=()
    
    # 检查基本工具
    for tool in curl grep sed tar make xcodebuild lipo autoreconf; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=($tool)
        fi
    done
    
    # 检查Xcode工具
    if ! xcode-select -p &> /dev/null; then
        echo "错误: 未找到Xcode命令行工具。请运行 'xcode-select --install' 安装。"
        exit 1
    fi
    
    # 检查编译器
    if ! xcrun --find clang &> /dev/null; then
        echo "错误: 未找到clang编译器。请确保Xcode和命令行工具已正确安装。"
        exit 1
    fi
    
    # 如果有缺失的工具，显示错误信息并退出
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo "错误: 以下必要工具未安装:"
        for tool in "${missing_tools[@]}"; do
            echo "  - $tool"
        done
        echo "请安装这些工具后再运行此脚本。"
        exit 1
    fi
    
    echo "所有必要工具已安装。"
}

# 执行环境检查
check_network
check_disk_space
check_required_tools

echo "开始构建过程..."

# 创建默认配置文件（如果不存在）
CONFIG_FILE="config.env"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "创建默认配置文件: $CONFIG_FILE"
    cat > "$CONFIG_FILE" << EOF
# 库版本配置
LZ4_VERSION="1.10.0"
XZ_VERSION="5.6.4"
LIBARCHIVE_VERSION="3.7.7"
BZIP2_VERSION="1.0.8"
LIBICONV_VERSION="1.17"

# 最低iOS版本
MIN_IOS="15.0"
EOF
fi

# 加载配置文件
echo "加载配置文件: $CONFIG_FILE"
source "$CONFIG_FILE"

# 设置文件名
LZ4_FILE="lz4-${LZ4_VERSION}.tar.gz"
XZ_FILE="xz-${XZ_VERSION}.tar.gz"
LIBARCHIVE_FILE="libarchive-${LIBARCHIVE_VERSION}.tar.gz"
BZIP2_FILE="bzip2-${BZIP2_VERSION}.tar.gz"
LIBICONV_FILE="libiconv-${LIBICONV_VERSION}.tar.gz"

# 设置下载URL
LZ4_URL="https://github.com/lz4/lz4/archive/v${LZ4_VERSION}.tar.gz"
XZ_URL="https://tukaani.org/xz/xz-${XZ_VERSION}.tar.gz"
LIBARCHIVE_URL="https://www.libarchive.org/downloads/libarchive-${LIBARCHIVE_VERSION}.tar.gz"
BZIP2_URL="https://sourceware.org/pub/bzip2/bzip2-${BZIP2_VERSION}.tar.gz"
LIBICONV_URL="https://ftp.gnu.org/pub/gnu/libiconv/libiconv-${LIBICONV_VERSION}.tar.gz"

echo "使用版本:"
echo "LZ4: ${LZ4_VERSION}"
echo "XZ: ${XZ_VERSION}"
echo "LIBARCHIVE: ${LIBARCHIVE_VERSION}"
echo "BZIP2: ${BZIP2_VERSION}"
echo "LIBICONV: ${LIBICONV_VERSION}"
echo "最低iOS版本: ${MIN_IOS}"

# 定义辅助函数
check_success()
{
    if [ $? -eq 0 ]; then
    echo "Succeeded"
    else
    echo "Failed"
    exit 1
    fi
}

remove_tar_gz_suffix() {
  local filename="$1"
  echo "${filename%.tar.gz}"
}

# Compiler settings for x86_64 simulator
CC_X86_64_SIM="$(xcrun --sdk iphonesimulator --find clang) -isysroot $(xcrun --sdk iphonesimulator --show-sdk-path) -arch x86_64 -mios-simulator-version-min=${MIN_IOS}"

# Compiler settings for arm64 simulator
CC_ARM64_SIM="$(xcrun --sdk iphonesimulator --find clang) -isysroot $(xcrun --sdk iphonesimulator --show-sdk-path) -arch arm64 -mios-simulator-version-min=${MIN_IOS}"

# Compiler settings for arm64 device
CC_ARM64_IOS="$(xcrun --sdk iphoneos --find clang) -isysroot $(xcrun --sdk iphoneos --show-sdk-path) -arch arm64 -miphoneos-version-min=${MIN_IOS}"

# 设置输出路径
BUILD_DIR="$(pwd)/build"
LIB_PATH="${BUILD_DIR}/libs"
INCLUDE_PATH="${BUILD_DIR}/include"
XCFRAMEWORK_PATH="${BUILD_DIR}/xcframeworks"

cd "$(dirname "$0")"
rm -rf "${BUILD_DIR}"
mkdir -p "${LIB_PATH}"
mkdir -p "${INCLUDE_PATH}"
mkdir -p "${XCFRAMEWORK_PATH}"

# 下载必要的源码包
download_if_needed() {
    local file=$1
    local url=$2
    local download_path="$DOWNLOAD_DIR/$file"
    
    if [ ! -f "$download_path" ]; then
        echo "下载 ${file}..."
        curl -L -o "$download_path" "$url"
        check_success
    else
        echo "使用已下载的 ${file}"
    fi
    
    # 复制到缓存目录以便后续处理
    cp "$download_path" "$CACHE_DIR/"
}

download_if_needed "${LZ4_FILE}" "${LZ4_URL}"
download_if_needed "${XZ_FILE}" "${XZ_URL}"
download_if_needed "${LIBARCHIVE_FILE}" "${LIBARCHIVE_URL}"
download_if_needed "${BZIP2_FILE}" "${BZIP2_URL}"
download_if_needed "${LIBICONV_FILE}" "${LIBICONV_URL}"

create_xcframework()
{

    echo "Creating FAT binary for simulator"
    lipo -create "${LIB_PATH}/x86_64_sim_$1.a" "${LIB_PATH}/arm64_sim_$1.a" -o "${LIB_PATH}/sim_fat_$1.a"
    check_success

    echo "Creating XCFramework for $1"
    xcodebuild -create-xcframework \
    -library "${LIB_PATH}/sim_fat_$1.a" -headers "${INCLUDE_PATH}/${LIB}" \
    -library "${LIB_PATH}/arm64_ios_$1.a" -headers "${INCLUDE_PATH}/${LIB}" \
    -output "${XCFRAMEWORK_PATH}/$1.xcframework"
    check_success
    
    echo "Cleaning up individual architecture binaries"
    rm -f "${LIB_PATH}/sim_fat_$1.a" "${LIB_PATH}/arm64_$1.a"
}

compile_library()
{
    ARCH=$1
    CC=$2
    LIB_NAME=$3
    HOST=$4
    
    # 使用缓存目录进行编译
    OUTPUT_PATH="${CACHE_DIR}/output/$ARCH"
    mkdir -p "$OUTPUT_PATH"
    
    # 进入缓存目录进行操作
    cd "$CACHE_DIR"
    
    if [ "$LIB_NAME" = "lz4" ]; then
    
        LZ4_FOLDER="lz4-${LZ4_VERSION}"
        
        tar -xzf ${LZ4_FILE}
        check_success
        
        # GitHub发布的tar.gz解压后可能有不同的目录名
        if [ ! -d "$LZ4_FOLDER" ]; then
            LZ4_FOLDER=$(find . -maxdepth 1 -type d -name "lz4-*" | head -1)
            LZ4_FOLDER=${LZ4_FOLDER#./}
        fi
        
        cd $LZ4_FOLDER
        
        export CC=$CC
        export CXX="${CC%clang}clang++"
        
        make -j4 install DESTDIR=${OUTPUT_PATH}
        check_success
        
        mkdir -p "${INCLUDE_PATH}/lz4"
        
        cd ..
        
        cp -r $(pwd)/output/$ARCH/usr/local/include/*.h "${INCLUDE_PATH}/lz4/"
        cp $(pwd)/output/$ARCH/usr/local/lib/*.a "${LIB_PATH}/${ARCH}_lz4.a"
        rm -rf $LZ4_FOLDER
        
    elif [ "$LIB_NAME" = "xz" ]; then
    
        XZ_FOLDER="xz-${XZ_VERSION}"
        tar -xzf ${XZ_FILE}
        
        cd $XZ_FOLDER
        
        export CC=$CC
        export CXX="${CC%clang}clang++"
        
        ./configure --disable-debug \
        --disable-dependency-tracking \
        --disable-silent-rules \
        --host=$HOST \
        --prefix=${OUTPUT_PATH}
        
        make -j4
        make install
        check_success
        
        mkdir -p "${INCLUDE_PATH}/xz"
        cp -r ${OUTPUT_PATH}/include/* "${INCLUDE_PATH}/xz/"
        cp ${OUTPUT_PATH}/lib/liblzma.a "${LIB_PATH}/${ARCH}_xz.a"
        cd ..
        rm -rf $XZ_FOLDER
        
    elif [ "$LIB_NAME" = "bzip2" ]; then
        
        BZIP2_FOLDER="bzip2-${BZIP2_VERSION}"
        tar -xzf ${BZIP2_FILE}
        
        cd $BZIP2_FOLDER
        
        # bzip2 不使用configure，直接修改Makefile
        export CC=$CC
        export CXX="${CC%clang}clang++"
        
        # 修改Makefile以使用我们的编译器和目标路径
        sed -i.bak "s/CC=gcc/CC=${CC//\//\\/}/g" Makefile
        
        # 编译并安装
        make -j4
        make install PREFIX=${OUTPUT_PATH}
        check_success
        
        mkdir -p "${INCLUDE_PATH}/bzip2"
        cp -r ${OUTPUT_PATH}/include/* "${INCLUDE_PATH}/bzip2/" 2>/dev/null || :
        cp *.h "${INCLUDE_PATH}/bzip2/"
        cp libbz2.a "${LIB_PATH}/${ARCH}_bzip2.a"
        cd ..
        rm -rf $BZIP2_FOLDER
        
    elif [ "$LIB_NAME" = "libiconv" ]; then
        
        LIBICONV_FOLDER="libiconv-${LIBICONV_VERSION}"
        tar -xzf ${LIBICONV_FILE}
        
        cd $LIBICONV_FOLDER
        
        export CC=$CC
        export CXX="${CC%clang}clang++"
        
        ./configure --disable-debug \
        --disable-dependency-tracking \
        --disable-silent-rules \
        --host=$HOST \
        --prefix=${OUTPUT_PATH} \
        --enable-static \
        --disable-shared
        
        make -j4
        make install
        check_success
        
        mkdir -p "${INCLUDE_PATH}/libiconv"
        cp -r ${OUTPUT_PATH}/include/* "${INCLUDE_PATH}/libiconv/"
        cp ${OUTPUT_PATH}/lib/libiconv.a "${LIB_PATH}/${ARCH}_libiconv.a"
        cd ..
        rm -rf $LIBICONV_FOLDER
        
    elif [ "$LIB_NAME" = "libarchive" ]; then
    
        LIBARCHIVE_FOLDER="libarchive-${LIBARCHIVE_VERSION}"
        tar -xzf ${LIBARCHIVE_FILE}
        
        cd $LIBARCHIVE_FOLDER
        
        export CC=$CC
        export CXX="${CC%clang}clang++"
        
        autoreconf -f -i
        CFLAGS="$CFLAGS -I${INCLUDE_PATH}/xz -I${INCLUDE_PATH}/lz4 -I${INCLUDE_PATH}/bzip2 -I${INCLUDE_PATH}/libiconv" \
        LDFLAGS="$LDFLAGS -L${LIB_PATH}" \
        ./configure --without-lzo2 \
        --without-nettle \
        --without-xml2 \
        --without-openssl \
        --without-expat \
        --with-bz2lib \
        --with-iconv \
        --host=$HOST \
        --prefix=${OUTPUT_PATH}
        
        make -j4
        make install
        check_success
        
        mkdir -p "${INCLUDE_PATH}/libarchive"
        cp -r ${OUTPUT_PATH}/include/* "${INCLUDE_PATH}/libarchive/"
        cp ${OUTPUT_PATH}/lib/libarchive.a "${LIB_PATH}/${ARCH}_libarchive.a"
        cd ..
        rm -rf $LIBARCHIVE_FOLDER
        
    else
        echo "Unsupported library: $LIB_NAME"
        exit 1
    fi
    
    # 返回到原始目录
    cd "$(dirname "$0")"
}

# Compile and create XCFrameworks for each library
for LIB in lz4 xz bzip2 libiconv libarchive; do
    echo "Building $LIB for x86_64 simulator"
    compile_library x86_64_sim "$CC_X86_64_SIM" $LIB x86_64-apple-darwin
    
    echo "Building $LIB for arm64 simulator"
    compile_library arm64_sim "$CC_ARM64_SIM" $LIB arm64-apple-darwin
    
    echo "Building $LIB for arm64 device"
    compile_library arm64_ios "$CC_ARM64_IOS" $LIB arm64-apple-ios
    
    echo "Building XCFramework for $LIB"
    create_xcframework $LIB
done

# 清理临时文件
if [ $KEEP_TEMP -eq 0 ]; then
    echo "清理临时文件..."
    
    # 询问是否清理缓存目录
    read -p "是否清理缓存目录? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "清理缓存目录..."
        rm -rf "$CACHE_DIR"
    fi
    
    # 询问是否保留下载的源码包
    read -p "是否清理下载目录? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "清理下载目录..."
        rm -rf "$DOWNLOAD_DIR"
    fi
else
    echo "保留临时文件和构建目录。"
fi

# 显示构建结果
echo ""
echo "构建完成！"
echo "XCFrameworks 已创建在: ${XCFRAMEWORK_PATH}"
echo ""
echo "构建的库版本:"
echo "- LZ4: ${LZ4_VERSION}"
echo "- XZ: ${XZ_VERSION}"
echo "- BZIP2: ${BZIP2_VERSION}"
echo "- LIBICONV: ${LIBICONV_VERSION}"
echo "- LIBARCHIVE: ${LIBARCHIVE_VERSION}"
echo ""
echo "要在Xcode项目中使用这些库，请将XCFrameworks添加到您的项目中。"
echo "确保在链接时包含所有必要的库。"
