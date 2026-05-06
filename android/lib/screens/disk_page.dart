import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/format_utils.dart';

class DiskPage extends StatefulWidget {
  final ApiService api;
  final void Function(String path, String name)? onOpenDisk;

  const DiskPage({super.key, required this.api, this.onOpenDisk});

  @override
  State<DiskPage> createState() => _DiskPageState();
}

class _DiskPageState extends State<DiskPage> {
  List<dynamic> _disks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final disks = await widget.api.getDisks();
      if (mounted) setState(() { _disks = disks; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: _disks.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 200),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.album, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text('未检测到外接磁盘', style: TextStyle(fontSize: 15, color: Colors.grey.shade500)),
                      const SizedBox(height: 4),
                      Text('连接外接硬盘后下拉刷新', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
                    ],
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _disks.length,
              itemBuilder: (_, i) => _buildDiskCard(_disks[i]),
            ),
    );
  }

  Widget _buildDiskCard(Map<String, dynamic> disk) {
    final name = disk['name'] as String;
    final path = disk['path'] as String;
    final total = disk['total'] as int;
    final free = disk['free'] as int;
    final used = total - free;
    final usedPercent = total > 0 ? used / total : 0.0;
    final isExternal = path.startsWith('/Volumes/');
    final color = isExternal ? Colors.blue : Colors.teal;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: widget.onOpenDisk != null ? () => widget.onOpenDisk!(path, name) : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(isExternal ? Icons.usb : Icons.computer, color: color, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        Text(path, style: TextStyle(fontSize: 11, color: Colors.grey.shade500), overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  if (widget.onOpenDisk != null)
                    Icon(Icons.chevron_right, color: Colors.grey.shade400),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: usedPercent,
                  minHeight: 8,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(
                    usedPercent > 0.9 ? Colors.red : usedPercent > 0.7 ? Colors.orange : color,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('已用 ${formatSize(used)}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  Text('可用 ${formatSize(free)}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  Text('共 ${formatSize(total)}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${(usedPercent * 100).toStringAsFixed(1)}% 已使用',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
