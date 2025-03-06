# iOS libarchive XCFrameworks

这个项目提供了一个脚本，用于为iOS构建libarchive及其依赖库的XCFrameworks。这些XCFrameworks可以轻松集成到您的iOS项目中，支持模拟器（x86_64和arm64架构）和真机（arm64架构）。

## 包含的库

- **libarchive**: 多格式归档和压缩库
- **lz4**: 极快的压缩算法
- **xz**: 高压缩率的LZMA压缩
- **bzip2**: 高质量的块排序文件压缩器
- **libiconv**: 字符集转换库

## 系统要求

- macOS系统
- Xcode命令行工具
- 基本命令行工具：curl, grep, sed, tar, make, autoreconf等

## 使用方法

### 1. 配置

首先，您可以通过编辑`config.env`文件来配置要构建的库版本：

```bash
# 库版本配置
LZ4_VERSION="1.10.0"
XZ_VERSION="5.6.4"
LIBARCHIVE_VERSION="3.7.7"
BZIP2_VERSION="1.0.8"
LIBICONV_VERSION="1.17"

# 最低iOS版本
MIN_IOS="15.0"
```

### 2. 构建

运行构建脚本：

```bash
./build.sh
```

脚本支持以下选项：

- `-h, --help`: 显示帮助信息
- `-c, --clean`: 清理所有下载的文件和构建目录
- `-k, --keep-temp`: 保留临时文件和构建目录
- `-v, --verbose`: 显示详细输出

### 3. 文件夹结构

脚本使用以下文件夹结构：

- `downloads`: 存储下载的源码包，避免重复下载
- `cache`: 临时编译目录，所有编译过程在此进行
- `build`: 最终构建产物的输出目录，包含XCFrameworks

### 4. 输出

构建完成后，XCFrameworks将位于`build/xcframeworks`目录中：

- `libarchive.xcframework`
- `lz4.xcframework`
- `xz.xcframework`
- `bzip2.xcframework`
- `libiconv.xcframework`

脚本会在构建完成后询问是否需要清理缓存文件。

## 在Xcode项目中使用

### 添加XCFrameworks到项目

1. 打开您的Xcode项目
2. 选择您的项目文件，然后选择目标
3. 选择"General"选项卡
4. 在"Frameworks, Libraries, and Embedded Content"部分，点击"+"按钮
5. 点击"Add Other..."，然后选择"Add Files..."
6. 导航到XCFrameworks所在的目录（`build/xcframeworks`），选择您需要的框架
7. 确保"Embed & Sign"选项已选中

### 在Swift项目中使用C库（通过桥接头文件）

要在Swift项目中使用这些C库，您需要创建一个桥接头文件：

1. 如果您的项目中还没有桥接头文件，创建一个新的头文件（例如`BridgingHeader.h`）
2. 在项目设置中，找到"Swift Compiler - General"部分
3. 在"Objective-C Bridging Header"字段中，输入桥接头文件的路径（相对于项目根目录）

在桥接头文件中，导入您需要的头文件：

```objc
// BridgingHeader.h

// libarchive
#import <libarchive/archive.h>
#import <libarchive/archive_entry.h>

// 如果需要，也可以导入其他库的头文件
#import <lz4/lz4.h>
#import <bzip2/bzlib.h>
```

### Swift中使用libarchive的示例

