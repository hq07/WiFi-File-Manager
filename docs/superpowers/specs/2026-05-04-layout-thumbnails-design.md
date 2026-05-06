# 文件列表布局与缩略图功能设计

## 概述

在文件列表页面（`FileListScreen`）新增列表/网格双布局切换，并在设置页提供布局配置，包括缩略图显示和文件元数据开关。

## 功能需求

### 1. 布局切换按钮

- 在 `FileListScreen` 的 AppBar 右侧添加布局切换图标按钮
- 点击在「列表视图」和「网格视图」之间切换
- 切换即时生效，无需刷新

### 2. 列表视图（增强版）

在现有 `ListTile` 基础上增加：
- 左侧缩略图（图片文件）或类型图标（其他文件）
- 文件名下方显示可配置的元数据行

### 3. 网格视图

- 使用 `GridView.builder` 展示
- 每个单元格：正方形缩略图/图标 + 文件名 + 元数据
- 列数可在设置中配置（2/3/4列）

### 4. 缩略图

- 图片文件（jpg/png/gif/webp/bmp）调用 `getPreviewUrl(path)` 加载真实缩略图
- 其他文件类型显示对应 Material 图标
- 设置中可关闭缩略图加载（省流量）

### 5. 文件元数据（每个可开关）

| 字段 | 来源 | 说明 |
|------|------|------|
| 文件大小 | `item['size']` | 已有，格式化显示 |
| 修改日期 | `item['modified']` | 已有 |
| 文件扩展名 | 从文件名解析 | 客户端计算 |
| 时长 | 服务端新增字段 | 音视频文件，需 ffprobe |
| 分辨率 | 服务端新增字段 | 图片/视频文件，需 PIL/ffprobe |

## 服务端改动

### 扩展 `FileItem` 模型

在 `server/models.py` 的 `FileItem` 中增加可选字段：

```python
class FileItem(BaseModel):
    name: str
    type: str
    size: int
    modified: str
    duration: float | None = None    # 秒，音视频文件
    resolution: str | None = None    # "1920x1080"，图片/视频文件
```

### 修改 `list_files()` 函数

在遍历文件时，对图片和音视频文件提取元数据：
- 图片：用 PIL 读取分辨率
- 音视频：用 ffprobe 读取时长和分辨率
- 提取失败时字段返回 `null`，不影响列表加载
- 仅在文件小于一定大小（如 500MB）时提取，避免卡顿

## 客户端改动

### 新增设置持久化

使用 `SharedPreferences` 存储布局设置：

```
layout_mode: "list" | "grid"          // 默认 "list"
show_thumbnails: bool                  // 默认 true
grid_columns: 2 | 3 | 4              // 默认 3
show_size: bool                        // 默认 true
show_date: bool                        // 默认 true
show_extension: bool                   // 默认 false
show_duration: bool                    // 默认 true
show_resolution: bool                  // 默认 true
```

### 设置页面新增「显示布局」区域

在 `SettingsScreen` 中添加：
- 默认布局选择（列表/网格 SegmentedButton）
- 显示缩略图开关
- 网格列数选择（2/3/4）
- 文件信息开关：大小、日期、扩展名、时长、分辨率

### `FileListScreen` 改动

1. AppBar 添加切换按钮（`Icons.view_list` / `Icons.grid_view`）
2. 读取设置决定当前布局模式
3. 列表模式：在现有 `ListTile` 基础上增加缩略图和元数据
4. 网格模式：用 `GridView.builder` + 缩略图卡片
5. 缩略图使用 `Image.network(getPreviewUrl(path))` + 占位图标 + 错误兜底

## 涉及文件

| 文件 | 改动 |
|------|------|
| `server/models.py` | FileItem 增加 duration/resolution |
| `server/main.py` | list_files 提取元数据 |
| `android/lib/screens/file_list_screen.dart` | 双布局 + 缩略图 + 元数据 |
| `android/lib/screens/settings_screen.dart` | 布局设置区域 |
| `android/lib/services/layout_prefs.dart` | 新建，封装 SharedPreferences |
