//
//  MusicWidgetLiveActivity.swift
//  MusicWidget
//
//  Created by Hongyue Wang on 2025/4/1.
//

import ActivityKit
import WidgetKit
import SwiftUI
// 移除对SharedTypes的导入，因为它不可用
// import SharedTypes

// 在Widget扩展中本地定义MusicPlaybackAttributes
// 共享的播放状态属性
public struct MusicPlaybackAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var title: String
        public var artist: String
        public var isPlaying: Bool
        public var currentTime: TimeInterval
        public var duration: TimeInterval
        public var artworkURLString: String? // 添加专辑封面URL
        
        public init(title: String, artist: String, isPlaying: Bool, currentTime: TimeInterval, duration: TimeInterval, artworkURLString: String? = nil) {
            self.title = title
            self.artist = artist
            self.isPlaying = isPlaying
            self.currentTime = currentTime
            self.duration = duration
            self.artworkURLString = artworkURLString
        }
        
        // 获取专辑封面URL
        public var artworkURL: URL? {
            if let urlString = artworkURLString {
                return URL(string: urlString)
            }
            return nil
        }
    }
    
    public init() {}
}

struct MusicWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MusicPlaybackAttributes.self) { context in
            // 锁屏界面UI
            VStack {
                HStack {
                    // 专辑封面
                    if let artworkURL = context.state.artworkURL {
                        AsyncImage(url: artworkURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.7))
                                .frame(width: 50, height: 50)
                                .overlay(
                                    Image(systemName: "music.note")
                                        .foregroundColor(.white)
                                )
                        }
                    } else {
                        // 默认封面占位符
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.7))
                            .frame(width: 50, height: 50)
                            .overlay(
                                Image(systemName: "music.note")
                                    .foregroundColor(.white)
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.title)
                            .font(.headline)
                            .lineLimit(1)
                        
                        Text(context.state.artist)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // 播放/暂停按钮
                    Link(destination: URL(string: "musicapp://control/playPause")!) {
                        Image(systemName: context.state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.blue)
                    }
                    
                    // 下一首按钮
                    Link(destination: URL(string: "musicapp://control/next")!) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.blue)
                            .padding(.leading, 8)
                    }
                }
                
                // 进度条
                ProgressView(value: context.state.currentTime, total: max(context.state.duration, 1))
                    .tint(.blue)
                    .padding(.vertical, 8)
                
                // 时间显示
                HStack {
                    Text(formatTime(context.state.currentTime))
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    Text(formatTime(context.state.duration))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .padding()
            .activityBackgroundTint(Color.white.opacity(0.9))
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // 展开样式UI
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.state.title)
                            .font(.subheadline)
                            .foregroundColor(.white)
                    } icon: {
                        if let artworkURL = context.state.artworkURL {
                            AsyncImage(url: artworkURL) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 28, height: 28)
                                    .clipShape(Circle())
                            } placeholder: {
                                Circle()
                                    .fill(Color.blue.opacity(0.7))
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Image(systemName: "music.note")
                                            .foregroundColor(.white)
                                            .font(.system(size: 14))
                                    )
                            }
                        } else {
                            Circle()
                                .fill(Color.blue.opacity(0.7))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Image(systemName: "music.note")
                                        .foregroundColor(.white)
                                        .font(.system(size: 14))
                                )
                        }
                    }
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    Label {
                        Text(context.state.artist)
                            .font(.caption)
                            .foregroundColor(.white)
                    } icon: {
                        Image(systemName: "person")
                            .foregroundColor(.white)
                    }
                }
                
                DynamicIslandExpandedRegion(.center) {
                    ProgressView(value: context.state.currentTime, total: max(context.state.duration, 1))
                        .tint(.white)
                        .frame(height: 2)
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    // 控制按钮
                    HStack {
                        // 上一首
                        Link(destination: URL(string: "musicapp://control/previous")!) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                        
                        Spacer()
                        
                        // 播放/暂停按钮
                        Link(destination: URL(string: "musicapp://control/playPause")!) {
                            Image(systemName: context.state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.white)
                        }
                        
                        Spacer()
                        
                        // 下一首
                        Link(destination: URL(string: "musicapp://control/next")!) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal)
                }
            } compactLeading: {
                // 紧凑型UI - 左侧
                if let artworkURL = context.state.artworkURL {
                    AsyncImage(url: artworkURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 18, height: 18)
                            .clipShape(Circle())
                    } placeholder: {
                        Image(systemName: "music.note")
                            .foregroundColor(.white)
                            .font(.system(size: 12))
                    }
                } else {
                    Image(systemName: "music.note")
                        .foregroundColor(.white)
                        .font(.system(size: 12))
                }
            } compactTrailing: {
                // 紧凑型UI - 右侧
                Link(destination: URL(string: "musicapp://control/playPause")!) {
                    Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 12))
                }
            } minimal: {
                // 最小型UI
                if let artworkURL = context.state.artworkURL {
                    AsyncImage(url: artworkURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 15, height: 15)
                            .clipShape(Circle())
                    } placeholder: {
                        Image(systemName: "music.note")
                            .foregroundColor(.white)
                            .font(.system(size: 8))
                    }
                } else {
                    Image(systemName: "music.note")
                        .foregroundColor(.white)
                        .font(.system(size: 8))
                }
            }
        }
    }
    
    // 格式化时间为 mm:ss 格式
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// 预览用拓展
extension MusicPlaybackAttributes {
    fileprivate static var preview: MusicPlaybackAttributes {
        MusicPlaybackAttributes()
    }
}

extension MusicPlaybackAttributes.ContentState {
    fileprivate static var playing: MusicPlaybackAttributes.ContentState {
        MusicPlaybackAttributes.ContentState(
            title: "明明就 - 周杰伦",
            artist: "黄雨勋",
            isPlaying: true,
            currentTime: 17,
            duration: 243,  // 4:03
            artworkURLString: "https://picsum.photos/200"
        )
    }
    
    fileprivate static var paused: MusicPlaybackAttributes.ContentState {
        MusicPlaybackAttributes.ContentState(
            title: "明明就 - 周杰伦",
            artist: "黄雨勋",
            isPlaying: false,
            currentTime: 17,
            duration: 243,  // 4:03
            artworkURLString: "https://picsum.photos/200"
        )
    }
}

// 使用传统的PreviewProvider替代iOS 17.0+的Preview宏
struct MusicWidgetLiveActivity_Previews: PreviewProvider {
    static let attributes = MusicPlaybackAttributes()
    static let contentState = MusicPlaybackAttributes.ContentState.playing
    
    static var previews: some View {
        attributes
            .previewContext(contentState, viewKind: .content)
            .previewDisplayName("Notification")
    }
}
