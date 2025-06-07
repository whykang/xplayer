import Foundation
import AVFoundation
import UIKit
import UniformTypeIdentifiers
import MediaPlayer
import Combine

// 定义音乐文件操作中的错误
enum MusicError: Error {
    case unsupportedFormat
    case fileNotFound
    case fileAccessDenied
    case metadataExtractionFailed
    case fileAlreadyExists(existingSong: Song, newURL: URL)  // 修改为带参数的错误类型
    case fileCopyFailed
    case directoryCreationFailed
    
    var localizedDescription: String {
        switch self {
        case .unsupportedFormat:
            return "不支持的音频文件格式"
        case .fileNotFound:
            return "文件不存在"
        case .fileAccessDenied:
            return "无法访问文件"
        case .metadataExtractionFailed:
            return "提取音频元数据失败"
        case .fileAlreadyExists(let existingSong, _):
            return "文件已存在：\(existingSong.title) - \(existingSong.artist)"
        case .fileCopyFailed:
            return "复制文件失败"
        case .directoryCreationFailed:
            return "创建目录失败"
        }
    }
}

// 歌词行结构体
public struct LyricLine: Identifiable, Hashable {
    public let id = UUID()
    public let timeTag: TimeInterval  // 时间标签，单位为秒
    public let text: String           // 歌词文本
    
    // 用于Hashable协议
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: LyricLine, rhs: LyricLine) -> Bool {
        return lhs.id == rhs.id
    }
}

class MusicFileManager: NSObject, ObservableObject {
    public static let shared = MusicFileManager()
    
    private let documentsDirectory: URL
    private let musicDirectory: URL
    private let lyricsDirectory: URL
    
    // 定义支持的音频格式扩展名
    private let supportedExtensions = ["mp3", "wav", "aiff", "m4a", "mp4", "flac", "alac", "aac", "ogg", "wma"]
    
    public override init() {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        documentsDirectory = paths[0]
        musicDirectory = documentsDirectory.appendingPathComponent("Music", isDirectory: true)
        lyricsDirectory = documentsDirectory.appendingPathComponent("Lyrics", isDirectory: true)
        
        super.init()
        
        createMusicDirectoryIfNeeded()
        createLyricsDirectoryIfNeeded()
    }
    
