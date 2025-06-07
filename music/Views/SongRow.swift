import SwiftUI
import ObjectiveC

struct SongRow: View {
    let song: Song
    @EnvironmentObject var musicLibrary: MusicLibrary
    @ObservedObject private var musicPlayer = MusicPlayer.shared
    @Environment(\.isInSongsView) private var isInSongsView
    
    var isSelected: Bool = false
    var isMultiSelecting: Bool = false
    var onSelect: (() -> Void)? = nil
    var showTrackNumber: Bool = false
    var showDuration: Bool = false
    var showAlbumName: Bool = false
    var highlightIfPlaying: Bool = true
    var disablePlayOnTap: Bool = false
    var onRowTap: (() -> Void)? = nil
    
    // 控制添加到歌单的选择器显示
    @State private var showingPlaylistSheet = false
    
    // 添加删除确认弹窗状态
    @State private var showingDeleteConfirmation = false
    
    // 添加编辑相关状态
    @State private var showingEditView = false
    
    // 添加静态属性以跟踪分享操作
    static var isSharingActive = false
    static var lastShareAttemptTime: TimeInterval = 0
    static var sharingTimer: Timer?
    
    // 添加静态变量跟踪是否有Alert正在显示
    static var isAlertShowing = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                // 多选模式下的选择图标
                if isMultiSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .font(.title3)
                        .frame(width: 24)
                        .onTapGesture {
                            onSelect?()
                        }
                }
                
                // 音轨编号
                if showTrackNumber, let trackNumber = song.trackNumber {
                    Text("\(trackNumber)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(width: 30, alignment: .center)
                }
                
                // 歌曲封面
                if let coverImagePath = song.coverImagePath,
                   let uiImage = UIImage(contentsOfFile: coverImagePath) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .cornerRadius(6)
                } else {
                    Image(systemName: "music.note")
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                        .frame(width: 50, height: 50)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(6)
                }
                
                // 歌曲信息
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(song.title)
                            .font(.system(size: 16, weight: isCurrentlyPlaying ? .bold : .regular))
                            .foregroundColor(isCurrentlyPlaying ? Color.accentColor : .primary)
                            .lineLimit(1)
                        
                        // 显示音频文件格式
                        if !song.fileFormat.isEmpty {
                            Text(song.fileFormat)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(3)
                        }
                        
                        // 显示置顶标记 - 只在SongsView中显示
                        if song.isPinned && isInSongsView {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                        }
                    }
                    
                    HStack {
                        Text(song.artist)
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                        
                        if showAlbumName {
                            Text("•")
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                                .padding(.horizontal, 2)
                            
                            Text(song.albumName)
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.leading, 4)
                
                Spacer()
                
                // 显示时长
                if showDuration {
                    Text(formatDuration(song.duration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.trailing, 4)
                }
                
                // 改进的播放按钮
                if !isMultiSelecting {
                    Button(action: {
                        if isCurrentlyPlaying {
                            // 如果当前正在播放此歌曲，则切换播放/暂停状态
                            musicPlayer.playPause()
                        } else {
                            // 不是当前播放的歌曲，则播放此歌曲
                            musicPlayer.play(song)
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(isCurrentlyPlaying ? Color.accentColor.opacity(0.15) : Color.clear)
                                .frame(width: 36, height: 36)
                            
                            if isCurrentlyPlaying {
                                // 当前播放的歌曲
                                Image(systemName: musicPlayer.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(Color.accentColor)
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                // 非当前播放的歌曲
                                Image(systemName: "play.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.primary.opacity(0.7))
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: isCurrentlyPlaying)
                        .animation(.easeInOut(duration: 0.2), value: musicPlayer.isPlaying)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    
                    // 新增的选项菜单
                    Menu {
                        Button(action: {
                            musicPlayer.addToPlaylist(song: song, playNext: true)
                        }) {
                            Label("下一首播放", systemImage: "text.insert")
                        }
                        
                        Button(action: {
                            musicPlayer.addToPlaylist(song: song)
                        }) {
                            Label("添加到播放列表", systemImage: "text.badge.plus")
                        }
                        
                        Button(action: {
                            _ = musicLibrary.toggleFavorite(song: song)
                        }) {
                            Label(
                                musicLibrary.isFavorite(song: song) ? "取消收藏" : "收藏", 
                                systemImage: musicLibrary.isFavorite(song: song) ? "heart.slash" : "heart"
                            )
                        }
                        
                        // 只在歌曲界面(SongsView)中显示置顶选项
                        if isInSongsView {
                            Button(action: {
                                musicLibrary.togglePinned(song: song)
                            }) {
                                Label(
                                    musicLibrary.isPinned(song: song) ? "取消置顶" : "置顶", 
                                    systemImage: musicLibrary.isPinned(song: song) ? "pin.slash" : "pin"
                                )
                            }
                        }
                        
                        Button(action: {
                            showingPlaylistSheet = true
                        }) {
                            Label("添加到歌单", systemImage: "music.note.list")
                        }
                        
                        Button(action: {
                            shareAction()
                        }) {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                        
                        // 添加编辑信息按钮
                        Button(action: {
                            showingEditView = true
                        }) {
                            Label("编辑信息", systemImage: "pencil")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive, action: {
                            confirmDelete()
                        }) {
                            Label("删除", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                }
            }
            .padding(.vertical, 12)
            .background(shouldHighlight ? Color.accentColor.opacity(0.1) : Color.clear)
            
            Divider()
                .background(Color.gray.opacity(0.3))
                .padding(.leading, showTrackNumber ? 60 : 54)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // 防止播放列表选择视图显示时触发点击操作
            guard !showingPlaylistSheet else { return }
            
            if isMultiSelecting {
                onSelect?()
            } else if onRowTap != nil {
                onRowTap?()
            } else {
                let isCurrentlyPlaying = musicPlayer.currentSong?.id == song.id
                
                // 使用环境变量检测是否在SongsView中
                print("通过环境变量检测到：isInSongsView = \(isInSongsView)")
                
                if isInSongsView {
                    print("在SongsView中点击歌曲，将所有歌曲添加到播放列表")
                    
                    if isCurrentlyPlaying {
                        // 如果点击当前播放的歌曲，则切换播放/暂停状态
                        musicPlayer.playPause()
                    } else {
                        // 获取歌曲列表
                        let allSongs = musicLibrary.songs
                        print("获取到全部歌曲列表，共\(allSongs.count)首歌曲")
                        
                        // 找到当前歌曲在列表中的索引
                        if let songIndex = allSongs.firstIndex(where: { $0.id == song.id }) {
                            print("找到歌曲在列表中的索引: \(songIndex)，将设置播放列表并从该歌曲开始播放")
                            // 设置播放列表并从当前歌曲开始播放
                            musicPlayer.setPlaylist(songs: allSongs, startIndex: songIndex)
                            
                            // 打印播放列表信息以验证设置成功
                            let currentPlaylist = musicPlayer.getCurrentPlaylist()
                            print("当前播放列表已设置，包含\(currentPlaylist.count)首歌曲")
                        } else {
                            // 如果找不到歌曲（这种情况不应该发生），就只播放这一首
                            print("未能在全部歌曲中找到当前歌曲，将只播放当前歌曲")
                            musicPlayer.play(song)
                        }
                    }
                } else {
                    // 正常的播放逻辑
                    if isCurrentlyPlaying {
                        // 如果点击当前播放的歌曲，则切换播放/暂停状态
                        musicPlayer.playPause()
                    } else {
                        // 否则播放此歌曲
                        musicPlayer.play(song)
                    }
                }
            }
        }
        .sheet(isPresented: $showingPlaylistSheet) {
            SingleSongPlaylistSelectionView(song: song)
                .onAppear {
                    // 当歌单选择视图出现时，暂时禁用点击播放功能
                    if isCurrentlyPlaying && musicPlayer.currentSong?.id == song.id {
                        musicPlayer.pause()
                    }
                }
        }
        // 删除确认弹窗
        .alert("删除歌曲", isPresented: $showingDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                deleteAction()
            }
        } message: {
            Text("确定要删除歌曲\"\(song.title)\"吗？此操作不可撤销。")
        }
        .sheet(isPresented: $showingEditView) {
            SongEditView(song: song)
        }
    }
    
    // 显示删除确认弹窗
    private func confirmDelete() {
        showingDeleteConfirmation = true
    }
    
    // 删除操作
    private func deleteAction() {
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
    
    // 显示Toast提示
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
    
    // 分享操作
    private func shareAction() {
        // 防止重复触发分享
        guard !SongRow.isSharingActive else {
            print("歌曲行-已有分享操作正在进行中，忽略本次请求")
            return
        }
        
        // 检查两次分享之间的时间间隔，防止快速连续点击
        let currentTime = Date().timeIntervalSince1970
        if currentTime - SongRow.lastShareAttemptTime < 1.0 {
            print("歌曲行-分享操作请求过于频繁，忽略本次请求")
            return
        }
        
        SongRow.lastShareAttemptTime = currentTime
        SongRow.isSharingActive = true
        print("歌曲行-开始执行分享操作: \(song.title)")
        print("Debug: 当前线程 - \(Thread.isMainThread ? "主线程" : "后台线程")")
        
        // 设置超时计时器，防止界面挂起
        SongRow.sharingTimer?.invalidate()
        SongRow.sharingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            if SongRow.isSharingActive {
                print("歌曲行-分享操作超时，强制重置状态")
                SongRow.isSharingActive = false
            }
        }
        
        // 准备分享的内容
        var itemsToShare: [Any] = []
        
        // 使用getShareableFileURL方法获取可分享的文件URL
        if let shareableURL = song.getShareableFileURL() {
            print("歌曲行-获取到可分享的文件URL: \(shareableURL.path)")
            
            // 获取安全访问权限
            let secureAccess = shareableURL.startAccessingSecurityScopedResource()
            
            // 确保在操作完成后停止访问
            defer {
                if secureAccess {
                    shareableURL.stopAccessingSecurityScopedResource()
                }
            }
            
            // 添加文件URL到分享项目
            itemsToShare.append(shareableURL)
            print("歌曲行-分享歌曲文件: \(shareableURL.lastPathComponent)")
        } else {
            // 没有可分享的文件URL，回退到文本分享
            let shareText = "\(song.title) - \(song.artist)"
            itemsToShare.append(shareText)
            print("歌曲行-无法获取可分享的文件URL，使用文本分享")
        }
        
        // 使用UIActivityViewController分享
        let activityViewController = UIActivityViewController(activityItems: itemsToShare, applicationActivities: nil)
        
        // 排除一些活动类型
        activityViewController.excludedActivityTypes = [
            .addToReadingList,
            .assignToContact,
            .openInIBooks
        ]
        
        // 设置完成回调
        activityViewController.completionWithItemsHandler = { (activityType, completed, returnedItems, error) in
            // 取消超时计时器
            SongRow.sharingTimer?.invalidate()
            SongRow.sharingTimer = nil
            
            // 重置分享状态
            SongRow.isSharingActive = false
            
            if let error = error {
                print("歌曲行-分享操作出错: \(error)")
            } else if completed {
                print("歌曲行-分享操作完成，活动类型: \(activityType?.rawValue ?? "未知")")
            } else {
                print("歌曲行-分享操作取消")
            }
        }
        
        // 在主线程上执行UI操作
        DispatchQueue.main.async {
            print("歌曲行-正在准备呈现分享界面")
            
            // 使用全局方法获取顶层视图控制器
            if let topViewController = UIApplication.getTopViewController() {
                // 直接在顶层视图控制器上呈现分享视图
                topViewController.present(activityViewController, animated: true) {
                    print("歌曲行-分享界面已呈现")
                }
            } else {
                // 如果获取顶层视图控制器失败，则尝试替代方法
                print("歌曲行-使用备选方法获取视图控制器")
                
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    // 尝试获取keyWindow
                    if let keyWindow = windowScene.keyWindow, let rootViewController = keyWindow.rootViewController {
                        var topVC = rootViewController
                        while let presentedVC = topVC.presentedViewController {
                            topVC = presentedVC
                        }
                        
                        topVC.present(activityViewController, animated: true) {
                            print("歌曲行-分享界面已呈现")
                        }
                    } else if let window = windowScene.windows.first, let rootViewController = window.rootViewController {
                        // 使用windows.first
                        var topVC = rootViewController
                        while let presentedVC = topVC.presentedViewController {
                            topVC = presentedVC
                        }
                        
                        topVC.present(activityViewController, animated: true) {
                            print("歌曲行-分享界面已呈现")
                        }
                    } else {
                        SongRow.isSharingActive = false
                        SongRow.sharingTimer?.invalidate()
                        SongRow.sharingTimer = nil
                        print("歌曲行-错误: 无法获取根视图控制器")
                    }
                } else {
                    SongRow.isSharingActive = false
                    SongRow.sharingTimer?.invalidate()
                    SongRow.sharingTimer = nil
                    print("歌曲行-错误: 无法获取窗口场景")
                }
            }
        }
    }
    
    // 检查是否为当前正在播放的歌曲
    private var isCurrentlyPlaying: Bool {
        musicPlayer.currentSong?.id == song.id
    }
    
    // 确定是否应该高亮显示
    private var shouldHighlight: Bool {
        highlightIfPlaying && isCurrentlyPlaying
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
