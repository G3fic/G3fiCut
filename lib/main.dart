import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart' as crypto;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'timeline_history.dart';
import 'timeline_editing.dart';
import 'project_document.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const G3fiCutApp());
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow(this.shortcut, this.description);
  final String shortcut;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      SizedBox(width: 156, child: Text(shortcut, style: const TextStyle(fontWeight: FontWeight.w700))),
      Expanded(child: Text(description)),
    ]),
  );
}

class G3fiCutApp extends StatelessWidget {
  const G3fiCutApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'GifCut',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF9B6DFF), brightness: Brightness.dark),
          scaffoldBackgroundColor: const Color(0xFF101116),
          dividerColor: const Color(0xFF292B36),
        ),
        home: const EditorPage(),
      );
}

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class TimelineClip {
  TimelineClip({required this.start, required this.end, double? timelineStart})
      : timelineStart = timelineStart ?? start;

  /// Source-media in/out points in seconds.
  double start;
  double end;

  /// Position of this clip in the edited sequence.
  double timelineStart;

  double get length => end - start;
  double get timelineEnd => timelineStart + length;
}

class PhotoOverlay {
  PhotoOverlay({required this.path, this.x = 0, this.y = 0, this.scale = 1, this.rotation = 0, this.opacity = 1});
  final String path;
  double x, y, scale, rotation, opacity;
}

class _EditorPageState extends State<EditorPage> with WidgetsBindingObserver {
  static const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.3.67');
  static const releaseApi = 'https://api.github.com/repos/G3fic/G3fiCut/releases/latest';

  static const panel = Color(0xFF17191F);
  static const muted = Color(0xFF969EAE);
  static const accent = Color(0xFF9B6DFF);
  static const videoBlue = Color(0xFF9B6DFF);
  static const audioGreen = Color(0xFF35C99A);

  Player? player;
  VideoController? videoController;
  StreamSubscription<Duration>? durationSub;
  StreamSubscription<Duration>? positionSub;
  StreamSubscription<bool>? playingSub;

  String? videoPath;
  String? audioPath;
  String? projectFilePath;
  bool projectDirty = false;
  Duration duration = Duration.zero;
  Duration audioDuration = Duration.zero;
  Duration position = Duration.zero;
  bool playing = false;
  double playbackRate = 1.0;
  double exportVolume = 1.0;
  double brightness = 0.0;
  double contrast = 1.0;
  double saturation = 1.0;
  bool filtersEnabled = true;
  bool motionBlurEnabled = false;
  double previewZoom = 1.0;
  double videoScaleX = 1.0, videoScaleY = 1.0, videoRotation = 0, videoOffsetX = 0, videoOffsetY = 0;
  final List<PhotoOverlay> photoOverlays = [];
  int selectedPhotoOverlay = -1;
  bool _playheadInGap = false;
  int _activePlaybackClipIndex = -1;
  Timer? _gapPlaybackTimer;
  Stopwatch? _gapPlaybackClock;
  double _gapPlaybackStartSeconds = 0;
  double _gapPlaybackEndSeconds = 0;
  int _gapNextClipIndex = -1;
  bool _gapResumePending = false;
  bool _suppressPlayerStateEvents = false;
  double _mediaPanelWidth = 188;
  double _inspectorPanelWidth = 220;
  double _timelinePanelHeight = 276;
  Offset? _videoMoveLastGlobal;
  Offset? _videoRotateLastGlobal;
  final Map<String, Offset> _resizeHandleLastGlobal = {};
  double frameRate = 30.0;
  bool snappingEnabled = true;
  double? _timelineSnapAt;
  final ScrollController timelineScrollController = ScrollController();
  int _clipMoveIndex = -1;
  double _clipMoveOriginalStart = 0;
  double _clipMovePointerX = 0;
  TimelineSnapshot? _clipMoveBefore;
  bool _showVerticalSnapGuide = false;
  bool _showHorizontalSnapGuide = false;
  String aspectRatioPreset = '16:9';
  String videoEffect = 'Оригинал';
  String transitionEffect = 'Нет';
  double transitionDuration = 0.4;

  double get previewAspectRatio => const {
    '16:9': 16 / 9,
    '9:16': 9 / 16,
    '1:1': 1.0,
    '4:3': 4 / 3,
    '4:5': 4 / 5,
    '3:2': 3 / 2,
  }[aspectRatioPreset] ?? 16 / 9;

  String get _exportEffectFilter => const {
    'Оригинал': 'null',
    'Чёрно-белый': 'hue=s=0',
    'Сепия': 'colorchannelmixer=.393:.769:.189:0:0:.349:.686:.168:0:0:.272:.534:.131:0:0',
    'Холодный': 'colorbalance=rs=-0.04:bs=0.12',
    'Тёплый': 'colorbalance=rs=0.12:bs=-0.06',
    'Негатив': 'negate',
    'Мягкое размытие': 'gblur=sigma=2',
  }[videoEffect] ?? 'null';

  List<double> get effectColorMatrix => const {
    'Оригинал': <double>[1,0,0,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0],
    'Чёрно-белый': <double>[0.213,0.715,0.072,0,0, 0.213,0.715,0.072,0,0, 0.213,0.715,0.072,0,0, 0,0,0,1,0],
    'Сепия': <double>[0.393,0.769,0.189,0,0, 0.349,0.686,0.168,0,0, 0.272,0.534,0.131,0,0, 0,0,0,1,0],
    'Холодный': <double>[0.96,0,0,0,0, 0,1,0,0,0, 0,0,1.12,0,0, 0,0,0,1,0],
    'Тёплый': <double>[1.12,0,0,0,0, 0,1,0,0,0, 0,0,0.94,0,0, 0,0,0,1,0],
    'Негатив': <double>[-1,0,0,0,255, 0,-1,0,0,255, 0,0,-1,0,255, 0,0,0,1,0],
    'Мягкое размытие': <double>[1,0,0,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0],
  }[videoEffect] ?? const <double>[1,0,0,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0];

  ({Color color, double opacity}) get previewTransitionOverlay {
    if (transitionEffect == 'Нет' || videoClips.length < 2) {
      return (color: Colors.black, opacity: 0);
    }
    final seconds = position.inMilliseconds / 1000;
    var opacity = 0.0;
    for (var i = 0; i < videoClips.length; i++) {
      final clip = videoClips[i];
      if (i > 0 && seconds >= clip.timelineStart && seconds < clip.timelineStart + transitionDuration) {
        opacity = math.max(opacity, 1 - (seconds - clip.timelineStart) / transitionDuration).toDouble();
      }
      if (i < videoClips.length - 1 && seconds > clip.timelineEnd - transitionDuration && seconds <= clip.timelineEnd) {
        opacity = math.max(opacity, (seconds - (clip.timelineEnd - transitionDuration)) / transitionDuration).toDouble();
      }
    }
    return (color: transitionEffect == 'Белая вспышка' ? Colors.white : Colors.black, opacity: opacity.clamp(0.0, 1.0).toDouble());
  }
  String inspectorTab = 'video';
  List<String> videoThumbnails = [];
  String? thumbnailDirectory;
  bool busy = false;
  bool _switchingMedia = false;
  bool _seekingAcrossCut = false;
  Duration? _switchingMediaDuration;
  int _edgeDragIndex = -1;
  bool _edgeDragLeft = false;
  double _edgeDragOriginalEdge = 0;
  double _edgeDragPointerX = 0;
  dynamic _edgeDragBefore;
  bool checkingForUpdates = false;
  Timer? _updateCheckTimer;
  double zoom = 32;
  final List<TimelineClip> videoClips = [];
  final TimelineHistory _timelineHistory = TimelineHistory();
  int selectedClipIndex = 0;
  double audioClipStart = 0;
  double audioClipEnd = 0;
  List<double> audioWaveform = const [];
  String status = 'Импортируйте видео, чтобы начать монтаж.';

  double get _timelineEndSeconds => videoClips.isEmpty
      ? 0
      : videoClips.map((clip) => clip.timelineEnd).reduce((a, b) => a > b ? a : b);
  Duration get timelineDuration =>
      Duration(milliseconds: (_timelineEndSeconds * 1000).round());
  double get timelineSeconds => videoClips.isNotEmpty
      ? math.max(1, _timelineEndSeconds).toDouble()
      : (duration.inMilliseconds > 0
          ? math.max(1, duration.inMilliseconds / 1000).toDouble()
          : 30);
  double get timelineWidth => math.max(720, timelineSeconds * zoom).toDouble();

  List<TimelineClipRange> _clipRanges() => videoClips
      .map((clip) => TimelineClipRange(
            clip.start,
            clip.end,
            timelineStart: clip.timelineStart,
          ))
      .toList();

  void _replaceClipRanges(List<TimelineClipRange> ranges) {
    videoClips
      ..clear()
      ..addAll(ranges.map((clip) => TimelineClip(
            start: clip.start,
            end: clip.end,
            timelineStart: clip.timelineStart,
          )))
      ..sort((a, b) => a.timelineStart.compareTo(b.timelineStart));
  }

  int _clipIndexAtTimelineTime(double seconds) {
    for (var i = 0; i < videoClips.length; i++) {
      final clip = videoClips[i];
      if (seconds >= clip.timelineStart - 0.001 &&
          seconds < clip.timelineEnd - 0.0001) {
        return i;
      }
    }
    return -1;
  }