```swift
import Foundation

// 解压缩tar.gz文件的示例
func extractTarGz(from sourcePath: String, to destinationPath: String) -> Bool {
    // 创建解压缩句柄
    guard let archive = archive_read_new() else {
        print("无法创建archive读取句柄")
        return false
    }
    defer {
        archive_read_free(archive)
    }
    
    // 设置过滤器和格式
    archive_read_support_filter_all(archive)
    archive_read_support_format_all(archive)
    
    // 创建写入句柄
    guard let ext = archive_write_disk_new() else {
        print("无法创建archive写入句柄")
        return false
    }
    defer {
        archive_write_free(ext)
    }
    
    // 设置写入选项
    let flags = ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_PERM | ARCHIVE_EXTRACT_ACL | ARCHIVE_EXTRACT_FFLAGS
    archive_write_disk_set_options(ext, Int32(flags))
    archive_write_disk_set_standard_lookup(ext)
    
    // 打开源文件
    if archive_read_open_filename(archive, sourcePath, 10240) != ARCHIVE_OK {
        print("无法打开源文件: \(String(cString: archive_error_string(archive)))")
        return false
    }
    
    // 解压文件
    var result = true
    var entry: OpaquePointer?
    
    while true {
        let readResult = archive_read_next_header(archive, &entry)
        if readResult == ARCHIVE_EOF {
            break
        }
        
        if readResult != ARCHIVE_OK {
            print("读取头信息失败: \(String(cString: archive_error_string(archive)))")
            result = false
            break
        }
        
        // 设置解压路径
        let entryPath = String(cString: archive_entry_pathname(entry))
        let fullPath = (destinationPath as NSString).appendingPathComponent(entryPath)
        archive_entry_set_pathname(entry, fullPath)
        
        // 写入磁盘
        if archive_write_header(ext, entry) != ARCHIVE_OK {
            print("写入头信息失败: \(String(cString: archive_error_string(ext)))")
            result = false
            break
        }
        
        // 复制数据
        if archive_entry_size(entry) > 0 {
            result = copyData(from: archive, to: ext)
            if !result {
                break
            }
        }
        
        // 完成写入
        if archive_write_finish_entry(ext) != ARCHIVE_OK {
            print("完成条目写入失败: \(String(cString: archive_error_string(ext)))")
            result = false
            break
        }
    }
    
    return result
}

// 从源复制数据到目标
private func copyData(from archive: OpaquePointer, to ext: OpaquePointer) -> Bool {
    var buffer: UnsafeRawPointer?
    var size: Int = 0
    var offset: Int64 = 0
    
    while true {
        let result = archive_read_data_block(archive, &buffer, &size, &offset)
        
        if result == ARCHIVE_EOF {
            return true
        }
        
        if result != ARCHIVE_OK {
            print("读取数据块失败: \(String(cString: archive_error_string(archive)))")
            return false
        }
        
        if archive_write_data_block(ext, buffer, size, offset) != ARCHIVE_OK {
            print("写入数据块失败: \(String(cString: archive_error_string(ext)))")
            return false
        }
    }
}

// 使用示例
func example() {
    let sourcePath = "/path/to/archive.tar.gz"
    let destinationPath = "/path/to/extract"
    
    if extractTarGz(from: sourcePath, to: destinationPath) {
        print("解压成功")
    } else {
        print("解压失败")
    }
}
```

### 创建压缩文件的示例

