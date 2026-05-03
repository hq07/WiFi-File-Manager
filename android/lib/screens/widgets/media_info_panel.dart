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

  const MediaInfoPanel({
    super.key,
    required this.fileName,
    this.fileSize,
    this.resolution,
    this.duration,
    this.format,
    this.dimensions,
    this.modifiedDate,
  });

  static void show(BuildContext context, {
    required String fileName,
    int? fileSize,
    String? resolution,
    String? duration,
    String? format,
    String? dimensions,
    String? modifiedDate,
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
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, TextStyle labelStyle, TextStyle valueStyle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: labelStyle), Text(value, style: valueStyle)],
      ),
    );
  }
}
