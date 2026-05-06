import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/history_service.dart';
import '../utils/format_utils.dart';
import 'media_player_screen.dart';
import 'widgets/preview_image.dart';

class HistoryPage extends StatefulWidget {
  final ApiService api;
  final HistoryService historyService;
  final ValueNotifier<int>? historyRefresh;
  const HistoryPage({super.key, required this.api, required this.historyService, this.historyRefresh});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  static const _imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};
  static const _videoExts = {'mp4', 'avi', 'mkv', 'mov', 'webm'};
  static const _audioExts = {'mp3', 'wav', 'flac', 'aac', 'ogg'};

  late List<HistoryItem> _history;

  @override
  void initState() {
    super.initState();
    _history = widget.historyService.getHistory();
    widget.historyRefresh?.addListener(_onRefresh);
  }

  @override
  void dispose() {
    widget.historyRefresh?.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() {
    if (mounted) setState(() => _history = widget.historyService.getHistory());
  }

  Future<void> _refresh() async {
    setState(() => _history = widget.historyService.getHistory());
  }

  IconData _fileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    if (_videoExts.contains(ext)) return Icons.video_file;
    if (_audioExts.contains(ext)) return Icons.audio_file;
    if (_imageExts.contains(ext)) return Icons.image;
    return Icons.insert_drive_file;
  }

  bool _hasPreview(String name) {
    final ext = name.split('.').last.toLowerCase();
    return _imageExts.contains(ext) || _videoExts.contains(ext);
  }

  Widget _buildLeading(HistoryItem item) {
    final ext = item.name.split('.').last.toLowerCase();
    final isVideo = _videoExts.contains(ext);
    final fallback = SizedBox(
      width: 56, height: 56,
      child: Icon(_fileIcon(item.name), size: 32, color: Colors.teal),
    );
    if (_hasPreview(item.name)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 56, height: 56,
          child: PreviewImage(
            key: ValueKey(item.path),
            url: widget.api.getPreviewUrl(item.path, thumbnail: isVideo),
            headers: widget.api.previewHeaders,
            fit: BoxFit.cover,
            fallback: fallback,
          ),
        ),
      );
    }
    return fallback;
  }

  void _openItem(HistoryItem item) {
    final ext = item.name.split('.').last.toLowerCase();
    final isMedia = _imageExts.contains(ext) || _videoExts.contains(ext) || _audioExts.contains(ext);
    // Pass all same-type history items for swipe/playlist navigation
    final allFiles = isMedia
        ? _history
            .where((h) {
              final e = h.name.split('.').last.toLowerCase();
              return _imageExts.contains(e) || _videoExts.contains(e) || _audioExts.contains(e);
            })
            .map((h) => {'name': h.name, 'size': h.size, 'path': h.path})
            .toList()
        : <Map<String, dynamic>>[{'name': item.name, 'size': item.size, 'path': item.path}];
    final positionMs = item.completed ? 0 : item.lastPositionMs;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaPlayerScreen(
          api: widget.api,
          historyService: widget.historyService,
          filePath: item.path,
          fileName: item.name,
          directoryFiles: allFiles,
          initialPositionMs: positionMs,
        ),
      ),
    ).then((_) {
      _refresh();
      widget.historyRefresh?.value++;
    });
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除播放历史'),
        content: const Text('确定要清除所有播放记录吗？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await widget.historyService.clearHistory();
      setState(() => _history = []);
    }
  }

  Widget _buildSubtitle(HistoryItem item) {
    final date = DateTime.tryParse(item.playedAt);
    final timeStr = date != null
        ? '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
        : '';
    final meta = '${formatSize(item.size)}${timeStr.isNotEmpty ? ' · $timeStr' : ''}';
    final progress = item.progress;
    if (progress <= 0 && !item.completed) {
      return Text(meta, style: const TextStyle(fontSize: 12));
    }
    final percent = item.completed ? 100 : (progress * 100).round();
    final color = item.completed ? Colors.green : Colors.teal;
    final label = item.completed ? '已看完' : '已看 $percent%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(meta, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: item.completed ? 1.0 : progress,
                  minHeight: 4,
                  backgroundColor: Colors.grey.shade300,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_history.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          children: [
            const SizedBox(height: 200),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text('还没有播放记录', style: TextStyle(fontSize: 15, color: Colors.grey.shade500)),
                  const SizedBox(height: 4),
                  Text('播放音视频文件后会自动记录', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Text('共 ${_history.length} 条记录', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              const Spacer(),
              TextButton(
                onPressed: _clearAll,
                child: const Text('清除全部', style: TextStyle(fontSize: 13, color: Colors.red)),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: _history.length,
              itemBuilder: (_, i) {
                final item = _history[i];
                return ListTile(
                  leading: _buildLeading(item),
                  title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: _buildSubtitle(item),
                  onTap: () => _openItem(item),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
