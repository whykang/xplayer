import SwiftUI
import UIKit

struct AlbumDetailView: View {
    let album: Album
    @EnvironmentObject var musicLibrary: MusicLibrary
    @ObservedObject var musicPlayer: MusicPlayer
    @State private var isMultiSelecting = false
    @State private var selectedSongs: Set<UUID> = []
    @State private var showingPlaylistSheet = false
    @State private var selectedSong: Song?
    @State private var showingSongPicker = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 专辑封面和信息
                HStack(alignment: .top, spacing: 20) {
                    if let firstSong = album.songs.first,
                       let coverImagePath = firstSong.coverImagePath,
                       let uiImage = UIImage(contentsOfFile: coverImagePath) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 120)
                            .cornerRadius(8)
                            .shadow(radius: 4)
                    } else {
                        Image(systemName: "music.note")
                            .resizable()
                            .scaledToFit()
                            .padding(20)
                            .frame(width: 120, height: 120)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(album.title)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(album.artist)
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("\(album.songs.count) 首歌曲")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Button(action: {
                                // 播放整个专辑
                                if let firstSong = album.songs.first {
                                    // 创建专辑播放列表并播放第一首歌
                                    playAlbum(startingAt: firstSong)
                                }
                            }) {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("播放")
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(20)
                            }
                            
                            Button(action: {
                                // 随机播放专辑
                                if let randomSong = album.songs.randomElement() {
                                    // 随机播放专辑中的歌曲
                                    playAlbum(startingAt: randomSong, shuffle: true)
                                }
                            }) {
                                HStack {
                                    Image(systemName: "shuffle")
                                    Text("随机播放")
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.secondary.opacity(0.2))
                                .foregroundColor(.primary)
                                .cornerRadius(20)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal)
                
                Divider()
                    .padding(.horizontal)
                
                // 多选头部
                if isMultiSelecting {
                    MultiSelectHeaderView(
                        selectedCount: selectedSongs.count,
                        onCancel: { 
                            isMultiSelecting = false
                            selectedSongs.removeAll()
                        },
                        onDelete: deleteSelectedSongs,
                        onAddToPlaylist: showPlaylistSelection
                    )
                }
                
                // 歌曲列表
                songsList
            }
        }
        .padding(.bottom, musicPlayer.currentSong != nil ? 100 : 0)
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
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
        .sheet(isPresented: $showingPlaylistSheet, onDismiss: {
            selectedSong = nil
        }) {
            if let song = selectedSong {
                SingleSongPlaylistSelectionView(song: song)
            } else if !selectedSongs.isEmpty {
                BatchPlaylistSelectionView(songIds: Array(selectedSongs))
            }
        }
        .sheet(isPresented: $showingSongPicker) {
            SongPickerView(album: album)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AddSongToPlaylist"))) { notification in
            if let song = notification.userInfo?["song"] as? Song {
                selectedSong = song
                showingPlaylistSheet = true
            }
        }
    }
    
    // 添加专辑播放方法
    private func playAlbum(startingAt song: Song, shuffle: Bool = false) {
        if shuffle {
            // 设置为随机播放模式
            musicPlayer.playMode = .shuffle
        } else {
            // 设置为正常播放模式
            musicPlayer.playMode = .normal
        }
        
        // 获取专辑中所有歌曲，按曲目排序
        let albumSongs = album.songs.sorted {
            if let track1 = $0.trackNumber, let track2 = $1.trackNumber {
                return track1 < track2
            }
            return $0.title < $1.title
        }
        
        // 找到起始歌曲的索引
        if let index = albumSongs.firstIndex(where: { $0.id == song.id }) {
            // 设置播放列表
            musicPlayer.setPlaylist(songs: albumSongs, startIndex: index)
        } else {
            // 如果找不到，从第一首开始播放
            musicPlayer.setPlaylist(songs: albumSongs, startIndex: 0)
        }
    }
    
    private var songsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(album.songs) { song in
                SongRow(
                    song: song, 
                    isSelected: selectedSongs.contains(song.id),
                    isMultiSelecting: isMultiSelecting,
                    onSelect: { toggleSongSelection(song) },
                    showTrackNumber: true,
                    showDuration: true,
                    highlightIfPlaying: false
                )
                .padding(.horizontal)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                )
                .contextMenu {
                    songContextMenu(song)
                }
            }
        }
        .padding(.vertical)
    }
    
    private func toggleSongSelection(_ song: Song) {
        if selectedSongs.contains(song.id) {
            selectedSongs.remove(song.id)
        } else {
            selectedSongs.insert(song.id)
        }
    }
    
    // 显示歌曲右键菜单
    private func songContextMenu(_ song: Song) -> some View {
        Group {
            Button(action: {
                // 播放歌曲
                MusicPlayer.shared.play(song)
            }) {
                Label("播放", systemImage: "play.fill")
            }
            
            Button(action: {
                // 下一首播放
                MusicPlayer.shared.addToPlaylist(song: song, playNext: true)
            }) {
                Label("下一首播放", systemImage: "text.insert")
            }
            
            Button(action: {
                // 添加到播放列表
                MusicPlayer.shared.addToPlaylist(song: song)
            }) {
                Label("添加到播放列表", systemImage: "text.badge.plus")
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
            
            Divider()
            
            Button(action: {
                // 分享歌曲文件
                let songTitle = song.title
                let artist = song.artist
                let shareText = "\(songTitle) - \(artist)"
                
                var items: [Any] = [shareText]
                
                // 如果有文件URL，添加到分享项目中
                if let fileURL = song.fileURL {
                    items.append(fileURL)
                }
                
                let activityViewController = UIActivityViewController(activityItems: items, applicationActivities: nil)
                
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootViewController = windowScene.keyWindow?.rootViewController {
                    rootViewController.present(activityViewController, animated: true)
                }
            }) {
                Label("分享", systemImage: "square.and.arrow.up")
            }
            
            Button(role: .destructive, action: {
                // 删除操作
                deleteSong(song)
            }) {
                Label("删除", systemImage: "trash")
            }
        }
    }
    
    // 删除单首歌曲
    private func deleteSong(_ song: Song) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }
        
        let alert = UIAlertController(
            title: "删除歌曲",
            message: "确定要删除歌曲\"\(song.title)\"吗？此操作不可撤销。",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { _ in
            // 显示加载指示器
            let loadingAlert = UIAlertController(
                title: "正在删除",
                message: "请稍候...",
                preferredStyle: .alert
            )
            
            rootViewController.present(loadingAlert, animated: true)
            
            // 删除歌曲
            musicLibrary.deleteSong(song) { success in
                DispatchQueue.main.async {
                    // 关闭加载指示器
                    loadingAlert.dismiss(animated: true) {
                        // 显示结果
                        if success {
                            showToast(message: "已删除\"\(song.title)\"", in: rootViewController)
                        } else {
                            let errorAlert = UIAlertController(
                                title: "删除失败",
                                message: "无法完全删除歌曲文件，请稍后再试。",
                                preferredStyle: .alert
                            )
                            
                            errorAlert.addAction(UIAlertAction(title: "确定", style: .default))
                            
                            rootViewController.present(errorAlert, animated: true)
                        }
                    }
                }
            }
        })
        
        rootViewController.present(alert, animated: true)
    }
    
    // 删除选中的歌曲
    private func deleteSelectedSongs() {
        guard !selectedSongs.isEmpty,
              let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }
        
        let songsToDelete = album.songs.filter { selectedSongs.contains($0.id) }
        let count = songsToDelete.count
        
        let alert = UIAlertController(
            title: "批量删除",
            message: "确定要删除选中的\(count)首歌曲吗？此操作不可撤销。",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { _ in
            // 显示加载指示器
            let loadingAlert = UIAlertController(
                title: "正在删除",
                message: "请稍候...",
                preferredStyle: .alert
            )
            
            rootViewController.present(loadingAlert, animated: true)
            
            // 批量删除歌曲
            musicLibrary.deleteSongs(songsToDelete) { success in
                DispatchQueue.main.async {
                    // 关闭加载指示器
                    loadingAlert.dismiss(animated: true) {
                        // 退出多选模式
                        isMultiSelecting = false
                        selectedSongs.removeAll()
                        
                        // 显示结果
                        if success {
                            showToast(message: "已删除\(count)首歌曲", in: rootViewController)
                        } else {
                            let errorAlert = UIAlertController(
                                title: "删除部分失败",
                                message: "部分歌曲文件无法删除，请稍后再试。",
                                preferredStyle: .alert
                            )
                            
                            errorAlert.addAction(UIAlertAction(title: "确定", style: .default))
                            
                            rootViewController.present(errorAlert, animated: true)
                        }
                    }
                }
            }
        })
        
        rootViewController.present(alert, animated: true)
    }
    
    // 显示提示消息
    private func showToast(message: String, in viewController: UIViewController) {
        let toastContainer = UIView(frame: CGRect(x: 0, y: 0, width: 280, height: 50))
        toastContainer.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        toastContainer.layer.cornerRadius = 10
        
        let messageLabel = UILabel(frame: CGRect(x: 0, y: 0, width: 280, height: 50))
        messageLabel.textAlignment = .center
        messageLabel.textColor = .white
        messageLabel.font = UIFont.systemFont(ofSize: 14)
        messageLabel.text = message
        
        toastContainer.addSubview(messageLabel)
        viewController.view.addSubview(toastContainer)
        
        toastContainer.center = viewController.view.center
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
    
    // 批量分享歌曲
    private func shareSelectedSongs() {
        guard !selectedSongs.isEmpty,
              let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }
        
        let songsToShare = album.songs.filter { selectedSongs.contains($0.id) }
        
        // 生成分享文本
        var shareText = "分享\(songsToShare.count)首歌曲：\n"
        for song in songsToShare.prefix(5) {
            shareText += "\(song.title) - \(song.artist)\n"
        }
        if songsToShare.count > 5 {
            shareText += "等\(songsToShare.count)首歌曲"
        }
        
        var items: [Any] = [shareText]
        
        // 添加所有文件URL到分享项目
        for song in songsToShare {
            if let fileURL = song.fileURL {
                items.append(fileURL)
            }
        }
        
        let activityViewController = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        rootViewController.present(activityViewController, animated: true) {
            // 分享完成后退出多选模式
            DispatchQueue.main.async {
                isMultiSelecting = false
                selectedSongs.removeAll()
            }
        }
    }
}

struct AlbumDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            AlbumDetailView(album: Album.examples.first!, musicPlayer: MusicPlayer.shared)
                .environmentObject(MusicLibrary.shared)
        }
    }
} 
