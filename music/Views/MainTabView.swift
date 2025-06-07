import SwiftUI

struct MainTabView: View {
    @ObservedObject var musicLibrary = MusicLibrary.shared
    @ObservedObject var musicPlayer = MusicPlayer.shared
    @ObservedObject var userSettings = UserSettings.shared
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                // 根据用户设置的顺序创建标签
                ForEach(userSettings.tabOrder) { tabType in
                    getTabView(for: tabType)
                        .tabItem {
                            Image(systemName: tabType.systemImage)
                            Text(tabType.rawValue)
                        }
                        .tag(userSettings.getTabIndex(for: tabType))
                }
            }
            .environmentObject(musicLibrary)
            
            // 迷你播放器
            if musicPlayer.currentSong != nil {
                VStack(spacing: 0) {
                    MiniPlayerView()
                        .background(Color(UIColor.systemBackground))
                        .animation(.easeInOut(duration: 0.3), value: musicPlayer.currentSong != nil)
                        .transition(.move(edge: .bottom))
                }
                .padding(.bottom, 49) // TabBar的高度
            }
        }
    }
    
    // 根据标签类型返回相应的视图
    @ViewBuilder
    private func getTabView(for tabType: TabType) -> some View {
        switch tabType {
        case .songs:
            SongsView(musicPlayer: musicPlayer)
            
        case .albums:
            NavigationView {
                AlbumsView(musicPlayer: musicPlayer)
                    .navigationBarTitleDisplayMode(.large)
            }
            .navigationViewStyle(StackNavigationViewStyle())
            
        case .artists:
            NavigationView {
                ArtistsView(musicPlayer: musicPlayer)
                    .navigationBarTitleDisplayMode(.large)
            }
            .navigationViewStyle(StackNavigationViewStyle())
            
        case .playlists:
            NavigationView {
                PlaylistsView()
                    .navigationBarTitleDisplayMode(.large)
            }
            .navigationViewStyle(StackNavigationViewStyle())
            
        case .settings:
            NavigationView {
                SettingsView()
                    .navigationBarTitleDisplayMode(.large)
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
    }
} 