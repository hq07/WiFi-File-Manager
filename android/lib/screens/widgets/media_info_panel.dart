import 'package:flutter/material.dart';
import '../../utils/format_utils.dart';

class MediaInfoPanel extends StatelessWidget {
  final String fileName;
  final int? fileSize;
  final String? resolution;
  final String? duration;
  final String? format;
  final String? dimensions;
  final String? modifiedDate;
  final String? filePath;

  const MediaInfoPanel({
    super.key,
    required this.fileName,
    this.fileSize,
    this.resolution,
    this.duration,
    this.format,
    this.dimensions,
    this.modifiedDate,
    this.filePath,
  });

  static void show(BuildContext context, {
    required String fileName,
    int? fileSize,
    String? resolution,
    String? duration,
    String? format,
    String? dimensions,
    String? modifiedDate,
    String? filePath,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (_) => MediaInfoPanel(
        fileName: fileName,
        fileSize: fileSize,
        resolution: resolution,
        duration: duration,
        format: format,
        dimensions: dimensions,
        modifiedDate: modifiedDate,
        filePath: filePath,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelStyle = TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 13);
    final valueStyle = TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('媒体信息', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87)),
            const SizedBox(height: 16),
            _row('文件名', fileName, labelStyle, valueStyle),
            if (fileSize != null) _row('大小', formatSize(fileSize!), labelStyle, valueStyle),
            if (resolution != null) _row('分辨率', resolution!, labelStyle, valueStyle),
            if (dimensions != null) _row('尺寸', dimensions!, labelStyle, valueStyle),
            if (duration != null) _row('时长', duration!, labelStyle, valueStyle),
            if (format != null) _row('格式', format!, labelStyle, valueStyle),
            if (modifiedDate != null) _row('修改日期', modifiedDate!, labelStyle, valueStyle),
            if (filePath != null) _row('路径', filePath!, labelStyle, valueStyle, selectable: true),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, TextStyle labelStyle, TextStyle valueStyle, {bool selectable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: labelStyle),
          const SizedBox(width: 16),
          Expanded(
            child: selectable
                ? SelectableText(value, style: valueStyle, textAlign: TextAlign.end)
                : Text(value, style: valueStyle, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}
