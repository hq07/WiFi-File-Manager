import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 显示可复制的 SnackBar
void showCopyableSnackBar(BuildContext context, String message, {bool isError = false, Duration? duration}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: GestureDetector(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: message));
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
          );
        },
        child: SelectableText(
          message,
          style: TextStyle(color: isError ? Colors.red.shade100 : null),
        ),
      ),
      duration: duration ?? const Duration(seconds: 4),
      action: SnackBarAction(
        label: '复制',
        textColor: Colors.white,
        onPressed: () {
          Clipboard.setData(ClipboardData(text: message));
        },
      ),
    ),
  );
}
