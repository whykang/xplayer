import Foundation
import UIKit
import AVFoundation

// WebDAV备份和恢复管理器
class WebDAVBackupManager: ObservableObject {
    static let shared = WebDAVBackupManager()
    
    private let userSettings = UserSettings.shared
    private let musicLibrary = MusicLibrary.shared
    @Published var isBackingUp = false
    @Published var isRestoring = false
    @Published var progress: Float = 0.0
    @Published var statusMessage = ""
    
    private init() {}
    
    // MARK: - 公共方法
    
    // 检查WebDAV连接
    func checkConnection(completion: @escaping (Bool, String) -> Void) {
        print("WebDAV备份: 开始检查连接")
        
        guard !userSettings.webdavServer.isEmpty && 
              !userSettings.webdavUsername.isEmpty && 
              !userSettings.webdavPassword.isEmpty else {
            print("WebDAV备份: 服务器信息不完整")
            completion(false, "WebDAV服务器信息不完整")
            return
        }
        
        // 确保服务器地址以/结尾
        var serverURL = userSettings.webdavServer
        if !serverURL.hasSuffix("/") {
            serverURL += "/"
            print("WebDAV备份: 服务器URL已添加/后缀: \(serverURL)")
        }
        
        // 创建目录检查请求
        guard let url = URL(string: serverURL) else {
            print("WebDAV备份: 无效的服务器URL: \(serverURL)")
            completion(false, "无效的服务器URL")
            return
        }
        
        print("WebDAV备份: 正在检查连接到: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        
        // 添加Basic认证
        let loginString = "\(userSettings.webdavUsername):\(userSettings.webdavPassword)"
        let loginData = loginString.data(using: .utf8)!
        let base64LoginString = loginData.base64EncodedString()
        request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("WebDAV备份: 连接错误: \(error.localizedDescription)")
                    completion(false, "连接错误: \(error.localizedDescription)")
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("WebDAV备份: 无效的服务器响应")
                    completion(false, "无效的服务器响应")
                    return
                }
                
                print("WebDAV备份: 服务器响应状态码: \(httpResponse.statusCode)")
                
                switch httpResponse.statusCode {
                case 200, 207:
                    print("WebDAV备份: 连接成功")
                    
                    // 如果URL没有/结尾，更新用户设置
                    if !self.userSettings.webdavServer.hasSuffix("/") {
                        self.userSettings.webdavServer += "/"
                        print("WebDAV备份: 已更新服务器URL为: \(self.userSettings.webdavServer)")
                    }
                    
                    completion(true, "连接成功")
                case 401:
                    print("WebDAV备份: 认证失败，用户名或密码错误")
                    completion(false, "认证失败，用户名或密码错误")
                case 404:
                    print("WebDAV备份: 服务器地址无效")
                    completion(false, "服务器地址无效")
                default:
                    print("WebDAV备份: 服务器返回错误: \(httpResponse.statusCode)")
                    completion(false, "服务器返回错误: \(httpResponse.statusCode)")
                }
            }
        }
        
        task.resume()
    }
    
    // 开始备份
    func startBackup(completion: @escaping (Bool, String) -> Void) {
        print("WebDAV备份: 开始备份流程 - DEBUG")
        print("WebDAV备份: isBackingUp=\(isBackingUp), isRestoring=\(isRestoring)")
        
        DispatchQueue.main.async {
            print("WebDAV备份: 在主线程上执行备份流程")
            
            guard self.validateSettings() else {
                print("WebDAV备份: 设置验证失败，服务器信息不完整")
                print("WebDAV备份: server=\(self.userSettings.webdavServer.isEmpty ? "空" : "有值")")
                print("WebDAV备份: username=\(self.userSettings.webdavUsername.isEmpty ? "空" : "有值")")
                print("WebDAV备份: password=\(self.userSettings.webdavPassword.isEmpty ? "空" : "有值")")
                completion(false, "WebDAV设置不完整")
                return
            }
            
            self.isBackingUp = true
            self.progress = 0.0
            self.statusMessage = "准备备份..."
            print("WebDAV备份: 设置验证通过，准备创建备份目录")
            
            // 创建备份目录
            self.createBackupDirectory { [weak self] success, message in
                guard let self = self else {
                    print("WebDAV备份: self已被释放")
                    DispatchQueue.main.async {
                        completion(false, "内部错误")
                    }
                    return
                }
                
                print("WebDAV备份: 目录创建结果 - 成功: \(success), 消息: \(message)")
                
                if !success {
                    print("WebDAV备份: 创建目录失败 - \(message)")
                    DispatchQueue.main.async {
                        self.isBackingUp = false
                        completion(false, message)
                    }
                    return
                }
                
                print("WebDAV备份: 目录创建成功，准备备份文件")
                
                // 准备备份文件
                self.prepareBackupFile { success, backupURL, message in
                    print("WebDAV备份: 备份文件准备结果 - 成功: \(success), 消息: \(message)")
                    
                    if !success || backupURL == nil {
                        print("WebDAV备份: 准备备份文件失败")
                        DispatchQueue.main.async {
                            self.isBackingUp = false
                            completion(false, message)
                        }
                        return
                    }
                    
                    print("WebDAV备份: 备份文件准备完成，开始上传: \(backupURL!.path)")
                    
                    // 上传备份文件
                    self.uploadBackupFile(backupURL!) { success, message in
                        print("WebDAV备份: 上传结果 - 成功: \(success), 消息: \(message)")
                        
                        DispatchQueue.main.async {
                            self.isBackingUp = false
                            if success {
                                self.userSettings.lastBackupDate = Date()
                                print("WebDAV备份: 备份完成，已更新最后备份时间")
                            } else {
                                print("WebDAV备份: 上传失败")
                            }
                            completion(success, message)
                        }
                    }
                }
            }
        }
    }
    
    // 开始恢复
    func startRestore(backupFolder: String, completion: @escaping (Bool, String) -> Void) {
        guard validateSettings() else {
            completion(false, "WebDAV设置不完整")
            return
        }
        
        isRestoring = true
        progress = 0.0
        statusMessage = "准备恢复..."
        
        // 获取备份文件夹中的音乐文件列表
        getBackupFilesList(folderName: backupFolder) { [weak self] success, musicFiles, message in
            guard let self = self, success, !musicFiles.isEmpty else {
                self?.isRestoring = false
                DispatchQueue.main.async {
                    completion(false, message.isEmpty ? "没有找到音乐文件" : message)
                }
                return
            }
            
            print("WebDAV备份: 准备恢复\(musicFiles.count)个音乐文件")
            
            // 创建临时目录存放下载的文件
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                print("WebDAV备份: 创建临时目录: \(tempDir.path)")
            } catch {
                print("WebDAV备份: 创建临时目录失败: \(error.localizedDescription)")
                self.isRestoring = false
                DispatchQueue.main.async {
                    completion(false, "创建临时目录失败")
                }
                return
            }
            
            // 创建组来并行下载和导入
            let group = DispatchGroup()
            var successCount = 0
            var failedFiles: [String] = []
            
            // 更新UI
            DispatchQueue.main.async {
                self.statusMessage = "开始下载音乐文件(0/\(musicFiles.count))..."
                self.progress = 0.1
            }
            
            // 下载每个音乐文件
            for (index, fileName) in musicFiles.enumerated() {
                group.enter()
                
                let directory = self.sanitizeWebDAVDirectory()
                let filePath = "\(directory)/\(backupFolder)/\(fileName)"
                let localURL = tempDir.appendingPathComponent(fileName)
                
                self.downloadMusicFile(from: filePath, to: localURL) { success in
                    if success {
                        // 导入音乐文件
                        MusicFileManager.shared.importMusicFile(from: localURL) { result in
                            switch result {
                            case .success(let song):
                                print("WebDAV备份: 成功导入歌曲: \(song.title)")
                                successCount += 1
                            case .failure(let error):
                                print("WebDAV备份: 导入歌曲失败: \(error.localizedDescription)")
                                failedFiles.append(fileName)
                            }
                            
                            // 更新进度
                            let progress = 0.1 + 0.9 * Float(index + 1) / Float(musicFiles.count)
                            DispatchQueue.main.async {
                                self.progress = progress
                                self.statusMessage = "恢复音乐文件(\(index + 1)/\(musicFiles.count))..."
                            }
                            
                            group.leave()
                        }
                    } else {
                        print("WebDAV备份: 下载文件失败: \(fileName)")
                        failedFiles.append(fileName)
                        
                        // 更新进度
                        let progress = 0.1 + 0.9 * Float(index + 1) / Float(musicFiles.count)
                        DispatchQueue.main.async {
                            self.progress = progress
                            self.statusMessage = "恢复音乐文件(\(index + 1)/\(musicFiles.count))..."
                        }
                        
                        group.leave()
                    }
                }
            }
            
            // 所有文件处理完成后
            group.notify(queue: .main) {
                print("WebDAV备份: 文件恢复完成，成功: \(successCount)/\(musicFiles.count)")
                
                // 清理临时目录
                try? FileManager.default.removeItem(at: tempDir)
                
                // 设置完成状态
                self.isRestoring = false
                if successCount == musicFiles.count {
                    self.progress = 1.0
                    self.statusMessage = "恢复成功完成"
                    completion(true, "所有\(musicFiles.count)个文件恢复成功")
                } else if successCount > 0 {
                    self.progress = 1.0
                    self.statusMessage = "部分文件恢复成功"
                    completion(true, "已恢复\(successCount)/\(musicFiles.count)个文件")
                } else {
                    self.progress = 0.0
                    self.statusMessage = "恢复失败"
                    completion(false, "所有文件恢复失败")
                }
            }
        }
    }
    
    // MARK: - 私有辅助方法
    
    // 验证WebDAV设置
    private func validateSettings() -> Bool {
        return !userSettings.webdavServer.isEmpty && 
               !userSettings.webdavUsername.isEmpty && 
               !userSettings.webdavPassword.isEmpty
    }
    
    // 创建WebDAV备份目录
    private func createBackupDirectory(completion: @escaping (Bool, String) -> Void) {
        print("WebDAV备份: 开始创建备份目录 - DEBUG")
        
        // 检查并修复目录路径
        let directory = sanitizeWebDAVDirectory()
        print("WebDAV备份: 使用目录路径: \(directory)")
        
        // 构建有效URL
        guard let url = buildValidWebDAVURL(path: directory) else {
            print("WebDAV备份: 无法构建有效的目录URL")
            DispatchQueue.main.async {
                completion(false, "无效的目录URL")
            }
            return
        }
        
        print("WebDAV备份: 成功构建目录URL: \(url.absoluteString)")
        createDirectory(url: url, completion: completion)
    }
    
    // 实际创建目录的操作
    private func createDirectory(url: URL, completion: @escaping (Bool, String) -> Void) {
        print("WebDAV备份: 开始创建目录操作 - URL: \(url)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "MKCOL"
        
        // 添加Basic认证
        let loginString = "\(userSettings.webdavUsername):\(userSettings.webdavPassword)"
        let loginData = loginString.data(using: .utf8)!
        let base64LoginString = loginData.base64EncodedString()
        request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
        
        print("WebDAV备份: 发送MKCOL请求到: \(url)")
        
        // 增加超时时间和额外调试信息
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30 // 设置请求超时为30秒
        config.timeoutIntervalForResource = 60 // 设置资源超时为60秒
        print("WebDAV备份: 设置请求超时时间为30秒，资源超时时间为60秒")
        
        let session = URLSession(configuration: config)
        print("WebDAV备份: 已创建自定义URLSession")
        
        let task = session.dataTask(with: request) { data, response, error in
            print("WebDAV备份: 收到目录创建请求的响应")
            
            DispatchQueue.main.async {
                if let error = error {
                    print("WebDAV备份: 创建目录错误: \(error.localizedDescription)")
                    completion(false, "创建目录错误: \(error.localizedDescription)")
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("WebDAV备份: 无效的服务器响应")
                    completion(false, "无效的服务器响应")
                    return
                }
                
                print("WebDAV备份: 创建目录响应状态码: \(httpResponse.statusCode)")
                
                switch httpResponse.statusCode {
                case 201:
                    print("WebDAV备份: 目录创建成功")
                    completion(true, "备份目录创建成功")
                case 405:
                    // 目录已存在是正常情况
                    print("WebDAV备份: 目录已存在，可以继续使用")
                    completion(true, "备份目录已存在")
                case 401:
                    print("WebDAV备份: 身份验证失败")
                    completion(false, "身份验证失败，请检查用户名和密码")
                case 403:
                    print("WebDAV备份: 权限不足")
                    completion(false, "没有创建目录的权限")
                case 409, 415, 507:
                    print("WebDAV备份: 服务器拒绝创建目录")
                    completion(false, "服务器拒绝创建目录，状态码: \(httpResponse.statusCode)")
                default:
                    print("WebDAV备份: 创建目录失败，未知状态码: \(httpResponse.statusCode)")
                    
                    // 尝试读取响应数据
                    if let data = data, let responseString = String(data: data, encoding: .utf8) {
                        print("WebDAV备份: 响应内容: \(responseString)")
                    }
                    
                    completion(false, "创建目录失败: \(httpResponse.statusCode)")
                }
            }
        }
        
        print("WebDAV备份: 开始执行创建目录任务")
        task.resume()
        print("WebDAV备份: 已启动网络请求")
    }
    
    // 准备备份文件
    private func prepareBackupFile(completion: @escaping (Bool, URL?, String) -> Void) {
        print("WebDAV备份: 开始准备备份音乐文件 - 直接上传模式")
        self.statusMessage = "正在准备音乐文件..."
        self.progress = 0.1
        
        // 获取音乐文件目录
        guard let musicDirectory = MusicFileManager.shared.getMusicDirectory() else {
            print("WebDAV备份: 无法获取音乐文件目录")
            DispatchQueue.main.async {
                completion(false, nil, "无法获取音乐文件目录")
            }
            return
        }
        
        print("WebDAV备份: 音乐文件目录: \(musicDirectory.path)")
        
        // 列出所有音乐文件
        DispatchQueue.global(qos: .background).async {
            do {
                let fileManager = FileManager.default
                let musicFiles = try fileManager.contentsOfDirectory(at: musicDirectory, includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension.lowercased() == "mp3" || $0.pathExtension.lowercased() == "flac" || $0.pathExtension.lowercased() == "wav" || $0.pathExtension.lowercased() == "m4a" }
                
                print("WebDAV备份: 找到\(musicFiles.count)个音乐文件")
                
                if musicFiles.isEmpty {
                    print("WebDAV备份: 没有找到音乐文件")
                    DispatchQueue.main.async {
                        completion(false, nil, "没有找到音乐文件可以备份")
                    }
                    return
                }
                
                // 创建临时目录用于存储文件信息
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
                
                // 创建一个信息文件，列出所有要上传的音乐文件
                let infoDict: [String: Any] = [
                    "totalFiles": musicFiles.count,
                    "timestamp": Date().timeIntervalSince1970,
                    "files": musicFiles.map { $0.lastPathComponent }
                ]
                
                let infoURL = tempDir.appendingPathComponent("filesInfo.json")
                let infoData = try JSONSerialization.data(withJSONObject: infoDict, options: .prettyPrinted)
                try infoData.write(to: infoURL)
                
                print("WebDAV备份: 创建了文件信息清单: \(infoURL.path)")
                print("WebDAV备份: 所有音乐文件已准备就绪，准备开始上传")
                
                DispatchQueue.main.async {
                    self.progress = 0.2
                    self.statusMessage = "音乐文件已准备就绪，准备上传"
                    // 将音乐目录和文件列表通过自定义URL格式传递给上传方法
                    let combinedInfo = "\(musicDirectory.path)|\(musicFiles.count)"
                    // 创建一个特殊URL来传递信息，实际上传将使用原始的音乐文件路径
                    let specialURL = URL(fileURLWithPath: combinedInfo)
                    completion(true, specialURL, "准备上传\(musicFiles.count)个音乐文件")
                }
            } catch {
                print("WebDAV备份: 准备音乐文件失败: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(false, nil, "准备音乐文件失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // 上传备份文件到WebDAV服务器（直接上传每个音乐文件）
    private func uploadBackupFile(_ infoURL: URL, completion: @escaping (Bool, String) -> Void) {
        print("WebDAV备份: 开始上传音乐文件")
        self.statusMessage = "开始上传音乐文件..."
        self.progress = Float(0.2)
        
        // 解析传入的特殊URL
        let components = infoURL.path.components(separatedBy: "|")
        guard components.count == 2,
              let musicCount = Int(components[1]) else {
            print("WebDAV备份: 无效的文件信息")
            DispatchQueue.main.async {
                completion(false, "无效的文件信息")
            }
            return
        }
        
        let musicDirPath = components[0]
        let musicDir = URL(fileURLWithPath: musicDirPath)
        
        // 列出所有音乐文件
        DispatchQueue.global(qos: .background).async {
            do {
                let fileManager = FileManager.default
                let musicFiles = try fileManager.contentsOfDirectory(at: musicDir, includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension.lowercased() == "mp3" || $0.pathExtension.lowercased() == "flac" || $0.pathExtension.lowercased() == "wav" || $0.pathExtension.lowercased() == "m4a" }
                
                // 确保音乐文件数量正确
                guard musicFiles.count == musicCount else {
                    print("WebDAV备份: 音乐文件数量不匹配: 预期\(musicCount)，实际\(musicFiles.count)")
                    DispatchQueue.main.async {
                        completion(false, "音乐文件数量不匹配")
                    }
                    return
                }
                
                print("WebDAV备份: 准备上传\(musicFiles.count)个音乐文件")
                
                // 创建目标目录
                let directory = self.sanitizeWebDAVDirectory()
                let musicDirName = "MusicBackup_\(Date().timeIntervalSince1970)"
                let targetDir = "\(directory)/\(musicDirName)"
                
                print("WebDAV备份: 目标目录: \(targetDir)")
                
                // 创建备份目录
                self.createBackupDirectory { [weak self] success, message in
                    guard let self = self, success else {
                        print("WebDAV备份: 创建主备份目录失败: \(message)")
                        DispatchQueue.main.async {
                            completion(false, "创建备份目录失败: \(message)")
                        }
                        return
                    }
                    
                    // 创建音乐备份子目录
                    if let targetDirURL = self.buildValidWebDAVURL(path: targetDir) {
                        print("WebDAV备份: 创建音乐备份子目录: \(targetDirURL)")
                        
                        self.createDirectory(url: targetDirURL) { success, message in
                            if !success {
                                print("WebDAV备份: 创建音乐备份子目录失败: \(message)")
                                DispatchQueue.main.async {
                                    completion(false, "创建音乐备份子目录失败")
                                }
                                return
                            }
                            
                            print("WebDAV备份: 音乐备份子目录创建成功，开始上传文件")
                            
                            // 创建任务组
                            let group = DispatchGroup()
                            var successCount = 0
                            var failedFiles: [String] = []
                            
                            // 更新UI
                            DispatchQueue.main.async {
                                self.statusMessage = "开始上传音乐文件(0/\(musicFiles.count))..."
                                self.progress = Float(0.2)
                            }
                            
                            // 开始上传每个文件
                            for (index, musicFile) in musicFiles.enumerated() {
                                group.enter()
                                
                                let fileName = musicFile.lastPathComponent
                                let targetPath = "\(targetDir)/\(fileName)"
                                
                                // 上传单个文件
                                self.uploadSingleFile(musicFile, targetPath: targetPath) { success in
                                    if success {
                                        successCount += 1
                                    } else {
                                        failedFiles.append(fileName)
                                    }
                                    
                                    // 更新进度
                                    let progress = 0.2 + 0.8 * Float(index + 1) / Float(musicFiles.count)
                                    DispatchQueue.main.async {
                                        self.progress = progress
                                        self.statusMessage = "上传音乐文件(\(index + 1)/\(musicFiles.count))..."
                                    }
                                    
                                    group.leave()
                                }
                            }
                            
                            // 所有上传完成后
                            group.notify(queue: .main) {
                                print("WebDAV备份: 文件上传完成，成功: \(successCount)/\(musicFiles.count)")
                                
                                // 更新用户信息
                                if successCount > 0 {
                                    self.userSettings.lastBackupDate = Date()
                                }
                                
                                // 设置完成状态
                                if successCount == musicFiles.count {
                                    self.progress = 1.0
                                    self.statusMessage = "备份成功完成"
                                    completion(true, "所有\(musicFiles.count)个文件备份成功")
                                } else if successCount > 0 {
                                    self.progress = 1.0
                                    self.statusMessage = "部分文件备份成功"
                                    completion(true, "已备份\(successCount)/\(musicFiles.count)个文件")
                                } else {
                                    self.progress = 0.0
                                    self.statusMessage = "备份失败"
                                    completion(false, "所有文件备份失败")
                                }
                            }
                        }
                    } else {
                        print("WebDAV备份: 无法创建有效的音乐备份目录URL")
                        DispatchQueue.main.async {
                            completion(false, "无法创建有效的备份目录URL")
                        }
                    }
                }
            } catch {
                print("WebDAV备份: 获取音乐文件失败: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(false, "获取音乐文件失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // 上传单个音乐文件
    private func uploadSingleFile(_ fileURL: URL, targetPath: String, completion: @escaping (Bool) -> Void) {
        guard let url = buildValidWebDAVURL(path: targetPath) else {
            print("WebDAV备份: 无法为文件 \(fileURL.lastPathComponent) 构建有效的上传URL")
            completion(false)
            return
        }
        
        do {
            // 读取文件数据
            let data: Data
            do {
                data = try Data(contentsOf: fileURL)
                print("WebDAV备份: 读取文件内容: \(fileURL.lastPathComponent), 大小: \(data.count)字节")
            } catch {
                print("WebDAV备份: 读取文件失败: \(fileURL.lastPathComponent) - \(error.localizedDescription)")
                completion(false)
                return
            }
            
            // 创建上传请求
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            
            // 添加Basic认证
            let loginString = "\(userSettings.webdavUsername):\(userSettings.webdavPassword)"
            let loginData = loginString.data(using: .utf8)!
            let base64LoginString = loginData.base64EncodedString()
            request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
            
            // 设置Content-Type和Content-Length
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
            
            // 设置自定义超时
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 120
            config.timeoutIntervalForResource = 240
            let session = URLSession(configuration: config)
            
            // 上传任务
            let task = session.uploadTask(with: request, from: data) { _, response, error in
                if let error = error {
                    print("WebDAV备份: 上传文件 \(fileURL.lastPathComponent) 失败: \(error.localizedDescription)")
                    completion(false)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("WebDAV备份: 上传文件 \(fileURL.lastPathComponent) 收到无效响应")
                    completion(false)
                    return
                }
                
                if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                    print("WebDAV备份: 上传文件 \(fileURL.lastPathComponent) 成功")
                    completion(true)
                } else {
                    print("WebDAV备份: 上传文件 \(fileURL.lastPathComponent) 失败，状态码: \(httpResponse.statusCode)")
                    completion(false)
                }
            }
            
            task.resume()
            
        } catch {
            print("WebDAV备份: 处理文件 \(fileURL.lastPathComponent) 失败: \(error.localizedDescription)")
            completion(false)
        }
    }
    
    // 列出可用的备份文件夹
    func listBackupFiles(completion: @escaping (Bool, [String], String) -> Void) {
        print("WebDAV备份: 开始获取备份文件夹列表")
        
        // 检查并修复目录路径
        let directory = sanitizeWebDAVDirectory()
        
        // 构建有效URL
        guard let url = buildValidWebDAVURL(path: directory) else {
            print("WebDAV备份: 无法构建有效的目录URL")
            completion(false, [], "无效的WebDAV URL")
            return
        }
        
        print("WebDAV备份: 列出目录内容: \(url)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        
        // 添加Basic认证
        let loginString = "\(userSettings.webdavUsername):\(userSettings.webdavPassword)"
        let loginData = loginString.data(using: .utf8)!
        let base64LoginString = loginData.base64EncodedString()
        request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
        
        // 设置超时时间
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        let session = URLSession(configuration: config)
        
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                print("WebDAV备份: 获取备份列表失败: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(false, [], "获取备份列表失败: \(error.localizedDescription)")
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (httpResponse.statusCode == 200 || httpResponse.statusCode == 207) else {
                print("WebDAV备份: 服务器返回错误状态码: \(String(describing: (response as? HTTPURLResponse)?.statusCode))")
                DispatchQueue.main.async {
                    completion(false, [], "服务器返回错误状态码")
                }
                return
            }
            
            guard let data = data, let xmlString = String(data: data, encoding: .utf8) else {
                print("WebDAV备份: 无法解析服务器响应")
                DispatchQueue.main.async {
                    completion(false, [], "无法解析服务器响应")
                }
                return
            }
            
            // 打印接收到的XML数据，帮助调试
            print("WebDAV备份: 服务器响应XML数据: \n\(xmlString)")
            
            // 解析XML，查找备份文件夹
            var backupFolders: [String] = []
            
            // 首先尝试从<d:displayname>标签中提取备份文件夹名
            let displayNamePattern = "<d:displayname>(MusicBackup_[0-9.]+)</d:displayname>"
            if let regex = try? NSRegularExpression(pattern: displayNamePattern, options: []) {
                let matches = regex.matches(in: xmlString, options: [], range: NSRange(xmlString.startIndex..., in: xmlString))
                for match in matches {
                    if let range = Range(match.range(at: 1), in: xmlString) {
                        let folderName = String(xmlString[range])
                        if folderName.hasPrefix("MusicBackup_") {
                            print("WebDAV备份: 从displayname标签找到备份文件夹: \(folderName)")
                            if !backupFolders.contains(folderName) {
                                backupFolders.append(folderName)
                            }
                        }
                    }
                }
            }
            
            // 如果未能从displayname找到，尝试从href中提取
            if backupFolders.isEmpty {
                let lines = xmlString.components(separatedBy: .newlines)
                
                print("WebDAV备份: 解析服务器返回数据，共\(lines.count)行")
                
                // 第一步：查找所有包含href标签的行，这些通常包含目录路径
                var hrefLines: [String] = []
                for line in lines {
                    if line.contains("<d:href>") || line.contains("<href>") {
                        hrefLines.append(line)
                    }
                }
                
                print("WebDAV备份: 找到\(hrefLines.count)个href标签")
                
                // 第二步：从href中提取目录名
                for hrefLine in hrefLines {
                    // 提取href标签中的内容
                    if let startRange = hrefLine.range(of: "<d:href>") ?? hrefLine.range(of: "<href>"),
                       let endRange = hrefLine.range(of: "</d:href>") ?? hrefLine.range(of: "</href>") {
                        let startIndex = startRange.upperBound
                        let endIndex = endRange.lowerBound
                        let href = String(hrefLine[startIndex..<endIndex])
                        
                        // 查找目录名
                        let pathComponents = href.split(separator: "/")
                        for component in pathComponents {
                            let comp = String(component)
                            if comp.contains("MusicBackup_") {
                                print("WebDAV备份: 从href找到备份文件夹: \(comp)")
                                if !backupFolders.contains(comp) {
                                    backupFolders.append(comp)
                                }
                            }
                        }
                    }
                }
                
                // 第三步：查找displayname标签，这通常包含准确的文件夹名称
                for (i, line) in lines.enumerated() {
                    if line.contains("<d:displayname>") || line.contains("<displayname>") {
                        if let startRange = line.range(of: "<d:displayname>") ?? line.range(of: "<displayname>"),
                           let endRange = line.range(of: "</d:displayname>") ?? line.range(of: "</displayname>") {
                            let startIndex = startRange.upperBound
                            let endIndex = endRange.lowerBound
                            let displayName = String(line[startIndex..<endIndex])
                            
                            if displayName.contains("MusicBackup_") {
                                print("WebDAV备份: 从displayname找到备份文件夹: \(displayName)")
                                if !backupFolders.contains(displayName) {
                                    backupFolders.append(displayName)
                                }
                            }
                        }
                    }
                }
                
                // 第四步：直接在整个XML中搜索MusicBackup_模式
                for line in lines {
                    if let folderName = self.extractBackupFolderName(from: line) {
                        print("WebDAV备份: 通过正则表达式找到备份文件夹: \(folderName)")
                        if !backupFolders.contains(folderName) {
                            backupFolders.append(folderName)
                        }
                    }
                }
            }
            
            print("WebDAV备份: 找到\(backupFolders.count)个备份文件夹: \(backupFolders)")
            
            DispatchQueue.main.async {
                completion(!backupFolders.isEmpty, backupFolders, backupFolders.isEmpty ? "没有找到备份文件" : "找到\(backupFolders.count)个备份")
            }
        }
        
        task.resume()
    }
    
    // 从XML中提取备份文件夹名称
    private func extractBackupFolderName(from line: String) -> String? {
        // 修改模式以匹配带小数点的时间戳
        let pattern = "MusicBackup_[0-9]+\\.[0-9]+"
        if let range = line.range(of: pattern, options: .regularExpression) {
            let extracted = String(line[range])
            // 确保不包含多余的字符
            if extracted.hasPrefix("MusicBackup_") {
                print("WebDAV备份: 提取到带小数点的备份文件夹名: \(extracted)")
                return extracted
            }
        }
        
        // 作为备用，尝试匹配没有小数点的情况
        let simplePattern = "MusicBackup_[0-9]+"
        if let range = line.range(of: simplePattern, options: .regularExpression) {
            let extracted = String(line[range])
            if extracted.hasPrefix("MusicBackup_") && !extracted.contains(".") {
                print("WebDAV备份: 提取到不带小数点的备份文件夹名: \(extracted)")
                return extracted
            }
        }
        
        return nil
    }
    
    // 获取指定备份文件夹中的音乐文件列表
    func getBackupFilesList(folderName: String, completion: @escaping (Bool, [String], String) -> Void) {
        print("WebDAV备份: 获取备份文件夹 \(folderName) 中的文件列表")
        
        let directory = sanitizeWebDAVDirectory()
        let folderPath = "\(directory)/\(folderName)"
        
        guard let url = buildValidWebDAVURL(path: folderPath) else {
            print("WebDAV备份: 无法构建有效的文件夹URL")
            DispatchQueue.main.async {
                completion(false, [], "无效的文件夹URL")
            }
            return
        }
        
        print("WebDAV备份: 请求URL: \(url)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        
        // 添加Basic认证
        let loginString = "\(userSettings.webdavUsername):\(userSettings.webdavPassword)"
        let loginData = loginString.data(using: .utf8)!
        let base64LoginString = loginData.base64EncodedString()
        request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
        
        // 设置超时时间
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        let session = URLSession(configuration: config)
        
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                print("WebDAV备份: 获取文件列表失败: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(false, [], "获取文件列表失败: \(error.localizedDescription)")
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (httpResponse.statusCode == 200 || httpResponse.statusCode == 207) else {
                print("WebDAV备份: 服务器返回错误状态码: \(String(describing: (response as? HTTPURLResponse)?.statusCode))")
                DispatchQueue.main.async {
                    completion(false, [], "服务器返回错误状态码")
                }
                return
            }
            
            guard let data = data, let xmlString = String(data: data, encoding: .utf8) else {
                print("WebDAV备份: 无法解析服务器响应")
                DispatchQueue.main.async {
                    completion(false, [], "无法解析服务器响应")
                }
                return
            }
            
            // 打印接收到的XML数据，用于调试
            print("WebDAV备份: 获取到文件夹内容XML: \n\(xmlString)")
            
            // 解析XML找出所有音乐文件
            var musicFiles: [String] = []
            
            // 从XML中提取<d:displayname>标签中的文件名，这是最可靠的方式
            // 支持的音乐文件扩展名
            let extensions = [".mp3", ".flac", ".wav", ".m4a"]
            
            // 解析<d:displayname>标签内容
            let displayNamePattern = "<d:displayname>([^<]+)</d:displayname>"
            do {
                let regex = try NSRegularExpression(pattern: displayNamePattern, options: [])
                let matches = regex.matches(in: xmlString, options: [], range: NSRange(xmlString.startIndex..., in: xmlString))
                
                for match in matches {
                    if let range = Range(match.range(at: 1), in: xmlString) {
                        let fileName = String(xmlString[range])
                        
                        // 检查是否是目录或音乐文件
                        let isDirectory = fileName == folderName || fileName.hasPrefix("MusicBackup_")
                        let isMusic = !isDirectory && extensions.contains { fileName.lowercased().hasSuffix($0) }
                        
                        if isMusic {
                            print("WebDAV备份: 从displayname标签找到音乐文件: \(fileName)")
                            if !musicFiles.contains(fileName) {
                                musicFiles.append(fileName)
                            }
                        }
                    }
                }
            } catch {
                print("WebDAV备份: 正则表达式匹配失败: \(error.localizedDescription)")
            }
            
            // 如果通过<d:displayname>没有找到任何文件，尝试直接在XML中搜索文件扩展名
            if musicFiles.isEmpty {
                let lines = xmlString.components(separatedBy: .newlines)
                
                for (i, line) in lines.enumerated() {
                    // 查找包含音乐文件扩展名的行
                    for ext in extensions {
                        if line.lowercased().contains(ext) {
                            // 查找临近的displayname标签
                            let startIndex = max(0, i - 5)
                            let endIndex = min(lines.count - 1, i + 5)
                            
                            for j in startIndex...endIndex {
                                let nearbyLine = lines[j]
                                if nearbyLine.contains("<d:displayname>") {
                                    if let startRange = nearbyLine.range(of: "<d:displayname>"),
                                       let endRange = nearbyLine.range(of: "</d:displayname>") {
                                        let startIdx = startRange.upperBound
                                        let endIdx = endRange.lowerBound
                                        let fileName = String(nearbyLine[startIdx..<endIdx])
                                        
                                        if !fileName.hasPrefix("MusicBackup_") && fileName.lowercased().hasSuffix(ext) {
                                            print("WebDAV备份: 通过上下文找到音乐文件: \(fileName)")
                                            if !musicFiles.contains(fileName) {
                                                musicFiles.append(fileName)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            print("WebDAV备份: 找到\(musicFiles.count)个音乐文件: \(musicFiles)")
            
            DispatchQueue.main.async {
                completion(!musicFiles.isEmpty, musicFiles, musicFiles.isEmpty ? "备份中没有找到音乐文件" : "找到\(musicFiles.count)个音乐文件")
            }
        }
        
        task.resume()
    }
    
    // 下载单个音乐文件
    private func downloadMusicFile(from path: String, to localURL: URL, completion: @escaping (Bool) -> Void) {
        print("WebDAV备份: 准备下载文件: \(path) 到 \(localURL.path)")
        
        // 处理包含中文和XML实体的文件路径
        // 先解码可能的XML实体引用
        var decodedPath = path
        decodedPath = decodedPath.replacingOccurrences(of: "&amp;", with: "&")
        print("WebDAV备份: 解码XML实体后的路径: \(decodedPath)")
        
        // 分解路径以单独处理文件名部分
        var pathComponents = decodedPath.components(separatedBy: "/")
        if let lastComponent = pathComponents.last, !lastComponent.isEmpty {
            // 完全处理文件名部分（特别注意处理&等特殊字符）
            let safeFileName = lastComponent
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? lastComponent
            
            // 替换路径中的最后一个组件
            pathComponents[pathComponents.count - 1] = safeFileName
            
            let processedPath = pathComponents.joined(separator: "/")
            print("WebDAV备份: 处理后的文件路径: \(processedPath)")
            
            // 构建有效URL
            guard let url = buildValidWebDAVURL(path: processedPath) else {
                print("WebDAV备份: 无法构建有效的下载URL: \(processedPath)")
                completion(false)
                return
            }
            
            print("WebDAV备份: 下载文件的完整URL: \(url.absoluteString)")
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            
            // 添加Basic认证
            let loginString = "\(userSettings.webdavUsername):\(userSettings.webdavPassword)"
            let loginData = loginString.data(using: .utf8)!
            let base64LoginString = loginData.base64EncodedString()
            request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
            
            // 配置会话
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForResource = 60 // 设置资源超时为60秒
            let session = URLSession(configuration: config)
            
            let task = session.downloadTask(with: request) { tempURL, response, error in
                if let error = error {
                    print("WebDAV备份: 下载文件失败: \(error.localizedDescription)")
                    
                    // 失败重试一次，使用原始路径的完全编码版本
                    let fallbackPath = decodedPath
                        .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? decodedPath
                    
                    print("WebDAV备份: 第一次下载失败，尝试备用路径: \(fallbackPath)")
                    
                    if let fallbackURL = self.buildValidWebDAVURL(path: fallbackPath) {
                        print("WebDAV备份: 使用备用URL重试下载: \(fallbackURL)")
                        
                        var fallbackRequest = URLRequest(url: fallbackURL)
                        fallbackRequest.httpMethod = "GET"
                        fallbackRequest.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
                        
                        let fallbackTask = session.downloadTask(with: fallbackRequest) { tempURL, response, error in
                            self.handleDownloadResult(tempURL: tempURL, response: response, error: error, localURL: localURL, completion: completion)
                        }
                        
                        fallbackTask.resume()
                    } else {
                        print("WebDAV备份: 无法构建备用URL，下载失败")
                        DispatchQueue.main.async {
                            completion(false)
                        }
                    }
                    return
                }
                
                self.handleDownloadResult(tempURL: tempURL, response: response, error: error, localURL: localURL, completion: completion)
            }
            
            task.resume()
        } else {
            print("WebDAV备份: 路径解析错误，找不到文件名")
            completion(false)
        }
    }
    
    // 处理下载结果的辅助方法
    private func handleDownloadResult(tempURL: URL?, response: URLResponse?, error: Error?, localURL: URL, completion: @escaping (Bool) -> Void) {
        if let error = error {
            print("WebDAV备份: 下载文件失败: \(error.localizedDescription)")
            DispatchQueue.main.async {
                completion(false)
            }
            return
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("WebDAV备份: 无效的服务器响应")
            DispatchQueue.main.async {
                completion(false)
            }
            return
        }
        
        // 记录HTTP响应信息
        print("WebDAV备份: 服务器响应状态码: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200, let tempURL = tempURL else {
            print("WebDAV备份: 下载失败，状态码: \(httpResponse.statusCode)")
            DispatchQueue.main.async {
                completion(false)
            }
            return
        }
        
        do {
            // 如果目标文件已存在，先删除
            if FileManager.default.fileExists(atPath: localURL.path) {
                try FileManager.default.removeItem(at: localURL)
                print("WebDAV备份: 已删除已存在的文件: \(localURL.path)")
            }
            
            // 移动下载的文件到目标位置
            try FileManager.default.moveItem(at: tempURL, to: localURL)
            print("WebDAV备份: 文件下载成功: \(localURL.lastPathComponent)")
            
            // 检查文件大小
            let fileSize = try FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64 ?? 0
            print("WebDAV备份: 下载的文件大小: \(fileSize) 字节")
            
            DispatchQueue.main.async {
                completion(true)
            }
        } catch {
            print("WebDAV备份: 保存下载文件失败: \(error.localizedDescription)")
            DispatchQueue.main.async {
                completion(false)
            }
        }
    }
    
    // 辅助方法：构建有效的WebDAV URL
    private func buildValidWebDAVURL(path: String) -> URL? {
        print("WebDAV备份: 开始构建URL - path=\(path)")
        // 确保服务器URL以/结尾
        var serverURL = userSettings.webdavServer
        if !serverURL.hasSuffix("/") {
            serverURL += "/"
            print("WebDAV备份: 服务器URL添加了/后缀: \(serverURL)")
        }
        
        // 确保路径不以/开头（避免双斜杠）
        var cleanPath = path
        if cleanPath.hasPrefix("/") && serverURL.hasSuffix("/") {
            cleanPath = String(cleanPath.dropFirst())
            print("WebDAV备份: 路径移除了起始/: \(cleanPath)")
        }
        
        // 分解路径并逐段编码
        var pathComponents = cleanPath.components(separatedBy: "/")
        for i in 0..<pathComponents.count {
            // 只对非空组件进行编码
            if !pathComponents[i].isEmpty {
                // 检查组件是否已编码
                if pathComponents[i].range(of: "%") == nil {
                    // 对路径组件进行URL编码，但保留/字符
                    if let encoded = pathComponents[i].addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
                        if encoded != pathComponents[i] {
                            print("WebDAV备份: 路径组件编码: \(pathComponents[i]) -> \(encoded)")
                        }
                        pathComponents[i] = encoded
                    }
                }
            }
        }
        
        // 重新组合编码后的路径
        let encodedPath = pathComponents.joined(separator: "/")
        
        // 组合URL
        let fullURLString = serverURL + encodedPath
        print("WebDAV备份: 完整URL字符串: \(fullURLString)")
        
        // 尝试创建URL
        if let url = URL(string: fullURLString) {
            print("WebDAV备份: 成功创建URL: \(url)")
            return url
        }
        
        // 如果直接创建失败，进行完整的URL编码
        print("WebDAV备份: 直接创建URL失败，尝试完整URL编码")
        if let encodedFullPath = fullURLString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            if let url = URL(string: encodedFullPath) {
                print("WebDAV备份: 完整编码后URL: \(url)")
                return url
            }
        }
        
        // 最后尝试使用RFC 3986标准
        print("WebDAV备份: 尝试使用RFC 3986标准编码")
        if let serverUrlObj = URL(string: serverURL) {
            let baseUrl = serverUrlObj.absoluteString
            if var components = URLComponents(string: baseUrl) {
                components.path += encodedPath
                if let finalUrl = components.url {
                    print("WebDAV备份: 使用URLComponents构建的URL: \(finalUrl)")
                    return finalUrl
                }
            }
        }
        
        print("WebDAV备份: 无法构建有效URL")
        return nil
    }
    
    // 检查并修复WebDAV目录路径
    private func sanitizeWebDAVDirectory() -> String {
        var directory = userSettings.webdavDirectory
        
        // 确保目录以/开头
        if !directory.hasPrefix("/") {
            directory = "/" + directory
        }
        
        // 确保不以/结尾（除非是根目录）
        if directory.count > 1 && directory.hasSuffix("/") {
            directory = String(directory.dropLast())
        }
        
        // 如果用户设置不同，更新它
        if directory != userSettings.webdavDirectory {
            userSettings.webdavDirectory = directory
        }
        
        return directory
    }
    
    // 格式化备份日期
    private func formatBackupDate(_ backupFolder: String) -> String {
        if let range = backupFolder.range(of: "MusicBackup_") {
            let timestampString = String(backupFolder[range.upperBound...])
            
            // 首先尝试只解析小数点前的部分
            if timestampString.contains(".") {
                let components = timestampString.components(separatedBy: ".")
                if let mainPart = components.first, let timeInterval = TimeInterval(mainPart) {
                    let date = Date(timeIntervalSince1970: timeInterval)
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .short
                    return formatter.string(from: date)
                }
            }
            
            // 如果失败，尝试解析整个时间戳
            if let timeInterval = TimeInterval(timestampString) {
                let date = Date(timeIntervalSince1970: timeInterval)
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                return formatter.string(from: date)
            }
        }
        
        return backupFolder
    }
} 