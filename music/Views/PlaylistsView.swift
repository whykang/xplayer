import SwiftUI
import UIKit
import ObjectiveC

struct PlaylistsView: View {
    @EnvironmentObject var musicLibrary: MusicLibrary
    @State private var showingAddPlaylist = false
    @State private var newPlaylistName = ""
    @State private var showingDuplicateAlert = false
    @State private var searchText = ""
    @State private var refreshView = false
    // 添加编辑模式State
    @State private var isEditing = false
    // 添加明确的EditMode状态
    @State private var editMode: EditMode = .inactive
    
    // 删除确认相关状态
    @State private var showingDeleteConfirmation = false
    @State private var playlistsToDelete: [Playlist] = []
    @State private var deleteIndexSet: IndexSet?
    
    // 筛选歌单
    var filteredPlaylists: [Playlist] {
        let playlists = musicLibrary.playlists.filter { $0.name != "我的收藏" }
        if searchText.isEmpty {
            return playlists
        } else {
            let lowercasedQuery = searchText.lowercased()
            return playlists.filter { playlist in
                playlist.name.lowercased().contains(lowercasedQuery)
            }
        }
    }
    
    // 查找我的收藏歌单
    var favoritesPlaylist: Playlist {
        return musicLibrary.favorites
    }
    
