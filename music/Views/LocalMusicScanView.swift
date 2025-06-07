import SwiftUI
import UniformTypeIdentifiers
import MobileCoreServices

struct LocalMusicScanView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var musicLibrary = MusicLibrary.shared
    @ObservedObject private var musicFileManager = MusicFileManager.shared
    
    @State private var isScanning = false
    @State private var scanMessage = "准备扫描"
    @State private var foundFiles: [FoundMusicFile] = []
    @State private var selectedFiles: Set<URL> = []
    @State private var scanProgress: Double = 0.0
    @State private var showResult = false
    @State private var importStats: (success: Int, failed: Int) = (0, 0)
    @State private var currentFolder: String = ""
    
    // 排序选项
    enum SortOption: String, CaseIterable {
        case fileName = "文件名"
        case fileSize = "文件大小"
        case modificationDate = "修改日期"
    }
    
    @State private var sortOption: SortOption = .fileName
    @State private var sortAscending = true
    
    // 筛选设置
    @State private var showingFilterSheet = false
    @State private var searchText = ""
    @State private var minFileSize: Double = 0 // KB
    @State private var maxFileSize: Double = 100000 // KB
    @State private var selectedFormats: Set<String> = Set(["mp3", "wav", "m4a", "flac", "aac"])
    
    var body: some View {
        VStack {
            // 顶部搜索和筛选区
            HStack {
                // 搜索框
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField("搜索文件名", text: $searchText)
                        .disableAutocorrection(true)
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(8)
                .background(Color(UIColor.systemGray6))
                .cornerRadius(10)
                
                // 筛选按钮
                Button(action: {
                    showingFilterSheet = true
                }) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 20))
                }
                .padding(.leading, 8)
            }
            .padding(.horizontal)
            
            // 排序选项
            HStack {
                Text("排序:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                ForEach(SortOption.allCases, id: \.self) { option in
                    Button(action: {
                        if sortOption == option {
                            sortAscending.toggle()
                        } else {
                            sortOption = option
                            sortAscending = true
                        }
                        sortFoundFiles()
                    }) {
                        HStack(spacing: 2) {
                            Text(option.rawValue)
                                .font(.subheadline)
                            
                            if sortOption == option {
                                Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 12))
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(sortOption == option ? Color.blue.opacity(0.2) : Color.clear)
                        .cornerRadius(4)
                    }
                    .foregroundColor(sortOption == option ? .blue : .primary)
                }
                
                Spacer()
                
                // 选择信息
                if !foundFiles.isEmpty {
                    Text("\(selectedFiles.count)/\(foundFiles.count)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)
            
            // 主内容区域
            if isScanning {
                // 扫描状态显示
                VStack(spacing: 15) {
                    Spacer()
                    
                    ProgressView(value: scanProgress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(width: 200)
                    
                    Text(scanMessage)
                        .font(.headline)
                    
                    if !currentFolder.isEmpty {
                        Text("正在扫描: \(currentFolder)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 300)
                    }
                    
                    Spacer()
                    
                    Button("取消扫描") {
                        cancelScan()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 20)
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red)
                    .cornerRadius(8)
                    
                    Spacer()
                }
                .padding()
            } else if foundFiles.isEmpty {
                // 空状态显示
                VStack(spacing: 20) {
                    Spacer()
                    
                    Image(systemName: "music.note.list")
                        .font(.system(size: 60))
                        .foregroundColor(.blue.opacity(0.7))
                    
                    Text("尚未扫描到音乐文件")
                        .font(.headline)
                    
                    Text("点击下方按钮开始扫描设备中的音乐文件")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Spacer()
                    
                    Button(action: {
                        startScan()
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("开始扫描")
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
            } else {
                // 文件列表
                List {
                    ForEach(filteredFiles, id: \.file) { item in
                        MusicFileRow(
                            file: item,
                            isSelected: selectedFiles.contains(item.file),
                            onToggle: { toggleFileSelection(item.file) }
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                }
                .listStyle(PlainListStyle())
                
                // 底部导入按钮
                VStack(spacing: 0) {
                    Divider()
                    
                    HStack {
                        Button(action: {
                            selectAll(!allSelected)
                        }) {
                            Text(allSelected ? "取消全选" : "全选")
                                .padding(.vertical, 12)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            startScan()
                        }) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("重新扫描")
                            }
                            .padding(.vertical, 12)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            importSelectedFiles()
                        }) {
                            Text("导入选中文件(\(selectedFiles.count))")
                                .fontWeight(.medium)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                .background(selectedFiles.isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .disabled(selectedFiles.isEmpty)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(UIColor.systemBackground))
                }
            }
        }
        .navigationTitle("扫描本机音乐")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("返回") {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showingFilterSheet) {
            FilterView(
                minFileSize: $minFileSize,
                maxFileSize: $maxFileSize,
                selectedFormats: $selectedFormats
            )
        }
        .alert(isPresented: $showResult) {
            Alert(
                title: Text("导入完成"),
                message: Text("成功导入\(importStats.success)首，失败\(importStats.failed)首"),
                dismissButton: .default(Text("确定")) {
                    if importStats.success > 0 {
                        dismiss()
                    }
                }
            )
        }
        .onDisappear {
            // 退出界面时确保取消所有扫描操作
            cancelScan()
        }
    }
    
    // 过滤后的文件列表
    private var filteredFiles: [FoundMusicFile] {
        var filtered = foundFiles
        
        // 应用搜索筛选
        if !searchText.isEmpty {
            filtered = filtered.filter { $0.file.lastPathComponent.lowercased().contains(searchText.lowercased()) }
        }
        
        // 应用格式筛选
        if !selectedFormats.isEmpty {
            filtered = filtered.filter { selectedFormats.contains($0.file.pathExtension.lowercased()) }
        }
        
        // 应用文件大小筛选
        filtered = filtered.filter { 
            let sizeKB = Double($0.size) / 1024.0
            return sizeKB >= minFileSize && sizeKB <= maxFileSize
        }
        
        return filtered
    }
    
    // 是否全部选中
    private var allSelected: Bool {
        !selectedFiles.isEmpty && selectedFiles.count == filteredFiles.count
    }
    
    // 开始扫描
    private func startScan() {
        foundFiles = []
        selectedFiles = []
        isScanning = true
        scanProgress = 0.0
        scanMessage = "正在准备扫描..."
        
        // 获取常用目录
        let locations = getStandardLocations()
        
        // 开始扫描
        scanFolders(locations)
    }
    
    // 取消扫描
    private func cancelScan() {
        // 这里可以添加取消扫描的逻辑
        isScanning = false
    }
    
    // 扫描指定文件夹
    private func scanFolders(_ folders: [URL]) {
        DispatchQueue.global(qos: .background).async {
            var allFoundFiles: [FoundMusicFile] = []
            let totalFolders = folders.count
            
            for (index, folder) in folders.enumerated() {
                // 更新进度
                let progress = Double(index) / Double(totalFolders)
                updateScanStatus(progress: progress, message: "扫描中...\(index+1)/\(totalFolders)", folder: folder.path)
                
                // 扫描单个文件夹
                let folderFiles = scanFolder(folder)
                allFoundFiles.append(contentsOf: folderFiles)
                
                // 更新找到的文件列表
                DispatchQueue.main.async {
                    self.foundFiles = allFoundFiles
                    self.sortFoundFiles()
                }
            }
            
            // 扫描完成
            DispatchQueue.main.async {
                self.isScanning = false
                self.scanProgress = 1.0
                self.scanMessage = "扫描完成，共找到\(allFoundFiles.count)个音乐文件"
                self.foundFiles = allFoundFiles
                self.sortFoundFiles()
            }
        }
    }
    
    // 更新扫描状态
    private func updateScanStatus(progress: Double, message: String, folder: String) {
        DispatchQueue.main.async {
            self.scanProgress = progress
            self.scanMessage = message
            self.currentFolder = folder
        }
    }
    
    // 扫描单个文件夹
    private func scanFolder(_ folder: URL) -> [FoundMusicFile] {
        var results: [FoundMusicFile] = []
        
        // 获取文件管理器
        let fileManager = FileManager.default
        
        // 获取指定路径下的所有内容
        do {
            let contents = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles])
            
            // 遍历所有内容
            for url in contents {
                // 检查是否是目录
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                    if isDirectory.boolValue {
                        // 是目录，递归扫描
                        let subResults = scanFolder(url)
                        results.append(contentsOf: subResults)
                    } else {
                        // 是文件，检查是否是音乐文件
                        if musicFileManager.isSupportedAudioFile(url: url) {
                            // 获取文件大小
                            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                            let fileSize = resourceValues.fileSize ?? 0
                            let modificationDate = resourceValues.contentModificationDate ?? Date()
                            
                            // 添加到结果列表
                            let foundFile = FoundMusicFile(file: url, size: fileSize, modificationDate: modificationDate)
                            results.append(foundFile)
                        }
                    }
                }
            }
        } catch {
            print("扫描文件夹出错: \(folder.path), 错误: \(error.localizedDescription)")
        }
        
        return results
    }
    
    // 获取标准位置
    private func getStandardLocations() -> [URL] {
        var locations: [URL] = []
        
        // 添加文档目录
        if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            locations.append(documentsDirectory)
        }
        
        // 添加下载目录
        if let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            locations.append(downloadsDirectory)
        }
        
        // 添加音乐目录
        if let musicDirectory = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first {
            locations.append(musicDirectory)
        }
        
        return locations
    }
    
    // 选择/取消选择文件
    private func toggleFileSelection(_ url: URL) {
        if selectedFiles.contains(url) {
            selectedFiles.remove(url)
        } else {
            selectedFiles.insert(url)
        }
    }
    
    // 全选/取消全选
    private func selectAll(_ select: Bool) {
        if select {
            // 全选
            selectedFiles = Set(filteredFiles.map { $0.file })
        } else {
            // 取消全选
            selectedFiles.removeAll()
        }
    }
    
    // 排序文件列表
    private func sortFoundFiles() {
        foundFiles.sort { first, second in
            let ascending = sortAscending
            
            switch sortOption {
            case .fileName:
                return ascending ? 
                    first.file.lastPathComponent < second.file.lastPathComponent :
                    first.file.lastPathComponent > second.file.lastPathComponent
            case .fileSize:
                return ascending ?
                    first.size < second.size :
                    first.size > second.size
            case .modificationDate:
                return ascending ?
                    first.modificationDate < second.modificationDate :
                    first.modificationDate > second.modificationDate
            }
        }
    }
    
    // 导入选中的文件
    private func importSelectedFiles() {
        guard !selectedFiles.isEmpty else { return }
        
        isScanning = true
        scanMessage = "正在导入选中的文件..."
        
        let urls = Array(selectedFiles)
        let totalFiles = urls.count
        var successCount = 0
        var failedCount = 0
        
        // 创建调度组
        let importGroup = DispatchGroup()
        
        // 导入每个文件
        for (index, url) in urls.enumerated() {
            importGroup.enter()
            
            // 更新进度
            DispatchQueue.main.async {
                self.scanProgress = Double(index) / Double(totalFiles)
                self.scanMessage = "正在导入文件 (\(index + 1)/\(totalFiles))"
                self.currentFolder = url.lastPathComponent
            }
            
            // 导入文件
            musicFileManager.importMusicFile(from: url) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        successCount += 1
                    case .failure:
                        failedCount += 1
                    }
                    importGroup.leave()
                }
            }
        }
        
        // 所有导入完成后显示结果
        importGroup.notify(queue: .main) {
            self.isScanning = false
            self.importStats = (successCount, failedCount)
            self.showResult = true
            
            // 增加多次延时加载音乐库的机制
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("开始刷新音乐库以加载所有导入的歌曲...")
                self.musicLibrary.loadLocalMusic()
                
                // 第二次延时加载
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    print("再次刷新音乐库以确保所有歌曲已加载完成...")
                    self.musicLibrary.loadLocalMusic()
                    
                    // 第三次延时加载
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        print("第三次刷新音乐库以确保所有歌曲已完全加载...")
                        self.musicLibrary.loadLocalMusic()
                    }
                }
            }
        }
    }
}

