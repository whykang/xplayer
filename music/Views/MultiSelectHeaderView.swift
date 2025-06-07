import SwiftUI

struct MultiSelectHeaderView: View {
    let selectedCount: Int
    let onCancel: () -> Void
    let onDelete: () -> Void
    let onAddToPlaylist: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onCancel) {
                Text("取消")
                    .foregroundColor(.blue)
            }
            
            Spacer()
            
            Text("已选择\(selectedCount)项")
                .foregroundColor(.secondary)
            
            Spacer()
            
            HStack(spacing: 20) {
                Button(action: onAddToPlaylist) {
                    Image(systemName: "music.note.list")
                        .foregroundColor(.blue)
                }
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.systemGray5)),
            alignment: .bottom
        )
    }
} 