  @override
  void initState() {
    super.initState();
    if (kReleaseMode && Platform.isWindows) {
      WidgetsBinding.instance.addObserver(this);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(checkForUpdates());
      });
      // Retry periodically while the editor remains open.
      _updateCheckTimer = Timer.periodic(const Duration(hours: 6), (_) {
        if (mounted && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
          unawaited(checkForUpdates());
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        kReleaseMode &&
        Platform.isWindows &&
        mounted) {
      unawaited(checkForUpdates());
    }
  }

  /// Fetches release metadata with retries for slow, unstable or VPN-routed connections.
  Future<String> _fetchLatestRelease(HttpClient client) async {
    Object? lastError;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        final request = await client
            .getUrl(Uri.parse(releaseApi))
            .timeout(const Duration(seconds: 45));
        request.headers
          ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
          ..set(HttpHeaders.cacheControlHeader, 'no-cache');
        final response = await request.close().timeout(const Duration(seconds: 60));
        if (response.statusCode == HttpStatus.notFound) {
          throw StateError('GitHub Releases пока недоступны. Проверьте, что репозиторий публичный и релиз опубликован.');
        }
        if (response.statusCode == HttpStatus.tooManyRequests ||
            response.statusCode >= 500) {
          throw HttpException('GitHub временно недоступен (HTTP ${response.statusCode}).');
        }
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('GitHub вернул HTTP ${response.statusCode}.');
        }
        return await response
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 60));
      } catch (e) {
        lastError = e;
        if (e is StateError) rethrow;
        if (attempt < 3) {
          // Exponential backoff: 2, 4 and 8 seconds.
          await Future.delayed(Duration(seconds: 2 << attempt));
        }
      }
    }
    throw HttpException(
      'Не удалось подключиться к GitHub после 4 попыток. Проверьте VPN и интернет. Последняя ошибка: $lastError',
    );
  }

  Future<void> checkForUpdates({bool showNoUpdateMessage = false}) async {
    if (checkingForUpdates) return;
    setState(() => checkingForUpdates = true);

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..idleTimeout = const Duration(seconds: 30)
      ..userAgent = 'G3fiCut/$appVersion';
    try {
      final responseBody = await _fetchLatestRelease(client);
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic>) throw const FormatException('Некорректный ответ GitHub Releases.');

      final latestTag = decoded['tag_name'] as String?;
      if (latestTag == null || latestTag.trim().isEmpty) {
        throw const FormatException('В ответе GitHub не найдена версия релиза.');
      }
      final latestVersion = latestTag.replaceFirst(RegExp(r'^[vV]'), '');
      if (!isVersionNewer(latestVersion, appVersion)) {
        if (showNoUpdateMessage && mounted) setStatus('Установлена последняя версия GifCut $appVersion.');
        return;
      }

      final assets = decoded['assets'];
      if (assets is! List) throw const FormatException('В релизе не найден список файлов.');
      Map<String, dynamic>? installerAsset;
      final expectedName = 'G3fiCut-Setup-$latestVersion.exe';
      for (final item in assets) {
        if (item is Map<String, dynamic> && item['name'] == expectedName) {
          installerAsset = item;
          break;
        }      }
      if (installerAsset == null) {
        throw StateError('В релизе $latestTag нет установщика $expectedName.');
      }

      final rawUrl = installerAsset['browser_download_url'] as String?;
      final downloadUri = rawUrl == null ? null : Uri.tryParse(rawUrl);
      if (downloadUri == null ||
          downloadUri.scheme != 'https' ||
          downloadUri.host != 'github.com' ||
          !downloadUri.path.startsWith('/G3fic/G3fiCut/releases/download/')) {
        throw const FormatException('Ссылка на установщик не принадлежит официальным GitHub Releases GifCut.');
      }

      final digest = installerAsset['digest'] as String?;
      if (digest == null || !digest.startsWith('sha256:')) {
        throw StateError('GitHub не предоставил SHA-256 установщика. Обновление не будет запущено без проверки целостности.');
      }
      if (mounted) setStatus('Доступно обновление v$latestVersion.');
      if (!mounted) return;
      final shouldUpdate = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Доступно обновление GifCut'),
          content: Text(
            'Установлена версия $appVersion. Доступна версия $latestVersion.\n\n'
            'GifCut скачает установщик из GitHub, проверит файл и запустит установку. '
            'Windows может запросить разрешение администратора.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Позже')),
            FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Обновить')),
          ],
        ),
      );
      if (shouldUpdate == true && mounted) {
        await _downloadAndRunInstaller(downloadUri, latestVersion, digest);
      }
    } catch (e) {
      if (mounted) {
        setStatus('Не удалось проверить обновления; повторим автоматически: ${e.toString().replaceFirst('Bad state: ', '')}');
      }
    } finally {
      client.close(force: true);
      if (mounted) setState(() => checkingForUpdates = false);
    }
  }

  Future<void> _downloadAndRunInstaller(Uri uri, String version, String? expectedDigest) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..userAgent = 'G3fiCut/$appVersion';
    File? installer;
    try {
      if (mounted) setStatus('Скачиваю обновление v$version…');
      final tempDir = await Directory.systemTemp.createTemp('g3ficut-update-');
      installer = File(p.join(tempDir.path, 'G3fiCut-Setup-$version.exe'));
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 25));
      final response = await request.close().timeout(const Duration(seconds: 40));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Не удалось скачать установщик (HTTP ${response.statusCode}).');
      }
      await response.pipe(installer.openWrite()).timeout(const Duration(minutes: 10));
      if (await installer.length() < 1024 * 1024) {
        throw StateError('Скачанный установщик слишком мал или повреждён.');
      }

      if (expectedDigest != null && expectedDigest.startsWith('sha256:')) {
        if (mounted) setStatus('Проверяю целостность обновления…');
        final actual = await crypto.sha256.bind(installer.openRead()).first.timeout(const Duration(minutes: 2));
        final expected = expectedDigest.substring('sha256:'.length).toLowerCase();
        if (actual.toString().toLowerCase() != expected) {
          throw StateError('Контрольная сумма установщика не совпала. Установка отменена.');
        }
      }

      if (mounted) setStatus('Запускаю установщик v$version…');
      await Process.start(
        installer.path,
        ['/SILENT', '/CLOSEAPPLICATIONS', '/NORESTART'],
        mode: ProcessStartMode.detached,
      );
      final activePlayer = player;
      if (activePlayer != null) await activePlayer.dispose();
      exit(0);
    } catch (e) {
      if (mounted) {
        setStatus('Не удалось установить обновление: ${e.toString().replaceFirst('Bad state: ', '')}');
      }
      if (installer != null) {
        try {
          if (await installer.exists()) await installer.delete();
        } catch (_) {
          // Keep the original installer error as the visible status.
        }
      }
    } finally {
      client.close(force: true);
    }
  }

  Player ensurePlayer() {
    final current = player;
    if (current != null) return current;

    // media_kit_video configures hardware decoding on the video controller.
    // auto-safe allows mpv to fall back when a driver's hardware path is unavailable.
    final created = Player();
    try {
      final controller = VideoController(
        created,
        configuration: const VideoControllerConfiguration(
          hwdec: 'auto-safe',
          enableHardwareAcceleration: true,
        ),
      );
      player = created;
      videoController = controller;
      durationSub = created.stream.duration.listen((v) {
        if (!mounted) return;
        if (_switchingMedia) {
          if (v > Duration.zero) _switchingMediaDuration = v;
          return;
        }
        setState(() {
          duration = v;
          // Some containers report duration only after the first stream event.
          // Keep the initial clip full-width instead of leaving a tiny zero-length block.
          if (videoClips.length == 1 && videoClips.first.start == 0 && videoClips.first.end <= 0 && v > Duration.zero) {
            videoClips.first.end = v.inMilliseconds / 1000;
          }
        });
      });
      positionSub = created.stream.position.listen((v) {
        if (mounted && !_switchingMedia) {
          unawaited(_handlePlayerPosition(v));
        }
      });
      playingSub = created.stream.playing.listen((v) {
        if (mounted && !_switchingMedia && !_playheadInGap && !_suppressPlayerStateEvents) {
          setState(() => playing = v);
        }
      });
      return created;
    } catch (_) {
      unawaited(created.dispose());
      rethrow;
    }
  }

  @override
  void dispose() {
    _updateCheckTimer?.cancel();
    _stopGapPlayback(clearNext: true);
    WidgetsBinding.instance.removeObserver(this);
    durationSub?.cancel();
    positionSub?.cancel();
    playingSub?.cancel();
    timelineScrollController.dispose();
    final activePlayer = player;
    if (activePlayer != null) unawaited(activePlayer.dispose());
    super.dispose();
  }

  Future<void> _generateVideoThumbnails(String source, Duration videoDuration) async {
    try {
      final directory = await Directory.systemTemp.createTemp('gifcut-thumbnails-');
      final seconds = videoDuration.inMilliseconds / 1000;
      if (seconds <= 0) return;
      final result = await Process.run(await findFfmpeg(), [
        '-hide_banner', '-loglevel', 'error', '-y', '-i', source,
        '-vf', 'fps=12/${seconds.toStringAsFixed(3)},scale=120:-1',
        '-frames:v', '12', p.join(directory.path, 'frame_%02d.jpg'),
      ]);
      if (result.exitCode != 0) return;
      final files = directory.listSync().whereType<File>().where((file) => file.path.toLowerCase().endsWith('.jpg')).toList()..sort((a, b) => a.path.compareTo(b.path));
      if (!mounted || videoPath != source) return;
      setState(() {
        thumbnailDirectory = directory.path;
        videoThumbnails = files.map((file) => file.path).toList();
      });
    } catch (_) {
      // The timeline remains usable with its fallback thumbnails if FFmpeg cannot extract frames.
    }
  }

  Future<void> pickVideo() async {
    if (busy) return;

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
        dialogTitle: 'Выберите видео',
      );
    } catch (e) {
      setStatus('Не удалось открыть окно выбора видео: $e');
      return;
    }
    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path;
    if (path == null) {
      setStatus('Не удалось получить путь к видео.');
      return;
    }
    if (!await _confirmReplaceIfDirty()) return;

    // Keep the current project data intact until the replacement media opens.
    final previousVideoPath = videoPath;
    final previousPosition = position;
    setState(() {
      busy = true;
      _switchingMedia = true;
      _switchingMediaDuration = null;
      status = 'Загрузка видео…';
    });

    try {
      final activePlayer = ensurePlayer();
      await activePlayer.stop();
      await activePlayer.open(Media(path), play: false);
      await activePlayer.seek(Duration.zero);
      var openedDuration = activePlayer.state.duration;
      if (openedDuration <= Duration.zero) {
        openedDuration = _switchingMediaDuration ?? Duration.zero;
      }
      if (openedDuration <= Duration.zero) {
        openedDuration = await activePlayer.stream.duration
            .firstWhere((value) => value > Duration.zero)
            .timeout(const Duration(seconds: 10));
      }

      _timelineHistory.clear();
      _switchingMedia = false;
      _switchingMediaDuration = null;
      final detectedFps = activePlayer.state.track.video.fps;
      if (!mounted) return;
      setState(() {
        if (detectedFps != null && detectedFps.isFinite && detectedFps > 0) {
          frameRate = detectedFps.clamp(1.0, 240.0).toDouble();
        }
        videoPath = path;
        projectFilePath = null;
        projectDirty = true;
        audioPath = null;
        audioDuration = Duration.zero;
        audioClipStart = 0;
        audioClipEnd = 0;
        duration = openedDuration;
        position = Duration.zero;
        playing = false;
        videoClips
          ..clear()
          ..add(TimelineClip(
            start: 0,
            end: openedDuration.inMilliseconds / 1000,
            timelineStart: 0,
          ));
        _activePlaybackClipIndex = 0;
        _playheadInGap = false;
        selectedClipIndex = 0;
        videoThumbnails = [];
        status = 'Видео загружено. Создаю миниатюры для таймлайна…';
      });
      unawaited(_generateVideoThumbnails(path, openedDuration));
    } catch (e) {
      if (previousVideoPath != null) {
        try {
          final activePlayer = ensurePlayer();
          await activePlayer.open(Media(previousVideoPath), play: false);
          await activePlayer.seek(previousPosition);
        } catch (_) {
          // Preserve project metadata even if the old preview cannot be restored.
        }
      }
      _switchingMedia = false;
      _switchingMediaDuration = null;      if (mounted) {
        setState(() {
          position = previousPosition;
          status = 'Не удалось открыть видео: $e';
        });
      }
    } finally {
      _switchingMedia = false;
      _switchingMediaDuration = null;
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> _confirmReplaceIfDirty() async {
    if (!projectDirty || videoPath == null) return true;
    final decision = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Есть несохранённые изменения'),
        content: const Text('Сохранить текущий проект перед заменой?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop('cancel'), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop('discard'), child: const Text('Не сохранять')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop('save'), child: const Text('Сохранить')),
        ],
      ),
    );
    if (decision == 'discard') return true;
    if (decision == 'save') return saveProject();
    return false;
  }

  Future<bool> saveProject({bool saveAs = false}) async {
    if (busy) return false;
    final source = videoPath;
    if (source == null) {
      setStatus('Сначала импортируйте видео, чтобы сохранить проект.');
      return false;
    }

    var target = projectFilePath;
    if (saveAs || target == null) {
      try {
        target = await FilePicker.platform.saveFile(
          dialogTitle: 'Сохранить проект GifCut',
          fileName: 'GifCut-Project.g3ficut',
          type: FileType.custom,
          allowedExtensions: ['g3ficut'],
        );
      } catch (e) {
        setStatus('Не удалось открыть диалог сохранения проекта: $e');
        return false;
      }
      if (target == null) return false;
      if (p.extension(target).toLowerCase() != '.g3ficut') {
        target = '${p.withoutExtension(target)}.g3ficut';
      }
    }

    try {
      final targetPath = target;
      final document = ProjectDocument(
        appVersion: appVersion,
        videoPath: source,
        videoDurationMs: duration.inMilliseconds,
        videoClips: videoClips
            .map((clip) => ProjectClipRange(
                  clip.start,
                  clip.end,
                  timelineStart: clip.timelineStart,
                ))
            .toList(),
        selectedClipIndex: videoClips.isEmpty ? 0 : selectedClipIndex.clamp(0, videoClips.length - 1).toInt(),
        audioPath: audioPath,
        audioDurationMs: audioPath == null ? 0 : audioDuration.inMilliseconds,
        audioClipStart: audioClipStart,
        audioClipEnd: audioClipEnd,
        timelineZoom: zoom,
        playheadMs: position.inMilliseconds.clamp(0, timelineDuration.inMilliseconds).toInt(),
      );
      await File(targetPath).writeAsString(document.encode(), flush: true);
      if (!mounted) return true;
      setState(() {
        projectFilePath = targetPath;
        projectDirty = false;
        status = 'Проект сохранён: ${p.basename(targetPath)}';
      });
      return true;
    } catch (e) {
      setStatus('Не удалось сохранить проект: $e');
      return false;
    }
  }

  Future<void> openProject() async {
    if (busy) return;
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['g3ficut'],
        allowMultiple: false,
        dialogTitle: 'Открыть проект GifCut',
      );
    } catch (e) {
      setStatus('Не удалось открыть диалог выбора проекта: $e');
      return;
    }
    if (result == null || result.files.isEmpty) return;
    final selectedPath = result.files.single.path;
    if (selectedPath == null) {
      setStatus('Не удалось получить путь к файлу проекта.');
      return;
    }

    ProjectDocument document;
    try {
      document = ProjectDocument.decode(await File(selectedPath).readAsString());
      if (!await File(document.videoPath).exists()) {
        throw FileSystemException('Исходное видео проекта не найдено.', document.videoPath);
      }
      final audio = document.audioPath;
      if (audio != null && !await File(audio).exists()) {
        throw FileSystemException('Файл аудио проекта не найден.', audio);
      }
    } catch (e) {
      setStatus('Не удалось прочитать проект: $e');
      return;
    }

    if (!await _confirmReplaceIfDirty()) return;
    final previousVideoPath = videoPath;
    final previousPosition = position;
    setState(() {
      busy = true;
      _switchingMedia = true;
      _switchingMediaDuration = null;
      status = 'Открываю проект…';
    });
    try {
      final activePlayer = ensurePlayer();
      await activePlayer.stop();
      try {
        await activePlayer.open(Media(document.videoPath), play: false);
      } catch (error) {
        if (previousVideoPath != null) {
          try {
            await activePlayer.open(Media(previousVideoPath), play: false);
            await activePlayer.seek(previousPosition);
          } catch (_) {
            // Keep the previous project data if playback restoration fails.
          }
        }
        rethrow;
      }

      final reportedDuration = activePlayer.state.duration;
      final pendingDuration = _switchingMediaDuration;
      final restoredDuration = reportedDuration > Duration.zero
          ? reportedDuration
          : (pendingDuration != null && pendingDuration > Duration.zero
              ? pendingDuration
              : Duration(milliseconds: document.videoDurationMs));
      final sequenceEndMs = document.videoClips.isEmpty
          ? 0
          : (document.videoClips
                      .map((clip) => clip.timelineEnd)
                      .reduce((a, b) => a > b ? a : b) *
                  1000)
              .round();
      final restoredPosition = Duration(
        milliseconds: document.playheadMs.clamp(0, sequenceEndMs).toInt(),
      );
      _timelineHistory.clear();
      _switchingMedia = false;
      _switchingMediaDuration = null;
      final detectedFps = activePlayer.state.track.video.fps;
      if (!mounted) return;
      setState(() {
        if (detectedFps != null && detectedFps.isFinite && detectedFps > 0) {
          frameRate = detectedFps.clamp(1.0, 240.0).toDouble();
        }
        videoPath = document.videoPath;
        duration = restoredDuration;
        videoClips
          ..clear()
          ..addAll(document.videoClips.map((clip) => TimelineClip(
                start: clip.start,
                end: clip.end,
                timelineStart: clip.timelineStart,
              )));
        videoClips.sort((a, b) => a.timelineStart.compareTo(b.timelineStart));
        _activePlaybackClipIndex = -1;
        _playheadInGap = false;
        selectedClipIndex = document.selectedClipIndex;
        audioPath = document.audioPath;
        audioDuration = Duration(milliseconds: document.audioDurationMs);
        audioClipStart = document.audioClipStart;
        audioClipEnd = document.audioClipEnd;
        zoom = document.timelineZoom;
        position = restoredPosition;
        projectFilePath = selectedPath;
        projectDirty = false;
        playing = false;
        status = 'Проект открыт: ${p.basename(selectedPath)}';
      });
      if (document.audioPath != null) {
        unawaited(_readWaveform(document.audioPath!).then((wave) {
          if (mounted && audioPath == document.audioPath) setState(() => audioWaveform = wave);
        }));
      }
      try {
        await seek(restoredPosition);
      } catch (e) {
        setStatus('Проект открыт, но не удалось восстановить позицию курсора: $e');
      }
    } catch (e) {
      _switchingMedia = false;
      _switchingMediaDuration = null;
      if (mounted) setState(() => status = 'Не удалось открыть проект: $e');
    } finally {
      _switchingMedia = false;
      _switchingMediaDuration = null;
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String> findFfmpeg() async {
    final exe = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
    final appDir = p.dirname(Platform.resolvedExecutable);
    for (final candidate in [p.join(appDir, exe), p.join(Directory.current.path, exe), p.join(appDir, 'tools', exe)]) {
      if (await File(candidate).exists()) return candidate;
    }
    return exe;
  }

  Future<void> importPhotoOverlay() async {
    if (busy || videoPath == null) return;
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false, dialogTitle: 'Выберите изображение поверх видео', allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp']);
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null || !await File(path).exists()) { setStatus('Не удалось прочитать изображение.'); return; }
      setState(() {
        photoOverlays.add(PhotoOverlay(path: path));
        selectedPhotoOverlay = photoOverlays.length - 1;
        projectDirty = true;
        status = 'Фото добавлено поверх видео.';
      });
    } catch (e) { setStatus('Не удалось импортировать фото: $e'); }
  }

  Future<List<double>> _readWaveform(String path, {int buckets = 1800}) async {
    final bytes = await File(path).readAsBytes();
    if (bytes.length < 44 || String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF') return const [];
    final dataOffset = 12 + 8;
    final channels = ByteData.sublistView(bytes).getUint16(22, Endian.little);
    final bitsPerSample = ByteData.sublistView(bytes).getUint16(34, Endian.little);
    final dataSize = ByteData.sublistView(bytes).getUint32(40, Endian.little);
    if (bitsPerSample != 16 || channels < 1) return const [];
    final sampleCount = math.min((bytes.length - dataOffset) ~/ 2, dataSize ~/ 2);
    if (sampleCount <= 0) return const [];
    final frames = sampleCount ~/ channels;
    final count = math.min(buckets, frames);
    final data = ByteData.sublistView(bytes);
    final result = <double>[];
    for (var bucket = 0; bucket < count; bucket++) {
      final first = (bucket * frames / count).floor();
      final last = math.max(first + 1, ((bucket + 1) * frames / count).floor());
      var peak = 0.0;
      for (var frame = first; frame < last; frame++) {
        for (var channel = 0; channel < channels; channel++) {
          final index = dataOffset + (frame * channels + channel) * 2;
          if (index + 1 >= bytes.length) break;
          final sample = data.getInt16(index, Endian.little).abs() / 32768.0;
          if (sample > peak) peak = sample;
        }
      }
      result.add(peak);
    }
    return result;
  }

  Future<void> extractAudio() async {
    final video = videoPath;
    if (video == null || busy) return;
    setState(() { busy = true; status = 'Извлекаю аудио и добавляю его на таймлайн…'; });
    try {
      final docs = await getApplicationDocumentsDirectory();
      final outDir = Directory(p.join(docs.path, 'GifCut', 'Media'));
      await outDir.create(recursive: true);
      final safeName = p.basenameWithoutExtension(video).replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final stamp = DateTime.now().millisecondsSinceEpoch.toString();
      final output = p.join(outDir.path, '${safeName}_audio_$stamp.wav');
      final result = await Process.run(await findFfmpeg(), [
        '-hide_banner', '-y', '-i', video, '-map', '0:a:0', '-vn',
        '-c:a', 'pcm_s16le', '-ar', '44100', '-ac', '2', output,
      ], runInShell: false);
      if (result.exitCode != 0 || !await File(output).exists()) {
        final details = result.stderr.toString().trim();
        if (details.toLowerCase().contains('matches no streams')) throw Exception('В видео нет звуковой дорожки.');
        if (details.isNotEmpty) {
          final lines = details.split('\n').where((s) => s.trim().isNotEmpty).toList();
          throw Exception(lines.isEmpty ? 'FFmpeg не смог обработать видео.' : lines.last.trim());
        }
        throw Exception('FFmpeg не смог обработать видео.');
      }
      final waveform = await _readWaveform(output);
      if (!mounted) return;
      _performTimelineEdit(() {
        audioWaveform = waveform;
        audioPath = output;
        audioDuration = duration;
        audioClipStart = 0;
        audioClipEnd = duration.inMilliseconds / 1000;
        status = 'Готово: звук добавлен на отдельную дорожку. Его можно обрезать независимо от видео правым кликом.';
      });    } on ProcessException {
      if (mounted) setState(() => status = 'FFmpeg не найден. В архиве из GitHub Actions ffmpeg.exe лежит рядом с GifCut.exe. Для локального запуска добавьте FFmpeg в PATH.');
    } catch (e) {
      if (mounted) setState(() => status = 'Ошибка извлечения звука: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void setStatus(String text) { if (mounted) setState(() => status = text); }
  Future<void> cyclePlaybackRate() async {
    const rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final current = rates.indexOf(playbackRate);
    final next = rates[(current + 1) % rates.length];
    try {
      await player?.setRate(next);
      if (mounted) setState(() => playbackRate = next);
      setStatus('Скорость предпросмотра: $next×. На экспорт это не влияет.');
    } catch (e) {
      setStatus('Не удалось изменить скорость предпросмотра: $e');
    }
  }

  Future<void> togglePlayback() async {
    final activePlayer = player;
    if (videoPath == null || activePlayer == null || videoClips.isEmpty) return;
    if (playing) {
      if (_playheadInGap) {
        _stopGapPlayback();
        _suppressPlayerStateEvents = true;
        if (mounted) setState(() => playing = false);
        await activePlayer.pause();
        _suppressPlayerStateEvents = false;
      } else {
        await activePlayer.pause();
      }
      return;
    }
    if (_playheadInGap || _clipIndexAtTimelineTime(playheadSeconds) < 0) {
      final nextIndex = _gapNextClipIndex >= 0
          ? _gapNextClipIndex
          : videoClips.indexWhere((clip) => clip.timelineStart > playheadSeconds + 0.001);
      if (nextIndex < 0) {
        await seek(Duration.zero);
        return;
      }
      if (mounted) setState(() => playing = true);
      _startGapPlayback(startSeconds: playheadSeconds, nextClipIndex: nextIndex);
      return;
    }
    await activePlayer.play();
  }

  Future<void> _handlePlayerPosition(Duration sourcePosition) async {
    final activePlayer = player;
    if (!mounted || _switchingMedia || _seekingAcrossCut || _playheadInGap ||
        activePlayer == null || videoPath == null || videoClips.isEmpty) {
      return;
    }
    final sourceSeconds = sourcePosition.inMilliseconds / 1000;
    var index = _activePlaybackClipIndex;
    if (index < 0 || index >= videoClips.length) {
      index = videoClips.indexWhere((clip) =>
          sourceSeconds >= clip.start - 0.03 && sourceSeconds < clip.end - 0.03);
      if (index < 0) return;
      _activePlaybackClipIndex = index;
    }
    final clip = videoClips[index];
    if (sourceSeconds >= clip.end - 0.045) {
      if (playing && index + 1 < videoClips.length) {
        final next = videoClips[index + 1];
        if (next.timelineStart > clip.timelineEnd + 0.001) {
          _startGapPlayback(startSeconds: clip.timelineEnd, nextClipIndex: index + 1);
          return;
        }
        _activePlaybackClipIndex = index + 1;
        _seekingAcrossCut = true;
        setState(() => position = Duration(milliseconds: (next.timelineStart * 1000).round()));
        try {
          await activePlayer.seek(Duration(milliseconds: (next.start * 1000).round()));
        } finally {
          _seekingAcrossCut = false;
        }
      } else if (playing) {
        setState(() => position = Duration(milliseconds: (clip.timelineEnd * 1000).round()));
        await activePlayer.pause();
      }
      return;
    }
    if (sourceSeconds >= clip.start - 0.025) {
      final sequenceSeconds = clip.timelineStart + math.max(0, sourceSeconds - clip.start);
      setState(() => position = Duration(milliseconds: (sequenceSeconds * 1000).round()));
    }
  }

  void _stopGapPlayback({bool clearNext = false}) {
    _gapPlaybackTimer?.cancel();
    _gapPlaybackTimer = null;
    _gapPlaybackClock?.stop();
    _gapPlaybackClock = null;
    _gapResumePending = false;
    if (clearNext) _gapNextClipIndex = -1;
  }

  void _startGapPlayback({required double startSeconds, required int nextClipIndex}) {
    if (nextClipIndex < 0 || nextClipIndex >= videoClips.length) return;
    final endSeconds = videoClips[nextClipIndex].timelineStart;
    final safeStart = startSeconds.clamp(0.0, endSeconds).toDouble();
    _gapNextClipIndex = nextClipIndex;
    if (endSeconds <= safeStart + 0.001) {
      unawaited(_resumePlaybackAfterGap());
      return;
    }
    _stopGapPlayback();
    _gapPlaybackStartSeconds = safeStart;
    _gapPlaybackEndSeconds = endSeconds;
    _gapNextClipIndex = nextClipIndex;
    _gapPlaybackClock = Stopwatch()..start();
    _suppressPlayerStateEvents = true;
    setState(() {
      _playheadInGap = true;
      _activePlaybackClipIndex = -1;
      position = Duration(milliseconds: (safeStart * 1000).round());
      playing = true;
    });
    unawaited(player?.pause());
    _gapPlaybackTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (!mounted || !playing || !_playheadInGap) {
        _stopGapPlayback();
        return;
      }
      final elapsedSeconds = (_gapPlaybackClock?.elapsedMilliseconds ?? 0) / 1000;
      final nextSeconds = _gapPlaybackStartSeconds + elapsedSeconds;
      if (nextSeconds >= _gapPlaybackEndSeconds) {
        if (_gapResumePending) return;
        _gapResumePending = true;
        timer.cancel();
        _gapPlaybackTimer = null;
        unawaited(_resumePlaybackAfterGap());
      } else {
        setState(() => position = Duration(milliseconds: (nextSeconds * 1000).round()));
      }
    });
  }

  Future<void> _resumePlaybackAfterGap() async {
    final activePlayer = player;
    final nextIndex = _gapNextClipIndex;
    _stopGapPlayback();
    if (!mounted || !playing || activePlayer == null ||
        nextIndex < 0 || nextIndex >= videoClips.length) {
      _suppressPlayerStateEvents = false;
      if (mounted) setState(() => playing = false);
      return;
    }
    final next = videoClips[nextIndex];
    setState(() {
      position = Duration(milliseconds: (next.timelineStart * 1000).round());
      _activePlaybackClipIndex = nextIndex;
    });
    _seekingAcrossCut = true;
    try {
      await activePlayer.seek(Duration(milliseconds: (next.start * 1000).round()));
      if (mounted && playing) await activePlayer.play();
    } catch (error) {
      if (mounted) {
        setState(() => playing = false);
        status = 'Не удалось продолжить видео после разрыва: $error';
      }
    } finally {
      _seekingAcrossCut = false;
      _gapNextClipIndex = -1;
      _suppressPlayerStateEvents = false;
      if (mounted) setState(() => _playheadInGap = !playing);
    }
  }

  Future<void> seek(Duration target) async {
    final activePlayer = player;
    if (activePlayer == null || videoPath == null) return;
    final maxMs = timelineDuration.inMilliseconds;
    final ms = target.inMilliseconds.clamp(0, maxMs > 0 ? maxMs : duration.inMilliseconds).toInt();
    final sequenceSeconds = ms / 1000;
    final index = _clipIndexAtTimelineTime(sequenceSeconds);
    if (index < 0) {
      _stopGapPlayback();
      _gapNextClipIndex = videoClips.indexWhere((clip) => clip.timelineStart > sequenceSeconds + 0.001);
      _suppressPlayerStateEvents = true;
      _activePlaybackClipIndex = -1;
      setState(() {
        position = Duration(milliseconds: ms);
        _playheadInGap = true;
        playing = false;
      });
      await activePlayer.pause();
      _suppressPlayerStateEvents = false;
      return;
    }
    _stopGapPlayback(clearNext: true);
    final clip = videoClips[index];
    final sourceSeconds = clip.start + sequenceSeconds - clip.timelineStart;
    _activePlaybackClipIndex = index;
    setState(() {
      position = Duration(milliseconds: ms);
      _playheadInGap = false;
    });
    _seekingAcrossCut = true;
    try {
      await activePlayer.seek(Duration(milliseconds: (sourceSeconds * 1000).round()));
    } finally {
      _seekingAcrossCut = false;
    }
  }

  void _startEdgeDrag(int index, bool left) {
    if (index < 0 || index >= videoClips.length) return;
    _edgeDragBefore = _captureTimelineSnapshot();
    _edgeDragIndex = index;
    _edgeDragLeft = left;
    final clip = videoClips[index];
    _edgeDragOriginalEdge = left ? clip.timelineStart : clip.timelineEnd;
    _edgeDragPointerX = 0;
    setState(() {
      selectedClipIndex = index;
      _timelineSnapAt = null;
    });
  }

  void _updateEdgeDrag(DragUpdateDetails details) {
    if (_edgeDragIndex < 0 || _edgeDragIndex >= videoClips.length) return;
    _edgeDragPointerX += details.delta.dx;
    final clip = videoClips[_edgeDragIndex];
    var nextEdge = _edgeDragOriginalEdge + _edgeDragPointerX / zoom;
    double? snapTo;
    if (snappingEnabled) {
      final points = <double>[playheadSeconds];
      for (var i = 0; i < videoClips.length; i++) {
        if (i == _edgeDragIndex) continue;
        points
          ..add(videoClips[i].timelineStart)
          ..add(videoClips[i].timelineEnd);
      }
      final threshold = 7 / zoom;
      for (final point in points) {
        if ((point - nextEdge).abs() <= threshold &&
            (snapTo == null || (point - nextEdge).abs() < (snapTo - nextEdge).abs())) {
          snapTo = point;
        }
      }
      if (snapTo != null) nextEdge = snapTo;
    }
    setState(() {
      if (_edgeDragLeft) {
        final delta = nextEdge - clip.timelineStart;
        if (clip.length - delta >= TimelineEditing.minimumClipLength && clip.start + delta >= 0) {
          clip.start += delta;
          clip.timelineStart = nextEdge;
        }
      } else {
        final newLength = nextEdge - clip.timelineStart;
        final sourceDuration = duration.inMilliseconds / 1000;
        if (newLength >= TimelineEditing.minimumClipLength &&
            (sourceDuration <= 0 || clip.start + newLength <= sourceDuration)) {
          clip.end = clip.start + newLength;
        }
      }
      _timelineSnapAt = snapTo;
      projectDirty = true;
    });
  }

  void _finishEdgeDrag() {
    if (_edgeDragIndex < 0) return;
    final before = _edgeDragBefore;
    if (before != null) _timelineHistory.record(before: before, after: _captureTimelineSnapshot());
    _edgeDragBefore = null;
    _edgeDragIndex = -1;
    if (mounted) {
      setState(() {
        _timelineSnapAt = null;
        status = 'Длина клипа изменена. Ctrl+Z — отменить.';
      });
    }
  }

  void setTimelineZoom(double next) {
    setState(() {
      zoom = next.clamp(8.0, 160.0).toDouble();
      projectDirty = true;
    });
  }

  void seekTimeline(double x) {
    if (timelineDuration.inMilliseconds <= 0) return;
    final target = Duration(
      milliseconds: ((x / zoom).clamp(0.0, timelineSeconds) * 1000).round(),
    );
    unawaited(seek(target));
  }

  String time(Duration value) {
    final total = math.max(0, value.inSeconds);
    final h = total ~/ 3600;
    final m = ((total % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    if (h > 0) return '${h.toString().padLeft(2, '0')}:$m:$s';
    return '$m:$s';
  }

  Future<void> showKeyboardShortcuts() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Горячие клавиши'),
        content: const SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _ShortcutRow('Пробел', 'Воспроизведение / пауза'),
              _ShortcutRow('← / →', 'На один кадр назад / вперёд'),
              _ShortcutRow('Shift + ← / →', 'На одну секунду назад / вперёд'),
              _ShortcutRow('Ctrl + ← / →', 'Предыдущая / следующая точка монтажа'),
              _ShortcutRow('J / K / L', 'Кадр назад / пауза / ускоренное воспроизведение'),
              _ShortcutRow('I / O', 'Обрезать начало / конец по курсору'),
              _ShortcutRow('Ctrl + B / Ctrl + K', 'Разделить клип'),
              _ShortcutRow('Ctrl + D', 'Дублировать клип после исходного'),
              _ShortcutRow('Delete', 'Удалить, оставить разрыв'),
              _ShortcutRow('Shift + Delete', 'Удалить со сдвигом'),
              _ShortcutRow('Ctrl + Z / Ctrl + Y', 'Отменить / повторить'),
              _ShortcutRow('Ctrl + S / Ctrl + Shift + S', 'Сохранить / сохранить как'),
              _ShortcutRow('Ctrl + O / Ctrl + Shift + O', 'Открыть проект / импортировать видео'),
              _ShortcutRow('Ctrl + M', 'Экспортировать видео'),
              _ShortcutRow('Ctrl + колесо мыши', 'Масштаб таймлайна под указателем'),
              _ShortcutRow('Колесо мыши', 'Горизонтальная прокрутка таймлайна'),
              _ShortcutRow('F1', 'Показать эту справку'),
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Закрыть'))],
      ),
    );
  }

  Future<void> _stepFrame(int direction) async {
    if (videoPath == null) return;
    if (playing) await player?.pause();
    final frameMs = (1000 / frameRate).round().clamp(1, 1000);
    await seek(position + Duration(milliseconds: frameMs * direction));
  }

  Future<void> _seekToEditPoint(int direction) async {
    final points = <double>[];
    for (final clip in videoClips) {
      points..add(clip.timelineStart)..add(clip.timelineEnd);
    }
    points.sort();
    if (direction < 0) {
      for (final point in points.reversed) {
        if (point < playheadSeconds - 0.02) {
          await seek(Duration(milliseconds: (point * 1000).round()));
          return;
        }
      }
      await seek(Duration.zero);
    } else {
      for (final point in points) {
        if (point > playheadSeconds + 0.02) {
          await seek(Duration(milliseconds: (point * 1000).round()));
          return;
        }
      }
      await seek(timelineDuration);
    }
  }

  Future<void> _shuttleForward() async {
    if (player == null || videoPath == null) return;
    const rates = [1.0, 2.0, 4.0, 8.0];
    final index = rates.indexOf(playbackRate);
    final next = !playing ? 1.0 : rates[(index < 0 ? 0 : (index + 1) % rates.length)];
    await player!.setRate(next);
    await player!.play();
    if (mounted) setState(() => playbackRate = next);
  }

  Future<void> _pauseAndResetShuttle() async {
    if (player == null) return;
    await player!.pause();
    await player!.setRate(1.0);
    if (mounted) setState(() => playbackRate = 1.0);
  }

  bool _isTextInputFocused() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    if (context.widget is EditableText) return true;
    var editing = false;
    context.visitAncestorElements((element) {
      if (element.widget is EditableText) {
        editing = true;
        return false;
      }
      return true;
    });
    return editing;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (_isTextInputFocused()) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final ctrl = keyboard.isControlPressed;
    final shift = keyboard.isShiftPressed;
    final key = event.logicalKey;
    if (event is KeyRepeatEvent &&
        (ctrl || (key != LogicalKeyboardKey.arrowLeft && key != LogicalKeyboardKey.arrowRight))) {
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyZ) {
      if (shift) { redoTimelineEdit(); } else { undoTimelineEdit(); }
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyY) { redoTimelineEdit(); return KeyEventResult.handled; }
    if (ctrl && key == LogicalKeyboardKey.keyO) {
      unawaited(shift ? pickVideo() : openProject());
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyS) {
      unawaited(saveProject(saveAs: shift));
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyE) { unawaited(extractAudio()); return KeyEventResult.handled; }
    if (ctrl && key == LogicalKeyboardKey.keyM) { unawaited(exportEditedVideo()); return KeyEventResult.handled; }
    if (ctrl && key == LogicalKeyboardKey.keyD) { duplicateSelectedClip(); return KeyEventResult.handled; }
    if (ctrl && (key == LogicalKeyboardKey.keyB || key == LogicalKeyboardKey.keyK)) {
      splitSelectedClip();
      return KeyEventResult.handled;
    }
    if (ctrl && (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.add || key == LogicalKeyboardKey.numpadAdd)) {
      setTimelineZoom(zoom + 4);
      return KeyEventResult.handled;
    }
    if (ctrl && (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract)) {
      setTimelineZoom(zoom - 4);
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.arrowLeft) { unawaited(_seekToEditPoint(-1)); return KeyEventResult.handled; }
    if (ctrl && key == LogicalKeyboardKey.arrowRight) { unawaited(_seekToEditPoint(1)); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.f1) { unawaited(showKeyboardShortcuts()); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.delete && shift) { deleteSelectedClip(ripple: true); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) { deleteSelectedClip(); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.space) { unawaited(togglePlayback()); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.keyJ) { unawaited(_stepFrame(-1)); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.keyK) { unawaited(_pauseAndResetShuttle()); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.keyL) { unawaited(_shuttleForward()); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.keyI) { trimSelectedStart(); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.keyO) { trimSelectedEnd(); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.arrowLeft) {
      unawaited(shift ? seek(position - const Duration(seconds: 1)) : _stepFrame(-1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      unawaited(shift ? seek(position + const Duration(seconds: 1)) : _stepFrame(1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) { unawaited(seek(Duration.zero)); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.end) { unawaited(seek(timelineDuration)); return KeyEventResult.handled; }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
        autofocus: true,        onKeyEvent: _handleKeyEvent,
        child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              topBar(),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    toolRail(),
                    const VerticalDivider(width: 1),
                    SizedBox(width: _mediaPanelWidth, child: mediaPanel()),
                    _verticalPanelSplitter('media-panel-splitter', (dx) {
                      final screenWidth = MediaQuery.sizeOf(context).width;
                      final maxWidth = (screenWidth - 64 - 1 - 14 - _inspectorPanelWidth - 220).clamp(150.0, 420.0).toDouble();
                      _mediaPanelWidth = (_mediaPanelWidth + dx).clamp(150.0, maxWidth).toDouble();
                    }),
                    Expanded(child: previewPanel()),
                    _verticalPanelSplitter('inspector-panel-splitter', (dx) {
                      final screenWidth = MediaQuery.sizeOf(context).width;
                      final maxWidth = (screenWidth - 64 - 1 - 14 - _mediaPanelWidth - 220).clamp(190.0, 440.0).toDouble();
                      _inspectorPanelWidth = (_inspectorPanelWidth - dx).clamp(190.0, maxWidth).toDouble();
                    }),
                    SizedBox(width: _inspectorPanelWidth, child: inspectorPanel()),
                  ],
                ),
              ),
              _horizontalTimelineSplitter(),
              timelinePanel(),
              const Divider(height: 1),
              statusBar(),
            ],
          ),
        ),
      ));

  Widget _verticalPanelSplitter(String key, ValueChanged<double> onDrag) => MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          key: ValueKey(key),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) => setState(() => onDrag(details.delta.dx)),
          child: SizedBox(width: 7, child: Center(child: Container(width: 1, height: double.infinity, color: const Color(0xFF343744)))),
        ),
      );

  Widget _horizontalTimelineSplitter() => MouseRegion(
        cursor: SystemMouseCursors.resizeRow,
        child: GestureDetector(
          key: const ValueKey('timeline-panel-splitter'),
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (details) => setState(() {
            _timelinePanelHeight = (_timelinePanelHeight - details.delta.dy).clamp(160.0, 520.0).toDouble();
          }),
          child: SizedBox(height: 8, child: Center(child: Container(width: double.infinity, height: 1, color: const Color(0xFF343744)))),
        ),
      );

  Widget topBar() => Container(
        height: 56,
        color: const Color(0xFF191B21),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(children: [
          Container(width: 34, height: 34, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF9B6DFF), Color(0xFF7046C8)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: accent.withValues(alpha: .18), blurRadius: 12, offset: const Offset(0, 3))]), child: const Icon(Icons.movie_creation_outlined, color: Colors.white, size: 20)),
          const SizedBox(width: 10),
          const Text('gifcut', style: TextStyle(fontSize: 18, letterSpacing: -.5, fontWeight: FontWeight.w900)),
          const SizedBox(width: 10),
          const SizedBox(width: 10),
          Flexible(child: Text((projectFilePath == null ? 'Новый проект' : p.basenameWithoutExtension(projectFilePath!)) + (projectDirty ? ' •' : ''), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFFD3D3DF)))),
          const Spacer(),
          IconButton(
            tooltip: checkingForUpdates ? 'Проверка обновлений…' : 'Проверить обновления',
            visualDensity: VisualDensity.compact,
            onPressed: checkingForUpdates ? null : () => unawaited(checkForUpdates(showNoUpdateMessage: true)),
            icon: checkingForUpdates
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.system_update_alt, size: 18, color: muted),
          ),
          IconButton(
            key: const ValueKey('keyboard-shortcuts'),
            tooltip: 'Горячие клавиши',
            visualDensity: VisualDensity.compact,
            onPressed: showKeyboardShortcuts,
            icon: const Icon(Icons.keyboard_outlined, size: 18),
          ),
          const Icon(Icons.desktop_windows_outlined, size: 16, color: muted),
          const SizedBox(width: 8),
          const Text('DESKTOP BETA', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget toolRail() => Container(
        width: 64,
        color: const Color(0xFF17191F),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: SingleChildScrollView(
          child: Column(children: [
            _railAction(Icons.folder_open_outlined, 'Открыть проект', openProject, disabled: busy),
            _railAction(Icons.save_outlined, 'Сохранить', () => unawaited(saveProject()), disabled: videoPath == null || busy),
            _railAction(Icons.save_as_outlined, 'Сохранить как', () => unawaited(saveProject(saveAs: true)), disabled: videoPath == null || busy),
            const Divider(height: 14),
            _railAction(Icons.video_call_outlined, 'Импорт видео', pickVideo, disabled: busy, color: accent),
            _railAction(Icons.add_photo_alternate_outlined, 'Добавить фото', importPhotoOverlay, disabled: busy || videoPath == null),
            _railAction(Icons.graphic_eq, 'Извлечь звук', extractAudio, disabled: busy || videoPath == null),
            const Divider(height: 14),
            _railAction(Icons.tune_rounded, 'Цвет', showColorAdjustments, disabled: busy || videoClips.isEmpty),
            _railAction(Icons.volume_up_rounded, 'Громкость', () => setState(() => inspectorTab = 'audio')),
            _railAction(Icons.undo, 'Отменить', undoTimelineEdit, disabled: !_timelineHistory.canUndo),
            _railAction(Icons.redo, 'Повторить', redoTimelineEdit, disabled: !_timelineHistory.canRedo),
            const Divider(height: 14),
            _railAction(Icons.ios_share, 'Экспорт', exportEditedVideo, disabled: videoClips.isEmpty || busy, color: accent),
            _railAction(Icons.system_update_alt, 'Обновления', () => unawaited(checkForUpdates(showNoUpdateMessage: true)), disabled: checkingForUpdates),
            _railAction(Icons.keyboard_outlined, 'Горячие клавиши', showKeyboardShortcuts),
          ]),
        ),
      );

  Widget _railAction(IconData icon, String tooltip, VoidCallback action, {bool disabled = false, Color color = muted}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Tooltip(
          message: tooltip,
          child: IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: disabled ? null : action,
            icon: Icon(icon, size: 20, color: disabled ? muted.withValues(alpha: .35) : color),
          ),
        ),
      );

  Widget mediaPanel() => Container(
        color: panel,
        padding: const EdgeInsets.fromLTRB(12, 15, 12, 12),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('МЕДИА', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: Tooltip(
                message: 'Импортировать видео',
                child: OutlinedButton.icon(
                  onPressed: busy ? null : pickVideo,
                  icon: const Icon(Icons.video_call_outlined, size: 17),
                  label: const Text('Импортировать видео'),
                ),
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: busy ? null : pickVideo,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
                decoration: BoxDecoration(color: const Color(0xFF202630), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF333542))),
                child: const Column(children: [
                  Icon(Icons.video_call_outlined, color: accent, size: 30),
                  SizedBox(height: 8),
                  Text('Добавить видео', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text('MP4 · MOV · MKV и другие', style: TextStyle(fontSize: 10, color: muted), textAlign: TextAlign.center),
                ]),
              ),
            ),
            if (videoPath != null) ...[
              const SizedBox(height: 14),
              const Text('ФАЙЛЫ ПРОЕКТА', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.1, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              mediaItem(Icons.movie_outlined, p.basename(videoPath!), 'Видео · исходник', videoBlue, imagePath: videoThumbnails.isNotEmpty ? videoThumbnails.first : null),
              if (audioPath != null) ...[
                const SizedBox(height: 7),
                mediaItem(Icons.graphic_eq, p.basename(audioPath!), 'Извлечённое аудио', audioGreen),
              ],
              if (photoOverlays.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('ФОТО', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.1, fontWeight: FontWeight.w700)),
                const SizedBox(height: 7),
                for (var i = 0; i < photoOverlays.length; i++) ...[
                  if (i > 0) const SizedBox(height: 6),
                  mediaItem(Icons.image_outlined, p.basename(photoOverlays[i].path), 'Фото · слой ${i + 1}', accent,
                    imagePath: photoOverlays[i].path,
                    selected: selectedPhotoOverlay == i,
                    onTap: () => setState(() => selectedPhotoOverlay = i)),
                ],
              ],
            ],
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            const Row(children: [Icon(Icons.tips_and_updates_outlined, color: muted, size: 15), SizedBox(width: 7), Text('Подсказка', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))]),
            const SizedBox(height: 5),
            const Text('Извлеките звук, чтобы получить отдельный клип на аудиодорожке под видео.', style: TextStyle(color: muted, fontSize: 11, height: 1.4)),
          ]),
        ),
      );

  Widget mediaItem(IconData icon, String name, String kind, Color color, {String? imagePath, bool selected = false, VoidCallback? onTap}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(color: selected ? const Color(0xFF26364A) : const Color(0xFF202630), borderRadius: BorderRadius.circular(8), border: Border.all(color: selected ? accent : const Color(0xFF343644))),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(width: 54, height: 40, child: imagePath != null
                ? Image.file(File(imagePath), fit: BoxFit.cover, errorBuilder: (_, __, ___) => ColoredBox(color: const Color(0xFF11151C), child: Icon(icon, color: color, size: 21)))
                : ColoredBox(color: const Color(0xFF11151C), child: Icon(icon, color: color, size: 21))),
            ),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(kind, style: const TextStyle(color: muted, fontSize: 9)),
            ])),
          ]),
        ),
      );

  Widget _videoResizeHandle({
    required Size canvasSize,
    required double x,
    required double y,
    required int horizontalDirection,
    required int verticalDirection,
    required String id,
  }) {
    final scaleX = (videoScaleX * previewZoom).abs().clamp(.2, 5.0).toDouble();
    final scaleY = (videoScaleY * previewZoom).abs().clamp(.2, 5.0).toDouble();
    final cursor = horizontalDirection == 0
        ? SystemMouseCursors.resizeUpDown
        : verticalDirection == 0
            ? SystemMouseCursors.resizeLeftRight
            : SystemMouseCursors.resizeUpLeftDownRight;
    return Positioned(
      left: x - 7 / scaleX,
      top: y - 7 / scaleY,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          key: ValueKey('video-resize-$id'),
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) => _resizeHandleLastGlobal[id] = details.globalPosition,
          onPanUpdate: (details) {
            final previous = _resizeHandleLastGlobal[id] ?? details.globalPosition;
            final screenDelta = details.globalPosition - previous;
            _resizeHandleLastGlobal[id] = details.globalPosition;
            final radians = videoRotation * math.pi / 180;
            final localDx = (screenDelta.dx * math.cos(radians) + screenDelta.dy * math.sin(radians)) / math.max(.1, previewZoom);
            final localDy = (-screenDelta.dx * math.sin(radians) + screenDelta.dy * math.cos(radians)) / math.max(.1, previewZoom);
            setState(() {
              if (horizontalDirection != 0) {
                videoScaleX = (videoScaleX + localDx * horizontalDirection * 2 / math.max(1, canvasSize.width)).clamp(.2, 4.0).toDouble();
              }
              if (verticalDirection != 0) {
                videoScaleY = (videoScaleY + localDy * verticalDirection * 2 / math.max(1, canvasSize.height)).clamp(.2, 4.0).toDouble();
              }
              projectDirty = true;
            });
          },
          onPanEnd: (_) => _resizeHandleLastGlobal.remove(id),
          child: Container(
            width: 14 / scaleX,
            height: 14 / scaleY,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: accent, width: 2),
              borderRadius: BorderRadius.circular(2 / math.min(scaleX, scaleY)),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 3)],
            ),
          ),
        ),
      ),
    );
  }

  Widget previewPanel() => Container(
        color: const Color(0xFF101217),
        child: Column(children: [
          Container(
            height: 39,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: const BoxDecoration(color: Color(0xFF171820), border: Border(bottom: BorderSide(color: Color(0xFF292B36)))),
            child: LayoutBuilder(builder: (context, constraints) => Row(children: [
              const Text('ПРЕДПРОСМОТР', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
              if (constraints.maxWidth > 300) ...[
                const SizedBox(width: 8),
                Expanded(child: Text(videoPath == null ? 'Нет клипа' : p.basename(videoPath!), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end, style: const TextStyle(color: Color(0xFFB8B8C6), fontSize: 11))),
              ],
            ])),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              color: const Color(0xFF080A0E),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(18),
              child: videoPath == null
                  ? SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 120),
                        child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.slideshow_outlined, size: 54, color: Color(0xFF414451)),
                          SizedBox(height: 14),
                          Text('Ваше видео появится здесь', style: TextStyle(color: Color(0xFF9A9CAB), fontSize: 14, fontWeight: FontWeight.w600)),
                          SizedBox(height: 5),
                          Text('Нажмите «Импорт видео», чтобы начать', style: TextStyle(color: Color(0xFF646777), fontSize: 11)),
                        ]),
                      ),
                    )
                  : videoController == null
                      ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.warning_amber_rounded, size: 42, color: Color(0xFFD5A35C)),
                          SizedBox(height: 12),
                          Text('Предпросмотр недоступен', style: TextStyle(color: Color(0xFFD3D1D8), fontSize: 13, fontWeight: FontWeight.w600)),
                          SizedBox(height: 5),
                          Text('Можно продолжить извлечение аудио.', style: TextStyle(color: Color(0xFF8A8D9D), fontSize: 11)),
                        ])
                      : Center(
                          child: AspectRatio(
                            aspectRatio: previewAspectRatio,
                            child: LayoutBuilder(builder: (context, bounds) {
                              final shortSide = math.min(bounds.maxWidth, bounds.maxHeight);
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: ClipRect(
                                  child: Stack(fit: StackFit.expand, children: [
                                    const ColoredBox(color: Colors.black),
                                    if (_showVerticalSnapGuide)
                                      Positioned(left: bounds.maxWidth / 2 - .5, top: 0, bottom: 0, child: IgnorePointer(child: Container(width: 1, color: const Color(0xFFB18CFF)))),
                                    if (_showHorizontalSnapGuide)
                                      Positioned(top: bounds.maxHeight / 2 - .5, left: 0, right: 0, child: IgnorePointer(child: Container(height: 1, color: const Color(0xFF35D7FF)))),
                                    Positioned.fill(
                                      child: Transform.translate(
                                        offset: Offset(videoOffsetX * bounds.maxWidth, videoOffsetY * bounds.maxHeight),
                                        child: Transform.rotate(
                                          angle: videoRotation * math.pi / 180,
                                          child: Transform.scale(
                                            scaleX: videoScaleX * previewZoom,
                                            scaleY: videoScaleY * previewZoom,
                                            child: SizedBox(
                                              width: bounds.maxWidth,
                                              height: bounds.maxHeight,
                                              child: Stack(
                                                clipBehavior: Clip.none,
                                                fit: StackFit.expand,
                                                children: [
                                                  Positioned.fill(
                                                    child: MouseRegion(
                                                      cursor: SystemMouseCursors.move,
                                                      child: GestureDetector(
                                                        behavior: HitTestBehavior.opaque,
                                                        onPanStart: (details) => _videoMoveLastGlobal = details.globalPosition,
                                                        onPanUpdate: (details) => setState(() {
                                                          final previous = _videoMoveLastGlobal ?? details.globalPosition;
                                                          final screenDelta = details.globalPosition - previous;
                                                          _videoMoveLastGlobal = details.globalPosition;
                                                          videoOffsetX += screenDelta.dx / math.max(1, bounds.maxWidth);
                                                          videoOffsetY += screenDelta.dy / math.max(1, bounds.maxHeight);
                                                          _showVerticalSnapGuide = videoOffsetX.abs() < 0.014;
                                                          _showHorizontalSnapGuide = videoOffsetY.abs() < 0.014;
                                                          projectDirty = true;
                                                        }),
                                                        onPanEnd: (_) {
                                                          _videoMoveLastGlobal = null;
                                                          setState(() {
                                                            _showVerticalSnapGuide = false;
                                                            _showHorizontalSnapGuide = false;
                                                          });
                                                        },
                                                        child: ColorFiltered(
                                                          colorFilter: ColorFilter.matrix(filtersEnabled ? previewColorMatrix : const <double>[1,0,0,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0]),
                                                          child: ColorFiltered(
                                                            colorFilter: ColorFilter.matrix(effectColorMatrix),
                                                            child: ImageFiltered(
                                                              imageFilter: ui.ImageFilter.blur(
                                                                sigmaX: (videoEffect == 'Мягкое размытие' ? 2.0 : 0.0) + (motionBlurEnabled ? 1.2 : 0.0),
                                                                sigmaY: (videoEffect == 'Мягкое размытие' ? 2.0 : 0.0) + (motionBlurEnabled ? 1.2 : 0.0),
                                                              ),
                                                              child: Video(controller: videoController!, controls: NoVideoControls, fit: BoxFit.cover),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  Positioned.fill(
                                                    child: IgnorePointer(
                                                      child: DecoratedBox(
                                                        decoration: BoxDecoration(border: Border.all(color: accent, width: 1.5)),
                                                      ),
                                                    ),
                                                  ),
                                                  _videoResizeHandle(canvasSize: Size(bounds.maxWidth, bounds.maxHeight), x: 0, y: 0, horizontalDirection: -1, verticalDirection: -1, id: 'top-left'),
                                                  _videoResizeHandle(canvasSize: Size(bounds.maxWidth, bounds.maxHeight), x: bounds.maxWidth / 2, y: 0, horizontalDirection: 0, verticalDirection: -1, id: 'top'),
                                                  _videoResizeHandle(canvasSize: Size(bounds.maxWidth, bounds.maxHeight), x: bounds.maxWidth, y: 0, horizontalDirection: 1, verticalDirection: -1, id: 'top-right'),
                                                  _videoResizeHandle(canvasSize: Size(bounds.maxWidth, bounds.maxHeight), x: 0, y: bounds.maxHeight / 2, horizontalDirection: -1, verticalDirection: 0, id: 'left'),
                                                  _videoResizeHandle(canvasSize: Size(bounds.maxWidth, bounds.maxHeight), x: bounds.maxWidth, y: bounds.maxHeight / 2, horizontalDirection: 1, verticalDirection: 0, id: 'right'),
                                                  _videoResizeHandle(canvasSize: Size(bounds.maxWidth, bounds.maxHeight), x: 0, y: bounds.maxHeight, horizontalDirection: -1, verticalDirection: 1, id: 'bottom-left'),
                                                  _videoResizeHandle(canvasSize: Size(bounds.maxWidth, bounds.maxHeight), x: bounds.maxWidth / 2, y: bounds.maxHeight, horizontalDirection: 0, verticalDirection: 1, id: 'bottom'),
                                                  _videoResizeHandle(canvasSize: Size(bounds.maxWidth, bounds.maxHeight), x: bounds.maxWidth, y: bounds.maxHeight, horizontalDirection: 1, verticalDirection: 1, id: 'bottom-right'),
                                                  Positioned(
                                                    left: bounds.maxWidth / 2 - 17 / math.max(.2, videoScaleX * previewZoom),
                                                    top: 18 / math.max(.2, videoScaleY * previewZoom),
                                                    width: 34 / math.max(.2, videoScaleX * previewZoom),
                                                    height: 34 / math.max(.2, videoScaleY * previewZoom),
                                                    child: MouseRegion(
                                                      cursor: SystemMouseCursors.grab,
                                                      child: GestureDetector(
                                                        key: const ValueKey('video-rotate-handle'),
                                                        behavior: HitTestBehavior.opaque,
                                                        onPanStart: (details) => _videoRotateLastGlobal = details.globalPosition,
                                                        onPanUpdate: (details) => setState(() {
                                                          final previous = _videoRotateLastGlobal ?? details.globalPosition;
                                                          final screenDelta = details.globalPosition - previous;
                                                          _videoRotateLastGlobal = details.globalPosition;
                                                          videoRotation = (videoRotation + (screenDelta.dx - screenDelta.dy) * .7) % 360;
                                                          projectDirty = true;
                                                        }),
                                                        onPanEnd: (_) => _videoRotateLastGlobal = null,
                                                        child: Container(
                                                          decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white, width: 1.5), boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)]),
                                                          child: const Icon(Icons.rotate_90_degrees_ccw, size: 17, color: Colors.white),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    for (var i = 0; i < photoOverlays.length; i++)
                                      Positioned(
                                        left: bounds.maxWidth / 2 + photoOverlays[i].x * bounds.maxWidth - shortSide * .18 * photoOverlays[i].scale,
                                        top: bounds.maxHeight / 2 + photoOverlays[i].y * bounds.maxHeight - shortSide * .18 * photoOverlays[i].scale,
                                        width: shortSide * .36 * photoOverlays[i].scale,
                                        height: shortSide * .36 * photoOverlays[i].scale,
                                        child: GestureDetector(
                                          onTap: () => setState(() => selectedPhotoOverlay = i),
                                          onPanStart: (_) => setState(() => selectedPhotoOverlay = i),
                                          onPanUpdate: (d) => setState(() {
                                            var nextX = (photoOverlays[i].x + d.delta.dx / bounds.maxWidth).clamp(-1.5, 1.5).toDouble();
                                            var nextY = (photoOverlays[i].y + d.delta.dy / bounds.maxHeight).clamp(-1.5, 1.5).toDouble();
                                            _showVerticalSnapGuide = nextX.abs() < 0.022;
                                            _showHorizontalSnapGuide = nextY.abs() < 0.022;
                                            if (nextX.abs() < 0.022) nextX *= 0.42;
                                            if (nextY.abs() < 0.022) nextY *= 0.42;
                                            if (nextX.abs() < 0.0025) nextX = 0;
                                            if (nextY.abs() < 0.0025) nextY = 0;
                                            photoOverlays[i].x = nextX;
                                            photoOverlays[i].y = nextY;
                                            projectDirty = true;
                                          }),
                                          onPanEnd: (_) => setState(() { _showVerticalSnapGuide = false; _showHorizontalSnapGuide = false; }),
                                          child: Transform.rotate(
                                            angle: photoOverlays[i].rotation * math.pi / 180,
                                            child: Opacity(
                                              opacity: photoOverlays[i].opacity,
                                              child: DecoratedBox(
                                                decoration: BoxDecoration(border: selectedPhotoOverlay == i ? Border.all(color: accent, width: 2) : null),
                                                child: Stack(fit: StackFit.expand, children: [
                                                  Image.file(File(photoOverlays[i].path), fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
                                                  if (selectedPhotoOverlay == i)
                                                    for (final point in const [Alignment.topLeft, Alignment.topCenter, Alignment.topRight, Alignment.centerLeft, Alignment.centerRight, Alignment.bottomLeft, Alignment.bottomCenter, Alignment.bottomRight])
                                                      Align(alignment: point, child: GestureDetector(
                                                        onPanUpdate: (d) => setState(() {
                                                          final delta = (d.delta.dx.abs() + d.delta.dy.abs()) / math.max(1, shortSide * .36);
                                                          photoOverlays[i].scale = (photoOverlays[i].scale + delta * ((point.x != 0 && d.delta.dx * point.x > 0) || (point.y != 0 && d.delta.dy * point.y > 0) ? 1 : -1)).clamp(.1, 5.0).toDouble();
                                                          projectDirty = true;
                                                        }),
                                                        child: Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.white, border: Border.all(color: accent, width: 2), borderRadius: BorderRadius.circular(2))),
                                                      )),
                                                ]),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (previewTransitionOverlay.opacity > 0)
                                      Positioned.fill(child: IgnorePointer(child: ColoredBox(color: previewTransitionOverlay.color.withValues(alpha: previewTransitionOverlay.opacity)))),
                                    if (_playheadInGap)
                                      const Positioned.fill(child: IgnorePointer(child: ColoredBox(color: Colors.black))),
                                  ]),
                                ),
                              );
                            }),
                          ),
                        ),
            ),
          ),
          Container(
            height: 63,
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
            decoration: const BoxDecoration(color: Color(0xFF171820), border: Border(top: BorderSide(color: Color(0xFF292B36)))),
            child: LayoutBuilder(builder: (context, constraints) {
              final compact = constraints.maxWidth < 380;
              final seekSlider = SliderTheme(
                data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5), overlayShape: const RoundSliderOverlayShape(overlayRadius: 11)),
                child: Slider(
                  value: timelineDuration.inMilliseconds > 0 ? (position.inMilliseconds / timelineDuration.inMilliseconds).clamp(0.0, 1.0).toDouble() : 0,
                  onChanged: timelineDuration.inMilliseconds > 0 ? (v) => seek(Duration(milliseconds: (timelineDuration.inMilliseconds * v).round())) : null,
                ),
              );
              final playButton = IconButton.filledTonal(
                tooltip: playing ? 'Пауза' : 'Воспроизвести',
                onPressed: videoPath == null ? null : togglePlayback,
                icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 21),
                visualDensity: VisualDensity.compact,
              );
              if (compact) {
                return Row(children: [
                  Text(time(position), style: const TextStyle(fontSize: 10, color: Color(0xFFD7D7E3))),
                  const SizedBox(width: 5),
                  Expanded(child: seekSlider),
                  const SizedBox(width: 5),
                  Text(time(timelineDuration), style: const TextStyle(fontSize: 10, color: muted)),
                  const SizedBox(width: 2),
                  playButton,
                ]);
              }
              return Row(children: [
                Text(time(position), style: const TextStyle(fontSize: 11, color: Color(0xFFD7D7E3))),
                const SizedBox(width: 8),
                Expanded(child: seekSlider),
                const SizedBox(width: 8),
                Text(time(timelineDuration), style: const TextStyle(fontSize: 11, color: muted)),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Скорость предпросмотра',
                  visualDensity: VisualDensity.compact,
                  onPressed: videoPath == null ? null : cyclePlaybackRate,
                  icon: Text('$playbackRate×', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: accent)),
                ),
                const SizedBox(width: 4),
                playButton,
              ]);
            }),
          ),
        ]),
      );

  List<double> get previewColorMatrix {
    final s = saturation;
    final c = contrast;
    final offset = brightness * 255 + 128 * (1 - c);
    return <double>[
      (0.213 + 0.787 * s) * c, (0.715 - 0.715 * s) * c, (0.072 - 0.072 * s) * c, 0, offset,
      (0.213 - 0.213 * s) * c, (0.715 + 0.285 * s) * c, (0.072 - 0.072 * s) * c, 0, offset,
      (0.213 - 0.213 * s) * c, (0.715 - 0.715 * s) * c, (0.072 + 0.928 * s) * c, 0, offset,
      0, 0, 0, 1, 0,
    ];
  }

  Widget inspectorTabButton(String id, String label, IconData icon) => Expanded(
    child: InkWell(
      onTap: () => setState(() => inspectorTab = id),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
        decoration: BoxDecoration(color: inspectorTab == id ? const Color(0xFF303642) : Colors.transparent, borderRadius: BorderRadius.circular(6)),
        child: Column(children: [Icon(icon, size: 16, color: inspectorTab == id ? accent : muted), const SizedBox(height: 4), Text(label, style: TextStyle(fontSize: 9, color: inspectorTab == id ? Colors.white : muted, fontWeight: FontWeight.w600))],),
      ),
    ),
  );

  Widget inspectorPanel() => Container(
        color: panel,
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              inspectorTabButton('video', 'Видео', Icons.movie_outlined),
              inspectorTabButton('audio', 'Аудио', Icons.graphic_eq),
              inspectorTabButton('speed', 'Скорость', Icons.speed),
              inspectorTabButton('adjust', 'Цвет', Icons.tune),
            ]),
            const SizedBox(height: 12),
            if (inspectorTab == 'video') ...[
              const Divider(),
              const Text('ФИЛЬТРЫ', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
              Material(
                color: panel,
                child: SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Цветокоррекция', style: TextStyle(fontSize: 12)), value: filtersEnabled, onChanged: (value) => setState(() => filtersEnabled = value)),
              ),
              const SizedBox(height: 6),
              const Text('ЭФФЕКТ ВИДЕО', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: videoEffect,
                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9)),
                items: const ['Оригинал', 'Чёрно-белый', 'Сепия', 'Холодный', 'Тёплый', 'Негатив', 'Мягкое размытие'].map((v) => DropdownMenuItem(value: v, child: Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)))).toList(),
                onChanged: (value) => setState(() { videoEffect = value ?? 'Оригинал'; projectDirty = true; }),
              ),
              const SizedBox(height: 8),
              Material(
                color: panel,
                child: SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Размытие движения', style: TextStyle(fontSize: 12)), subtitle: const Text('Предпросмотр и экспорт', style: TextStyle(fontSize: 9, color: muted)), value: motionBlurEnabled, onChanged: (value) => setState(() { motionBlurEnabled = value; projectDirty = true; })),
              ),
              const Divider(),
              const Text('СООТНОШЕНИЕ СТОРОН', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.0, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: aspectRatioPreset,
                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9)),
                items: const ['16:9', '9:16', '1:1', '4:3', '4:5', '3:2'].map((v) => DropdownMenuItem(value: v, child: Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)))).toList(),
                onChanged: (value) => setState(() { aspectRatioPreset = value ?? '16:9'; projectDirty = true; }),
              ),
              const SizedBox(height: 10),
              const Text('ПЕРЕХОД МЕЖДУ КЛИПАМИ', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.0, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: transitionEffect,
                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9)),
                items: const ['Нет', 'Затемнение', 'Белая вспышка'].map((v) => DropdownMenuItem(value: v, child: Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)))).toList(),
                onChanged: (value) => setState(() { transitionEffect = value ?? 'Нет'; projectDirty = true; }),
              ),
              if (transitionEffect != 'Нет')
                _adjustmentSlider('Длительность перехода', transitionDuration, 0.2, 1.0, (value) => setState(() { transitionDuration = value; projectDirty = true; })),
              const SizedBox(height: 8),
              Row(children: [
                const Expanded(child: Text('ФОТО ПОВЕРХ ВИДЕО', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.0, fontWeight: FontWeight.w800))),
                IconButton(tooltip: 'Добавить фото', visualDensity: VisualDensity.compact, onPressed: busy || videoPath == null ? null : importPhotoOverlay, icon: const Icon(Icons.add_photo_alternate_outlined, size: 18)),
              ]),
              for (var i = 0; i < photoOverlays.length; i++)
                ListTile(
                  dense: true, contentPadding: EdgeInsets.zero, selected: selectedPhotoOverlay == i,
                  leading: const Icon(Icons.image_outlined, size: 18, color: accent),
                  title: Text(p.basename(photoOverlays[i].path), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
                  trailing: IconButton(tooltip: 'Удалить фото', visualDensity: VisualDensity.compact, onPressed: () => setState(() {
                    photoOverlays.removeAt(i);
                    if (selectedPhotoOverlay >= photoOverlays.length) selectedPhotoOverlay = photoOverlays.length - 1;
                    projectDirty = true;
                  }), icon: const Icon(Icons.delete_outline, size: 16)),
                  onTap: () => setState(() => selectedPhotoOverlay = i),
                ),
              if (selectedPhotoOverlay >= 0 && selectedPhotoOverlay < photoOverlays.length) ...[
                _adjustmentSlider('Размер фото', photoOverlays[selectedPhotoOverlay].scale, 0.2, 3, (v) => setState(() { photoOverlays[selectedPhotoOverlay].scale = v; projectDirty = true; })),
                _adjustmentSlider('Поворот фото', photoOverlays[selectedPhotoOverlay].rotation, -180, 180, (v) => setState(() { photoOverlays[selectedPhotoOverlay].rotation = v; projectDirty = true; })),
                _adjustmentSlider('Прозрачность фото', photoOverlays[selectedPhotoOverlay].opacity, 0.05, 1, (v) => setState(() { photoOverlays[selectedPhotoOverlay].opacity = v; projectDirty = true; })),
              ],
              const Divider(),
              const Text('ПОЛОЖЕНИЕ И РАЗМЕР', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.0, fontWeight: FontWeight.w800)),
              _adjustmentSlider('Масштаб предпросмотра', previewZoom, 0.5, 2.0, (value) => setState(() => previewZoom = value)),
              const Text('Масштаб меняет только просмотр; исходный кадр не обрезается.', style: TextStyle(color: muted, fontSize: 10, height: 1.4)),
              const SizedBox(height: 12),
              const Text('ТЕКУЩИЙ ПРОЕКТ', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              property('Видео', videoPath == null ? 'Не выбрано' : 'Загружено'),
              property('Длительность', time(duration)),
              property('Клипы на дорожке', '${videoClips.length}'),
            ] else if (inspectorTab == 'audio') ...[
              const Text('ГРОМКОСТЬ', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
              _adjustmentSlider('Уровень', exportVolume, 0, 2, (value) => setState(() => exportVolume = value)),
              Text('${(exportVolume * 100).round()}% · применяется при экспорте', style: const TextStyle(color: muted, fontSize: 10)),
              const Divider(),
              property('Аудиодорожка', audioPath == null ? 'Не создана' : p.basename(audioPath!)),
              if (audioPath != null) property('Длительность', time(audioDuration)),
              const SizedBox(height: 8),
              FilledButton.icon(onPressed: videoPath == null || busy ? null : extractAudio, icon: const Icon(Icons.graphic_eq, size: 16), label: const Text('Извлечь звук')),
            ] else if (inspectorTab == 'speed') ...[
              const Text('СКОРОСТЬ ПРЕДПРОСМОТРА', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.0, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),              Center(child: Text('${playbackRate.toStringAsFixed(playbackRate == playbackRate.roundToDouble() ? 0 : 2)}×', style: const TextStyle(fontSize: 26, color: accent, fontWeight: FontWeight.w800))),
              Slider(min: 0.5, max: 2, divisions: 6, value: playbackRate, onChanged: videoPath == null ? null : (value) async { setState(() => playbackRate = value); await player?.setRate(value); }),
              const Text('Изменяет скорость воспроизведения в окне просмотра.', style: TextStyle(color: muted, fontSize: 10, height: 1.4)),
            ] else ...[
              const Text('КОРРЕКЦИЯ ИЗОБРАЖЕНИЯ', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.0, fontWeight: FontWeight.w800)),
              _adjustmentSlider('Яркость', brightness, -0.5, 0.5, (v) => setState(() { brightness = v; projectDirty = true; })),
              _adjustmentSlider('Контраст', contrast, 0.5, 2.0, (v) => setState(() { contrast = v; projectDirty = true; })),
              _adjustmentSlider('Насыщенность', saturation, 0.0, 2.0, (v) => setState(() { saturation = v; projectDirty = true; })),
              Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => setState(() { brightness = 0; contrast = 1; saturation = 1; filtersEnabled = true; projectDirty = true; }), icon: const Icon(Icons.restart_alt, size: 16), label: const Text('Сбросить'))),
              const Text('Изменения сразу видны в предпросмотре и применяются при экспорте.', style: TextStyle(color: muted, fontSize: 10, height: 1.4)),
            ],

          ]),
        ),
      );

  Widget property(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(label, style: const TextStyle(color: muted, fontSize: 11))),
          const SizedBox(width: 8),
          Flexible(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
        ]),
      );

  Widget timelinePanel() => Container(
        height: _timelinePanelHeight,
        color: const Color(0xFF12151B),
        child: Column(children: [
          Container(
            height: 43,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(color: Color(0xFF191A22), border: Border(bottom: BorderSide(color: Color(0xFF292B36)))),
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: math.max(720.0, constraints.maxWidth),
                  child: Row(children: [
                    const Icon(Icons.view_timeline_outlined, size: 17, color: accent),
                    const SizedBox(width: 8),
                    const Text('ТАЙМЛАЙН', style: TextStyle(fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFF292A36), borderRadius: BorderRadius.circular(5)),
                      child: const Text('V1', style: TextStyle(fontSize: 9, color: Color(0xFFB8B6D4), fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      key: const ValueKey('timeline-snap'),
                      tooltip: snappingEnabled ? 'Привязка включена' : 'Привязка выключена',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() {
                        snappingEnabled = !snappingEnabled;
                        _timelineSnapAt = null;
                      }),
                      icon: Icon(snappingEnabled ? Icons.push_pin : Icons.push_pin_outlined,
                        size: 17, color: snappingEnabled ? accent : muted),
                    ),
                    IconButton(
                      key: const ValueKey('timeline-undo'),
                      tooltip: 'Отменить (Ctrl+Z)',
                      visualDensity: VisualDensity.compact,
                      onPressed: _timelineHistory.canUndo ? undoTimelineEdit : null,
                      icon: const Icon(Icons.undo_rounded, size: 17),
                    ),
                    IconButton(
                      key: const ValueKey('timeline-redo'),
                      tooltip: 'Повторить (Ctrl+Y)',
                      visualDensity: VisualDensity.compact,
                      onPressed: _timelineHistory.canRedo ? redoTimelineEdit : null,
                      icon: const Icon(Icons.redo_rounded, size: 17),
                    ),
                    IconButton(
                      tooltip: 'Разделить клип (Ctrl+B)',
                      visualDensity: VisualDensity.compact,
                      onPressed: videoClips.isEmpty ? null : splitSelectedClip,
                      icon: const Icon(Icons.content_cut_rounded, size: 17),
                    ),
                    IconButton(
                      tooltip: 'Удалить выбранный клип',
                      visualDensity: VisualDensity.compact,
                      onPressed: videoClips.isEmpty ? null : deleteSelectedClip,
                      icon: const Icon(Icons.delete_outline_rounded, size: 17),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Уменьшить масштаб',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setTimelineZoom(zoom - 4),
                      icon: const Icon(Icons.remove, size: 17),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text('${zoom.toInt()} px/s', textAlign: TextAlign.center, style: const TextStyle(color: muted, fontSize: 10)),
                    ),
                    IconButton(
                      tooltip: 'Увеличить масштаб',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setTimelineZoom(zoom + 4),
                      icon: const Icon(Icons.add, size: 17),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          Expanded(
            child: Listener(
              onPointerSignal: (event) {
                if (event is! PointerScrollEvent || !timelineScrollController.hasClients) return;
                final controller = timelineScrollController;
                if (HardwareKeyboard.instance.isControlPressed) {
                  final pointerX = event.localPosition.dx;
                  final anchorSeconds = ((controller.offset + pointerX - 140) / zoom)
                      .clamp(0.0, timelineSeconds).toDouble();
                  setTimelineZoom(event.scrollDelta.dy < 0 ? zoom + 4 : zoom - 4);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!controller.hasClients) return;
                    final nextOffset = anchorSeconds * zoom + 140 - pointerX;
                    controller.jumpTo(nextOffset.clamp(0.0, controller.position.maxScrollExtent).toDouble());
                  });
                } else {
                  final delta = event.scrollDelta.dx != 0 ? event.scrollDelta.dx : event.scrollDelta.dy;
                  controller.jumpTo((controller.offset + delta)
                      .clamp(0.0, controller.position.maxScrollExtent).toDouble());
                }
              },
              child: SingleChildScrollView(
              controller: timelineScrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 140 + timelineWidth,
                child: Column(children: [
                  SizedBox(
                    height: 32,
                    child: Row(children: [
                      Container(width: 140, padding: const EdgeInsets.only(left: 14), alignment: Alignment.centerLeft, color: const Color(0xFF171820), child: const Text('ВРЕМЯ', style: TextStyle(color: muted, fontSize: 9, letterSpacing: 1.1, fontWeight: FontWeight.w800))),
                      SizedBox(width: timelineWidth, child: CustomPaint(painter: RulerPainter(seconds: timelineSeconds, pixelsPerSecond: zoom), child: const SizedBox.expand())),
                    ]),
                  ),
                  trackRow(audio: false),
                  const SizedBox(height: 5),
                  trackRow(audio: true),
                  if (photoOverlays.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    photoTrackRow(),
                  ],
                ]),
              ),
              ),
            ),
          ),
        ]),
      );

  Widget photoTrackRow() => SizedBox(
        width: 140 + timelineWidth,
        height: 54,
        child: Row(children: [
          Container(
            width: 140, height: 54, padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(color: Color(0xFF191A22), border: Border(bottom: BorderSide(color: Color(0xFF292B36)))),
            child: const Row(children: [
              Icon(Icons.image_outlined, size: 17, color: Color(0xFFB18CFF)),
              SizedBox(width: 8),
              Expanded(child: Text('Фото / оверлеи', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700))),
            ]),
          ),
          SizedBox(
            width: timelineWidth, height: 54,
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: TimelineGridPainter(seconds: timelineSeconds, pixelsPerSecond: zoom))),
              for (var i = 0; i < photoOverlays.length; i++)
                Positioned(
                  left: 4, top: 5 + i * 2.0, bottom: 5,
                  width: math.max(20.0, timelineWidth - 8).toDouble(),
                  child: GestureDetector(
                    onTapDown: (d) => seekTimeline(d.localPosition.dx),
                    onTap: () => setState(() => selectedPhotoOverlay = i),
                    child: Container(
                      decoration: BoxDecoration(color: const Color(0x443D2C69), borderRadius: BorderRadius.circular(5), border: Border.all(color: selectedPhotoOverlay == i ? Colors.white : const Color(0xFFB18CFF), width: selectedPhotoOverlay == i ? 2 : 1)),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(children: [
                        const Icon(Icons.image_outlined, size: 13, color: Colors.white),
                        const SizedBox(width: 6),
                        Flexible(child: Text(p.basename(photoOverlays[i].path), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: Colors.white))),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
      );

  Widget trackRow({required bool audio}) {
    final path = audio ? audioPath : videoPath;
    final color = audio ? audioGreen : videoBlue;
    final playhead = (position.inMilliseconds / 1000 * zoom).clamp(0.0, timelineWidth - 2).toDouble();

    return SizedBox(
      width: 140 + timelineWidth,
      height: 63,
      child: Row(children: [
        Container(
          width: 140,
          height: 63,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(color: Color(0xFF191A22), border: Border(bottom: BorderSide(color: Color(0xFF292B36)))),
          child: Row(children: [
            Icon(audio ? Icons.graphic_eq : Icons.movie_outlined, size: 17, color: color),
            const SizedBox(width: 8),
            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(audio ? 'Аудио 1' : 'Видео 1', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(audio ? 'Звуковая дорожка' : 'Видеодорожка', style: const TextStyle(fontSize: 9, color: muted)),
            ])),
          ]),
        ),
        SizedBox(
          width: timelineWidth,
          height: 63,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: duration.inMilliseconds > 0 ? (d) => seekTimeline(d.localPosition.dx) : null,
            onHorizontalDragStart: duration.inMilliseconds > 0 ? (d) => seekTimeline(d.localPosition.dx) : null,
            onHorizontalDragUpdate: duration.inMilliseconds > 0 ? (d) => seekTimeline(d.localPosition.dx) : null,
            child: Stack(clipBehavior: Clip.hardEdge, children: [
              Positioned.fill(child: CustomPaint(painter: TimelineGridPainter(seconds: timelineSeconds, pixelsPerSecond: zoom))),
              if (path != null && audio && audioClipEnd > audioClipStart)
                Positioned(
                  left: audioClipStart * zoom + 4,
                  top: 7,
                  bottom: 7,
                  width: math.max(12.0, (audioClipEnd - audioClipStart) * zoom - 2).toDouble(),
                  child: GestureDetector(
                    onSecondaryTapDown: (details) => showAudioClipMenu(details.globalPosition),
                    child: DecoratedBox(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: audioGreen, width: 1.5)),
                      child: audioClip(path),
                    ),
                  ),
                ),
              if (path != null && !audio)
                for (var i = 0; i < videoClips.length; i++)
                  Positioned(
                    left: videoClips[i].timelineStart * zoom + 4,
                    top: 7,
                    bottom: 7,
                    width: math.max(12.0, videoClips[i].length * zoom - 2).toDouble(),
                    child: GestureDetector(
                      onTapDown: (d) => seekTimeline(videoClips[i].timelineStart * zoom + d.localPosition.dx),
                      onTap: () => setState(() { selectedClipIndex = i; projectDirty = true; }),
                      onSecondaryTapDown: (details) => showClipMenu(details.globalPosition, i),
                      onHorizontalDragStart: (_) => _startClipMove(i),
                      onHorizontalDragUpdate: _updateClipMove,
                      onHorizontalDragEnd: (_) => _finishClipMove(),
                      child: Stack(
                        fit: StackFit.expand,
                        clipBehavior: Clip.hardEdge,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: selectedClipIndex == i ? const Color(0xFFFFFFFF) : videoBlue, width: selectedClipIndex == i ? 2 : 1),
                              boxShadow: selectedClipIndex == i ? [BoxShadow(color: videoBlue.withValues(alpha: .2), blurRadius: 8)] : null,
                            ),
                            child: ClipRRect(borderRadius: BorderRadius.circular(5), child: Stack(children: [
                              Positioned.fill(child: _videoThumbnailStrip(videoClips[i], math.max(12.0, videoClips[i].length * zoom - 2).toDouble())),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                color: const Color(0x552D76B8),
                                alignment: Alignment.centerLeft,
                                child: Row(children: [
                                  const Icon(Icons.movie_outlined, size: 14, color: Colors.white),
                                  const SizedBox(width: 6),
                                  Flexible(child: Text(p.basename(path), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700))),
                                  if (videoClips[i].length * zoom > 110) ...[
                                    const Spacer(),
                                    Text('${videoClips[i].length.toStringAsFixed(1)}с', style: const TextStyle(fontSize: 9, color: Colors.white70)),
                                  ],
                                ]),
                              ),
                            ])),
                          ),
                          if (selectedClipIndex == i) ...[
                            Positioned(
                              left: 0, top: 0, bottom: 0, width: 9,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.resizeLeftRight,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onHorizontalDragStart: (_) => _startEdgeDrag(i, true),
                                  onHorizontalDragUpdate: _updateEdgeDrag,
                                  onHorizontalDragEnd: (_) => _finishEdgeDrag(),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFF1EDFF),
                                      borderRadius: BorderRadius.horizontal(left: Radius.circular(5)),
                                    ),
                                    child: const Center(child: SizedBox(width: 2, height: 16, child: ColoredBox(color: Color(0xFF6551D9)))),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 0, top: 0, bottom: 0, width: 9,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.resizeLeftRight,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,                                  onHorizontalDragStart: (_) => _startEdgeDrag(i, false),
                                  onHorizontalDragUpdate: _updateEdgeDrag,
                                  onHorizontalDragEnd: (_) => _finishEdgeDrag(),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFF1EDFF),
                                      borderRadius: BorderRadius.horizontal(right: Radius.circular(5)),
                                    ),
                                    child: const Center(child: SizedBox(width: 2, height: 16, child: ColoredBox(color: Color(0xFF6551D9)))),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              if (_timelineSnapAt != null)
                Positioned(left: _timelineSnapAt! * zoom, top: 0, bottom: 0, width: 1,
                  child: const ColoredBox(color: Color(0xFFB18CFF))),
              Positioned(left: playhead, top: 0, bottom: 0, width: 2, child: Container(color: Colors.white)),
              Positioned(left: (playhead - 4).clamp(0.0, timelineWidth - 10).toDouble(), top: 0, width: 10, height: 8, child: const DecoratedBox(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.only(bottomLeft: Radius.circular(3), bottomRight: Radius.circular(3))))),
            ]),
          ),
        ),
      ]),
    );
  }

  TimelineSnapshot _captureTimelineSnapshot() => TimelineSnapshot(
        videoClips: videoClips
            .map((clip) => TimelineClipRange(
                  clip.start,
                  clip.end,
                  timelineStart: clip.timelineStart,
                ))
            .toList(),
        selectedClipIndex: selectedClipIndex,
        audioPath: audioPath,
        audioClipStart: audioClipStart,
        audioClipEnd: audioClipEnd,
      );

  void _restoreTimelineSnapshot(TimelineSnapshot snapshot) {
    videoClips
      ..clear()
      ..addAll(snapshot.videoClips.map((clip) => TimelineClip(
            start: clip.start,
            end: clip.end,
            timelineStart: clip.timelineStart,
          )));
    videoClips.sort((a, b) => a.timelineStart.compareTo(b.timelineStart));
    _activePlaybackClipIndex = snapshot.selectedClipIndex;
    selectedClipIndex = videoClips.isEmpty
        ? 0
        : snapshot.selectedClipIndex.clamp(0, videoClips.length - 1).toInt();
    audioPath = snapshot.audioPath;
    audioClipStart = snapshot.audioClipStart;
    audioClipEnd = snapshot.audioClipEnd;
  }

  void _performTimelineEdit(VoidCallback update) {
    final before = _captureTimelineSnapshot();
    setState(() {
      update();
      projectDirty = true;
    });
    _timelineHistory.record(before: before, after: _captureTimelineSnapshot());
  }

  void undoTimelineEdit() {
    final previous = _timelineHistory.undo(_captureTimelineSnapshot());
    if (previous == null) return;
    setState(() {
      _restoreTimelineSnapshot(previous);
      projectDirty = true;
      status = 'Действие отменено.';
    });
  }

  void redoTimelineEdit() {
    final next = _timelineHistory.redo(_captureTimelineSnapshot());
    if (next == null) return;
    setState(() {
      _restoreTimelineSnapshot(next);
      projectDirty = true;
      status = 'Действие повторено.';
    });
  }

  Future<void> showAudioClipMenu(Offset position) async {
    if (audioPath == null || audioClipEnd <= audioClipStart) return;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: const [
        PopupMenuItem(value: 'audioTrimStart', child: ListTile(dense: true, leading: Icon(Icons.first_page), title: Text('Обрезать начало звука до курсора'))),
        PopupMenuItem(value: 'audioTrimEnd', child: ListTile(dense: true, leading: Icon(Icons.last_page), title: Text('Обрезать конец звука по курсору'))),
        PopupMenuItem(value: 'audioReset', child: ListTile(dense: true, leading: Icon(Icons.restart_alt), title: Text('Сбросить обрезку звука'))),
        PopupMenuItem(value: 'audioDelete', child: ListTile(dense: true, leading: Icon(Icons.delete_outline, color: Colors.redAccent), title: Text('Удалить звуковой клип'))),
      ],
    );
    if (!mounted || action == null) return;
    final cut = playheadSeconds;
    _performTimelineEdit(() {
      switch (action) {
        case 'audioTrimStart':
          if (cut > audioClipStart && cut < audioClipEnd - .08) { audioClipStart = cut; status = 'Начало звука обрезано независимо от видео.'; }
          else { status = 'Курсор должен находиться внутри звукового клипа.'; }
          break;
        case 'audioTrimEnd':
          if (cut > audioClipStart + .08 && cut < audioClipEnd) { audioClipEnd = cut; status = 'Конец звука обрезан независимо от видео.'; }
          else { status = 'Курсор должен находиться внутри звукового клипа.'; }
          break;
        case 'audioReset':
          audioClipStart = 0;
          audioClipEnd = audioDuration.inMilliseconds / 1000;
          status = 'Обрезка звука сброшена.';
          break;
        case 'audioDelete':
          audioPath = null;
          audioWaveform = const [];
          audioClipStart = 0;
          audioClipEnd = 0;
          status = 'Звуковой клип удалён. Видеоклипы не изменены.';
          break;
      }
    });
  }

  Future<void> showClipMenu(Offset position, int index) async {
    if (index < 0 || index >= videoClips.length) return;
    setState(() { selectedClipIndex = index; projectDirty = true; });
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: const [
        PopupMenuItem(value: 'split', child: ListTile(dense: true, leading: Icon(Icons.content_cut), title: Text('Разделить по курсору'), subtitle: Text('Ctrl+B'))),
        PopupMenuItem(value: 'trimStart', child: ListTile(dense: true, leading: Icon(Icons.first_page), title: Text('Обрезать начало до курсора'))),
        PopupMenuItem(value: 'trimEnd', child: ListTile(dense: true, leading: Icon(Icons.last_page), title: Text('Обрезать конец по курсору'))),
        PopupMenuDivider(),
        PopupMenuItem(value: 'duplicate', child: ListTile(dense: true, leading: Icon(Icons.copy_outlined), title: Text('Дублировать клип'), subtitle: Text('Ctrl+D'))),
        PopupMenuItem(value: 'delete', child: ListTile(dense: true, leading: Icon(Icons.delete_outline), title: Text('Удалить, оставить разрыв'), subtitle: Text('Delete'))),
        PopupMenuItem(value: 'rippleDelete', child: ListTile(dense: true, leading: Icon(Icons.auto_delete_outlined, color: Colors.redAccent), title: Text('Удалить со сдвигом'), subtitle: Text('Shift+Delete'))),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'split': splitSelectedClip(); break;
      case 'trimStart': trimSelectedStart(); break;
      case 'trimEnd': trimSelectedEnd(); break;
      case 'duplicate': duplicateSelectedClip(); break;
      case 'delete': deleteSelectedClip(); break;
      case 'rippleDelete': deleteSelectedClip(ripple: true); break;
    }
  }

  double get playheadSeconds =>
      (position.inMilliseconds / 1000).clamp(0.0, timelineSeconds).toDouble();

  void splitSelectedClip() {
    try {
      final next = TimelineEditing.splitAt(_clipRanges(), selectedClipIndex, playheadSeconds);
      _performTimelineEdit(() {
        _replaceClipRanges(next);
        selectedClipIndex++;
        _activePlaybackClipIndex = selectedClipIndex;
        status = 'Клип разделён в ${time(position)}.';
      });
    } on ArgumentError catch (error) {
      setStatus(error.message?.toString() ?? 'Невозможно разделить клип в этой позиции.');
    }
  }

  void trimSelectedStart() {
    try {
      final next = TimelineEditing.trimStartRipple(_clipRanges(), selectedClipIndex, playheadSeconds);
      _performTimelineEdit(() {
        _replaceClipRanges(next);
        status = 'Начало клипа обрезано с риппл-сдвигом.';
      });
    } on ArgumentError catch (error) {
      setStatus(error.message?.toString() ?? 'Невозможно обрезать начало клипа.');
    }
  }

  void trimSelectedEnd() {
    try {
      final next = TimelineEditing.trimEndRipple(_clipRanges(), selectedClipIndex, playheadSeconds);
      _performTimelineEdit(() {
        _replaceClipRanges(next);
        status = 'Конец клипа обрезан с риппл-сдвигом.';
      });
    } on ArgumentError catch (error) {
      setStatus(error.message?.toString() ?? 'Невозможно обрезать конец клипа.');
    }
  }

  void duplicateSelectedClip() {
    if (selectedClipIndex < 0 || selectedClipIndex >= videoClips.length) return;
    final selected = videoClips[selectedClipIndex];
    final insertionTime = selected.timelineEnd;
    final next = TimelineEditing.duplicateAfter(_clipRanges(), selectedClipIndex);
    _performTimelineEdit(() {
      _replaceClipRanges(next);
      selectedClipIndex = videoClips.indexWhere((clip) =>
          clip.start == selected.start &&
          clip.end == selected.end &&
          (clip.timelineStart - insertionTime).abs() < 0.001);
      if (selectedClipIndex < 0) selectedClipIndex = 0;
      _activePlaybackClipIndex = selectedClipIndex;
      status = 'Копия вставлена после выбранного клипа.';
    });
  }

  void deleteSelectedClip({bool ripple = false}) {
    if (videoClips.isEmpty || selectedClipIndex < 0 || selectedClipIndex >= videoClips.length) return;
    final next = ripple
        ? TimelineEditing.rippleDelete(_clipRanges(), selectedClipIndex)
        : TimelineEditing.deleteLeaveGap(_clipRanges(), selectedClipIndex);
    _performTimelineEdit(() {
      _replaceClipRanges(next);
      selectedClipIndex = videoClips.isEmpty
          ? 0
          : selectedClipIndex.clamp(0, videoClips.length - 1).toInt();
      _activePlaybackClipIndex = -1;
      _playheadInGap = false;
      status = ripple
          ? 'Клип удалён, последующие клипы сдвинуты.'
          : 'Клип удалён. На таймлайне оставлен разрыв.';
    });
  }

  void _startClipMove(int index) {
    if (index < 0 || index >= videoClips.length) return;
    _clipMoveBefore = _captureTimelineSnapshot();
    _clipMoveIndex = index;
    _clipMoveOriginalStart = videoClips[index].timelineStart;
    _clipMovePointerX = 0;
    setState(() {
      selectedClipIndex = index;
      _timelineSnapAt = null;
    });
  }

  void _updateClipMove(DragUpdateDetails details) {
    if (_clipMoveIndex < 0 || _clipMoveIndex >= videoClips.length) return;
    _clipMovePointerX += details.delta.dx;
    var candidate = math.max(0.0, _clipMoveOriginalStart + _clipMovePointerX / zoom).toDouble();
    double? snapTo;
    if (snappingEnabled) {
      final threshold = 7 / zoom;
      final points = <double>[0, playheadSeconds];
      for (var i = 0; i < videoClips.length; i++) {
        if (i == _clipMoveIndex) continue;
        points
          ..add(videoClips[i].timelineStart)
          ..add(videoClips[i].timelineEnd);
      }
      for (final point in points) {
        if ((point - candidate).abs() <= threshold &&
            (snapTo == null || (point - candidate).abs() < (snapTo - candidate).abs())) {
          snapTo = point;
        }
      }
      if (snapTo != null) candidate = snapTo;
    }
    setState(() {
      videoClips[_clipMoveIndex].timelineStart = candidate;
      _timelineSnapAt = snapTo;
    });
  }

  void _finishClipMove() {
    final before = _clipMoveBefore;
    final index = _clipMoveIndex;
    if (before == null || index < 0 || index >= before.videoClips.length) return;
    final requestedStart = videoClips[index].timelineStart;
    final moving = before.videoClips[index];
    final next = TimelineEditing.moveInsert(before.videoClips, index, requestedStart);
    var selected = next.indexWhere((clip) =>
        clip.start == moving.start &&
        clip.end == moving.end &&
        (clip.timelineStart - requestedStart).abs() < 0.001);
    if (selected < 0) selected = 0;
    final after = TimelineSnapshot(
      videoClips: next,
      selectedClipIndex: selected,
      audioPath: before.audioPath,
      audioClipStart: before.audioClipStart,
      audioClipEnd: before.audioClipEnd,
    );
    setState(() {
      _replaceClipRanges(next);
      selectedClipIndex = selected;
      _activePlaybackClipIndex = selected;
      _timelineSnapAt = null;
      projectDirty = true;
      status = 'Клип перемещён. Ctrl+Z — отменить.';
    });
    _timelineHistory.record(before: before, after: after);
    _clipMoveBefore = null;
    _clipMoveIndex = -1;
    // Re-evaluate the playhead against the new clip positions immediately:
    // moving a clip away can leave the playhead in a black gap.
    unawaited(seek(position));
  }

  Future<void> showColorAdjustments() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Коррекция изображения'),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _adjustmentSlider('Яркость', brightness, -0.5, 0.5, (v) { setDialogState(() => brightness = v); setState(() {}); }),
              _adjustmentSlider('Контраст', contrast, 0.5, 2.0, (v) { setDialogState(() => contrast = v); setState(() {}); }),
              _adjustmentSlider('Насыщенность', saturation, 0.0, 2.0, (v) { setDialogState(() => saturation = v); setState(() {}); }),
              Align(alignment: Alignment.centerRight, child: TextButton.icon(
                onPressed: () { setDialogState(() { brightness = 0; contrast = 1; saturation = 1; }); setState(() {}); },
                icon: const Icon(Icons.restart_alt), label: const Text('Сбросить'),
              )),
              const Text('Параметры применяются при экспорте видео.', style: TextStyle(color: muted, fontSize: 12)),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Готово'))],
        ),
      ),
    );
  }

  Widget _adjustmentSlider(String label, double value, double min, double max, ValueChanged<double> onChanged) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(label)), Text(value.toStringAsFixed(2), style: const TextStyle(color: muted, fontSize: 12))]),
      Slider(min: min, max: max, value: value, onChanged: onChanged),
    ]),
  );

  String _buildExportVideoFilter(int index, TimelineClip clip) {
    final filters = <String>[];
    {
      final dimensions = const {
        '16:9': '1920:1080',
        '9:16': '1080:1920',
        '1:1': '1080:1080',
        '4:3': '1440:1080',
        '4:5': '864:1080',
        '3:2': '1620:1080',
      }[aspectRatioPreset];
      if (dimensions != null) {
        final parts = dimensions.split(':');
        filters.add('scale=${parts[0]}:${parts[1]}:force_original_aspect_ratio=increase');
        filters.add('crop=${parts[0]}:${parts[1]}');
      }
    }
    if (videoScaleX != 1.0 || videoScaleY != 1.0) filters.add('scale=iw*${videoScaleX.toStringAsFixed(3)}:ih*${videoScaleY.toStringAsFixed(3)}');
    if (videoRotation.abs() > 0.01) filters.add('rotate=${(videoRotation * math.pi / 180).toStringAsFixed(5)}:c=black');
    if (filtersEnabled) {
      filters.add('eq=brightness=${brightness.toStringAsFixed(3)}:contrast=${contrast.toStringAsFixed(3)}:saturation=${saturation.toStringAsFixed(3)}');
    }
    if (videoEffect != 'Оригинал' && _exportEffectFilter != 'null') filters.add(_exportEffectFilter);    if (motionBlurEnabled) filters.add('tmix=frames=3:weights=1 1 1');
    if (transitionEffect != 'Нет' && videoClips.length > 1) {
      final durationForClip = math.min(transitionDuration, math.max(0.1, clip.length / 2)).toDouble();
      final color = transitionEffect == 'Белая вспышка' ? 'white' : 'black';
      if (index > 0) filters.add('fade=t=in:st=0:d=${durationForClip.toStringAsFixed(2)}:color=$color');
      if (index < videoClips.length - 1) {
        final start = math.max(0, clip.length - durationForClip).toDouble();
        filters.add('fade=t=out:st=${start.toStringAsFixed(2)}:d=${durationForClip.toStringAsFixed(2)}:color=$color');
      }
    }
    return filters.isEmpty ? 'null' : filters.join(',');
  }

  Future<String> _detectH264Encoder(String ffmpeg) async {
    try {
      final result = await Process.run(ffmpeg, ['-hide_banner', '-encoders']);
      if (result.exitCode == 0) {
        final output = '${result.stdout}\\n${result.stderr}';
        for (final encoder in ['h264_nvenc', 'h264_qsv', 'h264_amf']) {
          if (output.contains(encoder)) return encoder;
        }
      }
    } catch (_) {
      // Capability probing must never prevent a software export.
    }
    return 'libx264';
  }

  List<String> _videoEncoderArguments(String encoder) {
    switch (encoder) {
      case 'h264_nvenc':
        return ['-c:v', encoder, '-preset', 'p4', '-cq', '18', '-b:v', '0'];
      case 'h264_qsv':
        return ['-c:v', encoder, '-preset', 'medium', '-global_quality', '18'];
      case 'h264_amf':
        return ['-c:v', encoder, '-quality', 'quality', '-qp_i', '18', '-qp_p', '18'];
      default:
        return ['-c:v', 'libx264', '-preset', 'veryfast', '-crf', '18'];
    }
  }

  Future<void> exportEditedVideo() async {
    final source = videoPath;
    if (source == null || videoClips.isEmpty || busy) return;

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Экспортировать смонтированное видео',
      fileName: 'GifCut-export.mp4',
      type: FileType.video,
      allowedExtensions: ['mp4'],
    );
    if (savePath == null) return;

    setState(() {
      busy = true;
      status = 'Подготавливаю экспорт…';
    });

    Directory? temp;
    try {
      temp = await Directory.systemTemp.createTemp('gifcut-export-');
      final listFile = File(p.join(temp.path, 'concat.txt'));
      final lines = <String>[];
      final orderedClips = List<TimelineClip>.of(videoClips)
        ..sort((a, b) => a.timelineStart.compareTo(b.timelineStart));

      final ffmpeg = await findFfmpeg();
      final sourceProbe = await Process.run(ffmpeg, ['-hide_banner', '-i', source]);
      final sourceHasAudio =
          '${sourceProbe.stdout}\\n${sourceProbe.stderr}'.contains('Audio:');
      final encoder = await _detectH264Encoder(ffmpeg);

      final outputSize = const {
        '16:9': '1920:1080',
        '9:16': '1080:1920',
        '1:1': '1080:1080',
        '4:3': '1440:1080',
        '4:5': '864:1080',
        '3:2': '1620:1080',
      }[aspectRatioPreset] ?? '1920:1080';

      var sequenceCursor = 0.0;
      var segmentNumber = 0;

      Future<void> appendGapSegment(double gapSeconds) async {
        if (gapSeconds < 0.015) return;
        final dimensions = outputSize.split(':');
        final gapPath = p.join(
          temp!.path,
          'segment_${segmentNumber.toString().padLeft(3, '0')}_gap.mp4',
        );
        segmentNumber++;

        final colorSource =
            'color=c=black:s=${dimensions[0]}x${dimensions[1]}:r=${frameRate.toStringAsFixed(3)}:d=${gapSeconds.toStringAsFixed(3)}';
        final baseArgs = <String>[
          '-hide_banner',
          '-y',
          '-f',
          'lavfi',
          '-i',
          colorSource,
          if (sourceHasAudio) ...[
            '-f',
            'lavfi',
            '-i',
            'anullsrc=channel_layout=stereo:sample_rate=44100',
          ],
          '-t',
          gapSeconds.toStringAsFixed(3),
          '-r',
          frameRate.toStringAsFixed(3),
        ];
        final audioArgs = <String>[
          if (sourceHasAudio) ...[
            '-c:a',
            'aac',
            '-b:a',
            '192k',
            '-ac',
            '2',
            '-ar',
            '44100',
            '-shortest',
          ],
          '-movflags',
          '+faststart',
          gapPath,
        ];

        var result = await Process.run(ffmpeg, [
          ...baseArgs,
          ..._videoEncoderArguments(encoder),
          ...audioArgs,
        ]);
        if (result.exitCode != 0 && encoder != 'libx264') {
          result = await Process.run(ffmpeg, [
            ...baseArgs,
            '-c:v',
            'libx264',
            '-preset',
            'veryfast',
            '-crf',
            '18',
            ...audioArgs,
          ]);
        }
        if (result.exitCode != 0 || !await File(gapPath).exists()) {
          throw Exception(
            'Не удалось создать пустой участок таймлайна: ${result.stderr}',
          );
        }
        lines.add("file '${gapPath.replaceAll('\\', '/')}'");
      }

      for (var i = 0; i < orderedClips.length; i++) {
        final clip = orderedClips[i];
        if (clip.timelineStart < sequenceCursor - 0.015) {
          throw StateError(
            'Клипы перекрываются на таймлайне. Разместите их последовательно перед экспортом.',
          );
        }
        if (clip.timelineStart > sequenceCursor + 0.015) {
          await appendGapSegment(clip.timelineStart - sequenceCursor);
        }

        final segmentPath = p.join(
          temp.path,
          'segment_${segmentNumber.toString().padLeft(3, '0')}.mp4',
        );
        segmentNumber++;

        final args = <String>[
          '-hide_banner',
          '-y',
          '-ss',
          clip.start.toStringAsFixed(3),
          '-i',
          source,
          '-t',
          clip.length.toStringAsFixed(3),
        ];
        for (final overlay in photoOverlays) {
          args.addAll(['-loop', '1', '-framerate', '30', '-i', overlay.path]);
        }

        if (photoOverlays.isEmpty) {
          args.addAll(['-vf', _buildExportVideoFilter(i, clip)]);
        } else {
          final graph = <String>[
            '[0:v]${_buildExportVideoFilter(i, clip)}[base0]',
          ];
          var previous = 'base0';
          for (var overlayIndex = 0;
              overlayIndex < photoOverlays.length;
              overlayIndex++) {
            final overlay = photoOverlays[overlayIndex];
            final inputIndex = overlayIndex + 1;
            final overlayLabel = 'ov$overlayIndex';
            final outputLabel = overlayIndex == photoOverlays.length - 1
                ? 'vout'
                : 'base${overlayIndex + 1}';
            final width = (360 * overlay.scale).round().clamp(24, 1800);
            final angle =
                (overlay.rotation * math.pi / 180).toStringAsFixed(5);
            graph.add(
              '[$inputIndex:v]scale=$width:-1,format=rgba,rotate=$angle:c=none,colorchannelmixer=aa=${overlay.opacity.toStringAsFixed(3)}[$overlayLabel]',
            );
            graph.add(
              '[$previous][$overlayLabel]overlay=x=(W-w)/2+(${overlay.x.toStringAsFixed(4)})*W:y=(H-h)/2+(${overlay.y.toStringAsFixed(4)})*H:shortest=1[$outputLabel]',
            );
            previous = outputLabel;
          }
          args.addAll([
            '-filter_complex',
            graph.join(';'),
            '-map',
            '[vout]',
            '-map',
            '0:a?',
          ]);
        }

        final commonOutputArgs = <String>[
          '-r',
          frameRate.toStringAsFixed(3),
          if (sourceHasAudio) ...[
            '-af',
            'volume=${exportVolume.toStringAsFixed(2)}',
            '-c:a',
            'aac',
            '-b:a',
            '192k',
            '-ac',
            '2',
            '-ar',
            '44100',
          ],
          '-movflags',
          '+faststart',
          segmentPath,
        ];

        var result = await Process.run(ffmpeg, [
          ...args,
          ..._videoEncoderArguments(encoder),
          ...commonOutputArgs,
        ]);
        if ((result.exitCode != 0 || !await File(segmentPath).exists()) &&
            encoder != 'libx264') {
          result = await Process.run(ffmpeg, [
            ...args,
            ..._videoEncoderArguments('libx264'),
            ...commonOutputArgs,
          ]);
        }
        if (result.exitCode != 0 || !await File(segmentPath).exists()) {
          throw Exception(
            'Не удалось обработать фрагмент ${i + 1}: ${result.stderr.toString().split('\n').last}',
          );
        }

        lines.add("file '${segmentPath.replaceAll('\\', '/')}'");
        sequenceCursor = clip.timelineEnd;
        if (mounted) {
          setState(() {
            status = 'Экспортирую фрагмент ${i + 1} из ${orderedClips.length}…';
          });
        }
      }

      await listFile.writeAsString(lines.join('\n'));
      final joinedVideo = audioPath == null
          ? savePath
          : p.join(temp.path, 'joined_video.mp4');
      final concatResult = await Process.run(ffmpeg, [
        '-hide_banner',
        '-y',
        '-f',
        'concat',
        '-safe',
        '0',
        '-i',
        listFile.path,
        '-c',
        'copy',
        '-movflags',
        '+faststart',
        joinedVideo,
      ]);
      if (concatResult.exitCode != 0) {
        throw Exception(concatResult.stderr.toString().split('\n').last);
      }

      // Detached audio replaces source audio at its own trim range.
      final detachedAudio = audioPath;
      if (detachedAudio != null && audioClipEnd > audioClipStart) {
        final audioResult = await Process.run(ffmpeg, [
          '-hide_banner',
          '-y',
          '-i',
          joinedVideo,
          '-ss',
          audioClipStart.toStringAsFixed(3),
          '-t',
          (audioClipEnd - audioClipStart).toStringAsFixed(3),
          '-i',
          detachedAudio,
          '-map',
          '0:v:0',
          '-map',
          '1:a:0',
          '-c:v',
          'copy',
          '-af',
          'volume=${exportVolume.toStringAsFixed(2)}',
          '-c:a',
          'aac',
          '-b:a',
          '192k',
          '-movflags',
          '+faststart',
          savePath,
        ]);
        if (audioResult.exitCode != 0) {
          throw Exception(audioResult.stderr.toString().split('\n').last);
        }
      }

      if (mounted) setState(() => status = 'Экспорт завершён: $savePath');
    } catch (e) {
      if (mounted) setState(() => status = 'Ошибка экспорта: $e');
    } finally {
      if (temp != null && await temp.exists()) {
        await temp.delete(recursive: true);
      }
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _videoThumbnailStrip(TimelineClip clip, double width) {
    if (videoThumbnails.isEmpty || duration.inMilliseconds <= 0) {
      return const CustomPaint(painter: VideoStripPainter(), child: SizedBox.expand());
    }
    final sourceDuration = duration.inMilliseconds / 1000;
    final tileWidth = width / math.max(1, (videoThumbnails.length * clip.length / sourceDuration).ceil());
    final first = ((clip.start / sourceDuration) * videoThumbnails.length).floor().clamp(0, videoThumbnails.length - 1).toInt();
    final last = ((clip.end / sourceDuration) * videoThumbnails.length).ceil().clamp(first + 1, videoThumbnails.length).toInt();
    final visible = videoThumbnails.sublist(first, last);
    return SizedBox(width: width, height: double.infinity, child: Row(children: [for (final path in visible) SizedBox(width: tileWidth.clamp(1.0, width).toDouble(), height: double.infinity, child: Image.file(File(path), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF234765))))]));
  }

  Widget videoClip(String path) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CustomPaint(
          painter: const VideoStripPainter(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(border: Border.all(color: videoBlue), borderRadius: BorderRadius.circular(6), color: const Color(0x442D76B8)),
            child: Row(children: [
              const Icon(Icons.movie_outlined, size: 15, color: Colors.white),
              const SizedBox(width: 7),
              Flexible(child: Text(p.basename(path), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700))),
            ]),
          ),
        ),
      );

  Widget audioClip(String path) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CustomPaint(
          painter: WaveformPainter(color: audioGreen, samples: audioWaveform),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(border: Border.all(color: audioGreen), borderRadius: BorderRadius.circular(6), color: const Color(0x66205E51)),
            child: Row(children: [
              const Icon(Icons.graphic_eq, size: 15, color: Colors.white),
              const SizedBox(width: 7),
              Flexible(child: Text(p.basename(path), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700))),
              const SizedBox(width: 8),
              const Text('WAV', style: TextStyle(fontSize: 9, color: Colors.white70, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      );

  Widget statusBar() => Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        color: panel,
        child: Row(children: [
          Icon(busy ? Icons.sync : (audioPath == null ? Icons.info_outline : Icons.check_circle_outline), size: 14, color: busy ? accent : (audioPath == null ? muted : audioGreen)),
          const SizedBox(width: 8),
          Expanded(child: Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFB9BAC8), fontSize: 10))),
          const SizedBox(width: 10),
          const Text('GifCut $appVersion · Windows', style: TextStyle(color: Color(0xFF676A7A), fontSize: 9)),
        ]),
      );
}