    var body: some View {
        Group {
            List {
                // 我的收藏
                FavoritesRow(favorites: favoritesPlaylist, refreshTrigger: refreshView)
                
                // 用户创建的歌单（排除"我的收藏"）
                ForEach(filteredPlaylists) { playlist in
                    PlaylistRow(playlist: playlist)
                }
                .onDelete(perform: confirmDeletePlaylists)
                .onMove(perform: movePlaylists)
                
                // 添加底部空间，避免被播放器遮挡
                Rectangle()
                    .frame(height: 100)
                    .foregroundColor(.clear)
                    .listRowSeparator(.hidden)
            }
            .searchable(text: $searchText, prompt: "搜索歌单")
            .listStyle(PlainListStyle())
            .environment(\.editMode, $editMode)
        }
        .navigationTitle("歌单")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingAddPlaylist = true
                }) {
                    Image(systemName: "plus")
                }
            }
            
            // 添加编辑按钮
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    isEditing.toggle()
                    editMode = isEditing ? .active : .inactive
                }) {
                    Text(isEditing ? "完成" : "编辑")
                }
            }
        }
        .alert("新建歌单", isPresented: $showingAddPlaylist) {
            TextField("歌单名称", text: $newPlaylistName)
            Button("取消", role: .cancel) {
                newPlaylistName = ""
            }
            Button("创建") {
                createPlaylist()
            }
        } message: {
            Text("请输入新歌单的名称")
        }
        .alert("歌单已存在", isPresented: $showingDuplicateAlert) {
            Button("确定", role: .cancel) {
                handleDuplicateAlert()
            }
        } message: {
            Text("已存在重复的歌单，请使用其他名称")
        }
        .alert("确认删除", isPresented: $showingDeleteConfirmation) {
            Button("取消", role: .cancel) {
                // 取消删除操作
                playlistsToDelete = []
                deleteIndexSet = nil
            }
            Button("删除", role: .destructive) {
                // 执行删除操作
                performDeletePlaylists()
            }
        } message: {
            if playlistsToDelete.count == 1 {
                Text("确定要删除歌单\(playlistsToDelete.first?.name ?? "")吗？歌单中的所有歌曲将从歌单中移除（不会删除音乐文件）。")
            } else {
                Text("确定要删除选中的\(playlistsToDelete.count)个歌单吗？歌单中的所有歌曲将从歌单中移除（不会删除音乐文件）。")
            }
        }
        .onAppear {
            // 监听收藏歌单更新通知
            NotificationCenter.default.addObserver(forName: Notification.Name("FavoritesUpdated"), object: nil, queue: .main) { _ in
                // 触发视图刷新
                refreshView.toggle()
            }
            
            // 监听普通歌单更新通知
            NotificationCenter.default.addObserver(forName: Notification.Name("PlaylistUpdated"), object: nil, queue: .main) { _ in
                // 触发视图刷新
                refreshView.toggle()
            }
        }
    }
    
    // 创建新歌单逻辑
    private func createPlaylist() {
        if !newPlaylistName.isEmpty {
            // 避免创建"我的收藏"同名歌单
            if newPlaylistName == "我的收藏" {
                newPlaylistName = ""
                return
            }
            
            // 检查是否已存在同名歌单
            if musicLibrary.playlists.contains(where: { $0.name == newPlaylistName }) {
                showingDuplicateAlert = true
            } else {
                let newPlaylist = Playlist(name: newPlaylistName, songs: [])
                musicLibrary.playlists.append(newPlaylist)
                musicLibrary.savePlaylists()
                newPlaylistName = ""
            }
        }
    }
    
    // 处理歌单重复警告
    private func handleDuplicateAlert() {
        showingDuplicateAlert = false
        // 重新显示创建歌单对话框
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            showingAddPlaylist = true
        }
    }
    
    // 确认删除歌单
    private func confirmDeletePlaylists(at offsets: IndexSet) {
        // 保存要删除的索引集合
        deleteIndexSet = offsets
        
        // 准备要删除的歌单列表用于显示
        playlistsToDelete = offsets.map { filteredPlaylists[$0] }
        
        // 显示确认对话框
        showingDeleteConfirmation = true
    }
    
    // 执行删除歌单操作
    private func performDeletePlaylists() {
        guard let offsets = deleteIndexSet else { return }
        
        // 从musicLibrary.playlists中删除相应的歌单
        for playlist in playlistsToDelete {
            if let index = musicLibrary.playlists.firstIndex(where: { $0.id == playlist.id }) {
                musicLibrary.playlists.remove(at: index)
            }
        }
        
        // 保存更改并清理状态
        musicLibrary.savePlaylists()
        playlistsToDelete = []
        deleteIndexSet = nil
    }
    
    // 移动歌单位置
    private func movePlaylists(from source: IndexSet, to destination: Int) {
        // 需要考虑"我的收藏"歌单不能移动，所以筛选出用户创建的歌单
        let userPlaylists = musicLibrary.playlists.filter { $0.name != "我的收藏" }
        
        // 源索引集合对应的歌单
        let movedPlaylists = source.map { filteredPlaylists[$0] }
        
        // 在原始歌单列表中执行移动
        // 1. 首先从歌单列表中删除要移动的歌单
        var updatedPlaylists = musicLibrary.playlists.filter { playlist in
            !movedPlaylists.contains { $0.id == playlist.id }
        }
        
        // 2. 找到插入位置（需要考虑"我的收藏"歌单）
        var insertPosition = destination
        
        // 根据搜索状态调整插入位置
        if !searchText.isEmpty {
            // 在搜索模式下，需要映射到全局列表的位置
            if destination >= filteredPlaylists.count {
                // 如果是移动到末尾，放在全局列表末尾
                insertPosition = updatedPlaylists.count
            } else {
                // 目标位置的歌单ID
                let targetPlaylistId = filteredPlaylists[min(destination, filteredPlaylists.count - 1)].id
                
                // 在全局列表中找到该歌单的位置
                if let targetIndex = updatedPlaylists.firstIndex(where: { $0.id == targetPlaylistId }) {
                    insertPosition = targetIndex
                } else {
                    // 找不到位置时，添加到末尾
                    insertPosition = updatedPlaylists.count
                }
            }
        } else {
            // 非搜索模式下，直接调整插入位置即可
            // 考虑"我的收藏"的位置
            if let favoritesIndex = updatedPlaylists.firstIndex(where: { $0.name == "我的收藏" }) {
                if favoritesIndex < insertPosition {
                    // 不需要调整，因为我的收藏在插入位置之前
                } else {
                    // 如果要插入到"我的收藏"位置，需要调整
                    insertPosition = max(1, insertPosition)
                }
            }
        }
        
        // 3. 在对应位置插入要移动的歌单
        updatedPlaylists.insert(contentsOf: movedPlaylists, at: insertPosition)
        
        // 4. 更新MusicLibrary中的歌单列表
        musicLibrary.playlists = updatedPlaylists
        
        // 5. 保存更改
        musicLibrary.savePlaylists()
    }
}

// 我的收藏行视图
struct FavoritesRow: View {
    @ObservedObject var favorites: Playlist
    var refreshTrigger: Bool
    
