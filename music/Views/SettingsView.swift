import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var musicLibrary: MusicLibrary
    @ObservedObject var musicPlayer = MusicPlayer.shared
    @ObservedObject var userSettings = UserSettings.shared
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showAlert = false
    @State private var alertTitle = "提示"
    @State private var alertMessage = ""
    @State private var showingImportView = false
    @State private var showingClearLibraryConfirmation = false
    @State private var showingClearLibraryView = false
    @State private var showingFeedbackView = false
    @State private var showingEasterEgg = false
    
    var body: some View {
        List {
            Section(header: Text("界面设置")) {
                NavigationLink(destination: TabOrderSettingsView()) {
                    HStack {
                        Text("主标签排序")
                        Spacer()
                        Text("自定义主界面标签顺序")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                NavigationLink(destination: ColorSchemeSettingsView()) {
                    HStack {
                        Text("外观模式")
                        Spacer()
                        Text(userSettings.colorScheme.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section(header: Text("常规设置")) {
                Toggle(isOn: $musicLibrary.enableSmartCoverMatching) {
                    HStack {
                        Text("智能匹配")
                        Spacer()
                    }
                }
                .onChange(of: musicLibrary.enableSmartCoverMatching) { newValue in
                    musicLibrary.updateSmartCoverMatchingSetting(enabled: newValue)
                }
                
                Toggle(isOn: $userSettings.savePlaybackState) {
                    HStack {
                        Text("保存播放状态")
                        Spacer()
                    }
                }
                .onChange(of: userSettings.savePlaybackState) { newValue in
                    print("保存播放状态设置已更改为: \(newValue ? "开启" : "关闭")")
                }
                
                Toggle(isOn: $userSettings.enableCarDisplayLyrics) {
                    HStack {
                        Text("车机歌词显示")
                        Spacer()
                    }
                }
                .onChange(of: userSettings.enableCarDisplayLyrics) { newValue in
                    print("车机歌词显示设置已更改为: \(newValue ? "开启" : "关闭")")
                }
                
                NavigationLink(destination: WebDAVBackupView()) {
                    HStack {
                        Text("备份与恢复")
                        Spacer()
                        Text("WebDAV")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section(header: Text("音乐库")) {
                Button(action: {
                    showingImportView = true
                }) {
                    HStack {
                        Text("导入音乐")
                        Spacer()
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                
                Button(action: {
                    showingClearLibraryView = true
                }) {
                    HStack {
                        Text("清空音乐库")
                        Spacer()
                        Image(systemName: "trash")
                    }
                    .foregroundColor(.red)
                }
                
                Text("已导入 \(musicLibrary.songs.count) 首歌曲")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("关于")) {
                Button(action: {
                    showingFeedbackView = true
                }) {
                    HStack {
                        Text("反馈与建议")
                        Spacer()
                        Image(systemName: "envelope")
                    }
                }
                
                // 添加"去评分"选项
                Button(action: {
                    // 打开App Store评分页面
                    if let url = URL(string: "https://apps.apple.com/app/6744457947?action=write-review") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Text("去评分")
                        Spacer()
                        Image(systemName: "star")
                    }
                }
                
                NavigationLink(destination: AboutView()) {
                    HStack {
                        Text("关于XPlayer")
                        Spacer()
                        Image(systemName: "info.circle")
                    }
                }
                
                HStack {
                    Text("版本")
                    Spacer()
                    Text(getAppVersion())
                        .foregroundColor(.secondary)
                        .onTapGesture(count: 1) {
                            viewModel.handleVersionTap()
                            if viewModel.showEasterEgg {
                                showingEasterEgg = true
                                viewModel.showEasterEgg = false
                            }
                        }
                }
            }
        }
        .navigationTitle("设置")
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                primaryButton: .destructive(Text("确定")) {
                    // 保留一个空的处理函数，或针对其他功能的处理逻辑
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        // 导入音乐弹出窗口
        .sheet(isPresented: $showingImportView) {
            EnhancedImportView()
        }
        // 清空音乐库界面
        .sheet(isPresented: $showingClearLibraryView) {
            ClearMusicLibraryView()
        }
        // 反馈界面
        .sheet(isPresented: $showingFeedbackView) {
            FeedbackView()
        }
        .sheet(isPresented: $showingEasterEgg) {
            EasterEggView()
        }
        // 添加底部间距，防止被迷你播放器挡住
        .padding(.bottom, musicPlayer.currentSong != nil ? 70 : 0)
    }
    
    // 获取应用版本号
    private func getAppVersion() -> String {
        guard let info = Bundle.main.infoDictionary,
              let version = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String else {
            return "未知版本"
        }
        
        // 如果版本号和构建号相同，只显示版本号
        if version == build {
            return version
        } else {
            // 显示版本号(构建号)格式
            return "\(version) (\(build))"
        }
    }
    
    // 清空音乐库
    private func clearMusicLibrary() {
        musicLibrary.songs = []
        musicLibrary.albums = []
        
        // 保留歌单结构，但清空歌单中的歌曲
        for i in 0..<musicLibrary.playlists.count {
            if musicLibrary.playlists[i].name != "我的收藏" {
                musicLibrary.playlists[i].songs = []
            }
        }
        
        // 清空收藏歌单中的歌曲
        musicLibrary.favorites.songs = []
        
        // 保存更改
        musicLibrary.savePlaylists()
        
        // 显示操作成功提示
        alertTitle = "操作成功"
        alertMessage = "音乐库已清空"
        showAlert = true
    }
}

struct TabOrderSettingsView: View {
    @ObservedObject var userSettings = UserSettings.shared
    @State private var editMode: EditMode = .inactive
    
    var body: some View {
        List {
            Section(header: Text("拖动调整标签顺序"), footer: restoreDefaultButton) {
                ForEach(userSettings.tabOrder) { tab in
                    HStack {
                        Image(systemName: tab.systemImage)
                            .foregroundColor(.blue)
                            .frame(width: 30)
                        
                        Text(tab.rawValue)
                    }
                }
                .onMove(perform: moveTab)
            }
        }
        .navigationTitle("主标签排序")
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        }
    }
    
    private var restoreDefaultButton: some View {
        Button(action: {
            withAnimation {
                userSettings.resetTabOrder()
            }
        }) {
            Text("恢复默认顺序")
                .foregroundColor(.blue)
        }
    }
    
    private func moveTab(from source: IndexSet, to destination: Int) {
        userSettings.tabOrder.move(fromOffsets: source, toOffset: destination)
    }
}

struct ColorSchemeSettingsView: View {
    @ObservedObject var userSettings = UserSettings.shared
    
    var body: some View {
        List {
            ForEach(UserSettings.AppColorScheme.allCases, id: \.rawValue) { scheme in
                Button(action: {
                    userSettings.colorScheme = scheme
                }) {
                    HStack {
                        Text(scheme.rawValue)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        if userSettings.colorScheme == scheme {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("外观模式")
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(MusicLibrary.shared)
    }
}

// 清空音乐库视图
struct ClearMusicLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var musicLibrary = MusicLibrary.shared
    @ObservedObject private var musicFileManager = MusicFileManager.shared
    
    // 两步确认
    @State private var showingFirstConfirmation = false
    @State private var showingFinalConfirmation = false
    
    // 显示结果
    @State private var successfullyCleared = false
    @State private var clearingInProgress = false
    @State private var operationMessage = ""
    
    // 清空选项
    @State private var deleteMusicData = true // 删除音乐数据（必选）
    @State private var deletePlaylistsData = true // 删除歌单数据（必选）
    @State private var deleteMusicSourceFiles = false // 删除音乐源文件（可选）
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 顶部图标和提示
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.red)
                    .padding(.top, 40)
                
                Text("清空音乐库")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                if clearingInProgress {
                    ProgressView(operationMessage)
                        .padding(.vertical, 20)
                } else {
                    Text("此操作将清空您的整个音乐库，包括已导入的音乐数据和歌单数据。此操作不可恢复！")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 30)
                        .padding(.bottom, 20)
                    
                    // 清空选项
                    VStack(alignment: .leading, spacing: 15) {
                        Toggle("删除音乐数据", isOn: $deleteMusicData)
                            .tint(.red)
                            .disabled(true) // 必选项，禁用切换
                        
                        Text("将删除所有歌曲信息和专辑封面缓存")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.leading, 5)
                        
                        Divider()
                        
                        Toggle("删除歌单数据", isOn: $deletePlaylistsData)
                            .tint(.red)
                            .disabled(true) // 必选项，禁用切换
                        
                        Text("将删除所有歌单和收藏数据")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.leading, 5)
                        
                        Divider()
                        
                        Toggle("删除音乐源文件", isOn: $deleteMusicSourceFiles)
                            .tint(.red)
                        
                        Text("将删除存储的所有音乐源文件")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.leading, 5)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                    )
                    .padding(.horizontal)
                    
                    // 统计信息
                    VStack(alignment: .leading, spacing: 12) {
                        StatRow(icon: "music.note", title: "歌曲", count: musicLibrary.songs.count)
                        StatRow(icon: "square.stack", title: "专辑", count: musicLibrary.albums.count)
                        StatRow(icon: "music.note.list", title: "歌单", count: musicLibrary.playlists.count)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                    )
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    // 底部操作按钮
                    VStack(spacing: 15) {
                        Button(action: {
                            showingFirstConfirmation = true
                        }) {
                            Text("清空音乐库")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(height: 50)
                                .frame(maxWidth: .infinity)
                                .background(Color.red)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        .disabled(!deleteMusicData && !deletePlaylistsData)
                        
                        Button(action: {
                            dismiss()
                        }) {
                            Text("取消")
                                .font(.headline)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("清空音乐库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            // 第一次确认弹窗
            .alert("确认清空音乐库", isPresented: $showingFirstConfirmation) {
                Button("取消", role: .cancel) {}
                Button("确认", role: .destructive) {
                    showingFinalConfirmation = true
                }
            } message: {
                // 拆分复杂表达式为多个简单子表达式
                let part1 = "您确定要清空音乐库吗？此操作将删除"
                let part2 = deleteMusicData ? "所有音乐数据" : ""
                let part3 = deleteMusicData && deletePlaylistsData ? "和" : ""
                let part4 = deletePlaylistsData ? "所有歌单数据" : ""
                let part5 = "，且无法恢复。"
                
                Text(part1 + part2 + part3 + part4 + part5)
            }
            // 第二次确认弹窗
            .alert("最终确认", isPresented: $showingFinalConfirmation) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) {
                    performClearLibrary()
                }
            } message: {
                Text("请再次确认您要清空音乐库。此操作完成后将无法恢复！")
            }
            // 操作成功弹窗
            .alert("操作成功", isPresented: $successfullyCleared) {
                Button("确定") {
                    dismiss()
                }
            } message: {
                Text("音乐库已清空。")
            }
        }
    }
    
    // 执行清空音乐库操作
    private func performClearLibrary() {
        clearingInProgress = true
        
        // 创建后台任务
        DispatchQueue.global(qos: .userInitiated).async {
            // 1. 删除音乐数据
            if deleteMusicData {
                DispatchQueue.main.async {
                    operationMessage = "正在删除音乐数据..."
                }
                clearMusicData()
            }
            
            // 2. 清空歌单数据
            if deletePlaylistsData {
                DispatchQueue.main.async {
                    operationMessage = "正在清空歌单数据..."
                }
                clearPlaylists()
            }
            
            // 3. 删除音乐源文件
            if deleteMusicSourceFiles {
                DispatchQueue.main.async {
                    operationMessage = "正在删除音乐源文件..."
                }
                clearMusicSourceFiles()
            }
            
            // 4. 清空内存中的歌曲和专辑数据
            DispatchQueue.main.async {
                operationMessage = "正在更新音乐库..."
                musicLibrary.songs = []
                musicLibrary.albums = []
                
                // 保存更新后的歌曲数据
                musicLibrary.saveAllData()
                
                // 完成操作
                clearingInProgress = false
                successfullyCleared = true
            }
        }
    }
    
    // 删除音乐数据
    private func clearMusicData() {
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // 1. 删除歌曲和专辑JSON文件
        let songsJSONPath = documentsDirectory.appendingPathComponent("songs.json")
        if fileManager.fileExists(atPath: songsJSONPath.path) {
            do {
                try fileManager.removeItem(at: songsJSONPath)
                print("已删除歌曲JSON文件")
            } catch {
                print("删除歌曲JSON文件失败: \(error)")
            }
        }
        
        // 2. 删除专辑封面缓存
        let albumCoversDirectory = documentsDirectory.appendingPathComponent("AlbumCovers", isDirectory: true)
        if fileManager.fileExists(atPath: albumCoversDirectory.path) {
            do {
                let fileURLs = try fileManager.contentsOfDirectory(at: albumCoversDirectory, includingPropertiesForKeys: nil)
                for fileURL in fileURLs {
                    try fileManager.removeItem(at: fileURL)
                }
                print("已删除专辑封面缓存")
            } catch {
                print("删除专辑封面缓存失败: \(error)")
            }
        }
        
        // 3. 删除封面图片缓存
        let artworksDirectory = documentsDirectory.appendingPathComponent("Artworks", isDirectory: true)
        if fileManager.fileExists(atPath: artworksDirectory.path) {
            do {
                let fileURLs = try fileManager.contentsOfDirectory(at: artworksDirectory, includingPropertiesForKeys: nil)
                for fileURL in fileURLs {
                    try fileManager.removeItem(at: fileURL)
                }
                print("已删除封面图片缓存")
            } catch {
                print("删除封面图片缓存失败: \(error)")
            }
        }
        
        // 4. 删除艺术家图片缓存
        let artistImagesDirectory = documentsDirectory.appendingPathComponent("ArtistImages", isDirectory: true)
        if fileManager.fileExists(atPath: artistImagesDirectory.path) {
            do {
                let fileURLs = try fileManager.contentsOfDirectory(at: artistImagesDirectory, includingPropertiesForKeys: nil)
                for fileURL in fileURLs {
                    try fileManager.removeItem(at: fileURL)
                }
                print("已删除艺术家图片缓存")
            } catch {
                print("删除艺术家图片缓存失败: \(error)")
            }
        }
    }
    
    // 清空歌单数据
    private func clearPlaylists() {
        if deletePlaylistsData {
            // 1. 删除歌单JSON文件
            let fileManager = FileManager.default
            let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let playlistsJSONPath = documentsDirectory.appendingPathComponent("playlists.json")
            
            if fileManager.fileExists(atPath: playlistsJSONPath.path) {
                do {
                    try fileManager.removeItem(at: playlistsJSONPath)
                    print("已删除歌单JSON文件")
                } catch {
                    print("删除歌单JSON文件失败: \(error)")
                }
            }
            
            // 2. 清空收藏歌单中的歌曲
            musicLibrary.favorites.songs = []
            
            // 3. 完全删除除"我的收藏"外的所有歌单
            musicLibrary.playlists = musicLibrary.playlists.filter { $0.name == "我的收藏" }
            
            // 4. 保存更改
            musicLibrary.savePlaylists()
            
            print("已清空所有歌单数据并删除自定义歌单")
        }
    }
    
    // 删除音乐源文件
    private func clearMusicSourceFiles() {
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let musicDirectory = documentsDirectory.appendingPathComponent("Music", isDirectory: true)
        
        // 检查音乐目录是否存在
        if fileManager.fileExists(atPath: musicDirectory.path) {
            do {
                // 获取目录中的所有文件
                let fileURLs = try fileManager.contentsOfDirectory(at: musicDirectory, includingPropertiesForKeys: nil)
                
                // 逐个删除文件
                for fileURL in fileURLs {
                    try fileManager.removeItem(at: fileURL)
                }
                
                print("已删除所有音乐源文件")
            } catch {
                print("删除音乐源文件时出错: \(error)")
            }
        }
    }
}

// 统计行视图
struct StatRow: View {
    var icon: String
    var title: String
    var count: Int
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .frame(width: 24, height: 24)
            
            Text(title)
                .font(.body)
            
            Spacer()
            
            Text("\(count)")
                .font(.headline)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 8)
    }
}

// 彩蛋视图模型
class SettingsViewModel: ObservableObject {
    private var tapCount = 0
    private var lastTapTime: Date?
    private let tapTimeThreshold: TimeInterval = 1.5 // 连续点击的最大时间间隔（秒）
    
    @Published var showEasterEgg = false
    
    func handleVersionTap() {
        let now = Date()
        
        // 检查是否在时间阈值内
        if let lastTime = lastTapTime, now.timeIntervalSince(lastTime) > tapTimeThreshold {
            // 超过时间阈值，重置计数
            tapCount = 1
        } else {
            // 增加点击计数
            tapCount += 1
        }
        
        // 更新上次点击时间
        lastTapTime = now
        
        // 检查是否达到触发彩蛋的点击次数
        if tapCount >= 6 {
            // 触发彩蛋
            tapCount = 0
            showEasterEgg = true
        }
    }
}

// 彩蛋视图
struct EasterEggView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1
    @State private var colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple]
    @State private var currentColorIndex = 0
    
    let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // 彩色背景
            RadialGradient(
                gradient: Gradient(colors: [colors[currentColorIndex], .black]),
                center: .center,
                startRadius: 50,
                endRadius: 300
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 1), value: currentColorIndex)
            
            VStack(spacing: 30) {
                Text("🎉 彩蛋触发！🎉")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .shadow(radius: 5)
                
                Image(systemName: "music.note")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .foregroundColor(.white)
                    .shadow(radius: 10)
                    .rotationEffect(.degrees(rotation))
                    .scaleEffect(scale)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: rotation)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: scale)
                
                Text("感谢您使用XPlayer！")
                    .font(.title2)
                    .foregroundColor(.white)
                    .shadow(radius: 3)
                    .padding(.top, 20)
                
                Text("祝您聆听愉快，心情舒畅！")
                    .font(.title3)
                    .foregroundColor(.white)
                    .shadow(radius: 3)
                    .padding(.top, 5)
                
                Text("2025.04.10 by Wang Hongyue")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .padding(.horizontal, 30)
                    .padding(.top, 10)
                
                Spacer()
                
                Button(action: {
                    dismiss()
                }) {
                    Text("关闭")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 15)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.6))
                        )
                }
                .padding(.bottom, 50)
            }
            .padding()
        }
        .onReceive(timer) { _ in
            // 动画效果
            rotation += 30
            scale = scale == 1 ? 1.2 : 1
            currentColorIndex = (currentColorIndex + 1) % colors.count
        }
    }
}