bool isVersionNewer(String candidate, String current) {
  List<int> parts(String version) => RegExp(r'\d+')
      .allMatches(version)
      .take(3)
      .map((match) => int.parse(match.group(0)!))
      .toList();

  final candidateParts = parts(candidate);
  final currentParts = parts(current);
  for (var i = 0; i < 3; i++) {
    final next = i < candidateParts.length ? candidateParts[i] : 0;
    final installed = i < currentParts.length ? currentParts[i] : 0;
    if (next != installed) return next > installed;
  }
  return false;
}

class RulerPainter extends CustomPainter {
  const RulerPainter({required this.seconds, required this.pixelsPerSecond});
  final double seconds;
  final double pixelsPerSecond;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF171820));
    for (var s = 0; s <= seconds.ceil(); s++) {
      final x = s * pixelsPerSecond;
      if (x > size.width) break;
      final major = s % 5 == 0;
      canvas.drawLine(Offset(x, major ? 13 : 22), Offset(x, size.height), Paint()..color = major ? const Color(0xFF5B5E6E) : const Color(0xFF343642));
      if (major) {
        final minuteText = (s ~/ 60).toString().padLeft(2, '0');
        final secondText = (s % 60).toString().padLeft(2, '0');
        final label = '$minuteText:$secondText';
        final tp = TextPainter(text: TextSpan(text: label, style: const TextStyle(color: Color(0xFFAAAABD), fontSize: 9)), textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas, Offset(x + 4, 3));
      }
    }
  }

  @override
  bool shouldRepaint(covariant RulerPainter old) => old.seconds != seconds || old.pixelsPerSecond != pixelsPerSecond;
}

