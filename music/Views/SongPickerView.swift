import SwiftUI

struct SongPickerView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var musicLibrary: MusicLibrary
    var playlist: Playlist?
    var album: Album?
    @State private var searchText = ""
    @State private var selectedSongs: Set<UUID> = []
    @State private var isMultiSelecting = false

    var filteredSongs: [Song] {
        if searchText.isEmpty {
            return musicLibrary.songs
        } else {
            return musicLibrary.songs.filter { song in
                song.title.localizedCaseInsensitiveContains(searchText) ||
                song.artist.localizedCaseInsensitiveContains(searchText) ||
                song.album.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                SearchBar(text: $searchText, placeholder: "搜索歌曲...")
                
                // 多选操作栏
                if isMultiSelecting {
                    HStack {
                        Text("已选择\(selectedSongs.count)首歌曲")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Button(action: {
                            isMultiSelecting = false
                            selectedSongs.removeAll()
                        }) {
                            Text("取消")
                                .foregroundColor(.blue)
                        }
                        
                        Button(action: {
                            addSelectedSongsToPlaylist()
                        }) {
                            Text("添加")
                                .bold()
                                .foregroundColor(.blue)
                        }
                        .disabled(selectedSongs.isEmpty)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(UIColor.secondarySystemBackground))
                }
                
                List {
                    ForEach(filteredSongs) { song in
                        if isMultiSelecting {
                            SongPickerRow(
                                song: song,
                                isSelected: selectedSongs.contains(song.id),
                                onToggle: { toggleSongSelection(song) }
                            )
                            .opacity(songIsInPlaylist(song: song) ? 0.5 : 1.0)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        } else {
                            SongRow(song: song, disablePlayOnTap: true, onRowTap: { selectSong(song) })
                                .contentShape(Rectangle())
                                .opacity(songIsInPlaylist(song: song) ? 0.5 : 1.0)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
            .navigationTitle("添加歌曲")
            .navigationBarItems(
                leading: Button(action: {
                    isMultiSelecting.toggle()
                    if !isMultiSelecting {
                        selectedSongs.removeAll()
                    }
                }) {
                    Text(isMultiSelecting ? "单选" : "多选")
                },
                trailing: Button("完成") {
                    // 如果在多选模式下点击完成，先添加选中的歌曲
                    if isMultiSelecting && !selectedSongs.isEmpty {
                        // 获取所选歌曲并添加到歌单
                        if let playlist = playlist {
                            let songsToAdd = filteredSongs.filter { selectedSongs.contains($0.id) && !playlist.songs.contains($0) }
                            
                            // 添加歌曲到歌单
                            for song in songsToAdd {
                                musicLibrary.addSongToPlaylist(song: song, playlist: playlist)
                            }
                            
                            // 只有成功添加了歌曲才显示简单提示
                            if !songsToAdd.isEmpty {
                                // 使用无需用户确认的提示方式，直接关闭选择界面
                                showSimpleToast(message: "已添加\(songsToAdd.count)首歌曲到'\(playlist.name)'")
                            }
                        }
                    }
                    // 无论是否添加了歌曲，都关闭界面
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
    
    private func selectSong(_ song: Song) {
        if let playlist = playlist {
            if !playlist.songs.contains(song) {
                musicLibrary.addSongToPlaylist(song: song, playlist: playlist)
                
                // 显示简单提示并直接关闭界面
                showSimpleToast(message: "已添加歌曲到'\(playlist.name)'")
                presentationMode.wrappedValue.dismiss()
            } else {
                // 提示该歌曲已经在歌单中
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
            }
        }
    }
    
    private func toggleSongSelection(_ song: Song) {
        if selectedSongs.contains(song.id) {
            selectedSongs.remove(song.id)
        } else {
            // 只选择尚未添加到歌单的歌曲
            if !songIsInPlaylist(song: song) {
                selectedSongs.insert(song.id)
            } else {
                // 提示该歌曲已经在歌单中
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
            }
        }
    }
    
    private func addSelectedSongsToPlaylist() {
        guard let playlist = playlist, !selectedSongs.isEmpty else { return }
        
        // 获取选中的歌曲
        let songsToAdd = filteredSongs.filter { selectedSongs.contains($0.id) && !playlist.songs.contains($0) }
        
        // 添加歌曲到歌单
        for song in songsToAdd {
            musicLibrary.addSongToPlaylist(song: song, playlist: playlist)
        }
        
        // 显示添加成功的提示
        if !songsToAdd.isEmpty {
            showSimpleToast(message: "已添加\(songsToAdd.count)首歌曲到'\(playlist.name)'")
            presentationMode.wrappedValue.dismiss()
        }
        
        // 清除选择状态
        isMultiSelecting = false
        selectedSongs.removeAll()
    }
    
    private func songIsInPlaylist(song: Song) -> Bool {
        playlist?.songs.contains(song) ?? false
    }
    
    // 显示简单的无需用户交互的提示
    private func showSimpleToast(message: String) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.keyWindow?.rootViewController {
            
            let toastContainer = UIView(frame: CGRect(x: 0, y: 0, width: 280, height: 50))
            toastContainer.backgroundColor = UIColor.black.withAlphaComponent(0.7)
            toastContainer.layer.cornerRadius = 10
            
            let messageLabel = UILabel(frame: CGRect(x: 0, y: 0, width: 280, height: 50))
            messageLabel.textAlignment = .center
            messageLabel.textColor = .white
            messageLabel.font = UIFont.systemFont(ofSize: 14)
            messageLabel.text = message
            
            toastContainer.addSubview(messageLabel)
            rootViewController.view.addSubview(toastContainer)
            
            toastContainer.center = rootViewController.view.center
            toastContainer.alpha = 0
            
            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn, animations: {
                toastContainer.alpha = 1
            }, completion: { _ in
                UIView.animate(withDuration: 0.2, delay: 1.5, options: .curveEaseOut, animations: {
                    toastContainer.alpha = 0
                }, completion: { _ in
                    toastContainer.removeFromSuperview()
                })
            })
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    var placeholder: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField(placeholder, text: $text)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            
            if !text.isEmpty {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
        .padding(.horizontal)
    }
}

// 空状态视图
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("没有可添加的歌曲")
                .font(.title3)
                .foregroundColor(.gray)
            
            Text("所有歌曲已在列表中，或歌曲库为空")
                .font(.subheadline)
                .foregroundColor(.gray.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
}

// 歌曲选择行
struct SongPickerRow: View {
    let song: Song
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray)
                    .font(.title3)
            }
            
            // 封面图
            AlbumArtworkView(song: song, size: 45)
                .cornerRadius(6)
            
            // 歌曲信息
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.system(size: 16))
                    .lineLimit(1)
                
                Text(song.artist)
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // 显示时长
            Text(formatDuration(song.duration))
                .font(.system(size: 14))
                .foregroundColor(.gray)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
        .padding(.vertical, 4)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
} 