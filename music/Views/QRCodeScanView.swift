import SwiftUI
import AVFoundation
import UIKit

struct QRCodeScanView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = QRCodeScanViewModel()
    @State private var showMusicFileList = false
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    // 扫描状态
                    if viewModel.isScanning {
                        // 相机预览层
                        QRCodeCameraView(viewModel: viewModel)
                            .edgesIgnoringSafeArea(.all)
                            .zIndex(0) // 确保预览层在最底层
                        
                        // 扫描界面覆盖层
                        scannerOverlayView(geometry: geometry)
                            .zIndex(1)
                        
                        // 扫描指示和取消按钮
                        scannerControlsView(geometry: geometry)
                            .zIndex(2)
                    } else if viewModel.isLoading {
                        // 加载状态
                        loadingView
                    } else if viewModel.hasError {
                        // 错误状态
                        errorView
                    } else {
                        // 显示音乐文件列表
                        MusicFileListView(
                            musicFiles: viewModel.musicFiles,
                            serverURL: viewModel.scannedURL,
                            dismiss: { dismiss() }
                        )
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .navigationBarTitle("扫一扫", displayMode: .inline)
            .navigationBarHidden(viewModel.isScanning)
            .onAppear {
                // 页面出现时开始扫描
                viewModel.startScanning()
            }
            .onDisappear {
                // 页面消失时停止扫描
                viewModel.stopScanning()
            }
        }
    }
    
    // 扫描界面覆盖层
    private func scannerOverlayView(geometry: GeometryProxy) -> some View {
        // 计算扫描框大小和位置
        let width = geometry.size.width * 0.7
        let xOffset = (geometry.size.width - width) / 2
        let yOffset = (geometry.size.height - width) / 2 - 50 // 稍微上移一点
        
        return ZStack {
            // 半透明黑色遮罩
            Rectangle()
                .fill(Color.black.opacity(0.6))
                .frame(width: geometry.size.width, height: geometry.size.height)
            
            // 透明扫描区域
            Rectangle()
                .fill(Color.clear)
                .frame(width: width, height: width)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2 - 50)
            
            // 扫描框
            QRCodeFrameView()
                .frame(width: width, height: width)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2 - 50)
        }
        .compositingGroup()
        .edgesIgnoringSafeArea(.all)
    }
    
    // 扫描控制视图
    private func scannerControlsView(geometry: GeometryProxy) -> some View {
        VStack {
            Spacer().frame(height: geometry.size.height * 0.7)
            
            Text("将网页二维码放入框内扫描")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.vertical)
                .shadow(color: .black, radius: 2)
            
            Spacer()
            
            Button(action: {
                dismiss()
            }) {
                Text("取消扫描")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(8)
            }
            .padding(.bottom, 30)
        }
    }
    
    // 加载视图
    private var loadingView: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack {
                ProgressView("正在加载数据...")
                    .progressViewStyle(CircularProgressViewStyle())
                    .foregroundColor(.white)
                    .padding()
            }
        }
    }
    
    // 错误视图
    private var errorView: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 50))
                    .foregroundColor(.red)
                
                Text(viewModel.errorMessage)
                    .font(.headline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding()
                
                Button("重新扫描") {
                    viewModel.startScanning()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
                
                Button("返回") {
                    dismiss()
                }
                .padding(.top)
                .foregroundColor(.white)
            }
            .padding()
        }
    }
}

// 相机视图 - 负责显示相机预览画面
struct QRCodeCameraView: UIViewRepresentable {
    @ObservedObject var viewModel: QRCodeScanViewModel
    
    func makeUIView(context: Context) -> UIView {
        // 创建容器视图 - 使用一个固定的初始尺寸，而非UIScreen.main.bounds
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        view.backgroundColor = .black
        print("创建相机预览视图，初始尺寸：\(view.frame)")
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // 确保视图有正确尺寸
        if uiView.bounds.width <= 0 || uiView.bounds.height <= 0 {
            print("警告：视图尺寸异常，尝试使用屏幕尺寸")
            uiView.frame = UIScreen.main.bounds
        }
        
        print("更新相机预览视图，当前尺寸：\(uiView.bounds)")
        
        // 确保预览层已经创建
        if let previewLayer = viewModel.previewLayer {
            previewLayer.frame = uiView.bounds
            previewLayer.videoGravity = .resizeAspectFill
            
            // 检查预览层是否已添加
            if uiView.layer.sublayers?.contains(where: { $0 === previewLayer }) != true {
                uiView.layer.addSublayer(previewLayer)
                print("已将预览层添加到视图，预览层尺寸：\(previewLayer.frame)")
            } else {
                // 如果已添加，确保尺寸正确
                previewLayer.frame = uiView.bounds
                print("更新预览层尺寸：\(previewLayer.frame)")
            }
        } else {
            print("警告：预览层为nil，请确保在startScanning中正确创建")
        }
    }
    
