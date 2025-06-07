import Foundation
import MediaPlayer
import Combine

// 定义重复播放模式
enum RepeatMode: String, Codable {
    case none    // 不重复
    case one     // 单曲重复
    case all     // 全部重复
}

// 定义歌曲排序方式
enum SongSortMode: String, CaseIterable {
    case creationDate = "导入时间"  // 按导入时间排序
    case alphabetical = "首字母"   // 按首字母排序
    case duration = "时长"         // 按时长排序
    case artist = "艺术家"         // 按艺术家排序
    case album = "专辑"           // 按专辑排序
}

class MusicLibrary: ObservableObject {
    public static let shared = MusicLibrary()
    
    @Published var songs: [Song] = []
    @Published var albums: [Album] = []
    @Published var playlists: [Playlist] = []
    @Published var favorites: Playlist
    @Published var currentPlaylist: Playlist?
    @Published var currentSong: Song?
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Float = 1.0
    @Published var isShuffleEnabled: Bool = false
    @Published var repeatMode: RepeatMode = .none
    @Published var isFirstLaunch: Bool = true
    @Published var isLoading: Bool = false
    @Published var loadingMessage: String = ""
    @Published var enableSmartCoverMatching: Bool = true // 智能专辑封面匹配设置，默认开启
    @Published var enableArtistImageMatching: Bool = true // 智能艺术家图片匹配设置，默认开启
    @Published var songSortMode: SongSortMode = .creationDate { // 歌曲排序方式，默认按导入时间
        didSet {
            // 当排序模式变更时，保存设置
            UserDefaults.standard.set(songSortMode.rawValue, forKey: "songSortMode")
        }
    }
    @Published var sortAscending: Bool = false { // 是否升序排列，默认为降序（false）
        didSet {
            // 当排序方向变更时，保存设置
            UserDefaults.standard.set(sortAscending, forKey: "sortAscending")
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private let userDefaults = UserDefaults.standard
    
    private init() {
        // 从UserDefaults加载首次启动标志
        self.isFirstLaunch = userDefaults.bool(forKey: "isFirstLaunch")
        
        // 加载智能封面匹配设置
        self.enableSmartCoverMatching = userDefaults.object(forKey: "enableSmartCoverMatching") as? Bool ?? true
        
        // 加载智能艺术家图片匹配设置
        self.enableArtistImageMatching = userDefaults.object(forKey: "enableArtistImageMatching") as? Bool ?? true
        
        // 加载歌曲排序模式设置
        if let sortModeString = userDefaults.string(forKey: "songSortMode"),
           let mode = SongSortMode(rawValue: sortModeString) {
            songSortMode = mode
        }
        
        // 加载排序方向设置
        self.sortAscending = userDefaults.bool(forKey: "sortAscending")
        
        // 初始化收藏夹（后续会在加载JSON文件时更新）
        self.favorites = Playlist(name: "我的收藏", songs: [])
        
        // 初始化空的播放列表数组（后续会在加载JSON文件时更新）
        self.playlists = []
        self.songs = []
        
        // 尝试从JSON文件加载歌曲和歌单数据
        loadSongsFromJSON()
        loadPlaylistsFromJSON()
        
        // 设置首次启动标志为false
        userDefaults.set(false, forKey: "isFirstLaunch")
        
        // 清理可能存在的老格式数据文件
        cleanupOldDataFiles()
        
        // 调试文件系统信息，帮助排查问题
        debugFileSystem()
        
        // 先执行数据修复检查
        checkAndRecoverPlaylistsData()
        
        // 先加载歌单
        self.loadPlaylists()
        
        // 异步加载本地音乐文件，但不从歌单同步歌曲到主歌曲库
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // 执行路径迁移和修复（只在需要时）
            DispatchQueue.main.async {
                self?.migratePathsToRelativeFormatIfNeeded()
                self?.validateAndRepairFilePaths()
            }
            
            // 加载本地音乐（不加载歌单，避免循环）
            self?.loadLocalMusic(shouldLoadPlaylists: false)
            
            // 加载完成后再次调试，看看文件是否正确保存
            DispatchQueue.main.async {
                self?.debugFileSystem()
            }
        }
    }
    
    // 检查并修复播放列表数据
    private func checkAndRecoverPlaylistsData() {
        print("检查播放列表数据并尝试恢复...")
        
        // 检查文件是否存在
        let filePath = getPlaylistsFilePath()
        let fileExists = FileManager.default.fileExists(atPath: filePath.path)
        
        // 检查UserDefaults中是否存在备份数据
        let hasUserDefaultsBackup = userDefaults.data(forKey: "playlists") != nil
                                 && userDefaults.data(forKey: "favorites") != nil
        
        print("文件存在: \(fileExists), UserDefaults备份存在: \(hasUserDefaultsBackup)")
        
        // 如果文件不存在但有UserDefaults备份，从备份恢复
        if !fileExists && hasUserDefaultsBackup {
            print("从UserDefaults备份恢复播放列表数据...")
            
            do {
                // 从UserDefaults加载数据
                if let playlistsData = userDefaults.data(forKey: "playlists"),
                   let favoritesData = userDefaults.data(forKey: "favorites") {
                    
                    let decoder = JSONDecoder()
                    let recoveredPlaylists = try decoder.decode([Playlist].self, from: playlistsData)
                    let recoveredFavorites = try decoder.decode(Playlist.self, from: favoritesData)
                    
                    print("从UserDefaults恢复了\(recoveredPlaylists.count)个播放列表和\(recoveredFavorites.songs.count)首收藏歌曲")
                    
                    // 临时设置数据
                    self.playlists = recoveredPlaylists
                    self.favorites = recoveredFavorites
                    
                    // 立即保存到文件
                    self.forceSavePlaylists()
                    
                    print("已将恢复的数据保存到文件")
                }
            } catch {
                print("从UserDefaults恢复数据失败: \(error)")
            }
        }
    }
    
    // 清理老格式的数据文件
    private func cleanupOldDataFiles() {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let oldJsonPath = documentsDirectory.appendingPathComponent("playlists.json")
        
        // 检查是否存在老的JSON格式文件
        if FileManager.default.fileExists(atPath: oldJsonPath.path) {
            do {
                try FileManager.default.removeItem(at: oldJsonPath)
                print("已清理旧版本数据文件: \(oldJsonPath.path)")
            } catch {
                print("清理旧版本数据文件失败: \(error.localizedDescription)")
            }
        }
    }
    
    // 添加观察歌单变化的方法
    private func registerObservers() {
        // 删除原有的定时保存逻辑
        print("歌单变化观察者已注册，但不会自动保存")
        // 不再使用Combine自动保存歌单
    }
    
    // MARK: - 音乐库管理
    
    func loadLocalMusic(shouldLoadPlaylists: Bool = false) {
        print("🔄 loadLocalMusic方法已被调用，但根据新的设计，启动时不再扫描音乐文件")
        // 软件启动时不再扫描音乐库中的文件，只从JSON加载数据
    }
    
    private func loadSampleData() {
        // 确保在主线程上执行
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.loadSampleData()
            }
            return
        }
        
        // 清空所有数据
        songs = []
        albums = []
        playlists = []
        
