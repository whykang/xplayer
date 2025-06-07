import Foundation

struct Album: Identifiable {
    let id = UUID()
    let title: String
    let artist: String
    let year: Int?
    let songs: [Song]
    var coverImage: String?
    
    // 示例数据
    static let examples: [Album] = []
} 