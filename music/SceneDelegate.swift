//
//  SceneDelegate.swift
//  music
//
//  Created by Hongyue Wang on 2025/3/31.
//

import UIKit
import SwiftUI
import WidgetKit
import UniformTypeIdentifiers
import Network
// import ActivityKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate, UIDocumentPickerDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIScene.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnecting:options:` instead).
        
        // 打印启动信息
        print("Scene启动：\(Date())")
        
        // 创建窗口
        guard let windowScene = (scene as? UIWindowScene) else { return }
        let window = UIWindow(windowScene: windowScene)
        self.window = window
        
        // 创建内容视图
        let musicLibrary = MusicLibrary.shared
        let musicPlayer = MusicPlayer.shared
        
        // 使用SwiftUI创建内容
        let contentView = ContentView()
            .environmentObject(musicLibrary)
            .environmentObject(musicPlayer)
        
        // 设置根视图控制器
        let hostingController = UIHostingController(rootView: contentView)
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        
        // 注册应用终止通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        
        // 处理从URL打开的情况
        if let urlContext = connectionOptions.urlContexts.first {
            handleExternalAudioFile(urlContext.url)
        }
        
        // 处理从文档选择器选择的文件
        if !connectionOptions.userActivities.isEmpty {
            for activity in connectionOptions.userActivities {
                if activity.activityType == NSUserActivityTypeBrowsingWeb,
                   let url = activity.webpageURL {
                    importMusicFromDocuments(url)
                }
            }
        }
        
        // 注册通知，处理来自AppDelegate的文件导入请求
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ExternalAudioFileReceived"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let url = notification.userInfo?["fileURL"] as? URL {
                self?.handleExternalAudioFile(url)
            }
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
        print("应用变为活跃")
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
        print("应用即将进入非活跃状态")
        
        // 保存当前播放状态
        PlaybackStateManager.shared.savePlaybackState()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
        print("应用即将回到前台")
        
        // 检查歌单数据一致性
        DispatchQueue.global(qos: .userInitiated).async {
            // 重新从磁盘加载歌单以确保数据一致性
            MusicLibrary.shared.loadPlaylists()
            
            // 打印歌单状态信息
            let playlistCount = MusicLibrary.shared.playlists.count
            let favoritesCount = MusicLibrary.shared.favorites.songs.count
            print("应用恢复到前台：载入了\(playlistCount)个歌单，收藏列表包含\(favoritesCount)首歌曲")
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
        print("应用进入后台")
        
        // 在应用进入后台时强制保存歌单，防止数据丢失
        MusicLibrary.shared.forceSavePlaylists()
        
        // 保存当前播放状态
        PlaybackStateManager.shared.savePlaybackState()
    }

    // 处理应用终止
    @objc func handleAppWillTerminate() {
        print("应用即将终止")
        // 在应用终止时强制保存歌单，防止数据丢失
        MusicLibrary.shared.forceSavePlaylists()
        
        // 保存当前播放状态
        PlaybackStateManager.shared.savePlaybackState()
    }

    // 处理来自灵动岛的URL操作
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        print("收到URL请求: \(url)")
        
        // 首先检查是否是支持的音频文件
        if MusicFileManager.shared.isSupportedAudioFile(url: url) {
            print("接收到的URL是音频文件, 开始处理...")
            handleExternalAudioFile(url)
            return
        }
        
        // 如果不是音频文件，处理其他URL操作
        let urlString = url.absoluteString
        
        // 播放控制
        if urlString.contains("control/") {
            let actionString = url.lastPathComponent
            
            switch actionString {
            case "playPause":
                print("URL操作: 播放/暂停")
                if MusicPlayer.shared.isPlaying {
                    MusicPlayer.shared.pause()
                } else {
                    MusicPlayer.shared.resume()
                }
            case "next":
                print("URL操作: 下一曲")
                MusicPlayer.shared.playNext()
            case "previous":
                print("URL操作: 上一曲")
                MusicPlayer.shared.playPrevious()
            default:
                print("未识别的URL操作: \(actionString)")
            }
        }
    }

    // 添加新方法处理外部音频文件
    private func handleExternalAudioFile(_ url: URL) {
        // 检查是否是支持的音频文件
        if MusicFileManager.shared.isSupportedAudioFile(url: url) {
            print("接收到外部音频文件: \(url.lastPathComponent)")
            
            // 尝试获取安全访问权限
            let secureAccess = url.startAccessingSecurityScopedResource()
            defer {
                if secureAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            // 首先只提取元数据，不导入
            MusicFileManager.shared.extractMetadataOnly(from: url) { [weak self] result in
                guard let self = self else { return }
                
                switch result {
                case .success(let song):
                    DispatchQueue.main.async {
                        // 检查是否有类似歌曲
                        if MusicLibrary.shared.hasSimilarSong(song) {
                            self.showDuplicateWarning(for: song, sourceURL: url)
                        } else {
                            // 没有类似歌曲，直接显示导入确认对话框
                            self.showImportConfirmation(for: url)
                        }
                    }
                    
                case .failure(let error):
                    DispatchQueue.main.async {
                        self.showErrorAlert(message: "无法读取音乐文件: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            print("不支持的文件类型: \(url.lastPathComponent)")
            showErrorAlert(message: "无法导入 \"\(url.lastPathComponent)\"，不支持此文件类型。")
        }
    }

    // 显示重复歌曲警告
    private func showDuplicateWarning(for song: Song, sourceURL: URL) {
        guard let rootViewController = self.window?.rootViewController else { return }
        
        // 获取类似的歌曲
        let similarSongs = MusicLibrary.shared.getSimilarSongs(song)
        let similarInfo = similarSongs.map { "• \($0.title) - \($0.artist)" }.joined(separator: "\n")
        
        let alert = UIAlertController(
            title: "发现类似歌曲",
            message: "音乐库中已存在类似歌曲:\n\(similarInfo)\n\n是否仍要导入?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        
        alert.addAction(UIAlertAction(title: "继续导入", style: .default) { _ in
            // 用户选择继续导入
            self.showImportConfirmation(for: sourceURL)
        })
        
        rootViewController.present(alert, animated: true)
    }

    // 显示导入确认对话框
    private func showImportConfirmation(for url: URL) {
        guard let rootViewController = self.window?.rootViewController else { return }
        
        let alert = UIAlertController(
            title: "导入音乐",
            message: "是否导入音乐文件 \"\(url.lastPathComponent)\" 到音乐库？",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        
        alert.addAction(UIAlertAction(title: "导入", style: .default) { _ in
            // 显示加载指示器
            let loadingAlert = UIAlertController(
                title: "正在导入",
                message: "请稍候...",
                preferredStyle: .alert
            )
            
            rootViewController.present(loadingAlert, animated: true)
            
            // 导入音乐文件
            MusicFileManager.shared.importMusicFile(from: url) { result in
                DispatchQueue.main.async {
                    // 关闭加载指示器
                    loadingAlert.dismiss(animated: true)
                    
                    switch result {
                    case .success(let song):
                        // 显示成功消息
                        let successAlert = UIAlertController(
                            title: "导入成功",
                            message: "已成功导入 \"\(song.title)\"",
                            preferredStyle: .alert
                        )
                        
                        successAlert.addAction(UIAlertAction(title: "确定", style: .default))
                        
                        rootViewController.present(successAlert, animated: true)
                        
                    case .failure(let error):
                        // 显示错误消息
                        self.showErrorAlert(message: "导入失败: \(error.localizedDescription)")
                    }
                }
            }
        })
        
        rootViewController.present(alert, animated: true)
    }

    // 显示错误提示
    private func showErrorAlert(message: String) {
        guard let rootViewController = self.window?.rootViewController else { return }
        
        let alert = UIAlertController(
            title: "错误",
            message: message,
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        
        rootViewController.present(alert, animated: true)
    }

    // 添加一个新方法：实现通过文档选择器导入音乐
    func importMusicFromDocuments(_ sourceURL: URL, completion: ((_ success: Bool) -> Void)? = nil) {
        print("通过文档选择器导入: \(sourceURL.path)")
        
        // 检查是否是支持的音频文件
        if !MusicFileManager.shared.isSupportedAudioFile(url: sourceURL) {
            print("不支持的文件类型: \(sourceURL.lastPathComponent)")
            showErrorAlert(message: "无法导入 \"\(sourceURL.lastPathComponent)\"，不支持此文件类型。")
            completion?(false)
            return
        }
        
        // 尝试获取安全访问权限
        let secureAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if secureAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        // 首先提取元数据
        MusicFileManager.shared.extractMetadataOnly(from: sourceURL) { [weak self] result in
            guard let self = self else { completion?(false); return }
            
            switch result {
            case .success(let song):
                DispatchQueue.main.async {
                    // 检查是否有类似歌曲
                    if MusicLibrary.shared.hasSimilarSong(song) {
                        self.showDuplicateWarning(for: song, sourceURL: sourceURL)
                        completion?(true) // 展示了重复歌曲警告，算作成功
                    } else {
                        // 没有类似歌曲，直接显示导入确认对话框
                        self.showImportConfirmation(for: sourceURL)
                        completion?(true) // 展示了导入确认对话框，算作成功
                    }
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self.showErrorAlert(message: "无法读取音乐文件: \(error.localizedDescription)")
                    completion?(false)
                }
            }
        }
    }

    // 添加临时保存音频文件的方法
    private func saveTemporaryAudioFile(_ data: Data) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "temp_audio_file_\(UUID().uuidString)"
        let fileURL = tempDir.appendingPathComponent(filename)
        
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("保存临时音频文件失败: \(error)")
            return nil
        }
    }
    
    // 添加对文件协调器的支持
    func scene(_ scene: UIScene, willContinueUserActivityWithType userActivityType: String) {
        print("场景将继续用户活动类型: \(userActivityType)")
    }
    
    // 处理接收到的活动请求
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        print("场景继续用户活动: \(userActivity.activityType)")
        
        // 检查是否是浏览网页类型的活动
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
           let url = userActivity.webpageURL,
           MusicFileManager.shared.isSupportedAudioFile(url: url) {
            print("从NSUserActivity接收到音频文件URL: \(url)")
            importMusicFromDocuments(url)
        }
    }
    
    // 处理活动失败
    func scene(_ scene: UIScene, didFailToContinueUserActivityWithType userActivityType: String, error: Error) {
        print("场景未能继续用户活动类型: \(userActivityType), 错误: \(error)")
    }

    // 显示文档选择器导入音乐文件
    func showDocumentPicker() {
        // 支持的音频文件类型
        let supportedTypes = MusicFileManager.shared.supportedAudioTypes()
        
        // 创建文档选择器
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes)
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = true
        
        // 显示文档选择器
        window?.rootViewController?.present(documentPicker, animated: true)
    }
    
    // UIDocumentPickerDelegate方法
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        print("文档选择器选择了 \(urls.count) 个文件")
        
        // 处理每个选择的文件
        for url in urls {
            // 检查是否是支持的音频文件
            if MusicFileManager.shared.isSupportedAudioFile(url: url) {
                print("从文档选择器接收到音频文件: \(url.lastPathComponent)")
                importMusicFromDocuments(url)
            } else {
                print("不支持的文件类型: \(url.lastPathComponent)")
                showErrorAlert(message: "无法导入 \"\(url.lastPathComponent)\"，不支持此文件类型。")
            }
        }
    }
    
    // 用户取消文档选择器
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        print("文档选择器被取消")
    }
}

// 添加扩展以提供全局访问的顶层视图控制器方法
extension UIApplication {
    // 返回当前应用的顶层视图控制器
    class func getTopViewController() -> UIViewController? {
        let keyWindow = UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .compactMap { $0 as? UIWindowScene }
            .first?
            .windows
            .filter { $0.isKeyWindow }
            .first
        
        if var topController = keyWindow?.rootViewController {
            while let presentedViewController = topController.presentedViewController {
                topController = presentedViewController
            }
            
            // 输出调试信息
            print("获取到顶层视图控制器: \(type(of: topController))")
            return topController
        }
        
        return nil
    }
}

