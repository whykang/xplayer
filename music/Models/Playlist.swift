import Foundation
import Combine

class Playlist: Identifiable, Codable, ObservableObject, Equatable {
    let id: UUID
    @Published var name: String
    @Published var songs: [Song]
    @Published var coverImage: String?
    
    // 用于Codable
    private enum CodingKeys: String, CodingKey {
        case id, name, songs, coverImage
    }
    
    init(id: UUID = UUID(), name: String, songs: [Song], coverImage: String? = nil) {
        self.id = id
        self.name = name
        self.songs = songs
        self.coverImage = coverImage
    }
    
    // 编码
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(songs, forKey: .songs)
        try container.encodeIfPresent(coverImage, forKey: .coverImage)
    }
    
    // 解码 - 需要实现required init因为这是一个class
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        songs = try container.decode([Song].self, forKey: .songs)
        coverImage = try container.decodeIfPresent(String.self, forKey: .coverImage)
    }
    
    // Equatable实现 - 对于class需要static func
    static func == (lhs: Playlist, rhs: Playlist) -> Bool {
        return lhs.id == rhs.id
    }
    
    // 示例数据
    static let examples: [Playlist] = []
    
    // 因为class是引用类型，添加copy方法模拟struct的值复制行为
    func copy() -> Playlist {
        return Playlist(id: id, name: name, songs: songs, coverImage: coverImage)
    }
} 