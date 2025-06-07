import SwiftUI

struct SongDetailView: View {
    let song: Song
    @ObservedObject var musicPlayer = MusicPlayer.shared
    @ObservedObject var musicLibrary = MusicLibrary.shared
    @State private var showingLyrics = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 20) {
                // 专辑封面
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 250, height: 250)
                        .cornerRadius(10)
                    
                    if let artworkURL = song.artworkURL {
                        AsyncImage(url: artworkURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 250, height: 250)
                                .cornerRadius(10)
                                .clipped()
                        } placeholder: {
                            Image(systemName: "music.note")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                        }
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                    }
                }
                .shadow(radius: 5)
                .padding(.top, 20)
                
                // 歌曲信息
                VStack(spacing: 8) {
                    Text(song.title)
                        .font(.title)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    HStack {
                        Text(song.artist)
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        if !song.composer.isEmpty && song.composer != song.artist {
                            Text("·")
                                .foregroundColor(.secondary)
                            
                            Text(song.composer)
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Text(song.albumName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // 收藏按钮
                    Button(action: {
                        let isFavorite = musicLibrary.toggleFavorite(song: song)
                        // 轻微的触觉反馈
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                    }) {
                        Image(systemName: musicLibrary.isFavorite(song: song) ? "heart.fill" : "heart")
                            .font(.system(size: 24))
                            .foregroundColor(musicLibrary.isFavorite(song: song) ? .red : .gray)
                            .padding(8)
                            .contentShape(Rectangle())
                    }
                }
                .padding()
                
                // 播放控制
                HStack(spacing: 40) {
                    Button(action: {
                        musicPlayer.playPrevious()
                    }) {
                        Image(systemName: "backward.fill")
                            .font(.title)
                            .foregroundColor(.primary)
                    }
                    
                    Button(action: {
                        if musicPlayer.currentSong?.id == song.id {
                            musicPlayer.playPause()
                        } else {
                            // 获取专辑中的歌曲作为播放列表
                            let albumSongs = getAlbumSongs()
                            let songIndex = albumSongs.firstIndex(where: { $0.id == song.id }) ?? 0
                            musicPlayer.setPlaylist(songs: albumSongs, startIndex: songIndex)
                        }
                    }) {
                        if musicPlayer.isBuffering && musicPlayer.currentSong?.id == song.id {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(1.5)
                        } else {
                            Image(systemName: 
                                (musicPlayer.currentSong?.id == song.id && musicPlayer.isPlaying) ? 
                                "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.primary)
                        }
                    }
                    
                    Button(action: {
                        musicPlayer.playNext()
                    }) {
                        Image(systemName: "forward.fill")
                            .font(.title)
                            .foregroundColor(.primary)
                    }
                }
                .padding(.vertical)
                
                // 播放进度条 (当前歌曲处于播放状态时)
                if musicPlayer.currentSong?.id == song.id {
                    HStack {
                        Text(formatDuration(musicPlayer.currentTime))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(formatDuration(musicPlayer.duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 40)
                }
                
                // 歌词按钮
                if let lyrics = song.lyrics, !lyrics.isEmpty || song.lyricsURL != nil {
                    Button(action: {
                        showingLyrics = true
                    }) {
                        HStack {
                            Image(systemName: "text.quote")
                            Text("查看歌词")
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
                
                // 详细信息
                VStack(alignment: .leading, spacing: 15) {
                    DetailRow(title: "曲目编号", value: song.trackNumber != nil ? "\(song.trackNumber!)" : "未知")
                    DetailRow(title: "发行年份", value: song.year != nil ? "\(song.year!)" : "未知")
                    DetailRow(title: "流派", value: song.genre.isEmpty ? "未知" : song.genre)
                    DetailRow(title: "专辑艺术家", value: song.albumArtist.isEmpty ? "未知" : song.albumArtist)
                    DetailRow(title: "时长", value: formatDuration(song.duration))
                    
                    if !song.fileFormat.isEmpty {
                        DetailRow(title: "文件格式", value: song.fileFormat)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
            }
            .padding(.bottom, musicPlayer.currentSong != nil ? 80 : 0)
        }
        .navigationTitle("歌曲详情")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingLyrics) {
            LyricsView(song: song)
        }
    }
    
    // 获取同一专辑的所有歌曲作为播放列表
    private func getAlbumSongs() -> [Song] {
        // 查找同一专辑的歌曲
        let albumSongs = musicLibrary.songs.filter { $0.albumName == song.albumName }
        
        // 如果找到同一专辑的歌曲，以专辑顺序(曲目号)排序并返回
        if !albumSongs.isEmpty {
            return albumSongs.sorted { 
                // 按曲目编号排序，如果没有编号则保持原顺序
                if let track1 = $0.trackNumber, let track2 = $1.trackNumber {
                    return track1 < track2
                } else if $0.trackNumber != nil {
                    return true
                } else if $1.trackNumber != nil {
                    return false
                }
                return $0.title < $1.title
            }
        }
        
        // 如果找不到同一专辑的歌曲，就只播放当前歌曲
        return [song]
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct DetailRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .font(.subheadline)
            
            Spacer()
        }
    }
}

struct LyricsView: View {
    let song: Song
    @State private var lyricsText: String = ""
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack {
                    if lyricsText.isEmpty {
                        ProgressView()
                            .padding()
                    } else {
                        Text(lyricsText)
                            .font(.body)
                            .padding()
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .navigationTitle("歌词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .onAppear {
                loadLyrics()
            }
        }
    }
    
    private func loadLyrics() {
        // 先检查歌曲是否直接包含歌词
        if let lyrics = song.lyrics, !lyrics.isEmpty {
            lyricsText = lyrics
            return
        }
        
        // 否则尝试从歌词URL加载
        if let lyricsURL = song.lyricsURL {
            do {
                lyricsText = try String(contentsOf: lyricsURL, encoding: .utf8)
            } catch let error {
                lyricsText = "无法加载歌词文件：\(error.localizedDescription)"
            }
        } else {
            lyricsText = "没有歌词"
        }
    }
}

struct SongDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SongDetailView(song: Song.examples[0])
        }
    }
} 