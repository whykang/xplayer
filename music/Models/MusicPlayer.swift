import Foundation
import AVFoundation
// import ActivityKit
import UIKit
import MediaPlayer

// 播放模式枚举
enum PlayMode {
    case normal      // 顺序播放
    case repeatOne   // 单曲循环
    case repeatAll   // 列表循环
    case shuffle     // 随机播放
}

// 共享的播放状态属性（已禁用灵动岛）
struct MusicPlaybackAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var isPlaying: Bool
        var currentTime: TimeInterval
        var duration: TimeInterval
        var artworkURLString: String? // 添加专辑封面URL
        
        init(title: String, artist: String, isPlaying: Bool, currentTime: TimeInterval, duration: TimeInterval, artworkURLString: String? = nil) {
            self.title = title
            self.artist = artist
            self.isPlaying = isPlaying
            self.currentTime = currentTime
            self.duration = duration
            self.artworkURLString = artworkURLString
        }
    }
}

class MusicPlayer: NSObject, ObservableObject {
    public static let shared = MusicPlayer()
    
    private var player: AVAudioPlayer?
    private var playerBufferingTimer: Timer?
    private var currentPlaylist: [Song] = []
    private var currentIndex: Int = -1
    private var shuffledIndices: [Int] = []
    
    // 定时播放
    private var sleepTimer: Timer?
    @Published var sleepTimerRemaining: TimeInterval = 0
    @Published var isSleepTimerActive: Bool = false
    @Published var isSleepAfterCurrentSong: Bool = false
    
    @Published var isPlaying = false
    @Published var currentSong: Song?
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isBuffering = false
    @Published var isSeeking = false
    @Published var seekPosition: Double = 0
    @Published var playMode: PlayMode = .repeatAll
    
    // 当前播放进度的百分比（0-1）
    var progressPercentage: Double {
        return currentTime / max(duration, 1)
    }
    
    // 蓝牙车机歌词显示相关
    private var displayLyricTimer: Timer?
    private var isLyricDisplayEnabled: Bool = false
    private var currentDisplayedLyrics: [LyricLine] = []
    private var originalSongTitle: String = ""
    private var currentLyricIndex: Int? = nil
    
    private var timer: Timer?
    
    // 音频会话和远程命令中心
    private let audioSession = AVAudioSession.sharedInstance()
    private let commandCenter = MPRemoteCommandCenter.shared()
    private let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
    
    // 播放器状态更新间隔
    private let updateInterval: TimeInterval = 0.5
    
    // 播放器状态更新回调
    var onPlayerStateUpdate: ((Bool, TimeInterval, TimeInterval) -> Void)?
    
    // 检查是否有活动的灵动岛 - 已禁用
    public var hasActiveLiveActivity: Bool {
        return false
    }
    
    public override init() {
        super.init()
        setupAudioSession()
        setupRemoteCommandCenter()
        
        // 监听应用终止通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }
    
    private func setupAudioSession() {
        do {
            try audioSession.setCategory(.playback, mode: .default, options: [.allowBluetooth, .allowAirPlay])
            try audioSession.setActive(true)
            
            // 设置音频会话以支持后台播放
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
            
            // 激活音频会话
            try audioSession.setActive(true)
        } catch let error {
            print("Failed to set up audio session: \(error)")
        }
    }
    
    // 配置远程控制命令中心，响应锁屏/控制中心的控制
    private func setupRemoteCommandCenter() {
        // 播放命令
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] event in
            self?.resume()
            return .success
        }
        
