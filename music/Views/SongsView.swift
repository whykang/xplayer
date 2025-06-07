import SwiftUI
import UIKit
import ObjectiveC
import Combine

// 添加一个环境键用于表示当前在SongsView中
struct InSongsViewKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isInSongsView: Bool {
        get { self[InSongsViewKey.self] }
        set { self[InSongsViewKey.self] = newValue }
    }
}

struct SongsView: View {
    @EnvironmentObject var musicLibrary: MusicLibrary
    @ObservedObject var musicPlayer: MusicPlayer
    
    @State private var searchText = ""
    @State private var showingImportView = false
    @State private var showingPlaylistSheet = false
    @State private var selectedSong: Song?
    @State private var isMultiSelecting = false
    @State private var selectedSongs: Set<UUID> = []
    
    // 添加用于确认删除的状态变量
    @State private var showingDeleteConfirmation = false
    @State private var songToDelete: Song?
    @State private var songsToDelete: [Song] = []
    
    // 添加静态变量以防止重复触发分享
    static var isSharingActive = false
    
    // 添加静态变量跟踪是否有Alert正在显示
    static var isAlertShowing = false
    
    // 添加状态变量跟踪是否已检查封面
    @State private var hasCheckedCovers = false
    
    // 添加歌曲排序菜单状态
    @State private var showingSortMenu = false
    
