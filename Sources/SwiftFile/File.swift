//
//  File.swift
//  DiskRemover
//
//  Created by robbin on 2022/7/26.
//

import Foundation

enum CommonError : Error {
    case runtimeError(String)
}


public enum SortDirection {
    case FromTopToDown
    case FromDownToTop
}

public class File {
    
    /// 文件名
    public let fileName: String!
    
    /// 不带扩展名的文件名
    public var fileNameWithoutExtension: String!
    
    /// 绝对路径
    public var absolutePath: String? = nil
    
    /// 是否是目录
    public var isDirectory: Bool = false
    
    /// 创建时间
    public var creationDate: Double? = nil
    
    /// 子文件（夹）列表
    public var subFileList: [File]? = nil
    
    /// 文件内容，注意只有内容较少的时候可以直接获取，否则请使用流式读取函数
    public var contents: String?
    
    /// 文件游标
    var offset: Int = 0
    
    /// 是否可写入
    public var writable: Bool {
        get {
            guard let absolutePath = self.absolutePath else {
                return false
            }
            if self.isDirectory == false && self.fileExists {
                return FileManager.default.isWritableFile(atPath: absolutePath)
            }
            return false
        }
    }
    
    /// 是否可读取
    public var readable: Bool {
        get {
            guard let absolutePath = self.absolutePath else {
                return false
            }
            
            if self.isDirectory == false && self.fileExists {
                return FileManager.default.isReadableFile(atPath: absolutePath)
            }
            return false
        }
    }
    
    /// 文件大小
    public lazy var size: Int64 = { [unowned self] in
        do {
            let size = try self.calcFileSize()
            return size
        } catch {
            return 0
        }
    }()
    
    public var fileExists: Bool {
        get {
            guard let absolutePath = self.absolutePath else {
                return false
            }
            return FileManager.default.fileExists(atPath: absolutePath, isDirectory: nil)
        }
    }
    
    /// 以GB为单位的大小
    public var sizeOfGB: Float {
        get {
            return (Float(self.size)) / 1024.0 / 1024.0 / 1024.0
        }
    }
    
    /// 初始化方法
    /// - Parameter path: 路径
    init(path: String) throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) == false {
//            throw CommonError.runtimeError("无法构建这个File对象")
        }
        
        self.isDirectory = isDirectory.boolValue
        self.fileName = (path as NSString).lastPathComponent
        self.fileNameWithoutExtension = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        self.absolutePath = path
        self.creationDate = (try FileManager.default.attributesOfItem(atPath: path)[.creationDate] as? Date)?.timeIntervalSince1970 ?? 0.0
    }
    
    /// 扫描目录下的所有文件
    /// - Parameter recurse: 是否递归扫描
    public func scanSubFiles(recurse: Bool = false) throws  {
        guard self.isDirectory, let absolutePath = self.absolutePath else {
            return
        }
        
        let list = try FileManager.default.contentsOfDirectory(atPath: absolutePath)
        if list.count > 0 {
            self.subFileList = [File]()
        }
        for item in list {
            let file = try File(path: absolutePath.stringByAppendFileSubPath(item))
            if file.isDirectory && recurse {
                try file.scanSubFiles(recurse: true)
            }
            self.subFileList?.append(file)
        }
    }
    
    
    /// 根据创建时间进行排序
    /// - Parameter sortDirection: 排序方向，从小到达，还是从大到小
    public func sortWithCreateTime(sortDirection: SortDirection = .FromTopToDown) {
        guard let _ = self.subFileList else {
            return
        }
        
        self.subFileList!.sort { fileA, fileB in
            guard let fileACreationDate = fileA.creationDate, let fileBCreationDate = fileB.creationDate else {
                return true
            }
            switch sortDirection {
            case .FromTopToDown:
                return fileACreationDate < fileBCreationDate
            case .FromDownToTop:
                return fileACreationDate > fileBCreationDate
            }
            
        }
    }
    
    /// 计算文件（夹）大小，如果是文件夹会递归进行计算
    /// - Returns: 文件大小
    fileprivate func calcFileSize() throws -> Int64 {
        guard let absolutePath = self.absolutePath else {
            return 0
        }
        if self.isDirectory {
            var totalSize: Int64 = 0
            try self.scanSubFiles()
            if let subFileList = self.subFileList {
                for file in subFileList {
                    totalSize += file.size
                }
            }
            
            return totalSize
        } else {
            return try FileManager.default.attributesOfItem(atPath: absolutePath)[.size] as? Int64 ?? 0
        }
    }
    
}

/// 文件操作的扩展
extension File {
    
    func createFileIfNotExists() {
        guard self.fileExists == false else {
            return
        }
        
        if let path = self.absolutePath {
            FileManager.default.createFile(atPath: path, contents: nil, attributes: nil)
        }
    }
    /// 删除文件
    func delete() throws {
        guard let absolutePath = self.absolutePath else {
            return
        }
        try FileManager.default.removeItem(atPath: absolutePath)
    }
    
    /// 找到对应文件名的文件
    /// - Parameter fileName: 文件名
    /// - Returns: 文件对象
    func findFile(_ fileName: String) throws -> File? {
        guard self.isDirectory else {
            return nil
        }
        
        if self.subFileList == nil {
            try self.scanSubFiles()
        }
        
        for item in self.subFileList! {
            if item.isDirectory {
                if let finded = try item.findFile(fileName) {
                    return finded
                }
            } else {
                if item.fileName == fileName {
                    return item
                }
            }
        }
        
        return nil
    }
}

extension File {
    
    /// 读取文件内容
    public func readToContents() throws {
        guard self.fileExists, self.isDirectory == false, let absolutePath = self.absolutePath, self.readable else {
            return
        }
        
        if let handle = FileHandle(forReadingAtPath: absolutePath) {
            if let data = try handle.readToEnd() {
                self.contents = String(data: data, encoding: .utf8)
            }
            
            try handle.close()
        }
    }
    
    public func writeContents(_ contents: String) throws -> Bool {
        guard self.fileExists, self.isDirectory == false, self.writable, let absolutePath = self.absolutePath else {
            return false
        }
        
        try contents.write(to: URL(fileURLWithPath: absolutePath), atomically: true, encoding: .utf8)
        return true
    }
    
    public func appendContents(_ contents: String) throws -> Bool {
        guard self.fileExists, self.isDirectory == false, self.writable, let absolutePath = self.absolutePath else {
            return false
        }
        
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: absolutePath))
        try handle.seekToEnd()
        if let data = contents.data(using: .utf8) {
            try handle.write(contentsOf: data)
            try handle.synchronize()
        }
        
        try handle.close()
        
        return true
    }
    
    public func emptyThisFile() throws -> Bool {
        return try self.writeContents("")
    }
}

extension String {
    
    /// 在末尾添加文件路径，自动处理斜杠/ 问题
    /// - Parameter subPath: 追加的路径
    /// - Returns: 完整路径
    public func stringByAppendFileSubPath(_ subPath: String) -> String {
        var path = ""
        var subPath = subPath
        
        if self.hasSuffix("/") == false {
            path += "/"
        }
        
        if subPath.hasPrefix("/") {
            subPath.remove(at: subPath.startIndex)
        }
        
        return "\(self)\(path)\(subPath)"
    }
    
    mutating func appendFileSubPath(_ subPath: String) {
        self = self.stringByAppendFileSubPath(subPath)
    }
}