        // 暂停命令
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] event in
            self?.pause()
            return .success
        }
        
        // 下一首命令
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] event in
            self?.playNext()
            return .success
        }
        
        // 上一首命令
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] event in
            self?.playPrevious()
            return .success
        }
        
        // 快进命令
        commandCenter.seekForwardCommand.isEnabled = true
        
        // 快退命令
        commandCenter.seekBackwardCommand.isEnabled = true
        
        // 拖动进度条命令
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let event = event as? MPChangePlaybackPositionCommandEvent {
                self?.seek(to: event.positionTime)
            }
            return .success
        }
    }
    
    // 更新播放信息到系统
    private func updateNowPlayingInfo() {
        guard let song = currentSong else {
            // 清空播放信息
            nowPlayingInfoCenter.nowPlayingInfo = nil
            return
        }
        
        // 创建播放信息字典
        var nowPlayingInfo = [String: Any]()
        
        // 歌曲标题 - 如果开启了歌词显示且有当前歌词，则显示当前歌词
        if isLyricDisplayEnabled, let index = currentLyricIndex, index >= 0, index < currentDisplayedLyrics.count {
            nowPlayingInfo[MPMediaItemPropertyTitle] = currentDisplayedLyrics[index].text
        } else {
            nowPlayingInfo[MPMediaItemPropertyTitle] = song.title
        }
        
        // 艺术家
        nowPlayingInfo[MPMediaItemPropertyArtist] = song.artist
        
        // 专辑名称
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = song.album
        
        // 当前播放时间
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        
        // 总时长
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        
        // 播放速率
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
        // 专辑封面
        if let coverImagePath = song.coverImagePath, let image = UIImage(contentsOfFile: coverImagePath) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { size in
                return image
            }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        } else if let artworkURL = song.artworkURL {
            // 如果有在线封面，尝试下载
            loadArtworkFromURL(artworkURL) { image in
                if let image = image {
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { size in
                        return image
                    }
                    var updatedInfo = self.nowPlayingInfoCenter.nowPlayingInfo ?? [:]
                    updatedInfo[MPMediaItemPropertyArtwork] = artwork
                    self.nowPlayingInfoCenter.nowPlayingInfo = updatedInfo
                }
            }
        }
        
        // 更新播放信息
        nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo
    }
    
    // 从URL加载封面图片
    private func loadArtworkFromURL(_ url: URL, completion: @escaping (UIImage?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let data = data, let image = UIImage(data: data) {
                DispatchQueue.main.async {
                    completion(image)
                }
            } else {
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }.resume()
    }
    
    // 切换播放模式
    func togglePlayMode() {
        switch playMode {
        case .normal:
            playMode = .repeatAll
        case .repeatAll:
            playMode = .repeatOne
        case .repeatOne:
            playMode = .shuffle
            generateShuffleIndices()
        case .shuffle:
            playMode = .normal
        }
    }
    
    // 生成随机播放索引
    private func generateShuffleIndices() {
        // 检查播放列表是否为空
        if currentPlaylist.isEmpty {
            shuffledIndices = []
            return
        }
        
        shuffledIndices = Array(0..<currentPlaylist.count)
        shuffledIndices.shuffle()
        
        // 确保当前歌曲在随机序列中的位置被正确记录
        if let currentSong = currentSong, 
           let originalIndex = currentPlaylist.firstIndex(where: { $0.id.uuidString == currentSong.id.uuidString }),
           let shuffledPosition = shuffledIndices.firstIndex(of: originalIndex) {
            currentIndex = shuffledPosition
        }
    }
    
    // 开始计时器更新当前播放时间
    private func startTimer() {
        // 停止可能存在的计时器
        timer?.invalidate()
        
        // 创建新的计时器，每0.1秒更新一次当前时间
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.player else { return }
            
            if !self.isSeeking {
                self.currentTime = player.currentTime
            }
        }
    }
    
    // MARK: - Live Activity Management - 已禁用
    
    // 强制更新或创建Live Activity - 已禁用
    public func forceUpdateLiveActivity() {
        print("灵动岛功能已禁用")
    }
    
    // 测试灵动岛 - 已禁用
    public func startTestLiveActivity() {
        print("灵动岛功能已禁用")
    }
    
    private func createNewTestActivity() {
        // 灵动岛功能已禁用
    }
    
    // 开始 Live Activity - 已禁用
    private func startLiveActivity() {
        // 灵动岛功能已禁用
    }
    
    // 更新 Live Activity - 已禁用
    private func updateLiveActivity() {
        // 灵动岛功能已禁用
    }
    
    // 结束单个Live Activity - 已禁用
    private func endLiveActivity() {
        // 灵动岛功能已禁用
    }
    
    // 结束所有Live Activities - 已禁用
    func endAllLiveActivities() {
        // 灵动岛功能已禁用
    }
    
    // 播放器状态更新处理
    private func updatePlayerState() {
        guard let player = player else { return }
        
        currentTime = player.currentTime
        duration = player.duration
        
        // 更新共享数据，供Widget使用
        if let song = currentSong {
            AppShare.shared.updatePlaybackInfo(
                title: song.title,
                artist: song.artist,
                isPlaying: isPlaying,
                currentTime: currentTime,
                duration: duration
            )
            
            // 更新系统播放信息
            updateNowPlayingInfo()
        } else {
            AppShare.shared.clearPlaybackInfo()
            
            // 清空系统播放信息
            nowPlayingInfoCenter.nowPlayingInfo = nil
        }
        
        // 调用回调
        onPlayerStateUpdate?(isPlaying, currentTime, duration)
    }
    
    // MARK: - 播放控制
    
    // 播放歌曲
    func play(_ song: Song, addToRecentlyPlayed: Bool = true) {
        do {
            guard let url = song.fileURL else {
                print("播放失败: 无效的文件URL")
                return
            }
            
            // 停止当前播放
            player?.stop()
            
            // 设置音频会话
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            
            // 处理MP3降级问题
            let fileExtension = url.pathExtension.lowercased()
            if fileExtension == "mp3" {
                do {
                    player = try AVAudioPlayer(contentsOf: url)
                } catch {
                    print("MP3播放失败，尝试降级处理: \(error.localizedDescription)")
                    
                    // 降级播放MP3文件的处理方法：以Data方式读取再创建播放器
                    do {
                        let data = try Data(contentsOf: url)
                        player = try AVAudioPlayer(data: data)
                    } catch let innerError {
                        print("MP3降级处理失败: \(innerError.localizedDescription)")
                        throw innerError
                    }
                }
            } else {
                // 非MP3文件使用原始方法
                player = try AVAudioPlayer(contentsOf: url)
            }
            
            player?.delegate = self
            player?.prepareToPlay()
            player?.play()
            
            isPlaying = true
            currentTime = 0
            duration = player?.duration ?? 0
            currentSong = song
            
            print("🎵 开始播放歌曲: \(song.title) - \(song.artist)")
            
            // 创建或更新状态更新计时器
            setupTimer()
            
            // 更新共享数据
            AppShare.shared.updatePlaybackInfo(
                title: song.title,
                artist: song.artist,
                isPlaying: true,
                currentTime: 0,
                duration: duration
            )
            
            // 更新系统播放信息
            updateNowPlayingInfo()
            
            // 如果歌词显示功能已启用，加载当前歌曲歌词
            if isLyricDisplayEnabled {
                // 保存原始歌曲标题
                originalSongTitle = song.title
                
                // 加载歌词
                loadCurrentSongLyrics()
            }
            
            // 强制重新加载车机歌词显示，确保在自动播放下一首时歌词也能正确更新
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if self.isLyricDisplayEnabled {
                    self.loadCurrentSongLyrics()
                    self.startLyricDisplayTimer()
                }
            }
            
            // 如果直接调用play方法（而不是通过playFromPlaylist/playNext等），确保添加到当前播放列表
            if !currentPlaylist.contains(where: { $0.id.uuidString == song.id.uuidString }) {
                if currentPlaylist.isEmpty {
                    // 如果播放列表为空，直接设置
                    currentPlaylist = [song]
                    currentIndex = 0
                } else if currentIndex >= 0 && currentIndex < currentPlaylist.count {
                    // 插入到当前位置之后
                    currentPlaylist.insert(song, at: currentIndex + 1)
                    currentIndex += 1
                } else {
                    // 异常情况，添加到末尾
                    currentPlaylist.append(song)
                    currentIndex = currentPlaylist.count - 1
                }
                
                // 如果是随机模式，更新随机索引
                if playMode == .shuffle {
                    generateShuffleIndices()
                }
            } else {
                // 歌曲已在播放列表中，找到并更新当前索引
                if let index = currentPlaylist.firstIndex(where: { $0.id.uuidString == song.id.uuidString }) {
                    currentIndex = index
                }
            }
            
            // 立即开始 Live Activity - 确保在主线程调用
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                print("在主线程启动Live Activity")
                self.startLiveActivity()
            }
            
            // 调用回调
            onPlayerStateUpdate?(isPlaying, currentTime, duration)
            
            // 发送歌曲变化通知，确保UI能够正确更新
            NotificationCenter.default.post(name: Notification.Name("CurrentSongChanged"), object: nil, userInfo: [
                "song": song
            ])
        } catch let error {
            print("播放失败: \(error.localizedDescription)")
        }
    }
    
    // 播放/暂停切换
    func playPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }
    
    // 暂停播放
    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo() // 更新系统播放信息
        
        // 停止计时器
        timer?.invalidate()
        timer = nil
        
        // 更新共享数据
        if let song = currentSong {
            AppShare.shared.updatePlaybackInfo(
                title: song.title,
                artist: song.artist,
                isPlaying: false,
                currentTime: currentTime,
                duration: duration
            )
        }
        
        // 如果歌词显示功能启用，暂停歌词更新
        if isLyricDisplayEnabled {
            stopLyricDisplayTimer()
        }
        
        // 调用回调
        onPlayerStateUpdate?(isPlaying, currentTime, duration)
    }
    
    // 恢复播放
    func resume() {
        player?.play()
        isPlaying = true
        updateNowPlayingInfo() // 更新系统播放信息
        
        // 重新设置计时器
        setupTimer()
        
        // 更新共享数据
        if let song = currentSong {
            AppShare.shared.updatePlaybackInfo(
                title: song.title,
                artist: song.artist,
                isPlaying: true,
                currentTime: currentTime,
                duration: duration
            )
        }
        
        // 如果歌词显示功能启用，恢复歌词更新
        if isLyricDisplayEnabled {
            startLyricDisplayTimer()
        }
        
        // 调用回调
        onPlayerStateUpdate?(isPlaying, currentTime, duration)
    }
    
    // 跳转到指定时间
    func seek(to time: TimeInterval) {
        guard let player = player else { return }
        
        let seekTime = min(max(time, 0), duration)
        player.currentTime = seekTime
        currentTime = seekTime
        updateNowPlayingInfo() // 更新系统播放信息
        
        // 更新共享数据
        if let song = currentSong {
            AppShare.shared.updatePlaybackInfo(
                title: song.title,
                artist: song.artist,
                isPlaying: isPlaying,
                currentTime: currentTime,
                duration: duration
            )
        }
        
        // 调用回调
        onPlayerStateUpdate?(isPlaying, currentTime, duration)
    }
    
    // 停止播放
    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        currentSong = nil
        
        // 停止计时器
        timer?.invalidate()
        timer = nil
        
        // 停止歌词显示计时器
        stopLyricDisplayTimer()
        
        // 清空歌词数据
        currentDisplayedLyrics = []
        currentLyricIndex = nil
        
        // 清除共享数据
        AppShare.shared.clearPlaybackInfo()
        
        // 结束 Live Activity
        endLiveActivity()
        
        // 调用回调
        onPlayerStateUpdate?(isPlaying, currentTime, duration)
    }
    
    // 设置更新计时器
    private func setupTimer() {
        // 先移除现有计时器
        timer?.invalidate()
        
        // 创建新计时器，每隔updateInterval秒更新一次状态
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.updatePlayerState()
        }
    }
    
    // 播放上一首歌曲
    func playPrevious() {
        guard !currentPlaylist.isEmpty else { return }
        
        if currentTime > 3.0 {
            // 如果当前播放时间超过3秒，则重新从头播放当前歌曲
            seek(to: 0)
            return
        }
        
        var previousIndex = currentIndex
        
        switch playMode {
        case .shuffle:
            // 随机模式下，前一首是随机列表中的前一首
            // 添加保护逻辑，确保shuffledIndices不为空
            if shuffledIndices.isEmpty {
                // 如果随机索引数组为空，重新生成
                generateShuffleIndices()
                // 如果生成后仍为空（可能是currentPlaylist为空），则返回
                if shuffledIndices.isEmpty {
                    return
                }
            }
            previousIndex = (currentIndex - 1 + shuffledIndices.count) % shuffledIndices.count
            currentIndex = previousIndex
            play(currentPlaylist[shuffledIndices[previousIndex]])
            
        case .repeatOne:
            // 单曲循环模式下，重新播放当前歌曲
            seek(to: 0)
            
        case .normal, .repeatAll:
            // 普通模式或列表循环模式
            if currentIndex > 0 {
                // 可以播放前一首
                previousIndex = currentIndex - 1
            } else if playMode == .repeatAll {
                // 列表循环模式，回到最后一首
                previousIndex = currentPlaylist.count - 1
            } else {
                // 普通模式，保持第一首
                previousIndex = 0
            }
            
            currentIndex = previousIndex
            play(currentPlaylist[previousIndex])
        }
    }
    
    // 播放下一首歌曲
    func playNext() {
        guard !currentPlaylist.isEmpty else { 
            print("播放列表为空，无法播放下一首")
            return 
        }
        
        var nextIndex = currentIndex
        
        switch playMode {
        case .shuffle:
            // 随机模式下，下一首是随机列表中的下一首
            // 添加保护逻辑，确保shuffledIndices不为空
            if shuffledIndices.isEmpty {
                // 如果随机索引数组为空，重新生成
                generateShuffleIndices()
                // 如果生成后仍为空（可能是currentPlaylist为空），则返回
                if shuffledIndices.isEmpty {
                    print("随机播放索引为空，无法播放下一首")
                    return
                }
            }
            nextIndex = (currentIndex + 1) % shuffledIndices.count
            currentIndex = nextIndex
            print("随机播放模式：播放索引\(nextIndex)的歌曲")
            play(currentPlaylist[shuffledIndices[nextIndex]])
            
        case .repeatOne:
            // 单曲循环模式下，重新播放当前歌曲
            print("单曲循环模式：重新播放当前歌曲")
            seek(to: 0)
            
        case .normal:
            // 普通模式，如果是最后一首则停止
            if currentIndex < currentPlaylist.count - 1 {
                nextIndex = currentIndex + 1
                currentIndex = nextIndex
                print("普通模式：播放下一首索引\(nextIndex)的歌曲")
                play(currentPlaylist[nextIndex])
            } else {
                print("普通模式：已到达播放列表末尾，停止播放")
            }
            
        case .repeatAll:
            // 列表循环模式，循环播放
            nextIndex = (currentIndex + 1) % currentPlaylist.count
            currentIndex = nextIndex
            print("列表循环模式：播放索引\(nextIndex)的歌曲")
            play(currentPlaylist[nextIndex])
        }
    }
    
    // 设置播放列表
    func setPlaylist(songs: [Song], startIndex: Int = 0, autoPlay: Bool = true) {
        print("【播放器】设置播放列表，共\(songs.count)首歌曲，从索引\(startIndex)开始\(autoPlay ? "播放" : "准备")")
        
        // 清空当前播放列表并设置新的
        currentPlaylist = songs
        
        // 如果播放列表为空，重置索引并返回
        if songs.isEmpty {
            currentIndex = -1
            shuffledIndices = []
            print("【播放器】播放列表为空，无法播放")
            return
        }
        
        currentIndex = max(0, min(startIndex, songs.count - 1))
        
        // 如果是随机模式，生成随机索引
        if playMode == .shuffle {
            generateShuffleIndices()
        }
        
        // 获取要播放或准备的歌曲
        let songToPrepare = currentPlaylist[currentIndex]
        print("【播放器】已选择歌曲: \(songToPrepare.title) by \(songToPrepare.artist)")
        
        // 如果autoPlay为true，则开始播放，否则只准备但不播放
        if autoPlay {
            play(songToPrepare)
        } else {
            // 只加载歌曲，不播放
            prepareToPlay(songToPrepare)
        }
        
        // 发送通知，UI可以观察此通知来更新播放列表视图
        NotificationCenter.default.post(name: Notification.Name("PlaylistUpdated"), object: nil, userInfo: [
            "playlist": currentPlaylist,
            "currentIndex": currentIndex
        ])
        
        print("【播放器】已设置新的播放列表，共\(songs.count)首歌曲，\(autoPlay ? "开始播放" : "已准备")索引\(currentIndex)的歌曲: \(songToPrepare.title)")
    }
    
    // 准备播放但不开始
    private func prepareToPlay(_ song: Song) {
        do {
            // 加载音频文件
            guard let url = song.fileURL else {
                print("准备失败: 无效的文件URL")
                return
            }
            
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
            
            isPlaying = false
            currentTime = 0
            duration = player?.duration ?? 0
            currentSong = song
            
            print("🎵 已准备歌曲: \(song.title) - \(song.artist)")
            
            // 更新共享数据
            AppShare.shared.updatePlaybackInfo(
                title: song.title,
                artist: song.artist,
                isPlaying: false,
                currentTime: 0,
                duration: duration
            )
            
            // 更新系统播放信息
            updateNowPlayingInfo()
            
        } catch {
            print("准备歌曲失败: \(error.localizedDescription)")
        }
    }
    
    // 添加到播放列表末尾
    func addToPlaylist(song: Song, playNext: Bool = false) {
        if playNext && currentIndex >= 0 && currentIndex < currentPlaylist.count {
            // 检查歌曲是否已在播放列表中
            if let existingIndex = currentPlaylist.firstIndex(where: { $0.id.uuidString == song.id.uuidString }) {
                // 如果歌曲已存在，且不是将要播放的下一首（即不是当前歌曲的下一个位置）
                if existingIndex != currentIndex + 1 {
                    // 从原位置移除
                    currentPlaylist.remove(at: existingIndex)
                    
                    // 如果移除的位置在当前播放索引之前，需要调整当前索引
                    if existingIndex <= currentIndex {
                        currentIndex -= 1
                    }
                    
                    // 插入到当前播放位置之后
                    currentPlaylist.insert(song, at: currentIndex + 1)
                    print("已将歌曲'\(song.title)'从原位置移至下一首播放位置，当前播放列表长度: \(currentPlaylist.count)")
                } else {
                    print("歌曲'\(song.title)'已经在下一首位置，无需调整")
                }
            } else {
                // 如果歌曲不在播放列表中，插入到当前播放歌曲之后
                currentPlaylist.insert(song, at: currentIndex + 1)
                print("已添加歌曲'\(song.title)'作为下一首播放，当前播放列表长度: \(currentPlaylist.count)")
            }
        } else {
            // 检查是否已经在播放列表中
            if !currentPlaylist.contains(where: { $0.id.uuidString == song.id.uuidString }) {
                // 添加到播放列表末尾
                currentPlaylist.append(song)
                print("已添加歌曲'\(song.title)'到播放列表末尾，当前播放列表长度: \(currentPlaylist.count)")
            } else {
                print("歌曲'\(song.title)'已在播放列表中，跳过添加到末尾操作")
            }
        }
        
        // 如果是随机模式，更新随机索引
        if playMode == .shuffle {
            generateShuffleIndices()
        }
        
        // 如果当前没有播放歌曲，立即播放新添加的歌曲
        if currentSong == nil {
            print("当前无播放歌曲，立即从播放列表中播放")
            if playNext {
                currentIndex = currentIndex + 1
            } else {
                currentIndex = currentPlaylist.count - 1
            }
            play(currentPlaylist[currentIndex])
        }
    }
    
    // 从播放列表播放指定索引的歌曲
    func playFromPlaylist(at index: Int) {
        guard index >= 0 && index < currentPlaylist.count else { return }
        
        currentIndex = index
        
        // 如果是随机模式，更新当前索引在随机序列中的位置
        if playMode == .shuffle {
            if let shuffledIndex = shuffledIndices.firstIndex(of: index) {
                currentIndex = shuffledIndex
            }
        }
        
        play(currentPlaylist[index])
    }
    
    // 获取当前播放列表
    func getCurrentPlaylist() -> [Song] {
        return currentPlaylist
    }
    
    // 从当前播放列表中移除指定索引的歌曲
    func removeFromCurrentPlaylist(at index: Int) {
        guard index >= 0 && index < currentPlaylist.count else { return }
        
        let isCurrentSong = index == currentIndex
        
        // 移除歌曲
        currentPlaylist.remove(at: index)
        
        // 调整当前索引
        if isCurrentSong {
            // 如果移除的是当前播放的歌曲
            if currentPlaylist.isEmpty {
                // 如果播放列表已空，停止播放
                stop()
                currentIndex = -1
            } else if index < currentPlaylist.count {
                // 如果移除后该位置还有歌曲，播放该位置的歌曲
                currentIndex = index
                play(currentPlaylist[currentIndex])
            } else {
                // 否则播放最后一首
                currentIndex = currentPlaylist.count - 1
                play(currentPlaylist[currentIndex])
            }
        } else if index < currentIndex {
            // 如果移除的是当前歌曲之前的歌曲，当前索引需要减1
            currentIndex -= 1
        }
        
        // 如果是随机模式，重新生成随机序列
        if playMode == .shuffle {
            generateShuffleIndices()
        }
    }
    
    // 清空播放列表
    func clearPlaylist() {
        currentPlaylist.removeAll()
        currentIndex = -1
        shuffledIndices = []
        
        // 如果当前正在播放，停止播放
        if isPlaying {
            stop()
        }
        
        print("已清空播放列表")
    }
    
    // MARK: - 定时播放功能
    
    // 设置定时播放
    func setSleepTimer(minutes: Int) {
        // 取消现有的定时器
        cancelSleepTimer()
        
        // 如果设置为0分钟，仅取消定时器
        guard minutes > 0 else { return }
        
        // 计算结束时间（秒）
        let seconds = TimeInterval(minutes * 60)
        sleepTimerRemaining = seconds
        isSleepTimerActive = true
        isSleepAfterCurrentSong = false
        
        // 创建定时器更新剩余时间
        let displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            self.sleepTimerRemaining -= 1
            
            // 当倒计时结束时
            if self.sleepTimerRemaining <= 0 {
                self.stopPlaybackAndCancelTimer()
            }
        }
        
        // 保持定时器有效
        RunLoop.current.add(displayTimer, forMode: .common)
        sleepTimer = displayTimer
        
        print("定时播放已设置，\(minutes)分钟后停止播放")
    }
    
    // 设置播放完当前歌曲后停止
    func setSleepAfterCurrentSong() {
        // 取消现有的定时器
        cancelSleepTimer()
        
        // 标记为播放完当前歌曲后停止
        isSleepAfterCurrentSong = true
        isSleepTimerActive = false
        
        print("已设置播放完当前歌曲后停止")
    }
    
    // 取消定时播放
    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerRemaining = 0
        isSleepTimerActive = false
        isSleepAfterCurrentSong = false
        print("已取消定时播放")
    }
    
    // 获取格式化后的剩余时间
    func formattedSleepTimerRemaining() -> String {
        let minutes = Int(sleepTimerRemaining) / 60
        let seconds = Int(sleepTimerRemaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // 停止播放并取消定时器
    private func stopPlaybackAndCancelTimer() {
        // 停止音乐播放
        pause()
        
        // 取消定时器
        cancelSleepTimer()
        
        print("定时播放时间到，已停止播放")
    }
    
    // 处理应用终止
    @objc private func handleAppWillTerminate() {
        print("应用即将终止，清理资源...")
        // 取消定时播放
        cancelSleepTimer()
    }
    
    // MARK: - Sharing Functionality
    
    // 分享当前播放的歌曲文件
    func shareSong() -> UIActivityViewController? {
        guard let currentSong = currentSong else { return nil }
        
        // 创建要分享的内容
        let songTitle = currentSong.title
        let artist = currentSong.artist
        let shareText = "\(songTitle) - \(artist)"
        
        // 准备分享的内容
        var itemsToShare: [Any] = [shareText]
        
        // 使用getShareableFileURL方法获取可分享的文件URL
        if let shareableURL = currentSong.getShareableFileURL() {
            print("获取到可分享的文件URL: \(shareableURL.path)")
            
            // 获取安全访问权限
            let secureAccess = shareableURL.startAccessingSecurityScopedResource()
            
            // 确保在操作完成后停止访问（通过活动控制器的完成回调）
            itemsToShare.append(shareableURL)
            
            // 创建活动视图控制器
            let activityViewController = UIActivityViewController(activityItems: itemsToShare, applicationActivities: nil)
            
            // 排除一些活动类型
            activityViewController.excludedActivityTypes = [
                .addToReadingList,
                .assignToContact,
                .openInIBooks
            ]
            
            // 设置完成回调来停止安全访问
            activityViewController.completionWithItemsHandler = { (activityType, completed, returnedItems, error) in
                if secureAccess {
                    shareableURL.stopAccessingSecurityScopedResource()
                }
                
                if let error = error {
                    print("分享操作出错: \(error)")
                } else if completed {
                    print("分享操作完成，活动类型: \(activityType?.rawValue ?? "未知")")
                } else {
                    print("分享操作取消")
                }
            }
            
            return activityViewController
        } else {
            // 如果无法获取文件URL，仅分享文本信息
            print("无法获取可分享的文件URL，仅分享文本信息")
            
            let activityViewController = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
            
            // 排除一些活动类型
            activityViewController.excludedActivityTypes = [
                .addToReadingList,
                .assignToContact,
                .openInIBooks
            ]
            
            return activityViewController
        }
    }
    
    // MARK: - 车机歌词显示功能
    
    // 设置歌词显示开关
    func setLyricDisplayEnabled(_ enabled: Bool) {
        isLyricDisplayEnabled = enabled
        
        if enabled {
            // 保存原始歌曲标题
            originalSongTitle = currentSong?.title ?? ""
            
            // 加载当前歌曲歌词
            loadCurrentSongLyrics()
            
            // 启动歌词更新计时器
            startLyricDisplayTimer()
        } else {
            // 停止计时器
            stopLyricDisplayTimer()
            
            // 恢复原始歌曲标题
            if let song = currentSong {
                var nowPlayingInfo = nowPlayingInfoCenter.nowPlayingInfo ?? [:]
                nowPlayingInfo[MPMediaItemPropertyTitle] = originalSongTitle
                nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo
            }
        }
    }
    
    // 获取歌词显示状态
    func getLyricDisplayEnabled() -> Bool {
        return isLyricDisplayEnabled
    }
    
    // 加载当前歌曲歌词
    private func loadCurrentSongLyrics() {
        guard let song = currentSong else {
            currentDisplayedLyrics = []
            currentLyricIndex = nil
            return
        }
        
        // 清空当前歌词
        currentDisplayedLyrics = []
        currentLyricIndex = nil
        
        // 如果歌曲有歌词，解析它
        if let lyrics = song.lyrics, !lyrics.isEmpty {
            let fileManager = MusicFileManager.shared
            currentDisplayedLyrics = fileManager.parseLyrics(from: lyrics)
            print("已加载车机显示歌词，共\(currentDisplayedLyrics.count)行")
        } else {
            // 尝试在Lyrics目录中查找歌词
            if let lyricsFromDirectory = MusicFileManager.shared.findLyricsInDirectoryFor(song) {
                currentDisplayedLyrics = MusicFileManager.shared.parseLyrics(from: lyricsFromDirectory)
                print("从Lyrics目录加载车机显示歌词，共\(currentDisplayedLyrics.count)行")
            } else {
                print("无法找到歌词，车机将只显示歌曲标题")
            }
        }
        
        // 更新当前歌词索引
        updateCurrentLyricIndex()
    }
    
    // 启动歌词显示计时器
    private func startLyricDisplayTimer() {
        // 先停止之前的计时器
        stopLyricDisplayTimer()
        
        // 创建新计时器，每0.5秒更新一次歌词
        displayLyricTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateCurrentLyricIndex()
        }
    }
    
    // 停止歌词显示计时器
    private func stopLyricDisplayTimer() {
        displayLyricTimer?.invalidate()
        displayLyricTimer = nil
    }
    
    // 更新当前歌词索引
    private func updateCurrentLyricIndex() {
        if currentDisplayedLyrics.isEmpty { return }
        
        let time = currentTime
        
        // 查找当前时间对应的歌词索引
        var index = 0
        for i in 0..<currentDisplayedLyrics.count {
            if i + 1 < currentDisplayedLyrics.count {
                if time >= currentDisplayedLyrics[i].timeTag && time < currentDisplayedLyrics[i + 1].timeTag {
                    index = i
                    break
                }
            } else {
                if time >= currentDisplayedLyrics[i].timeTag {
                    index = i
                    break
                }
            }
        }
        
        // 如果索引变化了，更新显示
        if currentLyricIndex != index {
            currentLyricIndex = index
            
            // 更新系统播放信息显示当前歌词
            if isLyricDisplayEnabled {
                var nowPlayingInfo = nowPlayingInfoCenter.nowPlayingInfo ?? [:]
                nowPlayingInfo[MPMediaItemPropertyTitle] = currentDisplayedLyrics[index].text
                nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo
            }
        }
    }
}

extension MusicPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // 播放结束
        isPlaying = false
        currentTime = duration
        
        // 停止计时器
        timer?.invalidate()
        timer = nil
        
        // 检查是否设置了播放完当前歌曲后停止
        if isSleepAfterCurrentSong {
            isSleepAfterCurrentSong = false
            print("当前歌曲播放完毕，停止播放")
        } else if playMode == .repeatOne {
            // 单曲循环模式
            seek(to: 0)
            resume()
        } else {
            // 根据播放模式自动播放下一首
            playNext()
        }
        
        // 更新共享数据
        if let song = currentSong {
            AppShare.shared.updatePlaybackInfo(
                title: song.title,
                artist: song.artist,
                isPlaying: false,
                currentTime: duration,
                duration: duration
            )
        }
        
        // 调用回调
        onPlayerStateUpdate?(isPlaying, currentTime, duration)
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("Audio player decode error: \(String(describing: error))")
        isBuffering = false
    }
} 