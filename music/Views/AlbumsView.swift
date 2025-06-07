import SwiftUI

struct AlbumsView: View {
    @EnvironmentObject var musicLibrary: MusicLibrary
    @ObservedObject var musicPlayer: MusicPlayer
    @State private var searchText = ""
    @State private var isGridMode: Bool = UserDefaults.standard.bool(forKey: "albumsViewIsGridMode")
    
    // 筛选专辑
    var filteredAlbums: [Album] {
        if searchText.isEmpty {
            return musicLibrary.albums
        } else {
            let lowercasedQuery = searchText.lowercased()
            return musicLibrary.albums.filter { album in
                album.title.lowercased().contains(lowercasedQuery) ||
                album.artist.lowercased().contains(lowercasedQuery)
            }
        }
    }
    
    var body: some View {
        Group {
            if musicLibrary.albums.isEmpty {
                EmptyAlbumsView()
            } else {
                if isGridMode {
                    // 网格模式显示
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 20) {
                            ForEach(filteredAlbums) { album in
                                NavigationLink(destination: AlbumDetailView(album: album, musicPlayer: musicPlayer)) {
                                    AlbumGridItem(album: album)
                                }
                            }
                        }
                        .padding()
                        
                        // 添加底部空间，避免被播放器遮挡
                        Rectangle()
                            .frame(height: 100)
                            .foregroundColor(.clear)
                    }
                    .searchable(text: $searchText, prompt: "搜索专辑或艺术家")
                } else {
                    // 列表模式显示
                    List {
                        ForEach(filteredAlbums) { album in
                            NavigationLink(destination: AlbumDetailView(album: album, musicPlayer: musicPlayer)) {
                                AlbumRow(album: album)
                            }
                        }
                        
                        // 添加底部空间，避免被播放器遮挡
                        Rectangle()
                            .frame(height: 100)
                            .foregroundColor(.clear)
                            .listRowSeparator(.hidden)
                    }
                    .searchable(text: $searchText, prompt: "搜索专辑或艺术家")
                    .listStyle(PlainListStyle())
                }
            }
        }
        .navigationTitle("专辑")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    isGridMode.toggle()
                    UserDefaults.standard.set(isGridMode, forKey: "albumsViewIsGridMode")
                }) {
                    Image(systemName: isGridMode ? "list.bullet" : "square.grid.2x2")
                }
            }
        }
        .onAppear {
            // 如果是第一次启动应用且没有设置过偏好，默认使用网格模式
            if UserDefaults.standard.object(forKey: "albumsViewIsGridMode") == nil {
                isGridMode = true
                UserDefaults.standard.set(true, forKey: "albumsViewIsGridMode")
            }
        }
    }
}

// 专辑网格项组件
struct AlbumGridItem: View {
    let album: Album
    
    var body: some View {
        VStack {
            if let firstSong = album.songs.first,
               let coverImagePath = firstSong.coverImagePath,
               let uiImage = UIImage(contentsOfFile: coverImagePath) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 150, height: 150)
                    .cornerRadius(8)
            } else {
                Image(systemName: "music.note")
                    .resizable()
                    .scaledToFit()
                    .padding(40)
                    .frame(width: 150, height: 150)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                
                Text(album.artist)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Text("\(album.songs.count) 首歌曲")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(width: 150, alignment: .leading)
            .padding(.top, 4)
        }
        .padding(.bottom)
    }
}

// 空专辑列表视图
struct EmptyAlbumsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.stack")
                .font(.system(size: 70))
                .foregroundColor(.gray)
            
            Text("没有专辑")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text("导入音乐文件以查看专辑")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct AlbumsView_Previews: PreviewProvider {
    static var previews: some View {
        AlbumsView(musicPlayer: MusicPlayer.shared)
            .environmentObject(MusicLibrary.shared)
    }
} 