    // 筛选歌曲
    var filteredSongs: [Song] {
        let songs: [Song]
        
        // 先获取排序后的歌曲列表（置顶歌曲在前）
        if searchText.isEmpty {
            songs = musicLibrary.getSortedSongs() // 使用新方法获取排序后的歌曲
        } else {
            let lowercasedQuery = searchText.lowercased()
            let filteredSongs = musicLibrary.songs.filter { song in
                song.title.lowercased().contains(lowercasedQuery) ||
                song.artist.lowercased().contains(lowercasedQuery) ||
                song.albumName.lowercased().contains(lowercasedQuery)
            }

            // 处理置顶歌曲，置顶歌曲始终在最前面
            let pinnedSongs = filteredSongs.filter { $0.isPinned }
            let unpinnedSongs = filteredSongs.filter { !$0.isPinned }
            
            // 根据排序模式对非置顶歌曲进行排序
            let sortedUnpinnedSongs: [Song]
            
            switch musicLibrary.songSortMode {
            case .creationDate:
                // 按照创建时间排序，根据升序/降序设置决定排序方向
                sortedUnpinnedSongs = unpinnedSongs.sorted { song1, song2 in
                    return musicLibrary.sortAscending ? (song1.creationDate < song2.creationDate) : (song1.creationDate > song2.creationDate)
                }
                
            case .alphabetical:
                // 按照歌曲标题首字母排序，根据升序/降序设置决定排序方向
                sortedUnpinnedSongs = unpinnedSongs.sorted { song1, song2 in
                    let comparison = song1.title.localizedCaseInsensitiveCompare(song2.title)
                    return musicLibrary.sortAscending ? (comparison == .orderedAscending) : (comparison == .orderedDescending)
                }
                
            case .duration:
                // 按照歌曲时长排序，根据升序/降序设置决定排序方向
                sortedUnpinnedSongs = unpinnedSongs.sorted { song1, song2 in
                    return musicLibrary.sortAscending ? (song1.duration < song2.duration) : (song1.duration > song2.duration)
                }
                
            case .artist:
                // 按照艺术家名称排序，根据升序/降序设置决定排序方向
                sortedUnpinnedSongs = unpinnedSongs.sorted { song1, song2 in
                    let comparison = song1.artist.localizedCaseInsensitiveCompare(song2.artist)
                    return musicLibrary.sortAscending ? (comparison == .orderedAscending) : (comparison == .orderedDescending)
                }
                
            case .album:
                // 按照专辑名称排序，根据升序/降序设置决定排序方向
                sortedUnpinnedSongs = unpinnedSongs.sorted { song1, song2 in
                    let comparison = song1.albumName.localizedCaseInsensitiveCompare(song2.albumName)
                    return musicLibrary.sortAscending ? (comparison == .orderedAscending) : (comparison == .orderedDescending)
                }
            }
            
            // 合并置顶歌曲和排序后的非置顶歌曲
            songs = pinnedSongs + sortedUnpinnedSongs
        }
        
        return songs
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                if musicLibrary.isLoading {
                    ProgressView(musicLibrary.loadingMessage)
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                } else if musicLibrary.songs.isEmpty {
                    // 当没有歌曲时显示适当的空视图
                    if musicLibrary.isFirstLaunch {
                        // 首次启动时显示欢迎视图
                        FirstLaunchView(onImport: {
                            showingImportView = true
                        })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // 非首次启动但没有歌曲时显示空视图
                        EmptySongsView(onImport: {
                            showingImportView = true
                        })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack {
                        if isMultiSelecting {
                            MultiSelectHeaderView(
                                selectedCount: selectedSongs.count,
                                onCancel: { 
                                    isMultiSelecting = false
                                    selectedSongs.removeAll()
                                },
                                onDelete: confirmDeleteSelectedSongs,
                                onAddToPlaylist: showPlaylistSelection
                            )
                        }
                        
                        listContent
                        .searchable(text: $searchText, prompt: "搜索歌曲、艺术家或专辑")
                    }
                }
            }
            .navigationTitle("歌曲")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        // 排序按钮
                        Button(action: {
                            showingSortMenu = true
                        }) {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        
                        // 导入按钮
                        Button(action: {
                            showingImportView = true
                        }) {
                            Image(systemName: "square.and.arrow.down")
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    if !musicLibrary.songs.isEmpty {
                        Button(action: {
                            isMultiSelecting.toggle()
                            if !isMultiSelecting {
                                selectedSongs.removeAll()
                            }
                        }) {
                            Image(systemName: isMultiSelecting ? "checkmark.circle.fill" : "checkmark.circle")
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        musicLibrary.loadLocalMusic()
                        // 添加封面检测并下载功能
                        DispatchQueue.global(qos: .userInitiated).async {
                            musicLibrary.checkAndDownloadCovers()
                            DispatchQueue.main.async {
                                hasCheckedCovers = true
                            }
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            // 单首歌曲删除确认弹窗
            .alert("删除歌曲", isPresented: $showingDeleteConfirmation, presenting: songToDelete) { song in
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    performDeleteSong(song)
                }
            } message: { song in
                Text("确定要删除歌曲\"\(song.title)\"吗？此操作不可撤销。")
            }
            // 多首歌曲删除确认弹窗
            .alert("批量删除", isPresented: Binding<Bool>(
                get: { !songsToDelete.isEmpty && !showingDeleteConfirmation },
                set: { if !$0 { songsToDelete = [] } }
            )) {
                Button("取消", role: .cancel) {
                    songsToDelete = []
                }
                Button("删除", role: .destructive) {
                    performDeleteSelectedSongs()
                }
            } message: {
                Text("确定要删除选中的\(songsToDelete.count)首歌曲吗？此操作不可撤销。")
            }
            .sheet(isPresented: $showingPlaylistSheet, onDismiss: {
                selectedSong = nil
            }) {
                if let song = selectedSong {
                    SingleSongPlaylistSelectionView(song: song)
                } else if !selectedSongs.isEmpty {
                    BatchPlaylistSelectionView(songIds: Array(selectedSongs))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AddSongToPlaylist"))) { notification in
                if let song = notification.userInfo?["song"] as? Song {
                    selectedSong = song
                    showingPlaylistSheet = true
                }
            }
            .environment(\.isInSongsView, true)
        }
        .environment(\.isInSongsView, true)
        .sheet(isPresented: $showingImportView) {
            EnhancedImportView()
        }
        .onAppear {
            // 检查并下载缺失的封面图片
            if !hasCheckedCovers && !musicLibrary.songs.isEmpty {
                DispatchQueue.global(qos: .userInitiated).async {
                    musicLibrary.checkAndDownloadCovers()
                    DispatchQueue.main.async {
                        hasCheckedCovers = true
                    }
                }
            }
        }
        // 添加底部弹出的排序选择框
        .sheet(isPresented: $showingSortMenu) {
            VStack(spacing: 0) {
                // 拖动条指示器
                Capsule()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 40, height: 5)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                
                // 标题
                Text("排序方式")
                    .font(.headline)
                    .padding()
                
                Divider()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // 排序模式部分
                        GroupBox(label: 
                            Text("分类")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        ) {
                            VStack(spacing: 0) {
                                ForEach(SongSortMode.allCases, id: \.self) { mode in
                                    Button(action: {
                                        musicLibrary.updateSongSortMode(mode: mode)
                                    }) {
                                        HStack {
                                            Text(mode.rawValue)
                                                .foregroundColor(.primary)
                                            
                                            Spacer()
                                            
                                            if musicLibrary.songSortMode == mode {
                                                Image(systemName: "checkmark")
                                                    .foregroundColor(.blue)
                                            }
                                        }
                                        .padding(.vertical, 12)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    
                                    if mode != SongSortMode.allCases.last {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 16)
                        
                        // 排序方向部分
                        GroupBox(label: 
                            Text("顺序")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        ) {
                            VStack(spacing: 0) {
                                Button(action: {
                                    musicLibrary.updateSortDirection(ascending: true)
                                }) {
                                    HStack {
                                        Text(getAscendingText())
                                            .foregroundColor(.primary)
                                            
                                        Spacer()
                                        
                                        if musicLibrary.sortAscending {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    .padding(.vertical, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Divider()
                                
                                Button(action: {
                                    musicLibrary.updateSortDirection(ascending: false)
                                }) {
                                    HStack {
                                        Text(getDescendingText())
                                            .foregroundColor(.primary)
                                            
                                        Spacer()
                                        
                                        if !musicLibrary.sortAscending {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    .padding(.vertical, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 24)
                }
                
                Divider()
                
                // 关闭按钮
                Button(action: {
                    showingSortMenu = false
                }) {
                    Text("完成")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.bottom, 30)
            }
            .presentationDetents([.height(420)])
            .presentationDragIndicator(.visible)
        }
    }
    
    private var listContent: some View {
        List {
            ForEach(filteredSongs, id: \.id) { song in
                ZStack {
                    SongRow(
                        song: song, 
                        isSelected: selectedSongs.contains(song.id),
                        isMultiSelecting: isMultiSelecting, 
                        onSelect: {
                            toggleSongSelection(song)
                        },
                        showDuration: true,
                        highlightIfPlaying: false
                    )
                    .environment(\.isInSongsView, true)
                    .contextMenu {
                        songContextMenu(song)
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            
            // 添加底部空间，避免被播放器遮挡
            Rectangle()
                .frame(height: 100)
                .foregroundColor(.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(PlainListStyle())
    }
    
    // 显示歌曲右键菜单
    private func songContextMenu(_ song: Song) -> some View {
        Group {
            Button(action: {
                // 播放歌曲
                musicPlayer.play(song)
            }) {
                Label("播放", systemImage: "play.fill")
            }
            
            Button(action: {
                // 下一首播放
                musicPlayer.addToPlaylist(song: song, playNext: true)
            }) {
                Label("下一首播放", systemImage: "text.insert")
            }
            
            Button(action: {
                // 添加到播放列表
                musicPlayer.addToPlaylist(song: song)
            }) {
                Label("添加到播放列表", systemImage: "text.badge.plus")
            }
            
            // 添加置顶/取消置顶选项
            Button(action: {
                // 切换置顶状态
                musicLibrary.togglePinned(song: song)
            }) {
                Label(musicLibrary.isPinned(song: song) ? "取消置顶" : "置顶", 
                      systemImage: musicLibrary.isPinned(song: song) ? "pin.slash" : "pin")
            }
            
            Divider()
            
            Button(action: {
                // 收藏操作
                musicLibrary.toggleFavorite(song: song)
            }) {
                Label(musicLibrary.isFavorite(song: song) ? "取消收藏" : "收藏", 
                      systemImage: musicLibrary.isFavorite(song: song) ? "heart.slash" : "heart")
            }
            
            Button(action: {
                // 显示播放列表选择
                selectedSong = song
                showingPlaylistSheet = true
            }) {
                Label("添加到歌单", systemImage: "music.note.list")
            }
            
            Button(action: {
                // 分享歌曲
                shareSong(song)
            }) {
                Label("分享", systemImage: "square.and.arrow.up")
            }
            
            Divider()
            
            Button(role: .destructive, action: {
                // 删除操作
                confirmDeleteSong(song)
            }) {
                Label("删除", systemImage: "trash")
            }
        }
    }
    
    // 分享单首歌曲
    private func shareSong(_ song: Song) {
        // 防止重复触发分享
        guard !SongsView.isSharingActive else {
            print("歌曲分享-已有分享操作正在进行中，忽略本次请求")
            return
        }
        
        print("歌曲分享-开始分享歌曲: \(song.title)")
        
        // 格式化分享信息
        let songTitle = song.title
        let artist = song.artist
        let shareText = "\(songTitle) - \(artist)"
        
        // 检查是否有封面
        if let coverPath = song.coverImagePath, FileManager.default.fileExists(atPath: coverPath) {
            // 如果有封面，可以使用封面
            if let coverImage = UIImage(contentsOfFile: coverPath) {
                // 使用带封面的分享
                shareWithImage(text: shareText, image: coverImage)
                return
            }
        }
        
        // 如果没有封面，使用纯文本分享
        shareTextOnly(shareText)
    }
    
    // 使用图片进行分享
    private func shareWithImage(text: String, image: UIImage) {
        // 防止重复触发分享
        guard !SongsView.isSharingActive else {
            return
        }
        
        SongsView.isSharingActive = true
        print("歌曲分享-使用图片进行分享")
        
        let activityViewController = UIActivityViewController(activityItems: [text, image], applicationActivities: nil)
        
        // 排除一些活动类型
        activityViewController.excludedActivityTypes = [
            .addToReadingList,
            .assignToContact,
            .openInIBooks
        ]
        
        // 设置完成回调
        activityViewController.completionWithItemsHandler = { (activityType, completed, returnedItems, error) in
            // 重置分享状态
            SongsView.isSharingActive = false
            
            if let error = error {
                print("歌曲分享-分享操作出错: \(error)")
            } else if completed {
                print("歌曲分享-分享操作完成，活动类型: \(activityType?.rawValue ?? "未知")")
            } else {
                print("歌曲分享-分享操作取消")
            }
        }
        
        // 获取UIWindow场景
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            // 在主线程上异步呈现视图控制器
            DispatchQueue.main.async {
                rootViewController.present(activityViewController, animated: true) {
                    print("歌曲分享-分享界面已呈现")
                }
            }
        } else {
            // 没有找到窗口场景时重置状态
            SongsView.isSharingActive = false
            print("歌曲分享-错误: 无法获取窗口场景或根视图控制器")
        }
    }
    
    // 确认删除单首歌曲
    private func confirmDeleteSong(_ song: Song) {
        songToDelete = song
        showingDeleteConfirmation = true
    }
    
    // 执行删除单首歌曲
    private func performDeleteSong(_ song: Song) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }
        
        // 执行删除操作
        musicLibrary.deleteSong(song) { success in
            DispatchQueue.main.async {
                if !success {
                    self.showToast(message: "删除失败，请稍后再试")
                }
            }
        }
    }
    
    // 确认删除选中的歌曲
    private func confirmDeleteSelectedSongs() {
        guard !selectedSongs.isEmpty else { return }
        
        songsToDelete = musicLibrary.songs.filter { selectedSongs.contains($0.id) }
        if !songsToDelete.isEmpty {
            // 弹窗会自动显示，因为我们设置了songsToDelete不为空时显示弹窗
        }
    }
    
    // 执行删除选中的歌曲
    private func performDeleteSelectedSongs() {
        guard !songsToDelete.isEmpty,
              let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }
        
        // 执行删除操作
        musicLibrary.deleteSongs(songsToDelete) { success in
            DispatchQueue.main.async {
                // 退出多选模式
                self.isMultiSelecting = false
                self.selectedSongs.removeAll()
                self.songsToDelete = []
                
                if !success {
                    self.showToast(message: "部分歌曲删除失败，请稍后再试")
                }
            }
        }
    }
    
    // 切换歌曲选择状态
    private func toggleSongSelection(_ song: Song) {
        if selectedSongs.contains(song.id) {
            selectedSongs.remove(song.id)
        } else {
            selectedSongs.insert(song.id)
        }
    }
    
    // 显示提示消息
    private func showToast(message: String) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.keyWindow else {
            return
        }
        
        let toastContainer = UIView(frame: CGRect(x: 0, y: 0, width: 280, height: 50))
        toastContainer.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        toastContainer.layer.cornerRadius = 10
        
        let messageLabel = UILabel(frame: CGRect(x: 0, y: 0, width: 280, height: 50))
        messageLabel.textAlignment = .center
        messageLabel.textColor = .white
        messageLabel.font = UIFont.systemFont(ofSize: 14)
        messageLabel.text = message
        
        toastContainer.addSubview(messageLabel)
        window.addSubview(toastContainer)
        
        toastContainer.center = window.center
        toastContainer.alpha = 0
        
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn, animations: {
            toastContainer.alpha = 1
        }, completion: { _ in
            UIView.animate(withDuration: 0.2, delay: 1.5, options: .curveEaseOut, animations: {
                toastContainer.alpha = 0
            }, completion: { _ in
                toastContainer.removeFromSuperview()
            })
        })
    }
    
    // 显示播放列表选择
    private func showPlaylistSelection() {
        if !selectedSongs.isEmpty {
            showingPlaylistSheet = true
        }
    }
    
    // 仅分享文本信息
    private func shareTextOnly(_ text: String, fileURL: URL? = nil) {
        // 防止重复触发分享
        guard !SongsView.isSharingActive else {
            print("歌曲列表界面-已有分享操作正在进行中，忽略本次请求")
            return
        }
        
        SongsView.isSharingActive = true
        print("歌曲列表界面-仅分享文本信息")
        
        let activityViewController = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        
        // 排除一些活动类型
        activityViewController.excludedActivityTypes = [
            .addToReadingList,
            .assignToContact,
            .openInIBooks
        ]
        
        // 设置完成回调
        activityViewController.completionWithItemsHandler = { (activityType, completed, returnedItems, error) in
            // 重置分享状态
            SongsView.isSharingActive = false
            
            if let error = error {
                print("歌曲列表界面-分享操作出错: \(error)")
            } else if completed {
                print("歌曲列表界面-分享操作完成，活动类型: \(activityType?.rawValue ?? "未知")")
            } else {
                print("歌曲列表界面-分享操作取消")
            }
        }
        
        // 获取UIWindow场景
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            // 在主线程上异步呈现视图控制器
            DispatchQueue.main.async {
                rootViewController.present(activityViewController, animated: true) {
                    print("歌曲列表界面-分享界面已呈现")
                }
            }
        } else {
            // 没有找到窗口场景时重置状态
            SongsView.isSharingActive = false
            print("歌曲列表界面-错误: 无法获取窗口场景或根视图控制器")
        }
    }
    
    private func getAscendingText() -> String {
        switch musicLibrary.songSortMode {
        case .creationDate:
            return "正序(旧→新)"
        case .alphabetical:
            return "正序(A→Z)"
        case .duration:
            return "正序(短→长)"
        case .artist:
            return "正序(A→Z)"
        case .album:
            return "正序(A→Z)"
        }
    }
    
    private func getDescendingText() -> String {
        switch musicLibrary.songSortMode {
        case .creationDate:
            return "倒序(新→旧)"
        case .alphabetical:
            return "倒序(Z→A)"
        case .duration:
            return "倒序(长→短)"
        case .artist:
            return "倒序(Z→A)"
        case .album:
            return "倒序(Z→A)"
        }
    }
}

// 空歌曲列表视图（非首次启动）
struct EmptySongsView: View {
    var onImport: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list")
                .font(.system(size: 70))
                .foregroundColor(.gray)
            
            Text("没有歌曲")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text("导入音乐文件开始欣赏")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: onImport) {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text("导入音乐")
                }
                .padding(.horizontal, 25)
                .padding(.vertical, 12)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(25)
            }
            .padding(.top, 20)
        }
        .padding()
    }
}

// 首次启动欢迎视图
struct FirstLaunchView: View {
    var onImport: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // 顶部欢迎图标
            Image(systemName: "music.note")
                .font(.system(size: 80))
                .foregroundColor(.blue)
                .padding()
                .background(
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 160, height: 160)
                )
            
            // 欢迎标题
            Text("欢迎使用XPlayer")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            // 欢迎说明
            Text("开始导入您的音乐文件，打造专属的音乐库")
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            // 功能说明
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "music.note.list", title: "音乐管理", description: "组织和管理您的音乐文件")
                FeatureRow(icon: "heart.fill", title: "收藏歌曲", description: "收藏您最喜欢的音乐")
                FeatureRow(icon: "person.fill", title: "艺术家分类", description: "按艺术家浏览您的音乐库")
                FeatureRow(icon: "music.note.list", title: "创建歌单", description: "创建自定义歌单满足不同场景")
            }
            .padding(.vertical, 20)
            
            // 开始按钮
            Button(action: onImport) {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text("开始导入音乐")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(15)
            }
            .padding(.horizontal, 32)
            .padding(.top, 10)
        }
        .padding()
    }
}

// 功能介绍行
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.blue)
                .frame(width: 30, height: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }
}

struct SongsView_Previews: PreviewProvider {
    static var previews: some View {
        SongsView(musicPlayer: MusicPlayer.shared)
    }
} 