    // 视图销毁时移除预览层
    func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        print("相机预览视图销毁")
        // 移除所有子图层，避免保留对预览层的引用
        uiView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
    }
}

// 扫描框视图
struct QRCodeFrameView: View {
    @State private var scanLinePosition: CGFloat = -0.35
    
    var body: some View {
        ZStack {
            // 白色边框
            RoundedRectangle(cornerRadius: 15)
                .stroke(Color.white, lineWidth: 3)
            
            // 四个角标
            CornerOverlayView()
            
            // 扫描线
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, .green, .clear]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)
                .offset(y: scanLinePosition * UIScreen.main.bounds.width * 0.7)
                .shadow(color: .green, radius: 2)
                .onAppear {
                    animateScanLine()
                }
        }
    }
    
    // 扫描线动画
    private func animateScanLine() {
        withAnimation(
            Animation.easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true)
        ) {
            scanLinePosition = 0.35
        }
    }
}

// 四个角标视图
struct CornerOverlayView: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let cornerSize: CGFloat = 30
            
            ZStack {
                // 左上角
                cornerShape
                    .position(x: cornerSize/2, y: cornerSize/2)
                
                // 右上角
                cornerShape
                    .rotationEffect(Angle(degrees: 90))
                    .position(x: width - cornerSize/2, y: cornerSize/2)
                
                // 右下角
                cornerShape
                    .rotationEffect(Angle(degrees: 180))
                    .position(x: width - cornerSize/2, y: height - cornerSize/2)
                
                // 左下角
                cornerShape
                    .rotationEffect(Angle(degrees: 270))
                    .position(x: cornerSize/2, y: height - cornerSize/2)
            }
        }
    }
    
    // 单个角标形状
    private var cornerShape: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 30, y: 0))
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: 30))
        }
        .stroke(Color.green, lineWidth: 5)
    }
}

// 音乐文件列表视图
struct MusicFileListView: View {
    let musicFiles: [MusicFile]
    let serverURL: String
    let dismiss: () -> Void
    
    @ObservedObject private var musicLibrary = MusicLibrary.shared
    @ObservedObject private var musicFileManager = MusicFileManager.shared
    
    @State private var selectedFiles: Set<String> = []
    @State private var importInProgress = false
    @State private var importedCount = 0
    @State private var totalToImport = 0
    @State private var showImportResult = false
    @State private var importResults: [(filename: String, success: Bool)] = []
    
