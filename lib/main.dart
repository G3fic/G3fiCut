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
import 'canvas_snapping.dart';
import 'effect_catalog.dart';
import 'release_assets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const GifCutApp());
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

class ContinuousPointerDrag extends StatefulWidget {
  const ContinuousPointerDrag({
    super.key,
    required this.onDelta,
    required this.child,
    this.onEnd,
    this.onStart,
  });

  final ValueChanged<Offset> onDelta;
  final VoidCallback? onEnd;
  final VoidCallback? onStart;
  final Widget child;

  @override
  State<ContinuousPointerDrag> createState() => _ContinuousPointerDragState();
}

class _ContinuousPointerDragState extends State<ContinuousPointerDrag> {
  int? _activePointer;
  Offset? _lastGlobalPosition;

  void _handlePointerDown(PointerDownEvent event) {
    if (_activePointer != null || (event.buttons & kPrimaryButton) == 0) return;
    _activePointer = event.pointer;
    _lastGlobalPosition = event.position;
    widget.onStart?.call();
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    final previous = _lastGlobalPosition;
    _lastGlobalPosition = event.position;
    if (previous == null) return;
    final delta = event.position - previous;
    if (delta.distanceSquared > 0) widget.onDelta(delta);
  }

  void _finishPointer(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _lastGlobalPosition = null;
    widget.onEnd?.call();
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: _finishPointer,
        onPointerCancel: _finishPointer,
        child: widget.child,
      );
}

class GifCutApp extends StatelessWidget {
  const GifCutApp({super.key});
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

class TimelineEffectClip {
  TimelineEffectClip({required this.type, required this.start, required this.end});
  String type;
  double start, end;
  double get duration => end - start;
}

class TimelineTransition {
  TimelineTransition({required this.type, required this.at, required this.duration});
  String type;
  double at, duration;
}

class ExportTimelineSegment {
  const ExportTimelineSegment({
    required this.path,
    required this.start,
    required this.end,
    required this.isGap,
  });
  final String path;
  final double start;
  final double end;
  final bool isGap;
  double get duration => end - start;
}

class _EditorPageState extends State<EditorPage> with WidgetsBindingObserver {
  static const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.3.78');
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
  final GlobalKey _previewCanvasKey = GlobalKey();
  String _selectedCanvasObject = 'video';
  double _videoRotateStartAngle = 0;
  double _videoRotateStartRotation = 0;
  final Map<int, double> _photoRotateStartAngles = {};
  final Map<int, double> _photoRotateStartRotations = {};
  double _videoDragRawX = 0;
  double _videoDragRawY = 0;
  CanvasGuide? _videoSnapXGuide;
  CanvasGuide? _videoSnapYGuide;
  final Map<int, Offset> _photoDragRawOffsets = {};
  final Map<int, CanvasGuide> _photoSnapXGuides = {};
  final Map<int, CanvasGuide> _photoSnapYGuides = {};
  double? _verticalSnapGuidePosition;
  double? _horizontalSnapGuidePosition;
  int _gapNextClipIndex = -1;
  bool _gapResumePending = false;
  bool _suppressPlayerStateEvents = false;
  double _mediaPanelWidth = 188;
  double _inspectorPanelWidth = 220;
  double _timelinePanelHeight = 252;
  final Map<String, Offset> _resizeHandleLastGlobal = {};
  double frameRate = 30.0;
  bool snappingEnabled = true;
  double? _timelineSnapAt;
  final ScrollController timelineScrollController = ScrollController();
  final ScrollController timelineVerticalScrollController = ScrollController();
  int _clipMoveIndex = -1;
  double _clipMoveOriginalStart = 0;
  double _clipMovePointerX = 0;
  TimelineSnapshot? _clipMoveBefore;
  bool _showVerticalSnapGuide = false;
  bool _showHorizontalSnapGuide = false;
  String aspectRatioPreset = '16:9';
  static const double _timelineLabelWidth = 112;
  double _aspectRatioValue(String preset) => switch (preset) {
    '9:16' => 9 / 16, '1:1' => 1, '4:3' => 4 / 3,
    '4:5' => 4 / 5, '3:2' => 3 / 2, _ => 16 / 9,
  };
  String videoEffect = 'Оригинал';
  String transitionEffect = 'Нет';
  double transitionDuration = 0.4;
  static const _timelineEffectTypes = ProjectEffectClip.supportedTypes;
  static const _timelineTransitionTypes = ProjectTransition.supportedTypes;

  String get _exportEffectFilter => _filterForEffect(videoEffect);

  String _filterForEffect(String type) {
    final lutName = builtinLutFiles[type];
    if (lutName != null) {
      final lutFile = File(p.join(
        p.dirname(Platform.resolvedExecutable),
        'luts',
        lutName,
      ));
      if (!lutFile.existsSync()) return 'null';
      final escapedPath = lutFile.absolute.path
          .replaceAll('\\\\', '/')
          .replaceAll("'", "\\\\'");
      return "lut3d=file='$escapedPath':interp=tetrahedral";
    }

    const legacyNames = <String, String>{
      'Холодный': 'Холодный тон',
      'Тёплый': 'Тёплый тон',
      'Мягкое размытие': 'Размытие',
    };
    const legacyFilters = <String, String>{
      'Холодный': 'colorbalance=rs=-0.04:bs=0.12',
      'Тёплый': 'colorbalance=rs=0.12:bs=-0.06',
      'Мягкое размытие': 'gblur=sigma=2',
    };
    return legacyFilters[type] ??
        builtinEffectExportFilters[legacyNames[type] ?? type] ??
        'null';
  }

  List<double> get effectColorMatrix =>
      lutPreviewMatrices[videoEffect] ??
      _previewEffectMatrix(videoEffect);

  List<double> _previewEffectMatrix(String type) {
    const aliases = <String, String>{
      'Холодный': 'Холодный тон',
      'Тёплый': 'Тёплый тон',
      'Мягкое размытие': 'Размытие',
      'Оригинал': 'Оригинал',
    };
    final resolved = aliases[type] ?? type;
    return _timelineEffectColorMatrix(resolved);
  }

  ({Color color, double opacity}) get previewTransitionOverlay {
    final seconds = position.inMilliseconds / 1000;
    var opacity = 0.0;
    var color = Colors.black;
    for (final transition in timelineTransitions) {
      final half = transition.duration / 2;
      final progress = 1 - (seconds - transition.at).abs() / math.max(0.05, half);
      if (progress <= 0) continue;
      if (transition.type == 'Белая вспышка' || transition.type == 'Растворение через белый') {
        color = Colors.white;
      } else if (transition.type == 'Затемнение' || transition.type == 'Растворение через чёрный' || transition.type == 'Растворение') {
        color = Colors.black;
      } else {
        color = const Color(0xFFB7A1E8);
      }
      opacity = math.max(opacity, progress.clamp(0.0, 0.72)).toDouble();
    }
    // Keep the legacy inspector transition as a fallback for projects that
    // use the global transition setting but have no per-cut transition clips.
    if (timelineTransitions.isEmpty && transitionEffect != 'Нет' && videoClips.length > 1) {
      for (var i = 0; i < videoClips.length; i++) {
        final clip = videoClips[i];
        if (i > 0 && seconds >= clip.timelineStart && seconds < clip.timelineStart + transitionDuration) {
          opacity = math.max(opacity, 1 - (seconds - clip.timelineStart) / transitionDuration).toDouble();
        }
        if (i < videoClips.length - 1 && seconds > clip.timelineEnd - transitionDuration && seconds <= clip.timelineEnd) {
          opacity = math.max(opacity, (seconds - (clip.timelineEnd - transitionDuration)) / transitionDuration).toDouble();
        }
      }
      color = transitionEffect == 'Белая вспышка' ? Colors.white : Colors.black;
    }
    return (color: color, opacity: opacity.clamp(0.0, 1.0).toDouble());
  }
  String inspectorTab = 'video';
  String mediaPanelTab = 'media';
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
  final List<TimelineEffectClip> effectClips = [];
  final List<TimelineTransition> timelineTransitions = [];
  int selectedEffectClipIndex = -1;
  int selectedTransitionIndex = -1;
  bool selectedAudioClip = false;
  int _effectClipMoveIndex = -1;
  double _effectClipMoveStart = 0;
  double _effectClipMovePointerX = 0;
  TimelineSnapshot? _effectClipMoveBefore;
  int _effectResizeIndex = -1;
  bool _effectResizeLeft = false;
  double _effectResizePointerX = 0;
  double _effectResizeStart = 0;
  double _effectResizeEnd = 0;
  TimelineSnapshot? _effectResizeBefore;
  String? _hoveredLibraryPreview;
  int? _timelinePanPointer;
  Offset? _timelinePanLastGlobal;
  bool _timelinePanMoved = false;
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
      ..userAgent = 'GifCut/$appVersion';
    try {
      final responseBody = await _fetchLatestRelease(client);
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic>) throw const FormatException('Некорректный ответ GitHub Releases.');

      final latestTag = decoded['tag_name'] as String?;
      if (latestTag == null || latestTag.trim().isEmpty) {
        throw const FormatException('В ответе GitHub не найдена версия релиза.');
      }
      final latestVersion = latestTag.replaceFirst(RegExp(r'^[vV]'), '');
      if (!isNumericSemanticVersion(latestVersion)) {
        throw FormatException('Некорректный номер версии GitHub Release: $latestTag. Ожидается формат MAJOR.MINOR.PATCH, например 0.3.74.');
      }
      if (!isVersionNewer(latestVersion, appVersion)) {
        if (showNoUpdateMessage && mounted) setStatus('Установлена последняя версия GifCut $appVersion.');
        return;
      }

      final assets = decoded['assets'];
      if (assets is! List) throw const FormatException('В релизе не найден список файлов.');
      final installerAsset = findReleaseUpdateAsset(assets, latestVersion);
      if (installerAsset == null) {
        throw StateError(
          'В релизе $latestTag не найден установщик '
          'GifCut-Setup-$latestVersion.exe. Обновление не запускалось.',
        );
      }

      final rawUrl = installerAsset['browser_download_url'] as String?;
      final downloadUri = rawUrl == null ? null : Uri.tryParse(rawUrl);
      if (downloadUri == null ||
          downloadUri.scheme != 'https' ||
          downloadUri.host != 'github.com' ||
          !(downloadUri.path.startsWith('/G3fic/G3fiCut/releases/download/') ||
            downloadUri.path.startsWith('/G3fic/GifCut/releases/download/'))) {
        throw const FormatException('Ссылка на установщик не принадлежит официальным GitHub Releases GifCut.');
      }

