import SwiftUI
import Foundation
import Network

struct LANImportView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var musicLibrary = MusicLibrary.shared
    @ObservedObject private var musicFileManager = MusicFileManager.shared
    
    // WebServer管理器
    @StateObject private var webServerManager = WebServerManager()
    
    // 状态变量
    @State private var showingQRCode = false
    @State private var serverURL: String = ""
    @State private var isServerRunning = false
    @State private var receivedFiles: [ReceivedFile] = []
    @State private var importResults: [(filename: String, success: Bool)] = []
    @State private var showImportResults = false
    @State private var importInProgress = false
    @State private var localFileURLs: [URL] = []
    @State private var isShowingSuccessAlert = false
    @State private var errorMessage: String?
    @State private var isShowingErrorAlert = false
    @State private var selectedFiles: Set<UUID> = []
    @State private var isShowingDuplicateAlert = false
    @State private var currentDuplicateFile: ReceivedFile? = nil
    @State private var existingSong: Song? = nil
    @State private var pendingImportFiles: [ReceivedFile] = []
    @State private var currentProcessingIndex = 0
    @State private var showingExitConfirmation = false
    
    var body: some View {
        VStack {
            // 顶部标题区域
            Text("局域网导入")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top)
            
            if isServerRunning {
                // 服务器运行状态
                serverStatusView
                    .padding()
                
                // 接收到的文件列表
                receivedFilesListView
                
                Spacer()
                
                // 底部按钮区域
                bottomButtonsView
            } else {
                // 服务器未运行状态
                VStack(spacing: 30) {
                    Spacer()
                    
                    Image(systemName: "wifi")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("局域网导入功能")
                        .font(.headline)
                    
                    Text("启动后将创建一个临时网页，您可以通过其他设备访问该网页上传音乐文件")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 30)
                    
                    Spacer()
                    
                    // 启动服务器按钮
                    Button(action: {
                        startServer()
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("启动服务")
                        }
                        .frame(minWidth: 200)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    
                    Spacer()
                }
                .padding()
            }
        }
        .navigationTitle("局域网导入")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("返回") {
                    // 如果服务器正在运行，显示退出确认
                    if isServerRunning {
                        showingExitConfirmation = true
                    } else {
                        dismiss()
                    }
                }
            }
            
            if isServerRunning {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingQRCode = true
                    }) {
                        Image(systemName: "qrcode")
                    }
                }
            }
        }
        .onAppear {
            // 初始化WebServer
            initializeServer()
        }
        .onDisappear {
            // 确保在视图消失时停止服务器
            if isServerRunning {
                webServerManager.stopServer()
            }
        }
        .sheet(isPresented: $showingQRCode) {
            QRCodeView(url: serverURL)
        }
        .alert("确认退出", isPresented: $showingExitConfirmation) {
            Button("取消", role: .cancel) {}
            Button("退出", role: .destructive) {
                webServerManager.stopServer()
                isServerRunning = false
                dismiss()
            }
        } message: {
            Text("退出后局域网导入服务将停止，其他设备将无法继续上传文件。确定要退出吗？")
        }
        .alert(isPresented: $showImportResults) {
            Alert(
                title: Text("导入结果"),
                message: Text(formattedImportResults),
                dismissButton: .default(Text("确定"))
            )
        }
        .alert(isPresented: $isShowingSuccessAlert) {
            Alert(
                title: Text("导入成功"),
                message: Text(errorMessage ?? ""),
                dismissButton: .default(Text("确定"))
            )
        }
        .alert(isPresented: $isShowingErrorAlert) {
            Alert(
                title: Text("导入失败"),
                message: Text(errorMessage ?? ""),
                dismissButton: .default(Text("确定"))
            )
        }
        .alert(isPresented: $isShowingDuplicateAlert) {
            Alert(
                title: Text("歌曲可能已存在"),
                message: Text("文件 \"\(currentDuplicateFile?.name ?? "")\" 与已有歌曲 \"\(existingSong?.title ?? "")\" (\(existingSong?.artist ?? "")) 似乎重复。是否仍要导入？"),
                primaryButton: .default(Text("继续导入")) {
                    if let file = currentDuplicateFile {
                        importFile(file, forcedImport: true)
                    } else {
                        // 如果无法获取当前文件，继续下一个
                        currentProcessingIndex += 1
                        processNextFile()
                    }
                },
                secondaryButton: .cancel(Text("跳过")) {
                    // 跳过当前文件，将其标记为已导入
                    if let file = currentDuplicateFile, let index = receivedFiles.firstIndex(where: { $0.id == file.id }) {
                        importResults.append((filename: file.name, success: true))
                        receivedFiles[index].status = .imported
                    }
                    
                    // 继续处理下一个文件
                    currentProcessingIndex += 1
                    processNextFile()
                }
            )
        }
    }
    
    // 服务器状态视图
    private var serverStatusView: some View {
        VStack(spacing: 15) {
            Text("服务器已启动")
                .font(.headline)
                .foregroundColor(.green)
            
            HStack {
                Text("访问地址：")
                    .font(.subheadline)
                
                Text(serverURL)
                    .font(.system(size: 16, weight: .medium))
                    .padding(8)
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(5)
            }
            
            Text("在同一网络下的设备可以访问此地址上传音乐文件")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: {
                // 复制到剪贴板
                UIPasteboard.general.string = serverURL
            }) {
                HStack {
                    Image(systemName: "doc.on.doc")
                    Text("复制链接")
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(8)
            }
            
            Button(action: {
                showingQRCode = true
            }) {
                HStack {
                    Image(systemName: "qrcode")
                    Text("显示二维码")
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(8)
            }
        }
    }
    
    // 接收到的文件列表视图
    private var receivedFilesListView: some View {
        VStack(alignment: .leading) {
            if receivedFiles.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("等待文件上传...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .background(Color(UIColor.systemGray6).opacity(0.3))
                .cornerRadius(10)
                .padding()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("已接收文件")
                            .font(.headline)
                        
                        Spacer()
                        
                        Button(action: {
                            // 全选/全不选
                            if selectedFiles.count == receivedFiles.count {
                                selectedFiles.removeAll()
                            } else {
                                selectedFiles = Set(receivedFiles.map { $0.id })
                            }
                        }) {
                            Text(selectedFiles.count == receivedFiles.count ? "全不选" : "全选")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        
                        Text("\(receivedFiles.count)个文件")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(receivedFiles.indices, id: \.self) { index in
                                ReceivedFileRow(
                                    file: receivedFiles[index],
                                    isSelected: Binding(
                                        get: { selectedFiles.contains(receivedFiles[index].id) },
                                        set: { newValue in
                                            if newValue {
                                                selectedFiles.insert(receivedFiles[index].id)
                                            } else {
                                                selectedFiles.remove(receivedFiles[index].id)
                                            }
                                        }
                                    )
                                )
                                .padding(.vertical, 8)
                                .padding(.horizontal)
                                .background(Color(UIColor.systemBackground))
                                
                                Divider()
                                    .padding(.horizontal)
                            }
                        }
                    }
                    .background(Color(UIColor.systemGray6).opacity(0.3))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }
            }
        }
    }
    
    // 底部按钮视图
    private var bottomButtonsView: some View {
        VStack {
            Divider()
            
            HStack {
                // 停止服务器
                Button(action: {
                    stopServer()
                }) {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text("停止服务")
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red)
                    .cornerRadius(8)
                }
                
                Spacer()
                
                // 导入接收到的文件
                Button(action: {
                    importFiles()
                }) {
                    if importInProgress {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                            Text("导入中...")
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    } else {
                        HStack {
                            Image(systemName: "arrow.down.doc")
                            let selectedCount = selectedFiles.count
                            Text("导入\(selectedCount)个文件")
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(selectedFiles.isEmpty ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                }
                .disabled(selectedFiles.isEmpty || importInProgress)
            }
            .padding()
        }
        .background(Color(UIColor.systemBackground))
    }
    
    // 格式化导入结果
    private var formattedImportResults: String {
        let total = importResults.count
        let successful = importResults.filter { $0.success }.count
        let failed = total - successful
        
        var message = "共\(total)个文件，成功\(successful)个，失败\(failed)个\n\n"
        
        if failed > 0 {
            let failedFiles = importResults.filter { !$0.success }.map { $0.filename }
            message += "导入失败的文件：\n" + failedFiles.joined(separator: "\n")
        }
        
        return message
    }
    
    // 初始化WebServer
    private func initializeServer() {
        // 设置接收文件的处理闭包 - 清空此处实现，避免重复添加文件
        // 现在我们完全依赖WebServerManagerDelegate来处理文件上传
        webServerManager.onFileReceived = nil
        
        // 为显示增强型上传页面，不做其他更改
        UserDefaults.standard.set(false, forKey: "useEnhancedUploadPage")
    }
    
    // 启动服务器
    private func startServer() {
        // 启动WebServer
        let ipAddress = webServerManager.startServer(delegate: self)
        serverURL = "http://\(ipAddress):8080"
        isServerRunning = true
        print("服务器已启动: \(serverURL)")
    }
    
    // 导入接收到的文件
    private func importFiles() {
        // 过滤出选中的文件
        let filesToImport = receivedFiles.filter { selectedFiles.contains($0.id) }
        
        guard !filesToImport.isEmpty else { 
            // 没有选中任何文件，显示提示
            errorMessage = "请至少选择一个要导入的文件"
            isShowingErrorAlert = true
            return 
        }
        
        // 重置进度状态
        pendingImportFiles = filesToImport
        currentProcessingIndex = 0
        
        // 开始处理第一个文件
        processNextFile()
    }
    
    // 处理下一个文件
    private func processNextFile() {
        // 检查是否已处理完所有文件
        if currentProcessingIndex >= selectedFiles.count || selectedFiles.isEmpty {
            print("所有选中的文件处理完毕，导入结果: 成功\(importResults.filter { $0.success }.count)个，失败\(importResults.filter { !$0.success }.count)个")
            
            // 设置状态指示完成
            showImportResults = true
            importInProgress = false
            
            // 计算成功导入的数量
            let successCount = importResults.filter { $0.success }.count
            print("导入完成: \(successCount)/\(importResults.count) 个文件成功")
            
            // 震动通知用户导入完成
            let generator = UINotificationFeedbackGenerator()
            if successCount == importResults.count {
                generator.notificationOccurred(.success)
            } else if successCount > 0 {
                generator.notificationOccurred(.warning)
            } else {
                generator.notificationOccurred(.error)
            }
            
            // 清理导入成功的临时文件
            if successCount > 0 {
                // 1. 获取所有成功导入的文件名
                let successfulFiles = self.importResults.filter { $0.success }.map { $0.filename }
                
                // 2. 找出对应的文件ID
                let successfulFileIDs = self.receivedFiles
                    .filter { file in successfulFiles.contains(file.name) && file.status == .imported }
                    .map { $0.id }
                
                // 3. 清理临时文件
                for fileID in successfulFileIDs {
                    if let index = self.receivedFiles.firstIndex(where: { $0.id == fileID }) {
                        let fileURL = self.receivedFiles[index].url
                        if let urlIndex = self.localFileURLs.firstIndex(of: fileURL) {
                            try? FileManager.default.removeItem(at: fileURL)
                            self.localFileURLs.remove(at: urlIndex)
                        }
                    }
                }
                
                // 4. 从选中文件集合中移除
                for fileID in successfulFileIDs {
                    self.selectedFiles.remove(fileID)
                }
                
                // 5. 从接收文件列表中移除
                self.receivedFiles.removeAll { file in
                    successfulFileIDs.contains(file.id)
                }
                
                print("已清理 \(successfulFileIDs.count) 个成功导入的文件")
                
                // 6. 使用延迟加载音乐库，确保所有文件都被正确处理
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    print("开始刷新音乐库以加载所有导入的歌曲...")
                    self.musicLibrary.loadLocalMusic()
                    
                    // 再次延迟检查是否所有歌曲都已加载
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        print("再次刷新音乐库以确保所有歌曲已加载完成...")
                        self.musicLibrary.loadLocalMusic()
                        
                        // 第三次延迟加载，以确保所有文件都被正确处理
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            print("第三次刷新音乐库以确保所有歌曲已完全加载...")
                            self.musicLibrary.loadLocalMusic()
                        }
                    }
                }
            } else {
                // 即使没有成功导入，也刷新一次以确保UI更新
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.musicLibrary.loadLocalMusic()
                }
            }
            
            return
        }
        
        // 获取当前要处理的文件
        let currentFile = pendingImportFiles[currentProcessingIndex]
        
        // 更新文件状态为导入中
        if let index = receivedFiles.firstIndex(where: { $0.id == currentFile.id }) {
            receivedFiles[index].status = .importing
        }
        
        // 异步检查文件是否已存在
        musicFileManager.checkIfSongExists(url: currentFile.url) { exists, existingSong in
            DispatchQueue.main.async {
                if exists {
                    // 找到了重复的歌曲，显示提示
                    self.currentDuplicateFile = currentFile
                    self.existingSong = existingSong
                    self.isShowingDuplicateAlert = true
                } else {
                    // 没有重复，直接导入
                    self.importFile(currentFile, forcedImport: false)
                }
            }
        }
    }
    
    // 导入单个文件
    private func importFile(_ file: ReceivedFile, forcedImport: Bool) {
        importInProgress = true
        
        if let fileIndex = receivedFiles.firstIndex(where: { $0.id == file.id }) {
            print("准备导入文件: \(file.name), URL: \(file.url.path)")
            
            // 检查是否是支持的音频文件
            if musicFileManager.isSupportedAudioFile(url: file.url) {
                print("文件类型支持，开始导入: \(file.name)")
                
                // 导入音乐文件，传递forcedImport参数
                musicFileManager.importMusicFile(from: file.url, forcedImport: forcedImport) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let song):
                            print("成功导入歌曲: \(song.title) - \(song.artist), 路径: \(song.filePath)")
                            self.importResults.append((filename: file.name, success: true))
                            self.receivedFiles[fileIndex].status = .imported
                            
                            // 不在每首歌导入后立即刷新音乐库，而是等待所有导入完成后再一次性刷新
                            // self.musicLibrary.loadLocalMusic()
                        case .failure(let error):
                            print("导入失败: \(file.name), 错误: \(error.localizedDescription)")
                            self.importResults.append((filename: file.name, success: false))
                            self.receivedFiles[fileIndex].status = .failed
                        }
                        
                        // 继续处理下一个文件
                        self.currentProcessingIndex += 1
                        self.processNextFile()
                    }
                }
            } else {
                // 使用现有的格式检测和修复逻辑
                // ... existing complex format detection code ...
                print("不支持的文件类型或扩展名有问题: \(file.name), 扩展名: \(file.url.pathExtension)")
                
                // 尝试通过检查文件格式来强制导入
                if let fileData = try? Data(contentsOf: file.url) {
                    let fileExtension = detectAudioType(from: fileData)
                    
                    if !fileExtension.isEmpty {
                        print("检测到文件实际格式为: \(fileExtension)，尝试改名后导入")
                        
                        // 创建临时文件，保存为正确的扩展名
                        let tempDir = FileManager.default.temporaryDirectory
                        let fileNameWithoutExt = file.url.deletingPathExtension().lastPathComponent
                        let newFileName = "\(fileNameWithoutExt).\(fileExtension)"
                        let newFileURL = tempDir.appendingPathComponent(newFileName)
                        
                        do {
                            try fileData.write(to: newFileURL)
                            print("已创建临时文件: \(newFileURL.path)")
                            
                            // 尝试导入新文件，传递forcedImport参数
                            musicFileManager.importMusicFile(from: newFileURL, forcedImport: forcedImport) { result in
                                DispatchQueue.main.async {
                                    switch result {
                                    case .success(let song):
                                        print("强制导入成功: \(song.title)")
                                        self.importResults.append((filename: file.name, success: true))
                                        self.receivedFiles[fileIndex].status = .imported
                                        
                                        // 确保MusicLibrary刷新
                                        self.musicLibrary.loadLocalMusic()
                                        
                                        // 继续处理下一个文件
                                        self.currentProcessingIndex += 1
                                        self.processNextFile()
                                    case .failure(let error):
                                        print("强制导入失败: \(error.localizedDescription)")
                                        
                                        // 尝试读取并提取音频元数据
                                        if let audioData = self.extractAudioData(from: fileData, fileExtension: fileExtension) {
                                            let finalFileName = "\(UUID().uuidString).\(fileExtension)"
                                            let finalFileURL = tempDir.appendingPathComponent(finalFileName)
                                            
                                            do {
                                                try audioData.write(to: finalFileURL)
                                                print("尝试最终修复后导入: \(finalFileURL.path)")
                                                
                                                self.musicFileManager.importMusicFile(from: finalFileURL, forcedImport: forcedImport) { finalResult in
                                                    DispatchQueue.main.async {
                                                        switch finalResult {
                                                        case .success(let song):
                                                            print("修复后导入成功: \(song.title)")
                                                            self.importResults.append((filename: file.name, success: true))
                                                            self.receivedFiles[fileIndex].status = .imported
                                                            self.musicLibrary.loadLocalMusic()
                                                        case .failure(let finalError):
                                                            print("修复后导入仍然失败: \(finalError)")
                                                            self.importResults.append((filename: file.name, success: false))
                                                            self.receivedFiles[fileIndex].status = .failed
                                                        }
                                                        // 清理临时文件
                                                        try? FileManager.default.removeItem(at: finalFileURL)
                                                        
                                                        // 继续处理下一个文件
                                                        self.currentProcessingIndex += 1
                                                        self.processNextFile()
                                                    }
                                                }
                                            } catch {
                                                print("写入修复文件失败: \(error)")
                                                self.importResults.append((filename: file.name, success: false))
                                                self.receivedFiles[fileIndex].status = .failed
                                                
                                                // 继续处理下一个文件
                                                self.currentProcessingIndex += 1
                                                self.processNextFile()
                                            }
                                        } else {
                                            // 无法修复文件
                                            self.importResults.append((filename: file.name, success: false))
                                            self.receivedFiles[fileIndex].status = .failed
                                            
                                            // 继续处理下一个文件
                                            self.currentProcessingIndex += 1
                                            self.processNextFile()
                                        }
                                    }
                                    
                                    // 清理临时文件
                                    try? FileManager.default.removeItem(at: newFileURL)
                                }
                            }
                        } catch {
                            print("创建临时文件失败: \(error)")
                            DispatchQueue.main.async {
                                self.importResults.append((filename: file.name, success: false))
                                self.receivedFiles[fileIndex].status = .failed
                                
                                // 继续处理下一个文件
                                self.currentProcessingIndex += 1
                                self.processNextFile()
                            }
                        }
                    } else {
                        // 无法识别文件类型
                        DispatchQueue.main.async {
                            self.importResults.append((filename: file.name, success: false))
                            self.receivedFiles[fileIndex].status = .failed
                            
                            // 继续处理下一个文件
                            self.currentProcessingIndex += 1
                            self.processNextFile()
                        }
                    }
                } else {
                    // 无法读取文件数据
                    DispatchQueue.main.async {
                        self.importResults.append((filename: file.name, success: false))
                        self.receivedFiles[fileIndex].status = .failed
                        
                        // 继续处理下一个文件
                        self.currentProcessingIndex += 1
                        self.processNextFile()
                    }
                }
            }
        } else {
            // 未找到文件索引，跳过
            self.currentProcessingIndex += 1
            self.processNextFile()
        }
    }
    
    // 提取音频数据（尝试修复损坏的文件）
    private func extractAudioData(from data: Data, fileExtension: String) -> Data? {
        switch fileExtension {
        case "mp3":
            return extractMP3Data(from: data)
        case "wav":
            return extractWAVData(from: data)
        case "m4a", "aac":
            return extractM4AData(from: data)
        case "flac":
            return extractFLACData(from: data)
        case "ogg":
            return extractOGGData(from: data)
        default:
            return nil
        }
    }
    
    // 提取MP3数据
    private func extractMP3Data(from data: Data) -> Data? {
        // 寻找ID3标记或MP3帧头
        if data.count < 10 { return nil }
        
        // 查找ID3v2标记
        if data.prefix(3) == Data([0x49, 0x44, 0x33]) {
            // ID3v2标记存在，找到其长度并跳过
            if data.count > 10 {
                let size1 = Int(data[6])
                let size2 = Int(data[7])
                let size3 = Int(data[8])
                let size4 = Int(data[9])
                
                // ID3标签大小（不包括头部的10个字节）
                let tagSize = ((size1 & 0x7F) << 21) | ((size2 & 0x7F) << 14) | ((size3 & 0x7F) << 7) | (size4 & 0x7F)
                let headerSize = 10 + tagSize
                
                if data.count > headerSize {
                    return data.subdata(in: headerSize..<data.count)
                }
            }
        }
        
        // 查找MP3帧头部
        for i in 0..<min(data.count - 4, 5000) {
            if data[i] == 0xFF && (data[i+1] & 0xE0) == 0xE0 {
                return data.subdata(in: i..<data.count)
            }
        }
        
        return data  // 无法找到正确的起始位置，返回原始数据
    }
    
    // 提取WAV数据
    private func extractWAVData(from data: Data) -> Data? {
        // WAV文件应该以"RIFF"开头
        if data.count > 12 && data.prefix(4) == Data([0x52, 0x49, 0x46, 0x46]) {
            return data
        }
        
        // 查找"RIFF"标记
        for i in 0..<min(data.count - 12, 1000) {
            if data[i] == 0x52 && data[i+1] == 0x49 && data[i+2] == 0x46 && data[i+3] == 0x46 &&
               data[i+8] == 0x57 && data[i+9] == 0x41 && data[i+10] == 0x56 && data[i+11] == 0x45 {
                return data.subdata(in: i..<data.count)
            }
        }
        
        return nil  // 无法找到WAV头部
    }
    
    // 提取M4A/AAC数据
    private func extractM4AData(from data: Data) -> Data? {
        // 简单返回原始数据，因为AAC/M4A结构较复杂
        return data
    }
    
    // 提取FLAC数据
    private func extractFLACData(from data: Data) -> Data? {
        // FLAC文件应该以"fLaC"开头
        if data.count > 4 && data.prefix(4) == Data([0x66, 0x4C, 0x61, 0x43]) {
            return data
        }
        
        // 查找"fLaC"标记
        for i in 0..<min(data.count - 4, 1000) {
            if data[i] == 0x66 && data[i+1] == 0x4C && data[i+2] == 0x61 && data[i+3] == 0x43 {
                return data.subdata(in: i..<data.count)
            }
        }
        
        return nil  // 无法找到FLAC头部
    }
    
    // 提取OGG数据
    private func extractOGGData(from data: Data) -> Data? {
        // OGG文件应该以"OggS"开头
        if data.count > 4 && data.prefix(4) == Data([0x4F, 0x67, 0x67, 0x53]) {
            return data
        }
        
        // 查找"OggS"标记
        for i in 0..<min(data.count - 4, 1000) {
            if data[i] == 0x4F && data[i+1] == 0x67 && data[i+2] == 0x67 && data[i+3] == 0x53 {
                return data.subdata(in: i..<data.count)
            }
        }
        
        return nil  // 无法找到OGG头部
    }
    
    // 检测音频文件类型
    private func detectAudioType(from data: Data) -> String {
        // 检查文件头部特征以识别文件类型
        if data.count < 12 {
            return ""
        }
        
        // MP3: 0xFF 0xFB 或 ID3头部
        if data.count > 2 && ((data[0] == 0xFF && (data[1] == 0xFB || data[1] == 0xF3 || data[1] == 0xF2)) ||
                             (data[0] == 0x49 && data[1] == 0x44 && data[2] == 0x33)) {
                return "mp3"
        }
        
        // 搜索整个文件前部分进行更深入检测
        for i in 0..<min(data.count - 2, 4096) {
            if data[i] == 0xFF && (data[i+1] & 0xE0) == 0xE0 {
                // 可能是MP3帧头
                return "mp3"
            }
        }
        
        // WAV: RIFF....WAVE
        if data.count > 12 && data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x46 &&
           data[8] == 0x57 && data[9] == 0x41 && data[10] == 0x56 && data[11] == 0x45 {
            return "wav"
        }
        
        // 搜索WAV头
        for i in 0..<min(data.count - 12, 4096) {
            if data[i] == 0x52 && data[i+1] == 0x49 && data[i+2] == 0x46 && data[i+3] == 0x46 &&
               (i+11 < data.count) && data[i+8] == 0x57 && data[i+9] == 0x41 && data[i+10] == 0x56 && data[i+11] == 0x45 {
                return "wav"
            }
        }
        
        // FLAC: fLaC
        if data.count > 4 && data[0] == 0x66 && data[1] == 0x4C && data[2] == 0x61 && data[3] == 0x43 {
            return "flac"
        }
        
        // 搜索FLAC头
        for i in 0..<min(data.count - 4, 4096) {
            if data[i] == 0x66 && data[i+1] == 0x4C && data[i+2] == 0x61 && data[i+3] == 0x43 {
                return "flac"
            }
        }
        
        // AAC: ADIF头部
        if data.count > 4 && data[0] == 0x41 && data[1] == 0x44 && data[2] == 0x49 && data[3] == 0x46 {
            return "aac"
        }
        
        // M4A/AAC: ftyp
        if data.count > 12 && data[4] == 0x66 && data[5] == 0x74 && data[6] == 0x79 && data[7] == 0x70 {
            return "m4a"
        }
        
        // OGG: OggS
        if data.count > 4 && data[0] == 0x4F && data[1] == 0x67 && data[2] == 0x67 && data[3] == 0x53 {
            return "ogg"
        }
        
        // 搜索OGG头
        for i in 0..<min(data.count - 4, 4096) {
            if data[i] == 0x4F && data[i+1] == 0x67 && data[i+2] == 0x67 && data[i+3] == 0x53 {
                return "ogg"
            }
        }
        
        // 对于不确定的文件，尝试以扩展名和MIME类型推测
        return "mp3"  // 默认为mp3，因为它是最常见的格式
    }
    
    // 停止服务器
    private func stopServer() {
        webServerManager.stopServer()
        isServerRunning = false
        
        // 清理临时文件
        for url in localFileURLs {
            try? FileManager.default.removeItem(at: url)
        }
        localFileURLs = []
    }
}