    var body: some View {
        VStack {
            // 标题和URL信息
            VStack(alignment: .leading, spacing: 8) {
                Text("发现音乐文件")
                    .font(.headline)
                    .padding(.top)
                
                HStack {
                    Text("网址：")
                        .font(.subheadline)
                    
                    Text(serverURL)
                        .font(.caption)
                        .padding(6)
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(4)
                }
                .padding(.bottom, 4)
                
                Text("从扫描的网址中发现以下音乐文件：")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            // 文件列表
            List {
                ForEach(musicFiles, id: \.url) { file in
                    HStack {
                        Button(action: {
                            toggleSelection(file.url)
                        }) {
                            Image(systemName: selectedFiles.contains(file.url) ? "checkmark.square.fill" : "square")
                                .foregroundColor(selectedFiles.contains(file.url) ? .blue : .gray)
                        }
                        
                        VStack(alignment: .leading) {
                            Text(file.name)
                                .fontWeight(.medium)
                            
                            HStack {
                                Text(file.type)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text(file.size)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.leading, 6)
                        
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleSelection(file.url)
                    }
                }
            }
            
            // 底部操作按钮
            HStack {
                Button("全选") {
                    if selectedFiles.count == musicFiles.count {
                        selectedFiles.removeAll()
                    } else {
                        selectedFiles = Set(musicFiles.map { $0.url })
                    }
                }
                .padding()
                .disabled(musicFiles.isEmpty)
                
                Spacer()
                
                Button(action: {
                    importSelectedFiles()
                }) {
                    if importInProgress {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("导入中(\(importedCount)/\(totalToImport))")
                        }
                        .padding()
                        .background(Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    } else {
                        Text("导入\(selectedFiles.count)个文件")
                            .padding()
                            .background(selectedFiles.isEmpty ? Color.gray : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .disabled(selectedFiles.isEmpty || importInProgress)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .alert(isPresented: $showImportResult) {
            Alert(
                title: Text("导入结果"),
                message: Text(formattedImportResults),
                dismissButton: .default(Text("确定")) {
                    dismiss()
                }
            )
        }
    }
    
    // 切换文件选择状态
    private func toggleSelection(_ url: String) {
        if selectedFiles.contains(url) {
            selectedFiles.remove(url)
        } else {
            selectedFiles.insert(url)
        }
    }
    
    // 导入选中的文件
    private func importSelectedFiles() {
        let filesToImport = musicFiles.filter { selectedFiles.contains($0.url) }
        guard !filesToImport.isEmpty else { return }
        
        importInProgress = true
        totalToImport = filesToImport.count
        importedCount = 0
        importResults = []
        
        print("开始导入 \(filesToImport.count) 个文件，服务器URL: \(serverURL)")
        
        let group = DispatchGroup()
        
        for file in filesToImport {
            group.enter()
            
            // 构建完整的文件URL
            var fileURLString = serverURL
            
            // 如果URL已经是完整的http链接，直接使用
            if file.url.hasPrefix("http") {
                fileURLString = file.url
                print("使用完整HTTP链接: \(fileURLString)")
            } 
            // 如果URL以/开头，需要处理
            else if file.url.hasPrefix("/") {
                // 从服务器URL中提取基础部分
                if let serverBaseURL = URL(string: serverURL),
                   let host = serverBaseURL.host {
                    let scheme = serverBaseURL.scheme ?? "http"
                    // 添加端口号8080
                    fileURLString = "\(scheme)://\(host):8080\(file.url)"
                    print("处理绝对路径URL(添加端口8080): \(fileURLString)")
                } else {
                    // 如果无法解析服务器URL，尝试直接拼接
                    // 尝试从扫描URL中提取主机名并添加端口
                    if let hostRange = serverURL.range(of: "://"),
                       let pathStartRange = serverURL.range(of: "/", options: .init(), range: hostRange.upperBound..<serverURL.endIndex) {
                        let hostPart = serverURL[hostRange.upperBound..<pathStartRange.lowerBound]
                        if !hostPart.contains(":") {
                            // 只有当主机部分不包含端口号时，添加端口
                            let baseWithPort = serverURL[..<pathStartRange.lowerBound] + ":8080"
                            fileURLString = String(baseWithPort) + file.url
                            print("通过提取主机名添加端口: \(fileURLString)")
                        } else {
                            fileURLString += file.url.dropFirst() // 去掉开头的/
                            print("主机已包含端口，直接拼接: \(fileURLString)")
                        }
                    } else {
                        // 简单拼接，假设URL需要端口
                        if serverURL.contains("://") && !serverURL.contains(":8080") {
                            // 在域名后添加端口
                            let parts = serverURL.split(separator: "://", maxSplits: 1)
                            if parts.count == 2 {
                                let hostPart = String(parts[1]).replacingOccurrences(of: "/", with: "")
                                fileURLString = "\(parts[0])://\(hostPart):8080\(file.url)"
                                print("简单处理添加端口: \(fileURLString)")
                            } else {
                                fileURLString += file.url.dropFirst()
                                print("无法分析URL结构，直接拼接: \(fileURLString)")
                            }
                        } else {
                            fileURLString += file.url.dropFirst()
                            print("无法解析服务器URL结构，简单拼接: \(fileURLString)")
                        }
                    }
                }
            }
            // 如果URL是相对路径，确保正确拼接
            else {
                // 处理相对路径，确保基础URL包含端口号
                if !serverURL.contains(":8080") && serverURL.contains("://") {
                    // 尝试添加端口号到基础URL
                    if let hostRange = serverURL.range(of: "://"),
                       let pathStartRange = serverURL.range(of: "/", options: .init(), range: hostRange.upperBound..<serverURL.endIndex) {
                        let hostPart = serverURL[hostRange.upperBound..<pathStartRange.lowerBound]
                        let protocolName = serverURL[..<hostRange.lowerBound]
                        let pathPart = serverURL[pathStartRange.lowerBound...]
                        
                        if !hostPart.contains(":") {
                            fileURLString = "\(protocolName)\(hostPart):8080\(pathPart)"
                            if !fileURLString.hasSuffix("/") {
                                fileURLString += "/"
                            }
                            fileURLString += file.url
                            print("相对路径添加端口到基础URL: \(fileURLString)")
                        } else {
                            if !serverURL.hasSuffix("/") {
                                fileURLString += "/"
                            }
                            fileURLString += file.url
                            print("基础URL已包含端口，直接拼接: \(fileURLString)")
                        }
                    } else {
                        // 简单添加端口
                        if serverURL.hasSuffix("/") {
                            let baseURL = serverURL.dropLast() // 去掉末尾的/
                            if !baseURL.contains(":") {
                                fileURLString = String(baseURL) + ":8080/" + file.url
                                print("简单添加端口到URL: \(fileURLString)")
                            } else {
                                fileURLString += file.url
                                print("URL已包含端口或无法识别格式: \(fileURLString)")
                            }
                        } else {
                            if !serverURL.contains(":") {
                                fileURLString += ":8080/" + file.url
                                print("简单添加端口和路径分隔符: \(fileURLString)")
                            } else {
                                fileURLString += "/" + file.url
                                print("URL可能已包含端口，添加路径分隔符: \(fileURLString)")
                            }
                        }
                    }
                } else {
                    // 基础URL已包含端口或无法解析
                    if !serverURL.hasSuffix("/") {
                        fileURLString += "/"
                    }
                    fileURLString += file.url
                    print("使用现有基础URL拼接: \(fileURLString)")
                }
            }
            
            print("尝试下载文件: \(file.name) 从URL: \(fileURLString)")
            
            guard let fileURL = URL(string: fileURLString) else {
                print("无效的文件URL: \(fileURLString)")
                importResults.append((filename: file.name, success: false))
                importedCount += 1
                group.leave()
                continue
            }
            
            // 下载并导入文件
            downloadAndImportFile(from: fileURL, filename: file.name) { success in
                DispatchQueue.main.async {
                    importResults.append((filename: file.name, success: success))
                    importedCount += 1
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            importInProgress = false
            showImportResult = true
            
            // 重新加载音乐库，增加多次延时加载
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("开始刷新音乐库以加载所有导入的歌曲...")
                musicLibrary.loadLocalMusic()
                
                // 第二次延时加载
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    print("再次刷新音乐库以确保所有歌曲已加载完成...")
                    musicLibrary.loadLocalMusic()
                    
                    // 第三次延时加载
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        print("第三次刷新音乐库以确保所有歌曲已完全加载...")
                        musicLibrary.loadLocalMusic()
                    }
                }
            }
        }
    }
    
    // 下载并导入文件
    private func downloadAndImportFile(from url: URL, filename: String, completion: @escaping (Bool) -> Void) {
        // 创建临时文件URL
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory
        let destinationURL = temporaryDirectoryURL.appendingPathComponent(filename)
        
        print("开始下载文件，URL: \(url.absoluteString)")
        print("下载到临时位置: \(destinationURL.path)")
        
        // 创建下载任务
        let downloadTask = URLSession.shared.downloadTask(with: url) { tempFileURL, response, error in
            guard let tempFileURL = tempFileURL, error == nil else {
                print("下载失败: \(error?.localizedDescription ?? "未知错误")")
                if let httpResponse = response as? HTTPURLResponse {
                    print("HTTP状态码: \(httpResponse.statusCode)")
                    print("响应头: \(httpResponse.allHeaderFields)")
                }
                completion(false)
                return
            }
            
            print("文件下载完成，临时位置: \(tempFileURL.path)")
            if let httpResponse = response as? HTTPURLResponse {
                print("下载成功，HTTP状态码: \(httpResponse.statusCode)")
                print("文件类型: \(httpResponse.mimeType ?? "未知")")
                print("文件大小: \(httpResponse.expectedContentLength) 字节")
            }
            
            do {
                // 如果目标位置已存在文件，先删除
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                    print("删除已存在的文件")
                }
                
                // 移动文件到目标位置
                try FileManager.default.moveItem(at: tempFileURL, to: destinationURL)
                print("移动文件到: \(destinationURL.path)")
                
                // 获取文件信息
                let fileAttributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
                if let fileSize = fileAttributes[.size] as? NSNumber {
                    print("文件大小: \(fileSize.intValue) 字节")
                }
                
                // 导入音乐文件
                musicFileManager.importMusicFile(from: destinationURL) { result in
                    switch result {
                    case .success(let importedFile):
                        print("成功导入: \(filename)")
                        print("导入文件信息: \(importedFile.title) - \(importedFile.artist) (\(importedFile.fileFormat))")
                        completion(true)
                    case .failure(let error):
                        print("导入失败: \(error.localizedDescription)")
                        print("导入失败路径: \(destinationURL.path)")
                        completion(false)
                    }
                    
                    // 清理临时文件
                    try? FileManager.default.removeItem(at: destinationURL)
                    print("清理临时文件")
                }
            } catch {
                print("处理下载文件时出错: \(error.localizedDescription)")
                completion(false)
            }
        }
        
        downloadTask.resume()
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
}

// 视图模型 - 负责管理扫描状态和逻辑
class QRCodeScanViewModel: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    // 视图状态
    @Published var isScanning = false
    @Published var isLoading = false
    @Published var hasError = false
    @Published var errorMessage = ""
    @Published var scannedURL = ""
    @Published var musicFiles: [MusicFile] = []
    
    // 捕获会话
    private var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    private var isSessionConfigured = false
    private var isConfiguring = false
    
    // 设置队列
    private let sessionQueue = DispatchQueue(label: "com.music.captureSessionQueue")
    
    override init() {
        super.init()
        print("QRCodeScanViewModel初始化")
    }
    
    deinit {
        print("QRCodeScanViewModel释放")
        // 确保在释放前停止会话
        if captureSession?.isRunning == true {
            print("在deinit中停止会话")
            captureSession?.stopRunning()
        }
        // 清理引用
        captureSession = nil
        previewLayer = nil
    }
    
    // 开始扫描
    func startScanning() {
        // 防止重复调用
        if isScanning || isConfiguring {
            print("已在扫描或配置中，忽略重复调用")
            return
        }
        
        // 重置状态
        hasError = false
        errorMessage = ""
        
        print("开始扫描流程，检查相机权限...")
        
        // 检查相机权限
        checkCameraPermission { [weak self] granted in
            guard let self = self else { return }
            
            if granted {
                print("相机权限已授权，开始设置")
                self.sessionQueue.async {
                    // 标记正在配置
                    self.isConfiguring = true
                    
                    // 确保会话仅配置一次
                    if !self.isSessionConfigured {
                        self.setupCaptureSession()
                    }
                    
                    // 启动会话
                    self.startCaptureSession()
                    
                    // 标记配置完成
                    self.isConfiguring = false
                }
            } else {
                DispatchQueue.main.async {
                    print("相机权限被拒绝")
                    self.hasError = true
                    self.errorMessage = "需要相机权限来扫描二维码"
                }
            }
        }
    }
    
    // 停止扫描
    func stopScanning() {
        print("尝试停止扫描")
        
        // 防止死锁，确保状态更新
        if !isScanning {
            print("当前未在扫描状态，直接返回")
            return
        }
        
        // 避免强引用循环
        let captureSessionCopy = captureSession
        
        sessionQueue.async {
            if let captureSession = captureSessionCopy, captureSession.isRunning {
                print("停止相机捕获会话")
                captureSession.stopRunning()
            } else {
                print("捕获会话不存在或未运行")
            }
            
            // 始终更新UI状态
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isScanning = false
                print("扫描状态已更新")
            }
        }
    }
    
    // 检查相机权限
    private func checkCameraPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            print("相机已授权")
            completion(true)
        case .notDetermined:
            print("相机权限未确定，请求权限...")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                print("相机权限请求结果: \(granted ? "已授权" : "已拒绝")")
                completion(granted)
            }
        case .denied, .restricted:
            print("相机权限被拒绝或受限")
            completion(false)
        @unknown default:
            print("相机权限状态未知")
            completion(false)
        }
    }
    
    // 设置捕获会话
    private func setupCaptureSession() {
        // 确保不重复配置并在正确的线程上执行
        if isSessionConfigured {
            print("相机会话已配置，跳过")
            return
        }
        
        if !Thread.isMainThread && DispatchQueue.getSpecific(key: DispatchSpecificKey<Bool>()) != nil {
            print("警告：相机会话应该在后台线程配置")
        }
        
        print("开始配置相机会话")
        
        // 创建新的会话
        let session = AVCaptureSession()
        
        // 设置预设质量
        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
            print("设置相机预设质量为高")
        } else {
            print("无法设置预设质量，使用默认值")
        }
        
        // 获取后置摄像头
        guard let videoCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("无法获取后置摄像头，尝试获取任意摄像头")
            guard let anyCamera = AVCaptureDevice.default(for: .video) else {
                print("无法获取任何摄像头设备")
                handleSetupError("找不到摄像头设备")
                return
            }
            print("已获取到摄像头设备: \(anyCamera.localizedName)")
            configureCameraInput(anyCamera, session: session)
            return
        }
        
