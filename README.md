# WiFi File Manager

局域网文件管理器，支持通过浏览器或 Android App 在手机和电脑之间无线传输、浏览、管理文件。

## 功能特性

### 文件浏览
- 列表/网格双视图，支持缩略图预览
- 文件排序（按名称/大小/日期），每个文件夹独立记忆排序偏好
- 文件夹详情统计（图片/视频/音频/子文件夹数量）
- 隐藏 macOS 元数据文件（`._` 和 `.DS_Store`）

### 文件传输
- 多文件上传、文件夹上传（保持目录结构）
- 文件下载、重命名、删除（移入废纸篓）
- Android SAF 直接读取，无需复制到缓存

### 媒体播放
- 视频播放：支持倍速、循环模式（顺序/随机/单曲循环）、画面适配
- 音频播放：后台播放、系统通知栏控制、迷你播放栏
- 播放进度云端同步，续播支持

### 其他
- 收藏夹、浏览历史、全局搜索
- 废纸篓（恢复/永久删除）
- 登录记住密码
- UDP 局域网自动发现服务器
- 缩略图异步生成（ffmpeg / opencv / PIL）

## 快速开始

### 服务端（Mac / Windows / Linux）

**一键启动：**
- Mac：双击 `WiFiFileManager.command`
- Windows：双击 `WiFiFileManager.bat`

首次运行会自动安装 [uv](https://docs.astral.sh/uv/) 和 Python 依赖。

**手动启动：**
```bash
# 安装 uv（如未安装）
curl -LsSf https://astral.sh/uv/install.sh | sh

# 启动服务
uv run python -m server.main
```

启动后访问 http://localhost:7777

### Android App

从 Releases 下载 APK 安装，或自行编译：
```bash
cd android
flutter build apk --release
```

## 配置

配置文件自动生成在 `config.json`（Mac/Linux）或 `config.win.json`（Windows）：

```json
{
  "port": 7777,
  "password_hash": "",
  "shared_dirs": [
    {"id": "xxx", "path": "/path/to/share", "visible": true}
  ],
  "uploads_dir": "/path/to/uploads",
  "sort_field": "name",
  "sort_ascending": true,
  "sort_prefs": {}
}
```

首次访问时设置密码，通过设置页添加共享文件夹。

## 项目结构

```
├── server/                  # Python 服务端（FastAPI）
│   ├── main.py              # API 路由
│   ├── config.py            # 配置管理
│   ├── file_manager.py      # 文件操作、媒体元数据
│   ├── models.py            # 数据模型
│   └── auth.py              # JWT 认证
├── android/                 # Flutter 客户端（Android + Web）
│   └── lib/
│       ├── screens/         # 页面
│       ├── services/        # API、播放、历史、收藏
│       └── utils/           # 工具函数
├── web/                     # Flutter Web 编译产物
├── config.json              # Mac/Linux 配置
├── config.win.json          # Windows 配置
├── WiFiFileManager.command  # Mac 启动脚本
├── WiFiFileManager.bat      # Windows 启动脚本
└── requirements.txt         # Python 依赖
```

## 分支说明

| 分支 | 用途 |
|------|------|
| `main` | 稳定版本 |
| `mac` | Mac 开发分支 |
| `win` | Windows 开发分支 |

## 技术栈

- **服务端**：Python 3.12+ / FastAPI / Uvicorn
- **客户端**：Flutter / Dart（Android + Web）
- **认证**：JWT
- **缩略图**：ffmpeg / opencv-python / Pillow

## 许可证

MIT
