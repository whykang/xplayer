//
//  AppDelegate.swift
//  music
//
//  Created by Hongyue Wang on 2025/3/31.
//

import UIKit
import AVFoundation
import WidgetKit
import MediaPlayer
import Network
// import ActivityKit

class AppDelegate: UIResponder, UIApplicationDelegate {

    // 添加网络监视器
    private var networkMonitor: NWPathMonitor?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        // 打印应用沙盒目录信息
        print("======= 应用启动 =======")
        print("应用沙盒根目录: \(NSHomeDirectory())")
        print("Documents目录: \(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path)")
        print("Library目录: \(FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].path)")
        print("临时目录: \(NSTemporaryDirectory())")
        print("Bundle ID: \(Bundle.main.bundleIdentifier ?? "未知")")
        print("======= 应用启动完成 =======")
        
        // 设置后台播放
        setupBackgroundPlayback()
        
        // 首次启动检查
        checkFirstLaunch()
        
        // 初始化网络监视器
        setupNetworkMonitoring()
        
        // 刷新Widget内容
        WidgetCenter.shared.reloadAllTimelines()
        
        // 设置分享功能
        setupSharingFunctionality()
        
        // 恢复上次的播放状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.restorePlaybackState()
        }
        
        return true
    }
    
    // 检查是否为首次启动并请求网络权限
    private func checkFirstLaunch() {
        let userDefaults = UserDefaults.standard
        let isFirstLaunch = !userDefaults.bool(forKey: "hasLaunchedBefore")
        
        if isFirstLaunch {
            print("检测到首次启动应用")
            userDefaults.set(true, forKey: "hasLaunchedBefore")
        } else {
            print("应用之前已启动过")
        }
    }
    
    // 设置后台播放
    private func setupBackgroundPlayback() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowBluetooth, .allowAirPlay])
            try AVAudioSession.sharedInstance().setActive(true)
            
            // 添加音频会话中断通知
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAudioSessionInterruption),
                name: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance()
            )
        } catch {
            print("设置音频会话失败: \(error)")
        }
    }
    
    // 处理音频会话中断
    @objc func handleAudioSessionInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        // 根据中断类型进行处理
        switch type {
        case .began:
            // 中断开始，例如接到电话
            print("音频中断开始")
            
        case .ended:
            // 中断结束，可以恢复播放
            print("音频中断结束")
            
            // 如果提供了中断选项并且可以恢复
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt,
               AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume) {
                // 重新激活会话
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    
                    // 恢复播放
                    if let player = MusicPlayer.shared.currentSong, MusicPlayer.shared.isPlaying {
                        print("中断结束后恢复播放")
                    }
                } catch {
                    print("恢复音频会话失败: \(error)")
                }
            }
            
        @unknown default:
            break
        }
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
    
    // 应用即将终止时调用
    func applicationWillTerminate(_ application: UIApplication) {
        print("应用即将终止")
        
        // 停止网络监视器
        networkMonitor?.cancel()
        
        // 强制保存歌单数据，确保在应用退出时歌单不会丢失
        MusicLibrary.shared.forceSavePlaylists()
        
        // 保存播放状态
        savePlaybackState()
    }
    
    // 设置分享功能
    private func setupSharingFunctionality() {
        // 注册分享相关的通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSharingCompletion),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    // 处理从分享界面返回的通知
    @objc func handleSharingCompletion() {
        // 确保重置SongRow的分享状态
        if SongRow.isSharingActive {
            print("AppDelegate: 检测到应用重新激活，重置分享状态")
            SongRow.isSharingActive = false
            SongRow.sharingTimer?.invalidate()
            SongRow.sharingTimer = nil
        }
    }
    
    // 处理通过文件打开应用的情况
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        print("AppDelegate接收到打开URL请求: \(url.absoluteString)")
        
        // 处理通过分享返回的URL
        if url.absoluteString.starts(with: "musicapp://sharing") || url.absoluteString.starts(with: "xplayer://sharing") {
            print("AppDelegate: 处理分享回调 URL: \(url)")
            
            // 重置分享状态
            SongRow.isSharingActive = false
            SongRow.sharingTimer?.invalidate()
            SongRow.sharingTimer = nil
            
            return true
        }
        
        // 处理音频文件打开
        if MusicFileManager.shared.isSupportedAudioFile(url: url) {
            print("通过应用程序委托接收到音频文件: \(url.lastPathComponent)")
            
            // 尝试获取安全访问权限
            let secureAccess = url.startAccessingSecurityScopedResource()
            defer {
                if secureAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            // 通知SceneDelegate处理文件导入（通过通知中心）
            NotificationCenter.default.post(
                name: Notification.Name("ExternalAudioFileReceived"),
                object: nil,
                userInfo: ["fileURL": url]
            )
            
            return true
        }
        
        return false
    }
    
    // 添加处理文档选择器选择文件的方法
    func application(_ app: UIApplication, open url: URL, sourceApplication: String?, annotation: Any) -> Bool {
        print("AppDelegate通过旧API接收到URL: \(url.absoluteString)")
        
        // 处理音频文件打开
        if MusicFileManager.shared.isSupportedAudioFile(url: url) {
            print("通过旧API接收到音频文件: \(url.lastPathComponent)")
            
            // 尝试获取安全访问权限
            let secureAccess = url.startAccessingSecurityScopedResource()
            defer {
                if secureAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            // 通知SceneDelegate处理文件导入
            NotificationCenter.default.post(
                name: Notification.Name("ExternalAudioFileReceived"),
                object: nil,
                userInfo: ["fileURL": url]
            )
            
            return true
        }
        
        return false
    }
    
    // 处理通用链接
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        // 处理从网页或其他来源的链接
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
           let url = userActivity.webpageURL {
            
            print("AppDelegate接收到NSUserActivity: \(url.absoluteString)")
            
            // 检查是否是支持的音频文件
            if MusicFileManager.shared.isSupportedAudioFile(url: url) {
                // 通知SceneDelegate处理文件导入
                NotificationCenter.default.post(
                    name: Notification.Name("ExternalAudioFileReceived"),
                    object: nil,
                    userInfo: ["fileURL": url]
                )
                return true
            }
        }
        
        return false
    }
    
    // 设置网络监视器
    private func setupNetworkMonitoring() {
        networkMonitor = NWPathMonitor()
        let queue = DispatchQueue(label: "NetworkMonitor")
        
        networkMonitor?.pathUpdateHandler = { path in
            // 这里只需触发网络权限请求，不需执行其他操作
            // 系统会自动弹出网络权限请求对话框
            print("网络状态: \(path.status == .satisfied ? "已连接" : "未连接")")
        }
        
        // 启动网络监视器，这会自动触发权限请求
        networkMonitor?.start(queue: queue)
    }
    
    // 恢复上次保存的播放状态
    private func restorePlaybackState() {
        // 确保MusicLibrary已经加载完成
        if !MusicLibrary.shared.songs.isEmpty {
            print("准备恢复上次的播放状态")
            PlaybackStateManager.shared.restorePlaybackState()
        } else {
            print("音乐库尚未加载完成，稍后再尝试恢复播放状态")
            // 延迟再次尝试
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.restorePlaybackState()
            }
        }
    }
    
    // 保存播放状态
    private func savePlaybackState() {
        print("正在保存播放状态...")
        PlaybackStateManager.shared.savePlaybackState()
    }
}

