import SwiftUI
import UIKit

struct ArtistsView: View {
    @EnvironmentObject var musicLibrary: MusicLibrary
    @ObservedObject var musicPlayer: MusicPlayer
    @State private var searchText = ""
    
    // 筛选艺术家
    var filteredArtists: [String: [Song]] {
        let songs = searchText.isEmpty ? musicLibrary.songs : musicLibrary.songs.filter { song in
            song.artist.lowercased().contains(searchText.lowercased()) ||
            song.title.lowercased().contains(searchText.lowercased())
        }
        
        // 按艺术家分组
        let groupedSongs = Dictionary(grouping: songs) { $0.artist }
        
        // 按艺术家名称排序
        return groupedSongs
    }
    
    // 排序后的艺术家列表
    var sortedArtists: [String] {
        filteredArtists.keys.sorted()
    }
    
    var body: some View {
        Group {
            if musicLibrary.isLoading {
                ProgressView(musicLibrary.loadingMessage)
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
            } else if sortedArtists.isEmpty {
                EmptyArtistsView()
            } else {
                List {
                    ForEach(sortedArtists, id: \.self) { artist in
                        NavigationLink(destination: ArtistDetailView(artist: artist, songs: filteredArtists[artist] ?? [], musicPlayer: musicPlayer)) {
                            ArtistRow(artist: artist, songCount: filteredArtists[artist]?.count ?? 0)
                        }
                    }
                    
                    // 添加底部空间，避免被播放器遮挡
                    Rectangle()
                        .frame(height: 100)
                        .foregroundColor(.clear)
                        .listRowSeparator(.hidden)
                }
                .listStyle(PlainListStyle())
            }
        }
        .navigationTitle("艺术家")
        .searchable(text: $searchText, prompt: "搜索艺术家")
    }
}

// 空艺术家视图
struct EmptyArtistsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.mic")
                .font(.system(size: 70))
                .foregroundColor(.gray)
            
            Text("没有艺术家")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text("导入音乐文件以查看艺术家")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// 艺术家行视图
struct ArtistRow: View {
    let artist: String
    let songCount: Int
    
    var body: some View {
        HStack {
            ArtistImageView(size: 50, artistName: artist)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(artist)
                    .font(.headline)
                    .lineLimit(1)
                
                Text("\(songCount) 首歌曲")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.leading, 10)
        }
        .padding(.vertical, 4)
    }
}

// 艺术家图片视图
struct ArtistImageView: View {
    let size: CGFloat
    let artistName: String
    @State private var artistImageURL: URL? = nil
    
    var body: some View {
        AsyncImage(url: artistImageURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            case .failure(_), .empty:
                fallbackImage
            @unknown default:
                fallbackImage
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            fetchArtistImage()
        }
    }
    
    private var fallbackImage: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: size, height: size)
            
            Image(systemName: "music.mic")
                .foregroundColor(.gray)
                .font(.system(size: size * 0.4))
        }
    }

    // 获取艺术家图片缓存目录
    private func getArtistImagesDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        let artistImagesDirectory = documentsDirectory.appendingPathComponent("ArtistImages", isDirectory: true)
        
        // 确保目录存在
        if !FileManager.default.fileExists(atPath: artistImagesDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: artistImagesDirectory, withIntermediateDirectories: true)
            } catch {
                print("创建艺术家图片目录失败: \(error)")
            }
        }
        
        return artistImagesDirectory
    }
    
    // 获取艺术家图片本地缓存路径
    private func getLocalImagePath(for artistName: String) -> URL {
        let sanitizedName = artistName.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return getArtistImagesDirectory().appendingPathComponent("\(sanitizedName).jpg")
    }
    
    // 从URL下载图片并保存到本地
    private func downloadAndSaveImage(from imageURL: URL, to localURL: URL) {
        URLSession.shared.dataTask(with: imageURL) { data, response, error in
            if let error = error {
                print("下载艺术家图片失败: \(error.localizedDescription)")
                return
            }
            
            guard let data = data, let _ = UIImage(data: data) else {
                print("无效的图片数据")
                return
            }
            
            do {
                try data.write(to: localURL)
                print("艺术家图片已保存到: \(localURL.path)")
                
                // 更新UI显示
                DispatchQueue.main.async {
                    self.artistImageURL = localURL
                }
            } catch {
                print("保存艺术家图片失败: \(error.localizedDescription)")
            }
        }.resume()
    }
    
    private func fetchArtistImage() {
        // 检查本地是否已有缓存
        let localImageURL = getLocalImagePath(for: artistName)
        
        if FileManager.default.fileExists(atPath: localImageURL.path) {
            print("从本地加载艺术家图片: \(localImageURL.path)")
            DispatchQueue.main.async {
                self.artistImageURL = localImageURL
            }
            return
        }
        
        // 检查智能艺术家图片匹配设置是否开启
        if !MusicLibrary.shared.enableArtistImageMatching {
            print("智能艺术家图片匹配已关闭，不从网络获取艺术家图片")
            return
        }
        
        // 本地没有缓存，从服务器获取
        print("本地无缓存图片，从服务器获取: \(artistName)")
        
        // 对艺术家名称进行URL编码
        guard let encodedName = artistName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            print("错误：无法对艺术家名称进行URL编码")
            return
        }
        
        // 构造API请求URL - 使用新的API地址和参数格式 需要自己实现
        let apiUrlString = ""
        print("请求艺术家图片API：\(apiUrlString)")
        
        guard let apiUrl = URL(string: apiUrlString) else {
            print("错误：无效的API URL")
            return
        }
        
        // 创建网络请求
        URLSession.shared.dataTask(with: apiUrl) { data, response, error in
            if let error = error {
                print("网络请求错误：\(error.localizedDescription)")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("API响应状态码：\(httpResponse.statusCode)")
            }
            
            guard let data = data else {
                print("错误：API返回空数据")
                return
            }
            
            // 解析JSON响应
            do {
                if let jsonStr = String(data: data, encoding: .utf8) {
                    print("API原始响应: \(jsonStr)")
                }
                
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("解析的JSON：\(json)")
                    
                    // 处理新的API响应格式
                    if let imageUrl = json["web_artistpic_short"] as? String {
                        print("获取到艺术家图片URL: \(imageUrl)")
                        
                        // 从服务器下载图片并保存到本地
                        if let remoteURL = URL(string: imageUrl) {
                            downloadAndSaveImage(from: remoteURL, to: localImageURL)
                        } else {
                            print("错误：无效的图片URL: \(imageUrl)")
                        }
                    } else {
                        print("错误：'web_artistpic_short'字段不存在或不是字符串")
                    }
                } else {
                    print("错误：JSON解析失败，无效的格式")
                }
            } catch {
                print("解析艺术家图片数据失败: \(error.localizedDescription)")
                
                // 尝试打印原始数据，帮助调试
                if let rawString = String(data: data, encoding: .utf8) {
                    print("原始响应数据: \(rawString)")
                }
            }
        }.resume()
    }
}