// 导入状态枚举
enum ImportStatus {
    case received    // 已接收
    case importing   // 导入中
    case imported    // 已导入
    case failed      // 导入失败
    
    var color: Color {
        switch self {
        case .received:
            return .blue
        case .importing:
            return .orange
        case .imported:
            return .green
        case .failed:
            return .red
        }
    }
    
    var icon: String {
        switch self {
        case .received:
            return "doc.badge.arrow.down"
        case .importing:
            return "arrow.clockwise"
        case .imported:
            return "checkmark.circle"
        case .failed:
            return "xmark.circle"
        }
    }
    
    var description: String {
        switch self {
        case .received:
            return "已接收"
        case .importing:
            return "导入中"
        case .imported:
            return "已导入"
        case .failed:
            return "导入失败"
        }
    }
}

// 接收到的文件结构
struct ReceivedFile: Identifiable {
    let id: UUID
    let url: URL
    let name: String
    let size: Int
    let dateReceived: Date
    var status: ImportStatus = .received
    var isSelected: Bool = true
}

// 接收到的文件行视图
struct ReceivedFileRow: View {
    let file: ReceivedFile
    @Binding var isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // 选择框
            Toggle("", isOn: $isSelected)
                .labelsHidden()
                .toggleStyle(CheckboxToggleStyle())
            
