import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
import 'project_document.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const G3fiCutApp());
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
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B75FF), brightness: Brightness.dark),
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
  TimelineClip({required this.start, required this.end});
  double start;
  double end;
  double get length => end - start;
}

class _EditorPageState extends State<EditorPage> {
  static const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.3.0');
  static const releaseApi = 'https://api.github.com/repos/G3fic/G3fiCut/releases/latest';

  static const panel = Color(0xFF171820);
  static const muted = Color(0xFF9295A7);
  static const accent = Color(0xFF8B75FF);
  static const videoBlue = Color(0xFF65AFFF);
  static const audioGreen = Color(0xFF36C6A3);

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
  double zoom = 32;
  final List<TimelineClip> videoClips = [];
  final TimelineHistory _timelineHistory = TimelineHistory();
  int selectedClipIndex = 0;
  double audioClipStart = 0;
  double audioClipEnd = 0;
  String status = 'Импортируйте видео, чтобы начать монтаж.';

  double get timelineSeconds => duration.inMilliseconds > 0 ? math.max(1, duration.inMilliseconds / 1000).toDouble() : 30;
  double get timelineWidth => math.max(720, timelineSeconds * zoom).toDouble();

  @override
  void initState() {
    super.initState();
    if (kReleaseMode && Platform.isWindows) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(checkForUpdates());
      });
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
        }
      }
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
      if (showNoUpdateMessage && mounted) {
        setStatus('Не удалось проверить обновления: ${e.toString().replaceFirst('Bad state: ', '')}');
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

    final created = Player();
    try {
      final controller = VideoController(created);
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
          setState(() => position = v);
          unawaited(_enforceEditedPlayback(v));
        }
      });
      playingSub = created.stream.playing.listen((v) {
        if (mounted && !_switchingMedia) setState(() => playing = v);
      });
      return created;
    } catch (_) {
      unawaited(created.dispose());
      rethrow;
    }
  }

  @override
  void dispose() {
    durationSub?.cancel();
    positionSub?.cancel();
    playingSub?.cancel();
    final activePlayer = player;
    if (activePlayer != null) unawaited(activePlayer.dispose());
    super.dispose();
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
      if (!mounted) return;
      setState(() {
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
          ..add(TimelineClip(start: 0, end: openedDuration.inMilliseconds / 1000));
        selectedClipIndex = 0;
        status = 'Видео загружено. Правый клик по клипу открывает монтажные инструменты.';
      });
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
      _switchingMediaDuration = null;
      if (mounted) {
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
        videoClips: videoClips.map((clip) => ProjectClipRange(clip.start, clip.end)).toList(),
        selectedClipIndex: videoClips.isEmpty ? 0 : selectedClipIndex.clamp(0, videoClips.length - 1).toInt(),
        audioPath: audioPath,
        audioDurationMs: audioPath == null ? 0 : audioDuration.inMilliseconds,
        audioClipStart: audioClipStart,
        audioClipEnd: audioClipEnd,
        timelineZoom: zoom,
        playheadMs: position.inMilliseconds.clamp(0, duration.inMilliseconds).toInt(),
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
      final restoredPosition = Duration(
        milliseconds: document.playheadMs.clamp(0, restoredDuration.inMilliseconds).toInt(),
      );
      _timelineHistory.clear();
      _switchingMedia = false;
      _switchingMediaDuration = null;
      if (!mounted) return;
      setState(() {
        videoPath = document.videoPath;
        duration = restoredDuration;
        videoClips
          ..clear()
          ..addAll(document.videoClips.map((clip) => TimelineClip(start: clip.start, end: clip.end)));
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
      try {
        await activePlayer.seek(restoredPosition);
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
      if (!mounted) return;
      _performTimelineEdit(() {
        audioPath = output;
        audioDuration = duration;
        audioClipStart = 0;
        audioClipEnd = duration.inMilliseconds / 1000;
        status = 'Готово: звук добавлен на отдельную дорожку. Его можно обрезать независимо от видео правым кликом.';
      });
    } on ProcessException {
      if (mounted) setState(() => status = 'FFmpeg не найден. В архиве из GitHub Actions ffmpeg.exe лежит рядом с GifCut.exe. Для локального запуска добавьте FFmpeg в PATH.');
    } catch (e) {
      if (mounted) setState(() => status = 'Ошибка извлечения звука: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void setStatus(String text) { if (mounted) setState(() => status = text); }
  Future<void> togglePlayback() async {
    final activePlayer = player;
    if (videoPath == null || activePlayer == null) return;
    if (playing) {
      await activePlayer.pause();
    } else {
      await activePlayer.play();
    }
  }

  Future<void> _enforceEditedPlayback(Duration value) async {
    final activePlayer = player;
    if (!mounted || _switchingMedia || _seekingAcrossCut || !playing ||
        activePlayer == null || videoPath == null) return;

    if (videoClips.isEmpty) {
      _seekingAcrossCut = true;
      try { await activePlayer.pause(); } finally { _seekingAcrossCut = false; }
      return;
    }

    final seconds = value.inMilliseconds / 1000;
    var currentIndex = -1;
    for (var i = 0; i < videoClips.length; i++) {
      final clip = videoClips[i];
      if (seconds >= clip.start - .02 && seconds < clip.end - .04) {
        currentIndex = i;
        break;
      }
    }

    double? jumpTo;
    if (currentIndex >= 0) {
      final clip = videoClips[currentIndex];
      if (seconds < clip.end - .07) return;
      if (currentIndex + 1 < videoClips.length) {
        jumpTo = videoClips[currentIndex + 1].start;
      } else {
        _seekingAcrossCut = true;
        try { await activePlayer.pause(); } finally { _seekingAcrossCut = false; }
        return;
      }
    } else {
      // If playback enters a removed section, jump to the next remaining clip.
      for (final clip in videoClips) {
        if (clip.start > seconds + .025) {
          jumpTo = clip.start;
          break;
        }
      }
      if (jumpTo == null) {
        final allPassed = videoClips.every((clip) => seconds >= clip.end - .04);
        if (allPassed) {
          _seekingAcrossCut = true;
          try { await activePlayer.pause(); } finally { _seekingAcrossCut = false; }
        }
        return;
      }
    }

    _seekingAcrossCut = true;
    try {
      await activePlayer.seek(Duration(milliseconds: (jumpTo! * 1000).round()));
    } finally {
      _seekingAcrossCut = false;
    }
  }

  void _startEdgeDrag(int index, bool left) {
    if (index < 0 || index >= videoClips.length) return;
    _edgeDragBefore = _captureTimelineSnapshot();
    _edgeDragIndex = index;
    _edgeDragLeft = left;
    _edgeDragOriginalEdge = left ? videoClips[index].start : videoClips[index].end;
    _edgeDragPointerX = 0;
    setState(() => selectedClipIndex = index);
  }

  void _updateEdgeDrag(DragUpdateDetails details) {
    if (_edgeDragIndex < 0 || _edgeDragIndex >= videoClips.length) return;
    _edgeDragPointerX += details.delta.dx;
    final clip = videoClips[_edgeDragIndex];
    final nextEdge = _edgeDragOriginalEdge + _edgeDragPointerX / zoom;
    setState(() {
      if (_edgeDragLeft) {
        clip.start = nextEdge.clamp(0.0, clip.end - .08).toDouble();
      } else {
        final sourceEnd = duration.inMilliseconds > 0
            ? duration.inMilliseconds / 1000
            : _edgeDragOriginalEdge + 3600;
        clip.end = nextEdge.clamp(clip.start + .08, math.max(clip.start + .08, sourceEnd)).toDouble();
      }
      projectDirty = true;
    });
  }

  void _finishEdgeDrag() {
    if (_edgeDragIndex < 0) return;
    final before = _edgeDragBefore;
    if (before != null) {
      _timelineHistory.record(before: before, after: _captureTimelineSnapshot());
    }
    _edgeDragBefore = null;
    _edgeDragIndex = -1;
    if (mounted) setState(() => status = 'Длина клипа изменена. Ctrl+Z — отменить.');
  }

  Future<void> seek(Duration target) async {
    final activePlayer = player;
    if (activePlayer == null || duration.inMilliseconds <= 0) return;
    final ms = target.inMilliseconds.clamp(0, duration.inMilliseconds).toInt();
    await activePlayer.seek(Duration(milliseconds: ms));
  }
  void setTimelineZoom(double next) {
    setState(() {
      zoom = next.clamp(8.0, 160.0).toDouble();
      projectDirty = true;
    });
  }

  void seekTimeline(double x) {
    if (duration.inMilliseconds <= 0) return;
    final seconds = (x / zoom).clamp(0.0, timelineSeconds);
    seek(Duration(milliseconds: (seconds * 1000).round()));
  }
  String time(Duration value) {
    final total = math.max(0, value.inSeconds);
    final h = total ~/ 3600;
    final m = ((total % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    if (h > 0) return '${h.toString().padLeft(2, '0')}:$m:$s';
    return '$m:$s';
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final keyboard = HardwareKeyboard.instance;
    final control = keyboard.isControlPressed;
    final key = event.logicalKey;
    if (control && key == LogicalKeyboardKey.keyZ) {
      if (keyboard.isShiftPressed) {
        redoTimelineEdit();
      } else {
        undoTimelineEdit();
      }
      return KeyEventResult.handled;
    }
    if (control && key == LogicalKeyboardKey.keyY) {
      redoTimelineEdit();
      return KeyEventResult.handled;
    }
    if (control && key == LogicalKeyboardKey.keyO) {
      if (keyboard.isShiftPressed) {
        unawaited(pickVideo());
      } else {
        unawaited(openProject());
      }
      return KeyEventResult.handled;
    }
    if (control && key == LogicalKeyboardKey.keyS) {
      if (keyboard.isShiftPressed) {
        saveProject(saveAs: true);
      } else {
        saveProject();
      }
      return KeyEventResult.handled;
    }
    if (control && key == LogicalKeyboardKey.keyE) {
      unawaited(extractAudio());
      return KeyEventResult.handled;
    }
    if (control && (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.add || key == LogicalKeyboardKey.numpadAdd)) {
      setTimelineZoom(zoom + 4);
      return KeyEventResult.handled;
    }
    if (control && (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract)) {
      setTimelineZoom(zoom - 4);
      return KeyEventResult.handled;
    }
    if (control && key == LogicalKeyboardKey.keyB) {
      splitSelectedClip();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      deleteSelectedClip();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      unawaited(togglePlayback());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      unawaited(seek(position - const Duration(seconds: 5)));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      unawaited(seek(position + const Duration(seconds: 5)));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      unawaited(seek(Duration.zero));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      unawaited(seek(duration));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              topBar(),
              const Divider(height: 1),
              toolbar(),
              const Divider(height: 1),
              Expanded(child: Row(children: [mediaPanel(), const VerticalDivider(width: 1), Expanded(child: previewPanel()), const VerticalDivider(width: 1), inspectorPanel()])),
              const Divider(height: 1),
              timelinePanel(),
              const Divider(height: 1),
              statusBar(),
            ],
          ),
        ),
      ));

  Widget topBar() => Container(
        height: 52,
        color: panel,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(children: [
          Container(width: 32, height: 32, decoration: BoxDecoration(color: accent.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(9)), child: const Icon(Icons.movie_creation_outlined, color: accent, size: 20)),
          const SizedBox(width: 10),
          const Text('GifCut', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(width: 22),
          Text((projectFilePath == null ? 'Новый проект' : p.basenameWithoutExtension(projectFilePath!)) + (projectDirty ? ' •' : ''), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFFD3D3DF))),
          const Spacer(),
          IconButton(
            tooltip: checkingForUpdates ? 'Проверка обновлений…' : 'Проверить обновления',
            visualDensity: VisualDensity.compact,
            onPressed: checkingForUpdates ? null : () => unawaited(checkForUpdates(showNoUpdateMessage: true)),
            icon: checkingForUpdates
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.system_update_alt, size: 18, color: muted),
          ),
          const Icon(Icons.desktop_windows_outlined, size: 16, color: muted),
          const SizedBox(width: 8),
          const Text('DESKTOP BETA', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget toolbar() => Container(
        constraints: const BoxConstraints(minHeight: 58),
        color: const Color(0xFF14151C),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(onPressed: busy ? null : openProject, icon: const Icon(Icons.folder_open_outlined, size: 18), label: const Text('Открыть проект')),
            OutlinedButton.icon(onPressed: videoPath == null || busy ? null : () async { await saveProject(); }, icon: const Icon(Icons.save_outlined, size: 18), label: const Text('Сохранить')),
            OutlinedButton.icon(onPressed: videoPath == null || busy ? null : () async { await saveProject(saveAs: true); }, icon: const Icon(Icons.drive_file_rename_outline, size: 18), label: const Text('Сохранить как…')),
            OutlinedButton.icon(onPressed: busy ? null : pickVideo, icon: const Icon(Icons.add_to_photos_outlined, size: 18), label: const Text('Импорт видео')),
            FilledButton.icon(
              onPressed: videoPath == null || busy ? null : extractAudio,
              icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.graphic_eq, size: 18),
              label: Text(busy ? 'Обработка…' : 'Извлечь звук на таймлайн'),
            ),
            OutlinedButton.icon(onPressed: videoClips.isEmpty || busy ? null : exportEditedVideo, icon: const Icon(Icons.ios_share, size: 18), label: const Text('Экспорт')),
            Tooltip(
              message: 'Отменить (Ctrl+Z)',
              child: OutlinedButton.icon(
                onPressed: _timelineHistory.canUndo ? undoTimelineEdit : null,
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Отменить'),
              ),
            ),
            Tooltip(
              message: 'Повторить (Ctrl+Y, Ctrl+Shift+Z)',
              child: OutlinedButton.icon(
                onPressed: _timelineHistory.canRedo ? redoTimelineEdit : null,
                icon: const Icon(Icons.redo, size: 18),
                label: const Text('Повторить'),
              ),
            ),
            if (audioPath != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(color: audioGreen.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8), border: Border.all(color: audioGreen.withValues(alpha: 0.35))),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle_outline, color: audioGreen, size: 15),
                  SizedBox(width: 6),
                  Text('Аудио на таймлайне', style: TextStyle(color: audioGreen, fontSize: 11, fontWeight: FontWeight.w600)),
                ]),
              ),
          ],
        ),
      );

  Widget mediaPanel() => Container(
        width: 218,
        color: panel,
        padding: const EdgeInsets.fromLTRB(12, 15, 12, 12),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('МЕДИА', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            InkWell(
              onTap: busy ? null : pickVideo,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
                decoration: BoxDecoration(color: const Color(0xFF20212B), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF333542))),
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
              mediaItem(Icons.movie_outlined, p.basename(videoPath!), 'Видео', videoBlue),
              if (audioPath != null) ...[
                const SizedBox(height: 7),
                mediaItem(Icons.graphic_eq, p.basename(audioPath!), 'Извлечённое аудио', audioGreen),
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

  Widget mediaItem(IconData icon, String name, String kind, Color color) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: const Color(0xFF22242F), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF343644))),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text(kind, style: const TextStyle(color: muted, fontSize: 10)),
          ])),
        ]),
      );

  Widget previewPanel() => Container(
        color: const Color(0xFF111218),
        child: Column(children: [
          Container(
            height: 39,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(color: Color(0xFF171820), border: Border(bottom: BorderSide(color: Color(0xFF292B36)))),
            child: Row(children: [
              const Text('ПРЕДПРОСМОТР', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(videoPath == null ? 'Нет клипа' : p.basename(videoPath!), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFB8B8C6), fontSize: 11)),
            ]),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              color: const Color(0xFF0B0C10),
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
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Video(controller: videoController!, controls: NoVideoControls),
                        ),
            ),
          ),
          Container(
            height: 63,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(color: Color(0xFF171820), border: Border(top: BorderSide(color: Color(0xFF292B36)))),
            child: Row(children: [
              Text(time(position), style: const TextStyle(fontSize: 11, color: Color(0xFFD7D7E3))),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5), overlayShape: const RoundSliderOverlayShape(overlayRadius: 11)),
                  child: Slider(
                    value: duration.inMilliseconds > 0 ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0).toDouble() : 0,
                    onChanged: duration.inMilliseconds > 0 ? (v) => seek(Duration(milliseconds: (duration.inMilliseconds * v).round())) : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(time(duration), style: const TextStyle(fontSize: 11, color: muted)),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: playing ? 'Пауза' : 'Воспроизвести',
                onPressed: videoPath == null ? null : togglePlayback,
                icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 21),
                visualDensity: VisualDensity.compact,
              ),
            ]),
          ),
        ]),
      );

  Widget inspectorPanel() => Container(
        width: 238,
        color: panel,
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('СВОЙСТВА', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            const Text('Текущий проект', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            property('Видео', videoPath == null ? 'Не выбрано' : 'Загружено'),
            property('Длительность', time(duration)),
            property('Аудиодорожка', audioPath == null ? 'Не создана' : 'Добавлена'),
            const SizedBox(height: 18),
            const Divider(),
            const SizedBox(height: 12),
            const Text('АУДИО', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
            const SizedBox(height: 9),
            if (audioPath == null)
              const Text('После извлечения звук появится здесь и на отдельной дорожке таймлайна.', style: TextStyle(color: muted, fontSize: 11, height: 1.5))
            else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: audioGreen.withValues(alpha: 0.09), border: Border.all(color: audioGreen.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(8)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.graphic_eq, color: audioGreen, size: 20),
                  const SizedBox(height: 7),
                  Text(p.basename(audioPath!), maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text('WAV · ${time(audioDuration)}', style: const TextStyle(color: audioGreen, fontSize: 10)),
                ]),
              ),
              const SizedBox(height: 8),
              const Text('Файл сохранён в Documents/GifCut/Media.', style: TextStyle(color: muted, fontSize: 10, height: 1.4)),
            ],
            const SizedBox(height: 14),
            const Text('ГОРЯЧИЕ КЛАВИШИ', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            shortcutRow('Пробел', 'Воспроизведение / пауза'),
            shortcutRow('← / →', 'Назад / вперёд на 5 секунд'),
            shortcutRow('Home / End', 'Начало / конец видео'),
            shortcutRow('Ctrl + O', 'Импортировать видео'),
            shortcutRow('Ctrl + E', 'Извлечь аудио'),
            shortcutRow('Ctrl + B', 'Разделить клип'),
            shortcutRow('Delete', 'Удалить выбранный клип'),
            shortcutRow('Ctrl + + / −', 'Масштаб таймлайна'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFF22232D), borderRadius: BorderRadius.circular(8)),
              child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.construction_outlined, size: 17, color: accent),
                SizedBox(width: 8),
                Expanded(child: Text('Монтаж: разделение, обрезка краёв, удаление фрагментов и экспорт через FFmpeg.', style: TextStyle(color: Color(0xFFB6B7C5), fontSize: 10, height: 1.45))),
              ]),
            ),
          ]),
        ),
      );

  Widget shortcutRow(String keys, String description) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 82, child: Text(keys, style: const TextStyle(color: Color(0xFFD5D1FF), fontSize: 10, fontWeight: FontWeight.w700))),
          Expanded(child: Text(description, style: const TextStyle(color: muted, fontSize: 10, height: 1.35))),
        ]),
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
        height: (MediaQuery.sizeOf(context).height * 0.38).clamp(210.0, 276.0).toDouble(),
        color: const Color(0xFF14151B),
        child: Column(children: [
          Container(
            height: 43,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(color: Color(0xFF191A22), border: Border(bottom: BorderSide(color: Color(0xFF292B36)))),
            child: Row(children: [
              const Icon(Icons.view_timeline_outlined, size: 17, color: accent),
              const SizedBox(width: 8),
              const Text('ТАЙМЛАЙН', style: TextStyle(fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
              const SizedBox(width: 12),
              Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4), decoration: BoxDecoration(color: const Color(0xFF292A36), borderRadius: BorderRadius.circular(5)), child: const Text('V1', style: TextStyle(fontSize: 9, color: Color(0xFFB8B6D4), fontWeight: FontWeight.w800))),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Отменить (Ctrl+Z)',
                visualDensity: VisualDensity.compact,
                onPressed: undoTimelineEdit,
                icon: const Icon(Icons.undo_rounded, size: 17),
              ),
              IconButton(
                tooltip: 'Повторить (Ctrl+Y)',
                visualDensity: VisualDensity.compact,
                onPressed: redoTimelineEdit,
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
              IconButton(tooltip: 'Уменьшить масштаб', visualDensity: VisualDensity.compact, onPressed: () => setTimelineZoom(zoom - 4), icon: const Icon(Icons.remove, size: 17)),
              SizedBox(width: 48, child: Text('${zoom.toInt()} px/s', textAlign: TextAlign.center, style: const TextStyle(color: muted, fontSize: 10))),
              IconButton(tooltip: 'Увеличить масштаб', visualDensity: VisualDensity.compact, onPressed: () => setTimelineZoom(zoom + 4), icon: const Icon(Icons.add, size: 17)),
            ]),
          ),
          Expanded(
            child: Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  final next = event.scrollDelta.dy < 0 ? zoom + 4 : zoom - 4;
                  setTimelineZoom(next);
                }
              },
              child: SingleChildScrollView(
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
                ]),
              ),
              ),
            ),
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
                    left: videoClips[i].start * zoom + 4,
                    top: 7,
                    bottom: 7,
                    width: math.max(12.0, videoClips[i].length * zoom - 2).toDouble(),
                    child: GestureDetector(
                      onTap: () => setState(() { selectedClipIndex = i; projectDirty = true; }),
                      onSecondaryTapDown: (details) => showClipMenu(details.globalPosition, i),
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
                            child: ClipRRect(borderRadius: BorderRadius.circular(5), child: CustomPaint(
                              painter: const VideoStripPainter(),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                color: const Color(0x442D76B8),
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
                            )),
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
                                    child: Center(child: Container(width: 2, height: 16, color: Color(0xFF6551D9))),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 0, top: 0, bottom: 0, width: 9,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.resizeLeftRight,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onHorizontalDragStart: (_) => _startEdgeDrag(i, false),
                                  onHorizontalDragUpdate: _updateEdgeDrag,
                                  onHorizontalDragEnd: (_) => _finishEdgeDrag(),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFF1EDFF),
                                      borderRadius: BorderRadius.horizontal(right: Radius.circular(5)),
                                    ),
                                    child: Center(child: Container(width: 2, height: 16, color: Color(0xFF6551D9))),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              Positioned(left: playhead, top: 0, bottom: 0, width: 2, child: Container(color: const Color(0xFFFF5E7D))),
              Positioned(left: (playhead - 4).clamp(0.0, timelineWidth - 10).toDouble(), top: 0, width: 10, height: 8, child: const DecoratedBox(decoration: BoxDecoration(color: Color(0xFFFF5E7D), borderRadius: BorderRadius.only(bottomLeft: Radius.circular(3), bottomRight: Radius.circular(3))))),
            ]),
          ),
        ),
      ]),
    );
  }

  TimelineSnapshot _captureTimelineSnapshot() => TimelineSnapshot(
        videoClips: videoClips.map((clip) => TimelineClipRange(clip.start, clip.end)).toList(),
        selectedClipIndex: selectedClipIndex,
        audioPath: audioPath,
        audioClipStart: audioClipStart,
        audioClipEnd: audioClipEnd,
      );

  void _restoreTimelineSnapshot(TimelineSnapshot snapshot) {
    videoClips
      ..clear()
      ..addAll(snapshot.videoClips.map((clip) => TimelineClip(start: clip.start, end: clip.end)));
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
        PopupMenuItem(value: 'duplicate', child: ListTile(dense: true, leading: Icon(Icons.copy_outlined), title: Text('Дублировать клип'))),
        PopupMenuItem(value: 'delete', child: ListTile(dense: true, leading: Icon(Icons.delete_outline, color: Colors.redAccent), title: Text('Удалить клип'))),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'split': splitSelectedClip(); break;
      case 'trimStart': trimSelectedStart(); break;
      case 'trimEnd': trimSelectedEnd(); break;
      case 'duplicate': duplicateSelectedClip(); break;
      case 'delete': deleteSelectedClip(); break;
    }
  }

  double get playheadSeconds => (position.inMilliseconds / 1000).clamp(0.0, timelineSeconds).toDouble();

  void splitSelectedClip() {
    if (selectedClipIndex < 0 || selectedClipIndex >= videoClips.length) return;
    final clip = videoClips[selectedClipIndex];
    final cut = playheadSeconds;
    if (cut <= clip.start + .08 || cut >= clip.end - .08) {
      setStatus('Поставьте курсор внутрь выбранного клипа, минимум за 0,08 с от края.');
      return;
    }
    _performTimelineEdit(() {
      final right = TimelineClip(start: cut, end: clip.end);
      clip.end = cut;
      videoClips.insert(selectedClipIndex + 1, right);
      selectedClipIndex++;
      status = 'Клип разделён в ${time(position)}.';
    });
  }

  void trimSelectedStart() {
    if (selectedClipIndex < 0 || selectedClipIndex >= videoClips.length) return;
    final clip = videoClips[selectedClipIndex];
    final cut = playheadSeconds;
    if (cut <= clip.start || cut >= clip.end - .08) {
      setStatus('Курсор должен находиться внутри выбранного клипа.');
      return;
    }
    _performTimelineEdit(() { clip.start = cut; status = 'Начало клипа обрезано до ${time(position)}.'; });
  }

  void trimSelectedEnd() {
    if (selectedClipIndex < 0 || selectedClipIndex >= videoClips.length) return;
    final clip = videoClips[selectedClipIndex];
    final cut = playheadSeconds;
    if (cut <= clip.start + .08 || cut >= clip.end) {
      setStatus('Курсор должен находиться внутри выбранного клипа.');
      return;
    }
    _performTimelineEdit(() { clip.end = cut; status = 'Конец клипа обрезан по ${time(position)}.'; });
  }

  void duplicateSelectedClip() {
    if (selectedClipIndex < 0 || selectedClipIndex >= videoClips.length) return;
    final clip = videoClips[selectedClipIndex];
    _performTimelineEdit(() {
      videoClips.insert(selectedClipIndex + 1, TimelineClip(start: clip.start, end: clip.end));
      selectedClipIndex++;
      status = 'Клип продублирован на таймлайне.';
    });
  }

  void deleteSelectedClip() {
    if (videoClips.isEmpty || selectedClipIndex < 0 || selectedClipIndex >= videoClips.length) return;
    _performTimelineEdit(() {
      videoClips.removeAt(selectedClipIndex);
      selectedClipIndex = videoClips.isEmpty ? 0 : selectedClipIndex.clamp(0, videoClips.length - 1).toInt();
      status = videoClips.isEmpty ? 'На таймлайне нет видеоклипов.' : 'Клип удалён с таймлайна.';
    });
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
    setState(() { busy = true; status = 'Экспортирую ${videoClips.length} фрагмент(ов)…'; });
    Directory? temp;
    try {
      temp = await Directory.systemTemp.createTemp('gifcut-export-');
      final listFile = File(p.join(temp.path, 'concat.txt'));
      final lines = <String>[];
      for (var i = 0; i < videoClips.length; i++) {
        final clip = videoClips[i];
        final segmentPath = p.join(temp.path, 'segment_${i.toString().padLeft(3, '0')}.mp4');
        final args = [
          '-hide_banner', '-y', '-ss', clip.start.toStringAsFixed(3), '-i', source,
          '-t', clip.length.toStringAsFixed(3), '-c:v', 'libx264', '-preset', 'veryfast',
          '-crf', '18', '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart', segmentPath,
        ];
        final result = await Process.run(await findFfmpeg(), args);
        if (result.exitCode != 0 || !await File(segmentPath).exists()) {
          throw Exception('Не удалось обработать фрагмент ${i + 1}: ${result.stderr.toString().split('\n').last}');
        }
        lines.add("file '${segmentPath.replaceAll('\\', '/')}'");
      }
      await listFile.writeAsString(lines.join('\n'));
      final joinedVideo = audioPath == null ? savePath : p.join(temp.path, 'joined_video.mp4');
      final concatResult = await Process.run(await findFfmpeg(), [
        '-hide_banner', '-y', '-f', 'concat', '-safe', '0', '-i', listFile.path,
        '-c', 'copy', '-movflags', '+faststart', joinedVideo,
      ]);
      if (concatResult.exitCode != 0) throw Exception(concatResult.stderr.toString().split('\n').last);

      // When a detached audio clip exists, apply its own trim range during export.
      // It replaces the source audio without changing the video edit decisions.
      final detachedAudio = audioPath;
      if (detachedAudio != null && audioClipEnd > audioClipStart) {
        final audioResult = await Process.run(await findFfmpeg(), [
          '-hide_banner', '-y',
          '-i', joinedVideo,
          '-ss', audioClipStart.toStringAsFixed(3), '-t', (audioClipEnd - audioClipStart).toStringAsFixed(3), '-i', detachedAudio,
          '-map', '0:v:0', '-map', '1:a:0',
          '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart',
          savePath,
        ]);
        if (audioResult.exitCode != 0) throw Exception(audioResult.stderr.toString().split('\n').last);
      }
      if (mounted) setState(() => status = 'Экспорт завершён: $savePath');
    } catch (e) {
      if (mounted) setState(() => status = 'Ошибка экспорта: $e');
    } finally {
      if (temp != null && await temp.exists()) await temp.delete(recursive: true);
      if (mounted) setState(() => busy = false);
    }
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
          painter: const WaveformPainter(color: audioGreen),
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
  const WaveformPainter({required this.color});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF163E37));
    final count = (size.width / 5).floor();
    final paint = Paint()..color = color.withValues(alpha: 0.92)..strokeWidth = 2..strokeCap = StrokeCap.round;
    final center = size.height / 2;
    for (var i = 0; i < count; i++) {
      final wave = (math.sin(i * 0.47) * 0.48 + math.cos(i * 0.19) * 0.3 + math.sin(i * 0.09) * 0.22).abs();
      final h = math.max(3.0, wave * size.height * 0.72);
      final x = i * 5.0 + 2;
      canvas.drawLine(Offset(x, center - h / 2), Offset(x, center + h / 2), paint);
    }
  }
  @override
  bool shouldRepaint(covariant WaveformPainter old) => old.color != color;
}
