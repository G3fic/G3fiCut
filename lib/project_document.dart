import 'dart:convert';

/// Source-time range for a single video clip in a saved project.
class ProjectClipRange {
  const ProjectClipRange(this.start, this.end);

  final double start;
  final double end;

  double get length => end - start;

  Map<String, Object> toJson() => <String, Object>{
        'start': start,
        'end': end,
      };

  @override
  bool operator ==(Object other) =>
      other is ProjectClipRange &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Versioned, validated representation of a GifCut editing project.
///
/// Media paths are deliberately persisted as local absolute paths for schema
/// version 1. Relative paths and relinking are reserved for a future schema.
class ProjectDocument {
  ProjectDocument({
    this.format = formatId,
    this.schemaVersion = currentSchemaVersion,
    required this.appVersion,
    required this.videoPath,
    required this.videoDurationMs,
    required List<ProjectClipRange> videoClips,
    required this.selectedClipIndex,
    required this.audioPath,
    required this.audioDurationMs,
    required this.audioClipStart,
    required this.audioClipEnd,
    required this.timelineZoom,
    required this.playheadMs,
  }) : videoClips = List<ProjectClipRange>.unmodifiable(videoClips) {
    _validate();
  }

  static const formatId = 'g3ficut-project';
  static const currentSchemaVersion = 1;

  final String format;
  final int schemaVersion;
  final String appVersion;
  final String videoPath;
  final int videoDurationMs;
  final List<ProjectClipRange> videoClips;
  final int selectedClipIndex;
  final String? audioPath;
  final int audioDurationMs;
  final double audioClipStart;
  final double audioClipEnd;
  final double timelineZoom;
  final int playheadMs;

