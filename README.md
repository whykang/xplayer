# 🎵 XPlayer - 简洁高效的iOS音乐播放器

<div align="center">

![XPlayer Logo](https://img.shields.io/badge/XPlayer-Music%20Player-blue?style=for-the-badge&logo=music)
![iOS](https://img.shields.io/badge/iOS-16.0+-black?style=for-the-badge&logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.0+-orange?style=for-the-badge&logo=swift)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

**一款专为iOS设计的简洁、高效的音乐播放器**

[功能特色](#-功能特色) • [应用截图](#-应用截图) • [下载安装](#-下载安装) • [技术架构](#-技术架构) • [贡献指南](#-贡献指南)

</div>

---

## 📲 下载安装

<div align="center">

### 🍎 已上架 App Store

<a href="https://apps.apple.com/app/6744457947">
  <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" width="200">
</a>

**扫码下载**

<img src="https://s21.ax1x.com/2025/06/07/pVi2WWV.png" width="150" alt="App Store下载二维码"/>

*支持iOS 16.0及以上版本*

</div>

---

## 🌟 功能特色

### 🎧 核心播放功能
- **本地音乐播放** - 支持MP3、WAV、M4A、AAC、FLAC等多种音频格式
- **智能歌单管理** - 创建和管理个人歌单，支持收藏功能
- **歌词显示** - 自动获取和显示歌词，支持车机歌词显示
- **专辑封面匹配** - 智能匹配和网络获取专辑封面

### 📱 导入方式
- **文件导入** - 从文件应用直接导入音乐文件
- **本机扫描** - 扫描设备中已有的音乐文件
- **局域网导入** - 通过WiFi从其他设备快速传输音乐
- **扫一扫导入** - 二维码快速导入功能

### 🎯 个性化体验
- **多种排序方式** - 按时长、艺术家、专辑、导入时间、首字母排序
- **外观模式选择** - 支持浅色、深色、跟随系统模式
- **主标签自定义** - 可调整主界面标签顺序
- **播放状态记忆** - 保存播放进度和状态

### 🔧 高级功能
- **WebDAV备份** - 支持音乐库备份与恢复
- **路径迁移** - 智能处理iOS应用更新后的路径变化
- **重复文件检测** - 导入时自动检测并处理重复文件
- **批量操作** - 支持批量导入和管理

---

## 📱 应用截图

<div align="center">
<img src="https://s21.ax1x.com/2025/06/07/pVi24QU.png" width="200" alt="主界面"/> 
<img src="https://s21.ax1x.com/2025/06/07/pVi2IL4.png" width="200" alt="主界面"/> 
<img src="https://s21.ax1x.com/2025/06/07/pVi26ds.png" width="200" alt="主界面"/> 
<img src="https://s21.ax1x.com/2025/06/07/pVi2rLQ.png" width="200" alt="播放界面"/> 
<img src="https://s21.ax1x.com/2025/06/07/pVi2yZj.png" width="200" alt="歌词显示"/>
<img src="https://s21.ax1x.com/2025/06/07/pVi2Dsg.png" width="200" alt="设置页面"/>



</div>

---

## 🚀 开发环境安装

### 系统要求
- **iOS 16.0** 或更高版本
- **Xcode 12.0** 或更高版本（开发环境）
- **Swift 5.0** 或更高版本

### 安装步骤

1. **克隆项目**
   ```bash
   git clone https://github.com/yourusername/XPlayer.git
   cd XPlayer
   ```

2. **打开项目**
   ```bash
   open music.xcodeproj
   ```

3. **配置签名**
   - 在Xcode中选择你的开发者账号
   - 配置Bundle Identifier

4. **运行应用**
   - 选择目标设备或模拟器
   - 点击运行按钮或使用 `Cmd + R`

---

## 🏗 技术架构

### 核心技术栈
- **SwiftUI** - 现代化的用户界面框架
- **AVFoundation** - 音频播放和处理
- **Combine** - 响应式编程
- **Network** - 局域网服务器实现

### 项目结构
```
XPlayer/
├── Models/           # 数据模型
│   ├── Song.swift
│   ├── MusicLibrary.swift
│   ├── MusicPlayer.swift
│   └── WebServerManager.swift
├── Views/            # 用户界面
│   ├── MainTabView.swift
│   ├── PlayerDetailView.swift
│   ├── LANImportView.swift
│   └── SettingsView.swift
├── Managers/         # 业务逻辑管理器
│   ├── MusicFileManager.swift
│   └── WebDAVBackupManager.swift
└── Resources/        # 资源文件
    ├── Assets.xcassets
    └── Info.plist
```

### 核心功能实现

#### 🎵 音频播放引擎
```swift
class MusicPlayer: ObservableObject {
    private var audioPlayer: AVAudioPlayer?
    @Published var currentSong: Song?
    @Published var isPlaying: Bool = false
    
    func play(song: Song) {
        // 播放逻辑实现
    }
}
```

#### 🌐 局域网导入服务器
```swift
class WebServerManager: ObservableObject {
    private var serverSocket: Int32 = -1
    
    func startServer() -> String {
        // HTTP服务器启动逻辑
    }
}
```

---

## 🎯 主要特性详解


### 🌐 局域网导入功能
创建临时HTTP服务器，支持从其他设备快速传输音乐：

- 自动获取设备IP地址
- 生成二维码便于访问
- 支持大文件传输
- 实时传输进度显示

### 🎤 智能歌词功能
- 本地歌词文件支持
- 网络歌词自动获取
- 车机显示模式
- 实时歌词同步

---

## 🤝 贡献指南

我们欢迎任何形式的贡献！无论是bug修复、功能增强还是文档改进。

### 贡献流程

1. **Fork 项目**
2. **创建功能分支** (`git checkout -b feature/AmazingFeature`)
3. **提交更改** (`git commit -m 'Add some AmazingFeature'`)
4. **推送分支** (`git push origin feature/AmazingFeature`)
5. **创建 Pull Request**

### 开发规范

- 遵循Swift代码规范
- 添加必要的注释和文档
- 确保新功能包含测试
- 保持代码风格一致

---

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情

---



## 👨‍💻 开发者

**Wang Hongyue**

- Email: kangkangwhy@gmail.com

---

<div align="center">

**⭐ 如果这个项目对你有帮助，请给个星标支持一下！**

![Stars](https://img.shields.io/github/stars/yourusername/XPlayer?style=social)
![Forks](https://img.shields.io/github/forks/yourusername/XPlayer?style=social)
![Issues](https://img.shields.io/github/issues/yourusername/XPlayer)

**📱 立即下载体验完整功能**

</div>
