import SwiftUI

// 单曲歌单选择视图 - 重新实现以解决命名冲突
struct SingleSongPlaylistSelectionView: View {
    let song: Song
    @ObservedObject var musicLibrary = MusicLibrary.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingNameInput = false
    @State private var newPlaylistName = ""
    @State private var showingDuplicateAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            List {
                ForEach(musicLibrary.playlists) { playlist in
                    PlaylistItemRow(playlist: playlist, song: song) {
                        // 添加歌曲到歌单
                        musicLibrary.addSongToPlaylist(song: song, playlist: playlist)
                        dismiss()
                    }
                }
                
                // 创建新播放列表的选项
                Button(action: {
                    // 显示创建歌单对话框
                    showingNameInput = true
                }) {
                    Label("创建新歌单", systemImage: "plus.circle")
                        .foregroundColor(.blue)
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
            .alert("创建新歌单", isPresented: $showingNameInput) {
                TextField("歌单名称", text: $newPlaylistName)
                    .autocapitalization(.none)
                
                Button("取消", role: .cancel) {
                    newPlaylistName = ""
                }
                
                Button("创建") {
                    if !newPlaylistName.isEmpty {
                        // 创建新歌单并添加歌曲
                        if let newPlaylist = musicLibrary.createPlaylist(name: newPlaylistName) {
                            musicLibrary.addSongToPlaylist(song: song, playlist: newPlaylist)
                            newPlaylistName = ""
                            dismiss()
                        } else {
                            // 创建失败，可能是重名
                            errorMessage = "已存在名为\(newPlaylistName)的歌单，请使用其他名称"
                            showingDuplicateAlert = true
                        }
                    }
                }
            } message: {
                Text("请输入新歌单的名称")
            }
            .alert("无法创建歌单", isPresented: $showingDuplicateAlert) {
                Button("确定", role: .cancel) {
                    showingDuplicateAlert = false
                    // 重新显示创建歌单对话框
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showingNameInput = true
                    }
                }
            } message: {
                Text(errorMessage)

            }
        }
    }
}

// 创建一个辅助视图用于显示歌单列表项
struct PlaylistItemRow: View {
    @ObservedObject var playlist: Playlist
    let song: Song
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "music.note.list")
                    .foregroundColor(.blue)
                
                Text(playlist.name)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(playlist.songs.count)首")
                    .foregroundColor(.secondary)
                    .font(.caption)
                
                if playlist.songs.contains(where: { $0.id == song.id }) {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
        }
    }
} 