class TimelineGridPainter extends CustomPainter {
  const TimelineGridPainter({required this.seconds, required this.pixelsPerSecond});
  final double seconds;
  final double pixelsPerSecond;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF13141B));
    for (var s = 0; s <= seconds.ceil(); s++) {
      final x = s * pixelsPerSecond;
      if (x > size.width) break;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), Paint()..color = s % 5 == 0 ? const Color(0xFF333542) : const Color(0xFF242630));
    }
    canvas.drawLine(Offset(0, size.height - 1), Offset(size.width, size.height - 1), Paint()..color = const Color(0xFF292B36));
  }

  @override
  bool shouldRepaint(covariant TimelineGridPainter old) => old.seconds != seconds || old.pixelsPerSecond != pixelsPerSecond;
}

class VideoStripPainter extends CustomPainter {
  const VideoStripPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF234765));
    var i = 0;
    for (var x = 2.0; x < size.width; x += 40) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, 3, 34, size.height - 6), const Radius.circular(3)), Paint()..color = i.isEven ? const Color(0xFF356D90) : const Color(0xFF294F77));
      canvas.drawRect(Rect.fromLTWH(x + 5, size.height * 0.25, 24, size.height * 0.36), Paint()..color = const Color(0xFF527D9B));
      i++;
    }
  }
  @override
  bool shouldRepaint(covariant VideoStripPainter old) => false;
}

class WaveformPainter extends CustomPainter {
  const WaveformPainter({required this.color, required this.samples});
  final Color color;
  final List<double> samples;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF163E37));
    final count = samples.isEmpty ? 0 : math.min(samples.length, (size.width / 2.5).floor());
    final paint = Paint()..color = color.withValues(alpha: 0.92)..strokeWidth = 1.8..strokeCap = StrokeCap.round;
    final center = size.height / 2;
    for (var i = 0; i < count; i++) {
      final sampleIndex = (i * samples.length / count).floor().clamp(0, samples.length - 1);
      final h = math.max(1.5, samples[sampleIndex] * size.height * 0.88);
      final x = i * size.width / count + 1;
      canvas.drawLine(Offset(x, center - h / 2), Offset(x, center + h / 2), paint);
    }
  }
  @override
  bool shouldRepaint(covariant WaveformPainter old) => old.color != color || !identical(old.samples, samples);
}