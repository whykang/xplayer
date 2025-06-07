//
//  MusicWidgetBundle.swift
//  MusicWidget
//
//  Created by Hongyue Wang on 2025/4/1.
//

import WidgetKit
import SwiftUI

@main
struct MusicWidgetBundle: WidgetBundle {
    var body: some Widget {
        // Widget和LiveActivity - 只包含普通Widget
        MusicWidget()
        MusicWidgetLiveActivity()
    }
    
    // 注：ControlWidget需要iOS 18.0+，当前暂不支持
    // 如果需要支持，请参考MusicWidgetControl.swift.disabled
}
