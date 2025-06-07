import SwiftUI
import UIKit

// 简化的播放队列视图 - 显示当前播放列表
struct SimplePlayQueueView: View {
    @ObservedObject var musicPlayer: MusicPlayer
    @Binding var isShowing: Bool
    @State private var currentPlaylist: [Song] = []
    @State private var refreshTimer: Timer? = nil
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // 半透明背景覆盖整个屏幕
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut) {
                            isShowing = false
                        }
                    }
                
                // 播放列表内容
                PlayQueueContentView(
                    geometry: geometry,
                    musicPlayer: musicPlayer,
                    isShowing: $isShowing,
                    currentPlaylist: $currentPlaylist
                )
                .frame(height: min(600, geometry.size.height * 0.7))
                .background(BackgroundBlurView())
                .offset(y: isShowing ? 0 : geometry.size.height)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isShowing)
            }
        }
        .onAppear {
            refreshPlaylistData()
            setupRefreshTimer()
        }
        .onDisappear {
            invalidateTimer()
        }
        .onChange(of: isShowing) { newValue in
            if newValue {
                refreshPlaylistData()
                setupRefreshTimer()
            } else {
                invalidateTimer()
            }
        }
    }
    
    // 刷新播放列表数据
    private func refreshPlaylistData() {
        self.currentPlaylist = musicPlayer.getCurrentPlaylist()
    }
    
    // 设置刷新计时器
    private func setupRefreshTimer() {
        // 先取消已有的计时器
        invalidateTimer()
        
        // 创建新的计时器，每秒刷新一次播放列表数据
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            refreshPlaylistData()
        }
    }
    
    // 停止计时器
    private func invalidateTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

// 背景模糊视图
struct BackgroundBlurView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
            
            // 使用UIViewRepresentable
            BackdropBlurView(style: .systemMaterialDark)
                .opacity(0.95)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: Color.black.opacity(0.4), radius: 15)
    }
}

// 内容视图
struct PlayQueueContentView: View {
    let geometry: GeometryProxy
    let musicPlayer: MusicPlayer
    @Binding var isShowing: Bool
    @Binding var currentPlaylist: [Song]
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部栏
            HeaderView(
                isShowing: $isShowing,
                currentPlaylist: $currentPlaylist,
                playlistIsEmpty: currentPlaylist.isEmpty,
                musicPlayer: musicPlayer
            )
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            // 内容区域 - 显示播放列表
            QueueContentView(
                musicPlayer: musicPlayer,
                currentPlaylist: $currentPlaylist,
                geometry: geometry
            )
        }
    }
}

// 顶部栏视图
struct HeaderView: View {
    @Binding var isShowing: Bool
    @Binding var currentPlaylist: [Song]
    let playlistIsEmpty: Bool
    let musicPlayer: MusicPlayer
    
    var body: some View {
        HStack {
            Text("播放列表")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Spacer()
            
            // 清空播放列表按钮
            Button(action: {
                musicPlayer.clearPlaylist()
                currentPlaylist = []
            }) {
                Label("清空", systemImage: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.red.opacity(0.5))
                    )
            }
            .disabled(playlistIsEmpty)
            .opacity(playlistIsEmpty ? 0.5 : 1)
            .padding(.trailing, 8)
            
            Button(action: {
                withAnimation(.easeInOut) {
                    isShowing = false
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 15)
        .padding(.bottom, 10)
    }
}

// 队列内容视图
struct QueueContentView: View {
    let musicPlayer: MusicPlayer
    @Binding var currentPlaylist: [Song]
    let geometry: GeometryProxy
    
    var body: some View {
        if currentPlaylist.isEmpty {
            EmptyQueueView(geometry: geometry)
        } else {
            QueueItemsView(
                musicPlayer: musicPlayer,
                currentPlaylist: $currentPlaylist,
                geometry: geometry
            )
        }
    }
}

// 空队列视图
struct EmptyQueueView: View {
    let geometry: GeometryProxy
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.4))
                .padding(.top, 40)
            
