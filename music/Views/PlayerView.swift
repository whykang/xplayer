import SwiftUI

struct PlayerView: View {
    @ObservedObject var musicPlayer: MusicPlayer
    @State private var showPlayerDetail = false
    @State private var isDragging = false
    @State private var localSliderPosition: Double = 0
    
    var body: some View {
        VStack(spacing: 0) {
            if let song = musicPlayer.currentSong {
                HStack(spacing: 12) {
                    // 专辑封面
                    AlbumArtworkView(song: song, size: 50)
                        .cornerRadius(6)
                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                    
                    // 歌曲信息
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(song.title)
                                .font(.system(size: 15, weight: .medium))
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
                        }
                        
                        Text(song.artist)
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // 播放控制
                    HStack(spacing: 16) {
                        // 循环播放按钮
                        Button(action: {
                            musicPlayer.togglePlayMode()
                        }) {
                            Image(systemName: playModeIcon)
                                .font(.system(size: 16))
                                .foregroundColor(playModeColor)
                                .frame(width: 30, height: 30)
                        }
                        
                        // 上一首按钮
                        Button(action: {
                            musicPlayer.playPrevious()
                        }) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                                .frame(width: 30, height: 30)
                        }
                        
                        // 播放/暂停按钮
                        Button(action: {
                            if musicPlayer.isPlaying {
                                musicPlayer.pause()
                            } else {
                                musicPlayer.resume()
                            }
                        }) {
                            Image(systemName: musicPlayer.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.primary)
                                .frame(width: 34, height: 34)
                        }
                        
                        // 下一首按钮
                        Button(action: {
                            musicPlayer.playNext()
                        }) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                                .frame(width: 30, height: 30)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                
                // 时间显示与进度条
                VStack(spacing: 4) {
                    // 时间显示
                    HStack {
                        Text(formatTime(musicPlayer.currentTime))
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                        
                        Spacer()
                        
                        Text(formatTime(musicPlayer.duration))
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 16)
                    
                    // 进度条
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // 背景条
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 6)
                            
                            // 进度条
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.blue)
                                .frame(width: geometry.size.width * (isDragging ? localSliderPosition : musicPlayer.progressPercentage), height: 6)
                            
                            // 滑块圆点
                            Circle()
                                .fill(Color.white)
                                .frame(width: 12, height: 12)
                                .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 0)
                                .offset(x: geometry.size.width * (isDragging ? localSliderPosition : musicPlayer.progressPercentage) - 6)
                                .opacity(isDragging ? 1 : 0.8)
                        }
                        // 触摸区域增大
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    isDragging = true
                                    localSliderPosition = min(max(0, value.location.x / geometry.size.width), 1)
                                }
                                .onEnded { _ in
                                    musicPlayer.seek(to: musicPlayer.duration * localSliderPosition)
                                    isDragging = false
                                }
                        )
                    }
                    .frame(height: 30)
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 4)
            } else {
                HStack {
                    Text("暂无播放")
                        .foregroundColor(.gray)
                        .padding()
                    Spacer()
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 0)
                .fill(Color(.systemGroupedBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: -1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if musicPlayer.currentSong != nil {
                showPlayerDetail = true
            }
        }
        .fullScreenCover(isPresented: $showPlayerDetail) {
            PlayerDetailView(musicPlayer: musicPlayer, musicLibrary: MusicLibrary.shared, musicFileManager: MusicFileManager.shared)
                .edgesIgnoringSafeArea(.all)
        }
        .onAppear {
            localSliderPosition = musicPlayer.progressPercentage
        }
        .onReceive(musicPlayer.$currentTime) { _ in
            if !isDragging {
                localSliderPosition = musicPlayer.progressPercentage
            }
        }
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
    
    // 根据播放模式返回对应的颜色
    private var playModeColor: Color {
        switch musicPlayer.playMode {
        case .normal:
            return .primary
        case .repeatAll, .repeatOne, .shuffle:
            return .blue
        }
    }
    
    // 格式化时间为 mm:ss 格式
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct AlbumArtworkView: View {
    let song: Song
    let size: CGFloat
    
    var body: some View {
        Group {
            if let coverImagePath = song.coverImagePath, let image = loadImage(from: coverImagePath) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
            } else if let artworkURL = song.artworkURL {
                AsyncImage(url: artworkURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        Color.gray.opacity(0.3)
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.4))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: size, height: size)
            } else {
                ZStack {
                    Color.gray.opacity(0.3)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4))
                        .foregroundColor(.white)
                }
                .frame(width: size, height: size)
            }
        }
    }
    
    private func loadImage(from path: String) -> UIImage? {
        UIImage(contentsOfFile: path)
    }
}

struct PlayerView_Previews: PreviewProvider {
    static var previews: some View {
        PlayerView(musicPlayer: MusicPlayer.shared)
            .previewLayout(.sizeThatFits)
    }
} 