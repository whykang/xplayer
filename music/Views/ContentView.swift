import SwiftUI

struct ContentView: View {
    @EnvironmentObject var musicLibrary: MusicLibrary
    @ObservedObject var musicPlayer = MusicPlayer.shared
    @ObservedObject var userSettings = UserSettings.shared
    @Environment(\.colorScheme) var systemColorScheme
    @State private var isAppFirstLaunch = true
    
    var body: some View {
        MainTabView()
            .preferredColorScheme(getPreferredColorScheme())
            .onAppear {
                // 应用启动时仅执行一次
                if isAppFirstLaunch {
                    isAppFirstLaunch = false
                    print("ContentView首次显示，准备恢复播放状态")
                    
                    // 延迟显示以确保所有视图已加载
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if userSettings.savePlaybackState, 
                           musicPlayer.currentSong != nil {
                            // 如果已经恢复了播放状态，可以添加提示
                            print("已恢复播放状态: \(musicPlayer.currentSong?.title ?? "未知歌曲")")
                        }
                    }
                }
            }
    }
    
    // 根据用户设置返回首选的颜色模式
    private func getPreferredColorScheme() -> ColorScheme? {
        switch userSettings.colorScheme {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system:
            return nil  // 返回nil表示跟随系统
        }
    }
} 