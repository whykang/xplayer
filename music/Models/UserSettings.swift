import Foundation
import SwiftUI

// Tab类型枚举
enum TabType: String, CaseIterable, Identifiable {
    case songs = "歌曲"
    case albums = "专辑"
    case artists = "艺术家"
    case playlists = "歌单"
    case settings = "设置"
    
    var id: String { self.rawValue }
    
    var systemImage: String {
        switch self {
        case .songs: return "music.note"
        case .albums: return "square.stack"
        case .artists: return "music.mic"
        case .playlists: return "music.note.list"
        case .settings: return "gear"
        }
    }
    
    var tag: Int {
        switch self {
        case .songs: return 0
        case .albums: return 1
        case .artists: return 2
        case .playlists: return 3
        case .settings: return 4
        }
    }
}

class UserSettings: ObservableObject {
    public static let shared = UserSettings()
    
    // 用于存储用户设置的UserDefaults
    private let userDefaults = UserDefaults.standard
    
    // 设置项的键名
    private struct Keys {
        static let autoFetchLyrics = "autoFetchLyrics"
        static let networkPermissionAsked = "networkPermissionAsked"
        static let tabOrder = "tabOrder"
        static let colorScheme = "colorScheme"
        static let savePlaybackState = "savePlaybackState"
        static let webdavServer = "webdavServer"
        static let webdavUsername = "webdavUsername"
        static let webdavPassword = "webdavPassword"
        static let webdavDirectory = "webdavDirectory"
        static let lastBackupDate = "lastBackupDate"
        static let enableCarDisplayLyrics = "enableCarDisplayLyrics"
        static let songSortMode = "songSortMode"
    }
    
    // 颜色模式枚举
    enum AppColorScheme: String, CaseIterable {
        case system = "跟随系统"
        case light = "浅色模式"
        case dark = "深色模式"
        
        var colorScheme: ColorScheme? {
            switch self {
            case .light: return .light
            case .dark: return .dark
            case .system: return nil
            }
        }
    }
    
    // 是否自动获取歌词
    @Published var autoFetchLyrics: Bool {
        didSet {
            userDefaults.set(autoFetchLyrics, forKey: Keys.autoFetchLyrics)
        }
    }
    
    // 是否已经询问过网络权限
    @Published var networkPermissionAsked: Bool {
        didSet {
            userDefaults.set(networkPermissionAsked, forKey: Keys.networkPermissionAsked)
        }
    }
    
    // 颜色模式设置
    @Published var colorScheme: AppColorScheme {
        didSet {
            userDefaults.set(colorScheme.rawValue, forKey: Keys.colorScheme)
        }
    }
    
    // 是否保存播放状态
    @Published var savePlaybackState: Bool {
        didSet {
            userDefaults.set(savePlaybackState, forKey: Keys.savePlaybackState)
        }
    }
    
    // 是否开启车机显示歌词功能
    @Published var enableCarDisplayLyrics: Bool {
        didSet {
            userDefaults.set(enableCarDisplayLyrics, forKey: Keys.enableCarDisplayLyrics)
            // 更新MusicPlayer的歌词显示设置
            MusicPlayer.shared.setLyricDisplayEnabled(enableCarDisplayLyrics)
        }
    }
    
    // WebDAV服务器地址
    @Published var webdavServer: String {
        didSet {
            userDefaults.set(webdavServer, forKey: Keys.webdavServer)
        }
    }
    
    // WebDAV用户名
    @Published var webdavUsername: String {
        didSet {
            userDefaults.set(webdavUsername, forKey: Keys.webdavUsername)
        }
    }
    
    // WebDAV密码（实际应用中应加密存储）
    @Published var webdavPassword: String {
        didSet {
            userDefaults.set(webdavPassword, forKey: Keys.webdavPassword)
        }
    }
    
    // WebDAV备份目录
    @Published var webdavDirectory: String {
        didSet {
            userDefaults.set(webdavDirectory, forKey: Keys.webdavDirectory)
        }
    }
    
    // 最后备份日期
    @Published var lastBackupDate: Date? {
        didSet {
            userDefaults.set(lastBackupDate, forKey: Keys.lastBackupDate)
        }
    }
    
    // Tab顺序设置
    @Published var tabOrder: [TabType] {
        didSet {
            // 将枚举转换为字符串数组存储
            let stringArray = tabOrder.map { $0.rawValue }
            userDefaults.set(stringArray, forKey: Keys.tabOrder)
        }
    }
    
    // 默认的Tab顺序
    static let defaultTabOrder: [TabType] = [
        .songs, .albums, .artists, .playlists, .settings
    ]
    
    private init() {
        // 从UserDefaults加载设置，默认为开启
        self.autoFetchLyrics = userDefaults.object(forKey: Keys.autoFetchLyrics) as? Bool ?? true
        self.networkPermissionAsked = userDefaults.bool(forKey: Keys.networkPermissionAsked)
        self.savePlaybackState = userDefaults.object(forKey: Keys.savePlaybackState) as? Bool ?? true
        self.enableCarDisplayLyrics = userDefaults.object(forKey: Keys.enableCarDisplayLyrics) as? Bool ?? true
        
        // 加载颜色模式设置
        if let savedColorScheme = userDefaults.string(forKey: Keys.colorScheme),
           let scheme = AppColorScheme(rawValue: savedColorScheme) {
            self.colorScheme = scheme
        } else {
            // 默认跟随系统
            self.colorScheme = .system
        }
        
        // 加载WebDAV设置
        self.webdavServer = userDefaults.string(forKey: Keys.webdavServer) ?? ""
        self.webdavUsername = userDefaults.string(forKey: Keys.webdavUsername) ?? ""
        self.webdavPassword = userDefaults.string(forKey: Keys.webdavPassword) ?? ""
        self.webdavDirectory = userDefaults.string(forKey: Keys.webdavDirectory) ?? "/XPlayer_Backup"
        self.lastBackupDate = userDefaults.object(forKey: Keys.lastBackupDate) as? Date
        
        // 加载Tab顺序设置
        if let savedOrder = userDefaults.stringArray(forKey: Keys.tabOrder),
           savedOrder.count == TabType.allCases.count {
            // 将字符串数组转换回枚举数组
            self.tabOrder = savedOrder.compactMap { TabType(rawValue: $0) }
        } else {
            // 默认顺序
            self.tabOrder = UserSettings.defaultTabOrder
        }
        
        // 初始化后应用车机歌词显示设置
        DispatchQueue.main.async {
            // 在主线程应用设置
            MusicPlayer.shared.setLyricDisplayEnabled(self.enableCarDisplayLyrics)
        }
    }
    
    // 重置所有设置为默认值
    func resetSettings() {
        autoFetchLyrics = true
        networkPermissionAsked = false
        tabOrder = UserSettings.defaultTabOrder
        colorScheme = .system
        savePlaybackState = true
        enableCarDisplayLyrics = true
    }
    
    // 重置Tab顺序为默认值
    func resetTabOrder() {
        tabOrder = UserSettings.defaultTabOrder
    }
    
    // 检查网络权限并请求
    func checkNetworkPermission() -> Bool {
        // 这里只是一个示例，实际iOS无法直接检查网络权限
        // 通常是通过请求网络时的错误来判断
        return true
    }
    
    // 获取Tab在当前排序中的索引
    func getTabIndex(for tabType: TabType) -> Int {
        return tabOrder.firstIndex(of: tabType) ?? tabType.tag
    }
} 