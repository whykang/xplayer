import Foundation
import ActivityKit

// 共享的播放状态属性
public struct MusicPlaybackAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var title: String
        public var artist: String
        public var isPlaying: Bool
        public var currentTime: TimeInterval
        public var duration: TimeInterval
        
        public init(title: String, artist: String, isPlaying: Bool, currentTime: TimeInterval, duration: TimeInterval) {
            self.title = title
            self.artist = artist
            self.isPlaying = isPlaying
            self.currentTime = currentTime
            self.duration = duration
        }
    }
    
    // 添加公共初始化方法
    public init() {}
} 