  void _validate() {
    if (format != formatId) {
      throw const FormatException('Неподдерживаемый формат файла проекта.');
    }
    if (schemaVersion != currentSchemaVersion) {
      throw FormatException('Версия формата проекта $schemaVersion не поддерживается.');
    }
    if (appVersion.trim().isEmpty) {
      throw const FormatException('В проекте не указана версия приложения.');
    }
    if (videoPath.trim().isEmpty) {
      throw const FormatException('В проекте не указан путь к видео.');
    }
    if (videoDurationMs < 0 || audioDurationMs < 0 || playheadMs < 0) {
      throw const FormatException('Длительность и позиция не могут быть отрицательными.');
    }
    if (!_isFinite(timelineZoom) || timelineZoom < 8 || timelineZoom > 160) {
      throw const FormatException('Масштаб таймлайна должен быть в диапазоне 8–160.');
    }
    if (!_isFinite(audioClipStart) || !_isFinite(audioClipEnd)) {
      throw const FormatException('Границы аудиоклипа должны быть конечными числами.');
    }

    if (videoClips.isEmpty) {
      if (selectedClipIndex != 0) {
        throw const FormatException('Для пустого таймлайна индекс выбранного клипа должен быть равен 0.');
      }
    } else if (selectedClipIndex < 0 || selectedClipIndex >= videoClips.length) {
      throw const FormatException('Индекс выбранного видеоклипа находится вне таймлайна.');
    }

    for (var i = 0; i < videoClips.length; i++) {
      final clip = videoClips[i];
      if (!_isFinite(clip.start) ||
          !_isFinite(clip.end) ||
          clip.start < 0 ||
          clip.end <= clip.start) {
        throw FormatException('Некорректные границы видеоклипа ${i + 1}.');
      }
      if (videoDurationMs > 0 && clip.end * 1000 > videoDurationMs + 1) {
        throw FormatException('Видеоклип ${i + 1} выходит за длительность исходного видео.');
      }
    }

    final path = audioPath;
    if (path == null) {
      if (audioDurationMs != 0 || audioClipStart != 0 || audioClipEnd != 0) {
        throw const FormatException('Данные аудио должны быть обнулены, если аудиодорожки нет.');
      }
    } else {
      if (path.trim().isEmpty) {
        throw const FormatException('Путь к аудиофайлу не может быть пустым.');
      }
      if (audioClipStart < 0 || audioClipEnd < audioClipStart) {
        throw const FormatException('Некорректные границы аудиоклипа.');
      }
      if (audioDurationMs > 0 && audioClipEnd * 1000 > audioDurationMs + 1) {
        throw const FormatException('Аудиоклип выходит за длительность аудиофайла.');
      }
    }

    if (videoDurationMs > 0 && playheadMs > videoDurationMs) {
      throw const FormatException('Позиция курсора выходит за длительность видео.');
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'format': format,
        'schemaVersion': schemaVersion,
        'appVersion': appVersion,
        'videoPath': videoPath,
        'videoDurationMs': videoDurationMs,
        'videoClips': videoClips.map((clip) => clip.toJson()).toList(),
        'selectedClipIndex': selectedClipIndex,
        'audioPath': audioPath,
        'audioDurationMs': audioDurationMs,
        'audioClipStart': audioClipStart,
        'audioClipEnd': audioClipEnd,
        'timelineZoom': timelineZoom,
        'playheadMs': playheadMs,
      };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory ProjectDocument.fromJson(Map<String, dynamic> json) {
    try {
      final format = _readString(json, 'format');
      final schemaVersion = _readInt(json, 'schemaVersion');
      final appVersion = _readString(json, 'appVersion');
      final videoPath = _readString(json, 'videoPath');
      final videoDurationMs = _readInt(json, 'videoDurationMs');
      final selectedClipIndex = _readInt(json, 'selectedClipIndex');
      final rawClips = json['videoClips'];
      if (rawClips is! List) {
        throw const FormatException('Поле videoClips должно быть массивом.');
      }
      final clips = <ProjectClipRange>[];
      for (var i = 0; i < rawClips.length; i++) {
        final rawClip = rawClips[i];
        if (rawClip is! Map) {
          throw FormatException('Видеоклип ${i + 1} должен быть объектом.');
        }
        final clipJson = <String, dynamic>{};
        for (final entry in rawClip.entries) {
          if (entry.key is! String) {
            throw FormatException('Некорректные поля видеоклипа ${i + 1}.');
          }
          clipJson[entry.key as String] = entry.value;
        }
        clips.add(ProjectClipRange(
          _readDouble(clipJson, 'start'),
          _readDouble(clipJson, 'end'),
        ));
      }

      final rawAudioPath = json['audioPath'];
      if (rawAudioPath != null && rawAudioPath is! String) {
        throw const FormatException('Поле audioPath должно быть строкой или null.');
      }

      return ProjectDocument(
        format: format,
        schemaVersion: schemaVersion,
        appVersion: appVersion,
        videoPath: videoPath,
        videoDurationMs: videoDurationMs,
        videoClips: clips,
        selectedClipIndex: selectedClipIndex,
        audioPath: rawAudioPath as String?,
        audioDurationMs: _readInt(json, 'audioDurationMs'),
        audioClipStart: _readDouble(json, 'audioClipStart'),
        audioClipEnd: _readDouble(json, 'audioClipEnd'),
        timelineZoom: _readDouble(json, 'timelineZoom'),
        playheadMs: _readInt(json, 'playheadMs'),
      );
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Не удалось прочитать файл проекта: $error');
    }
  }

  static ProjectDocument decode(String source) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException('Файл проекта содержит некорректный JSON.');
    }
    if (decoded is! Map) {
      throw const FormatException('Корнем файла проекта должен быть JSON-объект.');
    }
    final json = <String, dynamic>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String) {
        throw const FormatException('Поля проекта должны иметь строковые имена.');
      }
      json[entry.key as String] = entry.value;
    }
    return ProjectDocument.fromJson(json);
  }

  static String _readString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Поле $key должно быть непустой строкой.');
    }
    return value;
  }

  static int _readInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! int) {
      throw FormatException('Поле $key должно быть целым числом.');
    }
    return value;
  }

  static double _readDouble(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! num) {
      throw FormatException('Поле $key должно быть числом.');
    }
    final number = value.toDouble();
    if (!_isFinite(number)) {
      throw FormatException('Поле $key должно быть конечным числом.');
    }
    return number;
  }

  static bool _isFinite(double value) => value.isFinite;
}