        // 只保留"我的收藏"歌单
        if !playlists.contains(where: { $0.name == "我的收藏" }) {
            playlists.insert(favorites, at: 0)
        }
    }
    
    // 添加新歌曲到库中
    func addSong(_ song: Song) {
        // 确保在主线程上执行
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.addSong(song)
            }
            return
        }
        
        // 检查是否已存在相同歌曲（基于文件URL比较）
        if !songs.contains(where: { $0.fileURL?.absoluteString == song.fileURL?.absoluteString }) {
            songs.append(song)
            organizeAlbums()
            
            // 保存歌曲
            print("添加新歌曲后保存歌曲JSON")
            saveSongsToJSON()
        }
    }
    
    // 更新已有歌曲
    func updateSong(_ updatedSong: Song) {
        // 确保在主线程上执行
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.updateSong(updatedSong)
            }
            return
        }
        
        var updated = false
        
        if let index = songs.firstIndex(where: { $0.id == updatedSong.id }) {
            songs[index] = updatedSong
            updated = true
        } else if let fileURL = updatedSong.fileURL, 
                  let index = songs.firstIndex(where: { $0.fileURL?.absoluteString == fileURL.absoluteString }) {
            songs[index] = updatedSong
            updated = true
        }
        
        if updated {
            organizeAlbums()
            
            // 保存歌曲
            print("更新歌曲后保存歌曲JSON")
            saveSongsToJSON()
        }
    }
    
    // 根据歌曲信息重新组织专辑
    private func organizeAlbums() {
        // 确保在主线程上执行
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.organizeAlbums()
            }
            return
        }
        
        // 按专辑名称分组歌曲
        let albumGroups = Dictionary(grouping: songs) { $0.albumName }
        
        // 创建专辑对象
        var newAlbums: [Album] = []
        
        for (albumName, albumSongs) in albumGroups {
            // 查找专辑艺术家:
            // 1. 首先查找非"未知艺术家"的albumArtist
            // 2. 如果没有，使用最常见的artist值
            // 3. 如果仍然没有，使用"未知艺术家"
            
            let albumArtist: String
            
            // 尝试找到第一个有效的专辑艺术家
            if let firstValidAlbumArtist = albumSongs.first(where: { $0.albumArtist != "未知艺术家" })?.albumArtist {
                albumArtist = firstValidAlbumArtist
            } else {
                // 统计歌曲中出现次数最多的艺术家
                var artistCounts: [String: Int] = [:]
                for song in albumSongs where song.artist != "未知艺术家" {
                    artistCounts[song.artist, default: 0] += 1
                }
                
                // 找出出现次数最多的艺术家
                if let mostCommonArtist = artistCounts.max(by: { $0.value < $1.value })?.key {
                    albumArtist = mostCommonArtist
                } else {
                    // 如果没有有效艺术家，使用第一首歌的艺术家（即使是"未知艺术家"）
                    albumArtist = albumSongs.first?.artist ?? "未知艺术家"
                }
            }
            
            // 获取年份（使用第一首有年份的歌曲）
            let year = albumSongs.first { $0.year != nil }?.year
            
            let album = Album(
                title: albumName,
                artist: albumArtist,
                year: year,
                songs: albumSongs
            )
            
            newAlbums.append(album)
        }
        
        albums = newAlbums
        
        // 确保playlists包含"我的收藏"
        ensureFavoritesPlaylist()
    }
    
    // 确保"我的收藏"歌单存在
    private func ensureFavoritesPlaylist() {
        // 确保在主线程上执行
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.ensureFavoritesPlaylist()
            }
            return
        }
        
        // 先移除所有名为"我的收藏"的歌单
        playlists.removeAll(where: { $0.name == "我的收藏" })
        
        // 在第一位添加"我的收藏"歌单
        playlists.insert(favorites, at: 0)
    }
    
    // 导入音乐文件
    func importMusic(from url: URL, completion: @escaping (Result<Song, Error>) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isLoading = true
            self.loadingMessage = "导入音乐文件..."
        }
        
        MusicFileManager.shared.importMusicFile(from: url) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                completion(result)
            }
        }
    }
    
    // MARK: - 歌单管理
    
    // 创建新歌单 - 简化版，立即保存
    func createPlaylist(name: String, songs: [Song] = []) -> Playlist? {
        print("正在创建新歌单: '\(name)'")
        
        // 确保在主线程执行UI相关操作
        if !Thread.isMainThread {
            var result: Playlist?
            DispatchQueue.main.sync {
                result = self.createPlaylist(name: name, songs: songs)
            }
            return result
        }
        
        // 检查是否为"我的收藏"，不允许创建同名歌单
        if name == "我的收藏" {
            print("不允许创建与'我的收藏'同名的歌单")
            return nil
        }
        
        // 检查是否已存在同名歌单
        if playlists.contains(where: { $0.name == name }) {
            print("已存在名为'\(name)'的歌单，无法创建")
            return nil
        }
        
        // 创建并添加新歌单
        let newPlaylist = Playlist(name: name, songs: songs)
        playlists.append(newPlaylist)
        
        // 立即同步保存
        print("开始执行立即保存操作...")
        savePlaylists()
        
        print("已创建新歌单'\(name)'并保存，当前共有\(playlists.count)个歌单")
        return newPlaylist
    }
    
    // 收藏/取消收藏歌曲 - 简化版，立即保存
    func toggleFavorite(song: Song) -> Bool {
        print("切换歌曲 '\(song.title)' 的收藏状态")
        
        // 确保在主线程执行UI相关操作
        if !Thread.isMainThread {
            var result = false
            DispatchQueue.main.sync {
                result = self.toggleFavorite(song: song)
            }
            return result
        }
        
        let isFavoriteNow: Bool
        
        if let index = favorites.songs.firstIndex(where: { $0.id == song.id }) {
            // 已经在收藏列表中，移除
            favorites.songs.remove(at: index)
            isFavoriteNow = false
            print("已从收藏列表中移除歌曲 '\(song.title)'")
        } else {
            // 不在收藏列表中，添加
            favorites.songs.append(song)
            isFavoriteNow = true
            print("已添加歌曲 '\(song.title)' 到收藏列表")
        }
        
        // 立即同步保存
        print("开始执行立即保存操作...")
        savePlaylists()
        
        // 验证状态
        let verifyStatus = favorites.songs.contains(where: { $0.id == song.id })
        print("验证: 歌曲收藏状态为\(verifyStatus ? "已收藏" : "未收藏")，收藏列表现有\(favorites.songs.count)首歌曲")
        
        // 发送通知以更新UI，包括PlaylistsView
        NotificationCenter.default.post(name: Notification.Name("FavoritesUpdated"), object: nil)
        
        return isFavoriteNow // 返回新状态
    }
    
    // 检查歌曲是否已收藏
    func isFavorite(song: Song) -> Bool {
        return favorites.songs.contains(where: { $0.id == song.id })
    }
    
    // 添加歌曲到歌单 - 简化版，立即保存
    func addSongToPlaylist(song: Song, playlist: Playlist) {
        print("正在添加歌曲 '\(song.title)' 到歌单 '\(playlist.name)'")
        
        var songAdded = false
        
        // 如果是"我的收藏"歌单
        if playlist.name == "我的收藏" {
            // 检查歌曲是否已在收藏中
            if !self.favorites.songs.contains(where: { $0.id == song.id }) {
                // 直接修改对象属性
                self.favorites.songs.append(song)
                songAdded = true
                
                // 确保在playlists列表中也更新了favorites
                if let index = self.playlists.firstIndex(where: { $0.name == "我的收藏" }) {
                    self.playlists[index] = self.favorites
                }
                
                print("已添加歌曲'\(song.title)'到'我的收藏'，当前共有\(self.favorites.songs.count)首歌")
            } else {
                print("歌曲已存在于'我的收藏'中，跳过添加")
                return
            }
        } 
        // 处理普通歌单
        else if let index = self.playlists.firstIndex(where: { $0.id == playlist.id }) {
            // 如果歌曲已经在歌单中就不再添加
            if !self.playlists[index].songs.contains(where: { $0.id == song.id }) {
                // 直接修改playlist对象
                playlist.songs.append(song)
                songAdded = true
                
                // 更新playlists数组中的引用
                self.playlists[index] = playlist
                
                print("已添加歌曲'\(song.title)'到'\(playlist.name)'歌单，当前共有\(playlist.songs.count)首歌")
            } else {
                print("歌曲已存在于'\(playlist.name)'中，跳过添加")
                return
            }
        } else {
            print("未找到ID为\(playlist.id)的歌单，无法添加歌曲")
            return
        }
        
        // 如果添加了歌曲，立即同步保存
        if songAdded {
            print("开始执行立即保存操作...")
            // 直接同步保存，确保数据被写入
            self.savePlaylists()
            
            // 打印验证信息
            if playlist.name == "我的收藏" {
                print("验证: 收藏列表现在有 \(self.favorites.songs.count) 首歌曲")
                // 发送通知以更新UI，包括PlaylistsView
                NotificationCenter.default.post(name: Notification.Name("FavoritesUpdated"), object: nil)
            } else {
                if let updatedPlaylist = self.playlists.first(where: { $0.id == playlist.id }) {
                    print("验证: 歌单'\(updatedPlaylist.name)'现在有 \(updatedPlaylist.songs.count) 首歌曲")
                    // 发送通知以更新UI，包括PlaylistsView
                    NotificationCenter.default.post(name: Notification.Name("PlaylistUpdated"), object: nil, userInfo: ["playlistId": updatedPlaylist.id])
                }
            }
        }
    }
    
    // 从歌单中移除歌曲 - 简化版，立即保存
    func removeSongFromPlaylist(song: Song, playlist: Playlist) {
        print("正在从歌单 '\(playlist.name)' 移除歌曲 '\(song.title)'")
        
        var songRemoved = false
        
        // 如果是"我的收藏"歌单
        if playlist.name == "我的收藏" {
            if let index = favorites.songs.firstIndex(where: { $0.id == song.id }) {
                favorites.songs.remove(at: index)
                songRemoved = true
                
                // 确保playlists列表中的favorites也被更新
                if let playlistIndex = playlists.firstIndex(where: { $0.name == "我的收藏" }) {
                    playlists[playlistIndex] = favorites
                }
                
                print("已从'我的收藏'中移除歌曲 '\(song.title)'，当前剩余\(favorites.songs.count)首歌")
            } else {
                print("在'我的收藏'中找不到歌曲 '\(song.title)'")
            }
        } 
        // 处理普通歌单
        else if let songIndex = playlist.songs.firstIndex(where: { $0.id == song.id }) {
            playlist.songs.remove(at: songIndex)
            songRemoved = true
            
            // 确保playlists数组中的引用被更新
            if let playlistIndex = playlists.firstIndex(where: { $0.id == playlist.id }) {
                playlists[playlistIndex] = playlist
            }
            
            print("已从'\(playlist.name)'歌单中移除歌曲 '\(song.title)'，当前剩余\(playlist.songs.count)首歌")
        } else {
            print("在'\(playlist.name)'歌单中找不到歌曲 '\(song.title)'")
        }
        
        // 如果移除了歌曲，立即同步保存
        if songRemoved {
            print("开始执行立即保存操作...")
            // 直接同步保存，确保数据被写入
            self.savePlaylists()
            
            // 打印验证信息
            if playlist.name == "我的收藏" {
                print("验证: 收藏列表现在有 \(self.favorites.songs.count) 首歌曲")
            } else {
                if let updatedPlaylist = self.playlists.first(where: { $0.id == playlist.id }) {
                    print("验证: 歌单'\(updatedPlaylist.name)'现在有 \(updatedPlaylist.songs.count) 首歌曲")
                }
            }
        }
    }
    
    // 检查是否存在相似的歌曲（基于标题和艺术家比较）
    func hasSimilarSong(_ song: Song) -> Bool {
        return songs.contains { existingSong in
            // 如果文件URL一样，认为是同一首歌
            if let existingURL = existingSong.fileURL, 
               let newURL = song.fileURL,
               existingURL.absoluteString == newURL.absoluteString {
                return true
            }
            
            // 如果标题和艺术家都完全一样，认为是同一首歌
            if existingSong.title.lowercased() == song.title.lowercased() &&
               existingSong.artist.lowercased() == song.artist.lowercased() {
                return true
            }
            
            return false
        }
    }
    
    // 获取相似的歌曲
    func getSimilarSongs(_ song: Song) -> [Song] {
        return songs.filter { existingSong in
            // 如果标题和艺术家都完全一样，认为是同一首歌
            if existingSong.title.lowercased() == song.title.lowercased() &&
               existingSong.artist.lowercased() == song.artist.lowercased() {
                return true
            }
            
            return false
        }
    }
    
    // 从音乐库中删除歌曲及相关资源
    func deleteSong(_ song: Song, withConfirmation: Bool = true, completion: ((Bool) -> Void)? = nil) {
        // 如果当前正在播放这首歌曲，先停止播放
        if MusicPlayer.shared.currentSong?.id == song.id {
            MusicPlayer.shared.stop()
        }
        
        // 从所有歌单中移除这首歌曲
        for playlist in playlists {
            if playlist.songs.contains(where: { $0.id == song.id }) {
                playlist.songs.removeAll(where: { $0.id == song.id })
            }
        }
        
        // 特殊处理"我的收藏"
        favorites.songs.removeAll(where: { $0.id == song.id })
        
        // 从播放队列和当前播放列表中移除
        if let index = MusicPlayer.shared.getCurrentPlaylist().firstIndex(where: { $0.id == song.id }) {
            MusicPlayer.shared.removeFromCurrentPlaylist(at: index)
        }
        
        // 从歌曲库中移除
        songs.removeAll(where: { $0.id == song.id })
        
        // 重新组织专辑
        organizeAlbums()
        
        // 保存修改到歌曲和歌单JSON文件
        print("删除歌曲后保存歌曲和歌单JSON")
        saveSongsToJSON()
        savePlaylistsToJSON()
        
        // 删除物理文件
        let deleted = MusicFileManager.shared.deleteMusicFile(song: song)
        
        // 完成回调
        completion?(deleted)
    }
    
    // 切换歌曲置顶状态
    func togglePinned(song: Song) {
        guard let index = self.songs.firstIndex(where: { $0.id == song.id }) else {
            return
        }
        
        // 创建一个歌曲的可变副本
        var updatedSong = song
        // 切换置顶状态
        updatedSong.isPinned = !song.isPinned
        
        // 更新歌曲
        self.songs[index] = updatedSong
        
        // 立即保存到歌曲JSON文件
        print("更新歌曲置顶状态后保存歌曲JSON")
        saveSongsToJSON()
    }
    
    // 判断歌曲是否被置顶
    func isPinned(song: Song) -> Bool {
        guard let foundSong = self.songs.first(where: { $0.id == song.id }) else {
            return false
        }
        return foundSong.isPinned
    }
    
    // 获取排序后的歌曲列表（根据当前排序模式排序）
    func getSortedSongs() -> [Song] {
        // 先处理置顶歌曲，置顶歌曲始终在最前面
        let pinnedSongs = self.songs.filter { $0.isPinned }
        let unpinnedSongs = self.songs.filter { !$0.isPinned }
        
        // 根据排序模式对非置顶歌曲进行排序
        let sortedUnpinnedSongs: [Song]
        
        switch songSortMode {
        case .creationDate:
            // 按照创建时间排序，根据升序/降序设置决定排序方向
            sortedUnpinnedSongs = unpinnedSongs.sorted { song1, song2 in
                return sortAscending ? (song1.creationDate < song2.creationDate) : (song1.creationDate > song2.creationDate)
            }
            
        case .alphabetical:
            // 按照歌曲标题首字母排序，根据升序/降序设置决定排序方向
            sortedUnpinnedSongs = unpinnedSongs.sorted { song1, song2 in
                let comparison = song1.title.localizedCaseInsensitiveCompare(song2.title)
                return sortAscending ? (comparison == .orderedAscending) : (comparison == .orderedDescending)
            }
            
        case .duration:
            // 按照歌曲时长排序，根据升序/降序设置决定排序方向
            sortedUnpinnedSongs = unpinnedSongs.sorted { song1, song2 in
                return sortAscending ? (song1.duration < song2.duration) : (song1.duration > song2.duration)
            }
            
        case .artist:
            // 按照艺术家名称排序，根据升序/降序设置决定排序方向
            sortedUnpinnedSongs = unpinnedSongs.sorted { song1, song2 in
                let comparison = song1.artist.localizedCaseInsensitiveCompare(song2.artist)
                return sortAscending ? (comparison == .orderedAscending) : (comparison == .orderedDescending)
            }
            
        case .album:
            // 按照专辑名称排序，根据升序/降序设置决定排序方向
            sortedUnpinnedSongs = unpinnedSongs.sorted { song1, song2 in
                let comparison = song1.albumName.localizedCaseInsensitiveCompare(song2.albumName)
                return sortAscending ? (comparison == .orderedAscending) : (comparison == .orderedDescending)
            }
        }
        
        // 合并置顶歌曲和排序后的非置顶歌曲
        return pinnedSongs + sortedUnpinnedSongs
    }
    
    // 批量删除歌曲
    func deleteSongs(_ songsToDelete: [Song], completion: ((Bool) -> Void)? = nil) {
        var allSuccess = true
        
        for song in songsToDelete {
            // 不显示确认对话框，直接删除
            deleteSong(song, completion: { success in
                if !success {
                    allSuccess = false
                }
            })
        }
        
        // 刷新专辑
        organizeAlbums()
        
        // 完成回调
        completion?(allSuccess)
    }
    
    // 删除歌单 - 简化版，立即保存
    func deletePlaylist(_ playlist: Playlist) {
        print("正在删除歌单: '\(playlist.name)'")
        
        // 不允许删除"我的收藏"歌单
        if playlist.name == "我的收藏" { 
            print("不允许删除'我的收藏'歌单")
            return 
        }
        
        // 记录删除前的歌单数量
        let originalCount = playlists.count
        
        // 删除歌单
        playlists.removeAll(where: { $0.id == playlist.id })
        
        // 检查是否成功删除
        if originalCount > playlists.count {
            // 立即同步保存
            print("开始执行立即保存操作...")
            savePlaylists()
            print("已删除歌单'\(playlist.name)'并保存，当前剩余\(playlists.count)个歌单")
        } else {
            print("未找到ID为\(playlist.id)的歌单，无法删除")
        }
    }
    
    // MARK: - 专辑管理
    
    // 添加歌曲到专辑
    func addSongToAlbum(song: Song, album: Album) {
        // 创建歌曲的副本
        var updatedSong = song
        
        // 更新歌曲的专辑信息
        updatedSong.albumName = album.title
        updatedSong.albumArtist = album.artist
        
        // 更新这首歌曲
        updateSong(updatedSong)
        
        // 重新组织专辑
        organizeAlbums()
        
        // 保存专辑和歌单信息
        savePlaylists()
    }
    
    // MARK: - 歌单持久化
    
    // 获取歌单存储文件路径
    private func getPlaylistsFilePath() -> URL {
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // 为了调试，打印文档目录路径
        print("Documents directory path: \(documentsDirectory.path)")
        
        // 确保Documents目录存在
        if !fileManager.fileExists(atPath: documentsDirectory.path) {
            do {
                try fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)
                print("Created Documents directory")
            } catch {
                print("无法创建Documents目录: \(error.localizedDescription)")
            }
        }
        
        // 使用plist格式而不是json，提高序列化效率
        let playlistsFilePath = documentsDirectory.appendingPathComponent("playlists.plist")
        
        // 显示完整的文件保存路径
        print("将歌单保存到路径: \(playlistsFilePath.path)")
        
        return playlistsFilePath
    }
    
    // 保存歌单到本地 - 简化版，只保存一份
    func savePlaylists() {
        print("开始保存歌单数据到JSON文件...")
        savePlaylistsToJSON()
    }
    
    // 从JSON文件加载歌单
    func loadPlaylists() {
        print("从JSON文件加载歌单...")
        loadPlaylistsFromJSON()
    }
    
    // 用可用的歌曲更新歌单（确保歌单中的歌曲存在对应文件）
    private func updatePlaylistsWithAvailableSongs() {
        print("更新歌单中的歌曲，确保每首歌都有对应文件...")
        
        // 先检查songs数组中的歌曲文件是否存在
        var validSongs: [Song] = []
        var invalidSongs: [Song] = []
        
        // 处理应用程序重新安装后的UUID变化问题
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let musicDirectory = documentsDirectory.appendingPathComponent("Music")
        
        print("当前应用的documents目录: \(documentsDirectory.path)")
        print("当前应用的音乐目录: \(musicDirectory.path)")
        
        // 使用多种方法检查文件
        for song in songs {
            var isValid = false
            
            if let url = song.fileURL {
                let songFileName = url.lastPathComponent
                print("检查歌曲: \(song.title) - 原始路径: \(url.path)")
                
                // 方法1: 使用fileExists检查原始路径
                let fileExistsByPath = fileManager.fileExists(atPath: url.path)
                
                // 方法2: 尝试根据文件名在当前应用的Music目录中查找
                let newPathURL = musicDirectory.appendingPathComponent(songFileName)
                let fileExistsAtNewPath = fileManager.fileExists(atPath: newPathURL.path)
                
                print("当前尝试的新路径: \(newPathURL.path)")
                
                // 方法3: 尝试使用isReachable属性检查
                var isReachable = false
                do {
                    isReachable = try url.checkResourceIsReachable()
                } catch let error {
                    print("isReachable失败: \(error.localizedDescription)")
                }
                
                // 方法4: 尝试获取文件属性
                var hasAttributes = false
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: url.path)
                    hasAttributes = !attributes.isEmpty
                } catch {
                    // 忽略错误
                }
                
                // 如果任一方法显示文件存在，则认为歌曲有效
                isValid = fileExistsByPath || fileExistsAtNewPath || isReachable || hasAttributes
                
                print("文件检查结果: 原始路径存在=\(fileExistsByPath), 新路径存在=\(fileExistsAtNewPath), isReachable=\(isReachable), hasAttributes=\(hasAttributes), 结论=\(isValid ? "有效" : "无效")")
                
                // 如果找到文件在新路径，更新song的filePath
                if !fileExistsByPath && fileExistsAtNewPath {
                    print("文件已找到，但路径已变更。更新路径从: \(url.path) 到: \(newPathURL.path)")
                    
                    // 创建一个更新了路径的歌曲对象
                    var updatedSong = song
                    // 注意：这里我们直接修改了song的副本，但Song是值类型，需要在适当的地方更新原始数组
                    // 这里仅用于检查，真正的更新会在其他位置进行
                }
                
                if !isValid {
                    invalidSongs.append(song)
                    print("无效歌曲: '\(song.title)' - 文件不存在: \(url.path)")
                } else {
                    validSongs.append(song)
                }
            } else {
                invalidSongs.append(song)
                print("无效歌曲: '\(song.title)' - URL为空")
            }
        }
        
        print("检查结果: 有效歌曲 \(validSongs.count) 首，无效歌曲 \(invalidSongs.count) 首")
        
        // 现在使用validSongs来更新歌单，但同时也检查歌单中的歌曲文件
        
        // 更新所有歌单
        for i in 0..<playlists.count {
            let originalCount = playlists[i].songs.count
            
            // 找出无效的歌曲并打印详细信息
            var invalidInPlaylist: [Song] = []
            var manuallyValidatedSongs: [Song] = []
            
            for song in playlists[i].songs {
                // 先检查是否在validSongs中
                if validSongs.contains(where: { $0.id == song.id }) {
                    manuallyValidatedSongs.append(song)
                    continue
                }
                
                // 如果不在validSongs中，再单独检查一次
                if let url = song.fileURL {
                    let songFileName = url.lastPathComponent
                    
                    // 检查原始路径
                    let fileExistsByPath = fileManager.fileExists(atPath: url.path)
                    
                    // 检查在新应用上下文中的路径
                    let newPathURL = musicDirectory.appendingPathComponent(songFileName)
                    let fileExistsAtNewPath = fileManager.fileExists(atPath: newPathURL.path)
                    
                    if fileExistsByPath || fileExistsAtNewPath {
                        manuallyValidatedSongs.append(song)
                        print("歌单歌曲额外验证通过: '\(song.title)' - 文件存在")
                        continue
                    }
                }
                
                // 如果都不存在，则认为是无效歌曲
                invalidInPlaylist.append(song)
                if let url = song.fileURL {
                    print("歌单 '\(playlists[i].name)' 中的无效歌曲: '\(song.title)' - 文件不存在: \(url.path)")
                } else {
                    print("歌单 '\(playlists[i].name)' 中的无效歌曲: '\(song.title)' - URL为空")
                }
            }
            
            // 更新歌单中的歌曲为有效歌曲
            if manuallyValidatedSongs.count != originalCount {
                print("歌单 '\(playlists[i].name)': 原有\(originalCount)首歌，保留\(manuallyValidatedSongs.count)首有效歌曲，移除\(originalCount - manuallyValidatedSongs.count)首无效歌曲")
            }
            
            playlists[i].songs = manuallyValidatedSongs
        }
        
        // 更新收藏歌单
        let originalFavoritesCount = favorites.songs.count
        
        // 找出收藏列表中的无效歌曲
        var invalidInFavorites: [Song] = []
        var validFavoriteSongs: [Song] = []
        
        for song in favorites.songs {
            // 先检查是否在validSongs中
            if validSongs.contains(where: { $0.id == song.id }) {
                validFavoriteSongs.append(song)
                continue
            }
            
            // 如果不在validSongs中，再单独检查一次
            if let url = song.fileURL {
                let songFileName = url.lastPathComponent
                
                // 检查原始路径
                let fileExistsByPath = fileManager.fileExists(atPath: url.path)
                
                // 检查在新应用上下文中的路径
                let newPathURL = musicDirectory.appendingPathComponent(songFileName)
                let fileExistsAtNewPath = fileManager.fileExists(atPath: newPathURL.path)
                
                if fileExistsByPath || fileExistsAtNewPath {
                    validFavoriteSongs.append(song)
                    print("收藏歌曲额外验证通过: '\(song.title)' - 文件存在")
                    continue
                }
            }
            
            // 如果都不存在，则认为是无效歌曲
            invalidInFavorites.append(song)
            if let url = song.fileURL {
                print("收藏歌单中的无效歌曲: '\(song.title)' - 文件不存在: \(url.path)")
            } else {
                print("收藏歌单中的无效歌曲: '\(song.title)' - URL为空")
            }
        }
        
        if validFavoriteSongs.count != originalFavoritesCount {
            print("收藏歌单: 原有\(originalFavoritesCount)首歌，保留\(validFavoriteSongs.count)首有效歌曲，移除\(originalFavoritesCount - validFavoriteSongs.count)首无效歌曲")
        }
        
        favorites.songs = validFavoriteSongs
        
        // 确保"我的收藏"在列表中
        ensureFavoritesPlaylist()
        
        // 保存更新后的歌单状态
        savePlaylists()
    }
    
    // MARK: - 调试辅助方法
    
    // 打印文件系统信息以便调试
    func debugFileSystem() {
        // 打印所有可能的文件路径
        let fileManager = FileManager.default
        
        // 1. 打印Documents目录
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        print("===== 文件系统调试信息 =====")
        print("Documents目录: \(documentsDirectory.path)")
        
        // 2. 打印应用沙盒根目录
        if let bundleID = Bundle.main.bundleIdentifier {
            print("应用Bundle ID: \(bundleID)")
        }
        
        // 3. 打印临时目录
        let tempDirectory = NSTemporaryDirectory()
        print("临时目录: \(tempDirectory)")
        
        // 4. 打印缓存目录
        let cacheDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        print("缓存目录: \(cacheDirectory.path)")
        
        // 5. 打印应用支持目录
        let appSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        print("应用支持目录: \(appSupportDirectory.path)")
        
        // 6. 列出Documents目录文件
        print("\n列出Documents目录文件:")
        do {
            let documentsFiles = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
            if documentsFiles.isEmpty {
                print("Documents目录为空")
            } else {
                for file in documentsFiles {
                    var fileSize: Int64 = 0
                    do {
                        let attr = try fileManager.attributesOfItem(atPath: file.path)
                        fileSize = attr[.size] as? Int64 ?? 0
                    } catch {
                        print("无法获取文件大小: \(error.localizedDescription)")
                    }
                    print("- \(file.lastPathComponent) (大小: \(fileSize)字节)")
                }
            }
        } catch {
            print("无法列出Documents目录: \(error.localizedDescription)")
        }
        
        // 7. 检查歌单文件是否存在
        let playlistsFile = getPlaylistsFilePath()
        if fileManager.fileExists(atPath: playlistsFile.path) {
            do {
                let attr = try fileManager.attributesOfItem(atPath: playlistsFile.path)
                let fileSize = attr[.size] as? Int64 ?? 0
                print("\n歌单文件存在于: \(playlistsFile.path)")
                print("歌单文件大小: \(fileSize)字节")
            } catch {
                print("\n歌单文件存在，但无法获取属性: \(error.localizedDescription)")
            }
        } else {
            print("\n歌单文件不存在于: \(playlistsFile.path)")
        }
        
        print("===== 文件系统调试信息结束 =====")
    }
    
    // 强制保存歌单数据 - 简化版，直接保存
    func forceSavePlaylists() {
        print("强制保存歌单数据")
        
        // 确保在主线程更新UI相关的数据
        if !Thread.isMainThread {
            DispatchQueue.main.sync {
                self.ensureFavoritesPlaylist()
            }
        } else {
            self.ensureFavoritesPlaylist()
        }
        
        // 直接调用保存方法
        savePlaylists()
    }
    
    // 保存所有数据
    func saveAllData() {
        // 保存歌曲数据
        if let encodedSongs = try? JSONEncoder().encode(songs) {
            userDefaults.set(encodedSongs, forKey: "songs")
            print("保存了\(songs.count)首歌曲的数据")
        }
        
        // 保存歌单数据
        savePlaylists()
    }
    
    // 获取歌曲JSON文件路径
    private func getSongsJSONPath() -> URL {
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // 确保Documents目录存在
        if !fileManager.fileExists(atPath: documentsDirectory.path) {
            do {
                try fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)
                print("创建Documents目录成功")
            } catch {
                print("无法创建Documents目录: \(error.localizedDescription)")
            }
        }
        
        // 歌曲JSON文件路径
        let jsonFilePath = documentsDirectory.appendingPathComponent("songs.json")
        print("歌曲JSON文件路径: \(jsonFilePath.path)")
        
        return jsonFilePath
    }
    
    // 获取歌单JSON文件路径
    private func getPlaylistsJSONPath() -> URL {
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // 歌单JSON文件路径
        let jsonFilePath = documentsDirectory.appendingPathComponent("playlists.json")
        print("歌单JSON文件路径: \(jsonFilePath.path)")
        
        return jsonFilePath
    }
    
    // 保存歌曲数据到JSON文件
    func saveSongsToJSON() {
        print("开始保存歌曲数据到JSON文件...")
        
        do {
            // 创建一个简化版的歌曲结构体，不包含歌词内容
            struct SimpleSong: Codable {
                let id: UUID
                let title: String
                let artist: String
                let album: String
                let duration: TimeInterval
                let filePath: String
                let coverImagePath: String?
                let fileSize: Int64
                let trackNumber: Int?
                let year: Int?
                let isPinned: Bool
                let creationDate: Date
                let albumName: String
                let albumArtist: String
                let composer: String
                let genre: String
                let lyricsFilePath: String?
                
                // 从Song创建SimpleSong
                init(from song: Song) {
                    self.id = song.id
                    self.title = song.title
                    self.artist = song.artist
                    self.album = song.album
                    self.duration = song.duration
                    self.filePath = song.relativePath  // 使用相对路径
                    self.coverImagePath = song.relativeArtworkPath  // 使用相对封面路径
                    self.fileSize = song.fileSize
                    self.trackNumber = song.trackNumber
                    self.year = song.year
                    self.isPinned = song.isPinned
                    self.creationDate = song.creationDate
                    self.albumName = song.albumName
                    self.albumArtist = song.albumArtist
                    self.composer = song.composer
                    self.genre = song.genre
                    self.lyricsFilePath = song.relativeLyricsPath  // 使用相对歌词路径
                    // 不包含歌词内容，只保存路径
                    
                    // 调试信息：验证路径格式
                    if self.filePath.hasPrefix("/") {
                        print("⚠️ 警告：音频文件路径仍为绝对路径: \(self.filePath)")
                    }
                    if let path = self.coverImagePath, path.hasPrefix("/") {
                        print("⚠️ 警告：封面路径仍为绝对路径: \(path)")
                    }
                    if let path = self.lyricsFilePath, path.hasPrefix("/") {
                        print("⚠️ 警告：歌词路径仍为绝对路径: \(path)")
                    }
                }
            }
            
            // 转换歌曲数组为简化版
            let simpleSongs = songs.map { SimpleSong(from: $0) }
            
            // 获取文件路径
            let jsonFilePath = getSongsJSONPath()
            
            // 编码并写入文件
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted // 美观格式
            let jsonData = try encoder.encode(simpleSongs)
            
            // 使用atomic选项直接写入文件，确保写入过程的原子性
            try jsonData.write(to: jsonFilePath, options: .atomic)
            
            // 验证写入是否成功
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: jsonFilePath.path)
            let fileSize = fileAttributes[.size] as? Int ?? 0
            
            print("歌曲JSON文件保存成功，文件大小：\(fileSize)字节，包含\(songs.count)首歌曲")
        } catch {
            print("保存歌曲JSON文件失败: \(error)")
        }
    }
    
    // 保存歌单数据到JSON文件
    func savePlaylistsToJSON() {
        print("开始保存歌单数据到JSON文件...")
        
        // 确保favorites在playlists中的引用是最新的
        if Thread.isMainThread {
            ensureFavoritesPlaylist()
        } else {
            // 如果不在主线程，需要同步更新
            DispatchQueue.main.sync {
                self.ensureFavoritesPlaylist()
            }
        }
        
        // 创建一个简化版的歌单结构体，只包含歌曲ID引用
        struct SimplePlaylist: Codable {
            let id: UUID
            let name: String
            let songIds: [UUID]
            let coverImage: String?  // 添加封面图片路径
            
            // 从Playlist创建SimplePlaylist
            init(from playlist: Playlist) {
                self.id = playlist.id
                self.name = playlist.name
                self.songIds = playlist.songs.map { $0.id }
                self.coverImage = playlist.coverImage  // 保存封面图片路径
            }
        }
        
        // 创建简化歌单数据结构
        struct PlaylistsData: Codable {
            var playlists: [SimplePlaylist]
            var favorites: SimplePlaylist
        }
        
        do {
            // 转换歌单为简化版
            let simplePlaylists = playlists.map { SimplePlaylist(from: $0) }
            let simpleFavorites = SimplePlaylist(from: favorites)
            
            // 创建数据结构
            let data = PlaylistsData(
                playlists: simplePlaylists,
                favorites: simpleFavorites
            )
            
            // 获取文件路径
            let jsonFilePath = getPlaylistsJSONPath()
            
            // 首先创建备份文件
            let backupFilePath = jsonFilePath.deletingPathExtension().appendingPathExtension("backup.json")
            let fileManager = FileManager.default
            
            // 如果主文件存在，先进行备份
            if fileManager.fileExists(atPath: jsonFilePath.path) {
                do {
                    // 删除旧备份
                    if fileManager.fileExists(atPath: backupFilePath.path) {
                        try fileManager.removeItem(at: backupFilePath)
                    }
                    // 复制当前文件作为备份
                    try fileManager.copyItem(at: jsonFilePath, to: backupFilePath)
                    print("已创建歌单文件备份: \(backupFilePath.path)")
                } catch {
                    print("创建备份文件失败: \(error.localizedDescription)")
                    // 备份失败不阻止继续保存
                }
            }
            
            // 编码并写入文件
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(data)
            
            // 使用临时文件写入，然后移动
            let tempFilePath = jsonFilePath.deletingLastPathComponent().appendingPathComponent("temp_playlists.json")
            
            // 先写入临时文件
            try jsonData.write(to: tempFilePath, options: .atomic)
            
            // 检查临时文件是否成功写入
            if fileManager.fileExists(atPath: tempFilePath.path) {
                // 如果目标文件已存在，先删除
                if fileManager.fileExists(atPath: jsonFilePath.path) {
                    try fileManager.removeItem(at: jsonFilePath)
                }
                // 然后移动临时文件到目标位置
                try fileManager.moveItem(at: tempFilePath, to: jsonFilePath)
            } else {
                throw NSError(domain: "com.xplayer", code: 1001, userInfo: [NSLocalizedDescriptionKey: "临时文件未成功创建"])
            }
            
            // 验证写入是否成功
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: jsonFilePath.path)
            let fileSize = fileAttributes[.size] as? Int ?? 0
            
            print("歌单JSON文件保存成功，文件大小：\(fileSize)字节，包含\(playlists.count)个歌单")
            
            // 额外验证文件内容
            if fileSize < 10 && playlists.count > 0 {
                print("警告: 保存的歌单文件大小异常小，可能未成功保存所有内容")
                throw NSError(domain: "com.xplayer", code: 1002, userInfo: [NSLocalizedDescriptionKey: "保存文件大小异常"])
            }
        } catch {
            print("保存歌单JSON文件失败: \(error.localizedDescription)")
            
            // 尝试恢复备份文件
            let backupFilePath = getPlaylistsJSONPath().deletingPathExtension().appendingPathExtension("backup.json")
            if FileManager.default.fileExists(atPath: backupFilePath.path) {
                do {
                    let jsonFilePath = getPlaylistsJSONPath()
                    // 如果目标文件已存在且可能损坏，先删除
                    if FileManager.default.fileExists(atPath: jsonFilePath.path) {
                        try FileManager.default.removeItem(at: jsonFilePath)
                    }
                    // 复制备份文件到主文件
                    try FileManager.default.copyItem(at: backupFilePath, to: jsonFilePath)
                    print("已从备份文件恢复歌单数据")
                } catch {
                    print("从备份恢复失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // 从JSON文件加载歌曲数据
    func loadSongsFromJSON() {
        let jsonFilePath = getSongsJSONPath()
        print("尝试从JSON文件加载歌曲: \(jsonFilePath.path)")
        
        let fileManager = FileManager.default
        
        // 检查文件是否存在
        if !fileManager.fileExists(atPath: jsonFilePath.path) {
            print("歌曲JSON文件不存在，将使用空歌曲库")
            return
        }
        
        do {
            // 读取JSON文件
            let jsonData = try Data(contentsOf: jsonFilePath)
            
            // 使用与保存相同的简化结构体
            struct SimpleSong: Codable {
                let id: UUID
                let title: String
                let artist: String
                let album: String
                let duration: TimeInterval
                let filePath: String
                let coverImagePath: String?
                let fileSize: Int64
                let trackNumber: Int?
                let year: Int?
                let isPinned: Bool
                let creationDate: Date
                let albumName: String
                let albumArtist: String
                let composer: String
                let genre: String
                let lyricsFilePath: String?
            }
            
            // 解码
            let decoder = JSONDecoder()
            let simpleSongs = try decoder.decode([SimpleSong].self, from: jsonData)
            
            // 将SimpleSong转换回Song对象
            let loadedSongs = simpleSongs.map { simpleSong -> Song in
                return Song(
                    id: simpleSong.id,
                    title: simpleSong.title,
                    artist: simpleSong.artist,
                    album: simpleSong.album,
                    duration: simpleSong.duration,
                    filePath: simpleSong.filePath,
                    lyrics: nil, // 加载时不包含歌词内容
                    coverImagePath: simpleSong.coverImagePath,
                    fileSize: simpleSong.fileSize,
                    trackNumber: simpleSong.trackNumber,
                    year: simpleSong.year,
                    albumName: simpleSong.albumName,
                    albumArtist: simpleSong.albumArtist,
                    composer: simpleSong.composer,
                    genre: simpleSong.genre,
                    lyricsFilePath: simpleSong.lyricsFilePath,
                    isPinned: simpleSong.isPinned,
                    creationDate: simpleSong.creationDate
                )
            }
            
            // 在主线程上更新数据
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                // 更新歌曲数据
                self.songs = loadedSongs
                
                // 重新组织专辑
                self.organizeAlbums()
                
                print("成功从JSON文件加载歌曲，包含\(self.songs.count)首歌曲")
            }
        } catch {
            print("加载歌曲JSON文件失败: \(error)")
        }
    }
    
    // 从JSON文件加载歌单数据
    func loadPlaylistsFromJSON() {
        let jsonFilePath = getPlaylistsJSONPath()
        print("尝试从JSON文件加载歌单: \(jsonFilePath.path)")
        
        let fileManager = FileManager.default
        
        // 检查文件是否存在
        if !fileManager.fileExists(atPath: jsonFilePath.path) {
            print("歌单JSON文件不存在，将使用默认歌单")
            // 确保"我的收藏"歌单存在
            self.ensureFavoritesPlaylist()
            return
        }
        
        do {
            // 读取JSON文件
            let jsonData = try Data(contentsOf: jsonFilePath)
            
            // 使用与保存相同的简化结构体
            struct SimplePlaylist: Codable {
                let id: UUID
                let name: String
                let songIds: [UUID]
                let coverImage: String?  // 添加封面图片路径
            }
            
            struct PlaylistsData: Codable {
                var playlists: [SimplePlaylist]
                var favorites: SimplePlaylist
            }
            
            // 解码
            let decoder = JSONDecoder()
            let playlistsData = try decoder.decode(PlaylistsData.self, from: jsonData)
            
            // 在主线程上更新数据
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                // 将歌单ID转换为实际歌曲
                let createPlaylist = { (simplePlaylist: SimplePlaylist) -> Playlist in
                    // 查找每个歌曲ID对应的歌曲对象
                    let playlistSongs = simplePlaylist.songIds.compactMap { songId -> Song? in
                        let result = self.songs.first { $0.id == songId }
                        // 对于收藏夹特别诊断找不到的歌曲ID
                        if simplePlaylist.name == "我的收藏" && result == nil {
                            print("警告: 收藏中的歌曲ID \(songId) 在主歌曲库中未找到匹配项！")
                        }
                        return result
                    }
                    
                    // 诊断收藏歌单的丢失情况
                    if simplePlaylist.name == "我的收藏" {
                        print("收藏歌单加载情况: 原始ID数量 \(simplePlaylist.songIds.count), 成功加载歌曲数量 \(playlistSongs.count)")
                        if simplePlaylist.songIds.count != playlistSongs.count {
                            print("警告: 收藏歌单有 \(simplePlaylist.songIds.count - playlistSongs.count) 首歌曲未能从主歌曲库中找到！")
                        }
                    }
                    
                    // 创建歌单对象，包含封面图片路径
                    return Playlist(id: simplePlaylist.id, name: simplePlaylist.name, songs: playlistSongs, coverImage: simplePlaylist.coverImage)
                }
                
                // 更新收藏夹
                self.favorites = createPlaylist(playlistsData.favorites)
                
                // 更新其他歌单
                self.playlists = playlistsData.playlists.map { createPlaylist($0) }
                
                // 确保"我的收藏"歌单存在并在第一位
                self.ensureFavoritesPlaylist()
                
                print("成功从JSON文件加载歌单，包含\(self.playlists.count)个歌单")
            }
        } catch {
            print("加载歌单JSON文件失败: \(error)")
            // 如果加载失败，确保至少有收藏夹
            self.ensureFavoritesPlaylist()
        }
    }
    
    // 检查并获取歌曲封面图片
    func checkAndDownloadCovers() {
        print("正在检查歌曲封面图片...")
        
        // 如果智能封面匹配功能已关闭，则不进行下载
        if !enableSmartCoverMatching {
            print("智能封面匹配功能已关闭，跳过封面下载")
            return
        }
        
        // 获取没有封面图片的歌曲
        let songsWithoutCover = songs.filter { $0.coverImagePath == nil || $0.coverImagePath?.isEmpty == true }
        
        if songsWithoutCover.isEmpty {
            print("所有歌曲已有封面图片，无需下载")
            return
        }
        
        print("发现\(songsWithoutCover.count)首歌曲没有封面图片，开始下载...")
        
        // 用于跟踪是否有歌曲被更新
        var hasSongsUpdated = false
        
        // 为每首没有封面的歌曲下载封面
        for song in songsWithoutCover {
            if let coverData = MusicFileManager.shared.fetchAlbumCoverFromNetwork(artist: song.artist, title: song.title, album: song.albumName) {
                print("成功为歌曲 '\(song.title)' 下载封面图片")
                
                // 保存封面图片并更新Song对象
                if let artworkURL = MusicFileManager.shared.saveArtwork(coverData, for: song.title) {
                    // 找到要更新的歌曲
                    if let index = songs.firstIndex(where: { $0.id == song.id }) {
                        // 创建更新后的歌曲对象
                        var updatedSong = song
                        updatedSong.coverImagePath = artworkURL.path
                        
                        // 更新歌曲列表
                        songs[index] = updatedSong
                        hasSongsUpdated = true
                        
                        print("已更新歌曲 '\(song.title)' 的封面图片路径")
                    }
                }
            } else {
                print("无法为歌曲 '\(song.title)' 下载封面图片")
            }
        }
        
        // 如果有歌曲更新，保存到JSON
        if hasSongsUpdated {
            print("封面图片下载完成，保存歌曲JSON")
            saveSongsToJSON()
            
            // 重新组织专辑（可能需要更新专辑封面）
            organizeAlbums()
        }
    }
    
    // 更新智能封面匹配设置
    func updateSmartCoverMatchingSetting(enabled: Bool) {
        self.enableSmartCoverMatching = enabled
        userDefaults.set(enabled, forKey: "enableSmartCoverMatching")
        
        print("智能封面匹配设置已更新为: \(enabled ? "开启" : "关闭")")
    }
    
    // 更新智能艺术家图片匹配设置
    func updateArtistImageMatchingSetting(enabled: Bool) {
        self.enableArtistImageMatching = enabled
        userDefaults.set(enabled, forKey: "enableArtistImageMatching")
        
        print("智能艺术家图片匹配设置已更新为: \(enabled ? "开启" : "关闭")")
    }
    
    // 更新歌曲排序模式设置
    func updateSongSortMode(mode: SongSortMode) {
        songSortMode = mode
        userDefaults.set(mode.rawValue, forKey: "songSortMode")
    }
    
    // 更新排序方向设置
    func updateSortDirection(ascending: Bool) {
        sortAscending = ascending
        userDefaults.set(ascending, forKey: "sortAscending")
    }
    
    // MARK: - 数据修复方法
    
    // 清理收藏歌单中的无效歌曲ID（那些在主歌曲库中不存在对应歌曲的ID）
    func cleanInvalidFavorites() {
        print("开始清理收藏歌单中的无效歌曲...")
        
        // 先从JSON文件读取原始数据
        let jsonFilePath = getPlaylistsJSONPath()
        
        guard FileManager.default.fileExists(atPath: jsonFilePath.path) else {
            print("未找到歌单文件，无需清理")
            return
        }
        
        do {
            // 读取JSON文件
            let jsonData = try Data(contentsOf: jsonFilePath)
            
            // 使用与保存相同的简化结构体
            struct SimplePlaylist: Codable {
                let id: UUID
                let name: String
                var songIds: [UUID]
                let coverImage: String?
            }
            
            struct PlaylistsData: Codable {
                var playlists: [SimplePlaylist]
                var favorites: SimplePlaylist
            }
            
            // 解码
            let decoder = JSONDecoder()
            var playlistsData = try decoder.decode(PlaylistsData.self, from: jsonData)
            
            // 获取当前主歌曲库中的所有歌曲ID
            let validSongIds = Set(self.songs.map { $0.id })
            
            // 过滤收藏歌单中的无效ID
            let originalFavoritesCount = playlistsData.favorites.songIds.count
            playlistsData.favorites.songIds = playlistsData.favorites.songIds.filter { songId in
                let isValid = validSongIds.contains(songId)
                if !isValid {
                    print("移除收藏中的无效歌曲ID: \(songId)")
                }
                return isValid
            }
            
            // 如果有歌曲被移除
            if originalFavoritesCount != playlistsData.favorites.songIds.count {
                print("从收藏中移除了 \(originalFavoritesCount - playlistsData.favorites.songIds.count) 首无效歌曲")
                
                // 重新编码并保存
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let updatedJsonData = try encoder.encode(playlistsData)
                
                // 使用临时文件写入，然后移动
                let tempFilePath = jsonFilePath.deletingLastPathComponent().appendingPathComponent("temp_playlists.json")
                
                // 先写入临时文件
                try updatedJsonData.write(to: tempFilePath, options: .atomic)
                
                // 如果目标文件已存在，先删除
                if FileManager.default.fileExists(atPath: jsonFilePath.path) {
                    try FileManager.default.removeItem(at: jsonFilePath)
                }
                
                // 然后移动临时文件到目标位置
                try FileManager.default.moveItem(at: tempFilePath, to: jsonFilePath)
                
                print("成功保存清理后的收藏歌单数据")
                
                // 重新加载歌单数据
                self.loadPlaylistsFromJSON()
            } else {
                print("收藏歌单中没有无效歌曲，无需清理")
            }
            
        } catch {
            print("清理收藏歌单失败: \(error)")
        }
    }
    
    // MARK: - 数据迁移方法
    
    // 手动强制执行路径迁移（用于调试和确保迁移完成）
    func forceMigratePathsToRelativeFormat() {
        print("🔧 强制执行路径迁移...")
        migratePathsToRelativeFormat()
    }
    
    // 检查是否需要迁移，如果需要则执行迁移
    func migratePathsToRelativeFormatIfNeeded() {
        // 首先检查是否有需要迁移的歌曲
        let needsMigration = songs.contains { song in
            // 检查音频文件路径（任何绝对路径都需要迁移）
            if song.filePath.hasPrefix("/") && song.filePath.contains("/Documents/") {
                return true
            }
            
            // 检查封面路径（任何绝对路径都需要迁移）
            if let coverPath = song.coverImagePath, coverPath.hasPrefix("/") && coverPath.contains("/Documents/") {
                return true
            }
            
            // 检查歌词路径（任何绝对路径都需要迁移）
            if let lyricsPath = song.lyricsFilePath, lyricsPath.hasPrefix("/") && lyricsPath.contains("/Documents/") {
                return true
            }
            
            return false
        }
        
        if needsMigration {
            print("🔄 检测到需要迁移的路径，开始执行迁移...")
            migratePathsToRelativeFormat()
        }
    }
    
    // 迁移旧的绝对路径到新的相对路径格式
    private func migratePathsToRelativeFormat() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
        var migrationCount = 0
        
        // 迁移歌曲路径
        for i in 0..<songs.count {
            var song = songs[i]
            var needsUpdate = false
            
            // 准备新的路径值
            var newFilePath = song.filePath
            var newCoverPath = song.coverImagePath
            var newLyricsPath = song.lyricsFilePath
            
            // 检查并迁移音频文件路径（处理任何绝对路径）
            if song.filePath.hasPrefix("/") && song.filePath.contains("/Documents/") {
                if let documentsRange = song.filePath.range(of: "/Documents/") {
                    let relativePath = String(song.filePath[documentsRange.upperBound...])
                    newFilePath = relativePath
                    print("🎵 迁移音频路径: \(song.filePath) -> \(relativePath)")
                    needsUpdate = true
                }
            }
            
            // 检查并迁移封面路径（处理任何绝对路径）
            if let coverPath = song.coverImagePath, coverPath.hasPrefix("/") && coverPath.contains("/Documents/") {
                if let documentsRange = coverPath.range(of: "/Documents/") {
                    let relativePath = String(coverPath[documentsRange.upperBound...])
                    newCoverPath = relativePath
                    print("🖼️ 迁移封面路径: \(coverPath) -> \(relativePath)")
                    needsUpdate = true
                }
            }
            
            // 检查并迁移歌词路径（处理任何绝对路径）
            if let lyricsPath = song.lyricsFilePath, lyricsPath.hasPrefix("/") && lyricsPath.contains("/Documents/") {
                if let documentsRange = lyricsPath.range(of: "/Documents/") {
                    let relativePath = String(lyricsPath[documentsRange.upperBound...])
                    newLyricsPath = relativePath
                    print("🎵 迁移歌词路径: \(lyricsPath) -> \(relativePath)")
                    needsUpdate = true
                }
            }
            
            // 如果需要更新，创建新的Song对象
            if needsUpdate {
                song = Song(
                    id: song.id,
                    title: song.title,
                    artist: song.artist,
                    album: song.album,
                    duration: song.duration,
                    filePath: newFilePath,
                    lyrics: song.lyrics,
                    coverImagePath: newCoverPath,
                    fileSize: song.fileSize,
                    trackNumber: song.trackNumber,
                    year: song.year,
                    albumName: song.albumName,
                    albumArtist: song.albumArtist,
                    composer: song.composer,
                    genre: song.genre,
                    lyricsFilePath: newLyricsPath,
                    isPinned: song.isPinned,
                    creationDate: song.creationDate
                )
                
                // 验证迁移后的路径
                print("📋 迁移后验证 - 歌曲: \(song.title)")
                print("   音频路径: \(song.relativePath)")
                print("   封面路径: \(song.relativeArtworkPath ?? "无")")
                print("   歌词路径: \(song.relativeLyricsPath ?? "无")")
                
                songs[i] = song
                migrationCount += 1
            }
        }
        
        // 如果有迁移，保存数据
        if migrationCount > 0 {
            print("✅ 路径迁移完成，共迁移 \(migrationCount) 首歌曲")
            
            // 强制保存到JSON，确保新的相对路径格式被持久化
            saveSongsToJSON()
            
            // 同时更新播放列表中的歌曲引用
            updatePlaylistSongReferences()
            
            // 验证保存结果
            print("🔍 验证迁移结果：检查JSON文件中的路径格式...")
            DispatchQueue.global(qos: .background).async {
                // 延迟一秒后验证保存结果
                Thread.sleep(forTimeInterval: 1.0)
                self.validateMigrationResults()
            }
        }
    }
    
    // 更新播放列表中的歌曲引用
    private func updatePlaylistSongReferences() {
        var playlistsUpdated = false
        
        // 更新普通播放列表
        for i in 0..<playlists.count {
            for j in 0..<playlists[i].songs.count {
                let playlistSongId = playlists[i].songs[j].id
                if let updatedSong = songs.first(where: { $0.id == playlistSongId }) {
                    playlists[i].songs[j] = updatedSong
                    playlistsUpdated = true
                }
            }
        }
        
        // 更新收藏列表
        for i in 0..<favorites.songs.count {
            let favoriteSongId = favorites.songs[i].id
            if let updatedSong = songs.first(where: { $0.id == favoriteSongId }) {
                favorites.songs[i] = updatedSong
                playlistsUpdated = true
            }
        }
        
        if playlistsUpdated {
            savePlaylistsToJSON()
            print("✅ 播放列表中的歌曲引用已更新")
        }
    }
    
    // 验证文件路径有效性并尝试修复
    func validateAndRepairFilePaths() {
        print("🔍 验证文件路径有效性...")
        
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var repairedCount = 0
        var removedCount = 0
        
        songs = songs.compactMap { song in
            // 检查文件是否存在
            if let fileURL = song.fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
                return song // 文件存在，保持不变
            }
            
            // 文件不存在，尝试修复路径
            print("🔧 尝试修复路径: \(song.title)")
            
            // 尝试不同的修复策略
            let fileName = URL(fileURLWithPath: song.filePath).lastPathComponent
            let possiblePaths = [
                documentsURL.appendingPathComponent("Music").appendingPathComponent(fileName),
                documentsURL.appendingPathComponent(fileName),
                documentsURL.appendingPathComponent("Downloads").appendingPathComponent(fileName)
            ]
            
            for possibleURL in possiblePaths {
                if FileManager.default.fileExists(atPath: possibleURL.path) {
                    print("✅ 找到文件: \(possibleURL.path)")
                    
                    // 创建修复后的歌曲对象
                    let repairedSong = Song(
                        id: song.id,
                        title: song.title,
                        artist: song.artist,
                        album: song.album,
                        duration: song.duration,
                        filePath: possibleURL.path,
                        lyrics: song.lyrics,
                        coverImagePath: song.coverImagePath,
                        fileSize: song.fileSize,
                        trackNumber: song.trackNumber,
                        year: song.year,
                        albumName: song.albumName,
                        albumArtist: song.albumArtist,
                        composer: song.composer,
                        genre: song.genre,
                        lyricsFilePath: song.lyricsFilePath,
                        isPinned: song.isPinned,
                        creationDate: song.creationDate
                    )
                    
                    repairedCount += 1
                    return repairedSong
                }
            }
            
            // 无法修复，移除这首歌
            print("❌ 无法找到文件，移除歌曲: \(song.title)")
            removedCount += 1
            return nil
        }
        
        if repairedCount > 0 || removedCount > 0 {
            print("🔧 路径修复完成: 修复 \(repairedCount) 首，移除 \(removedCount) 首")
            saveSongsToJSON()
            
            if removedCount > 0 {
                // 从播放列表中也移除无效歌曲
                cleanupInvalidSongsFromPlaylists()
            }
        } else {
            print("✅ 所有文件路径有效")
        }
    }
    
    // 验证迁移结果
    private func validateMigrationResults() {
        let jsonFilePath = getSongsJSONPath()
        
        do {
            let jsonData = try Data(contentsOf: jsonFilePath)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            
            // 检查JSON文件中是否还有绝对路径
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
            let hasAbsolutePaths = jsonString.contains(documentsPath)
            
            if hasAbsolutePaths {
                print("⚠️ 警告：JSON文件中仍包含绝对路径，迁移可能不完整")
                
                // 详细分析哪些字段还包含绝对路径
                let lines = jsonString.components(separatedBy: .newlines)
                for (index, line) in lines.enumerated() {
                    if line.contains(documentsPath) {
                        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        print("   第\(index + 1)行: \(trimmedLine)")
                    }
                }
            } else {
                print("✅ 验证成功：JSON文件已使用相对路径格式")
            }
            
            // 统计相对路径的数量
            let linesWithRelativePaths = jsonString.components(separatedBy: .newlines).filter { line in
                (line.contains("\"filePath\"") || line.contains("\"coverImagePath\"") || line.contains("\"lyricsFilePath\"")) && !line.contains(documentsPath)
            }
            print("📊 相对路径统计：找到 \(linesWithRelativePaths.count) 个相对路径字段")
            
            // 检查内存中的songs数组状态
            DispatchQueue.main.async {
                self.validateSongsInMemory()
            }
            
        } catch {
            print("❌ 验证迁移结果失败：\(error)")
        }
    }
    
    // 验证内存中的songs数组状态
    private func validateSongsInMemory() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
        var songsWithAbsolutePaths = 0
        
        for song in songs {
            var hasAbsolutePath = false
            
            // 检查各种路径
            if song.relativePath.hasPrefix("/") {
                print("🔴 歌曲 '\(song.title)' 的音频路径仍为绝对路径: \(song.relativePath)")
                hasAbsolutePath = true
            }
            
            if let artworkPath = song.relativeArtworkPath, artworkPath.hasPrefix("/") {
                print("🔴 歌曲 '\(song.title)' 的封面路径仍为绝对路径: \(artworkPath)")
                hasAbsolutePath = true
            }
            
            if let lyricsPath = song.relativeLyricsPath, lyricsPath.hasPrefix("/") {
                print("🔴 歌曲 '\(song.title)' 的歌词路径仍为绝对路径: \(lyricsPath)")
                hasAbsolutePath = true
            }
            
            if hasAbsolutePath {
                songsWithAbsolutePaths += 1
            }
        }
        
        if songsWithAbsolutePaths > 0 {
            print("⚠️ 发现 \(songsWithAbsolutePaths) 首歌曲仍使用绝对路径")
        } else {
            print("✅ 所有歌曲都已使用相对路径")
        }
    }
    
    // 从播放列表中清理无效歌曲
    private func cleanupInvalidSongsFromPlaylists() {
        let validSongIds = Set(songs.map { $0.id })
        var playlistsUpdated = false
        
        // 清理普通播放列表
        for i in 0..<playlists.count {
            let originalCount = playlists[i].songs.count
            playlists[i].songs = playlists[i].songs.filter { validSongIds.contains($0.id) }
            if playlists[i].songs.count != originalCount {
                playlistsUpdated = true
                print("🧹 从播放列表 '\(playlists[i].name)' 中移除了 \(originalCount - playlists[i].songs.count) 首无效歌曲")
            }
        }
        
        // 清理收藏列表
        let originalFavoritesCount = favorites.songs.count
        favorites.songs = favorites.songs.filter { validSongIds.contains($0.id) }
        if favorites.songs.count != originalFavoritesCount {
            playlistsUpdated = true
            print("🧹 从收藏列表中移除了 \(originalFavoritesCount - favorites.songs.count) 首无效歌曲")
        }
        
        if playlistsUpdated {
            savePlaylistsToJSON()
        }
    }
} 