    var body: some View {
        NavigationLink(destination: PlaylistDetailView(playlist: favorites)) {
            HStack {
                ZStack {
                    PlaylistCoverView(playlist: favorites, size: 40)
                    
                    // 添加一个红色的心形图标在封面上
                    Image(systemName: "heart.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .background(
                            Circle()
                                .fill(Color.red)
                                .frame(width: 25, height: 25)
                        )
                        .offset(x: 15, y: 15) // 右下角位置
                }
                .frame(width: 50, height: 50)
                
                VStack(alignment: .leading) {
                    Text("我的收藏")
                        .font(.headline)
                    Text("\(favorites.songs.count) 首歌曲")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .id("favCount-\(favorites.songs.count)-\(refreshTrigger)")
                }
            }
        }
    }
}

// 单个歌单行视图
struct PlaylistRow: View {
    @ObservedObject var playlist: Playlist
    
    var body: some View {
        NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
            HStack {
                PlaylistCoverView(playlist: playlist, size: 50)
                
                VStack(alignment: .leading) {
                    Text(playlist.name)
                        .font(.headline)
                    Text("\(playlist.songs.count) 首歌曲")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// 歌单封面视图
struct PlaylistCoverView: View {
    @ObservedObject var playlist: Playlist
    let size: CGFloat
    
    var body: some View {
        Group {
            if let coverImagePath = playlist.coverImage, let image = UIImage(contentsOfFile: coverImagePath) {
                // 使用用户自定义的封面
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if let firstSong = playlist.songs.first, let coverPath = firstSong.coverImagePath, let image = UIImage(contentsOfFile: coverPath) {
                // 使用第一首歌曲的专辑封面
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                // 默认占位图
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: size, height: size)
                    
                    Image(systemName: "music.note.list")
                        .font(.system(size: size * 0.4))
                        .foregroundColor(.primary)
                }
            }
        }
    }
}

struct PlaylistDetailView: View {
    @EnvironmentObject var musicLibrary: MusicLibrary
    @ObservedObject var musicPlayer = MusicPlayer.shared
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var playlist: Playlist
    @State private var selectedSong: Song?
    @State private var showingSongPicker = false
    @State private var showingImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var isEditingName = false
    @State private var editedName = ""
    
    var body: some View {
        VStack {
            if playlist.songs.isEmpty {
                EmptyPlaylistView(showPicker: $showingSongPicker)
            } else {
                VStack {
                    // 添加封面图和编辑按钮
                    ZStack(alignment: .bottomTrailing) {
                        PlaylistCoverView(playlist: playlist, size: 150)
                            .padding(.top, 20)
                        
                        Button(action: {
                            showingImagePicker = true
                        }) {
                            Image(systemName: "photo")
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.gray.opacity(0.7))
                                .clipShape(Circle())
                        }
                        .padding(5)
                    }
                    .frame(width: 150, height: 150)
                    .padding(.bottom, 10)
                    
                    // 歌单名称（可编辑）
                    Group {
                        if isEditingName {
                            HStack {
                                TextField("歌单名称", text: $editedName)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                
                                Button(action: {
                                    // 保存编辑的名称
                                    if !editedName.isEmpty && editedName != "我的收藏" {
                                        playlist.name = editedName
                                        musicLibrary.savePlaylists()
                                    }
                                    isEditingName = false
                                }) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.title2)
                                }
                                
                                Button(action: {
                                    // 取消编辑
                                    editedName = playlist.name
                                    isEditingName = false
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                        .font(.title2)
                                }
                            }
                            .padding(.horizontal)
                        } else {
                            HStack {
                                Text(playlist.name)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                
                                // 不允许编辑"我的收藏"歌单
                                if playlist.name != "我的收藏" {
                                    Button(action: {
                                        editedName = playlist.name
                                        isEditingName = true
                                    }) {
                                        Image(systemName: "pencil")
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 5)
                    
                    // 添加顶部按钮区域
                    HStack(spacing: 20) {
                        Button(action: {
                            playAllSongs(shuffle: false)
                        }) {
                            VStack {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 20))
                                    .padding(10)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .clipShape(Circle())
                                
                                Text("播放全部")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                        }
                        
                        Button(action: {
                            playAllSongs(shuffle: true)
                        }) {
                            VStack {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 18))
                                    .padding(10)
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .clipShape(Circle())
                                
                                Text("随机播放")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 5)
                    
                    PlaylistSongsListView(playlist: playlist, musicLibrary: musicLibrary, musicPlayer: musicPlayer)
                }
            }
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingSongPicker = true
                }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingSongPicker) {
            SongPickerView(playlist: playlist)
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: $selectedImage, sourceType: .photoLibrary)
                .onDisappear {
                    if let selectedImage = selectedImage {
                        savePlaylistCoverImage(selectedImage)
                    }
                }
        }
    }
    
    // 保存选择的封面图片
    private func savePlaylistCoverImage(_ image: UIImage) {
        let fileManager = FileManager.default
        do {
            // 获取Documents目录
            let documentsDir = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            
            // 创建Covers目录（如果不存在）
            let coversDir = documentsDir.appendingPathComponent("Covers", isDirectory: true)
            if !fileManager.fileExists(atPath: coversDir.path) {
                try fileManager.createDirectory(at: coversDir, withIntermediateDirectories: true, attributes: nil)
            }
            
            // 生成唯一文件名
            let fileName = "\(playlist.id.uuidString)_cover.jpg"
            let fileURL = coversDir.appendingPathComponent(fileName)
            
            // 保存图片
            if let imageData = image.jpegData(compressionQuality: 0.8) {
                try imageData.write(to: fileURL)
                
                // 更新歌单的封面图片路径
                playlist.coverImage = fileURL.path
                
                // 保存歌单列表
                musicLibrary.savePlaylists()
            }
        } catch {
            print("保存歌单封面图片失败: \(error)")
        }
    }
    
    // 播放全部歌曲
    private func playAllSongs(shuffle: Bool) {
        guard !playlist.songs.isEmpty else { return }
        
        if shuffle {
            // 设置随机播放模式
            musicPlayer.playMode = .shuffle
        } else {
            // 设置正常播放模式
            musicPlayer.playMode = .normal
        }
        
        // 设置播放列表并开始播放
        musicPlayer.setPlaylist(songs: playlist.songs)
    }
}

// 空歌单视图
struct EmptyPlaylistView: View {
    @Binding var showPicker: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list")
                .font(.system(size: 70))
                .foregroundColor(.gray)
            
            Text("歌单为空")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("点击添加按钮将歌曲添加到这个歌单")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: {
                showPicker = true
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("添加歌曲")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(20)
            }
            .padding(.top, 8)
        }
        .padding()
    }
}