            Text("播放列表为空")
                .font(.headline)
                .foregroundColor(.white.opacity(0.7))
            
            Text("从歌曲列表中添加歌曲到播放列表")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(height: min(500, geometry.size.height * 0.6))
    }
}

// 队列项目视图
struct QueueItemsView: View {
    let musicPlayer: MusicPlayer
    @Binding var currentPlaylist: [Song]
    let geometry: GeometryProxy
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                ForEach(Array(currentPlaylist.enumerated()), id: \.element.id) { index, song in
                    let isCurrentlyPlaying = musicPlayer.currentSong?.id.uuidString == song.id.uuidString && musicPlayer.isPlaying
                    
                    SimplePlayQueueRow(
                        song: song,
                        isPlaying: isCurrentlyPlaying,
                        onPlay: {
                            if isCurrentlyPlaying {
                                // 如果是当前播放的歌曲，就暂停
                                musicPlayer.pause()
                            } else if musicPlayer.currentSong?.id.uuidString == song.id.uuidString {
                                // 如果是当前歌曲但已暂停，就恢复播放
                                musicPlayer.resume()
                            } else {
                                // 否则播放播放列表中的这首歌曲
                                musicPlayer.playFromPlaylist(at: index)
                            }
                        },
                        onRemove: {
                            // 从播放列表中移除歌曲
                            musicPlayer.removeFromCurrentPlaylist(at: index)
                            // 更新本地数据
                            DispatchQueue.main.async {
                                self.currentPlaylist = musicPlayer.getCurrentPlaylist()
                            }
                        }
                    )
                    .padding(.horizontal, 15)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isCurrentlyPlaying ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
                            .padding(.horizontal, 8)
                    )
                }
            }
            .padding(.vertical, 8)
        }
        .frame(height: min(500, geometry.size.height * 0.6))
    }
}

// UIKit 模糊效果包装器
struct BackdropBlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style = .systemMaterialDark
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

// 播放队列行视图 - 更现代的设计
struct SimplePlayQueueRow: View {
    let song: Song
    let isPlaying: Bool
    let onPlay: () -> Void
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // 封面图片
            CoverImageView(artworkURL: song.artworkURL)
            
            // 歌曲信息
            SongInfoView(title: song.title, artist: song.artist, fileFormat: song.fileFormat)
            
            Spacer()
            
            // 控制按钮组
            ControlButtonsView(
                isPlaying: isPlaying,
                song: song,
                onPlay: onPlay,
                onRemove: onRemove
            )
        }
        .padding(.vertical, 4)
    }
}

// 封面图片视图
struct CoverImageView: View {
    let artworkURL: URL?
    
    var body: some View {
        if let artworkURL = artworkURL {
            AsyncImage(url: artworkURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 45, height: 45)
                    .cornerRadius(8)
            } placeholder: {
                EmptyCoverPlaceholder()
            }
        } else {
            EmptyCoverPlaceholder()
        }
    }
}

// 空封面占位符
struct EmptyCoverPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.2))
            .frame(width: 45, height: 45)
            .overlay(
                Image(systemName: "music.note")
                    .foregroundColor(.white)
            )
    }
}

// 歌曲信息视图
struct SongInfoView: View {
    let title: String
    let artist: String
    var fileFormat: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                // 显示音频文件格式
                if !fileFormat.isEmpty {
                    Text(fileFormat)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(3)
                }
            }
            
            Text(artist)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
        }
    }
}

// 控制按钮视图
struct ControlButtonsView: View {
    let isPlaying: Bool
    let song: Song
    let onPlay: () -> Void
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            Button(action: onPlay) {
                Circle()
                    .fill(isPlaying ? Color.purple.opacity(0.8) : Color.blue.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    )
            }
            
            Button(action: onRemove) {
                Circle()
                    .fill(Color.red.opacity(0.5))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "xmark")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    )
            }
        }
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
} 