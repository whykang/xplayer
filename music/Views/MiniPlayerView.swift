import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject private var musicPlayer = MusicPlayer.shared
    @State private var showFullPlayer = false
    @State private var isDragging = false
    @State private var dragProgress: Double = 0.0
    
    var body: some View {
        if let currentSong = musicPlayer.currentSong {
            VStack(spacing: 0) {
                // 迷你播放器内容
                HStack(spacing: 15) {
                    // 歌曲封面 - 美化为圆角矩形
                    AlbumArtworkView(song: currentSong, size: 45)
                        .cornerRadius(6)
                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                        .padding(.leading, 8)
                    
                    // 歌曲信息
                    VStack(alignment: .leading, spacing: 2) {
                        Text(currentSong.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        
                        HStack(spacing: 4) {
                            Text(currentSong.artist)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                
                            // 添加时间指示
                            if !isDragging {
                                Text("· \(formatTime(musicPlayer.currentTime))/\(formatTime(currentSong.duration))")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // 控制按钮组
                    HStack(spacing: 18) {
                        // 上一首按钮
                        Button(action: {
                            musicPlayer.playPrevious()
                        }) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                        }
                        
                        // 播放/暂停按钮 - 美化为圆形背景
                        Button(action: {
                            musicPlayer.playPause()
                        }) {
                            Image(systemName: musicPlayer.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(Color.accentColor)
                                .clipShape(Circle())
                        }
                        
                        // 下一首按钮
                        Button(action: {
                            musicPlayer.playNext()
                        }) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(.trailing, 12)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 6)
                .onTapGesture {
                    showFullPlayer = true
                }
                
                // 可滑动的播放进度条 - 移到底部
                ZStack(alignment: .bottom) {
                    // 进度条背景
                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 4)
                    
                    // 实际进度
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.blue, Color.accentColor]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, min(geometry.size.width, geometry.size.width * (isDragging ? dragProgress : musicPlayer.progressPercentage))))
                    }
                    .frame(height: 4)
                    
                    // 拖动区域 - 扩大触摸范围
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(height: 30)
                        .offset(y: -15) // 将触摸区域上移，使其覆盖进度条
                        .gesture(
                            DragGesture(minimumDistance: 5) // 设置最小拖动距离，防止误点
                                .onChanged { value in
                                    let width = UIScreen.main.bounds.width
                                    let percentage = min(1, max(0, value.location.x / width))
                                    dragProgress = percentage
                                    isDragging = true
                                }
                                .onEnded { value in
                                    let width = UIScreen.main.bounds.width
                                    let percentage = min(1, max(0, value.location.x / width))
                                    let newTime = currentSong.duration * percentage
                                    
                                    // 先将拖动标志设为false
                                    isDragging = false
                                    
                                    // 然后应用新的播放位置
                                    DispatchQueue.main.async {
                                        musicPlayer.seek(to: newTime)
                                    }
                                }
                        )
                    
                    // 拖动手柄 - 始终显示，拖动时放大
                    GeometryReader { geometry in
                        Circle()
                            .fill(Color.white)
                            .frame(width: isDragging ? 16 : 10, height: isDragging ? 16 : 10)
                            .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                            .position(
                                x: geometry.size.width * (isDragging ? dragProgress : musicPlayer.progressPercentage),
                                y: 2
                            )
                            .animation(.spring(response: 0.2), value: isDragging)
                    }
                    .frame(height: 4)
                }
                .frame(height: 20)
                .padding(.bottom, 8) // 增加底部边距
            }
            .background(
                Color(UIColor.systemBackground)
                    .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: -2)
                    .blur(radius: 0.5)
            )
            .padding(.bottom, 8) // 增加与TabBar的距离
            .fullScreenCover(isPresented: $showFullPlayer) {
                PlayerDetailView(isPresented: $showFullPlayer)
            }
        } else {
            EmptyView()
        }
    }
    
    // 格式化时间显示
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct MiniPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Spacer()
            MiniPlayerView()
                .padding(.bottom, 49)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .edgesIgnoringSafeArea(.all)
    }
} 