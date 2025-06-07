import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct EnhancedImportView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var musicLibrary = MusicLibrary.shared
    @ObservedObject private var musicFileManager = MusicFileManager.shared
    
    @State private var isShowingDocumentPicker = false
    @State private var isLoading = false
    @State private var loadingMessage = ""
    @State private var importedSong: Song?
    @State private var importedSongs: [Song] = []
    @State private var showImportResult = false
    @State private var importError: Error?
    @State private var batchImportStats: (success: Int, failed: Int) = (0, 0)
    @State private var showLocalMusicScan = false
    @State private var showLANImport = false
    @State private var showQRCodeScan = false
    
    // 添加重复文件处理状态
    @State private var showingDuplicateAlert = false
    @State private var duplicateFile: (existingSong: Song, newURL: URL)?
    @State private var processingQueue: [URL] = []
    
    // 添加重复文件记录数组，用于批量报告
    @State private var duplicateFiles: [(name: String, existingSong: Song)] = []
    
    // 导入方法选项
    enum ImportMethod: String, CaseIterable, Identifiable {
        case files = "从文件导入"
        case localScan = "扫描本机音乐"
        case qrCode = "扫一扫"
        case lan = "局域网导入"
        
        var id: String { self.rawValue }
        
        var icon: String {
            switch self {
            case .files: return "folder"
            case .localScan: return "music.note.list"
            case .qrCode: return "qrcode.viewfinder"
            case .lan: return "network"
            }
        }
        
        var color: Color {
            switch self {
            case .files: return .blue
            case .localScan: return .purple
            case .qrCode: return .green
            case .lan: return .orange
            }
        }
        
        var description: String {
            switch self {
            case .files: return "从文件选择音乐文件导入"
            case .localScan: return "扫描设备中的音乐文件"
            case .qrCode: return "扫描二维码快速导入音乐"
            case .lan: return "从局域网内其他设备导入"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if isLoading {
                        ProgressView(loadingMessage)
                            .scaleEffect(1.5)
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            .padding(.top, 100)
                    } else {
                        // 顶部图标和标题
                        headerSection
                        
                        // 支持的导入方式
                        importMethodsSection
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("导入音乐")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isShowingDocumentPicker) {
                EnhancedDocumentPicker(supportedTypes: musicFileManager.supportedTypes) { urls in
                    if urls.count == 1 {
                        // 单文件导入
                        importMusicFile(from: urls[0])
                    } else if urls.count > 1 {
                        // 多文件导入
                        importMultipleMusicFiles(from: urls)
                    }
                }
            }
            .sheet(isPresented: $showLocalMusicScan) {
                NavigationView {
                    LocalMusicScanView()
                }
            }
            .sheet(isPresented: $showLANImport) {
                NavigationView {
                    LANImportView()
                }
            }
            .sheet(isPresented: $showQRCodeScan) {
                QRCodeScanView()
            }
            .alert(isPresented: $showImportResult) {
                if let error = importError {
                    // 导入失败的提示
                    return Alert(
                        title: Text("导入失败"),
                        message: Text(error.localizedDescription),
                        dismissButton: .default(Text("确定"))
                    )
                } else if let song = importedSong, importedSongs.isEmpty {
                    // 单首歌曲导入成功的提示
                    return Alert(
                        title: Text("导入成功"),
                        message: Text("已成功导入音乐：\(song.title)"),
                        dismissButton: .default(Text("确定")) {
                            dismiss()
                        }
                    )
                } else if !importedSongs.isEmpty || batchImportStats.failed > 0 {
                    // 多首歌曲导入结果的提示
                    let successCount = batchImportStats.success
                    let failedCount = batchImportStats.failed
                    let totalCount = successCount + failedCount
                    
                    var message = "共选择\(totalCount)首歌曲，成功导入\(successCount)首"
                    
                    if failedCount > 0 {
                        // 有导入失败的情况
                        message += "，\(failedCount)首导入失败"
                        
                        // 如果有重复文件，添加说明
                        let duplicateCount = duplicateFiles.count
                        if duplicateCount > 0 {
                            if duplicateCount == failedCount {
                                message += "（全部为重复文件）"
                            } else {
                                message += "（其中\(duplicateCount)首为重复文件）"
                            }
                        }
                    }
                    
                    return Alert(
                        title: Text("批量导入完成"),
                        message: Text(message),
                        dismissButton: .default(Text("确定")) {
                            dismiss()
                        }
                    )
                } else {
                    // 通用提示
                    return Alert(
                        title: Text("导入结果"),
                        message: Text("操作已完成"),
                        dismissButton: .default(Text("确定"))
                    )
                }
            }
            // 添加重复文件警告弹窗
            .alert("文件已存在", isPresented: $showingDuplicateAlert) {
                Button("确定", role: .cancel) {
                    skipDuplicateFile()
                }
            } message: {
                if let duplicate = duplicateFile {
                    if !processingQueue.isEmpty {
                        // 批量导入模式显示处理进度信息
                        let total = importedSongs.count + processingQueue.count + 1 // +1 是当前处理的文件
                        let processed = importedSongs.count + batchImportStats.failed
                        
                        Text("文件「\(duplicate.newURL.lastPathComponent)」与音乐库中的「\(duplicate.existingSong.title) - \(duplicate.existingSong.artist)」重复。\n\n系统将自动跳过此文件并继续处理剩余文件。（\(processed)/\(total)）")
                    } else {
                        // 单文件导入模式显示简洁信息
                        Text("文件「\(duplicate.newURL.lastPathComponent)」已存在于音乐库中。\n\n系统不允许导入重复文件。")
                    }
                } else {
                    Text("发现重复文件，将自动跳过")
                }
            }
        }
        .onAppear {
            print("EnhancedImportView appeared!")
        }
    }
    
    // 顶部图标和标题部分
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 50))
                .foregroundColor(.blue)
                .padding(.bottom, 8)
            
            Text("多种方式导入音乐")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("支持MP3、WAV、AAC、M4A、FLAC等格式")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.bottom, 10)
        }
        .padding(.top, 20)
    }
    
    // 导入方法部分
    private var importMethodsSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("选择导入方式")
                .font(.headline)
                .padding(.leading)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                ForEach(ImportMethod.allCases) { method in
                    importMethodButton(method)
                }
            }
            .padding(.horizontal, 5)
        }
    }
    
    // 导入方法按钮
    private func importMethodButton(_ method: ImportMethod) -> some View {
        Button(action: {
            handleImportMethodTap(method)
        }) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(method.color.opacity(0.2))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: method.icon)
                        .font(.system(size: 28))
                        .foregroundColor(method.color)
                }
                
                Text(method.rawValue)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
                
                Text(method.description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .frame(height: 170)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
            )
        }
    }
    
    // 导入音乐文件
    private func importMusicFile(from url: URL) {
        isLoading = true
        loadingMessage = "正在导入音乐文件..."
        
        // 重置状态
        importedSong = nil
        importedSongs = []
        importError = nil
        duplicateFiles = []
        
        musicFileManager.importMusicFile(from: url) { result in
            isLoading = false
            
            switch result {
            case .success(let song):
                importedSong = song
                showImportResult = true
                
            case .failure(let error):
                // 检查是否是重复文件错误
                if case let MusicError.fileAlreadyExists(existingSong, newURL) = error {
                    // 处理重复文件 - 单文件模式仍然显示提示
                    duplicateFile = (existingSong, newURL)
                    showingDuplicateAlert = true
                } else {
                    // 其他错误
                    importError = error
                    showImportResult = true
                }
            }
        }
    }
    
    // 批量导入音乐文件
    private func importMultipleMusicFiles(from urls: [URL]) {
        // 初始化状态
        importedSongs = []
        importedSong = nil
        batchImportStats = (0, 0)
        duplicateFiles = []
        
        // 初始化处理队列
        processingQueue = Array(urls)
        
        // 开始批量处理
        isLoading = true
        processNextFileInQueueSilently()
    }
    
    // 静默处理队列中的下一个文件（不显示中间弹窗）
    private func processNextFileInQueueSilently() {
        guard !processingQueue.isEmpty else {
            // 所有文件处理完毕
            isLoading = false
            showImportResult = true
            return
        }
        
        let totalFiles = importedSongs.count + batchImportStats.failed + processingQueue.count
        let processedFiles = importedSongs.count + batchImportStats.failed
        
        loadingMessage = "正在批量导入音乐文件 (\(processedFiles + 1)/\(totalFiles))..."
        let url = processingQueue.removeFirst()
        
        musicFileManager.importMusicFile(from: url) { result in
            switch result {
            case .success(let song):
                self.importedSongs.append(song)
                self.batchImportStats.success += 1
                
            case .failure(let error):
                if case let MusicError.fileAlreadyExists(existingSong, newURL) = error {
                    // 静默记录重复文件，不显示弹窗
                    self.batchImportStats.failed += 1
                    self.duplicateFiles.append((name: newURL.lastPathComponent, existingSong: existingSong))
                } else {
                    // 其他错误，只记录失败
                    self.batchImportStats.failed += 1
                }
            }
            
            // 继续处理下一个文件，不显示任何中间弹窗
            self.processNextFileInQueueSilently()
        }
    }
    
    // 跳过重复文件
    private func skipDuplicateFile() {
        // 清除重复文件信息
        duplicateFile = nil
        isLoading = false
    }
    
    // 处理导入方法选择
    private func handleImportMethodTap(_ method: ImportMethod) {
        switch method {
        case .files:
            isShowingDocumentPicker = true
        case .localScan:
            // 显示扫描本机音乐的界面
            showLocalMusicScan = true
        case .qrCode:
            // 显示扫一扫功能
            showQRCodeScan = true
        case .lan:
            // 显示局域网导入界面
            showLANImport = true
        }
    }
}

// 文档选择器
struct EnhancedDocumentPicker: UIViewControllerRepresentable {
    let supportedTypes: [UTType]
    let onPick: ([URL]) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: EnhancedDocumentPicker
        
        init(_ parent: EnhancedDocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            // 处理用户选择的文档
            if urls.isEmpty { return }
            
            var secureURLs: [URL] = []
            
            for url in urls {
                // 开始访问安全范围资源
                if url.startAccessingSecurityScopedResource() {
                    // 尝试创建安全书签，以便稍后访问
                    do {
                        let bookmarkData = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                        // 可以将bookmarkData保存到UserDefaults或其他持久化存储中
                        print("已创建文件书签")
                    } catch {
                        print("创建书签失败: \(error)")
                    }
                    
                    secureURLs.append(url)
                } else {
                    print("无法访问文件: \(url.lastPathComponent)")
                }
            }
            
            // 调用回调并处理文件
            if !secureURLs.isEmpty {
                parent.onPick(secureURLs)
            }
            
            // 使用后释放安全访问
            // 注意：如果需要长时间访问，应该在使用完毕后再调用
            for url in urls {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }
}

struct EnhancedImportView_Previews: PreviewProvider {
    static var previews: some View {
        EnhancedImportView()
    }
} 