import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var musicLibrary: MusicLibrary
    @State private var isShowingDocumentPicker = false
    @State private var importedSong: Song?
    @State private var showImportResult = false
    @State private var importError: Error?
    
    var body: some View {
        NavigationView {
            VStack {
                if musicLibrary.isLoading {
                    VStack(spacing: 20) {
                        ProgressView(musicLibrary.loadingMessage)
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.5)
                        
                        Text(musicLibrary.loadingMessage)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                } else {
                    VStack(spacing: 25) {
                        Image(systemName: "music.note.list")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .foregroundColor(.accentColor)
                        
                        Text("导入音乐文件")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("支持的文件格式: MP3, WAV, M4A, FLAC")
                            .foregroundColor(.secondary)
                        
                        Divider()
                        
                        Button(action: {
                            isShowingDocumentPicker = true
                        }) {
                            HStack {
                                Image(systemName: "folder")
                                Text("从文件导入")
                            }
                            .frame(minWidth: 200)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        
                        Button(action: {
                            openSystemDocumentPicker()
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.down")
                                Text("从其他应用导入")
                            }
                            .frame(minWidth: 200)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        
                        Button(action: {
                            musicLibrary.loadLocalMusic()
                        }) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("扫描本地文件")
                            }
                            .frame(minWidth: 200)
                            .padding()
                            .background(Color.secondary.opacity(0.2))
                            .foregroundColor(.primary)
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("导入音乐")
            .navigationBarItems(trailing: Button("完成") {
                presentationMode.wrappedValue.dismiss()
            })
            .sheet(isPresented: $isShowingDocumentPicker) {
                MusicDocumentPicker(supportedTypes: MusicFileManager.shared.supportedAudioTypes()) { urls in
                    if let url = urls.first {
                        musicLibrary.importMusic(from: url) { result in
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
            }
            .alert(isPresented: $showImportResult) {
                if let error = importError {
                    return Alert(
                        title: Text("导入失败"),
                        message: Text(error.localizedDescription),
                        dismissButton: .default(Text("确定"))
                    )
                } else if let song = importedSong {
                    return Alert(
                        title: Text("导入成功"),
                        message: Text("已成功导入音乐：\(song.title)"),
                        dismissButton: .default(Text("确定"))
                    )
                } else {
                    return Alert(
                        title: Text("导入结果"),
                        message: Text("操作已完成"),
                        dismissButton: .default(Text("确定"))
                    )
                }
            }
        }
    }
    
    // 打开系统文档选择器
    private func openSystemDocumentPicker() {
        // 获取SceneDelegate实例并调用showDocumentPicker方法
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let sceneDelegate = windowScene.delegate as? SceneDelegate {
            sceneDelegate.showDocumentPicker()
        }
    }
}

// 文档选择器
struct MusicDocumentPicker: UIViewControllerRepresentable {
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
        let parent: MusicDocumentPicker
        
        init(_ parent: MusicDocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            // 处理用户选择的文档
            var secureURLs: [URL] = []
            
            for url in urls {
                // 开始访问安全范围资源
                if url.startAccessingSecurityScopedResource() {
                    // 尝试创建安全书签，以便稍后访问
                    do {
                        let bookmarkData = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                        // 可以将bookmarkData保存到UserDefaults或其他持久化存储中
                        // 此处只是记录一下，实际使用时处理安全访问
                        print("已创建文件书签")
                    } catch {
                        print("创建书签失败: \(error)")
                    }
                    
                    secureURLs.append(url)
                } else {
                    print("无法访问文件: \(url.lastPathComponent)")
                }
            }
            
            // 调用回调并处理文件
            if !secureURLs.isEmpty {
                parent.onPick(secureURLs)
            }
            
            // 使用后释放安全访问
            // 注意：如果需要长时间访问，应该在使用完毕后再调用
            // 此处假设onPick已完成对文件的处理
            for url in urls {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }
}

struct ImportView_Previews: PreviewProvider {
    static var previews: some View {
        ImportView()
            .environmentObject(MusicLibrary.shared)
    }
} 