```swift
import Foundation

// 创建tar.gz文件的示例
func createTarGz(from sourcePath: String, to destinationPath: String) -> Bool {
    // 创建写入句柄
    guard let archive = archive_write_new() else {
        print("无法创建archive写入句柄")
        return false
    }
    defer {
        archive_write_free(archive)
    }
    
    // 设置压缩格式和过滤器
    archive_write_add_filter_gzip(archive)
    archive_write_set_format_pax_restricted(archive)
    
    // 打开目标文件
    if archive_write_open_filename(archive, destinationPath) != ARCHIVE_OK {
        print("无法打开目标文件: \(String(cString: archive_error_string(archive)))")
        return false
    }
    
    // 添加文件到归档
    let fileManager = FileManager.default
    var isDir: ObjCBool = false
    
    if fileManager.fileExists(atPath: sourcePath, isDirectory: &isDir) {
        if isDir.boolValue {
            // 添加目录
            return addDirectoryToArchive(archive, path: sourcePath, basePath: (sourcePath as NSString).deletingLastPathComponent)
        } else {
            // 添加单个文件
            return addFileToArchive(archive, path: sourcePath, basePath: (sourcePath as NSString).deletingLastPathComponent)
        }
    }
    
    return false
}

// 添加目录到归档
private func addDirectoryToArchive(_ archive: OpaquePointer, path: String, basePath: String) -> Bool {
    let fileManager = FileManager.default
    
    do {
        let contents = try fileManager.contentsOfDirectory(atPath: path)
        
        for item in contents {
            let fullPath = (path as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            
            if fileManager.fileExists(atPath: fullPath, isDirectory: &isDir) {
                if isDir.boolValue {
                    // 递归添加子目录
                    if !addDirectoryToArchive(archive, path: fullPath, basePath: basePath) {
                        return false
                    }
                } else {
                    // 添加文件
                    if !addFileToArchive(archive, path: fullPath, basePath: basePath) {
                        return false
                    }
                }
            }
        }
        
        return true
    } catch {
        print("读取目录内容失败: \(error.localizedDescription)")
        return false
    }
}

// 添加文件到归档
private func addFileToArchive(_ archive: OpaquePointer, path: String, basePath: String) -> Bool {
    // 创建条目
    guard let entry = archive_entry_new() else {
        print("无法创建archive条目")
        return false
    }
    defer {
        archive_entry_free(entry)
    }
    
    // 获取文件信息
    var stat = stat()
    if lstat(path, &stat) != 0 {
        print("无法获取文件信息")
        return false
    }
    
    // 设置条目信息
    archive_entry_set_size(entry, Int64(stat.st_size))
    archive_entry_set_mode(entry, UInt32(stat.st_mode))
    archive_entry_set_mtime(entry, Int64(stat.st_mtime), 0)
    
    // 设置相对路径
    let relativePath = path.replacingOccurrences(of: basePath, with: "")
    let entryPath = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
    archive_entry_set_pathname(entry, entryPath)
    
    // 写入头信息
    if archive_write_header(archive, entry) != ARCHIVE_OK {
        print("写入头信息失败: \(String(cString: archive_error_string(archive)))")
        return false
    }
    
    // 写入文件内容
    if stat.st_size > 0 {
        guard let file = fopen(path, "rb") else {
            print("无法打开文件")
            return false
        }
        defer {
            fclose(file)
        }
        
        let bufferSize = 8192
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer {
            buffer.deallocate()
        }
        
        while true {
            let bytesRead = fread(buffer, 1, bufferSize, file)
            if bytesRead == 0 {
                break
            }
            
            let bytesWritten = archive_write_data(archive, buffer, bytesRead)
            if bytesWritten < 0 || bytesWritten != bytesRead {
                print("写入数据失败")
                return false
            }
        }
    }
    
    return true
}

// 使用示例
func example() {
    let sourcePath = "/path/to/directory"
    let destinationPath = "/path/to/archive.tar.gz"
    
    if createTarGz(from: sourcePath, to: destinationPath) {
        print("创建归档成功")
    } else {
        print("创建归档失败")
    }
}
```

## 故障排除

### 链接错误

如果您在使用这些库时遇到链接错误，请确保：

1. 所有必要的XCFrameworks都已添加到项目中
2. 在"Build Phases" > "Link Binary With Libraries"中，确保所有库都已列出
3. 如果使用libarchive，确保同时链接了其所有依赖库（lz4、xz、bzip2和libiconv）

### 头文件找不到

如果编译器无法找到头文件，请检查：

1. 桥接头文件路径是否正确设置
2. 导入语句是否正确（例如`#import <libarchive/archive.h>`而不是`#import "archive.h"`）
3. XCFrameworks是否正确添加到项目中

## 许可证

本项目中的构建脚本采用MIT许可证。

各个库的许可证如下：
- libarchive: BSD 2-Clause
- lz4: BSD 2-Clause
- xz: 公共领域
- bzip2: BSD-like
- libiconv: LGPL

## 贡献

欢迎提交问题报告和拉取请求。 