            // 文件图标
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(getFileIconColor(file.name))
                    .opacity(0.2)
                    .frame(width: 42, height: 42)
                
                Image(systemName: getFileIcon(file.name))
                    .font(.system(size: 20))
                    .foregroundColor(getFileIconColor(file.name))
            }
            
            // 文件信息
            VStack(alignment: .leading, spacing: 4) {
                Text(file.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(formatFileSize(file.size))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                    
                    Text(formatDate(file.dateReceived))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // 文件状态
            statusView
        }
    }
    
    // 状态视图
    private var statusView: some View {
        HStack(spacing: 4) {
            if file.status == .importing {
                ProgressView()
                    .scaleEffect(0.7)
                    .padding(.trailing, 2)
            } else {
                Image(systemName: file.status.icon)
                    .font(.system(size: 12))
                    .foregroundColor(file.status.color)
            }
            
            Text(file.status.description)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(file.status.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(file.status.color.opacity(0.1))
        .cornerRadius(6)
    }
    
    // 获取文件图标
    private func getFileIcon(_ fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        
        switch ext {
        case "mp3":
            return "music.note"
        case "wav":
            return "waveform"
        case "flac":
            return "music.note.list"
        case "m4a", "aac":
            return "music.quarternote.3"
        case "ogg":
            return "music.mic"
        default:
            return "doc.music"
        }
    }
    
    // 获取文件图标颜色
    private func getFileIconColor(_ fileName: String) -> Color {
        let ext = (fileName as NSString).pathExtension.lowercased()
        
        switch ext {
        case "mp3":
            return .blue
        case "wav":
            return .green
        case "flac":
            return .purple
        case "m4a", "aac":
            return .orange
        case "ogg":
            return .pink
        default:
            return .gray
        }
    }
    
    // 格式化文件大小
    private func formatFileSize(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024.0
        
        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        } else {
            let mb = kb / 1024.0
            return String(format: "%.1f MB", mb)
        }
    }
    
    // 格式化日期
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// 二维码视图
struct QRCodeView: View {
    let url: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 30) {
            Text("扫描二维码")
                .font(.headline)
            
            if let qrImage = generateQRCode(from: url) {
                Image(uiImage: qrImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 250, height: 250)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(10)
                    .shadow(radius: 3)
            } else {
                Text("无法生成二维码")
                    .foregroundColor(.red)
            }
            
            Text(url)
                .font(.system(size: 16))
                .padding()
                .background(Color(UIColor.systemGray6))
                .cornerRadius(8)
            
            Text("使用其他设备的相机扫描此二维码上传音乐文件")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("关闭") {
                dismiss()
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
            .padding(.top)
        }
        .padding()
    }
    
    // 生成二维码
    private func generateQRCode(from string: String) -> UIImage? {
        let data = string.data(using: .utf8)
        
        if let filter = CIFilter(name: "CIQRCodeGenerator") {
            filter.setValue(data, forKey: "inputMessage")
            // 设置纠错级别
            filter.setValue("H", forKey: "inputCorrectionLevel")
            
            if let qrCodeImage = filter.outputImage {
                // 放大二维码
                let transform = CGAffineTransform(scaleX: 10, y: 10)
                let scaledQRImage = qrCodeImage.transformed(by: transform)
                
                if let context = CIContext().createCGImage(scaledQRImage, from: scaledQRImage.extent) {
                    return UIImage(cgImage: context)
                }
            }
        }
        
        return nil
    }
}

