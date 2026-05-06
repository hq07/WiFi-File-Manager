import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/audio_handler.dart';
import '../../services/api_service.dart';
import '../../services/playback_state.dart';
import '../../utils/format_utils.dart';
import '../media_player_screen.dart';

class MiniPlayer extends StatefulWidget {
  final ApiService api;

  const MiniPlayer({super.key, required this.api});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  VoidCallback? _stateListener;

  @override
  void initState() {
    super.initState();
    final player = audioPlayerService.player;
    _position = player.position;
    _duration = player.duration ?? Duration.zero;

    _positionSub = player.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _durationSub = player.durationStream.listen((dur) {
      if (mounted && dur != null) setState(() => _duration = dur);
    });

    _stateListener = () {
      if (mounted) setState(() {});
    };
    playbackStateNotifier.addListener(_stateListener!);
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    if (_stateListener != null) {
      playbackStateNotifier.removeListener(_stateListener!);
    }
    super.dispose();
  }

  void _openFullPlayer() {
    final state = playbackStateNotifier;
    if (state.filePath == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaPlayerScreen(
          api: widget.api,
          filePath: state.filePath!,
          fileName: state.fileName ?? '',
          directoryFiles: state.directoryFiles,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final state = playbackStateNotifier;
    final fileName = state.fileName ?? '';
    final isPlaying = state.isPlaying;
    final progress = _duration > Duration.zero
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return GestureDetector(
      onTap: _openFullPlayer,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1e1e2e) : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          children: [
            // Progress indicator
            LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 2,
              backgroundColor: isDark ? Colors.white12 : Colors.black12,
              valueColor: const AlwaysStoppedAnimation(Color(0xFF6C63FF)),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    // Album art placeholder
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6C63FF), Color(0xFFa855f7)],
                        ),
                      ),
                      child: const Icon(Icons.music_note,
                          color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    // Track info
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fileName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${formatDuration(_position)} / ${formatDuration(_duration)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white54 : Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Play/Pause
                    IconButton(
                      icon: Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      onPressed: () {
                        if (isPlaying) {
                          audioPlayerService.pause();
                        } else {
                          audioPlayerService.play();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