    private func createMusicDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: musicDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: musicDirectory, withIntermediateDirectories: true)
            } catch let error {
                print("创建音乐目录失败: \(error)")
            }
        }
    }
    
    private func createLyricsDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: lyricsDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: lyricsDirectory, withIntermediateDirectories: true)
            } catch let error {
                print("创建歌词目录失败: \(error)")
            }
        }
    }
    
    // 返回支持的音频文件类型
    func supportedAudioTypes() -> [UTType] {
        var types: [UTType] = [
            UTType.mp3,
            UTType.wav,
            UTType.aiff,
            UTType.mpeg4Audio,
            UTType.mpeg4Movie
        ]
        
        // 添加FLAC
        if let flacType = UTType(filenameExtension: "flac") {
            types.append(flacType)
        }
        
        // 添加ALAC/Apple Lossless
        if let alacType = UTType(filenameExtension: "alac") {
            types.append(alacType)
        }
        
        // 添加AAC
        if let aacType = UTType(filenameExtension: "aac") {
            types.append(aacType)
        }
        
        // 添加OGG
        if let oggType = UTType(filenameExtension: "ogg") {
            types.append(oggType)
        }
        
        // 添加WMA
        if let wmaType = UTType(filenameExtension: "wma") {
            types.append(wmaType)
        }
        
        return types
    }
    
    // 获取音乐目录
    func getMusicDirectory() -> URL? {
        // 确保目录存在
        if !FileManager.default.fileExists(atPath: musicDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: musicDirectory, withIntermediateDirectories: true)
                print("创建音乐目录: \(musicDirectory.path)")
            } catch {
                print("创建音乐目录失败: \(error)")
                return nil
            }
        }
        return musicDirectory
    }
    
    // 检查文件是否为支持的音频类型
    func isSupportedAudioFile(url: URL) -> Bool {
        // 检查文件扩展名
        let fileExtension = url.pathExtension.lowercased()
        if supportedExtensions.contains(fileExtension) {
            return true
        }
        
        // 备选：使用UTType检查
        guard let fileType = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
              let utType = UTType(fileType) else {
            return false
        }
        
        return supportedAudioTypes().contains { utType.conforms(to: $0) }
    }
    
    // 提取音频文件元数据
    func extractMetadata(from audioFileURL: URL, completion: @escaping (Result<Song, Error>) -> Void) {
        // 处理安全访问权限
        let secureAccess = audioFileURL.startAccessingSecurityScopedResource()
        
        // 确保在函数结束时停止访问
        defer {
            if secureAccess {
                audioFileURL.stopAccessingSecurityScopedResource()
            }
        }
        
        // 使用当前时间作为导入时间，而不是文件创建日期
        let importDate = Date()
        
        // 获取文件大小
        var fileSize: Int64 = 0
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: audioFileURL.path)
            if let size = attributes[.size] as? NSNumber {
                fileSize = size.int64Value
            }
        } catch {
            print("获取文件大小失败: \(error)")
        }
        
        // 检查是否是FLAC文件
        if audioFileURL.pathExtension.lowercased() == "flac" {
            // 使用专门的FLAC元数据提取方法，传入当前时间作为创建日期
            extractFlacMetadata(from: audioFileURL, fileSize: fileSize, creationDate: importDate) { result in
                switch result {
                case .success(var song):
                    // 如果没有获取到专辑艺术家，使用艺术家信息
                    if song.albumArtist == "未知艺术家" && song.artist != "未知艺术家" {
                        song.albumArtist = song.artist
                        completion(.success(song))
                    } else {
                        completion(.success(song))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
            return
        }
        
        let asset = AVAsset(url: audioFileURL)
        
        // 获取文件名（不含扩展名）
        let filename = audioFileURL.deletingPathExtension().lastPathComponent
        
        // 初始化默认值
        var title = filename
        var artist = "未知艺术家"
        var albumName = "未知专辑"
        var albumArtist = "未知艺术家"
        var composer = ""
        var genre = ""
        var year: Int? = nil
        var trackNumber: Int? = nil
        var artworkData: Data? = nil
        var lyrics = ""
        var duration: TimeInterval = 0
        
        // 加载元数据
        asset.loadValuesAsynchronously(forKeys: ["metadata", "duration"]) {
            // 尝试获取时长
            var error: NSError?
            let status = asset.statusOfValue(forKey: "duration", error: &error)
            if status == .loaded {
                duration = CMTimeGetSeconds(asset.duration)
            }
            
            // 先尝试从AVAsset元数据中提取
            self.extractID3Metadata(from: asset, title: &title, artist: &artist, albumName: &albumName, 
                                  albumArtist: &albumArtist, composer: &composer, genre: &genre, 
                                  year: &year, trackNumber: &trackNumber, artworkData: &artworkData, lyrics: &lyrics)
            
            // 如果没有艺术家信息，尝试从MediaPlayer中获取
            if artist == "未知艺术家" || albumName == "未知专辑" {
                self.extractMPMediaMetadata(from: audioFileURL, title: &title, artist: &artist, 
                                          albumName: &albumName, albumArtist: &albumArtist, composer: &composer, 
                                          genre: &genre, year: &year, trackNumber: &trackNumber, artworkData: &artworkData)
            }
            
            // 如果没有获取到专辑艺术家，使用艺术家信息
            if albumArtist == "未知艺术家" && artist != "未知艺术家" {
                albumArtist = artist
            }
            
            // 如果还没有专辑封面，尝试在同一目录查找
            if artworkData == nil {
                // 只有当智能封面匹配功能开启时才尝试查找封面
                if MusicLibrary.shared.enableSmartCoverMatching {
                    print("智能封面匹配已开启，尝试查找FLAC文件封面图片")
                    artworkData = self.findAlbumArtInFolder(audioFileURL: audioFileURL)
                } else {
                    print("智能封面匹配已关闭，跳过查找FLAC文件封面图片")
                }
            }
            
            // 创建新的 Song 对象，使用当前时间作为创建日期
            var song = Song(
                title: title,
                artist: artist,
                albumName: albumName,
                duration: duration,
                fileURL: audioFileURL,
                albumArtist: albumArtist,
                composer: composer,
                genre: genre,
                year: year,
                trackNumber: trackNumber,
                lyrics: lyrics,
                fileSize: fileSize,
                creationDate: importDate
            )
            
            // 如果存在封面图片，保存并设置URL
            if let artworkData = artworkData {
                let artworkURL = self.saveArtwork(artworkData, for: title)
                song.coverImagePath = artworkURL?.path
            }
            
            // 如果存在歌词，保存并设置URL
            if !lyrics.isEmpty {
                let lyricsPath = self.saveLyrics(lyrics, for: song)
                if let path = lyricsPath {
                    song.lyricsFilePath = path
                }
            }
            
            completion(.success(song))
        }
    }
    
    // 只提取元数据而不导入文件
    func extractMetadataOnly(from url: URL, completion: @escaping (Result<Song, Error>) -> Void) {
        // 确保是支持的音频文件
        guard isSupportedAudioFile(url: url) else {
            let error = NSError(domain: "MusicFileManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "不支持的音频文件格式"])
            completion(.failure(error))
            return
        }
        
        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: url.path) else {
            let error = NSError(domain: "MusicFileManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "文件不存在"])
            completion(.failure(error))
            return
        }
        
        // 使用当前时间作为导入时间
        let importDate = Date()
        
        // 检查是否是FLAC文件
        if url.pathExtension.lowercased() == "flac" {
            // 为FLAC文件使用专门的提取方法
            extractFlacMetadata(from: url, creationDate: importDate) { result in
                completion(result)
            }
            return
        }
        
        let asset = AVAsset(url: url)
        
        // 获取文件名（不含扩展名）
        let filename = url.deletingPathExtension().lastPathComponent
        
        // 初始化默认值
        var title = filename
        var artist = "未知艺术家"
        var albumName = "未知专辑"
        var albumArtist = "未知艺术家"
        var composer = ""
        var genre = ""
        var year: Int? = nil
        var trackNumber: Int? = nil
        var artworkData: Data? = nil
        var lyrics = ""
        var duration: TimeInterval = 0
        
        // 加载元数据
        asset.loadValuesAsynchronously(forKeys: ["metadata", "duration"]) {
            // 尝试获取时长
            var error: NSError?
            let status = asset.statusOfValue(forKey: "duration", error: &error)
            if status == .loaded {
                duration = CMTimeGetSeconds(asset.duration)
            }
            
            // 提取元数据
            self.extractID3Metadata(from: asset, title: &title, artist: &artist, albumName: &albumName, 
                                   albumArtist: &albumArtist, composer: &composer, genre: &genre, 
                                   year: &year, trackNumber: &trackNumber, artworkData: &artworkData, lyrics: &lyrics)
            
            // 如果没有获取到专辑艺术家，使用艺术家信息
            if albumArtist == "未知艺术家" && artist != "未知艺术家" {
                albumArtist = artist
            }
            
            // 创建Song对象，但只是为了预览，所以不保存封面等额外文件
            let song = Song(
                title: title,
                artist: artist,
                albumName: albumName,
                duration: duration,
                fileURL: url, 
                albumArtist: albumArtist,
                composer: composer,
                genre: genre,
                year: year,
                trackNumber: trackNumber,
                lyrics: lyrics,
                creationDate: importDate  // 使用当前日期
            )
            
            completion(.success(song))
        }
    }
    
    // 检查歌曲在音乐库中是否已存在
    func checkIfSongExists(url: URL, completion: @escaping (Bool, Song?) -> Void) {
        // 获取文件名（不含扩展名）
        let fileNameWithoutExt = url.deletingPathExtension().lastPathComponent
        
        // 处理安全访问权限
        let secureAccess = url.startAccessingSecurityScopedResource()
        
        // 确保在函数结束时停止访问
        defer {
            if secureAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // 获取当前音乐库中的所有歌曲
        let existingSongs = MusicLibrary.shared.songs
        
        // 直接路径匹配：检查是否已经有相同路径的歌曲
        if let matchingSong = existingSongs.first(where: { $0.fileURL?.lastPathComponent == url.lastPathComponent }) {
            print("找到完全匹配的歌曲: \(matchingSong.title)")
            completion(true, matchingSong)
            return
        }
        
        // 如果没有完全匹配，尝试提取元数据进行比较
        extractMetadata(from: url) { [weak self] result in
            guard let self = self else {
                completion(false, nil)
                return
            }
            
            switch result {
            case .success(let newSong):
                // 基于标题和艺术家进行匹配
                for existingSong in existingSongs {
                    // 如果标题和艺术家都匹配（忽略大小写）
                    if existingSong.title.lowercased() == newSong.title.lowercased() &&
                       existingSong.artist.lowercased() == newSong.artist.lowercased() {
                        print("发现匹配的歌曲: \(newSong.title) - \(newSong.artist)")
                        completion(true, existingSong)
                        return
                    }
                    
                    // 检查文件名是否包含在现有歌曲标题中（或反之）
                    if existingSong.title.lowercased().contains(fileNameWithoutExt.lowercased()) ||
                       fileNameWithoutExt.lowercased().contains(existingSong.title.lowercased()) {
                        // 如果艺术家也匹配或者为"未知艺术家"
                        if existingSong.artist.lowercased() == newSong.artist.lowercased() ||
                           existingSong.artist == "未知艺术家" || newSong.artist == "未知艺术家" {
                            print("发现部分匹配: \(existingSong.title) 与 \(fileNameWithoutExt)")
                            completion(true, existingSong)
                            return
                        }
                    }
                }
                
                // 没有找到匹配
                completion(false, nil)
            case .failure(let error):
                print("提取元数据失败: \(error)")
                completion(false, nil)
            }
        }
    }
    
    // 原来的同步方法，保留兼容性
    func checkIfSongExists(url: URL) -> (exists: Bool, existingSong: Song?) {
        // 创建信号量用于同步等待
        let semaphore = DispatchSemaphore(value: 0)
        var result: (exists: Bool, existingSong: Song?) = (false, nil)
        
        // 调用异步版本
        checkIfSongExists(url: url) { exists, song in
            result = (exists, song)
            semaphore.signal()
        }
        
        // 等待异步操作完成
        _ = semaphore.wait(timeout: .now() + 10) // 设置超时时间为10秒
        
        return result
    }
    
    // 导入音乐文件，添加参数控制是否强制导入
    func importMusicFile(from url: URL, forcedImport: Bool = false, completion: @escaping (Result<Song, Error>) -> Void) {
        // 确保是支持的音频文件
        guard isSupportedAudioFile(url: url) else {
            completion(.failure(MusicError.unsupportedFormat))
            return
        }
        
        // 检查文件是否已存在，如果不是强制导入则考虑跳过
        if !forcedImport {
            // 使用异步版本检查
            checkIfSongExists(url: url) { [weak self] exists, existingSong in
                guard let self = self else {
                    completion(.failure(NSError(domain: "MusicFileManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "对象已释放"])))
                    return
                }
                
                if exists, let existingSong = existingSong {
                    // 文件已存在，返回错误信息
                    print("文件已存在，返回重复文件错误: \(url.lastPathComponent)")
                    completion(.failure(MusicError.fileAlreadyExists(existingSong: existingSong, newURL: url)))
                } else {
                    // 文件不存在，继续导入流程
                    self.continueImportMusicFile(from: url, forcedImport: forcedImport, completion: completion)
                }
            }
        } else {
            // 强制导入，直接继续导入流程
            continueImportMusicFile(from: url, forcedImport: forcedImport, completion: completion)
        }
    }
    
    // 继续导入音乐文件的流程
    private func continueImportMusicFile(from url: URL, forcedImport: Bool, completion: @escaping (Result<Song, Error>) -> Void) {
        // 获取文件信息
        let fileName = url.lastPathComponent
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let musicDirectory = documentsDirectory.appendingPathComponent("Music", isDirectory: true)
        
        // 处理安全访问权限，确保在源文件URL上有正确访问权限
        let secureAccess = url.startAccessingSecurityScopedResource()
        
        // 确保在函数结束时停止访问
        defer {
            if secureAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // 使用当前时间作为导入时间
        let importDate = Date()
        
        // 先从UserDefaults加载歌曲数据，以保留歌曲的置顶状态等信息
        var existingSongs: [Song] = []
        if let songsData = UserDefaults.standard.data(forKey: "songs"),
           let decodedSongs = try? JSONDecoder().decode([Song].self, from: songsData) {
            existingSongs = decodedSongs
            print("导入时从UserDefaults加载了\(existingSongs.count)首歌曲的数据")
        }
        
        // 确保目录存在
        do {
            if !FileManager.default.fileExists(atPath: musicDirectory.path) {
                try FileManager.default.createDirectory(at: musicDirectory, withIntermediateDirectories: true)
                print("创建了音乐目录: \(musicDirectory.path)")
            }
        } catch let error {
            print("创建音乐目录失败: \(error)")
            completion(.failure(error))
            return
        }
        
        // 目标文件路径
        let destinationURL = musicDirectory.appendingPathComponent(fileName)
        
        // 如果是强制导入，检查文件是否已存在，若存在则重命名
        if forcedImport {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                // 生成一个带时间戳的新文件名
                let fileNameWithoutExt = url.deletingPathExtension().lastPathComponent
                let fileExt = url.pathExtension
                let timestamp = Int(Date().timeIntervalSince1970)
                let newFileName = "\(fileNameWithoutExt)_\(timestamp).\(fileExt)"
                let newDestinationURL = musicDirectory.appendingPathComponent(newFileName)
                
                print("文件已存在，重命名为: \(newFileName)")
                
                // 提取元数据并复制文件
                extractMetadata(from: url) { result in
                    switch result {
                    case .success(var song):
                        do {
                            // 复制文件到新目标路径
                            try FileManager.default.copyItem(at: url, to: newDestinationURL)
                            
                                                    // 创建新的Song实例，使用相对路径和当前时间作为创建日期
                        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
                        let relativePath = String(newDestinationURL.path.dropFirst(documentsPath.count))
                        let finalRelativePath = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
                        
                        let newSong = Song(
                            id: song.id,
                            title: song.title,
                            artist: song.artist,
                            album: song.album,
                            duration: song.duration,
                            filePath: finalRelativePath,  // 使用相对路径
                            lyrics: song.lyrics,
                            coverImagePath: song.coverImagePath,
                            fileSize: song.fileSize,
                            trackNumber: song.trackNumber,
                            year: song.year,
                            albumName: song.albumName,
                            albumArtist: song.albumArtist,
                            composer: song.composer,
                            genre: song.genre,
                            lyricsFilePath: song.lyricsFilePath,
                            isPinned: song.isPinned,
                            creationDate: importDate
                        )
                            
                            // 保存到音乐库
                            DispatchQueue.main.async {
                                MusicLibrary.shared.addSong(newSong)
                                completion(.success(newSong))
                            }
                        } catch let error {
                            print("复制文件失败: \(error)")
                            completion(.failure(error))
                        }
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
                return
            }
        }
        
        // 常规导入流程
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                // 文件已存在
                extractMetadata(from: destinationURL) { result in
                    switch result {
                    case .success(let song):
                        // 创建新的Song实例，使用相对路径和当前时间作为创建日期
                        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
                        let relativePath = String(destinationURL.path.dropFirst(documentsPath.count))
                        let finalRelativePath = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
                        
                        let newSong = Song(
                            id: song.id,
                            title: song.title,
                            artist: song.artist,
                            album: song.album,
                            duration: song.duration,
                            filePath: finalRelativePath,  // 使用相对路径
                            lyrics: song.lyrics,
                            coverImagePath: song.coverImagePath,
                            fileSize: song.fileSize,
                            trackNumber: song.trackNumber,
                            year: song.year,
                            albumName: song.albumName,
                            albumArtist: song.albumArtist,
                            composer: song.composer,
                            genre: song.genre,
                            lyricsFilePath: song.lyricsFilePath,
                            isPinned: song.isPinned,
                            creationDate: importDate
                        )
                        
                        // 保存到音乐库
                        DispatchQueue.main.async {
                            MusicLibrary.shared.addSong(newSong)
                            completion(.success(newSong))
                        }
                    case .failure(let error):
                        // 删除复制过来的文件
                        try? FileManager.default.removeItem(at: destinationURL)
                        completion(.failure(error))
                    }
                }
            } else {
                // 文件不存在，复制过去
                try FileManager.default.copyItem(at: url, to: destinationURL)
                
                // 提取元数据
                extractMetadata(from: destinationURL) { result in
                    switch result {
                    case .success(var song):
                        // 创建新的Song实例，使用相对路径和当前时间作为创建日期
                        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
                        let relativePath = String(destinationURL.path.dropFirst(documentsPath.count))
                        let finalRelativePath = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
                        
                        let newSong = Song(
                            id: song.id,
                            title: song.title,
                            artist: song.artist,
                            album: song.album,
                            duration: song.duration,
                            filePath: finalRelativePath,  // 使用相对路径
                            lyrics: song.lyrics,
                            coverImagePath: song.coverImagePath,
                            fileSize: song.fileSize,
                            trackNumber: song.trackNumber,
                            year: song.year,
                            albumName: song.albumName,
                            albumArtist: song.albumArtist,
                            composer: song.composer,
                            genre: song.genre,
                            lyricsFilePath: song.lyricsFilePath,
                            isPinned: song.isPinned,
                            creationDate: importDate
                        )
                        
                        // 保存到音乐库
                        DispatchQueue.main.async {
                            MusicLibrary.shared.addSong(newSong)
                            completion(.success(newSong))
                        }
                    case .failure(let error):
                        // 删除复制过来的文件
                        try? FileManager.default.removeItem(at: destinationURL)
                        completion(.failure(error))
                    }
                }
            }
        } catch let error {
            print("导入音乐文件失败: \(error)")
            completion(.failure(error))
        }
    }
    
    // 专门用于提取FLAC文件元数据
    private func extractFlacMetadata(from fileURL: URL, fileSize: Int64 = 0, creationDate: Date = Date(), completion: @escaping (Result<Song, Error>) -> Void) {
        // 获取文件名（不含扩展名）
        let filename = fileURL.deletingPathExtension().lastPathComponent
        
        // 创建任务在后台线程处理
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // 读取文件数据
                let fileData = try Data(contentsOf: fileURL)
                
                // 使用传入的文件大小，如果没有传入则使用文件数据的大小
                var actualFileSize = fileSize
                if actualFileSize == 0 {
                    actualFileSize = Int64(fileData.count)
                }
                
                // 初始化默认值
                var title = filename
                var artist = "未知艺术家"
                var albumName = "未知专辑"
                var albumArtist = "未知艺术家"
                var composer = ""
                var genre = ""
                var year: Int? = nil
                var trackNumber: Int? = nil
                var artworkData: Data? = nil
                var lyrics = ""
                var duration: TimeInterval = 0
                
                // 检查是否是FLAC文件
                if fileData.count > 4 {
                    let header = fileData.subdata(in: 0..<4)
                    if String(data: header, encoding: .ascii) == "fLaC" {
                        // 解析FLAC元数据块
                        self.parseFlacMetadataBlocks(fileData: fileData, 
                                                    title: &title, 
                                                    artist: &artist, 
                                                    albumName: &albumName, 
                                                    albumArtist: &albumArtist,
                                                    composer: &composer,
                                                    genre: &genre,
                                                    year: &year,
                                                    trackNumber: &trackNumber,
                                                    artworkData: &artworkData,
                                                    lyrics: &lyrics,
                                                    duration: &duration)
                    }
                }
                
                // 如果解析FLAC元数据失败，尝试使用文件名提取信息
                if artist == "未知艺术家" || albumName == "未知专辑" {
                    self.extractInfoFromFileName(fileName: title, artist: &artist, albumName: &albumName)
                }
                
                // 如果没有获取到专辑艺术家，使用艺术家信息
                if albumArtist == "未知艺术家" && artist != "未知艺术家" {
                    albumArtist = artist
                }
                
                // 如果还没有专辑封面，尝试在同一目录查找
                if artworkData == nil {
                    // 只有当智能封面匹配功能开启时才尝试查找封面
                    if MusicLibrary.shared.enableSmartCoverMatching {
                        print("智能封面匹配已开启，尝试查找FLAC文件封面图片")
                        artworkData = self.findAlbumArtInFolder(audioFileURL: fileURL)
                    } else {
                        print("智能封面匹配已关闭，跳过查找FLAC文件封面图片")
                    }
                }
                
                // 如果还没有确定时长，使用一个默认值
                if duration == 0 {
                    // 尝试使用AVAsset获取时长
                    let asset = AVAsset(url: fileURL)
                    duration = CMTimeGetSeconds(asset.duration)
                    
                    // 如果仍然为0，使用默认值
                    if duration == 0 {
                        duration = 180.0 // 默认3分钟
                    }
                }
                
                // 创建新的Song对象，使用传入的当前时间作为创建日期
                var song = Song(
                    title: title,
                    artist: artist,
                    albumName: albumName,
                    duration: duration,
                    fileURL: fileURL,
                    albumArtist: albumArtist,
                    composer: composer,
                    genre: genre,
                    year: year,
                    trackNumber: trackNumber,
                    lyrics: lyrics,
                    fileSize: actualFileSize,
                    creationDate: creationDate  // 使用传入的时间，extractMetadata已修改为传递当前时间
                )
                
                // 保存专辑封面
                if let artworkData = artworkData {
                    let artworkURL = self.saveArtwork(artworkData, for: title)
                    song.coverImagePath = artworkURL?.path
                }
                
                // 如果存在歌词，保存并设置URL
                if !lyrics.isEmpty {
                    let lyricsPath = self.saveLyrics(lyrics, for: song)
                    if let path = lyricsPath {
                        song.lyricsFilePath = path
                    }
                }
                
                // 返回结果
                DispatchQueue.main.async {
                    completion(.success(song))
                }
                
            } catch let error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // 解析FLAC元数据块
    private func parseFlacMetadataBlocks(fileData: Data, title: inout String, artist: inout String, albumName: inout String, 
                                        albumArtist: inout String, composer: inout String, genre: inout String,
                                        year: inout Int?, trackNumber: inout Int?, artworkData: inout Data?,
                                        lyrics: inout String, duration: inout TimeInterval) {
        // FLAC元数据块从文件头的第8个字节开始
        var offset = 4
        
        // 解析每个元数据块
        while offset < fileData.count - 4 { // 确保至少有4个字节可供读取
            // 读取元数据块头
            let blockHeader = fileData[offset]
            let isLastBlock = (blockHeader & 0x80) != 0
            let blockType = blockHeader & 0x7F
            
            // 读取块长度
            guard offset + 4 <= fileData.count else { break }
            let length = Int(fileData[offset + 1]) << 16 | Int(fileData[offset + 2]) << 8 | Int(fileData[offset + 3])
            
            // 检查长度是否有效
            guard length <= fileData.count - (offset + 4) else { break }
            
            offset += 4
            
            // 处理不同类型的元数据块
            switch blockType {
            case 0: // STREAMINFO块
                if length >= 18 {
                    // 从STREAMINFO块中提取总样本数和采样率，计算时长
                    let minBlockSize = UInt16(fileData[offset]) << 8 | UInt16(fileData[offset + 1])
                    let maxBlockSize = UInt16(fileData[offset + 2]) << 8 | UInt16(fileData[offset + 3])
                    let minFrameSize = UInt32(fileData[offset + 4]) << 16 | UInt32(fileData[offset + 5]) << 8 | UInt32(fileData[offset + 6])
                    let maxFrameSize = UInt32(fileData[offset + 7]) << 16 | UInt32(fileData[offset + 8]) << 8 | UInt32(fileData[offset + 9])
                    
                    // 采样率是20位，存储在offset+10、offset+11和offset+12的前4位
                    let sampleRateBits = UInt32(fileData[offset + 10]) << 12 | UInt32(fileData[offset + 11]) << 4 | (UInt32(fileData[offset + 12]) >> 4)
                    let channelBits = (UInt8(fileData[offset + 12]) & 0x0E) >> 1
                    let channels = channelBits + 1
                    
                    // 位深度
                    let bitsPerSampleBits = ((UInt8(fileData[offset + 12]) & 0x01) << 4) | (UInt8(fileData[offset + 13]) >> 4)
                    let bitsPerSample = bitsPerSampleBits + 1
                    
                    // 总样本数
                    let totalSamples = (UInt64(fileData[offset + 13] & 0x0F) << 32) | 
                                      (UInt64(fileData[offset + 14]) << 24) | 
                                      (UInt64(fileData[offset + 15]) << 16) | 
                                      (UInt64(fileData[offset + 16]) << 8) | 
                                       UInt64(fileData[offset + 17])
                    
                    // 计算时长
                    if sampleRateBits > 0 && totalSamples > 0 {
                        duration = Double(totalSamples) / Double(sampleRateBits)
                    }
                }
                
            case 4: // VORBIS_COMMENT块
                // 这是FLAC中存储歌曲元数据的主要块
                if length > 8 {
                    var blockOffset = offset
                    
                    // 读取vendor length
                    let vendorLength = Int(fileData[blockOffset]) | Int(fileData[blockOffset + 1]) << 8 | 
                                      Int(fileData[blockOffset + 2]) << 16 | Int(fileData[blockOffset + 3]) << 24
                    blockOffset += 4 + vendorLength
                    
                    // 读取评论数量
                    guard blockOffset + 4 <= offset + length else { break }
                    let commentCount = Int(fileData[blockOffset]) | Int(fileData[blockOffset + 1]) << 8 | 
                                      Int(fileData[blockOffset + 2]) << 16 | Int(fileData[blockOffset + 3]) << 24
                    blockOffset += 4
                    
                    // 遍历每个评论
                    for _ in 0..<commentCount {
                        guard blockOffset + 4 <= offset + length else { break }
                        
                        // 读取评论长度
                        let commentLength = Int(fileData[blockOffset]) | Int(fileData[blockOffset + 1]) << 8 | 
                                           Int(fileData[blockOffset + 2]) << 16 | Int(fileData[blockOffset + 3]) << 24
                        blockOffset += 4
                        
                        // 确保评论长度有效
                        guard commentLength > 0, blockOffset + commentLength <= offset + length else { break }
                        
                        // 读取评论字符串
                        if let commentStr = String(data: fileData.subdata(in: blockOffset..<(blockOffset + commentLength)), encoding: .utf8) {
                            // 按"="分割键值对
                            let parts = commentStr.split(separator: "=", maxSplits: 1)
                            if parts.count == 2 {
                                let key = String(parts[0]).uppercased()
                                let value = String(parts[1])
                                
                                // 根据键设置相应的元数据
                                switch key {
                                case "TITLE":
                                    title = value
                                case "ARTIST":
                                    artist = value
                                case "ALBUM":
                                    albumName = value
                                case "ALBUMARTIST":
                                    albumArtist = value
                                case "COMPOSER":
                                    composer = value
                                case "GENRE":
                                    genre = value
                                case "DATE", "YEAR":
                                    if let yearValue = Int(value.prefix(4)) {
                                        year = yearValue
                                    }
                                case "TRACKNUMBER":
                                    if let trackString = value.components(separatedBy: "/").first,
                                       let number = Int(trackString) {
                                        trackNumber = number
                                    }
                                case "LYRICS":
                                    lyrics = value
                                default:
                                    break
                                }
                            }
                        }
                        
                        blockOffset += commentLength
                    }
                }
                
            case 6: // PICTURE块
                // 这个块包含专辑封面
                if length > 32 {
                    var pictureOffset = offset
                    
                    // 读取图片类型
                    let pictureType = (UInt32(fileData[pictureOffset]) << 24) | (UInt32(fileData[pictureOffset + 1]) << 16) | 
                                     (UInt32(fileData[pictureOffset + 2]) << 8) | UInt32(fileData[pictureOffset + 3])
                    pictureOffset += 4
                    
                    // 读取MIME类型长度
                    let mimeLength = (UInt32(fileData[pictureOffset]) << 24) | (UInt32(fileData[pictureOffset + 1]) << 16) | 
                                    (UInt32(fileData[pictureOffset + 2]) << 8) | UInt32(fileData[pictureOffset + 3])
                    pictureOffset += 4
                    
                    // 跳过MIME类型
                    pictureOffset += Int(mimeLength)
                    
                    // 检查是否还有足够的数据
                    guard pictureOffset + 4 < offset + length else { break }
                    
                    // 读取描述长度
                    let descLength = (UInt32(fileData[pictureOffset]) << 24) | (UInt32(fileData[pictureOffset + 1]) << 16) | 
                                    (UInt32(fileData[pictureOffset + 2]) << 8) | UInt32(fileData[pictureOffset + 3])
                    pictureOffset += 4
                    
                    // 跳过描述
                    pictureOffset += Int(descLength)
                    
                    // 检查是否还有足够的数据
                    guard pictureOffset + 16 < offset + length else { break }
                    
                    // 跳过宽度、高度、色深度和颜色数
                    pictureOffset += 16
                    
                    // 读取图片数据长度
                    let dataLength = (UInt32(fileData[pictureOffset]) << 24) | (UInt32(fileData[pictureOffset + 1]) << 16) | 
                                    (UInt32(fileData[pictureOffset + 2]) << 8) | UInt32(fileData[pictureOffset + 3])
                    pictureOffset += 4
                    
                    // 检查数据长度是否有效
                    guard dataLength > 0, pictureOffset + Int(dataLength) <= offset + length else { break }
                    
                    // 读取图片数据
                    artworkData = fileData.subdata(in: pictureOffset..<(pictureOffset + Int(dataLength)))
                }
                
            default:
                break
            }
            
            offset += length
            
            // 如果是最后一个块，结束循环
            if isLastBlock {
                break
            }
        }
    }
    
    // 从文件名中提取艺术家和专辑信息
    private func extractInfoFromFileName(fileName: String, artist: inout String, albumName: inout String) {
        // 常见的文件名格式：艺术家 - 歌曲名.flac 或 艺术家-歌曲名.flac
        let patterns = [" - ", "-", "_", "–"]
        
        for pattern in patterns {
            let components = fileName.components(separatedBy: pattern)
            if components.count >= 2 {
                // 假设第一部分是艺术家，其余是歌曲名
                if artist == "未知艺术家" {
                    artist = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                }
                break
            }
        }
        
        // 对于专辑名，我们可以尝试使用歌曲文件所在的目录名
        if albumName == "未知专辑", let fileURL = Song.examples.first?.fileURL {
            let dirName = fileURL.deletingLastPathComponent().lastPathComponent
            if !dirName.isEmpty && dirName != "Music" {
                albumName = dirName
            }
        }
    }
    
    // 从ID3/MP4等标签中提取元数据
    private func extractID3Metadata(from asset: AVAsset, title: inout String, artist: inout String, albumName: inout String, 
                                   albumArtist: inout String, composer: inout String, genre: inout String, 
                                   year: inout Int?, trackNumber: inout Int?, artworkData: inout Data?, lyrics: inout String) {
        // 常规元数据
        for item in asset.metadata {
            if let key = item.commonKey?.rawValue {
                switch key {
                case AVMetadataKey.commonKeyTitle.rawValue:
                    if let value = item.stringValue, !value.isEmpty {
                        title = value
                    }
                case AVMetadataKey.commonKeyArtist.rawValue:
                    if let value = item.stringValue, !value.isEmpty {
                        artist = value
                    }
                case AVMetadataKey.commonKeyAlbumName.rawValue:
                    if let value = item.stringValue, !value.isEmpty {
                        albumName = value
                    }
                case AVMetadataKey.commonKeyArtwork.rawValue:
                    artworkData = item.dataValue
                default:
                    break
                }
            }
        }
        
        // 处理所有元数据，不按格式区分
        // AVFoundation不提供特定格式的元数据访问方式，直接使用所有元数据
        processFormatMetadata(asset.metadata, albumArtist: &albumArtist, composer: &composer, 
                             genre: &genre, year: &year, trackNumber: &trackNumber, lyrics: &lyrics)
    }
    
    // 处理特定格式的元数据
    private func processFormatMetadata(_ metadata: [AVMetadataItem], albumArtist: inout String, composer: inout String, 
                                      genre: inout String, year: inout Int?, trackNumber: inout Int?, lyrics: inout String) {
        for item in metadata {
            let keySpace = item.keySpace?.rawValue ?? ""
            let key = item.key as? String ?? ""
            let fullKey = "\(keySpace).\(key)"
            
            switch fullKey {
            // ID3v2 标签 - 专辑艺术家
            case "org.id3.TPE2":
                if let value = item.stringValue, !value.isEmpty {
                    albumArtist = value
                }
            // ID3v2 标签 - 作曲家
            case "org.id3.TCOM":
                if let value = item.stringValue, !value.isEmpty {
                    composer = value
                }
            // ID3v2 标签 - 流派
            case "org.id3.TCON":
                if let value = item.stringValue, !value.isEmpty {
                    genre = value
                }
            // ID3v2 标签 - 年份
            case "org.id3.TYER", "org.id3.TDRC":
                if let value = item.stringValue, !value.isEmpty {
                    if let yearValue = Int(value.prefix(4)) {
                        year = yearValue
                    }
                }
            // ID3v2 标签 - 歌曲编号
            case "org.id3.TRCK":
                if let value = item.stringValue, !value.isEmpty {
                    if let trackString = value.components(separatedBy: "/").first,
                       let number = Int(trackString) {
                        trackNumber = number
                    }
                }
            // ID3v2 标签 - 歌词
            case "org.id3.USLT":
                if let value = item.stringValue, !value.isEmpty {
                    lyrics = value
                }
            // iTunes 标签
            case "com.apple.iTunes.album_artist":
                if let value = item.stringValue, !value.isEmpty {
                    albumArtist = value
                }
            // QuickTime 标签
            case "com.apple.quicktime.composer":
                if let value = item.stringValue, !value.isEmpty {
                    composer = value
                }
            default:
                break
            }
        }
    }
    
    // 使用MediaPlayer框架提取元数据
    private func extractMPMediaMetadata(from audioFileURL: URL, title: inout String, artist: inout String, albumName: inout String, 
                                       albumArtist: inout String, composer: inout String, genre: inout String, 
                                       year: inout Int?, trackNumber: inout Int?, artworkData: inout Data?) {
        // 尝试在媒体库中查找匹配的歌曲
        let predicate = MPMediaPropertyPredicate(value: audioFileURL.lastPathComponent, 
                                                forProperty: MPMediaItemPropertyTitle, 
                                                comparisonType: .contains)
        
        let query = MPMediaQuery()
        query.addFilterPredicate(predicate)
        
        if let items = query.items, let item = items.first {
            // 标题
            if let itemTitle = item.title, !itemTitle.isEmpty {
                title = itemTitle
            }
            
            // 艺术家
            if let itemArtist = item.artist, !itemArtist.isEmpty {
                artist = itemArtist
            }
            
            // 专辑
            if let itemAlbum = item.albumTitle, !itemAlbum.isEmpty {
                albumName = itemAlbum
            }
            
            // 专辑艺术家
            if let itemAlbumArtist = item.albumArtist, !itemAlbumArtist.isEmpty {
                albumArtist = itemAlbumArtist
            }
            
            // 作曲家
            if let itemComposer = item.composer, !itemComposer.isEmpty {
                composer = itemComposer
            }
            
            // 流派
            if let itemGenre = item.genre, !itemGenre.isEmpty {
                genre = itemGenre
            }
            
            // 年份
            if let itemYear = item.value(forProperty: MPMediaItemPropertyReleaseDate) as? Date {
                let calendar = Calendar.current
                year = calendar.component(.year, from: itemYear)
            }
            
            // 曲目编号
            trackNumber = item.albumTrackNumber
            
            // 专辑封面
            if let artwork = item.artwork {
                let size = CGSize(width: 500, height: 500)
                if let image = artwork.image(at: size) {
                    artworkData = image.jpegData(compressionQuality: 0.8)
                }
            }
        }
    }
    
    // 在音频文件所在文件夹中查找专辑封面，如果没找到则尝试从网络获取
    private func findAlbumArtInFolder(audioFileURL: URL) -> Data? {
        // 获取文件所在目录
        let directory = audioFileURL.deletingLastPathComponent()
        
        // 处理安全访问权限
        let secureAccess = directory.startAccessingSecurityScopedResource()
        
        // 确保在函数结束时停止访问
        defer {
            if secureAccess {
                directory.stopAccessingSecurityScopedResource()
            }
        }
        
        // 常见的封面文件名
        let coverNames = ["cover", "folder", "album", "front", "artwork", "albumart"]
        let imageExtensions = ["jpg", "jpeg", "png", "bmp", "gif"]
        
        do {
            // 获取目录中的所有文件
            let fileURLs = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            
            // 先查找常见的封面文件名
            for coverName in coverNames {
                for ext in imageExtensions {
                    if let coverURL = fileURLs.first(where: { $0.lastPathComponent.lowercased().contains(coverName) && $0.pathExtension.lowercased() == ext }) {
                        do {
                            // 对图片文件也使用安全访问
                            let coverSecureAccess = coverURL.startAccessingSecurityScopedResource()
                            defer {
                                if coverSecureAccess {
                                    coverURL.stopAccessingSecurityScopedResource()
                                }
                            }
                            
                            return try Data(contentsOf: coverURL)
                        } catch {
                            print("读取封面图片文件失败: \(error)")
                        }
                    }
                }
            }
            
            // 如果没找到常见的封面文件，查找任何图片文件
            for ext in imageExtensions {
                if let imageURL = fileURLs.first(where: { $0.pathExtension.lowercased() == ext }) {
                    do {
                        // 对图片文件也使用安全访问
                        let imageSecureAccess = imageURL.startAccessingSecurityScopedResource()
                        defer {
                            if imageSecureAccess {
                                imageURL.stopAccessingSecurityScopedResource()
                            }
                        }
                        
                        return try Data(contentsOf: imageURL)
                    } catch {
                        print("读取图片文件失败: \(error)")
                    }
                }
            }
        } catch {
            print("读取目录内容失败: \(error)")
        }
        
        // 如果没有找到封面，提取艺术家、专辑和歌曲名称信息
        var artist = "未知艺术家"
        var album = "未知专辑" 
        var title = audioFileURL.deletingPathExtension().lastPathComponent // 默认使用文件名作为歌曲名称
        
        // 检查元数据中是否已经有艺术家和专辑信息
        let asset = AVAsset(url: audioFileURL)
        let metadata = asset.metadata
        
        for item in metadata {
            if let key = item.commonKey?.rawValue {
                if key == "artist" || key == "albumArtist", let value = item.stringValue {
                    artist = value
                } else if key == "albumName", let value = item.stringValue {
                    album = value
                } else if key == "title", let value = item.stringValue {
                    title = value
                }
            }
        }
        
        // 如果元数据中没有找到，尝试从文件名解析
        let fileName = audioFileURL.deletingPathExtension().lastPathComponent
        if artist == "未知艺术家" || album == "未知专辑" || title == fileName {
            if fileName.contains(" - ") {
                let components = fileName.components(separatedBy: " - ")
                if components.count >= 2 {
                    if artist == "未知艺术家" {
                        artist = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if title == fileName && components.count > 1 {
                        title = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if album == "未知专辑" && components.count > 2 {
                        album = components[2].trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            } else if fileName.contains("-") {
                let components = fileName.components(separatedBy: "-")
                if components.count >= 2 {
                    if artist == "未知艺术家" {
                        artist = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if title == fileName && components.count > 1 {
                        title = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if album == "未知专辑" && components.count > 2 {
                        album = components[2].trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }
        
        print("🔍 提取到的信息 - 艺术家: \"\(artist)\", 歌曲: \"\(title)\", 专辑: \"\(album)\"")
        
        // 检查本地缓存中是否已有该专辑的封面
        if let cachedCoverData = getLocalAlbumCover(artist: artist, album: album) {
            print("✅ 从本地缓存加载专辑封面")
            return cachedCoverData
        }
        
        // 本地未找到封面，检查是否允许从网络获取
        print("⚠️ 本地缓存中未找到专辑封面")
        
        // 检查用户是否开启了智能封面匹配功能
        if UserSettings.shared.autoFetchLyrics && MusicLibrary.shared.enableSmartCoverMatching {
            print("📱 智能封面匹配已开启，尝试从网络获取封面")
            if artist != "未知艺术家" {
                return fetchAlbumCoverFromNetwork(artist: artist, title: title, album: album)
            }
        } else {
            print("🚫 智能封面匹配已关闭，跳过网络获取")
        }
        
        return nil
    }
    
    // 从网络获取专辑封面
    public func fetchAlbumCoverFromNetwork(artist: String, title: String, album: String) -> Data? {
        print("👉 开始从网络获取专辑封面 - 艺术家: \"\(artist)\", 歌曲: \"\(title)\", 专辑: \"\(album)\"")
        
        // 构建查询参数 (歌手名称+空格+歌曲名称)
        let queryString = "\(artist) \(title)"
        
        // 对查询参数进行URL编码
        guard let encodedQuery = queryString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            print("❌ URL编码失败 - 无法对查询参数进行编码")
            return nil
        }
        
        // 构建API请求URL 需要自己实现
        let apiUrlString = ""
        guard let apiUrl = URL(string: apiUrlString) else {
            print("❌ 无效的API URL: \(apiUrlString)")
            return nil
        }
        
        print("🌐 请求专辑封面API: \(apiUrlString)")
        print("🔍 查询参数: 艺术家名称+空格+歌曲名称 = \"\(queryString)\"")
        
        // 使用信号量确保同步执行
        let semaphore = DispatchSemaphore(value: 0)
        var imageData: Data? = nil
        
        // 发起网络请求
        let task = URLSession.shared.dataTask(with: apiUrl) { data, response, error in
            defer {
                semaphore.signal()
            }
            
            // 打印HTTP状态码和响应头
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 HTTP状态码: \(httpResponse.statusCode)")
                if httpResponse.statusCode != 200 {
                    print("⚠️ 请求返回非200状态码: \(httpResponse.statusCode)")
                }
            }
            
            if let error = error {
                print("❌ 网络请求错误: \(error.localizedDescription)")
                if let nsError = error as NSError? {
                    print("  错误代码: \(nsError.code), 域: \(nsError.domain)")
                    if let failureReason = nsError.localizedFailureReason {
                        print("  失败原因: \(failureReason)")
                    }
                }
                return
            }
            
            guard let data = data else {
                print("❌ API返回空数据")
                return
            }
            
            print("✅ 收到API响应，数据大小: \(data.count) 字节")
            
            // 解析JSON响应
            do {
                if let jsonStr = String(data: data, encoding: .utf8) {
                    print("📄 API原始响应: \(jsonStr)")
                }
                
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("🔍 解析JSON成功: \(json)")
                    
                    // 检查是否有web_albumpic_short字段
                    if let imageUrl = json["web_albumpic_short"] as? String {
                        print("🎯 找到专辑封面URL: \(imageUrl)")
                        
                        // 使用返回的完整图片URL (不需要拼接)
                        guard let url = URL(string: imageUrl) else {
                            print("❌ 无效的图片URL: \(imageUrl)")
                            return
                        }
                        
                        print("📥 开始下载图片: \(imageUrl)")
                        
                        // 下载图片
                        do {
                            let startTime = Date()
                            imageData = try Data(contentsOf: url)
                            let downloadTime = Date().timeIntervalSince(startTime)
                            
                            if let imageData = imageData {
                                print("✅ 成功下载专辑封面图片，大小: \(imageData.count) 字节，耗时: \(String(format: "%.2f", downloadTime))秒")
                                
                                // 保存到本地缓存
                                self.saveAlbumCoverToCache(data: imageData, artist: artist, album: album)
                            }
                        } catch {
                            print("❌ 下载图片失败: \(error.localizedDescription)")
                            if let nsError = error as NSError? {
                                print("  错误代码: \(nsError.code), 域: \(nsError.domain)")
                                if let failureReason = nsError.localizedFailureReason {
                                    print("  失败原因: \(failureReason)")
                                }
                            }
                        }
                    } else {
                        print("⚠️ 没有找到专辑封面信息，缺少 'web_albumpic_short' 字段")
                        print("  返回的JSON字段: \(json.keys.joined(separator: ", "))")
                    }
                } else {
                    print("❌ 无法将数据解析为JSON字典")
                }
            } catch {
                print("❌ 解析JSON失败: \(error.localizedDescription)")
                if let jsonStr = String(data: data, encoding: .utf8) {
                    print("  收到的非JSON数据: \(jsonStr)")
                } else {
                    print("  收到的数据无法解析为字符串")
                }
            }
        }
        
        print("⏳ 等待网络请求完成...")
        task.resume()
        
        // 等待异步操作完成（设置超时时间为5秒）
        let waitResult = semaphore.wait(timeout: .now() + 5)
        if waitResult == .timedOut {
            print("⚠️ 网络请求超时（5秒）")
            task.cancel()
        }
        
        if imageData != nil {
            print("✅ 封面获取成功，返回图片数据")
        } else {
            print("⚠️ 未能获取封面图片数据")
        }
        
        return imageData
    }
    
    // 保存专辑封面到本地缓存
    private func saveAlbumCoverToCache(data: Data, artist: String, album: String) {
        let localPath = getLocalAlbumCoverPath(artist: artist, album: album)
        
        do {
            try data.write(to: localPath)
            print("💾 专辑封面已保存到本地: \(localPath.path)")
        } catch {
            print("❌ 保存专辑封面到本地失败: \(error.localizedDescription)")
        }
    }
    
    // 查找或提取歌词
    func findOrExtractLyrics(for song: Song) {
        guard let fileURL = song.fileURL else { return }
        
        // 1. 看是否有同名的LRC文件
        let fileName = fileURL.deletingPathExtension().lastPathComponent
        let lrcURL = fileURL.deletingLastPathComponent().appendingPathComponent(fileName).appendingPathExtension("lrc")
        
        if FileManager.default.fileExists(atPath: lrcURL.path) {
            do {
                let lyricsText = try String(contentsOf: lrcURL, encoding: .utf8)
                
                // 解析歌词内容
                let parsedLines = parseLyrics(from: lyricsText)
                if !parsedLines.isEmpty {
                    print("成功从LRC文件解析歌词: \(lrcURL.path)")
                    saveLyrics(lyricsText, for: song)
                    return
                } else {
                    print("LRC文件格式无效或内容为空: \(lrcURL.path)")
                }
            } catch let error {
                print("读取LRC文件失败: \(error)")
            }
        }
        
        // 2. 如果歌曲已经包含歌词, 保存它
        if let lyrics = song.lyrics, !lyrics.isEmpty {
            // 解析歌词内容验证有效性
            let parsedLines = parseLyrics(from: lyrics)
            if !parsedLines.isEmpty {
                print("使用歌曲内嵌歌词")
                saveLyrics(lyrics, for: song)
                return
            } else {
                print("歌曲内嵌歌词格式无效或内容为空")
            }
        }
        
        // 3. 检查用户是否开启了自动获取歌词，只有在开启时才从API获取歌词
        if UserSettings.shared.autoFetchLyrics {
            fetchLyricsFromAPI(for: song) { lyricsString in
                // 由调用方处理保存，这里不再自动保存
                // 这样可以防止重复保存和确保保存到正确的位置
                print("已获取歌词，由调用方处理保存")
            }
        } else {
            print("未开启自动获取歌词功能，跳过歌词获取")
        }
    }
    
    // 从网络API获取歌词
    func fetchLyricsFromAPI(for song: Song, completion: @escaping (String?) -> Void) {
        // 再次检查设置，确保在获取过程中设置没有被关闭
        guard UserSettings.shared.autoFetchLyrics else {
            print("自动获取歌词功能已关闭，取消获取歌词")
            completion(nil)
            return
        }
        
        // 对歌曲标题进行URL编码
        guard let encodedTitle = song.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            print("歌曲标题URL编码失败")
            completion(nil)
            return
        }
        
        // 构建API URL 需要自己实现
        let apiURLString = ""
        guard let apiURL = URL(string: apiURLString) else {
            print("构建API URL失败")
            completion(nil)
            return
        }
        
        print("正在从API获取歌词: \(apiURLString)")
        
        // 创建网络请求
        URLSession.shared.dataTask(with: apiURL) { [weak self] data, response, error in
            guard let self = self else { return }
            
            // 检查是否有错误
            if let error = error {
                print("获取歌词API请求失败: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            // 检查响应状态码
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                print("获取歌词API请求返回非200状态码: \(httpResponse.statusCode)")
                completion(nil)
                return
            }
            
            // 检查是否有数据
            guard let data = data else {
                print("获取歌词API请求没有返回数据")
                completion(nil)
                return
            }
            
            // 尝试将数据解析为字符串
            if let lyricsString = String(data: data, encoding: .utf8) {
                print("成功从API获取歌词，长度: \(lyricsString.count)字符")
                
                // 直接返回歌词字符串
                completion(lyricsString)
            } else {
                print("无法将API返回的数据解析为字符串")
                completion(nil)
            }
        }.resume()
    }
    
    // 从URL获取歌词内容
    func fetchLyrics(from url: URL, completion: @escaping (Result<String, Error>) -> Void) {
        // 检查URL类型
        if url.isFileURL {
            // 从本地文件读取
            do {
                let lyrics = try String(contentsOf: url, encoding: .utf8)
                completion(.success(lyrics))
            } catch let error {
                completion(.failure(error))
            }
        } else {
            // 从网络URL读取
            URLSession.shared.dataTask(with: url) { data, response, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let data = data else {
                    completion(.failure(NSError(domain: "MusicFileManager", code: 1001, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                    return
                }
                
                // 尝试不同的编码解析歌词
                let encodings: [String.Encoding] = [
                    .utf8,              // Unicode UTF-8
                    .shiftJIS,          // 日文 Windows
                    .windowsCP1252,     // 西欧 Windows
                    .windowsCP1251,     // 西里尔文 Windows
                    .macOSRoman,        // Mac Roman
                    .isoLatin1,         // 西欧 ISO
                    .isoLatin2,         // 中欧 ISO
                    .ascii,             // ASCII
                    .nonLossyASCII      // 无损 ASCII
                ]
                
                for encoding in encodings {
                    if let lyrics = String(data: data, encoding: encoding) {
                        completion(.success(lyrics))
                        return
                    }
                }
                
                // 如果所有编码都失败，返回错误
                completion(.failure(NSError(domain: "MusicFileManager", code: 1002, userInfo: [NSLocalizedDescriptionKey: "Failed to decode lyrics with supported encodings"])))
            }.resume()
        }
    }
    
    // 保存歌词到文件
    func saveLyrics(_ lyrics: String, for song: Song) -> String? {
        let lyrics = lyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        if lyrics.isEmpty {
            return nil
        }
        
        guard let songId = song.id.uuidString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else {
            print("歌词保存失败：无法编码歌曲ID")
            return nil
        }
        
        // 确保歌词目录存在
        createLyricsDirectoryIfNeeded()
        
        // 创建歌词文件名：使用歌曲ID作为文件名
        let lyricsFileName = "\(songId).lrc"
        let lyricsURL = lyricsDirectory.appendingPathComponent(lyricsFileName)
        
        do {
            // 写入歌词内容到文件
            try lyrics.write(to: lyricsURL, atomically: true, encoding: .utf8)
            print("歌词已保存到：\(lyricsURL.path)")
            return lyricsURL.path
        } catch {
            print("歌词保存失败：\(error)")
            return nil
        }
    }
    
    // 在Lyrics目录中查找匹配的歌词文件
    func findLyricsInDirectoryFor(_ song: Song) -> String? {
        // 确保歌词目录存在
        if !FileManager.default.fileExists(atPath: lyricsDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: lyricsDirectory, withIntermediateDirectories: true)
                print("创建歌词目录: \(lyricsDirectory.path)")
            } catch {
                print("创建歌词目录失败: \(error)")
                return nil
            }
        }
        
        do {
            // 获取歌词目录中的所有文件
            let files = try FileManager.default.contentsOfDirectory(at: lyricsDirectory, includingPropertiesForKeys: nil)
            
            // 安全处理文件名部分，与saveLyrics方法中相同
            let sanitizedTitle = song.title.replacingOccurrences(of: "/", with: "_")
                                           .replacingOccurrences(of: "\\", with: "_")
                                           .replacingOccurrences(of: ":", with: "_")
                                           .replacingOccurrences(of: "*", with: "_")
                                           .replacingOccurrences(of: "?", with: "_")
                                           .replacingOccurrences(of: "\"", with: "_")
                                           .replacingOccurrences(of: "<", with: "_")
                                           .replacingOccurrences(of: ">", with: "_")
                                           .replacingOccurrences(of: "|", with: "_")
                                           .replacingOccurrences(of: " ", with: "_")
            
            let sanitizedArtist = song.artist.replacingOccurrences(of: "/", with: "_")
                                             .replacingOccurrences(of: "\\", with: "_")
                                             .replacingOccurrences(of: ":", with: "_")
                                             .replacingOccurrences(of: "*", with: "_")
                                             .replacingOccurrences(of: "?", with: "_")
                                             .replacingOccurrences(of: "\"", with: "_")
                                             .replacingOccurrences(of: "<", with: "_")
                                             .replacingOccurrences(of: ">", with: "_")
                                             .replacingOccurrences(of: "|", with: "_")
                                             .replacingOccurrences(of: " ", with: "_")
            
            // 1. 首先查找完全匹配的文件（标题_艺术家.lrc）
            let exactFileName = "\(sanitizedTitle)_\(sanitizedArtist).lrc"
            if let exactFile = files.first(where: { $0.lastPathComponent == exactFileName }) {
                print("找到完全匹配的歌词文件: \(exactFile.path)")
                do {
                    return try String(contentsOf: exactFile, encoding: .utf8)
                } catch {
                    print("读取歌词文件失败: \(error)")
                }
            }
            
            // 2. 查找包含歌曲标题的文件
            let titleFiles = files.filter { $0.lastPathComponent.contains(sanitizedTitle) && $0.pathExtension.lowercased() == "lrc" }
            if !titleFiles.isEmpty {
                print("找到包含歌曲标题的歌词文件: \(titleFiles.first!.path)")
                do {
                    return try String(contentsOf: titleFiles.first!, encoding: .utf8)
                } catch {
                    print("读取歌词文件失败: \(error)")
                }
            }
            
            // 3. 查找包含艺术家名的文件
            if sanitizedArtist != "未知艺术家" {
                let artistFiles = files.filter { $0.lastPathComponent.contains(sanitizedArtist) && $0.pathExtension.lowercased() == "lrc" }
                if !artistFiles.isEmpty {
                    print("找到包含艺术家名的歌词文件: \(artistFiles.first!.path)")
                    do {
                        return try String(contentsOf: artistFiles.first!, encoding: .utf8)
                    } catch {
                        print("读取歌词文件失败: \(error)")
                    }
                }
            }
            
            // 没有找到匹配的歌词文件
            return nil
        } catch {
            print("获取歌词目录内容失败: \(error)")
            return nil
        }
    }
    
    // 保存专辑封面图片
    public func saveArtwork(_ data: Data, for songTitle: String) -> URL? {
        let artworkDirectory = documentsDirectory.appendingPathComponent("Artworks", isDirectory: true)
        
        do {
            if !FileManager.default.fileExists(atPath: artworkDirectory.path) {
                try FileManager.default.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
            }
            
            let fileName = "\(songTitle.replacingOccurrences(of: " ", with: "_")).jpg"
            let fileURL = artworkDirectory.appendingPathComponent(fileName)
            
            try data.write(to: fileURL)
            return fileURL
        } catch let error {
            print("保存封面图片失败: \(error)")
            return nil
        }
    }
    
    // 获取音乐目录中所有文件的信息
    func printMusicFilesInfo() {
        let fileManager = FileManager.default
        
        print("\n===== 音乐文件列表 =====")
        
        do {
            // 确保目录存在
            if !fileManager.fileExists(atPath: musicDirectory.path) {
                try fileManager.createDirectory(at: musicDirectory, withIntermediateDirectories: true)
                print("创建了音乐目录: \(musicDirectory.path)")
            }
            
            // 获取目录中的所有文件
            let musicFiles = try fileManager.contentsOfDirectory(at: musicDirectory, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey])
            
            if musicFiles.isEmpty {
                print("音乐目录为空")
            } else {
                print("音乐目录路径: \(musicDirectory.path)")
                print("共发现 \(musicFiles.count) 个文件:")
                
                // 格式化输出
                let formatter = ByteCountFormatter()
                formatter.allowedUnits = [.useAll]
                formatter.countStyle = .file
                
                // 日期格式化
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                dateFormatter.timeStyle = .short
                
                // 按照文件名排序
                let sortedFiles = musicFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }
                
                // 计算最长文件名，用于格式化输出
                let maxFileNameLength = sortedFiles.map { $0.lastPathComponent.count }.max() ?? 20
                let fileNamePadding = min(maxFileNameLength + 2, 50) // 限制最大宽度
                
                // 表头
                print(String(format: "%-\(fileNamePadding)s | %15s | %s", "文件名", "文件大小", "创建日期"))
                print(String(repeating: "-", count: fileNamePadding + 2 + 15 + 2 + 20))
                
                var totalSize: Int64 = 0
                
                for fileURL in sortedFiles {
                    do {
                        // 获取文件属性
                        let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                        let fileSize = resourceValues.fileSize ?? 0
                        let creationDate = resourceValues.creationDate
                        
                        // 累计总大小
                        totalSize += Int64(fileSize)
                        
                        // 格式化输出
                        let truncatedName = fileURL.lastPathComponent.count > fileNamePadding ? 
                            String(fileURL.lastPathComponent.prefix(fileNamePadding - 3)) + "..." : 
                            fileURL.lastPathComponent
                        
                        let formattedSize = formatter.string(fromByteCount: Int64(fileSize))
                        let formattedDate = creationDate != nil ? dateFormatter.string(from: creationDate!) : "未知"
                        
                        print(String(format: "%-\(fileNamePadding)s | %15s | %s", truncatedName, formattedSize, formattedDate))
                    } catch {
                        print("\(fileURL.lastPathComponent): 无法获取文件信息 - \(error.localizedDescription)")
                    }
                }
                
                // 输出总大小
                print(String(repeating: "-", count: fileNamePadding + 2 + 15 + 2 + 20))
                print("总文件大小: \(formatter.string(fromByteCount: totalSize))")
            }
        } catch {
            print("无法列出音乐目录内容: \(error.localizedDescription)")
        }
        
        print("===== 音乐文件列表结束 =====\n")
    }
    
    // 获取所有音乐文件的路径
    func getAllMusicFiles() -> [URL] {
        let fileManager = FileManager.default
        
        // 确保目录存在
        if !fileManager.fileExists(atPath: musicDirectory.path) {
            do {
                try fileManager.createDirectory(at: musicDirectory, withIntermediateDirectories: true)
            } catch {
                print("创建音乐目录失败: \(error)")
                return []
            }
        }
        
        do {
            // 获取目录中的所有文件
            let files = try fileManager.contentsOfDirectory(at: musicDirectory, includingPropertiesForKeys: nil)
            
            // 过滤出支持的音频文件
            return files.filter { isSupportedAudioFile(url: $0) }
        } catch {
            print("获取音乐文件列表失败: \(error)")
            return []
        }
    }
    
    // 获取当前应显示的歌词行索引
    public func getCurrentLyricIndex(lines: [LyricLine], currentTime: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }
        
        // 找到最后一个时间小于等于当前时间的歌词行
        var currentIndex: Int? = nil
        
        for (index, line) in lines.enumerated() {
            if line.timeTag <= currentTime {
                currentIndex = index
            } else {
                break
            }
        }
        
        return currentIndex
    }
    
    // 解析LRC格式歌词
    public func parseLyrics(from lyricsText: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        
        // 如果歌词为空，直接返回空数组
        if lyricsText.isEmpty {
            return []
        }
        
        // 按行分割
        let lyricsLines = lyricsText.components(separatedBy: .newlines)
        
        // LRC时间标签正则表达式 [mm:ss.xx]
        let timeTagPattern = "\\[(\\d{2}):(\\d{2})\\.(\\d{2,3})\\]"
        let regex = try? NSRegularExpression(pattern: timeTagPattern, options: [])
        
        // 处理每一行
        for line in lyricsLines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 跳过空行
            if trimmedLine.isEmpty {
                continue
            }
            
            // 跳过元数据行（标准LRC格式的元数据如[ar:艺术家]、[ti:标题]等）
            if trimmedLine.hasPrefix("[") && 
               (trimmedLine.contains("ar:") || 
                trimmedLine.contains("ti:") || 
                trimmedLine.contains("al:") || 
                trimmedLine.contains("by:") || 
                trimmedLine.contains("offset:") || 
                trimmedLine.contains("id:") || 
                trimmedLine.contains("hash:") || 
                trimmedLine.contains("sign:") || 
                trimmedLine.contains("qq:") || 
                trimmedLine.contains("total:")) {
                continue
            }
            
            // 没有识别到正确的时间标签格式，检查是否为纯文本歌词
            if regex == nil || !trimmedLine.contains("[") {
                // 对于纯文本歌词，将其按行分割并添加为无时间标签的歌词行
                if !trimmedLine.isEmpty {
                    lines.append(LyricLine(timeTag: Double(lines.count * 5), text: trimmedLine))
                }
                continue
            }
            
            // 提取时间标签和对应文本
            let nsString = trimmedLine as NSString
            let matches = regex?.matches(in: trimmedLine, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
            
            // 如果没有找到时间标签，跳过
            if matches.isEmpty {
                continue
            }
            
            // 提取所有时间标签
            var timeTags: [TimeInterval] = []
            var lastMatchEndIndex = 0
            
            for match in matches {
                lastMatchEndIndex = match.range.location + match.range.length
                
                let minutesRange = match.range(at: 1)
                let secondsRange = match.range(at: 2)
                let milliSecondsRange = match.range(at: 3)
                
                if minutesRange.location != NSNotFound && secondsRange.location != NSNotFound && milliSecondsRange.location != NSNotFound {
                    let minutes = Int(nsString.substring(with: minutesRange)) ?? 0
                    let seconds = Int(nsString.substring(with: secondsRange)) ?? 0
                    
                    // 处理毫秒，考虑到可能是2位或3位
                    let milliSecondsStr = nsString.substring(with: milliSecondsRange)
                    var milliSeconds = Int(milliSecondsStr) ?? 0
                    
                    // 如果是2位数，需要乘以10转为毫秒
                    if milliSecondsStr.count == 2 {
                        milliSeconds *= 10
                    }
                    
                    // 计算总秒数
                    let timeTag = TimeInterval(minutes * 60 + seconds) + TimeInterval(milliSeconds) / 1000
                    timeTags.append(timeTag)
                }
            }
            
            // 提取歌词文本
            var lyricText = ""
            if lastMatchEndIndex < nsString.length {
                lyricText = nsString.substring(from: lastMatchEndIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            // 为每个时间标签创建一个歌词行
            for timeTag in timeTags {
                lines.append(LyricLine(timeTag: timeTag, text: lyricText))
            }
        }
        
        // 解析成功且有内容，记录解析成功的标志
        if !lines.isEmpty {
            print("成功解析歌词，共\(lines.count)行")
        } else {
            print("歌词解析结果为空")
        }
        
        // 按时间排序
        return lines.sorted(by: { $0.timeTag < $1.timeTag })
    }
    
    // 删除音乐文件及相关资源
    func deleteMusicFile(song: Song) -> Bool {
        var success = true
        
        // 删除音乐文件
        if let fileURL = song.fileURL {
            do {
                try FileManager.default.removeItem(at: fileURL)
                print("已删除音乐文件: \(fileURL.lastPathComponent)")
            } catch {
                print("删除音乐文件失败: \(error)")
                success = false
            }
        }
        
        // 删除封面图片
        if let artworkURL = song.coverImagePath {
            // 检查是否有其他歌曲使用同一封面
            let isArtworkShared = MusicLibrary.shared.songs.contains(where: { 
                $0.id != song.id && $0.coverImagePath == artworkURL
            })
            
            if !isArtworkShared {
                do {
                    try FileManager.default.removeItem(at: URL(fileURLWithPath: artworkURL))
                    print("已删除封面图片: \(artworkURL)")
                } catch {
                    print("删除封面图片失败: \(error)")
                    // 不影响整体成功状态
                }
            }
        }
        
        // 删除歌词文件
        if let lyricsURL = song.lyricsURL {
            // 检查是否有其他歌曲使用同一歌词
            let isLyricsShared = MusicLibrary.shared.songs.contains(where: { 
                $0.id != song.id && $0.lyricsURL?.absoluteString == lyricsURL.absoluteString 
            })
            
            if !isLyricsShared {
                do {
                    try FileManager.default.removeItem(at: lyricsURL)
                    print("已删除歌词文件: \(lyricsURL.lastPathComponent)")
                } catch {
                    print("删除歌词文件失败: \(error)")
                    // 不影响整体成功状态
                }
            }
        }
        
        return success
    }
    
    // 支持的音频格式类型
    public var supportedTypes: [UTType] {
        var types = [UTType.mp3, UTType.wav, UTType.aiff, UTType.mpeg4Audio]
        
        // 添加AAC
        if let aacType = UTType(filenameExtension: "aac") {
            types.append(aacType)
        }
        
        // 添加M4A
        if let m4aType = UTType(filenameExtension: "m4a") {
            types.append(m4aType)
        }
        
        // 添加FLAC
        if let flacType = UTType(filenameExtension: "flac") {
            types.append(flacType)
        }
        
        return types
    }
    
    // 添加调试方法来确保目录存在并检查文件权限
    func ensureDirectoriesExist() {
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // 定义需要确保存在的目录
        let requiredDirectories = [
            documentsDirectory.appendingPathComponent("Music"),
            documentsDirectory.appendingPathComponent("Artwork"),
            documentsDirectory.appendingPathComponent("Lyrics")
        ]
        
        // 确保每个目录都存在
        for directory in requiredDirectories {
            do {
                if !fileManager.fileExists(atPath: directory.path) {
                    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                    print("创建目录: \(directory.path)")
                }
            } catch {
                print("创建目录失败 \(directory.path): \(error.localizedDescription)")
            }
        }
        
        // 列出Documents目录
        print("\n当前Documents目录内容:")
        do {
            let contentsOfDocuments = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
            for item in contentsOfDocuments {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: item.path, isDirectory: &isDir) {
                    print("- \(item.lastPathComponent) \(isDir.boolValue ? "(目录)" : "(文件)")")
                }
            }
        } catch {
            print("无法列出目录内容: \(error.localizedDescription)")
        }
        
        // 检查文件权限
        print("\n文件系统权限:")
        for directory in requiredDirectories {
            let testFilePath = directory.appendingPathComponent("test_permission.txt")
            do {
                try "Test permission".write(to: testFilePath, atomically: true, encoding: .utf8)
                print("可写入: \(directory.path)")
                try fileManager.removeItem(at: testFilePath)
            } catch {
                print("无法写入: \(directory.path) - \(error.localizedDescription)")
            }
        }
    }
    
    // 获取本地缓存的专辑封面
    private func getLocalAlbumCover(artist: String, album: String) -> Data? {
        let albumCoverDirectory = getAlbumCoversDirectory()
        let localCoverPath = getLocalAlbumCoverPath(artist: artist, album: album)
        
        print("🔍 查找本地专辑封面: \(localCoverPath.path)")
        
        // 检查文件是否存在
        if FileManager.default.fileExists(atPath: localCoverPath.path) {
            do {
                let imageData = try Data(contentsOf: localCoverPath)
                print("✅ 找到本地专辑封面: \(localCoverPath.lastPathComponent), 大小: \(imageData.count) 字节")
                return imageData
            } catch {
                print("❌ 读取本地专辑封面失败: \(error.localizedDescription)")
            }
        }
        
        return nil
    }
    
    // 获取专辑封面缓存目录
    private func getAlbumCoversDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        let albumCoversDirectory = documentsDirectory.appendingPathComponent("AlbumCovers", isDirectory: true)
        
        // 确保目录存在
        if !FileManager.default.fileExists(atPath: albumCoversDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: albumCoversDirectory, withIntermediateDirectories: true)
                print("📁 创建专辑封面目录: \(albumCoversDirectory.path)")
            } catch {
                print("❌ 创建专辑封面目录失败: \(error)")
            }
        }
        
        return albumCoversDirectory
    }
    
    // 获取本地专辑封面路径
    private func getLocalAlbumCoverPath(artist: String, album: String) -> URL {
        // 安全处理文件名，避免特殊字符
        let sanitizedArtist = artist.replacingOccurrences(of: "/", with: "_")
                                    .replacingOccurrences(of: "\\", with: "_")
                                    .replacingOccurrences(of: ":", with: "_")
                                    .replacingOccurrences(of: "*", with: "_")
                                    .replacingOccurrences(of: "?", with: "_")
                                    .replacingOccurrences(of: "\"", with: "_")
                                    .replacingOccurrences(of: "<", with: "_")
                                    .replacingOccurrences(of: ">", with: "_")
                                    .replacingOccurrences(of: "|", with: "_")
                                    .replacingOccurrences(of: " ", with: "_")
        
        let sanitizedAlbum = album.replacingOccurrences(of: "/", with: "_")
                                  .replacingOccurrences(of: "\\", with: "_")
                                  .replacingOccurrences(of: ":", with: "_")
                                  .replacingOccurrences(of: "*", with: "_")
                                  .replacingOccurrences(of: "?", with: "_")
                                  .replacingOccurrences(of: "\"", with: "_")
                                  .replacingOccurrences(of: "<", with: "_")
                                  .replacingOccurrences(of: ">", with: "_")
                                  .replacingOccurrences(of: "|", with: "_")
                                  .replacingOccurrences(of: " ", with: "_")
        
        let fileName = "\(sanitizedArtist)_\(sanitizedAlbum).jpg"
        return getAlbumCoversDirectory().appendingPathComponent(fileName)
    }
} 
