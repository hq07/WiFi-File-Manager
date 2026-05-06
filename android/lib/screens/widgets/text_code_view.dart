import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../services/api_service.dart';
import '../../services/history_service.dart';
import '../../utils/format_utils.dart';
import 'media_info_panel.dart';

class TextCodeView extends StatefulWidget {
  final ApiService api;
  final String filePath;
  final String fileName;
  final int? fileSize;
  final HistoryService? historyService;

  const TextCodeView({
    super.key,
    required this.api,
    required this.filePath,
    required this.fileName,
    this.fileSize,
    this.historyService,
  });

  @override
  State<TextCodeView> createState() => _TextCodeViewState();
}

class _TextCodeViewState extends State<TextCodeView> {
  String? _content;
  bool _loading = true;
  String? _error;

  bool _searchVisible = false;
  String _searchQuery = '';
  List<int> _matchLines = [];
  int _currentMatchIndex = -1;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  late bool _wordWrap;
  int _themeIndex = 0; // 0=auto, 1=mocha, 2=github, 3=monokai

  String get _ext => widget.fileName.contains('.')
      ? widget.fileName.split('.').last.toLowerCase()
      : '';

  @override
  void initState() {
    super.initState();
    _wordWrap = !isCodeFile(_ext);
    _loadContent();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadContent() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await Dio().get<String>(widget.api.getPreviewUrl(widget.filePath));
      setState(() {
        _content = resp.data ?? '';
        _loading = false;
      });
      widget.historyService?.addEntry(
        name: widget.fileName,
        path: widget.filePath,
        dirPath: widget.filePath.substring(0, widget.filePath.lastIndexOf('/')),
        size: widget.fileSize ?? 0,
      );
    } catch (e) {
      setState(() {
        _error = '加载失败: $e';
        _loading = false;
      });
    }
  }

  // ── Theme colors ──────────────────────────────────────────────────────

  bool _isDarkEffective(BuildContext context) {
    switch (_themeIndex) {
      case 1:
        return true;
      case 2:
        return false;
      case 3:
        return true;
      default:
        return Theme.of(context).brightness == Brightness.dark;
    }
  }

  Color _bgColor(BuildContext context) {
    final dark = _isDarkEffective(context);
    switch (_themeIndex) {
      case 1:
        return const Color(0xFF282c34); // Atom One Dark
      case 2:
        return const Color(0xFFffffff); // GitHub
      case 3:
        return const Color(0xFF272822); // Monokai
      default:
        return dark ? const Color(0xFF1e1e2e) : const Color(0xFFffffff);
    }
  }

  Color _fgColor(BuildContext context) {
    final dark = _isDarkEffective(context);
    return dark ? Colors.white : Colors.black87;
  }

  Color _mutedColor(BuildContext context) {
    final dark = _isDarkEffective(context);
    return dark ? Colors.white38 : Colors.black38;
  }

  Color _matchBg(BuildContext context) {
    final dark = _isDarkEffective(context);
    return dark ? const Color(0xFF2a2300) : const Color(0xFFfff8e1);
  }

  Color _currentMatchBg(BuildContext context) {
    final dark = _isDarkEffective(context);
    return dark ? const Color(0xFF3d2f00) : const Color(0xFFfff3cd);
  }

  Color _surfaceColor(BuildContext context) {
    final dark = _isDarkEffective(context);
    return dark ? const Color(0xFF1a1a2e) : const Color(0xFFf5f5f5);
  }

  // ── Search logic ──────────────────────────────────────────────────────

  void _onSearchChanged(String query) {
    if (_content == null) return;
    final lines = _content!.split('\n');
    final q = query.toLowerCase();
    final matches = <int>[];
    for (var i = 0; i < lines.length; i++) {
      if (q.isNotEmpty && lines[i].toLowerCase().contains(q)) {
        matches.add(i);
      }
    }
    setState(() {
      _searchQuery = query;
      _matchLines = matches;
      _currentMatchIndex = matches.isEmpty ? -1 : 0;
    });
    if (matches.isNotEmpty) _scrollToMatch();
  }

  void _nextMatch() {
    if (_matchLines.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex + 1) % _matchLines.length;
    });
    _scrollToMatch();
  }

  void _prevMatch() {
    if (_matchLines.isEmpty) return;
    setState(() {
      _currentMatchIndex =
          (_currentMatchIndex - 1 + _matchLines.length) % _matchLines.length;
    });
    _scrollToMatch();
  }

  void _scrollToMatch() {
    if (_currentMatchIndex < 0 || _currentMatchIndex >= _matchLines.length) return;
    final lineIdx = _matchLines[_currentMatchIndex];
    final target = lineIdx * 22.0; // approx line height (13 * 1.6 ≈ 20.8 ≈ 22)
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(_fgColor(context)),
            ),
            const SizedBox(height: 12),
            Text('正在加载...', style: TextStyle(color: _mutedColor(context))),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center,
                  style: TextStyle(color: _fgColor(context))),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _loadContent,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final bg = _bgColor(context);

    return Container(
      color: bg,
      child: Column(
        children: [
          _buildTopBar(context),
          if (_searchVisible) _buildSearchBar(context),
          Expanded(child: _buildContent(context)),
          _buildStatusBar(context),
        ],
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────

  Widget _buildTopBar(BuildContext context) {
    final fg = _fgColor(context);
    final surface = _surfaceColor(context);

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      color: surface,
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: fg),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Text(
              widget.fileName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          IconButton(
            icon: Icon(_searchVisible ? Icons.close : Icons.search, color: fg, size: 20),
            onPressed: () {
              setState(() {
                _searchVisible = !_searchVisible;
                if (!_searchVisible) {
                  _searchController.clear();
                  _searchQuery = '';
                  _matchLines = [];
                  _currentMatchIndex = -1;
                }
              });
            },
          ),
          IconButton(
            icon: Icon(Icons.palette, color: fg, size: 20),
            onPressed: _showThemePicker,
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: fg, size: 20),
            color: surface,
            onSelected: _onMenuAction,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'wrap',
                child: Text(_wordWrap ? '关闭自动换行' : '开启自动换行',
                    style: TextStyle(color: fg)),
              ),
              PopupMenuItem(
                value: 'info',
                child: Text('文件信息', style: TextStyle(color: fg)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _onMenuAction(String action) {
    switch (action) {
      case 'wrap':
        setState(() => _wordWrap = !_wordWrap);
        break;
      case 'info':
        MediaInfoPanel.show(
          context,
          fileName: widget.fileName,
          fileSize: widget.fileSize,
          format: '${getLanguageName(_ext)} · UTF-8',
        );
        break;
    }
  }

  void _showThemePicker() {
    final labels = ['跟随系统', 'Catppuccin Mocha', 'GitHub Light', 'Monokai'];
    final colors = [
      _isDarkEffective(context) ? const Color(0xFF1e1e2e) : Colors.white,
      const Color(0xFF282c34),
      Colors.white,
      const Color(0xFF272822),
    ];
    final textColors = [Colors.white, Colors.white, Colors.black87, Colors.white];

    showModalBottomSheet(
      context: context,
      backgroundColor: _surfaceColor(context),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12, left: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('选择主题',
                      style: TextStyle(
                          color: _fgColor(context),
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              ...List.generate(4, (i) {
                return ListTile(
                  leading: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: colors[i],
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white24),
                    ),
                  ),
                  title: Text(labels[i],
                      style: TextStyle(color: _fgColor(context))),
                  trailing: _themeIndex == i
                      ? Icon(Icons.check, color: _fgColor(context))
                      : null,
                  onTap: () {
                    setState(() => _themeIndex = i);
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // ── Search bar ────────────────────────────────────────────────────────

  Widget _buildSearchBar(BuildContext context) {
    final dark = _isDarkEffective(context);
    final fg = _fgColor(context);
    final surface = _surfaceColor(context);

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: surface,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: true,
              style: TextStyle(color: fg, fontSize: 13),
              decoration: InputDecoration(
                hintText: '搜索...',
                hintStyle: TextStyle(color: _mutedColor(context)),
                filled: true,
                fillColor: dark ? Colors.white10 : Colors.black.withOpacity(0.05),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _matchLines.isEmpty
                ? '0/0'
                : '${_currentMatchIndex + 1}/${_matchLines.length}',
            style: TextStyle(color: _mutedColor(context), fontSize: 12),
          ),
          IconButton(
            icon: Icon(Icons.keyboard_arrow_up, color: fg, size: 20),
            onPressed: _prevMatch,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            icon: Icon(Icons.keyboard_arrow_down, color: fg, size: 20),
            onPressed: _nextMatch,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  // ── Content ───────────────────────────────────────────────────────────

  Widget _buildContent(BuildContext context) {
    final lines = _content!.split('\n');
    final fg = _fgColor(context);

    final listView = ListView.builder(
      controller: _scrollController,
      itemCount: lines.length,
      itemExtent: 22.0,
      itemBuilder: (_, i) => _buildLine(context, i, lines[i], fg),
    );

    if (_wordWrap) {
      return listView;
    } else {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 2000,
          child: listView,
        ),
      );
    }
  }

  Widget _buildLine(BuildContext context, int index, String line, Color fg) {
    final isMatch = _matchLines.contains(index);
    final isCurrent = isMatch && _currentMatchIndex >= 0 &&
        _matchLines[_currentMatchIndex] == index;

    Color? rowBg;
    if (isCurrent) {
      rowBg = _currentMatchBg(context);
    } else if (isMatch) {
      rowBg = _matchBg(context);
    }

    return Container(
      color: rowBg,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              '${index + 1}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                color: _mutedColor(context),
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              line,
              overflow: _wordWrap ? TextOverflow.ellipsis : TextOverflow.visible,
              maxLines: 1,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: fg,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Status bar ────────────────────────────────────────────────────────

  Widget _buildStatusBar(BuildContext context) {
    final surface = _surfaceColor(context);
    final muted = _mutedColor(context);
    final lines = _content?.split('\n').length ?? 0;
    final sizeStr = widget.fileSize != null ? formatSize(widget.fileSize!) : '';

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: surface,
      child: Row(
        children: [
          Text('${getLanguageName(_ext)} · UTF-8',
              style: TextStyle(color: muted, fontSize: 11)),
          const Spacer(),
          Text('$lines 行${sizeStr.isNotEmpty ? ' · $sizeStr' : ''}',
              style: TextStyle(color: muted, fontSize: 11)),
        ],
      ),
    );
  }
}
