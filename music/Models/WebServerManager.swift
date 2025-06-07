import Foundation
import Network
import Darwin

/// WebServer管理器代理协议
protocol WebServerManagerDelegate {
    /// 处理上传的文件
    func webServerManager(_ manager: WebServerManager, didReceiveFile fileURL: URL, filename: String, fileSize: Int, mimeType: String)
}

/// WebServer管理器
class WebServerManager: ObservableObject {
    /// 服务器监听端口
    private let port: UInt16
    
    /// 委托对象
    var delegate: WebServerManagerDelegate?
    
    /// 文件接收回调，用于与旧代码兼容
    var onFileReceived: ((URL, String, Int, String) -> Void)?
    
    /// 服务器运行状态
    @Published private(set) var isRunning = false
    
    /// 服务器socket
    private var serverSocket: Int32 = -1
    
    /// 运行队列
    private let serverQueue = DispatchQueue(label: "com.music.serverQueue", attributes: .concurrent)
    
    /// Socket连接类型别名
    typealias SocketConnection = Int32
    
    /// HTTP请求结构
    typealias HTTPRequest = (headers: [String: String], body: Data)
    
    /// 初始化
    init(port: UInt16 = 8080) {
        self.port = port
    }
    
    deinit {
        stopServer()
    }
    
