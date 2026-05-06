import 'dart:async';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import '../../services/api_service.dart';
import '../../services/history_service.dart';
import 'media_info_panel.dart';
import 'playlist_manager.dart';

class ImageGalleryView extends StatefulWidget {
  final ApiService api;
  final String filePath;
  final String fileName;
  final int? fileSize;
  final PlaylistManager playlist;
  final HistoryService? historyService;

  const ImageGalleryView({
    super.key,
    required this.api,
    required this.filePath,
    required this.fileName,
    this.fileSize,
    required this.playlist,
    this.historyService,
  });

  @override
  State<ImageGalleryView> createState() => _ImageGalleryViewState();
}

class _ImageGalleryViewState extends State<ImageGalleryView> {
  late final PageController _pageController;
  bool _showControls = true;
  Timer? _hideControlsTimer;
  Timer? _slideshowTimer;
  bool _isSlideshowActive = false;
  int _slideshowIntervalSeconds = 5;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: widget.playlist.currentIndex,
    );
    _startHideControlsTimer();
    _recordHistory();
  }

  void _recordHistory() {
    final hs = widget.historyService;
    if (hs == null) return;
    final item = widget.playlist.currentItem;
    hs.addEntry(
      name: item['name'] ?? widget.fileName,
      path: widget.filePath,
      dirPath: widget.filePath.substring(0, widget.filePath.lastIndexOf('/')),
      size: item['size'] as int? ?? widget.fileSize ?? 0,
    );
  }

  @override
  void dispose() {
    _slideshowTimer?.cancel();
    _hideControlsTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  // ---- Controls visibility ----

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_isSlideshowActive) {
        setState(() => _showControls = false);
      }
    });
  }

  void _onTap() {
    if (_isSlideshowActive) {
      _stopSlideshow();
    } else {
      setState(() => _showControls = !_showControls);
      if (_showControls) _startHideControlsTimer();
    }
  }

  // ---- Slideshow ----

  void _showSlideshowPicker() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '幻灯片间隔',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              for (final seconds in [3, 5, 10, 30])
                ListTile(
                  title: Text('$seconds 秒'),
                  trailing: _slideshowIntervalSeconds == seconds && _isSlideshowActive
                      ? const Icon(Icons.check, color: Color(0xFF6C63FF))
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _startSlideshow(seconds);
                  },
                ),
              if (_isSlideshowActive)
                ListTile(
                  title: const Text('停止幻灯片', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _stopSlideshow();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _startSlideshow(int intervalSeconds) {
    _slideshowTimer?.cancel();
    setState(() {
      _isSlideshowActive = true;
      _showControls = false;
      _slideshowIntervalSeconds = intervalSeconds;
    });
    _slideshowTimer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) {
        if (!mounted) {
          _slideshowTimer?.cancel();
          return;
        }
        final nextIdx = widget.playlist.currentIndex + 1;
        if (nextIdx >= widget.playlist.items.length) {
          _stopSlideshow();
          return;
        }
        widget.playlist.setItems(
          widget.playlist.items,
          startIndex: nextIdx,
        );
        _pageController.animateToPage(
          nextIdx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      },
    );
  }

  void _stopSlideshow() {
    _slideshowTimer?.cancel();
    if (mounted) {
      setState(() {
        _isSlideshowActive = false;
        _showControls = true;
      });
      _startHideControlsTimer();
    }
  }

  // ---- Info panel ----

  void _showInfoPanel() {
    final item = widget.playlist.currentItem;
    MediaInfoPanel.show(
      context,
      fileName: item['name'] ?? widget.fileName,
      fileSize: item['size'] ?? widget.fileSize,
      format: (widget.filePath.split('.').last).toUpperCase(),
    );
  }

  // ---- Page change ----

  void _onPageChanged(int index) {
    if (index != widget.playlist.currentIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.playlist.setItems(
          widget.playlist.items,
          startIndex: index,
        );
      });
    }
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Gallery
        Positioned.fill(
          child: GestureDetector(
            onTap: _onTap,
            child: PhotoViewGallery.builder(
              pageController: _pageController,
              itemCount: widget.playlist.items.length,
              builder: (context, index) {
                final path = widget.playlist.items[index]['path'] as String;
                return PhotoViewGalleryPageOptions(
                  imageProvider: NetworkImage(widget.api.getPreviewUrl(path)),
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 3,
                  heroAttributes: PhotoViewHeroAttributes(tag: 'gallery_$index'),
                );
              },
              backgroundDecoration: const BoxDecoration(color: Colors.black),
              onPageChanged: _onPageChanged,
            ),
          ),
        ),
        // Top bar
        if (_showControls) _buildTopBar(),
        // Bottom bar + page indicator
        if (_showControls) _buildBottomControls(),
        // Slideshow stop button (shown during slideshow)
        if (_isSlideshowActive) _buildSlideshowStopButton(),
      ],
    );
  }

  // ---- Top bar ----

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black54, Colors.transparent],
          ),
        ),
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 4,
          left: 8,
          right: 8,
          bottom: 8,
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Text(
                widget.playlist.currentItem['name'] ?? widget.fileName,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.slideshow,
                color: _isSlideshowActive
                    ? const Color(0xFF6C63FF)
                    : Colors.white,
              ),
              onPressed: _showSlideshowPicker,
            ),
            IconButton(
              icon: const Icon(Icons.info_outline, color: Colors.white),
              onPressed: _showInfoPanel,
            ),
          ],
        ),
      ),
    );
  }

  // ---- Bottom controls ----

  Widget _buildBottomControls() {
    final total = widget.playlist.items.length;
    final current = widget.playlist.currentIndex + 1;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black54, Colors.transparent],
          ),
        ),
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).padding.bottom + 12,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Page indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '$current / $total',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
            // Bottom action icons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildBottomAction(Icons.share, '分享'),
                _buildBottomAction(Icons.file_download_outlined, '下载'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomAction(IconData icon, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon, color: Colors.white, size: 26),
          onPressed: () {}, // Stub / no-op for now
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }

  // ---- Slideshow stop button ----

  Widget _buildSlideshowStopButton() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      right: 16,
      child: GestureDetector(
        onTap: _stopSlideshow,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.stop, color: Colors.white, size: 18),
              SizedBox(width: 4),
              Text(
                '停止',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
