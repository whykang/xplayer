import SwiftUI

struct AlbumRow: View {
    let album: Album
    
    var body: some View {
        HStack {
            if let firstSong = album.songs.first,
               let coverImagePath = firstSong.coverImagePath,
               let uiImage = UIImage(contentsOfFile: coverImagePath) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .cornerRadius(4)
            } else {
                Image(systemName: "music.note")
                    .resizable()
                    .scaledToFit()
                    .padding(10)
                    .frame(width: 50, height: 50)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
            }
            
            VStack(alignment: .leading) {
                Text(album.title)
                    .font(.headline)
                Text(album.artist)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("\(album.songs.count) 首歌曲")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
} 