String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String getLanguageName(String ext) {
  const map = {
    'py': 'Python', 'js': 'JavaScript', 'ts': 'TypeScript',
    'json': 'JSON', 'html': 'HTML', 'htm': 'HTML', 'css': 'CSS',
    'md': 'Markdown', 'yaml': 'YAML', 'yml': 'YAML', 'go': 'Go',
    'rs': 'Rust', 'java': 'Java', 'c': 'C', 'cpp': 'C++', 'h': 'C/C++ Header',
    'sh': 'Shell', 'bash': 'Shell', 'sql': 'SQL', 'xml': 'XML', 'toml': 'TOML',
    'txt': 'Plain Text', 'csv': 'CSV', 'log': 'Log',
  };
  return map[ext] ?? ext.toUpperCase();
}

String getHighlightLanguage(String ext) {
  const map = {
    'py': 'python', 'js': 'javascript', 'ts': 'typescript',
    'json': 'json', 'html': 'html', 'htm': 'html', 'css': 'css',
    'md': 'markdown', 'yaml': 'yaml', 'yml': 'yaml', 'go': 'go',
    'rs': 'rust', 'java': 'java', 'c': 'c', 'cpp': 'cpp', 'h': 'c',
    'sh': 'bash', 'bash': 'bash', 'sql': 'sql', 'xml': 'xml', 'toml': 'ini',
  };
  return map[ext] ?? '';
}

bool isCodeFile(String ext) {
  return ['py', 'js', 'ts', 'json', 'html', 'htm', 'css', 'go', 'rs',
          'java', 'c', 'cpp', 'h', 'sh', 'bash', 'sql', 'xml', 'toml',
          'yaml', 'yml'].contains(ext);
}
