import SwiftUI

// 多选歌单选择视图 - 重新实现以解决命名冲突
struct BatchPlaylistSelectionView: View {
    var songIds: [UUID]
    @ObservedObject var musicLibrary = MusicLibrary.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isProcessing = false
    
    var body: some View {
        NavigationView {
            ZStack {
                List {
                    ForEach(musicLibrary.playlists) { playlist in
                        BatchPlaylistRow(playlist: playlist, isDisabled: isProcessing) {
                            addSongsToPlaylist(playlist)
                        }
                    }
                }
                
                if isProcessing {
                    ProgressView("处理中...")
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(10)
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
    
    private func addSongsToPlaylist(_ playlist: Playlist) {
        isProcessing = true
        
        // 在后台处理以避免UI卡顿
        DispatchQueue.global(qos: .userInitiated).async {
            // 获取要添加的歌曲
            let songsToAdd = musicLibrary.songs.filter { songIds.contains($0.id) }
            
            // 添加歌曲到歌单
            for song in songsToAdd {
                musicLibrary.addSongToPlaylist(song: song, playlist: playlist)
            }
            
            // 在主线程关闭视图
            DispatchQueue.main.async {
                isProcessing = false
                
                // 显示成功消息并关闭
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootViewController = windowScene.keyWindow?.rootViewController {
                    let message = "已添加\(songsToAdd.count)首歌曲到'\(playlist.name)'"
                    
                    let alert = UIAlertController(title: "已添加", message: message, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
                        self.dismiss()
                    })
                    
                    rootViewController.present(alert, animated: true)
                } else {
                    self.dismiss()
                }
            }
        }
    }
}

// 批量选择歌单行
struct BatchPlaylistRow: View {
    @ObservedObject var playlist: Playlist
    let isDisabled: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(playlist.name)
                    .foregroundColor(.primary)
                Spacer()
                Text("\(playlist.songs.count)首歌曲")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
        .disabled(isDisabled)
    }
} 