// 艺术家详情视图
struct ArtistDetailView: View {
    let artist: String
    let songs: [Song]
    @EnvironmentObject var musicLibrary: MusicLibrary
    @ObservedObject var musicPlayer: MusicPlayer
    @State private var isMultiSelecting = false
    @State private var selectedSongs: Set<UUID> = []
    @State private var showingPlaylistSheet = false
    @State private var selectedSong: Song?
    
    // 按专辑分组的歌曲
    var songsByAlbum: [String: [Song]] {
        Dictionary(grouping: songs) { $0.albumName }
    }
    
    // 专辑名称排序
    var sortedAlbums: [String] {
        songsByAlbum.keys.sorted()
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 艺术家头部
                VStack(spacing: 10) {
                    ArtistImageView(size: 120, artistName: artist)
                    
                    Text(artist)
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("\(songs.count) 首歌曲")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 20) {
                        Button(action: {
                            musicPlayer.setPlaylist(songs: songs, startIndex: 0)
                        }) {
                            Text("播放全部")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .cornerRadius(20)
                        }
                        
                        Button(action: {
                            musicPlayer.setPlaylist(songs: songs.shuffled(), startIndex: 0)
                        }) {
                            Text("随机播放")
                                .font(.headline)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(20)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                
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
                    .padding(.horizontal)
                }
                
                // 按专辑分组显示歌曲
                ForEach(sortedAlbums, id: \.self) { album in
                    VStack(alignment: .leading, spacing: 10) {
                        // 专辑标题
                        Text(album)
                            .font(.title3)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                        
                        // 专辑内的歌曲
                        ForEach(songsByAlbum[album] ?? []) { song in
                            SongRow(
                                song: song, 
                                isSelected: selectedSongs.contains(song.id),
                                isMultiSelecting: isMultiSelecting, 
                                onSelect: { toggleSongSelection(song) },
                                showDuration: true,
                                showAlbumName: false
                            )
                            .contextMenu {
                                songContextMenu(song)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
        }
        .padding(.bottom, musicPlayer.currentSong != nil ? 100 : 0)
        .navigationTitle(artist)
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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AddSongToPlaylist"))) { notification in
            if let song = notification.userInfo?["song"] as? Song {
                selectedSong = song
                showingPlaylistSheet = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DeleteSong"))) { notification in
            if let song = notification.userInfo?["song"] as? Song {
                deleteSong(song)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ToggleFavorite"))) { notification in
            if let song = notification.userInfo?["song"] as? Song {
                musicLibrary.toggleFavorite(song: song)
            }
        }
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
            
            Divider()
            
            Button(action: {
                // 收藏操作
                musicLibrary.toggleFavorite(song: song)
            }) {
                Label(musicLibrary.isFavorite(song: song) ? "取消收藏" : "收藏", 
                      systemImage: musicLibrary.isFavorite(song: song) ? "heart.slash" : "heart")
            }
            
            Button(action: {
                // 添加到歌单
                selectedSong = song
                showingPlaylistSheet = true
            }) {
                Label("添加到歌单", systemImage: "music.note.list")
            }
            
            Button(action: {
                // 分享歌曲
                let songTitle = song.title
                let artist = song.artist
                let shareText = "\(songTitle) - \(artist)"
                
                var items: [Any] = [shareText]
                
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
            
            Divider()
            
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
                            self.showToast(message: "已删除\"\(song.title)\"", in: rootViewController)
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
        
        let songsToDelete = songs.filter { selectedSongs.contains($0.id) }
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
                        self.isMultiSelecting = false
                        self.selectedSongs.removeAll()
                        
                        // 显示结果
                        if success {
                            // 显示成功提示
                            let successAlert = UIAlertController(
                                title: "删除成功",
                                message: "已删除\(count)首歌曲",
                                preferredStyle: .alert
                            )
                            successAlert.addAction(UIAlertAction(title: "确定", style: .default))
                            rootViewController.present(successAlert, animated: true)
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
    
    // 切换歌曲选择状态
    private func toggleSongSelection(_ song: Song) {
        if selectedSongs.contains(song.id) {
            selectedSongs.remove(song.id)
        } else {
            selectedSongs.insert(song.id)
        }
    }
    
    // 显示提示消息
    func showToast(message: String, in viewController: UIViewController) {
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
} 
