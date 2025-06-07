import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ImportMusicView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var musicLibrary = MusicLibrary.shared
    @ObservedObject private var musicFileManager = MusicFileManager.shared
    
    @State private var isShowingDocumentPicker = false
    @State private var isLoading = false
    @State private var loadingMessage = ""
    @State private var importedSong: Song?
    @State private var showImportResult = false
    @State private var importError: Error?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                if isLoading {
                    ProgressView(loadingMessage)
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                } else {
                    // 图标
                    Image(systemName: "music.note")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    // 标题和说明
                    VStack(spacing: 10) {
                        Text("导入音乐")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("支持导入MP3、WAV、AAC、M4A、FLAC等格式")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    // 导入按钮
                    Button(action: {
                        isShowingDocumentPicker = true
                    }) {
                        Label("从文件选择", systemImage: "folder")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 30)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("导入音乐")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isShowingDocumentPicker) {
                DocumentPicker(supportedTypes: musicFileManager.supportedTypes) { urls in
                    if let url = urls.first {
                        importMusicFile(from: url)
                    }
                }
            }
            .alert(isPresented: $showImportResult) {
                if let error = importError {
                    // 导入失败的提示
                    return Alert(
                        title: Text("导入失败"),
                        message: Text(error.localizedDescription),
                        dismissButton: .default(Text("确定"))
                    )
                } else if let song = importedSong {
                    // 导入成功的提示
                    return Alert(
                        title: Text("导入成功"),
                        message: Text("已成功导入音乐：\(song.title)"),
                        dismissButton: .default(Text("确定")) {
                            dismiss()
                        }
                    )
                } else {
                    // 通用提示
                    return Alert(
                        title: Text("导入结果"),
                        message: Text("操作已完成"),
                        dismissButton: .default(Text("确定"))
                    )
                }
            }
        }
    }
    
    // 导入音乐文件
    private func importMusicFile(from url: URL) {
        isLoading = true
        loadingMessage = "正在导入音乐文件..."
        
        musicFileManager.importMusicFile(from: url) { result in
            isLoading = false
            
            switch result {
            case .success(let song):
                importedSong = song
                importError = nil
            case .failure(let error):
                importedSong = nil
                importError = error
            }
            
            showImportResult = true
        }
    }
}

// 文档选择器
struct DocumentPicker: UIViewControllerRepresentable {
    let supportedTypes: [UTType]
    let onPick: ([URL]) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            // 处理用户选择的文档
            if let url = urls.first {
                if url.startAccessingSecurityScopedResource() {
                    // 获取永久访问权限
                    let shouldStopAccessing = url.startAccessingSecurityScopedResource()
                    defer {
                        if shouldStopAccessing {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    
                    // 用来访问文件
                    let bookmarkData: Data
                    do {
                        bookmarkData = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                    } catch {
                        print("创建书签失败: \(error)")
                    }
                }
                
                parent.onPick([url])
            }
        }
    }
}

struct ImportMusicView_Previews: PreviewProvider {
    static var previews: some View {
        ImportMusicView()
    }
} 