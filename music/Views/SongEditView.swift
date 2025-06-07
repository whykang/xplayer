import SwiftUI

struct SongEditView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var musicLibrary = MusicLibrary.shared
    
    @State private var song: Song
    @State private var title: String
    @State private var artist: String
    @State private var albumName: String
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var isImagePickerSourceCamera = false
    @State private var showingActionSheet = false
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var isSaving = false
    @State private var isFetchingCover = false
    
    init(song: Song) {
        self.song = song
        self._title = State(initialValue: song.title)
        self._artist = State(initialValue: song.artist)
        self._albumName = State(initialValue: song.albumName)
        
        // 加载封面图片
        if let coverPath = song.coverImagePath, let image = UIImage(contentsOfFile: coverPath) {
            self._selectedImage = State(initialValue: image)
        } else {
            self._selectedImage = State(initialValue: nil)
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Form {
                    // 专辑封面
                    Section {
                        VStack {
                            HStack {
                                Spacer()
                                if let image = selectedImage {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 200, height: 200)
                                        .cornerRadius(8)
                                } else if let coverPath = song.coverImagePath, let image = UIImage(contentsOfFile: coverPath) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 200, height: 200)
                                        .cornerRadius(8)
                                } else {
                                    Image(systemName: "music.note")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 100, height: 100)
                                        .padding(50)
                                        .foregroundColor(.gray)
                                        .background(Color.gray.opacity(0.2))
                                        .cornerRadius(8)
                                }
                                Spacer()
                            }
                            .padding(.vertical)
                            
                            Button(action: {
                                showingActionSheet = true
                            }) {
                                HStack {
                                    Image(systemName: "photo")
                                    Text("编辑封面")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                        }
                    }
                    
                    // 歌曲信息
                    Section(header: Text("基本信息"), footer: Text("网络获取封面功能需要准确的歌曲名称和艺术家信息").font(.caption).foregroundColor(.secondary)) {
                        HStack {
                            Text("歌曲名称：")
                                .foregroundColor(.secondary)
                            TextField("歌曲名称", text: $title)
                                .autocapitalization(.none)
                        }
                        
                        HStack {
                            Text("艺术家：")
                                .foregroundColor(.secondary)
                            TextField("艺术家", text: $artist)
                                .autocapitalization(.none)
                        }
                        
                        HStack {
                            Text("专辑：")
                                .foregroundColor(.secondary)
                            TextField("专辑", text: $albumName)
                                .autocapitalization(.none)
                        }
                    }
                    
                    // 保存按钮
                    Section {
                        Button(action: saveChanges) {
                            HStack {
                                Spacer()
                                Text("保存更改")
                                    .bold()
                                Spacer()
                            }
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .disabled(isSaving)
                    }
                }
                
                if isSaving {
                    Color.black.opacity(0.3)
                        .edgesIgnoringSafeArea(.all)
                    
                    ProgressView("正在保存...")
                        .padding()
                        .background(Color(UIColor.systemBackground))
                        .cornerRadius(8)
                        .shadow(radius: 10)
                }
            }
            .navigationTitle("编辑歌曲信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .actionSheet(isPresented: $showingActionSheet) {
                ActionSheet(title: Text("选择封面图片来源"), buttons: [
                    .default(Text("从相册选择")) {
                        isImagePickerSourceCamera = false
                        showingImagePicker = true
                    },
                    .default(Text("拍照")) {
                        isImagePickerSourceCamera = true
                        showingImagePicker = true
                    },
                    .default(Text("网络获取")) {
                        fetchCoverFromNetwork()
                    },
                    .destructive(Text("删除封面")) {
                        selectedImage = nil
                    },
                    .cancel()
                ])
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(selectedImage: $selectedImage, sourceType: isImagePickerSourceCamera ? .camera : .photoLibrary)
            }
            .alert(isPresented: $showingAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("确定")) {
                        if alertTitle == "保存成功" {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                )
            }
        }
    }
    
    // 保存修改
    private func saveChanges() {
        isSaving = true
        
        // 在后台线程执行保存操作
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // 创建全新的Song实例，而不是修改原有实例
                var updatedSong = Song(
                    id: song.id,
                    title: title,
                    artist: artist,
                    album: albumName, // 使用新的专辑名
                    duration: song.duration,
                    filePath: song.filePath,
                    lyrics: song.lyrics,
                    coverImagePath: song.coverImagePath,
                    fileSize: song.fileSize,
                    trackNumber: song.trackNumber,
                    year: song.year,
                    albumName: albumName,
                    albumArtist: song.albumArtist,
                    composer: song.composer,
                    genre: song.genre,
                    lyricsFilePath: song.lyricsFilePath,
                    isPinned: song.isPinned,
                    creationDate: song.creationDate
                )
                
                // 如果修改了封面图片
                if let newImage = selectedImage {
                    if let imageData = newImage.jpegData(compressionQuality: 0.8) {
                        // 保存新的封面图片
                        let artworkURL = MusicFileManager.shared.saveArtwork(imageData, for: title)
                        updatedSong.coverImagePath = artworkURL?.path
                    }
                } else if selectedImage == nil && song.coverImagePath != nil {
                    // 用户选择删除封面
                    if let coverPath = song.coverImagePath {
                        try? FileManager.default.removeItem(at: URL(fileURLWithPath: coverPath))
                    }
                    updatedSong.coverImagePath = nil
                }
                
                // 更新歌曲数据
                musicLibrary.updateSong(updatedSong)
                
                // 在主线程更新UI
                DispatchQueue.main.async {
                    isSaving = false
                    alertTitle = "保存成功"
                    alertMessage = "歌曲信息已更新"
                    showingAlert = true
                }
            } catch {
                // 处理错误
                DispatchQueue.main.async {
                    isSaving = false
                    alertTitle = "保存失败"
                    alertMessage = error.localizedDescription
                    showingAlert = true
                }
            }
        }
    }
    
    // 从网络获取封面
    private func fetchCoverFromNetwork() {
        guard !title.isEmpty, !artist.isEmpty else {
            alertTitle = "信息不完整"
            alertMessage = "请先填写歌曲名称和艺术家信息"
            showingAlert = true
            return
        }
        
        isFetchingCover = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            // 清理和拼接查询参数：歌曲名称在前，艺术家在后
            let cleanedArtist = self.cleanStringForHTTP(self.artist)
            let cleanedTitle = self.cleanStringForHTTP(self.title)
            let queryString = "\(cleanedTitle)\(cleanedArtist)"
            
            // 对查询参数进行URL编码
            guard let encodedQuery = queryString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                DispatchQueue.main.async {
                    self.isFetchingCover = false
                    self.alertTitle = "获取失败"
                    self.alertMessage = "查询参数编码失败"
                    self.showingAlert = true
                }
                return
            }
            
            // 构建API请求URL 需要自己实现
            let apiUrlString = ""
            guard let apiUrl = URL(string: apiUrlString) else {
                DispatchQueue.main.async {
                    self.isFetchingCover = false
                    self.alertTitle = "获取失败"
                    self.alertMessage = "无效的API URL"
                    self.showingAlert = true
                }
                return
            }
            
            print("🌐 请求专辑封面API: \(apiUrlString)")
            print("🔍 查询参数: 歌曲名称+艺术家 = \"\(queryString)\"")
            
            // 发起网络请求
            URLSession.shared.dataTask(with: apiUrl) { data, response, error in
                DispatchQueue.main.async {
                    self.isFetchingCover = false
                    
                    if let error = error {
                        print("❌ 网络请求失败: \(error.localizedDescription)")
                        self.alertTitle = "获取失败"
                        self.alertMessage = "网络请求失败: \(error.localizedDescription)"
                        self.showingAlert = true
                        return
                    }
                    
                    guard let data = data else {
                        print("❌ API返回空数据")
                        self.alertTitle = "获取失败"
                        self.alertMessage = "服务器返回空数据"
                        self.showingAlert = true
                        return
                    }
                    
                    // 解析JSON响应
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            print("🔍 解析JSON成功: \(json)")
                            
                            // 检查是否有web_albumpic_short字段
                            if let imageUrl = json["web_albumpic_short"] as? String {
                                print("🎯 找到专辑封面URL: \(imageUrl)")
                                
                                // 下载图片
                                if let url = URL(string: imageUrl) {
                                    URLSession.shared.dataTask(with: url) { imageData, _, imageError in
                                        DispatchQueue.main.async {
                                            if let imageError = imageError {
                                                print("❌ 图片下载失败: \(imageError.localizedDescription)")
                                                self.alertTitle = "获取失败"
                                                self.alertMessage = "图片下载失败"
                                                self.showingAlert = true
                                                return
                                            }
                                            
                                            if let imageData = imageData, let image = UIImage(data: imageData) {
                                                // 成功获取封面，更新显示
                                                self.selectedImage = image
                                                self.alertTitle = "获取成功"
                                                self.alertMessage = "已成功从网络获取专辑封面"
                                                self.showingAlert = true
                                                print("✅ 成功获取专辑封面")
                                            } else {
                                                self.alertTitle = "获取失败"
                                                self.alertMessage = "无法解析图片数据"
                                                self.showingAlert = true
                                            }
                                        }
                                    }.resume()
                                } else {
                                    self.alertTitle = "获取失败"
                                    self.alertMessage = "无效的图片URL"
                                    self.showingAlert = true
                                }
                            } else {
                                print("⚠️ 没有找到专辑封面信息")
                                self.alertTitle = "获取失败"
                                self.alertMessage = "未找到匹配的专辑封面"
                                self.showingAlert = true
                            }
                        } else {
                            self.alertTitle = "获取失败"
                            self.alertMessage = "服务器响应格式错误"
                            self.showingAlert = true
                        }
                    } catch {
                        print("❌ 解析JSON失败: \(error.localizedDescription)")
                        self.alertTitle = "获取失败"
                        self.alertMessage = "解析服务器响应失败"
                        self.showingAlert = true
                    }
                }
            }.resume()
        }
    }
    
    // 清理字符串，去除HTTP请求中的干扰字符
    private func cleanStringForHTTP(_ string: String) -> String {
        // 去除常见的干扰字符和特殊符号
        let unwantedCharacters = CharacterSet(charactersIn: " !@#$%^&*()+=[]{}|\\:;\"'<>?/.,`~")
        return string.components(separatedBy: unwantedCharacters).joined()
    }
} 
