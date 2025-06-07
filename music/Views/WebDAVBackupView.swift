import SwiftUI

struct WebDAVBackupView: View {
    @ObservedObject private var backupManager = WebDAVBackupManager.shared
    @ObservedObject private var userSettings = UserSettings.shared
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var isTestingConnection = false
    @State private var showPassword = false
    @State private var showingBackupConfirmation = false
    @State private var showingRestoreConfirmation = false
    @State private var availableBackups: [String] = []
    @State private var isLoadingBackups = false
    @State private var selectedBackupFolder: String = ""
    @State private var showingBackupSelector = false
    @Environment(\.presentationMode) var presentationMode
    
    // 格式化上次备份时间
    private var lastBackupText: String {
        guard let date = userSettings.lastBackupDate else {
            return "从未备份"
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // 格式化备份文件夹名称为可读时间
    private func formatBackupDate(_ backupFolder: String) -> String {
        if let range = backupFolder.range(of: "MusicBackup_") {
            let timestampString = String(backupFolder[range.upperBound...])
            
            // 处理可能包含小数点的时间戳
            if timestampString.contains(".") {
                let components = timestampString.components(separatedBy: ".")
                if let mainPart = components.first, let timeInterval = TimeInterval(mainPart) {
                    let date = Date(timeIntervalSince1970: timeInterval)
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .short
                    return formatter.string(from: date)
                }
            }
            
            // 尝试直接解析整个时间戳
            if let timeInterval = TimeInterval(timestampString) {
                // 尝试完整解析（包括小数点）
                let date = Date(timeIntervalSince1970: timeInterval)
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                return formatter.string(from: date)
            }
        }
        return backupFolder
    }
    
    var body: some View {
        List {
            Section(header: Text("WebDAV服务器信息")) {
                TextField("服务器地址", text: $userSettings.webdavServer)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                
                TextField("用户名", text: $userSettings.webdavUsername)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                
                HStack {
                    if showPassword {
                        TextField("密码", text: $userSettings.webdavPassword)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    } else {
                        SecureField("密码", text: $userSettings.webdavPassword)
                    }
                    
                    Button(action: {
                        showPassword.toggle()
                    }) {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundColor(.gray)
                    }
                }
                
                TextField("备份目录", text: $userSettings.webdavDirectory)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                
                Button(action: testConnection) {
                    HStack {
                        Text("测试连接")
                        Spacer()
                        if isTestingConnection {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "network")
                        }
                    }
                }
                .disabled(isTestingConnection || !isServerInfoValid)
            }
            
            Section(header: Text("备份与恢复")) {
                HStack {
                    Text("上次备份时间")
                    Spacer()
                    Text(lastBackupText)
                        .foregroundColor(.secondary)
                }
                
                Button(action: {
                    print("WebDAV视图: 开始备份按钮被点击")
                    // 检查按钮是否被禁用
                    if backupManager.isBackingUp || backupManager.isRestoring || !isServerInfoValid {
                        print("WebDAV视图: 备份按钮点击但被禁用 - isBackingUp=\(backupManager.isBackingUp), isRestoring=\(backupManager.isRestoring), isServerInfoValid=\(isServerInfoValid)")
                        return
                    }
                    
                    print("WebDAV视图: 即将显示备份确认对话框")
                    DispatchQueue.main.async {
                        self.showingBackupConfirmation = true
                        print("WebDAV视图: 已设置showingBackupConfirmation = \(self.showingBackupConfirmation)")
                    }
                }) {
                    HStack {
                        Text("开始备份")
                        Spacer()
                        if backupManager.isBackingUp {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.up.doc")
                        }
                    }
                    .foregroundColor(backupManager.isBackingUp || backupManager.isRestoring || !isServerInfoValid ? .gray : .blue)
                }
                .disabled(backupManager.isBackingUp || backupManager.isRestoring || !isServerInfoValid)
                
                Button(action: {
                    print("WebDAV视图: 开始恢复按钮被点击")
                    // 检查按钮是否被禁用
                    if backupManager.isBackingUp || backupManager.isRestoring || !isServerInfoValid {
                        print("WebDAV视图: 恢复按钮点击但被禁用 - isBackingUp=\(backupManager.isBackingUp), isRestoring=\(backupManager.isRestoring), isServerInfoValid=\(isServerInfoValid)")
                        return
                    }
                    
                    print("WebDAV视图: 准备加载备份列表")
                    loadBackups()
                }) {
                    HStack {
                        Text("查看备份")
                        Spacer()
                        if isLoadingBackups {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "folder")
                        }
                    }
                    .foregroundColor(backupManager.isBackingUp || backupManager.isRestoring || !isServerInfoValid ? .gray : .blue)
                }
                .disabled(backupManager.isBackingUp || backupManager.isRestoring || !isServerInfoValid)
                
                Button(action: {
                    // 打开WebDAV设置教程网页
                    if let url = URL(string: "https://help.jianguoyun.com/?p=2064") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Text("查看教程")
                        Spacer()
                        Image(systemName: "book")
                    }
                }
            }
            
            if !availableBackups.isEmpty {
                Section(header: Text("可用备份")) {
                    ForEach(availableBackups, id: \.self) { backup in
                        Button(action: {
                            selectedBackupFolder = backup
                            showingRestoreConfirmation = true
                        }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(formatBackupDate(backup))
                                        .font(.headline)
                                    Text(backup)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                Image(systemName: "arrow.down.doc")
                            }
                        }
                        .disabled(backupManager.isBackingUp || backupManager.isRestoring)
                    }
                }
            }
            
            if backupManager.isBackingUp || backupManager.isRestoring {
                Section(header: Text("进度")) {
                    Text(backupManager.statusMessage)
                        .foregroundColor(.secondary)
                    
                    ProgressView(value: Float(backupManager.progress), total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle())
                }
            }
        }
        .navigationTitle("WebDAV备份")
        .navigationBarItems(trailing: Button("完成") {
            presentationMode.wrappedValue.dismiss()
        })
        .alert(isPresented: $showingAlert) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                dismissButton: .default(Text("确定"))
            )
        }
        .sheet(isPresented: $showingBackupConfirmation) {
            VStack(spacing: 20) {
                Text("备份到WebDAV")
                    .font(.headline)
                    .padding(.top, 20)
                
                Text("这将备份您的音乐文件到WebDAV服务器。")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                HStack(spacing: 20) {
                    Button(action: {
                        print("WebDAV视图: 取消备份操作")
                        showingBackupConfirmation = false
                    }) {
                        Text("取消")
                            .frame(minWidth: 100)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                    }
                    
                    Button(action: {
                        print("WebDAV视图: 确认执行备份操作")
                        showingBackupConfirmation = false
                        startBackup()
                    }) {
                        Text("开始备份")
                            .frame(minWidth: 100)
                            .padding()
                            .background(Color.red.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(12)
            .padding()
        }
        .sheet(isPresented: $showingRestoreConfirmation) {
            VStack(spacing: 20) {
                Text("从备份恢复")
                    .font(.headline)
                    .padding(.top, 20)
                
                Text("您将从备份 \(formatBackupDate(selectedBackupFolder)) 恢复音乐文件。")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                HStack(spacing: 20) {
                    Button(action: {
                        print("WebDAV视图: 取消恢复操作")
                        showingRestoreConfirmation = false
                    }) {
                        Text("取消")
                            .frame(minWidth: 100)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                    }
                    
                    Button(action: {
                        print("WebDAV视图: 确认执行恢复操作")
                        showingRestoreConfirmation = false
                        startRestore(from: selectedBackupFolder)
                    }) {
                        Text("开始恢复")
                            .frame(minWidth: 100)
                            .padding()
                            .background(Color.red.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(12)
            .padding()
        }
    }
    
    // 服务器信息是否有效
    private var isServerInfoValid: Bool {
        !userSettings.webdavServer.isEmpty &&
        !userSettings.webdavUsername.isEmpty &&
        !userSettings.webdavPassword.isEmpty
    }
    
    // 测试WebDAV连接
    private func testConnection() {
        isTestingConnection = true
        
        backupManager.checkConnection { success, message in
            isTestingConnection = false
            alertTitle = success ? "连接成功" : "连接失败"
            alertMessage = message
            showingAlert = true
        }
    }
    
    // 加载备份列表
    private func loadBackups() {
        isLoadingBackups = true
        availableBackups = []
        
        backupManager.listBackupFiles { success, backups, message in
            isLoadingBackups = false
            
            if success && !backups.isEmpty {
                // 按时间戳排序，最新的备份在前面
                self.availableBackups = backups.sorted { folder1, folder2 -> Bool in
                    // 提取时间戳并比较
                    if let range1 = folder1.range(of: "MusicBackup_"),
                       let range2 = folder2.range(of: "MusicBackup_") {
                        let timestamp1 = String(folder1[range1.upperBound...])
                        let timestamp2 = String(folder2[range2.upperBound...])
                        return timestamp1 > timestamp2
                    }
                    return folder1 > folder2
                }
            } else {
                alertTitle = "获取备份列表"
                alertMessage = message
                showingAlert = true
            }
        }
    }
    
    // 开始备份
    private func startBackup() {
        print("WebDAV视图: startBackup方法被调用")
        print("WebDAV视图: 准备开始备份，调用backupManager.startBackup()")
        
        // 检查设置是否有效
        if !isServerInfoValid {
            print("WebDAV视图: 服务器设置无效，无法开始备份")
            alertTitle = "备份失败"
            alertMessage = "WebDAV设置不完整"
            showingAlert = true
            return
        }
        
        // 打印当前设置信息（不含密码）
        print("WebDAV视图: 使用的服务器地址: \(userSettings.webdavServer)")
        print("WebDAV视图: 使用的用户名: \(userSettings.webdavUsername)")
        print("WebDAV视图: 使用的备份目录: \(userSettings.webdavDirectory)")
        
        print("WebDAV视图: 当前备份状态: isBackingUp=\(backupManager.isBackingUp)")
        
        // 将startBackup也放在主线程执行，确保UI更新
        DispatchQueue.main.async {
            print("WebDAV视图: 在主线程上调用backupManager.startBackup()")
            self.backupManager.startBackup { success, message in
                print("WebDAV视图: 备份完成回调 - 成功: \(success), 消息: \(message)")
                self.alertTitle = success ? "备份成功" : "备份失败"
                self.alertMessage = message
                self.showingAlert = true
            }
        }
    }
    
    // 开始恢复
    private func startRestore(from backupFolder: String) {
        print("WebDAV视图: 准备从备份文件夹恢复: \(backupFolder)")
        
        backupManager.startRestore(backupFolder: backupFolder) { success, message in
            print("WebDAV视图: 恢复完成回调 - 成功: \(success), 消息: \(message)")
            self.alertTitle = success ? "恢复成功" : "恢复失败"
            self.alertMessage = message
            self.showingAlert = true
        }
    }
} 