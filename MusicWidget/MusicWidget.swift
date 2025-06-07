//
//  MusicWidget.swift
//  MusicWidget
//
//  Created by Hongyue Wang on 2025/4/1.
//

import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), title: "示例歌曲", artist: "示例艺术家", isPlaying: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(), title: "示例歌曲", artist: "示例艺术家", isPlaying: true)
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> ()) {
        var entries: [SimpleEntry] = []

        // 生成未来几小时的条目
        let currentDate = Date()
        for hourOffset in 0 ..< 5 {
            let entryDate = Calendar.current.date(byAdding: .hour, value: hourOffset, to: currentDate)!
            // 在实际应用中，这些值应该从AppShare或UserDefaults中获取
            let entry = SimpleEntry(
                date: entryDate,
                title: "示例歌曲",
                artist: "示例艺术家",
                isPlaying: hourOffset % 2 == 0 // 简单的交替显示播放状态
            )
            entries.append(entry)
        }

        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String
    let isPlaying: Bool
}

struct MusicWidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        ZStack {
            // 背景渐变
            LinearGradient(
                gradient: Gradient(colors: [.blue.opacity(0.8), .purple.opacity(0.6)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(alignment: .leading, spacing: 8) {
                // 顶部标题
                Text("正在播放")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                
                // 中间内容
                HStack(spacing: 12) {
                    // 专辑封面占位符
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundColor(.white)
                        )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title)
                            .font(.headline)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text(entry.artist)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // 播放/暂停按钮
                    Image(systemName: entry.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                }
                
                Spacer()
            }
            .padding()
        }
    }
}

struct MusicWidget: Widget {
    let kind: String = "MusicWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            MusicWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("XPlayer")
        .description("显示当前正在播放的音乐。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// 使用传统PreviewProvider替代iOS 17.0+的Preview宏
struct MusicWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MusicWidgetEntryView(entry: SimpleEntry(
                date: .now,
                title: "示例歌曲",
                artist: "示例艺术家",
                isPlaying: true
            ))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            
            MusicWidgetEntryView(entry: SimpleEntry(
                date: .now,
                title: "另一首歌曲",
                artist: "另一位艺术家",
                isPlaying: false
            ))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
        }
    }
}
