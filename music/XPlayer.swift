import SwiftUI
import WidgetKit

@main
struct MusicApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var musicLibrary = MusicLibrary.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(musicLibrary)
                .onAppear {
                    // 注册Widget
                    WidgetCenter.shared.reloadAllTimelines()
                }
        }
    }
} 