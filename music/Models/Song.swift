import Foundation
import AVFoundation

struct Song: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    var relativePath: String  // 改为相对路径（相对于Documents目录）
    var lyrics: String?
    var relativeArtworkPath: String?  // 改为相对路径
    let fileSize: Int64
    let trackNumber: Int?
    let year: Int?
    var isPinned: Bool = false
    let creationDate: Date
    
    var parsedLyrics: [LyricLine]? = nil
    
    var albumName: String
    var albumArtist: String
    let composer: String
    let genre: String
    
    // 歌词文件相对路径
    var relativeLyricsPath: String?
    
    // MARK: - 向后兼容的属性
    // 保留原有的属性名以兼容旧数据
    var filePath: String {
        get { 
            // 如果relativePath是绝对路径（旧数据），尝试转换为相对路径
            if relativePath.hasPrefix("/") {
                return relativePath
            }
            // 否则构建绝对路径
            return getAbsolutePath(from: relativePath)
        }
        set { 
            // 将绝对路径转换为相对路径存储
            relativePath = Self.convertToRelativePath(newValue)
        }
    }
    
    var coverImagePath: String? {
        get {
            guard let relativeArtworkPath = relativeArtworkPath else { return nil }
            if relativeArtworkPath.hasPrefix("/") {
                return relativeArtworkPath  // 旧数据，返回绝对路径
            }
            return getAbsolutePath(from: relativeArtworkPath)
        }
        set {
            if let newValue = newValue {
                relativeArtworkPath = Self.convertToRelativePath(newValue)
            } else {
                relativeArtworkPath = nil
            }
        }
    }
    
    var lyricsFilePath: String? {
        get {
            guard let relativeLyricsPath = relativeLyricsPath else { return nil }
            if relativeLyricsPath.hasPrefix("/") {
                return relativeLyricsPath  // 旧数据，返回绝对路径
            }
            return getAbsolutePath(from: relativeLyricsPath)
        }
        set {
            if let newValue = newValue {
                relativeLyricsPath = Self.convertToRelativePath(newValue)
            } else {
                relativeLyricsPath = nil
            }
        }
    }
    
    // MARK: - 路径处理方法
    
    // 获取Documents目录
    private static func getDocumentsDirectory() -> URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    // 将相对路径转换为绝对路径
    private func getAbsolutePath(from relativePath: String) -> String {
        if relativePath.isEmpty { return "" }
        let documentsURL = Self.getDocumentsDirectory()
        return documentsURL.appendingPathComponent(relativePath).path
    }
    
    // 将绝对路径转换为相对路径
    private static func convertToRelativePath(_ absolutePath: String) -> String {
        if absolutePath.isEmpty { return "" }
        
        let documentsPath = getDocumentsDirectory().path
        
        // 如果是绝对路径且在Documents目录下
        if absolutePath.hasPrefix(documentsPath) {
            let relativePath = String(absolutePath.dropFirst(documentsPath.count))
            return relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
        }
        
        // 如果已经是相对路径或者不在Documents目录下，直接返回
        return absolutePath
    }
    
    // 将URL属性改为计算属性，优化性能
    var fileURL: URL? {
        let path = filePath
        if path.isEmpty { return nil }
        
        let documentsURL = Self.getDocumentsDirectory()
        
        // 如果是相对路径，直接构建URL（最常见的情况）
        if !path.hasPrefix("/") {
            return documentsURL.appendingPathComponent(path)
        }
        
        // 如果是绝对路径，直接返回（旧数据或特殊情况）
        return URL(fileURLWithPath: path)
    }
    
    // 获取准备分享的文件URL（带有资源访问权限）
    func getShareableFileURL() -> URL? {
        guard let url = fileURL else { 
            return nil 
        }
        
        // 验证文件存在
        if !FileManager.default.fileExists(atPath: url.path) {
            return nil
        }
        
        // 检查文件是否可读
        if !FileManager.default.isReadableFile(atPath: url.path) {
            return nil
        }
        
        return url
    }
    
    var artworkURL: URL? {
        if let path = coverImagePath {
            if path.hasPrefix("/") {
                // 绝对路径
                if FileManager.default.fileExists(atPath: path) {
                    return URL(fileURLWithPath: path)
                }
                // 绝对路径无效，尝试迁移
                let fileName = URL(fileURLWithPath: path).lastPathComponent
                let documentsURL = Self.getDocumentsDirectory()
                let newURL = documentsURL.appendingPathComponent("Artworks").appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: newURL.path) {
                    return newURL
                }
            } else {
                // 相对路径
                let documentsURL = Self.getDocumentsDirectory()
                return documentsURL.appendingPathComponent(path)
            }
        }
        return nil
    }
    
    // 获取文件格式
    var fileFormat: String {
        return fileURL?.pathExtension.uppercased() ?? ""
    }
    
    var lyricsURL: URL? {
        if let path = lyricsFilePath {
            if path.hasPrefix("/") {
                // 绝对路径
                if FileManager.default.fileExists(atPath: path) {
                    return URL(fileURLWithPath: path)
                }
                // 绝对路径无效，尝试迁移
                let fileName = URL(fileURLWithPath: path).lastPathComponent
                let documentsURL = Self.getDocumentsDirectory()
                let newURL = documentsURL.appendingPathComponent("Lyrics").appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: newURL.path) {
                    return newURL
                }
            } else {
                // 相对路径
                let documentsURL = Self.getDocumentsDirectory()
                return documentsURL.appendingPathComponent(path)
            }
        }
        return nil
    }
    
    enum CodingKeys: String, CodingKey {
        case id, title, artist, album, duration, relativePath, lyrics, relativeArtworkPath, fileSize, trackNumber, year
        case albumName, albumArtist, composer, genre, relativeLyricsPath, isPinned, creationDate
        // 保留旧的键名以支持向后兼容
        case filePath, coverImagePath, lyricsFilePath
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        artist = try container.decode(String.self, forKey: .artist)
        album = try container.decode(String.self, forKey: .album)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        
        // 支持新旧两种路径格式
        if let newRelativePath = try container.decodeIfPresent(String.self, forKey: .relativePath) {
            relativePath = newRelativePath
        } else if let oldFilePath = try container.decodeIfPresent(String.self, forKey: .filePath) {
            // 将旧的绝对路径转换为相对路径
            relativePath = Self.convertToRelativePath(oldFilePath)
        } else {
            relativePath = ""
        }
        
        lyrics = try container.decodeIfPresent(String.self, forKey: .lyrics)
        
        // 支持新旧两种封面路径格式
        if let newArtworkPath = try container.decodeIfPresent(String.self, forKey: .relativeArtworkPath) {
            relativeArtworkPath = newArtworkPath
        } else if let oldCoverPath = try container.decodeIfPresent(String.self, forKey: .coverImagePath) {
            relativeArtworkPath = Self.convertToRelativePath(oldCoverPath)
        } else {
            relativeArtworkPath = nil
        }
        
        fileSize = try container.decode(Int64.self, forKey: .fileSize)
        trackNumber = try container.decodeIfPresent(Int.self, forKey: .trackNumber)
        year = try container.decodeIfPresent(Int.self, forKey: .year)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        creationDate = try container.decodeIfPresent(Date.self, forKey: .creationDate) ?? Date()
        
        albumName = try container.decode(String.self, forKey: .albumName)
        albumArtist = try container.decode(String.self, forKey: .albumArtist)
        composer = try container.decode(String.self, forKey: .composer)
        genre = try container.decode(String.self, forKey: .genre)
        
        // 支持新旧两种歌词路径格式
        if let newLyricsPath = try container.decodeIfPresent(String.self, forKey: .relativeLyricsPath) {
            relativeLyricsPath = newLyricsPath
        } else if let oldLyricsPath = try container.decodeIfPresent(String.self, forKey: .lyricsFilePath) {
            relativeLyricsPath = Self.convertToRelativePath(oldLyricsPath)
        } else {
            relativeLyricsPath = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(artist, forKey: .artist)
        try container.encode(album, forKey: .album)
        try container.encode(duration, forKey: .duration)
        try container.encode(relativePath, forKey: .relativePath)  // 使用新的相对路径
        try container.encodeIfPresent(lyrics, forKey: .lyrics)
        try container.encodeIfPresent(relativeArtworkPath, forKey: .relativeArtworkPath)  // 使用新的相对路径
        try container.encode(fileSize, forKey: .fileSize)
        try container.encodeIfPresent(trackNumber, forKey: .trackNumber)
        try container.encodeIfPresent(year, forKey: .year)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(creationDate, forKey: .creationDate)
        
        try container.encode(albumName, forKey: .albumName)
        try container.encode(albumArtist, forKey: .albumArtist)
        try container.encode(composer, forKey: .composer)
        try container.encode(genre, forKey: .genre)
        try container.encodeIfPresent(relativeLyricsPath, forKey: .relativeLyricsPath)  // 使用新的相对路径
    }
    
    static func == (lhs: Song, rhs: Song) -> Bool {
        return lhs.id == rhs.id
    }
    
    // 简化初始化，允许忽略部分字段
    init(title: String, artist: String, albumName: String, duration: TimeInterval, fileURL: URL?, 
         albumArtist: String = "未知专辑艺术家", composer: String = "", genre: String = "", 
         year: Int? = nil, trackNumber: Int? = nil, artworkURL: URL? = nil, lyricsURL: URL? = nil, lyrics: String = "",
         fileSize: Int64 = 0, creationDate: Date = Date()) {
        self.id = UUID()
        self.title = title
        self.artist = artist
        self.albumName = albumName
        self.albumArtist = albumArtist
        self.composer = composer
        self.genre = genre
        self.year = year
        self.trackNumber = trackNumber
        self.duration = duration
        
        // 转换为相对路径存储
        if let fileURL = fileURL {
            let absolutePath = fileURL.path
            let documentsPath = Self.getDocumentsDirectory().path
            if absolutePath.hasPrefix(documentsPath) {
                let relativePath = String(absolutePath.dropFirst(documentsPath.count))
                self.relativePath = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
            } else {
                self.relativePath = absolutePath
            }
        } else {
            self.relativePath = ""
        }
        
        // 处理封面相对路径
        if let artworkURL = artworkURL {
            let absolutePath = artworkURL.path
            let documentsPath = Self.getDocumentsDirectory().path
            if absolutePath.hasPrefix(documentsPath) {
                let relativePath = String(absolutePath.dropFirst(documentsPath.count))
                self.relativeArtworkPath = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
            } else {
                self.relativeArtworkPath = absolutePath
            }
        } else {
            self.relativeArtworkPath = nil
        }
        
        // 处理歌词相对路径
        if let lyricsURL = lyricsURL {
            let absolutePath = lyricsURL.path
            let documentsPath = Self.getDocumentsDirectory().path
            if absolutePath.hasPrefix(documentsPath) {
                let relativePath = String(absolutePath.dropFirst(documentsPath.count))
                self.relativeLyricsPath = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
            } else {
                self.relativeLyricsPath = absolutePath
            }
        } else {
            self.relativeLyricsPath = nil
        }
        
        self.lyrics = lyrics
        self.album = albumName // 使用albumName作为album
        self.fileSize = fileSize
        self.creationDate = creationDate
    }
    
    // 示例数据，用于开发和测试
    static let examples: [Song] = []
    
    // 单个示例，用于Widget预览
    static let example = Song(
        title: "预览歌曲",
        artist: "预览艺术家",
        albumName: "预览专辑",
        duration: 180,
        fileURL: nil,
        albumArtist: "预览专辑艺术家",
        composer: "预览作曲家",
        genre: "流行",
        year: 2023,
        trackNumber: 1
    )
    
    // 加载并解析歌词
    mutating func loadLyrics(using fileManager: MusicFileManager) {
        if let lyrics = lyrics, !lyrics.isEmpty {
            self.parsedLyrics = fileManager.parseLyrics(from: lyrics)
        }
    }
    
    // Hashable实现
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // 添加一个便利初始化方法
    init(id: UUID = UUID(), title: String, artist: String, album: String, duration: TimeInterval,
         filePath: String, lyrics: String? = nil, coverImagePath: String? = nil, fileSize: Int64,
         trackNumber: Int? = nil, year: Int? = nil, albumName: String, albumArtist: String,
         composer: String, genre: String, lyricsFilePath: String? = nil, isPinned: Bool = false,
         creationDate: Date = Date()) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        
        // 处理文件路径（可能是绝对路径或相对路径）
        let documentsPath = Self.getDocumentsDirectory().path
        if filePath.hasPrefix(documentsPath) {
            // 绝对路径，转换为相对路径
            let relativePath = String(filePath.dropFirst(documentsPath.count))
            self.relativePath = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
        } else if filePath.hasPrefix("/") {
            // 绝对路径但不在Documents目录下，保持原样
            self.relativePath = filePath
        } else {
            // 已经是相对路径，直接使用
            self.relativePath = filePath
        }
        
        self.lyrics = lyrics
        
        // 处理封面路径（可能是绝对路径或相对路径）
        if let coverImagePath = coverImagePath {
            if coverImagePath.hasPrefix(documentsPath) {
                // 绝对路径，转换为相对路径
                let relativePath = String(coverImagePath.dropFirst(documentsPath.count))
                self.relativeArtworkPath = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
            } else if coverImagePath.hasPrefix("/") {
                // 绝对路径但不在Documents目录下，保持原样
                self.relativeArtworkPath = coverImagePath
            } else {
                // 已经是相对路径，直接使用
                self.relativeArtworkPath = coverImagePath
            }
        } else {
            self.relativeArtworkPath = nil
        }
        
        self.fileSize = fileSize
        self.trackNumber = trackNumber
        self.year = year
        self.albumName = albumName
        self.albumArtist = albumArtist
        self.composer = composer
        self.genre = genre
        
        // 处理歌词路径（可能是绝对路径或相对路径）
        if let lyricsFilePath = lyricsFilePath {
            if lyricsFilePath.hasPrefix(documentsPath) {
                // 绝对路径，转换为相对路径
                let relativePath = String(lyricsFilePath.dropFirst(documentsPath.count))
                self.relativeLyricsPath = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
            } else if lyricsFilePath.hasPrefix("/") {
                // 绝对路径但不在Documents目录下，保持原样
                self.relativeLyricsPath = lyricsFilePath
            } else {
                // 已经是相对路径，直接使用
                self.relativeLyricsPath = lyricsFilePath
            }
        } else {
            self.relativeLyricsPath = nil
        }
        
        self.isPinned = isPinned
        self.creationDate = creationDate
    }
} 