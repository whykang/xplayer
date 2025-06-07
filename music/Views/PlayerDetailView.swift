import SwiftUI
import UIKit
import Foundation

struct PlayerDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isPresented: Bool
    @ObservedObject var musicPlayer = MusicPlayer.shared
    @ObservedObject var musicLibrary = MusicLibrary.shared
    @ObservedObject var musicFileManager = MusicFileManager.shared
    
    @State private var showLyrics = false
    @State private var currentSong: Song?
    @State private var parsedLyrics: [LyricLine] = []
    @State private var currentLyricIndex: Int? = nil
    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var isPlaying = false
    @State private var lyricsLoaded = false
    @State private var showPlayQueue = false
    @State private var showSleepTimer = false
    
    // 构造函数重载，兼容传入isPresented的调用方式
    init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }
    
    // 保留原有的构造函数
    init(musicPlayer: MusicPlayer, musicLibrary: MusicLibrary, musicFileManager: MusicFileManager) {
        self.musicPlayer = musicPlayer
        self.musicLibrary = musicLibrary
        self.musicFileManager = musicFileManager
        self._isPresented = .constant(true) // 传入一个常量绑定
    }
    
    // 定时播放选项
    private let sleepTimerOptions = [15, 30, 45, 60, 90]
    
    var body: some View {
        GeometryReader { geometry in
        ZStack {
            // 背景层
            LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0.8), Color.purple.opacity(0.4)]), 
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            
            // 关闭按钮 - 放在ZStack顶层，独立于内容
            VStack {
                HStack {
                    Button(action: {
                        isPresented = false
                        dismiss()
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.3))
                                    .frame(width: 50, height: 50)
                            Image(systemName: "chevron.down")
                                    .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                        .padding(.leading, 16)
                        .padding(.top, max(0, geometry.safeAreaInsets.top - 15))
                    
                    Spacer()
                }
                Spacer()
            }
            .zIndex(1) // 确保按钮在最上层
            
            // 播放列表视图 - 从底部弹出
            if showPlayQueue {
                SimplePlayQueueView(
                    musicPlayer: musicPlayer,
                    isShowing: $showPlayQueue
                )
                .zIndex(2) // 确保播放列表在最上层
            }
            
                VStack(spacing: 0) {
                    // 在这里添加小空间，避免内容被顶部按钮遮挡，固定为10点
                    Spacer().frame(height: 10)
                
                    // 中间内容区域 - 使用Flexible模式
                if showLyrics {
                    // 歌词视图
                    VStack {
                            // 添加歌曲标题和作者
                            VStack(spacing: 4) {
                                Text(currentSong?.title ?? "未在播放")
                                    .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                                
                                Text(currentSong?.artist ?? "")
                                    .font(.body)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .padding(.top, 5)
                            .padding(.bottom, 10)
                            .padding(.horizontal)
                        
                        if parsedLyrics.isEmpty {
                            if lyricsLoaded {
                                Text("暂无歌词")
                                    .foregroundColor(.white.opacity(0.6))
                                    .padding(.top, 40)
                            } else {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .padding(.top, 40)
                            }
                        } else {
                            ScrollViewReader { proxy in
                                ScrollView(.vertical, showsIndicators: false) {
                                    VStack(spacing: 24) {
                                        ForEach(Array(parsedLyrics.enumerated()), id: \.element.id) { index, line in
                                            Text(line.text)
                                                .font(.system(size: currentLyricIndex == index ? 18 : 16))
                                                .fontWeight(currentLyricIndex == index ? .bold : .regular)
                                                .foregroundColor(currentLyricIndex == index ? .white : .white.opacity(0.6))
                                                .multilineTextAlignment(.center)
                                                .padding(.horizontal)
                                                .padding(.vertical, 4)
                                                .id(index)
                                                .transition(.opacity)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .fill(Color.white.opacity(0.05))
                                                        .opacity(currentLyricIndex == index ? 1 : 0)
                                                )
                                                .onTapGesture {
                                                    seekToLyric(at: index)
                                                }
                                        }
                                    }
                                        .padding(.vertical, 40)
                                }
                                .onAppear {
                                    scrollProxy = proxy
                                    if let index = currentLyricIndex {
                                        proxy.scrollTo(index, anchor: .center)
                                    }
                                }
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation {
                            showLyrics.toggle()
                        }
                    }
                } else {
                        // 专辑封面视图与歌词预览 - 自适应布局
                        VStack(spacing: 0) {
                        // 歌曲标题 - 放在专辑封面上方
                        VStack(spacing: 4) {
                            Text(currentSong?.title ?? "未在播放")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text(currentSong?.artist ?? "")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.7))
                        }
                            .padding(.top, 5)
                            .padding(.bottom, 8)
                            .padding(.horizontal)
                        
                            Spacer(minLength: 8)
                        
                            // 专辑封面 - 动态尺寸
                        if let song = currentSong {
                                let coverSize = min(geometry.size.width * 0.75, 270)
                                AlbumArtworkView(song: song, size: coverSize)
                                .shadow(radius: 10)
                                    .padding(.vertical, 5)
                        } else {
                                let coverSize = min(geometry.size.width * 0.75, 270)
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.gray.opacity(0.3))
                                    .frame(width: coverSize, height: coverSize)
                                    .padding(.vertical, 5)
                        }
                        
                            // 歌词预览 - 只在有歌词时显示
                            if !parsedLyrics.isEmpty {
                                VStack(spacing: 8) {
                            ForEach(-2...2, id: \.self) { offset in
                                if let currentIndex = currentLyricIndex,
                                   let index = calculateIndex(currentIndex + offset),
                                   index >= 0 && index < parsedLyrics.count {
                                    Text(parsedLyrics[index].text)
                                        .font(.system(size: offset == 0 ? 17 : 15))
                                        .fontWeight(offset == 0 ? .bold : .regular)
                                        .foregroundColor(offset == 0 ? .white : .white.opacity(0.6))
                                        .lineLimit(1)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                        .scaleEffect(offset == 0 ? 1.05 : 1.0)
                                        .animation(.easeInOut, value: currentLyricIndex)
                                        .onTapGesture {
                                            if let currentIndex = currentLyricIndex {
                                                seekToLyric(at: currentIndex + offset)
                                            }
                                        }
                                }
                            }
                        }
                                .frame(height: min(120, geometry.size.height * 0.15))
                                .padding(.top, 8)
                            } else {
                                // 如果没有歌词，添加一些空间
                        Spacer()
                                    .frame(height: min(60, geometry.size.height * 0.08))
                            }
                            
                            Spacer(minLength: 5)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation {
                            showLyrics.toggle()
                        }
                    }
                }
                
                    Spacer(minLength: 10)
                
                // 底部控制区域
                    VStack(spacing: min(20, geometry.size.height * 0.025)) {
                    // 进度条
                    VStack(spacing: 8) {
                            Spacer().frame(height: 10)
                            
                        // 进度滑块
                            GeometryReader { sliderGeometry in
                            ZStack(alignment: .leading) {
                                // 背景条
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white.opacity(0.2))
                                    .frame(height: 6)
                                
                                // 进度条
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white)
                                        .frame(width: sliderGeometry.size.width * (musicPlayer.isSeeking ? musicPlayer.seekPosition : (musicPlayer.currentTime / max(musicPlayer.duration, 1))), height: 6)
                                
                                // 滑块圆点
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 18, height: 18)
                                    .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 0)
                                        .offset(x: sliderGeometry.size.width * (musicPlayer.isSeeking ? musicPlayer.seekPosition : (musicPlayer.currentTime / max(musicPlayer.duration, 1))) - 9)
                            }
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        musicPlayer.isSeeking = true
                                            musicPlayer.seekPosition = min(max(0, value.location.x / sliderGeometry.size.width), 1)
                                    }
                                    .onEnded { _ in
                                        musicPlayer.seek(to: musicPlayer.seekPosition * musicPlayer.duration)
                                        musicPlayer.isSeeking = false
                                    }
                            )
                        }
                        .frame(height: 30)
                        
                        // 时间标签
                        HStack {
                            Text(formatTime(musicPlayer.currentTime))
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            
                            Spacer()
                            
                            Text(formatTime(musicPlayer.duration))
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal)
                    
                        // 播放控制 - 动态间距
                        let controlSpacing = min(40, geometry.size.width * 0.1)
                        HStack(spacing: controlSpacing) {
                        Button(action: {
                            musicPlayer.playPrevious()
                        }) {
                            Image(systemName: "backward.fill")
                                    .font(.system(size: 30))
                                .foregroundColor(.white)
                                    .frame(width: 48, height: 48)
                                .contentShape(Rectangle())
                        }
                        
                        Button(action: {
                            if isPlaying {
                                musicPlayer.pause()
                            } else {
                                musicPlayer.resume()
                            }
                        }) {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 70))
                                .foregroundColor(.white)
                                    .frame(width: 80, height: 80)
                                .contentShape(Rectangle())
                        }
                        
                        Button(action: {
                            musicPlayer.playNext()
                        }) {
                            Image(systemName: "forward.fill")
                                    .font(.system(size: 30))
                                .foregroundColor(.white)
                                    .frame(width: 48, height: 48)
                                .contentShape(Rectangle())
                        }
                    }
                        .padding(.vertical, 12)
                    
                        // 额外控制按钮 - 完全自适应布局
                        let buttonSize: CGFloat = 50
                        let buttonCount: CGFloat = 5
                        let availableWidth = geometry.size.width - 40 // 减去两侧边距
                        
                        // 计算适合的间距
                        let spacing = min(20, (availableWidth - (buttonSize * buttonCount)) / (buttonCount - 1))
                        
                        HStack(spacing: spacing) {
                        Button(action: {
                            musicPlayer.togglePlayMode()
                        }) {
                            Image(systemName: playModeIcon)
                                    .font(.system(size: 24))
                                .foregroundColor(isActivePlayMode ? .white : .white.opacity(0.7))
                                    .frame(width: buttonSize, height: buttonSize)
                                .contentShape(Rectangle())
                        }
                        
                        Button(action: {
                            // 显示歌词/专辑封面切换
                            withAnimation {
                                showLyrics.toggle()
                            }
                        }) {
                            Image(systemName: showLyrics ? "music.note" : "text.quote")
                                    .font(.system(size: 24))
                                .foregroundColor(.white.opacity(0.7))
                                    .frame(width: buttonSize, height: buttonSize)
                                .contentShape(Rectangle())
                        }
                        
                        Button(action: {
                            // 显示播放列表
                            withAnimation {
                                showPlayQueue.toggle()
                            }
                        }) {
                            Image(systemName: "list.bullet")
                                    .font(.system(size: 24))
                                .foregroundColor(.white.opacity(0.7))
                                    .frame(width: buttonSize, height: buttonSize)
                                .contentShape(Rectangle())
                        }
                        
                        Button(action: {
                            // 显示定时播放选项
                            withAnimation {
                                showSleepTimer.toggle()
                            }
                        }) {
                            ZStack {
                                Image(systemName: "clock")
                                        .font(.system(size: 24))
                                    .foregroundColor(musicPlayer.isSleepTimerActive ? .blue : .white.opacity(0.7))
                                        .frame(width: buttonSize, height: buttonSize)
                                
                                // 显示定时器状态
                                if musicPlayer.isSleepTimerActive {
                                    Text(musicPlayer.formattedSleepTimerRemaining())
                                        .font(.system(size: 10))
                                        .foregroundColor(.white)
                                        .padding(2)
                                        .background(Color.blue.opacity(0.7))
                                        .cornerRadius(4)
                                            .offset(y: 18)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        
                        Button(action: {
                            // 分享当前歌曲
                            directShareSong()
                        }) {
                            Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 24))
                                .foregroundColor(.white.opacity(0.7))
                                    .frame(width: buttonSize, height: buttonSize)
                                .contentShape(Rectangle())
                        }
                    }
                        .padding(.horizontal, 20)
                }
                    .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? geometry.safeAreaInsets.bottom + 10 : 30)
                .padding(.horizontal)
            }
            
            // 定时播放设置面板
            if showSleepTimer {
                VStack {
                    Spacer()
                    
                    VStack(spacing: 20) {
                        Text("定时播放")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text("选择播放停止时间")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                        
                        // 使用ScrollView实现可滑动的时间选项
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 15) {
                                // 播放完当前歌曲选项
                                Button(action: {
                                    // 设置播放完当前歌曲后停止
                                    musicPlayer.setSleepAfterCurrentSong()
                                    withAnimation {
                                        showSleepTimer = false
                                    }
                                }) {
                                    VStack {
                                        Image(systemName: "music.note.list")
                                            .font(.system(size: 20))
                                            .foregroundColor(.white)
                                            .padding(.bottom, 4)
                                        
                                        Text("播完本曲")
                                            .foregroundColor(.white)
                                            .font(.system(size: 13))
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 8)
                                    .frame(width: 100, height: 80)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(
                                                musicPlayer.isSleepAfterCurrentSong
                                                ? Color.blue.opacity(0.7)
                                                : Color.white.opacity(0.2)
                                            )
                                    )
                                }
                                
                                ForEach(sleepTimerOptions, id: \.self) { minutes in
                                    Button(action: {
                                        // 设置定时器
                                        musicPlayer.setSleepTimer(minutes: minutes)
                                        withAnimation {
                                            showSleepTimer = false
                                        }
                                    }) {
                                        VStack {
                                            Image(systemName: "clock")
                                                .font(.system(size: 20))
                                                .foregroundColor(.white)
                                                .padding(.bottom, 4)
                                            
                                            Text("\(minutes)分钟")
                                                .foregroundColor(.white)
                                                .font(.system(size: 13))
                                        }
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 8)
                                        .frame(width: 100, height: 80)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(
                                                    (musicPlayer.isSleepTimerActive && Int(musicPlayer.sleepTimerRemaining / 60) == minutes)
                                                    ? Color.blue.opacity(0.7)
                                                    : Color.white.opacity(0.2)
                                                )
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        // 如果定时器正在运行，显示当前状态
                        if musicPlayer.isSleepTimerActive || musicPlayer.isSleepAfterCurrentSong {
                            VStack(spacing: 10) {
                                if musicPlayer.isSleepTimerActive {
                                    Text("剩余时间: \(musicPlayer.formattedSleepTimerRemaining())")
                                        .foregroundColor(.white)
                                        .font(.system(size: 18, weight: .medium))
                                } else if musicPlayer.isSleepAfterCurrentSong {
                                    Text("将在本曲播放完毕后停止")
                                        .foregroundColor(.white)
                                        .font(.system(size: 16, weight: .medium))
                                }
                                
                                Button(action: {
                                    musicPlayer.cancelSleepTimer()
                                }) {
                                    Text("取消定时")
                                        .foregroundColor(.red)
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 20)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.red, lineWidth: 1)
                                        )
                                }
                            }
                            .padding(.top, 15)
                        }
                        
                        Button(action: {
                            withAnimation {
                                showSleepTimer = false
                            }
                        }) {
                            Text("关闭")
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.vertical, 10)
                                .padding(.horizontal, 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.1))
                                )
                        }
                        .padding(.top, 15)
                    }
                    .padding(.vertical, 25)
                    .padding(.horizontal, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.black.opacity(0.8))
                            .shadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: 2)
                    )
                    .padding(.horizontal, 20)
                        .padding(.bottom, geometry.safeAreaInsets.bottom + 10)
                }
                .zIndex(2)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: showSleepTimer)
                }
            }
        }
        .onAppear {
            isPlaying = musicPlayer.isPlaying
            loadCurrentSongLyrics()
        }
        .onReceive(musicPlayer.$isPlaying) { playing in
            isPlaying = playing
        }
        .onReceive(musicPlayer.$currentTime) { time in
            updateCurrentLyricIndex(for: time)
        }
        .onReceive(musicPlayer.$currentSong) { song in
            currentSong = song
            loadCurrentSongLyrics()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CurrentSongChanged"))) { notification in
            // 监听歌曲变化通知，确保在自动播放下一首时歌词也能正确更新
            if let song = notification.userInfo?["song"] as? Song {
                DispatchQueue.main.async {
                    self.currentSong = song
                    // 强制清空当前歌词状态
                    self.parsedLyrics = []
                    self.currentLyricIndex = nil
                    self.lyricsLoaded = false
                    // 重新加载歌词
                    self.loadCurrentSongLyrics()
                    print("收到歌曲变化通知，重新加载歌词: \(song.title)")
                }
            }
        }
    }
    
    // 跳转到特定歌词处开始播放
    private func seekToLyric(at index: Int) {
        guard index >= 0 && index < parsedLyrics.count else { return }
        
        let targetTime = parsedLyrics[index].timeTag
        musicPlayer.seek(to: targetTime)
        
        // 如果当前暂停中，自动开始播放
        if !isPlaying {
            musicPlayer.resume()
        }
        
        // 添加轻微的触觉反馈
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    // 格式化时间
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // 加载当前歌曲歌词
    private func loadCurrentSongLyrics() {
        guard let song = musicPlayer.currentSong else {
            parsedLyrics = []
            currentLyricIndex = nil
            lyricsLoaded = true
            return
        }
        
        print("【歌词加载】开始加载歌曲歌词: \(song.title) - \(song.artist)")
        
        lyricsLoaded = false
        
        // 先清空当前歌词
        parsedLyrics = []
        currentLyricIndex = nil
        
        let manager = musicFileManager
        
        if let lyrics = song.lyrics, !lyrics.isEmpty {
            // 使用本地歌词
            parsedLyrics = manager.parseLyrics(from: lyrics)
            lyricsLoaded = true
        } else if let lyricsURL = song.lyricsURL {
            // 从URL获取歌词
            manager.fetchLyrics(from: lyricsURL) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let lyrics):
                        self.parsedLyrics = manager.parseLyrics(from: lyrics)
                    case .failure(let error):
                        print("获取歌词失败: \(error)")
                        // 如果从URL获取失败且开启了自动获取歌词，尝试从API获取
                        if UserSettings.shared.autoFetchLyrics {
                            self.fetchLyricsFromAPI()
                        } else {
                            self.lyricsLoaded = true
                        }
                    }
                    
                    self.lyricsLoaded = true
                }
            }
        } else {
            // 在使用API获取歌词前，先检查Lyrics目录中是否有匹配的歌词文件
            if let lyricsFromDirectory = musicFileManager.findLyricsInDirectoryFor(song) {
                // 找到匹配的歌词文件
                parsedLyrics = manager.parseLyrics(from: lyricsFromDirectory)
                
                // 更新歌曲的歌词属性
                var updatedSong = song
                updatedSong.lyrics = lyricsFromDirectory
                
                // 通知音乐库更新歌曲
                MusicLibrary.shared.updateSong(updatedSong)
                
                print("从Lyrics目录找到匹配的歌词文件")
                lyricsLoaded = true
            }
            // 如果目录中没有找到匹配的歌词，且开启了自动获取歌词，尝试从API获取
            else if UserSettings.shared.autoFetchLyrics {
                fetchLyricsFromAPI()
            } else {
                // 如果没有开启自动获取歌词，直接标记加载完成
                print("未开启自动获取歌词，跳过API获取")
                lyricsLoaded = true
            }
        }
    }
    
    // 从API获取歌词
    private func fetchLyricsFromAPI() {
        guard let song = currentSong else { return }
        
        print("尝试从API获取歌词: \(song.title)")
        
        musicFileManager.fetchLyricsFromAPI(for: song) { lyricsString in
            DispatchQueue.main.async {
                if let lyrics = lyricsString {
                    // 获取到歌词后，解析并显示
                    self.parsedLyrics = self.musicFileManager.parseLyrics(from: lyrics)
                    print("成功从API获取并解析歌词，共\(self.parsedLyrics.count)行")
                    
                    // 更新当前显示的歌词
                    self.updateCurrentLyricIndex(for: self.musicPlayer.currentTime)
                    
                    // 显式保存歌词到文件系统，确保歌词永久保存
                    if let currentSong = self.currentSong {
                        // 创建一个歌曲的副本以进行更新
                        var updatedSong = currentSong
                        updatedSong.lyrics = lyrics
                        
                        // 保存歌词到文件
                        self.musicFileManager.saveLyrics(lyrics, for: updatedSong)
                        print("已显式保存歌词到文件系统")
                    }
                } else {
                    print("从API获取歌词失败")
                }
                
                self.lyricsLoaded = true
            }
        }
    }
    
    private func updateCurrentLyricIndex(for time: TimeInterval) {
        if parsedLyrics.isEmpty { return }
        
        let manager = musicFileManager
        let newIndex = manager.getCurrentLyricIndex(lines: parsedLyrics, currentTime: time)
        
        if currentLyricIndex != newIndex {
            currentLyricIndex = newIndex
            
            // 当歌词索引变化时，滚动到当前歌词
            if showLyrics, let index = currentLyricIndex, let proxy = scrollProxy {
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
    }
    
    // 计算实际的歌词索引（处理越界情况）
    private func calculateIndex(_ index: Int) -> Int? {
        if parsedLyrics.isEmpty { return nil }
        return index
    }
    
    // 根据播放模式返回对应的图标
    private var playModeIcon: String {
        switch musicPlayer.playMode {
        case .normal:
            return "arrow.right"
        case .repeatAll:
            return "repeat"
        case .repeatOne:
            return "repeat.1"
        case .shuffle:
            return "shuffle"
        }
    }
    
    // 判断是否是激活的播放模式（非普通模式）
    private var isActivePlayMode: Bool {
        musicPlayer.playMode != .normal
    }
    
    // 使用直接方法分享歌曲
    private func directShareSong() {
        guard let song = currentSong else { return }
        
        print("播放详情-开始分享歌曲: \(song.title)")
        
        // 准备分享内容
        var itemsToShare: [Any] = []
        let shareText = "\(song.title) - \(song.artist)"
        itemsToShare.append(shareText)
        
        // 尝试获取文件URL
        if let url = song.fileURL, FileManager.default.fileExists(atPath: url.path) {
            print("播放详情-找到音乐文件：\(url.path)")
            
            // 直接使用文件URL，不调用getShareableFileURL
            let secureAccess = url.startAccessingSecurityScopedResource()
            print("播放详情-获取安全访问权限：\(secureAccess)")
            
            // 添加URL到分享项目
            itemsToShare.append(url)
            
            // 创建分享控制器
            let activityController = UIActivityViewController(
                activityItems: itemsToShare,
                applicationActivities: nil
            )
            
            // 排除某些活动类型
            activityController.excludedActivityTypes = [
                .addToReadingList,
                .assignToContact,
                .openInIBooks
            ]
            
            // 设置完成回调，确保资源访问被释放
            activityController.completionWithItemsHandler = { (_, _, _, _) in
                if secureAccess {
                    url.stopAccessingSecurityScopedResource()
                    print("播放详情-停止文件安全访问")
                }
            }
            
            // 获取当前窗口进行呈现
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                var rootVC: UIViewController?
                
                // 尝试多种方式获取视图控制器
                if let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {
                    rootVC = keyWindow.rootViewController
                } else if let window = windowScene.windows.first {
                    rootVC = window.rootViewController
                }
                
                if let rootVC = rootVC {
                    // 查找最顶层的控制器
                    var topVC = rootVC
                    while let presentedVC = topVC.presentedViewController {
                        topVC = presentedVC
                    }
                    
                    print("播放详情-找到顶层视图控制器，准备显示分享界面")
                    
                    // 在iPad上，我们需要设置弹出源以避免崩溃
                    if let popoverController = activityController.popoverPresentationController {
                        popoverController.sourceView = topVC.view
                        popoverController.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
                        popoverController.permittedArrowDirections = []
                    }
                    
                    // 呈现分享控制器
                    DispatchQueue.main.async {
                        topVC.present(activityController, animated: true) {
                            print("播放详情-分享界面已呈现")
                        }
                    }
                } else {
                    print("播放详情-无法获取视图控制器")
                    if secureAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
            } else {
                print("播放详情-无法获取窗口场景")
                if secureAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
        } else {
            // 如果无法获取文件URL，仅分享文本
            print("播放详情-未找到音乐文件，仅分享文本")
            let activityController = UIActivityViewController(
                activityItems: [shareText],
                applicationActivities: nil
            )
            
            // 尝试显示分享界面
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootVC = window.rootViewController {
                var topVC = rootVC
                while let presentedVC = topVC.presentedViewController {
                    topVC = presentedVC
                }
                
                // 在iPad上的特殊处理
                if let popoverController = activityController.popoverPresentationController {
                    popoverController.sourceView = topVC.view
                    popoverController.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
                    popoverController.permittedArrowDirections = []
                }
                
                DispatchQueue.main.async {
                    topVC.present(activityController, animated: true) {
                        print("播放详情-文本分享界面已呈现")
                    }
                }
            }
        }
    }
}

struct PlayerDetailView_Previews: PreviewProvider {
    static var previews: some View {
        PlayerDetailView(isPresented: .constant(true))
    }
} 