import Foundation

class PlaybackStateManager {
    static let shared = PlaybackStateManager()
    
    private let userDefaults = UserDefaults.standard
    private let musicPlayer = MusicPlayer.shared
    private let userSettings = UserSettings.shared
    
    // 保存播放状态的键名
    private enum Keys {
        static let currentSongID = "playbackState_currentSongID"
        static let currentPosition = "playbackState_currentPosition"
        static let isPlaying = "playbackState_isPlaying"
        static let playlistSongs = "playbackState_playlistSongs"
        static let currentIndex = "playbackState_currentIndex"
        static let playMode = "playbackState_playMode"
    }
    
    // 构造函数
    private init() {}
    
    // 保存当前播放状态
    func savePlaybackState() {
        // 检查是否开启了保存播放状态的功能
        guard userSettings.savePlaybackState else {
            print("保存播放状态功能已关闭，跳过保存")
            return
        }
        
        // 检查是否有正在播放的歌曲
        guard let currentSong = musicPlayer.currentSong else {
            print("当前没有播放的歌曲，无需保存播放状态")
            return
        }
        
        print("开始保存播放状态")
        
        // 保存当前歌曲ID
        userDefaults.set(currentSong.id.uuidString, forKey: Keys.currentSongID)
        
        // 保存当前播放位置
        userDefaults.set(musicPlayer.currentTime, forKey: Keys.currentPosition)
        
        // 保存是否在播放状态
        userDefaults.set(musicPlayer.isPlaying, forKey: Keys.isPlaying)
        
        // 保存当前播放列表
        let playlist = musicPlayer.getCurrentPlaylist()
        if !playlist.isEmpty {
            let songIDs = playlist.map { $0.id.uuidString }
            userDefaults.set(songIDs, forKey: Keys.playlistSongs)
            
            // 保存当前歌曲在播放列表中的索引
            if let currentSong = musicPlayer.currentSong,
               let currentSongIndex = playlist.firstIndex(where: { $0.id == currentSong.id }) {
                userDefaults.set(currentSongIndex, forKey: Keys.currentIndex)
            }
        }
        
        // 保存播放模式
        let playModeString: String
        switch musicPlayer.playMode {
        case .normal:
            playModeString = "normal"
        case .repeatOne:
            playModeString = "repeatOne"
        case .repeatAll:
            playModeString = "repeatAll"
        case .shuffle:
            playModeString = "shuffle"
        }
        userDefaults.set(playModeString, forKey: Keys.playMode)
        
        print("播放状态保存完成")
    }
    
    // 恢复播放状态
    func restorePlaybackState() {
        // 检查是否开启了保存播放状态的功能
        guard userSettings.savePlaybackState else {
            print("保存播放状态功能已关闭，跳过恢复")
            return
        }
        
        print("开始恢复播放状态")
        
        // 检查是否有保存的歌曲ID
        guard let savedSongIDString = userDefaults.string(forKey: Keys.currentSongID),
              let savedSongID = UUID(uuidString: savedSongIDString) else {
            print("没有找到保存的歌曲ID，无法恢复播放状态")
            return
        }
        
        // 检查是否有保存的播放列表
        guard let savedPlaylistIDs = userDefaults.stringArray(forKey: Keys.playlistSongs),
              !savedPlaylistIDs.isEmpty else {
            print("没有找到保存的播放列表，无法恢复播放状态")
            return
        }
        
        // 从MusicLibrary获取歌曲对象
        let musicLibrary = MusicLibrary.shared
        var playlistSongs: [Song] = []
        
        for songIDString in savedPlaylistIDs {
            if let songID = UUID(uuidString: songIDString),
               let song = musicLibrary.songs.first(where: { $0.id == songID }) {
                playlistSongs.append(song)
            }
        }
        
        if playlistSongs.isEmpty {
            print("无法恢复播放列表中的歌曲，可能已被删除")
            return
        }
        
        // 恢复播放列表
        let savedIndex = userDefaults.integer(forKey: Keys.currentIndex)
        let validIndex = min(max(0, savedIndex), playlistSongs.count - 1)
        
        // 恢复播放模式
        if let playModeString = userDefaults.string(forKey: Keys.playMode) {
            switch playModeString {
            case "normal":
                musicPlayer.playMode = .normal
            case "repeatOne":
                musicPlayer.playMode = .repeatOne
            case "repeatAll":
                musicPlayer.playMode = .repeatAll
            case "shuffle":
                musicPlayer.playMode = .shuffle
            default:
                musicPlayer.playMode = .repeatAll // 默认为列表循环
            }
        }
        
        // 设置播放列表，但不自动开始播放
        musicPlayer.setPlaylist(songs: playlistSongs, startIndex: validIndex, autoPlay: false)
        
        // 恢复播放位置
        let savedPosition = userDefaults.double(forKey: Keys.currentPosition)
        musicPlayer.seek(to: savedPosition)
        
        // 记录之前的播放状态，但不自动恢复播放
        let wasPlaying = userDefaults.bool(forKey: Keys.isPlaying)
        print("之前的播放状态: \(wasPlaying ? "正在播放" : "已暂停")")
        
        // 不再自动恢复播放，即使之前是播放状态
        // if wasPlaying {
        //     musicPlayer.resume()
        // }
        
        print("播放状态恢复完成，但未自动恢复播放")
    }
    
    // 清除保存的播放状态
    func clearPlaybackState() {
        userDefaults.removeObject(forKey: Keys.currentSongID)
        userDefaults.removeObject(forKey: Keys.currentPosition)
        userDefaults.removeObject(forKey: Keys.isPlaying)
        userDefaults.removeObject(forKey: Keys.playlistSongs)
        userDefaults.removeObject(forKey: Keys.currentIndex)
        userDefaults.removeObject(forKey: Keys.playMode)
        
        print("已清除保存的播放状态")
    }
} 