        print("已获取摄像头设备: \(videoCaptureDevice.localizedName)")
        configureCameraInput(videoCaptureDevice, session: session)
    }
    
    // 配置相机输入
    private func configureCameraInput(_ device: AVCaptureDevice, session: AVCaptureSession) {
        do {
            let videoInput = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
                print("已添加视频输入到会话")
                configureMetadataOutput(session: session)
            } else {
                print("无法添加视频输入到会话")
                handleSetupError("无法添加视频输入")
            }
        } catch {
            print("创建视频输入失败: \(error.localizedDescription)")
            handleSetupError("设置摄像头失败: \(error.localizedDescription)")
        }
    }
    
    // 配置元数据输出
    private func configureMetadataOutput(session: AVCaptureSession) {
        let metadataOutput = AVCaptureMetadataOutput()
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            print("已添加元数据输出到会话")
            
            // 设置代理
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            
            // 检查支持的元数据类型
            print("可用的元数据类型: \(metadataOutput.availableMetadataObjectTypes)")
            
            // 设置要识别的元数据类型
            if metadataOutput.availableMetadataObjectTypes.contains(.qr) {
                metadataOutput.metadataObjectTypes = [.qr]
                print("已设置QR码识别")
                
                // 完成会话设置
                finishSessionSetup(session: session)
            } else {
                print("元数据输出不支持QR码识别")
                handleSetupError("此设备不支持二维码扫描")
            }
        } else {
            print("无法添加元数据输出到会话")
            handleSetupError("无法添加元数据输出")
        }
    }
    
    // 完成会话设置
    private func finishSessionSetup(session: AVCaptureSession) {
        // 保存会话
        self.captureSession = session
        print("相机会话配置完成")
        
        // 在主线程上创建预览层
        DispatchQueue.main.async {
            // 创建预览层
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            print("已创建相机预览层")
            self.previewLayer = previewLayer
            
            // 标记会话已配置
            self.isSessionConfigured = true
        }
    }
    
    // 开始捕获会话
    private func startCaptureSession() {
        guard let captureSession = captureSession else {
            print("相机会话未初始化")
            handleSetupError("相机会话未初始化")
            return
        }
        
        // 确保在正确的线程上运行
        if Thread.isMainThread {
            print("警告：应在后台线程启动相机会话")
        }
        
        if !captureSession.isRunning {
            print("开始运行相机会话")
            
            // 开始相机会话
            captureSession.startRunning()
            
            // 更新UI状态
            DispatchQueue.main.async {
                print("相机会话已启动，更新UI状态")
                self.isScanning = true
            }
        } else {
            print("相机会话已在运行")
            DispatchQueue.main.async {
                self.isScanning = true
            }
        }
    }
    
    // 处理设置错误
    private func handleSetupError(_ message: String) {
        print("相机设置错误: \(message)")
        DispatchQueue.main.async {
            self.hasError = true
            self.errorMessage = message
        }
    }
    
    // AVCaptureMetadataOutputObjectsDelegate
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        print("检测到元数据对象: \(metadataObjects.count)")
        
        // 这个方法已经在主线程运行，检查状态避免重复处理
        if !isScanning || isLoading {
            print("已在处理中或未在扫描状态，忽略新的元数据")
            return
        }
        
        // 有有效二维码时暂停扫描
        if let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
           let urlString = metadataObject.stringValue {
            
            print("扫描到URL: \(urlString)")
            
            // 先设置加载状态，防止重复处理
            isScanning = false
            isLoading = true
            
            // 安全地停止会话
            sessionQueue.async { [weak self] in
                guard let self = self else { return }
                
                if let session = self.captureSession, session.isRunning {
                    session.stopRunning()
                    print("检测到二维码后停止会话")
                }
            }
            
            // 处理扫描结果
            if let url = URL(string: urlString) {
                self.scannedURL = urlString
                
                // 处理扫描到的URL
                self.fetchMusicFiles(from: url)
            } else {
                print("无效的URL格式: \(urlString)")
                self.handleError("扫描结果不是有效的URL")
                
                // 重置状态，允许继续扫描
                self.isLoading = false
                self.startScanning()
            }
        } else {
            // 未检测到有效二维码，继续扫描
            print("未检测到有效的二维码")
        }
    }
    
    // 处理错误
    private func handleError(_ message: String) {
        print("错误: \(message)")
        hasError = true
        errorMessage = message
    }
    
    // 从URL获取音乐文件列表
    private func fetchMusicFiles(from url: URL) {
        print("开始从URL获取音乐文件: \(url.absoluteString)")
        
        // 确保URL以斜杠结尾
        var serverURLString = url.absoluteString
        if !serverURLString.hasSuffix("/") {
            serverURLString += "/"
        }
        scannedURL = serverURLString
        print("使用服务器URL: \(serverURLString)")
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    print("网络请求失败: \(error.localizedDescription)")
                    self.handleError("无法连接到服务器: \(error.localizedDescription)")
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("无效的HTTP响应")
                    self.handleError("服务器响应无效")
                    return
                }
                
                print("HTTP状态码: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode != 200 {
                    self.handleError("服务器返回错误: \(httpResponse.statusCode)")
                    return
                }
                
                guard let data = data,
                      let htmlString = String(data: data, encoding: .utf8) else {
                    print("无法解析服务器响应")
                    self.handleError("无法解析服务器响应")
                    return
                }
                
                // 记录HTML大小以便调试
                print("收到HTML响应，大小: \(data.count)字节")
                
                // 解析HTML获取音乐文件
                let files = self.parseMusicFilesFromHTML(htmlString)
                
                if files.isEmpty {
                    print("未找到音乐文件")
                    self.handleError("未在网页中找到音乐文件，请确认链接是否正确")
                } else {
                    print("成功找到\(files.count)个音乐文件")
                    self.musicFiles = files
                }
            }
        }.resume()
    }
    
    // 解析HTML中的音乐文件
    private func parseMusicFilesFromHTML(_ html: String) -> [MusicFile] {
        var musicFiles: [MusicFile] = []
        
        print("开始解析HTML，长度: \(html.count)字符")
        
        // 尝试匹配自定义表格格式
        let customTablePattern = "<tr><td><a\\s+href=[\"']([^\"']+)[\"']>([^<]+)\\s*(?:<span[^>]*>\\([^)]+\\)</span>)?</a></td><td>([^<]+)</td><td>([^<]+)</td><td>([^<]+)</td></tr>"
        
        do {
            let regex = try NSRegularExpression(pattern: customTablePattern, options: [])
            let nsString = html as NSString
            let range = NSRange(location: 0, length: nsString.length)
            let matches = regex.matches(in: html, options: [], range: range)
            
            print("自定义表格模式找到\(matches.count)个文件链接")
            
            for match in matches {
                if match.numberOfRanges >= 5 {
                    let urlPath = nsString.substring(with: match.range(at: 1))
                    let fileName = nsString.substring(with: match.range(at: 2))
                    let fileType = nsString.substring(with: match.range(at: 3))
                    let fileSize = nsString.substring(with: match.range(at: 4))
                    
                    // 提取纯文件名，去掉路径标记部分
                    let cleanFileName = fileName.replacingOccurrences(of: "<span[^>]*>[^<]*</span>", with: "", options: .regularExpression)
                                               .trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanFileType = fileType.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanFileSize = fileSize.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    print("找到可能的音频文件: \(cleanFileName), 类型: \(cleanFileType), 大小: \(cleanFileSize), URL: \(urlPath)")
                    
                    // 检查文件类型或URL是否为音频文件
                    if isAudioFile(urlPath) || cleanFileType.lowercased().contains("音频") ||
                       cleanFileType.lowercased().contains("flac") || cleanFileType.lowercased().contains("mp3") {
                        print("确认为音频文件: \(cleanFileName)")
                        
                        musicFiles.append(
                            MusicFile(
                                name: cleanFileName,
                                url: urlPath,
                                size: cleanFileSize,
                                type: cleanFileType
                            )
                        )
                    }
                }
            }
        } catch {
            print("解析自定义表格错误: \(error)")
        }
        
        // 如果没有找到音频文件，尝试Apache类型的目录列表
        if musicFiles.isEmpty {
            print("尝试Apache模式解析")
            let linkPattern = "<tr[^>]*>\\s*<td[^>]*><a\\s+href=[\"']([^\"']+)[\"'][^>]*>([^<]+)</a></td>\\s*<td[^>]*>([^<]+)</td>\\s*<td[^>]*>([^<]+)</td>"
            
            do {
                let regex = try NSRegularExpression(pattern: linkPattern, options: [])
                let nsString = html as NSString
                let range = NSRange(location: 0, length: nsString.length)
                let matches = regex.matches(in: html, options: [], range: range)
                
                print("Apache模式找到\(matches.count)个文件链接")
                
                for match in matches {
                    if match.numberOfRanges >= 5 {
                        let urlPath = nsString.substring(with: match.range(at: 1))
                        let fileName = nsString.substring(with: match.range(at: 2))
                        let fileType = nsString.substring(with: match.range(at: 3))
                        let fileSize = nsString.substring(with: match.range(at: 4))
                        
                        // 判断是否为音频文件
                        if isAudioFile(urlPath) {
                            let cleanFileName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
                            let cleanFileType = fileType.trimmingCharacters(in: .whitespacesAndNewlines)
                            let cleanFileSize = fileSize.trimmingCharacters(in: .whitespacesAndNewlines)
                            
                            print("找到音频文件: \(cleanFileName), 类型: \(cleanFileType), 大小: \(cleanFileSize)")
                            
                            musicFiles.append(
                                MusicFile(
                                    name: cleanFileName,
                                    url: urlPath,
                                    size: cleanFileSize,
                                    type: cleanFileType
                                )
                            )
                        }
                    }
                }
            } catch {
                print("解析Apache模式错误: \(error)")
            }
        }
        
        // 如果仍然没有找到音频文件，尝试最基本的链接匹配
        if musicFiles.isEmpty {
            print("尝试基本链接匹配")
            let fallbackLinkPattern = "<a\\s+href=[\"']([^\"']+)[\"'][^>]*>([^<]+)</a>"
            
            do {
                let regex = try NSRegularExpression(pattern: fallbackLinkPattern, options: [])
                let nsString = html as NSString
                let range = NSRange(location: 0, length: nsString.length)
                let matches = regex.matches(in: html, options: [], range: range)
                
                print("基本链接匹配找到\(matches.count)个链接")
                
                for match in matches {
                    if match.numberOfRanges >= 3 {
                        let urlPath = nsString.substring(with: match.range(at: 1))
                        let fileName = nsString.substring(with: match.range(at: 2))
                        
                        // 判断是否为音频文件
                        if isAudioFile(urlPath) {
                            let cleanFileName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
                            
                            print("找到音频文件: \(cleanFileName), URL: \(urlPath)")
                            
                            musicFiles.append(
                                MusicFile(
                                    name: cleanFileName,
                                    url: urlPath,
                                    size: "未知大小",
                                    type: urlPath.components(separatedBy: ".").last?.uppercased() ?? "音频"
                                )
                            )
                        }
                    }
                }
            } catch {
                print("基本链接匹配错误: \(error)")
            }
        }
        
        // 如果所有方法都失败，尝试宽松的模式匹配所有flac文件
        if musicFiles.isEmpty {
            print("使用特定模式匹配该网页的音频文件")
            let specificPattern = "<a\\s+href=[\"']([^\"']+)[\"'][^>]*>([^<]+)\\.flac\\s*<span"
            
            do {
                let regex = try NSRegularExpression(pattern: specificPattern, options: [.caseInsensitive])
                let nsString = html as NSString
                let range = NSRange(location: 0, length: nsString.length)
                let matches = regex.matches(in: html, options: [], range: range)
                
                print("特定模式找到\(matches.count)个音频文件链接")
                
                for match in matches {
                    if match.numberOfRanges >= 3 {
                        let urlPath = nsString.substring(with: match.range(at: 1))
                        var fileName = nsString.substring(with: match.range(at: 2))
                        
                        // 确保文件名包含扩展名
                        if !fileName.lowercased().hasSuffix(".flac") {
                            fileName += ".flac"
                        }
                        
                        print("特定模式找到音频文件: \(fileName), URL: \(urlPath)")
                        
                        musicFiles.append(
                            MusicFile(
                                name: fileName,
                                url: urlPath,
                                size: "未知大小",
                                type: "FLAC无损音频"
                            )
                        )
                    }
                }
            } catch {
                print("特定模式匹配错误: \(error)")
            }
        }
        
        // 如果所有方法都失败，尝试宽松的模式匹配所有flac文件
        if musicFiles.isEmpty {
            print("使用最宽松模式匹配音频文件")
            let loosePattern = "href=[\"']([^\"']+\\.(?:flac|mp3|wav|m4a|aac|ogg|ape))[\"']"
            
            do {
                let regex = try NSRegularExpression(pattern: loosePattern, options: [.caseInsensitive])
                let nsString = html as NSString
                let range = NSRange(location: 0, length: nsString.length)
                let matches = regex.matches(in: html, options: [], range: range)
                
                print("宽松模式找到\(matches.count)个音频文件链接")
                
                for match in matches {
                    if match.numberOfRanges >= 2 {
                        let urlPath = nsString.substring(with: match.range(at: 1))
                        let fileName = urlPath.components(separatedBy: "/").last ?? urlPath
                        
                        print("宽松模式找到音频文件: \(fileName), URL: \(urlPath)")
                        
                        musicFiles.append(
                            MusicFile(
                                name: fileName,
                                url: urlPath,
                                size: "未知大小",
                                type: fileName.components(separatedBy: ".").last?.uppercased() ?? "音频"
                            )
                        )
                    }
                }
            } catch {
                print("宽松模式匹配错误: \(error)")
            }
        }
        
        // 打印解析结果
        print("共找到\(musicFiles.count)个音频文件")
        for file in musicFiles {
            print("文件名: \(file.name), URL: \(file.url), 大小: \(file.size), 类型: \(file.type)")
        }
        
        return musicFiles
    }
    
    // 判断是否为音频文件
    private func isAudioFile(_ path: String) -> Bool {
        let audioExtensions = ["mp3", "wav", "m4a", "aac", "flac", "ogg", "ape", "alac"]
        let lowercasedPath = path.lowercased()
        
        // 检查是否以音频扩展名结尾
        for ext in audioExtensions {
            if lowercasedPath.hasSuffix(".\(ext)") {
                return true
            }
        }
        
        return false
    }
}

// 音乐文件模型
struct MusicFile {
    let name: String
    let url: String
    let size: String
    let type: String
}

// 字符串扩展
extension String {
    func matches(for regex: String) -> [String] {
        do {
            let regex = try NSRegularExpression(pattern: regex, options: [])
            let nsString = self as NSString
            let results = regex.matches(in: self, options: [], range: NSRange(location: 0, length: nsString.length))
            return results.map { nsString.substring(with: $0.range) }
        } catch {
            return []
        }
    }
}

// NSRegularExpression扩展
extension NSTextCheckingResult {
    func captureRanges(in string: String) -> [Range<String.Index>] {
        return (0..<self.numberOfRanges)
            .map { self.range(at: $0) }
            .compactMap { Range($0, in: string) }
    }
}

// 扫描遮罩视图
struct ScannerOverlayView: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 半透明黑色背景
                Color.black.opacity(0.5)
                
                // 中间裁剪出透明的方形区域
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 250, height: 250)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
        }
    }
}

struct QRCodeScanView_Previews: PreviewProvider {
    static var previews: some View {
        QRCodeScanView()
    }
} 