    /// 启动服务器
    func startServer(delegate: WebServerManagerDelegate? = nil) -> String {
        self.delegate = delegate
        
        // 获取本地IP地址
        let ipAddress = getLocalIPAddress()
        print("使用IP地址: \(ipAddress)")
        
        // 创建socket
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        if serverSocket == -1 {
            print("创建socket失败")
            return ipAddress
        }
        
        // 允许地址重用
        var reuse: Int32 = 1
        if setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse))) == -1 {
            print("设置SO_REUSEADDR失败")
            close(serverSocket)
            serverSocket = -1
            return ipAddress
        }
        
        // 增加接收缓冲区大小
        var rcvBufSize: Int32 = 1024 * 1024 * 16 // 16MB，增大缓冲区以处理大文件
        if setsockopt(serverSocket, SOL_SOCKET, SO_RCVBUF, &rcvBufSize, socklen_t(MemoryLayout.size(ofValue: rcvBufSize))) == -1 {
            print("设置SO_RCVBUF失败，使用系统默认值")
        }
        
        // 设置非阻塞模式
        // 设置socket地址
        var serverAddr = sockaddr_in()
        serverAddr.sin_family = sa_family_t(AF_INET)
        serverAddr.sin_port = port.bigEndian
        serverAddr.sin_addr.s_addr = UInt32(INADDR_ANY).bigEndian
        serverAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        
        // 绑定地址
        let bindResult = withUnsafePointer(to: &serverAddr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        if bindResult == -1 {
            print("绑定失败: \(String(cString: strerror(errno)))")
            close(serverSocket)
            serverSocket = -1
            return ipAddress
        }
        
        // 监听连接
        if listen(serverSocket, 5) == -1 {
            print("监听失败: \(String(cString: strerror(errno)))")
            close(serverSocket)
            serverSocket = -1
            return ipAddress
        }
        
        // 服务器已启动
        isRunning = true
        
        // 在后台线程接受连接
        serverQueue.async { [weak self] in
            self?.acceptConnections()
        }
        
        return ipAddress
    }
    
    /// 停止服务器
    func stopServer() {
        if serverSocket != -1 {
            close(serverSocket)
            serverSocket = -1
        }
        isRunning = false
    }
    
    /// 接受连接
    private func acceptConnections() {
        while isRunning && serverSocket != -1 {
            var clientAddr = sockaddr_in()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            
            let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { clientAddrPtr in
                clientAddrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    accept(serverSocket, sockaddrPtr, &clientAddrLen)
                }
            }
            
            if clientSocket != -1 {
                // 在新线程中处理客户端连接
                serverQueue.async { [weak self] in
                    self?.handleClient(clientSocket)
                }
            } else if errno != EAGAIN && errno != EWOULDBLOCK {
                print("接受连接失败: \(String(cString: strerror(errno)))")
                break
            }
        }
    }
    
    /// 处理客户端连接
    private func handleClient(_ clientSocket: Int32) {
        defer {
            close(clientSocket)
            print("客户端连接已关闭")
        }
        
        print("新客户端连接已建立")
        
        // 设置接收缓冲区大小
        var rcvBufSize: Int32 = 1024 * 1024 * 16 // 16MB，增大缓冲区以处理大文件
        if setsockopt(clientSocket, SOL_SOCKET, SO_RCVBUF, &rcvBufSize, socklen_t(MemoryLayout.size(ofValue: rcvBufSize))) == -1 {
            print("为客户端设置SO_RCVBUF失败: \(String(cString: strerror(errno)))")
        } else {
            // 验证实际设置的缓冲区大小
            var actualSize: Int32 = 0
            var sizeLen = socklen_t(MemoryLayout.size(ofValue: actualSize))
            if getsockopt(clientSocket, SOL_SOCKET, SO_RCVBUF, &actualSize, &sizeLen) == 0 {
                print("客户端接收缓冲区大小设置为: \(actualSize) 字节")
            }
        }
        
        // 设置更长的超时时间 (30分钟)
        var timeout = timeval(tv_sec: 1800, tv_usec: 0)
        if setsockopt(clientSocket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout))) == -1 {
            print("设置接收超时失败: \(String(cString: strerror(errno)))")
        }
        
        // 读取请求
        let request = readRequest(from: clientSocket)
        
        // 检查请求是否有效
        if request.headers.isEmpty {
            print("收到空请求头，发送默认错误响应")
            sendErrorResponse(to: clientSocket, errorMessage: "无效的请求格式")
            return
        }
        
        // 从readRequest方法返回的原始头部字符串中获取第一行
        let firstLine = request.headers["Method"] ?? "UNKNOWN"
        if firstLine.isEmpty {
            print("请求头中没有有效的请求行")
            sendErrorResponse(to: clientSocket, errorMessage: "无效的HTTP请求格式")
            return
        }
        
        print("处理请求: \(firstLine)")
        
        // 提取HTTP方法
        let method = firstLine
        
        // 处理不同的HTTP方法
        switch method {
        case "GET":
            print("处理GET请求")
            sendUploadPage(to: clientSocket)
        case "POST":
            print("处理POST请求")
            handleFileUpload(request: request, client: clientSocket)
        case "OPTIONS":
            print("处理OPTIONS请求")
            sendCORSResponse(to: clientSocket)
        default:
            print("收到不支持的HTTP方法: \(method)")
            sendErrorResponse(to: clientSocket, errorMessage: "不支持的HTTP方法: \(method)")
        }
    }
    
    /// 读取HTTP请求
    private func readRequest(from clientSocket: Int32) -> HTTPRequest {
        var headerString = ""
        var bodyData = Data()
        let bufferSize = 16384 // 增大到16KB
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var headersComplete = false
        var contentLength = 0
        var bytesReadInBody = 0
        var headerEndPositionInFirstChunk = 0
        
        // 第一次读取，获取头部
        let bytesRead = recv(clientSocket, &buffer, bufferSize - 1, 0)
        if bytesRead <= 0 {
            let errorCode = errno
            print("读取请求时出错或连接关闭: \(String(cString: strerror(errorCode))) (错误码: \(errorCode))")
            return ([:], Data())
        }
        
        // 将读取的数据存储
        let chunk = Data(bytes: buffer, count: bytesRead)
        
        // 调试：打印前100个字节的十六进制表示
        let previewSize = min(100, chunk.count)
        let hexString = chunk.prefix(previewSize).map { String(format: "%02x", $0) }.joined(separator: " ")
        print("收到数据前\(previewSize)字节: \(hexString)")
        
        // 尝试从第一个数据块中提取头部
        if let rawHeader = String(data: chunk, encoding: .utf8) {
            // 查找头部结束标记
            if let headerEndRange = rawHeader.range(of: "\r\n\r\n") {
                headersComplete = true
                headerString = String(rawHeader[..<headerEndRange.upperBound])
                
                // 计算头部结束位置在数据中的偏移量
                if let headerEndData = "\r\n\r\n".data(using: .utf8),
                   let headerEndPosition = chunk.range(of: headerEndData) {
                    headerEndPositionInFirstChunk = headerEndPosition.upperBound
                    
                    // 将剩余数据添加到body中
                    if headerEndPositionInFirstChunk < chunk.count {
                        let remainingData = chunk.subdata(in: headerEndPositionInFirstChunk..<chunk.count)
                        bodyData.append(remainingData)
                        bytesReadInBody = remainingData.count
                    }
                }
            } else {
                // 如果第一个块没有完整头部，暂时存储并继续读取（正常情况下不太可能发生，HTTP头部通常很小）
                headerString = rawHeader
            }
        } else {
            print("无法将请求头转换为UTF-8字符串，尝试寻找HTTP头部结束标记")
            
            // 尝试直接在二进制数据中寻找头部结束标记
            if let headersEndData = "\r\n\r\n".data(using: .utf8),
               let headersEndPos = chunk.range(of: headersEndData) {
                // 尝试转换头部部分
                let headersData = chunk.prefix(upTo: headersEndPos.upperBound)
                if let headers = String(data: headersData, encoding: .utf8) {
                    headersComplete = true
                    headerString = headers
                    
                    // 将剩余数据添加到body中
                    if headersEndPos.upperBound < chunk.count {
                        let remainingData = chunk.subdata(in: headersEndPos.upperBound..<chunk.count)
                        bodyData.append(remainingData)
                        bytesReadInBody = remainingData.count
                    }
                } else {
                    print("找到头部结束标记但无法解析头部，使用默认GET请求头")
                    // 使用默认GET请求头
                    headerString = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
                    headersComplete = true
                    
                    // 将剩余数据添加到body中
                    if headersEndPos.upperBound < chunk.count {
                        bodyData.append(chunk.subdata(in: headersEndPos.upperBound..<chunk.count))
                        bytesReadInBody = chunk.count - headersEndPos.upperBound
                    }
                }
            } else {
                print("无法识别HTTP请求格式，使用默认GET请求")
                // 完全无法解析，返回默认GET请求
                return (["Method": "GET", "Path": "/", "Host": "localhost"], chunk)
            }
        }
        
        // 如果头部还未完成，继续读取（很少见情况）
        while !headersComplete {
            let bytesRead = recv(clientSocket, &buffer, bufferSize - 1, 0)
            if bytesRead <= 0 {
                break
            }
            
            let chunk = Data(bytes: buffer, count: bytesRead)
            if let partHeader = String(data: chunk, encoding: .utf8) {
                headerString += partHeader
                
                if let headerEndRange = headerString.range(of: "\r\n\r\n") {
                    headersComplete = true
                    headerString = String(headerString[..<headerEndRange.upperBound])
                }
            } else {
                print("无法将请求头部分转换为UTF-8字符串，终止读取头部")
                // 如果无法解析，就使用已有的头部信息
                if !headerString.isEmpty && !headerString.hasSuffix("\r\n\r\n") {
                    headerString += "\r\n\r\n"
                }
                headersComplete = true
            }
        }
        
        // 确保有请求方法
        if !headerString.contains("HTTP/") {
            headerString = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
        }
        
        // 解析HTTP头部为字典
        var headers = parseHTTPHeaders(headerString)
        
        // 解析请求行并添加到头部
        if let requestLine = headerString.components(separatedBy: "\r\n").first, 
           !requestLine.isEmpty {
            let parts = requestLine.components(separatedBy: " ")
            if parts.count >= 3 {
                headers["Method"] = parts[0]
                headers["Path"] = parts[1]
                headers["Version"] = parts[2]
            } else if parts.count >= 1 {
                headers["Method"] = parts[0]
                headers["Path"] = parts.count >= 2 ? parts[1] : "/"
            }
        } else {
            // 默认为GET请求
            headers["Method"] = "GET"
            headers["Path"] = "/"
        }
        
        // 解析Content-Length
        if let contentLengthValue = headers["Content-Length"] {
            contentLength = Int(contentLengthValue) ?? 0
            print("检测到Content-Length: \(contentLength)")
        }
        
        // 检查Transfer-Encoding
        let isChunked = headers["Transfer-Encoding"]?.lowercased().contains("chunked") == true
        
        if isChunked {
            print("检测到分块传输编码，将使用特殊处理")
        }
        
        // 获取HTTP方法
        let method = headers["Method"] ?? "GET"
        
        // 如果是POST请求并且有Content-Length > 0，继续读取请求体
        if method == "POST" && (contentLength > 0 || isChunked) {
            print("POST请求，总Content-Length: \(contentLength)，已接收: \(bytesReadInBody)")
            
            // 设置最大允许的请求体大小：100MB
            let maxBodySize = 100 * 1024 * 1024
            let actualContentLength = min(contentLength, maxBodySize)
            if contentLength > maxBodySize {
                print("请求体太大（\(contentLength) 字节），将限制为 \(maxBodySize) 字节")
            }
            
            let startTime = Date()
            var lastProgressLogTime = Date()
            var progressLogInterval: TimeInterval = 0.5 // 每0.5秒更新一次进度
            var totalBytesRead = bytesReadInBody
            
            if isChunked {
                // 处理分块传输编码
                // 暂不实现，因为文件上传通常使用标准POST而非分块编码
                print("暂不支持分块传输编码")
            } else {
                // 标准传输：读取直到Content-Length
                var retryCount = 0
                let maxRetries = 10
                
                // 继续读取直到得到完整的请求体或超时
                while totalBytesRead < actualContentLength {
                    // 增加尝试读取的数据量
                    let remainingBytes = actualContentLength - totalBytesRead
                    let bytesToRead = min(bufferSize - 1, remainingBytes)
                    
                    let bytesRead = recv(clientSocket, &buffer, bytesToRead, 0)
                    if bytesRead <= 0 {
                        let errorCode = errno
                        let errorMessage = String(cString: strerror(errorCode))
                        
                        if errorCode == EAGAIN || errorCode == EWOULDBLOCK {
                            retryCount += 1
                            print("暂时无数据可读，重试 \(retryCount)/\(maxRetries)")
                            
                            if retryCount >= maxRetries {
                                print("达到最大重试次数，停止读取")
                                break
                            }
                            
                            // 短暂休眠后重试
                            usleep(100000) // 休眠100毫秒
                            continue
                        } else {
                            print("读取请求体时出错或连接关闭: \(errorMessage) (错误码: \(errorCode))")
                            break
                        }
                    }
                    
                    // 重置重试计数
                    retryCount = 0
                    
                    let chunk = Data(bytes: buffer, count: bytesRead)
                    bodyData.append(chunk)
                    totalBytesRead += bytesRead
                    
                    // 定期打印进度
                    let now = Date()
                    if now.timeIntervalSince(lastProgressLogTime) >= progressLogInterval {
                        let elapsedTime = now.timeIntervalSince(startTime)
                        let bytesPerSecond = Double(totalBytesRead) / elapsedTime
                        let progress = Double(totalBytesRead) / Double(actualContentLength) * 100.0
                        print(String(format: "已接收: %.1f%% (%d/%d 字节), 速度: %.2f KB/s", 
                                     progress, totalBytesRead, actualContentLength, bytesPerSecond / 1024))
                        lastProgressLogTime = now
                    }
                }
            }
            
            // 检查是否接收完整
            if totalBytesRead < actualContentLength {
                print("警告: 请求体数据不完整，只收到 \(totalBytesRead)/\(actualContentLength) 字节")
            } else {
                let totalTime = Date().timeIntervalSince(startTime)
                let bytesPerSecond = Double(totalBytesRead) / (totalTime > 0 ? totalTime : 0.1)
                print(String(format: "接收完成: %d 字节, 总耗时: %.1f 秒, 平均速度: %.2f KB/s", 
                             totalBytesRead, totalTime, bytesPerSecond / 1024))
            }
        }
        
        print("请求读取完成，头部字段数：\(headers.count)，请求体大小：\(bodyData.count) 字节")
        
        return (headers, bodyData)
    }
    
    /// 处理文件上传请求
    private func handleFileUpload(request: HTTPRequest, client: SocketConnection) {
        print("开始处理文件上传请求")
        
        let requestHeaders = request.headers
        
        // 检查是否是multipart表单
        guard let contentType = requestHeaders["Content-Type"],
              contentType.hasPrefix("multipart/form-data") else {
            print("不是multipart表单请求")
            sendErrorResponse(to: client, errorMessage: "需要multipart/form-data请求")
            return
        }
        
        // 从Content-Type提取boundary
        guard let boundaryRange = contentType.range(of: "boundary=") else {
            print("未找到boundary参数")
            sendErrorResponse(to: client, errorMessage: "未找到boundary参数")
            return
        }
        
        // 提取boundary值
        let boundary = String(contentType[boundaryRange.upperBound...])
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        
        print("表单边界: \(boundary)")
        
        // 如果请求体为空，返回错误
        guard request.body.count > 0 else {
            print("请求体为空")
            sendErrorResponse(to: client, errorMessage: "请求体为空")
            return
        }
        
        // 解析multipart表单数据
        guard let fileData = parseMultipartFormDataBinary(bodyData: request.body, boundary: boundary) else {
            print("解析multipart表单数据失败")
            sendErrorResponse(to: client, errorMessage: "解析文件数据失败")
            return
        }
        
        let filename = fileData.filename
        let fileContent = fileData.data
        
        print("成功解析文件: \(filename), 大小: \(fileContent.count) 字节")
        
        // 检查文件完整性
        if fileContent.count < 1024 {
            print("警告: 文件太小 (\(fileContent.count) 字节)，可能不完整")
            sendErrorResponse(to: client, errorMessage: "上传的文件太小或不完整")
            return
        }
        
        // 文件大小上限检查 (500MB)
        let maxFileSize = 500 * 1024 * 1024
        if fileContent.count > maxFileSize {
            print("文件太大: \(fileContent.count) 字节，超过上限 \(maxFileSize) 字节")
            sendErrorResponse(to: client, errorMessage: "文件太大，最大允许500MB")
            return
        }
        
        // 获取文件MIME类型
        let mimeType = getMimeType(for: filename)
        
        // 验证是否为支持的音频文件类型
        let supportedAudioTypes = ["audio/mpeg", "audio/mp3", "audio/wav", "audio/x-wav", "audio/aac", "audio/x-m4a", "audio/mp4", "audio/flac", "audio/ogg"]
        if !supportedAudioTypes.contains(mimeType) {
            print("不支持的文件类型: \(mimeType)")
            // 如果文件名有MP3后缀但MIME类型不对，尝试继续处理
            if !filename.lowercased().hasSuffix(".mp3") {
                sendErrorResponse(to: client, errorMessage: "不支持的文件类型，仅支持音频文件")
                return
            } else {
                print("文件扩展名为MP3，尝试继续处理")
            }
        }
        
        // 创建临时文件路径
        let tempDirectory = FileManager.default.temporaryDirectory
        // 使用原始文件名来保存临时文件，避免随机UUID名称
        let safeFilename = sanitizeFilename(filename)
        let tempFileURL = tempDirectory.appendingPathComponent(safeFilename)
        
        do {
            // 如果同名文件已存在，先删除
            if FileManager.default.fileExists(atPath: tempFileURL.path) {
                try FileManager.default.removeItem(at: tempFileURL)
                print("删除已存在的同名临时文件: \(tempFileURL.path)")
            }
            
            // 保存文件内容到临时位置
            try fileContent.write(to: tempFileURL)
            print("成功将文件保存到临时位置: \(tempFileURL.path)")
            
            // 尝试用AVFoundation验证音频文件
            if validateAudioFile(at: tempFileURL) {
                print("音频文件验证通过")
            } else {
                print("警告: 音频文件验证失败，但继续处理")
            }
            
            // 调用代理方法通知文件上传成功
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.webServerManager(self!, didReceiveFile: tempFileURL, filename: filename, fileSize: fileContent.count, mimeType: mimeType)
                
                // 兼容旧代码，调用onFileReceived回调
                self?.onFileReceived?(tempFileURL, filename, fileContent.count, mimeType)
            }
            
            // 返回成功页面
            sendSuccessResponse(to: client, filename: filename, fileSize: fileContent.count)
            
        } catch {
            print("保存文件失败: \(error.localizedDescription)")
            
            // 清理临时文件
            try? FileManager.default.removeItem(at: tempFileURL)
            
            sendErrorResponse(to: client, errorMessage: "保存文件失败: \(error.localizedDescription)")
        }
    }
    
    /// 验证音频文件是否可以播放
    private func validateAudioFile(at fileURL: URL) -> Bool {
        // 这里应该使用AVFoundation来验证音频文件
        // 但为了避免导入过多依赖，这里只做简单检查
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            // 检查文件大小
            if let fileSize = attributes[.size] as? NSNumber {
                if fileSize.intValue < 1024 { // 小于1KB的文件可能不是有效音频
                    return false
                }
            }
            
            // 读取文件头部做简单验证
            let fileHandle = try FileHandle(forReadingFrom: fileURL)
            defer { fileHandle.closeFile() }
            
            guard let header = try? fileHandle.read(upToCount: 4) else {
                return false
            }
            
            // MP3文件通常以ID3标签或特定比特开头
            if header.count >= 3 {
                // 检查ID3标签
                if header.prefix(3) == Data("ID3".utf8) {
                    return true
                }
                
                // 检查MP3帧头部
                if header[0] == 0xFF && (header[1] & 0xE0) == 0xE0 {
                    return true
                }
            }
            
            // 未能识别为标准音频格式，但仍允许上传
            return true
            
        } catch {
            print("验证音频文件失败: \(error.localizedDescription)")
            return false
        }
    }
    
    /// 获取文件的MIME类型
    private func getMimeType(for filename: String) -> String {
        // 实现获取文件MIME类型的逻辑
        // 这里只是一个示例，实际实现需要根据文件扩展名来确定MIME类型
        switch filename.split(separator: ".").last {
        case "mp3":
            return "audio/mpeg"
        case "wav":
            return "audio/wav"
        case "m4a":
            return "audio/x-m4a"
        case "aac":
            return "audio/aac"
        case "flac":
            return "audio/flac"
        case "ogg":
            return "audio/ogg"
        default:
            return "application/octet-stream"
        }
    }
    
    /// 发送上传页面
    private func sendUploadPage(to clientSocket: Int32) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>音乐文件上传</title>
            <style>
                body { font-family: -apple-system, sans-serif; text-align: center; padding: 20px; max-width: 600px; margin: 0 auto; }
                h1 { margin-bottom: 20px; }
                .upload-form { background-color: #f9f9f9; border-radius: 10px; padding: 20px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
                .submit-button { background-color: #007aff; color: white; border: none; border-radius: 5px; padding: 10px 20px; 
                  font-size: 16px; margin-top: 15px; cursor: pointer; width: 100%; }
                .submit-button:disabled { background-color: #cccccc; }
                .note { margin-top: 15px; font-size: 14px; color: #666; }
                #file-list { text-align: left; margin-top: 20px; max-height: 300px; overflow-y: auto; 
                  border: 1px solid #ddd; border-radius: 5px; padding: 10px; background-color: white; }
                .file-item { padding: 8px 10px; margin-bottom: 5px; border-radius: 5px; background-color: #f0f0f0; 
                  display: flex; justify-content: space-between; align-items: center; }
                .file-name { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
                .file-size { margin-left: 10px; color: #666; font-size: 12px; }
                .remove-file { color: #ff3b30; cursor: pointer; margin-left: 10px; font-weight: bold; }
                .select-button { background-color: #007aff; color: white; border: none; border-radius: 5px; 
                  padding: 10px 20px; font-size: 16px; cursor: pointer; width: 100%; margin-bottom: 15px; }
                #file-input { display: none; }
                .empty-list { text-align: center; color: #999; padding: 20px 0; }
                #progress-container { display: none; margin-top: 15px; }
                #progress-bar { height: 10px; background-color: #007aff; width: 0%; border-radius: 5px; }
                #current-file, #upload-count { margin-top: 5px; font-size: 14px; }
            </style>
        </head>
        <body>
            <h1>音乐文件上传</h1>
            <div class="upload-form">
                <form method="post" enctype="multipart/form-data">
                    <input type="button" class="select-button" value="选择音乐文件" onclick="document.getElementById('file-input').click();">
                    <input type="file" id="file-input" name="file" multiple accept="audio/*" onchange="handleFiles(this.files)">
                    
                    <div id="file-list">
                        <div class="empty-list">暂无选择文件</div>
                    </div>
                    
                    <div id="progress-container">
                        <div id="progress-bar"></div>
                        <div id="current-file">正在上传：</div>
                        <div id="upload-count">0/0</div>
                    </div>
                    
                    <input type="button" class="submit-button" value="开始上传" id="upload-button" disabled onclick="startUpload()">
                </form>
                
                <div class="note">
                    支持的文件格式: MP3, WAV, AAC, M4A, FLAC, OGG<br>
                    单个文件最大大小: 500MB<br>
                    单次最多上传: 20首歌曲
                </div>
            </div>
            
            <script>
                var selectedFiles = [];
                var currentUploadIndex = 0;
                var isUploading = false;
                
                function handleFiles(files) {
                    if (files.length === 0) return;
                    
                    var addedCount = 0;
                    var skippedCount = 0;
                    
                    for (var i = 0; i < files.length; i++) {
                        // 检查是否超过20首限制
                        if (selectedFiles.length >= 20) {
                            skippedCount = files.length - i;
                            break;
                        }
                        
                        var file = files[i];
                        var exists = false;
                        
                        for (var j = 0; j < selectedFiles.length; j++) {
                            if (selectedFiles[j].name === file.name && selectedFiles[j].size === file.size) {
                                exists = true;
                                break;
                            }
                        }
                        
                        if (!exists) {
                            selectedFiles.push(file);
                            addedCount++;
                        }
                    }
                    
                    // 显示限制提示
                    if (skippedCount > 0) {
                        alert('最多只能选择20首歌曲，已跳过 ' + skippedCount + ' 个文件');
                    } else if (selectedFiles.length === 20 && addedCount > 0) {
                        alert('已达到最大文件数量限制（20首）');
                    }
                    
                    updateFileList();
                    document.getElementById('upload-button').disabled = (selectedFiles.length === 0);
                    document.getElementById('file-input').value = '';
                }
                
                function updateFileList() {
                    var fileList = document.getElementById('file-list');
                    
                    if (selectedFiles.length === 0) {
                        fileList.innerHTML = '<div class="empty-list">暂无选择文件</div>';
                        return;
                    }
                    
                    fileList.innerHTML = '';
                    
                    // 添加数量统计
                    var countInfo = document.createElement('div');
                    countInfo.style.cssText = 'text-align: center; padding: 8px; background-color: #e8f4fd; border-radius: 5px; margin-bottom: 10px; font-size: 14px;';
                    countInfo.innerHTML = '已选择 <strong>' + selectedFiles.length + '/20</strong> 首歌曲';
                    if (selectedFiles.length >= 20) {
                        countInfo.style.backgroundColor = '#ffe6e6';
                        countInfo.innerHTML += ' <span style="color: #ff3b30;">（已达上限）</span>';
                    }
                    fileList.appendChild(countInfo);
                    
                    for (var i = 0; i < selectedFiles.length; i++) {
                        var file = selectedFiles[i];
                        var fileItem = document.createElement('div');
                        fileItem.className = 'file-item';
                        
                        var fileName = document.createElement('div');
                        fileName.className = 'file-name';
                        fileName.textContent = file.name;
                        
                        var fileSize = document.createElement('div');
                        fileSize.className = 'file-size';
                        fileSize.textContent = formatFileSize(file.size);
                        
                        var removeButton = document.createElement('div');
                        removeButton.className = 'remove-file';
                        removeButton.textContent = '✕';
                        removeButton.onclick = (function(index) {
                            return function() {
                                selectedFiles.splice(index, 1);
                                updateFileList();
                                document.getElementById('upload-button').disabled = (selectedFiles.length === 0);
                            };
                        })(i);
                        
                        fileItem.appendChild(fileName);
                        fileItem.appendChild(fileSize);
                        fileItem.appendChild(removeButton);
                        fileList.appendChild(fileItem);
                    }
                }
                
                function formatFileSize(bytes) {
                    if (bytes < 1024) {
                        return bytes + ' B';
                    } else if (bytes < 1024 * 1024) {
                        return (bytes / 1024).toFixed(1) + ' KB';
                    } else {
                        return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
                    }
                }
                
                function startUpload() {
                    if (selectedFiles.length === 0 || isUploading) {
                        return;
                    }
                    
                    isUploading = true;
                    currentUploadIndex = 0;
                    document.getElementById('upload-button').disabled = true;
                    document.getElementById('progress-container').style.display = 'block';
                    document.getElementById('upload-count').textContent = '0/' + selectedFiles.length;
                    
                    uploadNextFile();
                }
                
                function uploadNextFile() {
                    if (currentUploadIndex >= selectedFiles.length) {
                        // 所有文件上传完成
                        isUploading = false;
                        document.getElementById('progress-container').style.display = 'none';
                        document.getElementById('upload-button').disabled = (selectedFiles.length === 0);
                        
                        if (selectedFiles.length === 0) {
                            alert('所有文件上传完成！');
                        }
                        return;
                    }
                    
                    var file = selectedFiles[currentUploadIndex];
                    document.getElementById('current-file').textContent = '正在上传：' + file.name;
                    document.getElementById('progress-bar').style.width = '0%';
                    
                    var formData = new FormData();
                    formData.append('file', file);
                    
                    var xhr = new XMLHttpRequest();
                    xhr.open('POST', window.location.href, true);
                    
                    xhr.upload.onprogress = function(e) {
                        if (e.lengthComputable) {
                            var percent = (e.loaded / e.total) * 100;
                            document.getElementById('progress-bar').style.width = percent + '%';
                        }
                    };
                    
                    xhr.onload = function() {
                        if (xhr.status >= 200 && xhr.status < 300) {
                            // 上传成功
                            selectedFiles.splice(currentUploadIndex, 1);
                            document.getElementById('upload-count').textContent = currentUploadIndex + '/' + 
                                (currentUploadIndex + selectedFiles.length);
                            updateFileList();
                            
                            // 延迟一秒后上传下一个文件
                            setTimeout(uploadNextFile, 1000);
                        } else {
                            // 上传失败
                            alert('上传失败: ' + file.name);
                            currentUploadIndex++;
                            uploadNextFile();
                        }
                    };
                    
                    xhr.onerror = function() {
                        alert('上传失败: ' + file.name);
                        currentUploadIndex++;
                        uploadNextFile();
                    };
                    
                    xhr.send(formData);
                }
            </script>
        </body>
        </html>
        """
        
        // 简化HTTP响应格式，确保正确处理
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        
        guard let data = response.data(using: .utf8) else {
            print("无法编码HTTP响应")
            return
        }
        
        // 一次性发送所有数据
        data.withUnsafeBytes { buffer in
            let result = send(clientSocket, buffer.baseAddress, buffer.count, 0)
            if result < 0 {
                print("发送HTTP响应失败: \(String(cString: strerror(errno)))")
            } else {
                print("发送了 \(result) 字节的响应数据")
            }
        }
    }
    
    /// 发送成功响应
    private func sendSuccessResponse(to clientSocket: Int32, filename: String, fileSize: Int) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>上传成功</title>
            <style>
                body { font-family: -apple-system, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f7; color: #1d1d1f; text-align: center; }
                .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 10px; padding: 30px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
                .success-icon { color: #34c759; font-size: 48px; margin-bottom: 20px; }
                h1 { color: #34c759; margin-bottom: 20px; }
                .file-name { padding: 10px; background-color: #f2f2f7; border-radius: 8px; word-break: break-all; margin: 15px 0; }
                .back-link { display: inline-block; background-color: #0071e3; color: white; text-decoration: none; padding: 12px 24px; 
                    border-radius: 8px; margin-top: 20px; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="success-icon">✓</div>
                <h1>上传成功</h1>
                <p>文件已成功上传到设备</p>
                <div class="file-name">\(filename)</div>
                <a href="/" class="back-link">继续上传</a>
            </div>
        </body>
        </html>
        """
        
        // 简化HTTP响应格式
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        
        guard let data = response.data(using: .utf8) else {
            print("无法编码HTTP响应")
            return
        }
        
        data.withUnsafeBytes { buffer in
            let result = send(clientSocket, buffer.baseAddress, buffer.count, 0)
            if result < 0 {
                print("发送HTTP响应失败: \(String(cString: strerror(errno)))")
            }
        }
    }
    
    /// 发送错误响应
    private func sendErrorResponse(to clientSocket: Int32, errorMessage: String) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>上传错误</title>
            <style>
                body { font-family: -apple-system, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f7; color: #1d1d1f; text-align: center; }
                .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 10px; padding: 30px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
                .error-icon { color: #ff3b30; font-size: 48px; margin-bottom: 20px; }
                h1 { color: #ff3b30; margin-bottom: 20px; }
                .error-message { padding: 10px; background-color: #ffeeee; border-radius: 8px; color: #cc0000; margin: 15px 0; }
                .back-link { display: inline-block; background-color: #0071e3; color: white; text-decoration: none; padding: 12px 24px; 
                    border-radius: 8px; margin-top: 20px; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="error-icon">✗</div>
                <h1>上传失败</h1>
                <p>处理您的请求时发生错误</p>
                <div class="error-message">\(errorMessage)</div>
                <a href="/" class="back-link">返回上传页面</a>
            </div>
        </body>
        </html>
        """
        
        // 简化HTTP响应格式
        let response = "HTTP/1.1 400 Bad Request\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        
        guard let data = response.data(using: .utf8) else {
            print("无法编码HTTP响应")
            return
        }
        
        data.withUnsafeBytes { buffer in
            let result = send(clientSocket, buffer.baseAddress, buffer.count, 0)
            if result < 0 {
                print("发送HTTP响应失败: \(String(cString: strerror(errno)))")
            }
        }
    }
    
    /// 发送CORS响应
    private func sendCORSResponse(to clientSocket: Int32) {
        // 简化CORS响应
        let response = "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: POST, GET, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        
        guard let data = response.data(using: .utf8) else {
            print("无法编码CORS响应")
            return
        }
        
        data.withUnsafeBytes { buffer in
            let result = send(clientSocket, buffer.baseAddress, buffer.count, 0)
            if result < 0 {
                print("发送CORS响应失败: \(String(cString: strerror(errno)))")
            }
        }
    }
    
    /// 获取本地IP地址
    private func getLocalIPAddress() -> String {
        var ipAddress = "127.0.0.1"
        
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else {
            return ipAddress
        }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let interface = ptr?.pointee,
                  interface.ifa_addr.pointee.sa_family == UInt8(AF_INET),
                  String(cString: interface.ifa_name) != "lo0" else {
                continue
            }
            
            // 转换为sockaddr_in结构
            var addr = interface.ifa_addr.pointee
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(&addr, socklen_t(interface.ifa_addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            
            if let addressString = String(validatingUTF8: hostname) {
                // 如果是192.168开头的地址，优先使用
                if addressString.hasPrefix("192.168") {
                    ipAddress = addressString
                    break
                }
                // 其次使用10.开头的地址
                else if addressString.hasPrefix("10.") && ipAddress == "127.0.0.1" {
                    ipAddress = addressString
                }
                // 再次使用172.16-31网段
                else if addressString.hasPrefix("172.") && ipAddress == "127.0.0.1" {
                    let parts = addressString.split(separator: ".")
                    if parts.count >= 2, let second = Int(parts[1]), second >= 16 && second <= 31 {
                        ipAddress = addressString
                    }
                }
                // 最后使用非回环地址
                else if addressString != "127.0.0.1" && ipAddress == "127.0.0.1" {
                    ipAddress = addressString
                }
            }
        }
        
        return ipAddress
    }
    
    /// 清理文件名
    private func sanitizeFilename(_ filename: String) -> String {
        // 移除非法字符
        var cleanName = filename
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "*", with: "_")
            .replacingOccurrences(of: "?", with: "_")
            .replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "<", with: "_")
            .replacingOccurrences(of: ">", with: "_")
            .replacingOccurrences(of: "|", with: "_")
        
        // 限制文件名长度
        let maxFilenameLength = 100
        if cleanName.count > maxFilenameLength {
            let startIndex = cleanName.startIndex
            let endIndex = cleanName.index(startIndex, offsetBy: maxFilenameLength - 10)
            let fileExtension = cleanName.fileExtension()
            cleanName = String(cleanName[startIndex..<endIndex]) + "..." + fileExtension
        }
        
        return cleanName
    }
    
    /// 直接以二进制方式解析multipart表单数据
    private func parseMultipartFormDataBinary(bodyData: Data, boundary: String) -> (filename: String, data: Data)? {
        print("开始解析multipart表单数据，boundary=\(boundary)，数据大小=\(bodyData.count)字节")
        
        // 如果数据太小，不可能是有效的multipart表单
        guard bodyData.count > boundary.count + 10 else {
            print("数据太小，无法包含有效的multipart表单")
            return nil
        }
        
        // 调试：打印前100个字节
        let debugSize = min(100, bodyData.count)
        let hexString = bodyData.prefix(debugSize).map { String(format: "%02x", $0) }.joined(separator: " ")
        print("表单数据前\(debugSize)字节: \(hexString)")
        
        // 尝试不同的边界格式
        let possibleBoundaryPrefixes = [
            "--\(boundary)",                // 标准格式
            boundary,                       // 无前缀
            "\r\n--\(boundary)",            // 带前导CRLF
            "\n--\(boundary)"               // 仅带前导LF
        ]
        
        var firstBoundaryRange: Range<Data.Index>? = nil
        var usedBoundaryPrefix = ""
        
        // 构建用于查找的数据
        let searchData: [Data] = possibleBoundaryPrefixes.compactMap { $0.data(using: .utf8) }
        
        // 查找第一个边界
        for (index, boundaryData) in searchData.enumerated() {
            if let range = bodyData.range(of: boundaryData) {
                firstBoundaryRange = range
                usedBoundaryPrefix = possibleBoundaryPrefixes[index]
                print("找到边界格式: \"\(usedBoundaryPrefix)\"，位置: \(range.lowerBound)")
                break
            }
        }
        
        // 如果找不到边界，放弃解析
        guard let firstBoundaryRange = firstBoundaryRange else {
            print("未找到任何边界格式！")
            return nil
        }
        
        // 构建其他边界形式
        let boundaryNext = "\r\n--\(boundary)" // 后续边界
        let endBoundary = "--\(boundary)--" // 结束边界
        
        guard let boundaryNextData = boundaryNext.data(using: .utf8),
              let endBoundaryData = endBoundary.data(using: .utf8),
              let headersEndData = "\r\n\r\n".data(using: .utf8) else {
            print("无法创建边界数据")
            return nil
        }
        
        // 查找头部结束位置
        let afterFirstBoundary = firstBoundaryRange.upperBound
        guard afterFirstBoundary < bodyData.endIndex,
              let headersEndRange = bodyData.range(of: headersEndData, options: [], in: afterFirstBoundary..<bodyData.endIndex) else {
            print("未找到头部结束标记")
            return nil
        }
        
        // 提取头部区域并转换为字符串分析
        let headersData = bodyData.subdata(in: afterFirstBoundary..<headersEndRange.lowerBound)
        guard let headersString = String(data: headersData, encoding: .utf8) else {
            print("无法将头部数据转换为字符串")
            return nil
        }
        
        print("头部数据: \(headersString)")
        
        // 从头部中提取文件名
        var filename = "unknown"
        if headersString.contains("filename=") {
            if let filenameRange = headersString.range(of: "filename=\""),
               let filenameEndRange = headersString[filenameRange.upperBound...].range(of: "\"") {
                filename = String(headersString[filenameRange.upperBound..<filenameEndRange.lowerBound])
                print("从头部提取的文件名: \(filename)")
            }
        } else {
            print("头部中未找到文件名")
            return nil
        }
        
        // 提取Content-Type
        var contentType = "application/octet-stream"
        if headersString.contains("Content-Type:") {
            if let contentTypeRange = headersString.range(of: "Content-Type:"),
               let contentTypeEndRange = headersString[contentTypeRange.upperBound...].range(of: "\r\n") {
                contentType = String(headersString[contentTypeRange.upperBound..<contentTypeEndRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                print("文件内容类型: \(contentType)")
            }
        }
        
        // 提取文件内容：从头部结束标记之后开始
        let contentStartIndex = headersEndRange.upperBound
        guard contentStartIndex < bodyData.endIndex else {
            print("内容起始位置超出数据范围")
            return nil
        }
        
        // 查找下一个边界或结束边界
        var contentEndIndex = bodyData.endIndex
        var foundEndingBoundary = false
        
        // 优先寻找结束边界，因为单个文件上传通常只有一个表单项
        if let endBoundaryRange = bodyData.range(of: endBoundaryData, in: contentStartIndex..<bodyData.endIndex) {
            contentEndIndex = endBoundaryRange.lowerBound
            foundEndingBoundary = true
            print("找到结束边界，位置: \(endBoundaryRange.lowerBound)")
        }
        // 如果找不到结束边界，寻找下一个普通边界
        else if let nextBoundaryRange = bodyData.range(of: boundaryNextData, in: contentStartIndex..<bodyData.endIndex) {
            contentEndIndex = nextBoundaryRange.lowerBound
            foundEndingBoundary = true
            print("找到下一个边界，位置: \(nextBoundaryRange.lowerBound)")
        }
        // 如果找不到任何边界，使用数据末尾作为结束位置
        else {
            print("未找到任何结束边界，使用数据末尾作为内容结束位置")
            
            // 确保提取最大可能的有效数据，但丢弃最后几个可能不完整的字节
            if bodyData.count > contentStartIndex + 1024 { // 至少有1KB数据
                // 如果数据很大（超过1MB），我们假设传输中断，只取一部分
                if bodyData.count - contentStartIndex > 1024 * 1024 {
                    let safeEndPosition = min(contentStartIndex + 1024 * 1024, bodyData.count - 4)
                    contentEndIndex = safeEndPosition
                    print("数据很大，可能是完整文件，使用前1MB作为内容: \(contentStartIndex) 到 \(safeEndPosition)")
                } else {
                    // 丢弃最后4个字节，防止包含不完整的Unicode字符或其他边界片段
                    contentEndIndex = bodyData.count - 4
                    print("数据可能接近完整，丢弃最后几个字节: \(contentStartIndex) 到 \(contentEndIndex)")
                }
            }
        }
        
        // 确保内容索引在有效范围内
        if contentEndIndex <= contentStartIndex {
            print("内容范围无效: \(contentStartIndex) 到 \(contentEndIndex)")
            return nil
        }
        
        // 提取内容
        let fileContent = bodyData.subdata(in: contentStartIndex..<contentEndIndex)
        
        // 检查数据是否符合声明的Content-Type
        let isConsistentWithContentType = validateFileContentType(fileContent, contentType: contentType)
        if !isConsistentWithContentType {
            print("警告: 文件内容与声明的类型不符，可能数据不完整或损坏")
        }
        
        // 检查数据完整性
        let integrityStatus = checkFileIntegrity(fileContent, fileName: filename)
        
        // 如果文件太小且没有找到结束边界，可能表示数据不完整
        if fileContent.count < 1024 && !foundEndingBoundary {
            print("警告: 提取的文件内容太小(\(fileContent.count)字节)且没有找到结束边界，可能数据不完整")
        }
        
        let sanitizedFilename = sanitizeFilename(filename)
        print("提取到文件内容，大小: \(fileContent.count) 字节，完整性检查: \(integrityStatus ? "通过" : "可能不完整")")
        
        // 返回清理过的文件名和内容
        return (sanitizedFilename, fileContent)
    }
    
    /// 检查文件内容类型是否与声明一致
    private func validateFileContentType(_ fileData: Data, contentType: String) -> Bool {
        // 简单的文件签名验证
        if contentType.contains("audio/mpeg") || contentType.contains("mp3") {
            // MP3通常以"ID3"或特定比特开头
            if fileData.count >= 3 {
                let header = fileData.prefix(3)
                if header.elementsEqual("ID3".data(using: .utf8)!) {
                    return true
                }
                
                // 或者以0xFF开头
                if fileData[0] == 0xFF && (fileData[1] & 0xE0) == 0xE0 {
                    return true
                }
            }
        }
        
        // 对于小文件片段，我们无法确定，默认认为有效
        return fileData.count < 1024 ? true : false
    }
    
    /// 检查文件数据完整性
    private func checkFileIntegrity(_ fileData: Data, fileName: String) -> Bool {
        // 检查文件是否至少有合理大小
        if fileData.count < 100 {
            return false
        }
        
        // 针对MP3文件的特殊验证
        if fileName.lowercased().hasSuffix(".mp3") {
            // 假设3.9MB的文件至少应该有1MB
            if fileData.count < 1024 * 1024 {
                print("MP3文件太小，可能不完整")
                return false
            }
        }
        
        // 默认情况
        return true
    }
}

/// String扩展，添加文件扩展名获取功能
extension String {
    /// 获取文件扩展名
    func fileExtension() -> String {
        guard let lastDotIndex = self.lastIndex(of: ".") else {
            return ""
        }
        
        let afterDot = self.index(after: lastDotIndex)
        return String(self[afterDot...])
    }
}

/// 从原始请求头解析HTTP头部字段
private func parseHTTPHeaders(_ rawHeaders: String) -> [String: String] {
    var headers = [String: String]()
    let headerLines = rawHeaders.components(separatedBy: "\r\n")
    
    // 跳过第一行(请求行)
    for i in 1..<headerLines.count {
        let line = headerLines[i]
        if line.isEmpty { continue }
        
        if let colonIndex = line.firstIndex(of: ":") {
            let headerName = line[..<colonIndex].trimmingCharacters(in: .whitespaces)
            let headerValue = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            headers[headerName] = headerValue
        }
    }
    
    return headers
}









