import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void main() => runApp(const AudioCutterApp());

class AudioCutterApp extends StatelessWidget {
  const AudioCutterApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Audio Cutter',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
          useMaterial3: true,
        ),
        home: const CutterPage(),
      );
}

class CutterPage extends StatefulWidget {
  const CutterPage({super.key});

  @override
  State<CutterPage> createState() => _CutterPageState();
}

class _CutterPageState extends State<CutterPage> {
  String? _video;
  String _format = 'mp3';
  final _start = TextEditingController(text: '0');
  final _end = TextEditingController();
  String _status = 'Выберите видео, укажите фрагмент и сохраните аудио.';
  bool _busy = false;

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );
    if (picked == null || picked.files.single.path == null) return;
    setState(() {
      _video = picked.files.single.path!;
      _status = 'Выбрано: ${p.basename(_video!)}';
    });
  }

  String _quote(String s) => '"${s.replaceAll('"', r'\"')}"';

  Future<void> _export() async {
    final video = _video;
    final start = double.tryParse(_start.text.trim());
    final endText = _end.text.trim();
    final end = endText.isEmpty ? null : double.tryParse(endText);
    if (video == null) {
      setState(() => _status = 'Сначала выберите видео.');
      return;
    }
    if (start == null || start < 0 || (endText.isNotEmpty && end == null) ||
        (end != null && end <= start)) {
      setState(() => _status = 'Укажите корректное время в секундах.');
      return;
    }

    setState(() {
      _busy = true;
      _status = 'Обработка аудио…';
    });

    try {
      final dir = await getApplicationDocumentsDirectory();
      final ext = _format;
      final base = p.basenameWithoutExtension(video)
          .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final output = p.join(
        dir.path,
        '${base}_audio_${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      final args = <String>['-y', '-ss', start.toStringAsFixed(3), '-i', video];
      if (end != null) args.addAll(['-t', (end - start).toStringAsFixed(3)]);
      args.addAll(['-vn']);
      if (_format == 'mp3') {
        args.addAll(['-codec:a', 'libmp3lame', '-q:a', '2']);
      } else if (_format == 'm4a') {
        args.addAll(['-codec:a', 'aac', '-b:a', '192k', '-f', 'ipod']);
      } else {
        args.addAll(['-codec:a', 'pcm_s16le', '-f', 'wav']);
      }
      args.add(output);

        final session = await FFmpegKit.execute(args.map(_quote).join(' '));
        final code = await session.getReturnCode();
        if (!ReturnCode.isSuccess(code)) {
          throw Exception('FFmpeg не смог обработать файл. Проверьте формат видео и поддержку кодеков.');
        }
      if (mounted) setState(() => _status = 'Готово! Файл сохранён:\n$output');
    } catch (e) {
      if (mounted) setState(() => _status = 'Ошибка: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Audio Cutter')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                const Icon(Icons.audio_file_rounded, size: 68),
                const SizedBox(height: 12),
                Text('Извлечение и обрезка звука',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickVideo,
                  icon: const Icon(Icons.video_file_outlined),
                  label: Text(_video == null ? 'Выбрать видео' : p.basename(_video!)),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _format,
                  decoration: const InputDecoration(
                    labelText: 'Формат аудио',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'mp3', child: Text('MP3')),
                    DropdownMenuItem(value: 'm4a', child: Text('M4A / AAC')),
                    DropdownMenuItem(value: 'wav', child: Text('WAV')),
                  ],
                  onChanged: _busy ? null : (v) => setState(() => _format = v ?? 'mp3'),
                ),
                const SizedBox(height: 16),
                const Text('Время начала и конца в секундах. Конец можно оставить пустым.'),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(
                    controller: _start,
                    enabled: !_busy,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Начало', suffixText: 'сек', border: OutlineInputBorder()),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(
                    controller: _end,
                    enabled: !_busy,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Конец', suffixText: 'сек', border: OutlineInputBorder()),
                  )),
                ]),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _busy ? null : _export,
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.content_cut),
                  label: Text(_busy ? 'Обработка…' : 'Извлечь и сохранить'),
                ),
                const SizedBox(height: 18),
                SelectableText(_status),
                const SizedBox(height: 12),
                const Text(
                  'Результат сохраняется в папку документов приложения. Для Windows нужен ffmpeg.exe в PATH. Перед распространением проверьте поддержку платформ и лицензии FFmpeg.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
}