// 添加关于页面
struct AboutView: View {
    @ObservedObject var musicPlayer = MusicPlayer.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // App Logo
                Image(systemName: "music.note.list")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundColor(.blue)
                    .padding()
                    .background(
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                    )
                    .padding(.top, 40)
                
                // App名称和版本
                Text("XPlayer")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("版本 \(getAppVersionForAbout())")
                    .foregroundColor(.secondary)
                
                // 分隔线
                Divider()
                    .padding(.horizontal, 50)
                    .padding(.vertical, 20)
                
                // 应用描述
                VStack(alignment: .leading, spacing: 15) {
                    Text("XPlayer是一款简洁、高效的音乐播放器")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    
                    Text("核心功能：")
                        .font(.headline)
                        .padding(.top, 10)
                    
                    AboutFeatureRow(icon: "music.note", title: "本地音乐播放", description: "支持多种格式")
                    AboutFeatureRow(icon: "rectangle.stack", title: "智能歌单管理", description: "轻松创建和管理歌单")
                    AboutFeatureRow(icon: "text.bubble", title: "歌词显示", description: "自动获取和显示歌词")
                    AboutFeatureRow(icon: "photo", title: "专辑封面匹配", description: "自动匹配专辑封面和艺术家图片")
                }
                .padding(.horizontal, 30)
                
                // 分隔线
                Divider()
                    .padding(.horizontal, 50)
                    .padding(.vertical, 20)
                
                // 版权信息
                VStack(spacing: 10) {
                    Text("© 2025 by WangHongyue")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    
                    Text("")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 30)
            }
            // 添加底部间距，防止被迷你播放器挡住
            .padding(.bottom, musicPlayer.currentSong != nil ? 70 : 0)
        }
        .navigationTitle("关于")
    }
    
    // 获取应用版本号（为AboutView使用）
    private func getAppVersionForAbout() -> String {
        guard let info = Bundle.main.infoDictionary,
              let version = info["CFBundleShortVersionString"] as? String else {
            return "未知版本"
        }
        return version
    }
}

// 功能行组件
struct AboutFeatureRow: View {
    var icon: String
    var title: String
    var description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.blue)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
} 