      final digest = installerAsset['digest'] as String?;
      if (digest == null || !digest.startsWith('sha256:')) {
        throw StateError('GitHub не предоставил SHA-256 установщика. Обновление отменено без проверки целостности.');
      }
      if (mounted) setStatus('Доступно обновление $latestVersion.');
      if (!mounted) return;
      final shouldUpdate = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Доступно обновление GifCut'),
          content: Text(
            'Установлена версия $appVersion. Доступна версия $latestVersion.\n\n'
            'GifCut скачает установщик Windows и проверит его SHA-256. Затем откроется мастер установки GifCut. '
            'Программа закроется, пока установщик обновляет файлы. '
            'Подтвердите запрос Windows, если появится окно контроля учётных записей.',
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

  Future<void> _downloadAndRunInstaller(
    Uri uri,
    String version,
    String expectedDigest,
  ) async {
    if (!Platform.isWindows) {
      setStatus('Автообновление поддерживается только в Windows.');
      return;
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..userAgent = 'GifCut/$appVersion';
    File? installer;
    var installerVerified = false;
    try {
      if (mounted) setStatus('Подготавливаю установщик GifCut $version…');
      final downloadsDirectory = await getDownloadsDirectory();
      final updateDirectory = downloadsDirectory ?? await getTemporaryDirectory();
      await updateDirectory.create(recursive: true);
      installer = File(p.join(updateDirectory.path, 'GifCut-Setup-$version.exe'));

      final request = await client.getUrl(uri).timeout(const Duration(seconds: 25));
      final response = await request.close().timeout(const Duration(seconds: 60));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Не удалось скачать установщик (HTTP ${response.statusCode}).');
      }

      final sink = installer.openWrite();
      var received = 0;
      var nextProgressMark = 1024 * 1024;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          if (received >= nextProgressMark) {
            nextProgressMark = received + 1024 * 1024;
            final total = response.contentLength;
            final progress = total > 0
                ? ' ${(received * 100 / total).clamp(0, 100).round()}%'
                : '';
            if (mounted) setStatus('Скачиваю установщик $version$progress…');
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (await installer.length() < 1024 * 1024) {
        throw StateError('Файл установщика слишком мал или повреждён.');
      }

      if (mounted) setStatus('Проверяю SHA-256 установщика…');
      final actual = await crypto.sha256
          .bind(installer.openRead())
          .first
          .timeout(const Duration(minutes: 3));
      final expected = expectedDigest.substring('sha256:'.length).toLowerCase();
      if (actual.toString().toLowerCase() != expected) {
        throw StateError('Контрольная сумма установщика не совпала. Установка отменена.');
      }
      installerVerified = true;

      // Open the verified executable through Windows Explorer. The shell
      // honors the Inno Setup elevation manifest and can show the UAC prompt.
      // Keep GifCut alive; Inno Setup's Restart Manager can close the editor
      // when setup is ready to replace the running application files.
      if (mounted) setStatus('Открываю установщик GifCut $version…');
      await Process.start(
        'explorer.exe',
        [installer.path],
        mode: ProcessStartMode.detached,
      );
      if (mounted) {
        setStatus(
          'Установщик GifCut $version сохранён в папке «Загрузки» и открыт. '
          'Завершите установку в отдельном окне.',
        );
      }
    } catch (e) {
      final message = e.toString().replaceFirst('Bad state: ', '');
      if (mounted) {
        setStatus(
          installerVerified
              ? 'Установщик сохранён в папке «Загрузки», но не открылся: $message'
              : 'Не удалось подготовить установщик: $message',
        );
      }
      if (installer != null && !installerVerified) {
        try {
          if (await installer.exists()) await installer.delete();
        } catch (_) {
          // Keep the original update error visible in the status bar.
        }
      }
      if (mounted && installerVerified && installer != null) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Установщик скачан, но не открылся'),
            content: SelectableText(
              'Запустите файл вручную из папки «Загрузки»:\n${installer!.path}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Закрыть'),
              ),
            ],
          ),
        );
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
    timelineVerticalScrollController.dispose();
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
        effectClips: effectClips.map((effect) => ProjectEffectClip(
          type: effect.type,
          start: effect.start,
          end: effect.end,
        )).toList(),
        transitions: timelineTransitions.map((transition) => ProjectTransition(
          type: transition.type,
          at: transition.at,
          duration: transition.duration,
        )).toList(),
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
        effectClips
          ..clear()
          ..addAll(document.effectClips.map((effect) => TimelineEffectClip(
            type: effect.type,
            start: effect.start,
            end: effect.end,
          )));
        timelineTransitions
          ..clear()
          ..addAll(document.transitions.map((transition) => TimelineTransition(
            type: transition.type,
            at: transition.at,
            duration: transition.duration,
          )));
        selectedEffectClipIndex = -1;
        selectedTransitionIndex = -1;
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
    if (busy) return;
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false, dialogTitle: 'Выберите изображение для слоя фото', allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp']);
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null || !await File(path).exists()) { setStatus('Не удалось прочитать изображение.'); return; }
      setState(() {
        photoOverlays.add(PhotoOverlay(path: path));
        selectedPhotoOverlay = photoOverlays.length - 1;
        _selectedCanvasObject = 'photo';
        projectDirty = true;
        status = videoPath == null
            ? 'Фото загружено. Добавьте видео, чтобы разместить его поверх.'
            : 'Фото добавлено поверх видео.';
      });
    } catch (e) { setStatus('Не удалось импортировать фото: $e'); }
  }

  Future<List<double>> _readWaveform(String path, {int buckets = 1800}) async {
    final bytes = await File(path).readAsBytes();
    if (bytes.length < 44 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      return const [];
    }

    final data = ByteData.sublistView(bytes);
    var channels = 0;
    var bitsPerSample = 0;
    var audioFormat = 0;
    var dataOffset = -1;
    var dataSize = 0;
    var offset = 12;

    // WAV files can contain optional chunks before audio data. Find the
    // format and data chunks rather than assuming a fixed 44-byte header.
    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      final chunkStart = offset + 8;
      final availableSize = math.max(
        0,
        math.min(chunkSize, bytes.length - chunkStart),
      ).toInt();

      if (chunkId == 'fmt ' && availableSize >= 16) {
        audioFormat = data.getUint16(chunkStart, Endian.little);
        channels = data.getUint16(chunkStart + 2, Endian.little);
        bitsPerSample = data.getUint16(chunkStart + 14, Endian.little);
      } else if (chunkId == 'data') {
        dataOffset = chunkStart;
        dataSize = availableSize;
      }

      if (dataOffset >= 0 && channels > 0 && bitsPerSample > 0) break;
      final nextOffset = chunkStart + chunkSize + (chunkSize.isOdd ? 1 : 0);
      if (nextOffset <= offset || nextOffset > bytes.length) break;
      offset = nextOffset;
    }

    if (audioFormat != 1 || bitsPerSample != 16 || channels < 1 || dataOffset < 0) {
      return const [];
    }

    final bytesPerSample = bitsPerSample ~/ 8;
    final frameSize = channels * bytesPerSample;
    final frames = dataSize ~/ frameSize;
    if (frames <= 0) return const [];

    final count = math.min(buckets, frames);
    final result = <double>[];
    for (var bucket = 0; bucket < count; bucket++) {
      final first = (bucket * frames / count).floor();
      final last = math.max(first + 1, ((bucket + 1) * frames / count).floor());
      var peak = 0.0;
      for (var frame = first; frame < last; frame++) {
        for (var channel = 0; channel < channels; channel++) {
          final index = dataOffset + frame * frameSize + channel * bytesPerSample;
          if (index + 1 >= dataOffset + dataSize) break;
          final sample = data.getInt16(index, Endian.little).abs() / 32768.0;
          if (sample > peak) peak = sample;
        }
      }
      result.add(peak);
    }
    return result;
  }

  CanvasGuideSnapResult _snapToCanvasGuide(
    double rawOffset,
    double canvasExtent,
    double objectExtent,
    CanvasGuide? previousGuide,
  ) =>
      const CanvasGuideSnapper().update(
        rawOffset: rawOffset,
        canvasExtent: canvasExtent,
        objectExtent: objectExtent,
        previousGuide: previousGuide,
        enabled: snappingEnabled,
      );

  double? _canvasGuidePosition(CanvasGuide? guide, double extent) =>
      switch (guide) {
        CanvasGuide.leading => 0,
        CanvasGuide.center => extent / 2,
        CanvasGuide.trailing => extent,
        null => null,
      };

  void _clearCanvasSnapGuides() {
    _videoSnapXGuide = null;
    _videoSnapYGuide = null;
    _photoSnapXGuides.clear();
    _photoSnapYGuides.clear();
    _showVerticalSnapGuide = false;
    _showHorizontalSnapGuide = false;
    _verticalSnapGuidePosition = null;
    _horizontalSnapGuidePosition = null;
  }

  void _startVideoCanvasDrag() {
    _videoDragRawX = videoOffsetX;
    _videoDragRawY = videoOffsetY;
    _videoSnapXGuide = null;
    _videoSnapYGuide = null;
    _selectVideoAtPlayhead();
  }

  double _softAngleSnap(double degrees) {
    if (!snappingEnabled) return degrees;
    final rightAngle = const AngleSnapper(stepDegrees: 90, catchDistance: 5)
        .snap(degrees);
    if (rightAngle != degrees) return rightAngle;
    return const AngleSnapper(stepDegrees: 15, catchDistance: 3).snap(degrees);
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
        if ((next.start - clip.end).abs() <= 0.05) {
          // Split clips share a contiguous source range; seeking here causes
          // a visible frame flash and a brief audio dropout in media_kit.
          setState(() => position = Duration(milliseconds: (next.timelineStart * 1000).round()));
          return;
        }
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
    final resumeAfterGapSeek = _playheadInGap && playing;
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
      if (resumeAfterGapSeek) {
        _suppressPlayerStateEvents = false;
        await activePlayer.play();
      }
    } finally {
      _seekingAcrossCut = false;
      _suppressPlayerStateEvents = false;
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
      _selectedCanvasObject = 'video';
      selectedPhotoOverlay = -1;
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
    if (mounted) {
      setState(() {
        _reconcileTimelineAnnotations();
        _timelineSnapAt = null;
        status = 'Длина клипа изменена. Ctrl+Z — отменить.';
      });
    }
    if (before != null) _timelineHistory.record(before: before, after: _captureTimelineSnapshot());
    _edgeDragBefore = null;
    _edgeDragIndex = -1;
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
    if (key == LogicalKeyboardKey.delete && shift) { deleteSelectedTimelineItem(ripple: true); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) { deleteSelectedTimelineItem(); return KeyEventResult.handled; }
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
                    SizedBox(width: _inspectorPanelWidth, child: inspectorPanel()),
                    _verticalPanelSplitter('inspector-panel-splitter', (dx) {
                      final screenWidth = MediaQuery.sizeOf(context).width;
                      final maxWidth = (screenWidth - 64 - 1 - 14 - _mediaPanelWidth - 220).clamp(190.0, 440.0).toDouble();
                      _inspectorPanelWidth = (_inspectorPanelWidth - dx).clamp(190.0, maxWidth).toDouble();
                    }),
                    Expanded(child: previewPanel()),
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
            final screenHeight = MediaQuery.sizeOf(context).height;
            final maxTimelineHeight = (screenHeight - 56 - 8 - 1 - 40 - 180)
                .clamp(160.0, 520.0).toDouble();
            _timelinePanelHeight = (_timelinePanelHeight - details.delta.dy)
                .clamp(160.0, maxTimelineHeight).toDouble();
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
          const Text('GifCut', style: TextStyle(fontSize: 18, letterSpacing: -.5, fontWeight: FontWeight.w900)),
          const SizedBox(width: 10),
          const SizedBox(width: 10),
          Flexible(child: Text((projectFilePath == null ? 'Новый проект' : p.basenameWithoutExtension(projectFilePath!)) + (projectDirty ? ' •' : ''), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFFD3D3DF)))),
          const Spacer(),
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
            _railAction(Icons.add_photo_alternate_outlined, 'Добавить фото', importPhotoOverlay, disabled: busy, color: const Color(0xFFB18CFF)),
            _railAction(Icons.graphic_eq, 'Извлечь звук', extractAudio, disabled: busy || videoPath == null),
            const Divider(height: 14),
            _railAction(Icons.tune_rounded, 'Цвет', showColorAdjustments, disabled: busy || videoClips.isEmpty),
            _railAction(Icons.volume_up_rounded, 'Громкость', () => setState(() => inspectorTab = 'audio')),
            _railAction(Icons.undo, 'Отменить', undoTimelineEdit, disabled: !_timelineHistory.canUndo),
            _railAction(Icons.redo, 'Повторить', redoTimelineEdit, disabled: !_timelineHistory.canRedo),
            const Divider(height: 14),
            _railAction(Icons.ios_share, 'Экспорт', exportEditedVideo, disabled: videoClips.isEmpty || busy, color: accent),
            _railAction(Icons.system_update_alt, 'Обновления', () => unawaited(checkForUpdates(showNoUpdateMessage: true)), disabled: checkingForUpdates),
            _railAction(Icons.keyboard_outlined, 'Горячие клавиши', showKeyboardShortcuts, key: const ValueKey('keyboard-shortcuts')),
          ]),
        ),
      );

  Widget _railAction(IconData icon, String tooltip, VoidCallback action, {bool disabled = false, Color color = muted, Key? key}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Tooltip(
          message: tooltip,
          child: IconButton(
            key: key,
            visualDensity: VisualDensity.compact,
            onPressed: disabled ? null : action,
            icon: Icon(icon, size: 20, color: disabled ? muted.withValues(alpha: .35) : color),
          ),
        ),
      );

  Widget mediaPanel() => Container(
        color: panel,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _mediaPanelTabButton('media', 'Медиа', Icons.perm_media_outlined),
            const SizedBox(width: 6),
            _mediaPanelTabButton('effects', 'Эффекты', Icons.auto_awesome_outlined),
          ]),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: mediaPanelTab == 'media'
                  ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(
                        width: double.infinity,
                        child: LayoutBuilder(builder: (context, constraints) {
                          final compact = constraints.maxWidth < 170;
                          return Tooltip(
                            message: 'Импортировать видео',
                            child: OutlinedButton.icon(
                              onPressed: busy ? null : pickVideo,
                              icon: const Icon(Icons.video_call_outlined, size: 17),
                              label: Text(
                                compact ? 'Импорт' : 'Импортировать видео',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(width: double.infinity, child: OutlinedButton.icon(
                        onPressed: busy ? null : importPhotoOverlay,
                        icon: const Icon(Icons.add_photo_alternate_outlined, size: 17),
                        label: const Text('Добавить фото'),
                      )),
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
                        mediaItem(Icons.movie_outlined, p.basename(videoPath!), 'Видео · исходник', videoBlue,
                          imagePath: videoThumbnails.isNotEmpty ? videoThumbnails.first : null,
                          selected: _selectedCanvasObject == 'video',
                          onTap: () => _selectVideoClip(selectedClipIndex.clamp(0, videoClips.isEmpty ? 0 : videoClips.length - 1).toInt())),
                        if (audioPath != null) ...[
                          const SizedBox(height: 7),
                          mediaItem(Icons.graphic_eq, p.basename(audioPath!), 'Извлечённое аудио', audioGreen,
                            selected: selectedAudioClip,
                            onTap: () => setState(() { selectedAudioClip = true; selectedPhotoOverlay = -1; selectedEffectClipIndex = -1; selectedTransitionIndex = -1; inspectorTab = 'audio'; _selectedCanvasObject = 'audio'; })),
                        ],
                        if (photoOverlays.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          const Text('ФОТО', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.1, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 7),
                          for (var i = 0; i < photoOverlays.length; i++) ...[
                            if (i > 0) const SizedBox(height: 6),
                            mediaItem(Icons.image_outlined, p.basename(photoOverlays[i].path), 'Фото · слой \${i + 1}', accent,
                              imagePath: photoOverlays[i].path,
                              selected: selectedPhotoOverlay == i,
                              onTap: () => setState(() { selectedPhotoOverlay = i; _selectedCanvasObject = 'photo'; })),
                          ],
                        ],
                      ],
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 8),
                      const Row(children: [Icon(Icons.tips_and_updates_outlined, color: muted, size: 15), SizedBox(width: 7), Text('Подсказка', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))]),
                      const SizedBox(height: 5),
                      const Text('Извлеките звук, чтобы получить отдельный клип на аудиодорожке под видео.', style: TextStyle(color: muted, fontSize: 11, height: 1.4)),
                    ])
                  : _effectsLibraryPanel(),
            ),
          ),
        ]),
      );

  Widget _mediaPanelTabButton(String id, String label, IconData icon) => Expanded(
        child: InkWell(
          key: ValueKey('media-library-$id'),
          borderRadius: BorderRadius.circular(7),
          onTap: () => setState(() => mediaPanelTab = id),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 5),
            decoration: BoxDecoration(
              color: mediaPanelTab == id ? const Color(0xFF303642) : const Color(0xFF20232B),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: mediaPanelTab == id ? accent : const Color(0xFF343644)),
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 14, color: mediaPanelTab == id ? accent : muted),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        color: mediaPanelTab == id ? Colors.white : muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Widget _libraryPreviewIndicator(
    String key, {
    required Color color,
    required IconData icon,
    required bool transition,
  }) {
    final hovering = _hoveredLibraryPreview == key;
    return AnimatedContainer(
      key: ValueKey('hover-preview-$key'),
      duration: const Duration(milliseconds: 220),
      width: 58,
      height: 27,
      decoration: BoxDecoration(
        color: hovering ? color.withValues(alpha: 0.22) : const Color(0xFF151720),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: hovering ? color.withValues(alpha: 0.9) : const Color(0xFF3A3D4A),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        Positioned.fill(
          child: Row(children: [
            Expanded(child: ColoredBox(color: color.withValues(alpha: hovering ? 0.32 : 0.12))),
            Expanded(child: ColoredBox(color: Colors.white.withValues(alpha: hovering && transition ? 0.24 : 0.04))),
          ]),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          left: hovering ? 34 : 3,
          top: 2,
          bottom: 2,
          width: 18,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: transition
                  ? Colors.white.withValues(alpha: hovering ? 0.94 : 0.45)
                  : color.withValues(alpha: hovering ? 0.96 : 0.5),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Icon(icon, size: 12, color: hovering ? Colors.black87 : Colors.white),
          ),
        ),
      ]),
    );
  }

  Widget _effectsLibraryPanel() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('СТАНДАРТНЫЕ ЭФФЕКТЫ', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.0, fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          for (final type in (_timelineEffectTypes.toList()..sort()))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SizedBox(
                width: double.infinity,
                child: MouseRegion(
                  onEnter: (_) => setState(() => _hoveredLibraryPreview = 'effect:$type'),
                  onExit: (_) {
                    if (_hoveredLibraryPreview == 'effect:$type') {
                      setState(() => _hoveredLibraryPreview = null);
                    }
                  },
                  child: OutlinedButton(
                    onPressed: busy || videoClips.isEmpty ? null : () => unawaited(addTimelineEffect(type)),
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    child: Row(children: [
                      const Icon(Icons.add, size: 14),
                      const SizedBox(width: 5),
                      Expanded(child: Text(type, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 4),
                      _libraryPreviewIndicator(
                        'effect:$type',
                        color: const {
                          'Чёрно-белый': Color(0xFFB8C0CC),
                          'Сепия': Color(0xFFC18B52),
                          'Негатив': Color(0xFFCE8BFF),
                          'Тёплый тон': Color(0xFFFFA65A),
                          'Холодный тон': Color(0xFF63C7FF),
                          'Размытие': Color(0xFF79D9CF),
                          'Высокий контраст': Color(0xFF9F8BFF),
                        }[type] ?? const Color(0xFFB18CFF),
                        icon: const {
                          'Чёрно-белый': Icons.tonality,
                          'Сепия': Icons.filter_vintage,
                          'Негатив': Icons.invert_colors,
                          'Тёплый тон': Icons.wb_sunny_outlined,
                          'Холодный тон': Icons.ac_unit,
                          'Размытие': Icons.blur_on,
                          'Высокий контраст': Icons.contrast,
                        }[type] ?? Icons.auto_awesome,
                        transition: false,
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          const Divider(height: 22),
          const Text('СТАНДАРТНЫЕ ПЕРЕХОДЫ', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.0, fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          for (final type in (_timelineTransitionTypes.toList()..sort()))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SizedBox(
                width: double.infinity,
                child: MouseRegion(
                  onEnter: (_) => setState(() => _hoveredLibraryPreview = 'transition:$type'),
                  onExit: (_) {
                    if (_hoveredLibraryPreview == 'transition:$type') {
                      setState(() => _hoveredLibraryPreview = null);
                    }
                  },
                  child: OutlinedButton(
                    onPressed: busy || videoClips.length < 2 ? null : () => unawaited(addTimelineTransition(type)),
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    child: Row(children: [
                      const Icon(Icons.add, size: 14),
                      const SizedBox(width: 5),
                      Expanded(child: Text(type, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 4),
                      _libraryPreviewIndicator(
                        'transition:$type',
                        color: const {
                          'Затемнение': Color(0xFF8A8D98),
                          'Белая вспышка': Color(0xFFFFFFFF),
                          'Растворение': Color(0xFFB79BFF),
                          'Смахивание влево': Color(0xFF72C8FF),
                          'Смахивание вправо': Color(0xFF72E0BA),
                        }[type] ?? const Color(0xFFFFC56B),
                        icon: const {
                          'Затемнение': Icons.brightness_3,
                          'Белая вспышка': Icons.flash_on,
                          'Растворение': Icons.blur_circular,
                          'Смахивание влево': Icons.swipe_left,
                          'Смахивание вправо': Icons.swipe_right,
                        }[type] ?? Icons.compare_arrows,
                        transition: true,
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Наведите курсор на карточку, чтобы увидеть анимированный образец. Добавляйте эффекты на свободные участки таймлайна.',
            style: TextStyle(color: muted, fontSize: 10, height: 1.45),
          ),
        ],
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
            final uniformScale = (videoScaleX + videoScaleY) / 2;
            final signedDelta = horizontalDirection != 0 && verticalDirection != 0
                ? (localDx * horizontalDirection + localDy * verticalDirection) / 2
                : horizontalDirection != 0 ? localDx * horizontalDirection : localDy * verticalDirection;
            final nextScale = (uniformScale + signedDelta * 2 / math.max(1, canvasSize.shortestSide)).clamp(.2, 4.0).toDouble();
            setState(() {
              videoScaleX = nextScale;
              videoScaleY = nextScale;
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

  Widget _buildPreviewBackdrop() => ClipRect(
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: 0.38),
              BlendMode.srcATop,
            ),
            child: Video(
              controller: videoController!,
              controls: NoVideoControls,
              fit: BoxFit.cover,
            ),
          ),
        ),
      );

  Widget _buildPreviewVideo() {
    Widget result = Video(
      controller: videoController!,
      controls: NoVideoControls,
      fit: BoxFit.contain,
    );
    final activeEffects = effectClips.where((effect) =>
        playheadSeconds >= effect.start && playheadSeconds < effect.end);
    for (final effect in activeEffects) {
      if (effect.type == 'Размытие') {
        result = ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 5.5, sigmaY: 5.5),
          child: result,
        );
      } else {
        result = ColorFiltered(
          colorFilter: ColorFilter.matrix(_timelineEffectColorMatrix(effect.type)),
          child: result,
        );
      }
    }
    return result;
  }

  List<double> _timelineEffectColorMatrix(String type) =>
      lutPreviewMatrices[type] ?? const <String, List<double>>{
        'Чёрно-белый': <double>[0.213,0.715,0.072,0,0, 0.213,0.715,0.072,0,0, 0.213,0.715,0.072,0,0, 0,0,0,1,0],
        'Сепия': <double>[0.393,0.769,0.189,0,0, 0.349,0.686,0.168,0,0, 0.272,0.534,0.131,0,0, 0,0,0,1,0],
        'Негатив': <double>[-1,0,0,0,255, 0,-1,0,0,255, 0,0,-1,0,255, 0,0,0,1,0],
        'Тёплый тон': <double>[1.12,0,0,0,0, 0,1,0,0,0, 0,0,0.94,0,0, 0,0,0,1,0],
        'Холодный тон': <double>[0.96,0,0,0,0, 0,1,0,0,0, 0,0,1.12,0,0, 0,0,0,1,0],
        'Высокий контраст': <double>[1.45,0,0,0,-56, 0,1.45,0,0,-56, 0,0,1.45,0,-56, 0,0,0,1,0],
        'Кинематографичный': <double>[1.08,0.01,0,0,2, 0.01,1,0,0,1, 0,0,0.96,0,-2, 0,0,0,1,0],
        'Плёночное зерно': <double>[1.04,0.01,0,0,0, 0,1.02,0,0,0, 0,0,0.98,0,0, 0,0,0,1,0],
        'Старая плёнка': <double>[0.90,0.08,0.02,0,10, 0.06,0.9,0.04,0,8, 0.02,0.08,0.88,0,6, 0,0,0,1,0],
        'VHS': <double>[1.04,0,0.02,0,0, 0.01,0.92,0.01,0,0, 0.02,0,1.05,0,0, 0,0,0,1,0],
        'Глитч RGB': <double>[1.08,0,-0.04,0,0, -0.04,1.05,0,0,0, 0,0.02,1.08,0,0, 0,0,0,1,0],
        'Виньетка': <double>[0.92,0,0,0,0, 0,0.92,0,0,0, 0,0,0.92,0,0, 0,0,0,1,0],
        'Резкость': <double>[1.04,0,0,0,-4, 0,1.04,0,0,-4, 0,0,1.04,0,-4, 0,0,0,1,0],
        'Пастель': <double>[0.94,0.03,0.03,0,12, 0.03,0.94,0.03,0,12, 0.03,0.03,0.94,0,12, 0,0,0,1,0],
        'Холодная ночь': <double>[0.90,0,0.06,0,0, 0,0.98,0.03,0,0, 0,0.05,1.16,0,0, 0,0,0,1,0],
      }[type] ?? const <double>[1,0,0,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0];

  String _effectExportFilter(String type) => _filterForEffect(type);

  String _transitionFilterName(String type) => transitionFilterName(type);

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
              color: const Color(0xFF303238),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(6),
              child: videoPath == null
                  ? SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 96),
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
                            aspectRatio: _aspectRatioValue(aspectRatioPreset),
                            child: LayoutBuilder(builder: (context, bounds) {
                              final shortSide = math.min(bounds.maxWidth, bounds.maxHeight);
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: ClipRect(
                                  child: Stack(key: _previewCanvasKey, fit: StackFit.expand, children: [
                                    const ColoredBox(color: Colors.black),
                                    if (videoController != null)
                                      Positioned.fill(
                                        child: IgnorePointer(child: _buildPreviewBackdrop()),
                                      ),
                                    if (_showVerticalSnapGuide && _verticalSnapGuidePosition != null)
                                      Positioned(left: _verticalSnapGuidePosition! - .5, top: 0, bottom: 0, child: IgnorePointer(child: Container(width: 1, color: const Color(0xFFB18CFF)))),
                                    if (_showHorizontalSnapGuide && _horizontalSnapGuidePosition != null)
                                      Positioned(top: _horizontalSnapGuidePosition! - .5, left: 0, right: 0, child: IgnorePointer(child: Container(height: 1, color: const Color(0xFF35D7FF)))),
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
                                                      child: ContinuousPointerDrag(
                                                        key: const ValueKey('video-canvas-drag-surface'),
                                                        onStart: _startVideoCanvasDrag,
                                                        onDelta: (screenDelta) => setState(() {
                                                          _videoDragRawX += screenDelta.dx / math.max(1, bounds.maxWidth);
                                                          _videoDragRawY += screenDelta.dy / math.max(1, bounds.maxHeight);
                                                          final radians = videoRotation * math.pi / 180;
                                                          final scaleX = (videoScaleX * previewZoom).abs();
                                                          final scaleY = (videoScaleY * previewZoom).abs();
                                                          final objectWidth = bounds.maxWidth * scaleX * math.cos(radians).abs() +
                                                              bounds.maxHeight * scaleY * math.sin(radians).abs();
                                                          final objectHeight = bounds.maxHeight * scaleY * math.cos(radians).abs() +
                                                              bounds.maxWidth * scaleX * math.sin(radians).abs();
                                                          final snapX = _snapToCanvasGuide(
                                                            _videoDragRawX,
                                                            bounds.maxWidth,
                                                            objectWidth,
                                                            _videoSnapXGuide,
                                                          );
                                                          final snapY = _snapToCanvasGuide(
                                                            _videoDragRawY,
                                                            bounds.maxHeight,
                                                            objectHeight,
                                                            _videoSnapYGuide,
                                                          );
                                                          _videoSnapXGuide = snapX.guide;
                                                          _videoSnapYGuide = snapY.guide;
                                                          _showVerticalSnapGuide = snapX.isSnapped;
                                                          _showHorizontalSnapGuide = snapY.isSnapped;
                                                          _verticalSnapGuidePosition = _canvasGuidePosition(snapX.guide, bounds.maxWidth);
                                                          _horizontalSnapGuidePosition = _canvasGuidePosition(snapY.guide, bounds.maxHeight);
                                                          videoOffsetX = snapX.offset;
                                                          videoOffsetY = snapY.offset;
                                                          projectDirty = true;
                                                        }),
                                                        onEnd: () => setState(_clearCanvasSnapGuides),
                                                        child: IgnorePointer(
                                                          child: ColorFiltered(
                                                            colorFilter: ColorFilter.matrix(filtersEnabled ? previewColorMatrix : const <double>[1,0,0,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0]),
                                                            child: ColorFiltered(
                                                              colorFilter: ColorFilter.matrix(effectColorMatrix),
                                                              child: ImageFiltered(
                                                                imageFilter: ui.ImageFilter.blur(
                                                                  sigmaX: (videoEffect == 'Мягкое размытие' ? 2.0 : 0.0) + (motionBlurEnabled ? 1.2 : 0.0),
                                                                  sigmaY: (videoEffect == 'Мягкое размытие' ? 2.0 : 0.0) + (motionBlurEnabled ? 1.2 : 0.0),
                                                                ),
                                                                child: _buildPreviewVideo(),
                                                              ),
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
                                                  if (_selectedCanvasObject == 'video') ...[
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
                                                        onPanStart: (details) {
                                                          final box = _previewCanvasKey.currentContext?.findRenderObject() as RenderBox?;
                                                          if (box == null) return;
                                                          final center = box.localToGlobal(Offset(box.size.width / 2 + videoOffsetX * box.size.width, box.size.height / 2 + videoOffsetY * box.size.height));
                                                          _videoRotateStartAngle = math.atan2(details.globalPosition.dy - center.dy, details.globalPosition.dx - center.dx);
                                                          _videoRotateStartRotation = videoRotation;
                                                        },
                                                        onPanUpdate: (details) {
                                                          final box = _previewCanvasKey.currentContext?.findRenderObject() as RenderBox?;
                                                          if (box == null) return;
                                                          final center = box.localToGlobal(Offset(box.size.width / 2 + videoOffsetX * box.size.width, box.size.height / 2 + videoOffsetY * box.size.height));
                                                          final angle = math.atan2(details.globalPosition.dy - center.dy, details.globalPosition.dx - center.dx);
                                                          var delta = (angle - _videoRotateStartAngle) * 180 / math.pi;
                                                          if (delta > 180) delta -= 360;
                                                          if (delta < -180) delta += 360;
                                                          setState(() { videoRotation = _softAngleSnap(_videoRotateStartRotation + delta); projectDirty = true; });
                                                        },
                                                        child: Container(
                                                          decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white, width: 1.5), boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)]),
                                                          child: const Icon(Icons.rotate_90_degrees_ccw, size: 17, color: Colors.white),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  ],
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
                                          onTap: () => setState(() {
                      selectedPhotoOverlay = i;
                      selectedAudioClip = false;
                      selectedEffectClipIndex = -1;
                      selectedTransitionIndex = -1;
                      inspectorTab = 'video';
                      _selectedCanvasObject = 'photo';
                    }),
                                          onPanStart: (_) {
                                            _photoDragRawOffsets[i] = Offset(photoOverlays[i].x, photoOverlays[i].y);
                                            _photoSnapXGuides.remove(i);
                                            _photoSnapYGuides.remove(i);
                                            setState(() { selectedPhotoOverlay = i; _selectedCanvasObject = 'photo'; });
                                          },
                                          onPanUpdate: (d) => setState(() {
                                            final raw = _photoDragRawOffsets[i] ?? Offset(photoOverlays[i].x, photoOverlays[i].y);
                                            final rawX = (raw.dx + d.delta.dx / bounds.maxWidth).clamp(-1.5, 1.5).toDouble();
                                            final rawY = (raw.dy + d.delta.dy / bounds.maxHeight).clamp(-1.5, 1.5).toDouble();
                                            final angle = photoOverlays[i].rotation * math.pi / 180;
                                            final photoExtent = shortSide * .36 * photoOverlays[i].scale *
                                                (math.cos(angle).abs() + math.sin(angle).abs());
                                            final snapX = _snapToCanvasGuide(
                                              rawX,
                                              bounds.maxWidth,
                                              photoExtent,
                                              _photoSnapXGuides[i],
                                            );
                                            final snapY = _snapToCanvasGuide(
                                              rawY,
                                              bounds.maxHeight,
                                              photoExtent,
                                              _photoSnapYGuides[i],
                                            );
                                            _photoDragRawOffsets[i] = Offset(rawX, rawY);
                                            if (snapX.guide == null) {
                                              _photoSnapXGuides.remove(i);
                                            } else {
                                              _photoSnapXGuides[i] = snapX.guide!;
                                            }
                                            if (snapY.guide == null) {
                                              _photoSnapYGuides.remove(i);
                                            } else {
                                              _photoSnapYGuides[i] = snapY.guide!;
                                            }
                                            _showVerticalSnapGuide = snapX.isSnapped;
                                            _showHorizontalSnapGuide = snapY.isSnapped;
                                            _verticalSnapGuidePosition = _canvasGuidePosition(snapX.guide, bounds.maxWidth);
                                            _horizontalSnapGuidePosition = _canvasGuidePosition(snapY.guide, bounds.maxHeight);
                                            photoOverlays[i].x = snapX.offset;
                                            photoOverlays[i].y = snapY.offset;
                                            projectDirty = true;
                                          }),
                                          onPanEnd: (_) {
                                            _photoDragRawOffsets.remove(i);
                                            _photoSnapXGuides.remove(i);
                                            _photoSnapYGuides.remove(i);
                                            setState(_clearCanvasSnapGuides);
                                          },
                                          child: Transform.rotate(
                                            angle: photoOverlays[i].rotation * math.pi / 180,
                                            child: Opacity(
                                              opacity: photoOverlays[i].opacity,
                                              child: DecoratedBox(
                                                decoration: BoxDecoration(border: selectedPhotoOverlay == i ? Border.all(color: accent, width: 2) : null),
                                                child: Stack(fit: StackFit.expand, children: [
                                                  Image.file(File(photoOverlays[i].path), fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
                                                  if (selectedPhotoOverlay == i)
                                                    Align(
                                                      alignment: Alignment.topCenter,
                                                      child: Transform.translate(
                                                        offset: const Offset(0, -19),
                                                        child: GestureDetector(
                                                          key: ValueKey('photo-rotate-$i'),
                                                          behavior: HitTestBehavior.opaque,
                                                          onPanStart: (details) {
                                                            final box = _previewCanvasKey.currentContext?.findRenderObject() as RenderBox?;
                                                            if (box == null) return;
                                                            final centerLocal = Offset(
                                                              bounds.maxWidth / 2 + photoOverlays[i].x * bounds.maxWidth,
                                                              bounds.maxHeight / 2 + photoOverlays[i].y * bounds.maxHeight,
                                                            );
                                                            final center = box.localToGlobal(centerLocal);
                                                            _photoRotateStartAngles[i] = math.atan2(details.globalPosition.dy - center.dy, details.globalPosition.dx - center.dx);
                                                            _photoRotateStartRotations[i] = photoOverlays[i].rotation;
                                                          },
                                                          onPanUpdate: (details) {
                                                            final box = _previewCanvasKey.currentContext?.findRenderObject() as RenderBox?;
                                                            if (box == null) return;
                                                            final centerLocal = Offset(
                                                              bounds.maxWidth / 2 + photoOverlays[i].x * bounds.maxWidth,
                                                              bounds.maxHeight / 2 + photoOverlays[i].y * bounds.maxHeight,
                                                            );
                                                            final center = box.localToGlobal(centerLocal);
                                                            final angle = math.atan2(details.globalPosition.dy - center.dy, details.globalPosition.dx - center.dx);
                                                            var delta = (angle - (_photoRotateStartAngles[i] ?? angle)) * 180 / math.pi;
                                                            if (delta > 180) delta -= 360;
                                                            if (delta < -180) delta += 360;
                                                            setState(() {
                                                              photoOverlays[i].rotation = _softAngleSnap((_photoRotateStartRotations[i] ?? photoOverlays[i].rotation) + delta);
                                                              projectDirty = true;
                                                            });
                                                          },
                                                          child: Container(
                                                            width: 26, height: 26,
                                                            decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white, width: 1.5)),
                                                            child: const Icon(Icons.rotate_right, size: 15, color: Colors.white),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
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

  Widget _selectedItemSettings() {
    if (selectedTransitionIndex >= 0 && selectedTransitionIndex < timelineTransitions.length) {
      final t = timelineTransitions[selectedTransitionIndex];
      final maxDuration = math.max(0.1, _maxTransitionDurationAt(t.at)).toDouble();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('НАСТРОЙКИ ПЕРЕХОДА', style: TextStyle(color: muted, fontSize: 10, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          isExpanded: true, initialValue: t.type,
          decoration: const InputDecoration(labelText: 'Тип перехода', isDense: true, border: OutlineInputBorder()),
          items: (_timelineTransitionTypes.toList()..sort()).map((v) => DropdownMenuItem(value: v, child: Text(v, style: const TextStyle(fontSize: 11)))).toList(),
          onChanged: (v) { if (v != null) _performTimelineEdit(() { t.type = v; status = 'Переход изменён: $v'; }); },
        ),
        _adjustmentSlider('Длительность', t.duration, 0.1, maxDuration, (v) => _performTimelineEdit(() { t.duration = v; })),
        property('Стык', '${t.at.toStringAsFixed(2)} с'),
        TextButton.icon(onPressed: deleteSelectedTimelineItem, icon: const Icon(Icons.delete_outline), label: const Text('Удалить переход')),
        const Divider(),
      ]);
    }
    if (selectedEffectClipIndex >= 0 && selectedEffectClipIndex < effectClips.length) {
      final e = effectClips[selectedEffectClipIndex];
      final maxDuration = math.max(0.08, timelineSeconds - e.start).toDouble();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('НАСТРОЙКИ ЭФФЕКТА', style: TextStyle(color: muted, fontSize: 10, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          isExpanded: true, initialValue: e.type,
          decoration: const InputDecoration(labelText: 'Эффект', isDense: true, border: OutlineInputBorder()),
          items: (_timelineEffectTypes.toList()..sort()).map((v) => DropdownMenuItem(value: v, child: Text(v, style: const TextStyle(fontSize: 11)))).toList(),
          onChanged: (v) { if (v != null) _performTimelineEdit(() { e.type = v; }); },
        ),
        _adjustmentSlider('Длительность', e.duration, 0.08, maxDuration, (v) {
          final ranges = effectClips.map((x) => TimelineEffectRange(x.type, x.start, x.end)).toList();
          final resized = TimelineEditing.resizeEffectEdge(effects: ranges, index: selectedEffectClipIndex, requestedTime: e.start + v, timelineEnd: timelineSeconds, resizeStart: false);
          _performTimelineEdit(() { e.start = resized.start; e.end = resized.end; });
        }),
        property('Начало', '${e.start.toStringAsFixed(2)} с'),
        TextButton.icon(onPressed: deleteSelectedTimelineItem, icon: const Icon(Icons.delete_outline), label: const Text('Удалить эффект')),
        const Divider(),
      ]);
    }
    if (selectedPhotoOverlay >= 0 && selectedPhotoOverlay < photoOverlays.length) {
      final pht = photoOverlays[selectedPhotoOverlay];
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('НАСТРОЙКИ ФОТО', style: TextStyle(color: muted, fontSize: 10, fontWeight: FontWeight.w800)),
        property('Файл', p.basename(pht.path)),
        _adjustmentSlider('Размер', pht.scale, 0.1, 5, (v) => setState(() { pht.scale = v; projectDirty = true; })),
        _adjustmentSlider('Поворот', pht.rotation, -180, 180, (v) => setState(() { pht.rotation = v; projectDirty = true; })),
        _adjustmentSlider('Прозрачность', pht.opacity, 0.05, 1, (v) => setState(() { pht.opacity = v; projectDirty = true; })),
        TextButton.icon(onPressed: deleteSelectedTimelineItem, icon: const Icon(Icons.delete_outline), label: const Text('Удалить фото')),
        const Divider(),
      ]);
    }
    if (selectedAudioClip && audioPath != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('НАСТРОЙКИ АУДИО', style: TextStyle(color: muted, fontSize: 10, fontWeight: FontWeight.w800)),
        _adjustmentSlider('Громкость', exportVolume, 0, 2, (v) => setState(() { exportVolume = v; projectDirty = true; })),
        property('Файл', p.basename(audioPath!)),
        TextButton.icon(onPressed: deleteSelectedTimelineItem, icon: const Icon(Icons.delete_outline), label: const Text('Удалить аудио')),
        const Divider(),
      ]);
    }
    if (_selectedCanvasObject == 'video' && videoClips.isNotEmpty && selectedClipIndex < videoClips.length) {
      final c = videoClips[selectedClipIndex];
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('НАСТРОЙКИ ВИДЕОКЛИПА', style: TextStyle(color: muted, fontSize: 10, fontWeight: FontWeight.w800)),
        property('Фрагмент', '${c.start.toStringAsFixed(2)}–${c.end.toStringAsFixed(2)} с'),
        property('На таймлайне', '${c.timelineStart.toStringAsFixed(2)} с'),
        const Divider(),
      ]);
    }
    return const SizedBox.shrink();
  }

  Widget inspectorPanel() => Container(
        color: panel,
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if ((selectedTransitionIndex >= 0 && selectedTransitionIndex < timelineTransitions.length) ||
                (selectedEffectClipIndex >= 0 && selectedEffectClipIndex < effectClips.length) ||
                (selectedPhotoOverlay >= 0 && selectedPhotoOverlay < photoOverlays.length) || selectedAudioClip ||
                (videoClips.isNotEmpty && _selectedCanvasObject == 'video' && selectedClipIndex < videoClips.length))
              _selectedItemSettings(),
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
                items: globalVideoEffectOptions.map((v) => DropdownMenuItem(value: v, child: Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)))).toList(),
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
                items: ['Нет', ...(_timelineTransitionTypes.toList()..sort())].map((v) => DropdownMenuItem(value: v, child: Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)))).toList(),
                onChanged: (value) => setState(() { transitionEffect = value ?? 'Нет'; projectDirty = true; }),
              ),
              if (transitionEffect != 'Нет')
                _adjustmentSlider('Длительность перехода', transitionDuration, 0.2, 1.0, (value) => setState(() { transitionDuration = value; projectDirty = true; })),
              const SizedBox(height: 8),
              Row(children: [
                const Expanded(child: Text('ФОТО ПОВЕРХ ВИДЕО', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.0, fontWeight: FontWeight.w800))),
                IconButton(tooltip: 'Добавить фото', visualDensity: VisualDensity.compact, onPressed: busy ? null : importPhotoOverlay, icon: const Icon(Icons.add_photo_alternate_outlined, size: 18)),
              ]),
              for (var i = 0; i < photoOverlays.length; i++)
                ListTile(
                  dense: true, contentPadding: EdgeInsets.zero, selected: selectedPhotoOverlay == i,
                  leading: const Icon(Icons.image_outlined, size: 18, color: accent),
                  title: Text(p.basename(photoOverlays[i].path), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
                  trailing: IconButton(tooltip: 'Удалить фото', visualDensity: VisualDensity.compact, onPressed: () => setState(() {
                    photoOverlays.removeAt(i);
                    if (selectedPhotoOverlay == i) {
                      selectedPhotoOverlay = -1;
                      _selectedCanvasObject = 'video';
                    } else if (selectedPhotoOverlay > i) {
                      selectedPhotoOverlay--;
                    }
                    projectDirty = true;
                  }), icon: const Icon(Icons.delete_outline, size: 16)),
                  onTap: () => setState(() {
                    selectedPhotoOverlay = i;
                    selectedAudioClip = false;
                    selectedEffectClipIndex = -1;
                    selectedTransitionIndex = -1;
                    _selectedCanvasObject = 'photo';
                  }),
                ),
              if (selectedPhotoOverlay >= 0 && selectedPhotoOverlay < photoOverlays.length) ...[
                _adjustmentSlider('Размер фото', photoOverlays[selectedPhotoOverlay].scale, 0.2, 3, (v) => setState(() { photoOverlays[selectedPhotoOverlay].scale = v; projectDirty = true; })),
                _adjustmentSlider('Поворот фото', photoOverlays[selectedPhotoOverlay].rotation, -180, 180, (v) => setState(() { photoOverlays[selectedPhotoOverlay].rotation = v; projectDirty = true; })),
                _adjustmentSlider('Прозрачность фото', photoOverlays[selectedPhotoOverlay].opacity, 0.05, 1, (v) => setState(() { photoOverlays[selectedPhotoOverlay].opacity = v; projectDirty = true; })),
              ],
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

  void _handleTimelinePointerDown(PointerDownEvent event) {
    if ((event.buttons & kSecondaryMouseButton) == 0) return;
    _timelinePanPointer = event.pointer;
    _timelinePanLastGlobal = event.position;
    _timelinePanMoved = false;
  }

  void _handleTimelinePointerMove(PointerMoveEvent event) {
    if (event.pointer != _timelinePanPointer) return;
    final previous = _timelinePanLastGlobal;
    _timelinePanLastGlobal = event.position;
    if (previous == null) return;
    final delta = event.position - previous;
    if (delta.distanceSquared < 0.25) return;
    if (delta.distance > 3) _timelinePanMoved = true;

    final horizontal = timelineScrollController;
    final vertical = timelineVerticalScrollController;
    if (horizontal.hasClients && delta.dx != 0) {
      horizontal.jumpTo(
        (horizontal.offset - delta.dx)
            .clamp(0.0, horizontal.position.maxScrollExtent)
            .toDouble(),
      );
    }
    if (vertical.hasClients && delta.dy != 0) {
      vertical.jumpTo(
        (vertical.offset - delta.dy)
            .clamp(0.0, vertical.position.maxScrollExtent)
            .toDouble(),
      );
    }
  }

  void _handleTimelinePointerEnd(PointerEvent event) {
    if (event.pointer != _timelinePanPointer) return;
    _timelinePanPointer = null;
    _timelinePanLastGlobal = null;
    // Keep _timelinePanMoved until the secondary-tap recognizer has decided
    // whether this was a context click or an intentional right-button pan.
  }

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
                      tooltip: 'Удалить выбранный элемент',
                      visualDensity: VisualDensity.compact,
                      onPressed: videoClips.isEmpty && effectClips.isEmpty && timelineTransitions.isEmpty && audioPath == null && photoOverlays.isEmpty
                          ? null
                          : deleteSelectedTimelineItem,
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
              behavior: HitTestBehavior.translucent,
              onPointerDown: _handleTimelinePointerDown,
              onPointerMove: _handleTimelinePointerMove,
              onPointerUp: _handleTimelinePointerEnd,
              onPointerCancel: _handleTimelinePointerEnd,
              onPointerSignal: (event) {
                if (event is! PointerScrollEvent) return;
                final horizontalController = timelineScrollController;
                final verticalController = timelineVerticalScrollController;
                if (event.scrollDelta.dy != 0 && horizontalController.hasClients) {
                  final pointerX = event.localPosition.dx;
                  final anchorSeconds = ((horizontalController.offset + pointerX - _timelineLabelWidth) / zoom)
                      .clamp(0.0, timelineSeconds).toDouble();
                  setTimelineZoom(event.scrollDelta.dy < 0 ? zoom + 4 : zoom - 4);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!horizontalController.hasClients) return;
                    final nextOffset = anchorSeconds * zoom + _timelineLabelWidth - pointerX;
                    horizontalController.jumpTo(nextOffset.clamp(0.0, horizontalController.position.maxScrollExtent).toDouble());
                  });
                } else if (verticalController.hasClients &&
                    verticalController.position.maxScrollExtent > 0) {
                  verticalController.jumpTo(
                    (verticalController.offset + event.scrollDelta.dy)
                        .clamp(0.0, verticalController.position.maxScrollExtent).toDouble(),
                  );
                }
              },
              child: SingleChildScrollView(
              controller: timelineScrollController,
              physics: const NeverScrollableScrollPhysics(),
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _timelineLabelWidth + timelineWidth,
                child: SingleChildScrollView(
                  controller: timelineVerticalScrollController,
                  primary: false,
                  physics: const NeverScrollableScrollPhysics(),
                  scrollDirection: Axis.vertical,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    SizedBox(
                      height: 32,
                      child: Row(children: [
                        Container(width: _timelineLabelWidth, padding: const EdgeInsets.only(left: 14), alignment: Alignment.centerLeft, color: const Color(0xFF171820), child: const Text('ВРЕМЯ', style: TextStyle(color: muted, fontSize: 9, letterSpacing: 1.1, fontWeight: FontWeight.w800))),
                        SizedBox(width: timelineWidth, child: CustomPaint(painter: RulerPainter(seconds: timelineSeconds, pixelsPerSecond: zoom), child: const SizedBox.expand())),
                      ]),
                    ),
                    trackRow(audio: false),
                    const SizedBox(height: 5),
                    trackRow(audio: true),
                    if (effectClips.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      effectTrackRow(),
                    ],
                    if (timelineTransitions.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      transitionTrackRow(),
                    ],
                    if (photoOverlays.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      photoTrackRow(),
                    ],
                  ]),
                  ),
                ),
              ),
              ),
            ),
          ),
        ]),
      );

  Widget effectTrackRow() => SizedBox(
        width: _timelineLabelWidth + timelineWidth,
        height: 54,
        child: Row(children: [
          Container(
            width: _timelineLabelWidth, height: 54, padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: const BoxDecoration(color: Color(0xFF191A22), border: Border(bottom: BorderSide(color: Color(0xFF292B36)))),
            child: Row(children: [
              const Icon(Icons.auto_awesome_outlined, size: 16, color: Color(0xFFB18CFF)),
              const SizedBox(width: 6),
              const Expanded(child: Text('Эффекты', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700))),
              IconButton(
                tooltip: 'Добавить эффект на таймлайн',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(width: 28, height: 30),
                padding: EdgeInsets.zero,
                onPressed: busy || videoClips.isEmpty ? null : addTimelineEffect,
                icon: const Icon(Icons.add, size: 16),
              ),
            ]),
          ),
          SizedBox(
            width: timelineWidth, height: 54,
            child: Stack(clipBehavior: Clip.hardEdge, children: [
              Positioned.fill(child: CustomPaint(painter: TimelineGridPainter(seconds: timelineSeconds, pixelsPerSecond: zoom))),
              for (var i = 0; i < effectClips.length; i++)
                Positioned(
                  left: effectClips[i].start * zoom + 3,
                  top: 5,
                  bottom: 5,
                  width: math.max(34.0, effectClips[i].duration * zoom - 2).toDouble(),
                  child: Stack(children: [
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          selectedEffectClipIndex = i;
                          selectedTransitionIndex = -1;
                          selectedAudioClip = false;
                          selectedPhotoOverlay = -1;
                          inspectorTab = 'video';
                          _selectedCanvasObject = 'timeline-effect';
                        }),
                        onSecondaryTapUp: (details) {
                          if (!_timelinePanMoved) showEffectClipMenu(details.globalPosition, i);
                        },
                        onPanStart: (_) => _startEffectClipMove(i),
                        onPanUpdate: _updateEffectClipMove,
                        onPanEnd: (_) => _finishEffectClipMove(),
                        onPanCancel: _finishEffectClipMove,
                        child: Container(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 11),
                          decoration: BoxDecoration(
                            color: const Color(0xAA7651B8),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: selectedEffectClipIndex == i ? Colors.white : const Color(0xFFD2B9FF),
                              width: selectedEffectClipIndex == i ? 2 : 1,
                            ),
                          ),
                          child: Row(children: [
                            const Icon(Icons.auto_awesome, size: 11, color: Colors.white),
                            const SizedBox(width: 4),
                            Flexible(child: Text(effectClips[i].type, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700))),
                          ]),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 10,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeLeftRight,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragStart: (_) => _startEffectResize(i, fromLeft: true),
                          onHorizontalDragUpdate: _updateEffectResize,
                          onHorizontalDragEnd: (_) => _finishEffectResize(),
                          onHorizontalDragCancel: _finishEffectResize,
                          child: Container(
                            decoration: BoxDecoration(
                              color: selectedEffectClipIndex == i ? Colors.white : const Color(0x88FFFFFF),
                              borderRadius: const BorderRadius.horizontal(left: Radius.circular(5)),
                            ),
                            child: const Center(child: SizedBox(width: 2, height: 15, child: ColoredBox(color: Color(0xFF7651B8)))),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: 10,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeLeftRight,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragStart: (_) => _startEffectResize(i, fromLeft: false),
                          onHorizontalDragUpdate: _updateEffectResize,
                          onHorizontalDragEnd: (_) => _finishEffectResize(),
                          onHorizontalDragCancel: _finishEffectResize,
                          child: Container(
                            decoration: BoxDecoration(
                              color: selectedEffectClipIndex == i ? Colors.white : const Color(0x88FFFFFF),
                              borderRadius: const BorderRadius.horizontal(right: Radius.circular(5)),
                            ),
                            child: const Center(child: SizedBox(width: 2, height: 15, child: ColoredBox(color: Color(0xFF7651B8)))),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
            ]),
          ),
        ]),
      );

  Widget transitionTrackRow() => SizedBox(
        width: _timelineLabelWidth + timelineWidth,
        height: 42,
        child: Row(children: [
          Container(
            width: _timelineLabelWidth, height: 42, padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: const BoxDecoration(color: Color(0xFF191A22), border: Border(bottom: BorderSide(color: Color(0xFF292B36)))),
            child: Row(children: [
              const Icon(Icons.compare_arrows, size: 16, color: Color(0xFFFFC56B)),
              const SizedBox(width: 6),
              const Expanded(child: Text('Переходы', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700))),
              IconButton(
                tooltip: 'Добавить переход на ближайший стык',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                padding: EdgeInsets.zero,
                onPressed: busy || videoClips.length < 2 ? null : addTimelineTransition,
                icon: const Icon(Icons.add, size: 16),
              ),
            ]),
          ),
          SizedBox(
            width: timelineWidth, height: 42,
            child: Stack(clipBehavior: Clip.hardEdge, children: [
              Positioned.fill(child: CustomPaint(painter: TimelineGridPainter(seconds: timelineSeconds, pixelsPerSecond: zoom))),
              for (var i = 0; i < timelineTransitions.length; i++)
                Positioned(
                  left: (timelineTransitions[i].at * zoom - 24).clamp(0.0, math.max(0.0, timelineWidth - 48)).toDouble(),
                  top: 3, bottom: 3, width: 48,
                  child: GestureDetector(
                    onTap: () => setState(() {
                      selectedTransitionIndex = i;
                      selectedEffectClipIndex = -1;
                      selectedAudioClip = false;
                      selectedPhotoOverlay = -1;
                      inspectorTab = 'video';
                      _selectedCanvasObject = 'timeline-transition';
                    }),
                    onSecondaryTapUp: (details) {
                      if (!_timelinePanMoved) showTimelineTransitionMenu(details.globalPosition, i);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xCC9A7138),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: selectedTransitionIndex == i ? Colors.white : const Color(0xFFFFD28D), width: selectedTransitionIndex == i ? 2 : 1),
                      ),
                      child: const Center(child: Icon(Icons.compare_arrows, size: 17, color: Colors.white)),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
      );
  Widget photoTrackRow() => SizedBox(
        width: _timelineLabelWidth + timelineWidth,
        height: 54,
        child: Row(children: [
          Container(
            width: _timelineLabelWidth, height: 54, padding: const EdgeInsets.symmetric(horizontal: 12),
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
                    onTap: () => setState(() {
                      selectedPhotoOverlay = i;
                      selectedAudioClip = false;
                      selectedEffectClipIndex = -1;
                      selectedTransitionIndex = -1;
                      _selectedCanvasObject = 'photo';
                    }),
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
      width: _timelineLabelWidth + timelineWidth,
      height: 63,
      child: Row(children: [
        Container(
          width: _timelineLabelWidth,
          height: 63,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(color: Color(0xFF191A22), border: Border(bottom: BorderSide(color: Color(0xFF292B36)))),
          child: Row(children: [
            Icon(audio ? Icons.graphic_eq : Icons.movie_outlined, size: 17, color: color),
            const SizedBox(width: 8),
            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(audio ? 'Аудио 1' : 'Видео 1', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(audio ? 'Звуковая дорожка' : 'Видеодорожка', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: muted)),
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
                    onTap: () => setState(() {
                      selectedAudioClip = true;
                      selectedEffectClipIndex = -1;
                      selectedTransitionIndex = -1;
                      selectedPhotoOverlay = -1;
                      inspectorTab = 'audio';
                      _selectedCanvasObject = 'audio';
                    }),
                    onSecondaryTapUp: (details) {
                      if (!_timelinePanMoved) showAudioClipMenu(details.globalPosition);
                    },
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: selectedAudioClip ? Colors.white : audioGreen, width: selectedAudioClip ? 2 : 1.5),
                      ),
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
                      onTap: () => _selectVideoClip(i),
                      onSecondaryTapUp: (details) {
                        if (!_timelinePanMoved) showClipMenu(details.globalPosition, i);
                      },
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
                              border: Border.all(color: _selectedCanvasObject == 'video' && selectedClipIndex == i ? const Color(0xFFB69CFF) : videoBlue, width: _selectedCanvasObject == 'video' && selectedClipIndex == i ? 3 : 1),
                              boxShadow: _selectedCanvasObject == 'video' && selectedClipIndex == i ? [BoxShadow(color: accent.withValues(alpha: .50), blurRadius: 12, spreadRadius: 1)] : null,
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
                          if (_selectedCanvasObject == 'video' && selectedClipIndex == i) ...[
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
              if (!audio)
                for (var i = 0; i < timelineTransitions.length; i++)
                  Positioned(
                    left: (timelineTransitions[i].at - timelineTransitions[i].duration / 2) * zoom + 4,
                    top: 9,
                    bottom: 9,
                    width: math.max(16.0, timelineTransitions[i].duration * zoom - 1).toDouble(),
                    child: GestureDetector(
                      onTap: () => setState(() {
                        selectedTransitionIndex = i;
                        selectedEffectClipIndex = -1;
                        selectedAudioClip = false;
                        selectedPhotoOverlay = -1;
                        _selectedCanvasObject = 'timeline-transition';
                      }),
                      onSecondaryTapUp: (details) {
                        if (!_timelinePanMoved) showTimelineTransitionMenu(details.globalPosition, i);
                      },
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0x66FFFFFF),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: selectedTransitionIndex == i ? Colors.white : const Color(0xCCFFFFFF),
                            width: selectedTransitionIndex == i ? 2 : 1,
                          ),
                        ),
                        child: const Center(
                          child: Icon(Icons.compare_arrows, size: 12, color: Colors.white),
                        ),
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
        effectClips: effectClips.map((effect) => TimelineEffectRange(
          effect.type, effect.start, effect.end,
        )).toList(),
        transitions: timelineTransitions.map((transition) => TimelineTransitionRange(
          transition.type, transition.at, transition.duration,
        )).toList(),
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
    effectClips
      ..clear()
      ..addAll(snapshot.effectClips.map((effect) => TimelineEffectClip(
        type: effect.type, start: effect.start, end: effect.end,
      )));
    timelineTransitions
      ..clear()
      ..addAll(snapshot.transitions.map((transition) => TimelineTransition(
        type: transition.type, at: transition.at, duration: transition.duration,
      )));
    selectedEffectClipIndex = selectedEffectClipIndex < effectClips.length
        ? selectedEffectClipIndex : -1;
    selectedTransitionIndex = selectedTransitionIndex < timelineTransitions.length
        ? selectedTransitionIndex : -1;
  }

  void _reconcileTimelineAnnotations() {
    if (videoClips.isEmpty) {
      effectClips.clear();
      timelineTransitions.clear();
      selectedEffectClipIndex = -1;
      selectedTransitionIndex = -1;
      return;
    }

    final end = _timelineEndSeconds;
    effectClips.removeWhere((effect) => effect.start >= end - 0.001);
    for (final effect in effectClips) {
      if (effect.end > end) effect.end = end;
    }
    effectClips.removeWhere((effect) => effect.end <= effect.start + 0.05);

    timelineTransitions.removeWhere((transition) {
      final maximum = _maxTransitionDurationAt(transition.at);
      if (maximum < 0.1) return true;
      if (transition.duration > maximum) transition.duration = maximum;
      return false;
    });
    if (selectedEffectClipIndex >= effectClips.length) selectedEffectClipIndex = -1;
    if (selectedTransitionIndex >= timelineTransitions.length) selectedTransitionIndex = -1;
  }

  void _performTimelineEdit(VoidCallback update) {
    final before = _captureTimelineSnapshot();
    setState(() {
      update();
      _reconcileTimelineAnnotations();
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
    setState(() {
      selectedAudioClip = true;
      selectedEffectClipIndex = -1;
      selectedTransitionIndex = -1;
      selectedPhotoOverlay = -1;
      _selectedCanvasObject = 'audio';
    });
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
          selectedAudioClip = false;
          _selectedCanvasObject = 'video';
          status = 'Звуковой клип удалён. Видеоклипы не изменены.';
          break;
      }
    });
  }

  Future<void> showClipMenu(Offset position, int index) async {
    if (index < 0 || index >= videoClips.length) return;
    _selectVideoClip(index);
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
  Future<void> addTimelineEffect([String? selectedType]) async {
    if (videoClips.isEmpty || busy) {
      setStatus('Сначала добавьте видео на таймлайн.');
      return;
    }
    final type = selectedType ?? await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Добавить эффект на таймлайн'),
        children: [
          for (final value in _timelineEffectTypes)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(value),
              child: Text(value),
            ),
        ],
      ),
    );
    if (!mounted || type == null) return;
    final length = math.min(2.0, timelineSeconds).toDouble();
    if (length < 0.25) {
      setStatus('Недостаточно места на таймлайне для эффекта.');
      return;
    }
    final start = TimelineEditing.findAvailableEffectStart(
      effects: effectClips.map((item) => TimelineEffectRange(item.type, item.start, item.end)).toList(),
      preferred: playheadSeconds,
      length: length,
      timelineEnd: timelineSeconds,
    );
    if (start == null) {
      setStatus('На таймлайне нет свободного участка для нового эффекта. Переместите или растяните существующий эффект.');
      return;
    }
    _performTimelineEdit(() {
      effectClips.add(TimelineEffectClip(type: type, start: start, end: start + length));
      selectedEffectClipIndex = effectClips.length - 1;
      selectedTransitionIndex = -1;
      selectedAudioClip = false;
      selectedPhotoOverlay = -1;
      _selectedCanvasObject = 'timeline-effect';
      status = 'Эффект «$type» добавлен на свободный участок таймлайна.';
    });
  }

  Future<void> addTimelineTransition([String? selectedType]) async {
    if (videoClips.length < 2 || busy) {
      setStatus('Для перехода нужны два видеоклипа на таймлайне.');
      return;
    }
    final clips = List<TimelineClip>.of(videoClips)..sort((a, b) => a.timelineStart.compareTo(b.timelineStart));
    final joins = <({double at, TimelineClip left, TimelineClip right})>[];
    for (var i = 1; i < clips.length; i++) {
      final previous = clips[i - 1];
      final next = clips[i];
      if ((previous.timelineEnd - next.timelineStart).abs() <= 0.025) {
        joins.add((at: next.timelineStart, left: previous, right: next));
      }
    }
    if (joins.isEmpty) {
      setStatus('Переход можно поставить только на стык двух клипов без разрыва.');
      return;
    }
    joins.sort((a, b) => (a.at - playheadSeconds).abs().compareTo((b.at - playheadSeconds).abs()));
    final join = joins.first;
    final type = selectedType ?? await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Переход на ${time(Duration(milliseconds: (join.at * 1000).round()))}'),
        children: [
          for (final value in _timelineTransitionTypes)
            SimpleDialogOption(onPressed: () => Navigator.of(dialogContext).pop(value), child: Text(value)),
        ],
      ),
    );
    if (!mounted || type == null) return;
    final limit = math.min(join.left.length / 2, join.right.length / 2);
    if (limit < 0.1) {
      setStatus('Эти клипы слишком короткие для перехода. Увеличьте их длину.');
      return;
    }
    final length = math.min(0.6, limit).toDouble();
    _performTimelineEdit(() {
      final existing = timelineTransitions.indexWhere((item) => (item.at - join.at).abs() <= 0.025);
      final transition = TimelineTransition(type: type, at: join.at, duration: length);
      if (existing >= 0) {
        timelineTransitions[existing] = transition;
        selectedTransitionIndex = existing;
      } else {
        timelineTransitions.add(transition);
        selectedTransitionIndex = timelineTransitions.length - 1;
      }
      selectedEffectClipIndex = -1;
      selectedAudioClip = false;
      selectedPhotoOverlay = -1;
      _selectedCanvasObject = 'timeline-transition';
      status = 'Переход «$type» добавлен между видеоклипами.';
    });
  }

  double _maxTransitionDurationAt(double at) {
    final ordered = List<TimelineClip>.of(videoClips)..sort((a, b) => a.timelineStart.compareTo(b.timelineStart));
    for (var i = 1; i < ordered.length; i++) {
      final left = ordered[i - 1];
      final right = ordered[i];
      if ((left.timelineEnd - at).abs() <= 0.025 && (right.timelineStart - at).abs() <= 0.025) {
        return math.min(5.0, math.min(left.length / 2, right.length / 2)).toDouble();
      }
    }
    return 0.0;
  }

  Future<void> showEffectClipMenu(Offset position, int index) async {
    if (index < 0 || index >= effectClips.length) return;
    setState(() {
      selectedEffectClipIndex = index;
      selectedTransitionIndex = -1;
      selectedAudioClip = false;
      selectedPhotoOverlay = -1;
      _selectedCanvasObject = 'timeline-effect';
    });
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: const [
        PopupMenuItem(value: 'longer', child: Text('Увеличить на 1 секунду')),
        PopupMenuItem(value: 'shorter', child: Text('Уменьшить на 1 секунду')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'delete', child: Text('Удалить эффект')),
      ],
    );
    if (!mounted || action == null || index >= effectClips.length) return;
    _performTimelineEdit(() {
      final effect = effectClips[index];
      if (action == 'delete') {
        effectClips.removeAt(index);
        selectedEffectClipIndex = -1;
        status = 'Эффект удалён с таймлайна.';
      } else {
        final ranges = effectClips
            .map((item) => TimelineEffectRange(item.type, item.start, item.end))
            .toList();
        final requested = action == 'longer' ? effect.end + 1 : effect.end - 1;
        final resized = TimelineEditing.resizeEffectEdge(
          effects: ranges,
          index: index,
          requestedTime: requested,
          timelineEnd: timelineSeconds,
          resizeStart: false,
        );
        effect
          ..start = resized.start
          ..end = resized.end;
        status = action == 'longer'
            ? 'Длительность эффекта увеличена без перекрытия соседних эффектов.'
            : 'Длительность эффекта уменьшена.';
      }
    });
  }

  Future<void> showTimelineTransitionMenu(Offset position, int index) async {
    if (index < 0 || index >= timelineTransitions.length) return;
    setState(() {
      selectedTransitionIndex = index;
      selectedEffectClipIndex = -1;
      selectedAudioClip = false;
      selectedPhotoOverlay = -1;
      _selectedCanvasObject = 'timeline-transition';
    });
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: const [
        PopupMenuItem(value: 'change', child: Text('Изменить переход')),
        PopupMenuItem(value: 'shorter', child: Text('Короче')),
        PopupMenuItem(value: 'longer', child: Text('Длиннее')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'delete', child: Text('Удалить переход')),
      ],
    );
    if (!mounted || action == null || index >= timelineTransitions.length) return;
    if (action == 'change') {
      final type = await showDialog<String>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Тип перехода'),
          children: [
            for (final value in _timelineTransitionTypes)
              SimpleDialogOption(onPressed: () => Navigator.of(dialogContext).pop(value), child: Text(value)),
          ],
        ),
      );
      if (!mounted || type == null) return;
      _performTimelineEdit(() { timelineTransitions[index].type = type; status = 'Тип перехода изменён на «$type».'; });
      return;
    }
    _performTimelineEdit(() {
      if (action == 'delete') {
        timelineTransitions.removeAt(index);
        selectedTransitionIndex = -1;
        status = 'Переход удалён.';
      } else {
        final transition = timelineTransitions[index];
        final maxDuration = _maxTransitionDurationAt(transition.at);
        transition.duration = action == 'longer'
            ? math.min(maxDuration, transition.duration + 0.1).toDouble()
            : math.max(0.1, transition.duration - 0.1).toDouble();
        status = 'Длительность перехода изменена.';
      }
    });
  }

  void _startEffectClipMove(int index) {
    if (_timelinePanPointer != null || index < 0 || index >= effectClips.length) return;
    _effectClipMoveBefore = _captureTimelineSnapshot();
    _effectClipMoveIndex = index;
    _effectClipMoveStart = effectClips[index].start;
    _effectClipMovePointerX = 0;
    setState(() {
      selectedEffectClipIndex = index;
      selectedTransitionIndex = -1;
      selectedAudioClip = false;
      selectedPhotoOverlay = -1;
      _selectedCanvasObject = 'timeline-effect';
    });
  }

  void _updateEffectClipMove(DragUpdateDetails details) {
    if (_timelinePanPointer != null || _effectClipMoveIndex < 0 || _effectClipMoveIndex >= effectClips.length) return;
    _effectClipMovePointerX += details.delta.dx;
    final effect = effectClips[_effectClipMoveIndex];
    final length = effect.duration;
    final desiredStart = _effectClipMoveStart + _effectClipMovePointerX / zoom;
    final nextStart = TimelineEditing.findAvailableEffectStart(
      effects: effectClips.map((item) => TimelineEffectRange(item.type, item.start, item.end)).toList(),
      preferred: desiredStart,
      length: length,
      timelineEnd: timelineSeconds,
      ignoreIndex: _effectClipMoveIndex,
    );
    if (nextStart == null) return;
    setState(() {
      effect.start = nextStart;
      effect.end = nextStart + length;
      projectDirty = true;
    });
  }

  void _startEffectResize(int index, {required bool fromLeft}) {
    if (_timelinePanPointer != null || index < 0 || index >= effectClips.length) return;
    final effect = effectClips[index];
    _effectResizeBefore = _captureTimelineSnapshot();
    _effectResizeIndex = index;
    _effectResizeLeft = fromLeft;
    _effectResizePointerX = 0;
    _effectResizeStart = effect.start;
    _effectResizeEnd = effect.end;
    setState(() {
      selectedEffectClipIndex = index;
      selectedTransitionIndex = -1;
      selectedAudioClip = false;
      selectedPhotoOverlay = -1;
      _selectedCanvasObject = 'timeline-effect';
    });
  }

  void _updateEffectResize(DragUpdateDetails details) {
    if (_timelinePanPointer != null) return;
    final index = _effectResizeIndex;
    if (index < 0 || index >= effectClips.length) return;
    _effectResizePointerX += details.delta.dx;
    final requested = (_effectResizeLeft ? _effectResizeStart : _effectResizeEnd) +
        _effectResizePointerX / zoom;
    final ranges = effectClips
        .map((item) => TimelineEffectRange(item.type, item.start, item.end))
        .toList();
    final resized = TimelineEditing.resizeEffectEdge(
      effects: ranges,
      index: index,
      requestedTime: requested,
      timelineEnd: timelineSeconds,
      resizeStart: _effectResizeLeft,
    );
    setState(() {
      effectClips[index]
        ..start = resized.start
        ..end = resized.end;
      projectDirty = true;
    });
  }

  void _finishEffectResize() {
    final before = _effectResizeBefore;
    if (before != null) {
      _timelineHistory.record(before: before, after: _captureTimelineSnapshot());
    }
    _effectResizeBefore = null;
    _effectResizeIndex = -1;
  }

  void _finishEffectClipMove() {
    final before = _effectClipMoveBefore;
    if (before != null) _timelineHistory.record(before: before, after: _captureTimelineSnapshot());
    _effectClipMoveBefore = null;
    _effectClipMoveIndex = -1;
  }

  int _nearestClipIndexToPlayhead() {
    final active = _clipIndexAtTimelineTime(playheadSeconds);
    if (active >= 0) return active;
    if (videoClips.isEmpty) return -1;
    var nearest = 0;
    var nearestDistance = double.infinity;
    for (var i = 0; i < videoClips.length; i++) {
      final clip = videoClips[i];
      final distance = playheadSeconds < clip.timelineStart
          ? clip.timelineStart - playheadSeconds
          : playheadSeconds > clip.timelineEnd
              ? playheadSeconds - clip.timelineEnd
              : 0.0;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = i;
      }
    }
    return nearest;
  }

  void _selectVideoAtPlayhead() {
    final index = _nearestClipIndexToPlayhead();
    setState(() {
      _selectedCanvasObject = 'video';
      selectedPhotoOverlay = -1;
      selectedAudioClip = false;
      selectedEffectClipIndex = -1;
      selectedTransitionIndex = -1;
      if (index >= 0) selectedClipIndex = index;
    });
  }

  void _selectVideoClip(int index) {
    if (index < 0 || index >= videoClips.length) return;
    setState(() {
      selectedClipIndex = index;
      selectedPhotoOverlay = -1;
      selectedAudioClip = false;
      selectedEffectClipIndex = -1;
      selectedTransitionIndex = -1;
      inspectorTab = 'video';
      _selectedCanvasObject = 'video';
    });
  }

  void deleteSelectedTimelineItem({bool ripple = false}) {
    if (selectedEffectClipIndex >= 0 && selectedEffectClipIndex < effectClips.length) {
      final index = selectedEffectClipIndex;
      _performTimelineEdit(() {
        effectClips.removeAt(index);
        selectedEffectClipIndex = -1;
        _selectedCanvasObject = 'video';
        status = 'Выбранный эффект удалён.';
      });
      return;
    }
    if (selectedTransitionIndex >= 0 && selectedTransitionIndex < timelineTransitions.length) {
      final index = selectedTransitionIndex;
      _performTimelineEdit(() {
        timelineTransitions.removeAt(index);
        selectedTransitionIndex = -1;
        _selectedCanvasObject = 'video';
        status = 'Выбранный переход удалён.';
      });
      return;
    }
    if (selectedPhotoOverlay >= 0 && selectedPhotoOverlay < photoOverlays.length) {
      setState(() {
        photoOverlays.removeAt(selectedPhotoOverlay);
        selectedPhotoOverlay = -1;
        _selectedCanvasObject = 'video';
        projectDirty = true;
        status = 'Выбранное фото удалено.';
      });
      return;
    }
    if (selectedAudioClip && audioPath != null) {
      _performTimelineEdit(() {
        audioPath = null;
        audioDuration = Duration.zero;
        audioClipStart = 0;
        audioClipEnd = 0;
        audioWaveform = const [];
        selectedAudioClip = false;
        _selectedCanvasObject = 'video';
        status = 'Выбранный аудиоклип удалён.';
      });
      return;
    }
    deleteSelectedClip(ripple: ripple);
  }

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
    if (_timelinePanPointer != null || index < 0 || index >= videoClips.length) return;
    _clipMoveBefore = _captureTimelineSnapshot();
    _clipMoveIndex = index;
    _clipMoveOriginalStart = videoClips[index].timelineStart;
    _clipMovePointerX = 0;
    setState(() {
      selectedClipIndex = index;
      selectedPhotoOverlay = -1;
      selectedAudioClip = false;
      selectedEffectClipIndex = -1;
      selectedTransitionIndex = -1;
      _selectedCanvasObject = 'video';
      _timelineSnapAt = null;
    });
  }

  void _updateClipMove(DragUpdateDetails details) {
    if (_timelinePanPointer != null) return;
    final before = _clipMoveBefore;
    if (before == null || _clipMoveIndex < 0 ||
        _clipMoveIndex >= videoClips.length ||
        _clipMoveIndex >= before.videoClips.length) {
      return;
    }
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
    final sourceRange = before.videoClips[_clipMoveIndex];
    setState(() {
      final moving = videoClips[_clipMoveIndex];
      moving
        ..start = sourceRange.start
        ..end = sourceRange.end
        ..timelineStart = candidate;
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
    setState(() {
      _replaceClipRanges(next);
      _reconcileTimelineAnnotations();
      selectedClipIndex = selected;
      _activePlaybackClipIndex = selected;
      _timelineSnapAt = null;
      projectDirty = true;
      status = 'Клип перемещён. Ctrl+Z — отменить.';
    });
    _timelineHistory.record(before: before, after: _captureTimelineSnapshot());
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
    if (videoScaleX != 1.0 || videoScaleY != 1.0) {
      filters.add(
        'scale=iw*${videoScaleX.toStringAsFixed(3)}:ih*${videoScaleY.toStringAsFixed(3)}:flags=lanczos',
      );
    }
    if (videoRotation.abs() > 0.01) {
      filters.add(
        'rotate=${(videoRotation * math.pi / 180).toStringAsFixed(5)}:c=none:ow=rotw(iw):oh=roth(ih)',
      );
    }
    if (filtersEnabled) {
      filters.add(
        'eq=brightness=${brightness.toStringAsFixed(3)}:contrast=${contrast.toStringAsFixed(3)}:saturation=${saturation.toStringAsFixed(3)}',
      );
    }
    if (videoEffect != 'Оригинал' && _exportEffectFilter != 'null') {
      filters.add(_exportEffectFilter);
    }
    if (motionBlurEnabled) filters.add('tmix=frames=3:weights=1 1 1');

    for (final effect in effectClips) {
      final overlapStart = math.max(effect.start, clip.timelineStart).toDouble();
      final overlapEnd = math.min(effect.end, clip.timelineEnd).toDouble();
      if (overlapEnd <= overlapStart) continue;
      final localStart = (overlapStart - clip.timelineStart).clamp(0.0, clip.length).toDouble();
      final localEnd = (overlapEnd - clip.timelineStart).clamp(0.0, clip.length).toDouble();
      final filter = _effectExportFilter(effect.type);
      if (filter != 'null') {
        filters.add("$filter:enable='between(t,${localStart.toStringAsFixed(3)},${localEnd.toStringAsFixed(3)})'");
      }
    }
    if (transitionEffect != 'Нет' && videoClips.length > 1) {
      final durationForClip = math.min(transitionDuration, math.max(0.1, clip.length / 2)).toDouble();
      final color = transitionEffect == 'Белая вспышка' ? 'white' : 'black';
      final hasIncomingOverride = timelineTransitions.any((value) => (value.at - clip.timelineStart).abs() <= 0.025);
      final hasOutgoingOverride = timelineTransitions.any((value) => (value.at - clip.timelineEnd).abs() <= 0.025);
      if (index > 0 && !hasIncomingOverride) filters.add('fade=t=in:st=0:d=${durationForClip.toStringAsFixed(2)}:color=$color');
      if (index < videoClips.length - 1 && !hasOutgoingOverride) {
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
      final exportSegments = <ExportTimelineSegment>[];
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
        exportSegments.add(ExportTimelineSegment(path: gapPath, start: sequenceCursor, end: sequenceCursor + gapSeconds, isGap: true));
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

        final dimensions = const {
          '16:9': '1920:1080',
          '9:16': '1080:1920',
          '1:1': '1080:1080',
          '4:3': '1440:1080',
          '4:5': '864:1080',
          '3:2': '1620:1080',
        }[aspectRatioPreset] ?? '1920:1080';
        final dimensionParts = dimensions.split(':');
        final outputWidth = dimensionParts[0];
        final outputHeight = dimensionParts[1];
        final foregroundEffects = _buildExportVideoFilter(i, clip);
        final foregroundChain = foregroundEffects == 'null'
            ? 'format=rgba'
            : 'format=rgba,$foregroundEffects';
        final graph = <String>[
          '[0:v]split=2[fitSource][backdropSource]',
          '[backdropSource]scale=$outputWidth:$outputHeight:force_original_aspect_ratio=increase,'
              'crop=$outputWidth:$outputHeight,boxblur=26:12,'
              'eq=brightness=-0.30:saturation=0.82[backdrop]',
          '[fitSource]scale=$outputWidth:$outputHeight:force_original_aspect_ratio=decrease,'
              'pad=$outputWidth:$outputHeight:(ow-iw)/2:(oh-ih)/2:color=0x00000000,'
              'setsar=1,$foregroundChain[foreground]',
          '[backdrop][foreground]overlay=(W-w)/2:(H-h)/2:shortest=1[base0]',
        ];
        var previous = 'base0';
        for (var overlayIndex = 0;
            overlayIndex < photoOverlays.length;
            overlayIndex++) {
          final overlay = photoOverlays[overlayIndex];
          final inputIndex = overlayIndex + 1;
          final overlayLabel = 'ov$overlayIndex';
          final outputLabel = 'base${overlayIndex + 1}';
          final width = (360 * overlay.scale).round().clamp(24, 1800);
          final angle = (overlay.rotation * math.pi / 180).toStringAsFixed(5);
          graph.add(
            '[$inputIndex:v]scale=$width:-1,format=rgba,rotate=$angle:c=none,'
                'colorchannelmixer=aa=${overlay.opacity.toStringAsFixed(3)}[$overlayLabel]',
          );
          graph.add(
            '[$previous][$overlayLabel]overlay=x=(W-w)/2+(${overlay.x.toStringAsFixed(4)})*W:'
                'y=(H-h)/2+(${overlay.y.toStringAsFixed(4)})*H:shortest=1[$outputLabel]',
          );
          previous = outputLabel;
        }
        graph.add('[$previous]setsar=1,format=yuv420p[vout]');
        args.addAll([
          '-filter_complex',
          graph.join(';'),
          '-map',
          '[vout]',
          '-map',
          '0:a?',
        ]);

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
        exportSegments.add(ExportTimelineSegment(path: segmentPath, start: clip.timelineStart, end: clip.timelineEnd, isGap: false));
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
      final useTransitionGraph = timelineTransitions.isNotEmpty && exportSegments.length > 1;
      if (!useTransitionGraph) {
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
      } else {
        final graph = <String>[];
        final args = <String>['-hide_banner', '-y'];
        for (var i = 0; i < exportSegments.length; i++) {
          args.addAll(['-i', exportSegments[i].path]);
          graph.add(
            '[$i:v]settb=AVTB,setpts=PTS-STARTPTS,fps=${frameRate.toStringAsFixed(3)},format=yuv420p[v$i]',
          );
          if (sourceHasAudio) graph.add('[$i:a]asetpts=PTS-STARTPTS[a$i]');
        }

        var activeVideo = 'v0';
        var activeAudio = 'a0';
        var accumulatedDuration = exportSegments.first.duration;
        for (var i = 1; i < exportSegments.length; i++) {
          final previousSegment = exportSegments[i - 1];
          final currentSegment = exportSegments[i];
          TimelineTransition? transition;
          if (!previousSegment.isGap &&
              !currentSegment.isGap &&
              (previousSegment.end - currentSegment.start).abs() <= 0.025) {
            for (final candidate in timelineTransitions) {
              if ((candidate.at - currentSegment.start).abs() <= 0.025) {
                transition = candidate;
                break;
              }
            }
          }

          final durationForTransition = transition == null
              ? 0.0
              : math.min(
                  transition.duration,
                  math.min(previousSegment.duration / 2, currentSegment.duration / 2),
                ).toDouble();
          final canTransition = transition != null && durationForTransition >= 0.05;
          final videoOutput = 'vjoin$i';
          final audioOutput = 'ajoin$i';
          if (canTransition) {
            final name = _transitionFilterName(transition.type);
            final offset = math.max(0.0, accumulatedDuration - durationForTransition).toDouble();
            graph.add(
              '[$activeVideo][v$i]xfade=transition=$name:duration=${durationForTransition.toStringAsFixed(3)}:offset=${offset.toStringAsFixed(3)}[$videoOutput]',
            );
            if (sourceHasAudio) {
              graph.add(
                '[$activeAudio][a$i]acrossfade=d=${durationForTransition.toStringAsFixed(3)}:c1=tri:c2=tri[$audioOutput]',
              );
            }
            accumulatedDuration += currentSegment.duration - durationForTransition;
          } else {
            graph.add('[$activeVideo][v$i]concat=n=2:v=1:a=0[$videoOutput]');
            if (sourceHasAudio) {
              graph.add('[$activeAudio][a$i]concat=n=2:v=0:a=1[$audioOutput]');
            }
            accumulatedDuration += currentSegment.duration;
          }
          activeVideo = videoOutput;
          if (sourceHasAudio) activeAudio = audioOutput;
        }

        final graphOutputArgs = <String>[
          ...args,
          '-filter_complex',
          graph.join(';'),
          '-map',
          '[$activeVideo]',
          if (sourceHasAudio) ...[
            '-map',
            '[$activeAudio]',
            '-c:a',
            'aac',
            '-b:a',
            '192k',
            '-ac',
            '2',
            '-ar',
            '44100',
          ],
          '-r',
          frameRate.toStringAsFixed(3),
        ];
        var joinResult = await Process.run(ffmpeg, [
          ...graphOutputArgs,
          ..._videoEncoderArguments(encoder),
          '-movflags',
          '+faststart',
          joinedVideo,
        ]);
        if (joinResult.exitCode != 0 && encoder != 'libx264') {
          joinResult = await Process.run(ffmpeg, [
            ...graphOutputArgs,
            ..._videoEncoderArguments('libx264'),
            '-movflags',
            '+faststart',
            joinedVideo,
          ]);
        }
        if (joinResult.exitCode != 0 || !await File(joinedVideo).exists()) {
          throw Exception(joinResult.stderr.toString().split('\n').last);
        }
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
    if (samples.isEmpty || size.width <= 0 || size.height <= 0) return;

    final peak = samples.reduce((a, b) => a > b ? a : b);
    if (peak <= 0) return;
    final count = math.min(samples.length, (size.width / 2.2).floor());
    if (count <= 0) return;

    final center = size.height / 2;
    final waveformPaint = Paint()
      ..color = color.withValues(alpha: 0.98)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    final peakPaint = Paint()
      ..color = const Color(0xFFD9FFF3).withValues(alpha: 0.72)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < count; i++) {
      final sampleIndex = (i * samples.length / count)
          .floor()
          .clamp(0, samples.length - 1)
          .toInt();
      final raw = (samples[sampleIndex] / peak).clamp(0.0, 1.0);
      // Normalize quiet recordings and compress their dynamic range so
      // bass hits and quieter passages remain visible on the timeline.
      final boosted = math.pow(raw, 0.58).toDouble();
      final halfHeight = math.max(1.2, boosted * size.height * 0.43).toDouble();
      final x = (i + 0.5) * size.width / count;
      canvas.drawLine(
        Offset(x, center - halfHeight),
        Offset(x, center + halfHeight),
        waveformPaint,
      );
      if (boosted > 0.78) {
        canvas.drawLine(
          Offset(x, center - halfHeight),
          Offset(x, center + halfHeight),
          peakPaint,
        );
      }
    }

    canvas.drawLine(
      Offset(0, center),
      Offset(size.width, center),
      Paint()
        ..color = color.withValues(alpha: 0.20)
        ..strokeWidth = 0.7,
    );
  }

  @override
  bool shouldRepaint(covariant WaveformPainter old) =>
      old.color != color || !identical(old.samples, samples);
}