// 歌单歌曲列表视图
struct PlaylistSongsListView: View {
    @ObservedObject var playlist: Playlist
    let musicLibrary: MusicLibrary
    let musicPlayer: MusicPlayer
    
    var body: some View {
        List {
            ForEach(playlist.songs) { song in
                SongRow(song: song, highlightIfPlaying: false)
                    .contextMenu {
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
                            musicLibrary.removeSongFromPlaylist(song: song, playlist: playlist)
                        }) {
                            Label("从歌单移除", systemImage: "minus.circle")
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
            .onDelete { indexSet in
                indexSet.forEach { index in
                    let song = playlist.songs[index]
                    musicLibrary.removeSongFromPlaylist(song: song, playlist: playlist)
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

struct PlaylistsView_Previews: PreviewProvider {
    static var previews: some View {
        PlaylistsView()
            .environmentObject(MusicLibrary.shared)
    }
}

// MARK: - 歌单选择视图
struct PlaylistSongSelectionView: View {
    var song: Song
    @ObservedObject var musicLibrary = MusicLibrary.shared
    @Environment(\.dismiss) private var dismiss
    @State private var originPlaylist: Playlist?
    
    init(song: Song, musicLibrary: MusicLibrary = MusicLibrary.shared, originPlaylist: Playlist? = nil) {
        self.song = song
        self.musicLibrary = musicLibrary
        self._originPlaylist = State(initialValue: originPlaylist)
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(musicLibrary.playlists) { playlist in
                    Button(action: {
                        // 添加歌曲到这个歌单
                        musicLibrary.addSongToPlaylist(song: song, playlist: playlist)
                        dismiss()
                    }) {
                        HStack {
                            Text(playlist.name)
                                .foregroundColor(.primary)
                            Spacer()
                            if musicLibrary.playlists.first(where: { $0.id == playlist.id })?.songs.contains(where: { $0.id == song.id }) ?? false {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 多选歌单选择视图
// 此视图已被移至BatchPlaylistSelectionView.swift文件中
// 原实现已删除以避免名称冲突

// 空占位符，保持文件结构 
