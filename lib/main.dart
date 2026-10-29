import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const ClipForgeApp());
}

class ClipForgeApp extends StatelessWidget {
  const ClipForgeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ClipForge',
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

class _EditorPageState extends State<EditorPage> {
  static const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.2.0');
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
  Duration duration = Duration.zero;
  Duration audioDuration = Duration.zero;
  Duration position = Duration.zero;
  bool playing = false;
  bool busy = false;
  bool checkingForUpdates = false;
  double zoom = 32;
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

  Future<void> checkForUpdates({bool showNoUpdateMessage = false}) async {
    if (checkingForUpdates) return;
    setState(() => checkingForUpdates = true);

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..userAgent = 'ClipForge/$appVersion';
    try {
      final request = await client.getUrl(Uri.parse(releaseApi)).timeout(const Duration(seconds: 15));
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode == HttpStatus.notFound) {
        throw StateError('GitHub Releases пока недоступны. Репозиторий должен быть публичным и содержать опубликованный релиз.');
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('GitHub вернул HTTP ${response.statusCode}.');
      }

      final responseBody = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 20));
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic>) throw const FormatException('Некорректный ответ GitHub Releases.');

      final latestTag = decoded['tag_name'] as String?;
      if (latestTag == null || latestTag.trim().isEmpty) {
        throw const FormatException('В ответе GitHub не найдена версия релиза.');
      }
      final latestVersion = latestTag.replaceFirst(RegExp(r'^[vV]'), '');
      if (!isVersionNewer(latestVersion, appVersion)) {
        if (showNoUpdateMessage && mounted) setStatus('Установлена последняя версия ClipForge $appVersion.');
        return;
      }

      final assets = decoded['assets'];
      if (assets is! List) throw const FormatException('В релизе не найден список файлов.');
      Map<String, dynamic>? installerAsset;
      final expectedName = 'ClipForge-Setup-$latestVersion.exe';
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
        throw const FormatException('Ссылка на установщик не принадлежит официальным GitHub Releases ClipForge.');
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
          title: const Text('Доступно обновление ClipForge'),
          content: Text(
            'Установлена версия $appVersion. Доступна версия $latestVersion.\n\n'
            'ClipForge скачает установщик из GitHub, проверит файл и запустит установку. '
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
      ..userAgent = 'ClipForge/$appVersion';
    File? installer;
    try {
      if (mounted) setStatus('Скачиваю обновление v$version…');
      final tempDir = await Directory.systemTemp.createTemp('clipforge-update-');
      installer = File(p.join(tempDir.path, 'ClipForge-Setup-$version.exe'));
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
        if (mounted) setState(() => duration = v);
      });
      positionSub = created.stream.position.listen((v) {
        if (mounted) setState(() => position = v);
      });
      playingSub = created.stream.playing.listen((v) {
        if (mounted) setState(() => playing = v);
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

    setState(() {
      busy = true;
      videoPath = path;
      audioPath = null;
      audioDuration = Duration.zero;
      duration = Duration.zero;
      position = Duration.zero;
      playing = false;
      status = 'Загрузка видео…';
    });

    try {
      final activePlayer = ensurePlayer();
      await activePlayer.stop();
      await activePlayer.open(Media(path), play: false);
      if (!mounted) return;
      setState(() {
        duration = activePlayer.state.duration;
        status = 'Видео загружено. Нажмите «Извлечь звук», чтобы создать дорожку ниже видео.';
      });
    } catch (e) {
      if (mounted) setState(() => status = 'Не удалось открыть видео: $e');
    } finally {
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
      final outDir = Directory(p.join(docs.path, 'ClipForge', 'Media'));
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
      setState(() {
        audioPath = output;
        audioDuration = duration;
        status = 'Готово: извлечённый звук добавлен на отдельную дорожку под видео.';
      });
    } on ProcessException {
      if (mounted) setState(() => status = 'FFmpeg не найден. В архиве из GitHub Actions ffmpeg.exe лежит рядом с ClipForge.exe. Для локального запуска добавьте FFmpeg в PATH.');
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

  Future<void> seek(Duration target) async {
    final activePlayer = player;
    if (activePlayer == null || duration.inMilliseconds <= 0) return;
    final ms = target.inMilliseconds.clamp(0, duration.inMilliseconds).toInt();
    await activePlayer.seek(Duration(milliseconds: ms));
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
    if (control && key == LogicalKeyboardKey.keyO) {
      unawaited(pickVideo());
      return KeyEventResult.handled;
    }
    if (control && key == LogicalKeyboardKey.keyE) {
      unawaited(extractAudio());
      return KeyEventResult.handled;
    }
    if (control && (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.add || key == LogicalKeyboardKey.numpadAdd)) {
      setState(() => zoom = math.min(80, zoom + 4).toDouble());
      return KeyEventResult.handled;
    }
    if (control && (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract)) {
      setState(() => zoom = math.max(12, zoom - 4).toDouble());
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
          const Text('ClipForge', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(width: 22),
          const Text('Новый проект', style: TextStyle(fontSize: 12, color: Color(0xFFD3D3DF))),
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
            OutlinedButton.icon(onPressed: busy ? null : pickVideo, icon: const Icon(Icons.add_to_photos_outlined, size: 18), label: const Text('Импорт видео')),
            FilledButton.icon(
              onPressed: videoPath == null || busy ? null : extractAudio,
              icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.graphic_eq, size: 18),
              label: Text(busy ? 'Обработка…' : 'Извлечь звук на таймлайн'),
            ),
            OutlinedButton.icon(onPressed: null, icon: const Icon(Icons.ios_share, size: 18), label: const Text('Экспорт')),
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
              const Text('Файл сохранён в Documents/ClipForge/Media.', style: TextStyle(color: muted, fontSize: 10, height: 1.4)),
            ],
            const SizedBox(height: 14),
            const Text('ГОРЯЧИЕ КЛАВИШИ', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            shortcutRow('Пробел', 'Воспроизведение / пауза'),
            shortcutRow('← / →', 'Назад / вперёд на 5 секунд'),
            shortcutRow('Home / End', 'Начало / конец видео'),
            shortcutRow('Ctrl + O', 'Импортировать видео'),
            shortcutRow('Ctrl + E', 'Извлечь аудио'),
            shortcutRow('Ctrl + + / −', 'Масштаб таймлайна'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFF22232D), borderRadius: BorderRadius.circular(8)),
              child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.construction_outlined, size: 17, color: accent),
                SizedBox(width: 8),
                Expanded(child: Text('MVP: импорт, просмотр, воспроизведение и извлечение звука. Остальные инструменты добавим позже.', style: TextStyle(color: Color(0xFFB6B7C5), fontSize: 10, height: 1.45))),
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
        height: 276,
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
              const Spacer(),
              IconButton(tooltip: 'Уменьшить масштаб', visualDensity: VisualDensity.compact, onPressed: () => setState(() => zoom = math.max(12, zoom - 4).toDouble()), icon: const Icon(Icons.remove, size: 17)),
              SizedBox(width: 48, child: Text('${zoom.toInt()} px/s', textAlign: TextAlign.center, style: const TextStyle(color: muted, fontSize: 10))),
              IconButton(tooltip: 'Увеличить масштаб', visualDensity: VisualDensity.compact, onPressed: () => setState(() => zoom = math.min(80, zoom + 4).toDouble()), icon: const Icon(Icons.add, size: 17)),
            ]),
          ),
          Expanded(
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
        ]),
      );

  Widget trackRow({required bool audio}) {
    final path = audio ? audioPath : videoPath;
    final color = audio ? audioGreen : videoBlue;
    final clipDuration = audio ? audioDuration : duration;
    final wantedWidth = clipDuration.inMilliseconds > 0 ? clipDuration.inMilliseconds / 1000 * zoom : 180.0;
    final clipWidth = math.min(timelineWidth - 8, math.max(150.0, wantedWidth)).toDouble();
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
              if (path != null)
                Positioned(left: 4, top: 7, bottom: 7, width: clipWidth, child: audio ? audioClip(path) : videoClip(path)),
              Positioned(left: playhead, top: 0, bottom: 0, width: 2, child: Container(color: const Color(0xFFFF5E7D))),
              Positioned(left: (playhead - 4).clamp(0.0, timelineWidth - 10).toDouble(), top: 0, width: 10, height: 8, child: const DecoratedBox(decoration: BoxDecoration(color: Color(0xFFFF5E7D), borderRadius: BorderRadius.only(bottomLeft: Radius.circular(3), bottomRight: Radius.circular(3))))),
            ]),
          ),
        ),
      ]),
    );
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
          const Text('ClipForge $appVersion · Windows', style: TextStyle(color: Color(0xFF676A7A), fontSize: 9)),
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
