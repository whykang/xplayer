import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var musicLibrary: MusicLibrary
    @ObservedObject var musicPlayer: MusicPlayer
    @State private var showingImportSheet = false
    
    var body: some View {
        NavigationView {
            List {
                if musicLibrary.songs.isEmpty {
                    Section {
                        VStack(spacing: 20) {
                            Image(systemName: "music.note")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 60, height: 60)
                                .foregroundColor(.secondary)
                            
                            Text("没有音乐文件")
                                .font(.headline)
                            
                            Button(action: {
                                showingImportSheet = true
                            }) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("导入音乐")
                                }
                                .padding()
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    }
                } else {
                    Section {
                        ForEach(musicLibrary.songs) { song in
                            SongRow(song: song)
                        }
                    }
                }
            }
            .navigationTitle("歌曲")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        print("Import button clicked in LibraryView!")
                        showingImportSheet = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingImportSheet) {
                EnhancedImportView()
            }
        }
    }
}

struct LibraryView_Previews: PreviewProvider {
    static var previews: some View {
        LibraryView(musicPlayer: MusicPlayer.shared)
            .environmentObject(MusicLibrary.shared)
    }
} 