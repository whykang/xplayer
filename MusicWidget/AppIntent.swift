//
//  AppIntent.swift
//  musicwidget
//
//  Created by Hongyue Wang on 2025/4/1.
//

import WidgetKit
import AppIntents

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Configuration" }
    static var description: IntentDescription { "This is an example widget." }

    // An example configurable parameter.
    @Parameter(title: "Favorite Emoji", default: "😃")
    var favoriteEmoji: String
    
    // 添加必要的perform方法，满足iOS 16.6+的要求
    func perform() async throws -> some IntentResult {
        return .result()
    }
}