extension LANImportView: WebServerManagerDelegate {
    func webServerManager(_ manager: WebServerManager, didReceiveFile fileURL: URL, filename: String, fileSize: Int, mimeType: String) {
        print("接收到文件: \(filename), 大小: \(fileSize) 字节")
        
        // 创建一个新的接收文件记录
        let newFile = ReceivedFile(
            id: UUID(),
            url: fileURL,
            name: filename,
            size: fileSize,
            dateReceived: Date(),
            isSelected: true
        )
        
        // 添加到接收文件列表
        DispatchQueue.main.async {
            // 检查是否已存在相同名称的文件
            let existingIndex = self.receivedFiles.firstIndex { $0.name == filename }
            if let index = existingIndex {
                // 替换已存在的文件
                self.receivedFiles[index] = newFile
                // 移除旧的临时文件
                if let oldURL = self.localFileURLs.firstIndex(where: { $0.lastPathComponent.contains(filename) }) {
                    try? FileManager.default.removeItem(at: self.localFileURLs[oldURL])
                    self.localFileURLs.remove(at: oldURL)
                }
                
                // 保持选择状态
                if self.selectedFiles.contains(self.receivedFiles[index].id) {
                    self.selectedFiles.remove(self.receivedFiles[index].id)
                }
                self.selectedFiles.insert(newFile.id)
            } else {
                // 添加新文件
                self.receivedFiles.append(newFile)
                // 默认选中新文件
                self.selectedFiles.insert(newFile.id)
            }
            
            // 保存临时文件URL引用
            self.localFileURLs.append(fileURL)
            
            // 使用震动反馈提示用户文件已收到
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
        
        print("文件已保存到: \(fileURL.path)")
    }
    
    // 从文件名获取MIME类型
    private func getMimeTypeFromFileName(_ filename: String) -> String {
        let fileExtension = (filename as NSString).pathExtension.lowercased()
        
        switch fileExtension {
        case "mp3":
            return "audio/mpeg"
        case "wav":
            return "audio/wav"
        case "m4a":
            return "audio/mp4"
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
    
    // 清理文件名
    private func sanitizeFilename(_ filename: String) -> String {
        // 如果文件名为空，返回默认值
        if filename.isEmpty {
            return "unknown"
        }
        
        // 移除文件路径，只保留文件名
        var name = filename
        if let lastSlashIndex = filename.lastIndex(of: "/") {
            name = String(filename[filename.index(after: lastSlashIndex)...])
        }
        if let lastBackslashIndex = name.lastIndex(of: "\\") {
            name = String(name[name.index(after: lastBackslashIndex)...])
        }
        
        // 处理URL编码的文件名
        if name.contains("%") {
            if let decodedName = name.removingPercentEncoding {
                name = decodedName
            }
        }
        
        // 替换非法字符
        let illegalChars = CharacterSet(charactersIn: "\\/:*?\"<>|")
        var cleanName = name
        
        for index in name.indices {
            let char = name[index]
            if let scalar = char.unicodeScalars.first, illegalChars.contains(scalar) {
                cleanName = cleanName.replacingOccurrences(of: String(char), with: "_")
            }
        }
        
        // 确保长度合理
        if cleanName.count > 100 {
            if let extensionDot = cleanName.lastIndex(of: ".") {
                let baseName = String(cleanName[..<extensionDot])
                let ext = String(cleanName[extensionDot...])
                cleanName = String(baseName.prefix(90)) + ext
            } else {
                cleanName = String(cleanName.prefix(100))
            }
        }
        
        return cleanName.isEmpty ? "unknown" : cleanName
    }
}

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .resizable()
                .frame(width: 22, height: 22)
                .foregroundColor(configuration.isOn ? .blue : .gray)
                .onTapGesture {
                    configuration.isOn.toggle()
                }
            
            configuration.label
        }
    }
} 