// 筛选视图
struct FilterView: View {
    @Environment(\.dismiss)
    
    
    
    var dismiss
    @Binding var minFileSize: Double
    @Binding var maxFileSize: Double
    @Binding var selectedFormats: Set<String>
    
    let allFormats = ["mp3", "wav", "m4a", "flac", "aac", "ogg", "wma"]
    
    var body: some View {
        NavigationView {
            Form {
                // 文件大小范围
                Section(header: Text("文件大小范围 (KB)")) {
                    HStack {
                        Text("最小: \(Int(minFileSize))")
                            .frame(width: 80, alignment: .leading)
                        Slider(value: $minFileSize, in: 0...maxFileSize, step: 100)
                    }
                    
                    HStack {
                        Text("最大: \(Int(maxFileSize))")
                            .frame(width: 80, alignment: .leading)
                        Slider(value: $maxFileSize, in: minFileSize...100000, step: 100)
                    }
                }
                
                // 文件格式
                Section(header: Text("文件格式")) {
                    ForEach(allFormats, id: \.self) { format in
                        Button(action: {
                            toggleFormat(format)
                        }) {
                            HStack {
                                Text(".\(format.uppercased())")
                                
                                Spacer()
                                
                                if selectedFormats.contains(format) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                
                // 重置按钮
                Section {
                    Button("重置筛选条件") {
                        resetFilters()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("筛选选项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("确定") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // 切换格式选择状态
    private func toggleFormat(_ format: String) {
        if selectedFormats.contains(format) {
            selectedFormats.remove(format)
            
            // 确保至少选择一种格式
            if selectedFormats.isEmpty {
                selectedFormats.insert(format)
            }
        } else {
            selectedFormats.insert(format)
        }
    }
    
    // 重置筛选条件
    private func resetFilters() {
        minFileSize = 0
        maxFileSize = 100000
        selectedFormats = Set(allFormats)
    }
}

// 音乐文件行
struct MusicFileRow: View {
    let file: FoundMusicFile
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // 选择指示器
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? .blue : .gray)
                
                // 文件类型图标
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Text(file.file.pathExtension.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.blue)
                }
                
                // 文件信息
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.file.lastPathComponent)
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack {
                        Text(formatFileSize(file.size))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        
                        Text(formatDate(file.modificationDate))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    
                    Text(file.file.deletingLastPathComponent().path)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 6)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // 格式化文件大小
    private func formatFileSize(_ size: Int) -> String {
        let kb = Double(size) / 1024.0
        
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
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// 找到的音乐文件模型
struct FoundMusicFile {
    let file: URL
    let size: Int
    let modificationDate: Date
} 
