import Foundation
import WidgetKit
import UIKit

// 使用UserDefaults + App Groups 在主应用和Widget之间共享数据
class AppShare {
    static let shared = AppShare()
    
    // App Group标识符
    private let appGroupIdentifier = "group.com.yourcompany.music.widget"
    
    // 共享的UserDefaults
    private var sharedDefaults: UserDefaults?
    
    // 键名常量
    private struct Keys {
        static let currentSongTitle = "currentSongTitle"
        static let currentArtist = "currentArtist"
        static let isPlaying = "isPlaying"
        static let currentTime = "currentTime"
        static let duration = "duration"
        static let lastUpdated = "lastUpdated"
        static let albumCoverData = "albumCoverData"
    }
    
    private init() {
        sharedDefaults = UserDefaults(suiteName: appGroupIdentifier)
    }
    
    // 更新当前播放信息
    func updatePlaybackInfo(title: String, artist: String, isPlaying: Bool, currentTime: TimeInterval, duration: TimeInterval, albumCover: UIImage? = nil) {
        guard let defaults = sharedDefaults else { return }
        
        defaults.set(title, forKey: Keys.currentSongTitle)
        defaults.set(artist, forKey: Keys.currentArtist)
        defaults.set(isPlaying, forKey: Keys.isPlaying)
        defaults.set(currentTime, forKey: Keys.currentTime)
        defaults.set(duration, forKey: Keys.duration)
        defaults.set(Date(), forKey: Keys.lastUpdated)
        
        // 保存专辑封面
        if let albumCover = albumCover, let imageData = albumCover.jpegData(compressionQuality: 0.7) {
            defaults.set(imageData, forKey: Keys.albumCoverData)
        }
        
        defaults.synchronize()
        
        // 通知Widget更新
        #if os(iOS)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
    
    // 获取当前播放信息
    func getCurrentPlaybackInfo() -> (title: String, artist: String, isPlaying: Bool, currentTime: TimeInterval, duration: TimeInterval, lastUpdated: Date, albumCover: UIImage?) {
        guard let defaults = sharedDefaults else {
            return ("", "", false, 0, 0, Date(), nil)
        }
        
        let title = defaults.string(forKey: Keys.currentSongTitle) ?? ""
        let artist = defaults.string(forKey: Keys.currentArtist) ?? ""
        let isPlaying = defaults.bool(forKey: Keys.isPlaying)
        let currentTime = defaults.double(forKey: Keys.currentTime)
        let duration = defaults.double(forKey: Keys.duration)
        let lastUpdated = defaults.object(forKey: Keys.lastUpdated) as? Date ?? Date()
        
        // 获取专辑封面
        var albumCover: UIImage? = nil
        if let imageData = defaults.data(forKey: Keys.albumCoverData) {
            albumCover = UIImage(data: imageData)
        }
        
        return (title, artist, isPlaying, currentTime, duration, lastUpdated, albumCover)
    }
    
    // 清除当前播放信息
    func clearPlaybackInfo() {
        guard let defaults = sharedDefaults else { return }
        
        defaults.removeObject(forKey: Keys.currentSongTitle)
        defaults.removeObject(forKey: Keys.currentArtist)
        defaults.removeObject(forKey: Keys.isPlaying)
        defaults.removeObject(forKey: Keys.currentTime)
        defaults.removeObject(forKey: Keys.duration)
        defaults.removeObject(forKey: Keys.lastUpdated)
        defaults.removeObject(forKey: Keys.albumCoverData)
        
        defaults.synchronize()
        
        // 通知Widget更新
        #if os(iOS)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
} 