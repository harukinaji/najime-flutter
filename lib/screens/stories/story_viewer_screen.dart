import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../data/auth_state.dart';
import '../../data/story_service.dart';
import '../../models/story.dart';

class StoryViewerScreen extends StatefulWidget {
  final String initialUserId;
  final List<String> userIds;

  const StoryViewerScreen({
    super.key,
    required this.initialUserId,
    required this.userIds,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with TickerProviderStateMixin {
  late int _userIndex;
  late List<StoryModel> _currentStories;
  late int _storyIndex;
  Timer? _timer;
  late AnimationController _progressController;
  VideoPlayerController? _videoController;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _userIndex = widget.userIds.indexOf(widget.initialUserId);
    if (_userIndex == -1) _userIndex = 0;
    _currentStories = _getStoriesForCurrentUser();
    _storyIndex = 0;
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    _progressController.addListener(() {
      if (_progressController.isCompleted && !_isPaused) {
        _nextStory();
      }
    });
    _startProgress();
  }

  List<StoryModel> _getStoriesForCurrentUser() {
    final userId = widget.userIds[_userIndex];
    return StoryService.instance.getStoriesForUser(userId);
  }

  void _startProgress() {
    _timer?.cancel();
    _progressController.reset();
    if (_storyIndex >= _currentStories.length) return;

    final story = _currentStories[_storyIndex];

    if (story.mediaType == StoryMediaType.video) {
      _videoController?.removeListener(_onVideoUpdate);
      _initVideo(story.mediaPath);
    } else {
      _videoController?.dispose();
      _videoController = null;
      _progressController.duration = const Duration(seconds: 5);
      _progressController.forward();
      _precacheNext();
    }

    _markViewed(story);
  }

  void _precacheNext() {
    final nextIdx = _storyIndex + 1;
    if (nextIdx < _currentStories.length) {
      final next = _currentStories[nextIdx];
      if (next.mediaType == StoryMediaType.image) {
        precacheImage(NetworkImage(next.mediaPath), context);
      }
    } else if (_userIndex + 1 < widget.userIds.length) {
      final nextUser = widget.userIds[_userIndex + 1];
      final nextUserStories = StoryService.instance.getStoriesForUser(nextUser);
      if (nextUserStories.isNotEmpty) {
        final next = nextUserStories.first;
        if (next.mediaType == StoryMediaType.image) {
          precacheImage(NetworkImage(next.mediaPath), context);
        }
      }
    }
  }

  void _onVideoUpdate() {
    if (!mounted || _videoController == null) return;
    final v = _videoController!;
    if (!v.value.isInitialized) return;
    final pos = v.value.position;
    final dur = v.value.duration;
    if (dur.inMilliseconds > 0) {
      _progressController.value = pos.inMilliseconds / dur.inMilliseconds;
    }
  }

  Future<void> _initVideo(String path) async {
    _videoController?.dispose();
    _videoController = VideoPlayerController.network(path);
    _videoController!.addListener(_onVideoUpdate);
    try {
      await _videoController!.initialize();
    } catch (_) {
      _progressController.duration = const Duration(seconds: 5);
      _progressController.forward();
      return;
    }
    if (!mounted) return;
    final duration = _videoController!.value.duration;
    _progressController.duration = duration.inMilliseconds > 0 && !duration.isNegative
        ? duration
        : const Duration(seconds: 10);
    _videoController!.play();
    _progressController.forward();
    _precacheNext();
  }

  void _markViewed(StoryModel story) {
    final myId = AuthState.instance.username ?? '';
    if (myId.isNotEmpty && story.userId != myId) {
      StoryService.instance.addViewer(story.id, myId);
    }
  }

  void _setPaused(bool paused) {
    if (_isPaused == paused) return;
    setState(() {
      _isPaused = paused;
      if (paused) {
        _timer?.cancel();
        _progressController.stop();
        _videoController?.pause();
      } else {
        _videoController?.play();
        _progressController.forward();
      }
    });
  }

  void _nextStory() {
    if (_storyIndex + 1 < _currentStories.length) {
      setState(() {
        _storyIndex++;
      });
      _startProgress();
    } else if (_userIndex + 1 < widget.userIds.length) {
      setState(() {
        _userIndex++;
        _currentStories = _getStoriesForCurrentUser();
        _storyIndex = 0;
      });
      _startProgress();
    } else {
      Navigator.pop(context);
    }
  }

  void _previousStory() {
    if (_storyIndex > 0) {
      setState(() {
        _storyIndex--;
      });
      _startProgress();
    } else if (_userIndex > 0) {
      setState(() {
        _userIndex--;
        _currentStories = _getStoriesForCurrentUser();
        _storyIndex = _currentStories.length - 1;
      });
      _startProgress();
    }
  }

  void _onTapUp(TapUpDetails details) {
    final width = MediaQuery.of(context).size.width;
    final pos = details.localPosition.dx;
    if (_isPaused) {
      _setPaused(false);
      return;
    }
    if (pos < width * 0.3) {
      _previousStory();
    } else if (pos > width * 0.7) {
      _nextStory();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _progressController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentStories.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: const Center(
          child: Text('No stories', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    final story = _currentStories[_storyIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: _onTapUp,
        onLongPressStart: (_) => _setPaused(true),
        onLongPressEnd: (_) => _setPaused(false),
        child: Stack(
          children: [
            Positioned.fill(
              child: story.mediaType == StoryMediaType.image
                  ? Image.network(story.mediaPath, fit: BoxFit.contain)
                  : _videoController != null && _videoController!.value.isInitialized
                      ? VideoPlayer(_videoController!)
                      : const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
            ),
            // Gradient overlay for UI readability
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 160,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.6),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Progress bars
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              right: 8,
              child: _buildProgressBars(),
            ),
            // User info + close
            Positioned(
              top: MediaQuery.of(context).padding.top + 28,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: story.userAvatar != null
                        ? NetworkImage(story.userAvatar!)
                        : null,
                    child: story.userAvatar == null
                        ? Text(
                            story.userName.isNotEmpty
                                ? story.userName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(color: Colors.white),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      story.userName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Caption
            if (story.caption != null && story.caption!.isNotEmpty)
              Positioned(
                bottom: 40,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    story.caption!,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
              ),
            // Viewers count for my own stories
            if (story.userId == (AuthState.instance.username ?? '') && story.viewerIds.isNotEmpty)
              Positioned(
                bottom: 80,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${story.viewerIds.length} ${story.viewerIds.length == 1 ? 'view' : 'views'}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBars() {
    return Row(
      children: List.generate(_currentStories.length, (i) {
        return Expanded(
          child: Container(
            height: 2.5,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: Colors.white24,
            ),
            child: i < _storyIndex
                ? Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  )
                : i == _storyIndex
                    ? AnimatedBuilder(
                        animation: _progressController,
                        builder: (context, child) {
                          return LinearProgressIndicator(
                            value: _progressController.value,
                            backgroundColor: Colors.transparent,
                            valueColor: const AlwaysStoppedAnimation(Colors.white),
                          );
                        },
                      )
                    : null,
          ),
        );
      }),
    );
  }
}
