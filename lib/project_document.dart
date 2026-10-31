import 'effect_catalog.dart';

import 'dart:convert';

/// Source-time range for a single video clip in a saved project.
class ProjectClipRange {
  const ProjectClipRange(this.start, this.end, {double? timelineStart})
      : timelineStart = timelineStart ?? start;

  final double start;
  final double end;
  final double timelineStart;

  double get length => end - start;
  double get timelineEnd => timelineStart + length;

  Map<String, Object> toJson() => <String, Object>{
        'start': start,
        'end': end,
        'timelineStart': timelineStart,
      };

  @override
  bool operator ==(Object other) =>
      other is ProjectClipRange &&
      other.start == start &&
      other.end == end &&
      other.timelineStart == timelineStart;

  @override
  int get hashCode => Object.hash(start, end, timelineStart);
}


/// A standalone effect block placed on the effects timeline track.
class ProjectEffectClip {
  const ProjectEffectClip({
    required this.type,
    required this.start,
    required this.end,
  });

  static const supportedTypes = builtinEffectTypes;

  final String type;
  final double start;
  final double end;

  double get duration => end - start;

  Map<String, Object> toJson() => <String, Object>{
        'type': type,
        'start': start,
        'end': end,
      };

  @override
  bool operator ==(Object other) =>
      other is ProjectEffectClip &&
      other.type == type &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(type, start, end);
}

/// A transition attached to the cut at [at] seconds on the sequence timeline.
class ProjectTransition {
  const ProjectTransition({
    required this.type,
    required this.at,
    required this.duration,
  });

  static final supportedTypes = builtinTransitionFilters.keys.toSet();

  final String type;
  final double at;
  final double duration;

  Map<String, Object> toJson() => <String, Object>{
        'type': type,
        'at': at,
        'duration': duration,
      };

  @override
  bool operator ==(Object other) =>
      other is ProjectTransition &&
      other.type == type &&
      other.at == at &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(type, at, duration);
}

/// A persistent image layer placed over the sequence canvas.
class ProjectPhotoOverlay {
  const ProjectPhotoOverlay({
    required this.path,
    this.x = 0,
    this.y = 0,
    this.scale = 1,
    this.rotation = 0,
    this.opacity = 1,
    this.start = 0,
    this.end = 3,
  });

  final String path;
  final double x;
  final double y;
  final double scale;
  final double rotation;
  final double opacity;
  final double start;
  final double end;

  Map<String, Object> toJson() => <String, Object>{
        'path': path,
        'x': x,
        'y': y,
        'scale': scale,
        'rotation': rotation,
        'opacity': opacity,
        'start': start,
        'end': end,
      };
}

/// Editable text/caption layer with sequence timing and canvas placement.
class ProjectTextOverlay {
  const ProjectTextOverlay({
    required this.text,
    required this.start,
    required this.end,
    this.x = 0,
    this.y = 0.28,
    this.fontSize = 42,
    this.color = '#FFFFFF',
    this.bold = true,
    this.opacity = 1,
  });

  final String text;
  final double start;
  final double end;
  final double x;
  final double y;
  final double fontSize;
  final String color;
  final bool bold;
  final double opacity;

  Map<String, Object> toJson() => <String, Object>{
        'text': text,
        'start': start,
        'end': end,
        'x': x,
        'y': y,
        'fontSize': fontSize,
        'color': color,
        'bold': bold,
        'opacity': opacity,
      };
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
    List<ProjectEffectClip> effectClips = const [],
    List<ProjectTransition> transitions = const [],
    List<ProjectPhotoOverlay> photoOverlays = const [],
    List<ProjectTextOverlay> textOverlays = const [],
  })  : videoClips = List<ProjectClipRange>.unmodifiable(videoClips),
        effectClips = List<ProjectEffectClip>.unmodifiable(effectClips),
        transitions = List<ProjectTransition>.unmodifiable(transitions),
        photoOverlays = List<ProjectPhotoOverlay>.unmodifiable(photoOverlays),
        textOverlays = List<ProjectTextOverlay>.unmodifiable(textOverlays) {
    _validate();
  }

  static const formatId = 'g3ficut-project';
  static const currentSchemaVersion = 4;

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
  final List<ProjectEffectClip> effectClips;
  final List<ProjectTransition> transitions;
  final List<ProjectPhotoOverlay> photoOverlays;
  final List<ProjectTextOverlay> textOverlays;

  void _validate() {
    if (format != formatId) {
      throw const FormatException('Неподдерживаемый формат файла проекта.');
    }
    if (schemaVersion != 1 && schemaVersion != 2 && schemaVersion != 3 && schemaVersion != currentSchemaVersion) {
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
          !_isFinite(clip.timelineStart) ||
          clip.start < 0 ||
          clip.end <= clip.start ||
          clip.timelineStart < 0) {
        throw FormatException('Некорректные границы видеоклипа ${i + 1}.');
      }
      if (videoDurationMs > 0 && clip.end * 1000 > videoDurationMs + 1) {
        throw FormatException('Видеоклип ${i + 1} выходит за длительность исходного видео.');
      }
    }

    for (var i = 0; i < effectClips.length; i++) {
      final effect = effectClips[i];
      if (!ProjectEffectClip.supportedTypes.contains(effect.type) ||
          !_isFinite(effect.start) ||
          !_isFinite(effect.end) ||
          effect.start < 0 ||
          effect.end <= effect.start ||
          (videoClips.isNotEmpty && effect.end > videoClips.map((clip) => clip.timelineEnd).reduce((a, b) => a > b ? a : b) + 0.001)) {
        throw FormatException('Некорректный эффект на таймлайне ${i + 1}.');
      }
    }
    for (var i = 0; i < transitions.length; i++) {
      final transition = transitions[i];
      if (!ProjectTransition.supportedTypes.contains(transition.type) ||
          !_isFinite(transition.at) ||
          !_isFinite(transition.duration) ||
          transition.at < 0 ||
          transition.duration < 0.1 ||
          transition.duration > 5) {
        throw FormatException('Некорректный переход ${i + 1}.');
      }
      final hasJoin = videoClips.any((left) => videoClips.any((right) =>
          (left.timelineEnd - transition.at).abs() < 0.025 &&
          (right.timelineStart - transition.at).abs() < 0.025 &&
          left.timelineStart != right.timelineStart));
      if (!hasJoin) {
        throw FormatException('Переход ${i + 1} не привязан к стыку двух видеоклипов.');
      }
    }

    for (var i = 0; i < photoOverlays.length; i++) {
      final overlay = photoOverlays[i];
      if (overlay.path.trim().isEmpty ||
          !_isFinite(overlay.x) ||
          !_isFinite(overlay.y) ||
          !_isFinite(overlay.scale) ||
          !_isFinite(overlay.rotation) ||
          !_isFinite(overlay.opacity) ||
          !_isFinite(overlay.start) ||
          !_isFinite(overlay.end) ||
          overlay.scale < 0.05 ||
          overlay.scale > 8 ||
          overlay.opacity < 0 ||
          overlay.opacity > 1 ||
          overlay.start < 0 ||
          overlay.end <= overlay.start) {
        throw FormatException('Некорректный слой фото ${i + 1}.');
      }
    }
    for (var i = 0; i < textOverlays.length; i++) {
      final overlay = textOverlays[i];
      if (overlay.text.trim().isEmpty ||
          !_isFinite(overlay.x) ||
          !_isFinite(overlay.y) ||
          !_isFinite(overlay.fontSize) ||
          !_isFinite(overlay.opacity) ||
          !_isFinite(overlay.start) ||
          !_isFinite(overlay.end) ||
          overlay.fontSize < 8 ||
          overlay.fontSize > 240 ||
          overlay.opacity < 0 ||
          overlay.opacity > 1 ||
          overlay.start < 0 ||
          overlay.end <= overlay.start ||
          !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(overlay.color)) {
        throw FormatException('Некорректный текстовый слой ${i + 1}.');
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

    if (schemaVersion == 1) {
      if (videoDurationMs > 0 && playheadMs > videoDurationMs) {
        throw const FormatException('Позиция курсора выходит за длительность видео.');
      }
    } else if (videoClips.isNotEmpty) {
      final sequenceEnd = videoClips
          .map((clip) => clip.timelineEnd)
          .reduce((left, right) => left > right ? left : right);
      if (playheadMs > sequenceEnd * 1000 + 1) {
        throw const FormatException('Позиция курсора выходит за длительность таймлайна.');
      }
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
        'effectClips': effectClips.map((effect) => effect.toJson()).toList(),
        'transitions': transitions.map((transition) => transition.toJson()).toList(),
        'photoOverlays': photoOverlays.map((overlay) => overlay.toJson()).toList(),
        'textOverlays': textOverlays.map((overlay) => overlay.toJson()).toList(),
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
      var legacyTimelineCursor = 0.0;
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
        final sourceStart = _readDouble(clipJson, 'start');
        final sourceEnd = _readDouble(clipJson, 'end');
        final timelineStart = schemaVersion == 1
            ? legacyTimelineCursor
            : (clipJson.containsKey('timelineStart')
                ? _readDouble(clipJson, 'timelineStart')
                : legacyTimelineCursor);
        clips.add(ProjectClipRange(
          sourceStart,
          sourceEnd,
          timelineStart: timelineStart,
        ));
        legacyTimelineCursor += sourceEnd - sourceStart;
      }

      List<ProjectEffectClip> readEffects() {
        final raw = json['effectClips'] ?? const [];
        if (raw is! List) throw const FormatException('Поле effectClips должно быть массивом.');
        return raw.asMap().entries.map((entry) {
          final value = entry.value;
          if (value is! Map) throw FormatException('Эффект ${entry.key + 1} должен быть объектом.');
          final map = <String, dynamic>{};
          for (final field in value.entries) {
            if (field.key is! String) throw const FormatException('Некорректные поля эффекта.');
            map[field.key as String] = field.value;
          }
          return ProjectEffectClip(
            type: _readString(map, 'type'),
            start: _readDouble(map, 'start'),
            end: _readDouble(map, 'end'),
          );
        }).toList();
      }

      List<ProjectTransition> readTransitions() {
        final raw = json['transitions'] ?? const [];
        if (raw is! List) throw const FormatException('Поле transitions должно быть массивом.');
        return raw.asMap().entries.map((entry) {
          final value = entry.value;
          if (value is! Map) throw FormatException('Переход ${entry.key + 1} должен быть объектом.');
          final map = <String, dynamic>{};
          for (final field in value.entries) {
            if (field.key is! String) throw const FormatException('Некорректные поля перехода.');
            map[field.key as String] = field.value;
          }
          return ProjectTransition(
            type: _readString(map, 'type'),
            at: _readDouble(map, 'at'),
            duration: _readDouble(map, 'duration'),
          );
        }).toList();
      }

      List<ProjectPhotoOverlay> readPhotoOverlays() {
        final raw = json['photoOverlays'] ?? const [];
        if (raw is! List) throw const FormatException('Поле photoOverlays должно быть массивом.');
        return raw.asMap().entries.map((entry) {
          final value = entry.value;
          if (value is! Map) throw FormatException('Слой фото ${entry.key + 1} должен быть объектом.');
          final map = <String, dynamic>{};
          for (final field in value.entries) {
            if (field.key is! String) throw const FormatException('Некорректные поля слоя фото.');
            map[field.key as String] = field.value;
          }
          return ProjectPhotoOverlay(
            path: _readString(map, 'path'),
            x: map.containsKey('x') ? _readDouble(map, 'x') : 0,
            y: map.containsKey('y') ? _readDouble(map, 'y') : 0,
            scale: map.containsKey('scale') ? _readDouble(map, 'scale') : 1,
            rotation: map.containsKey('rotation') ? _readDouble(map, 'rotation') : 0,
            opacity: map.containsKey('opacity') ? _readDouble(map, 'opacity') : 1,
            start: map.containsKey('start') ? _readDouble(map, 'start') : 0,
            end: map.containsKey('end') ? _readDouble(map, 'end') : 3,
          );
        }).toList();
      }

      List<ProjectTextOverlay> readTextOverlays() {
        final raw = json['textOverlays'] ?? const [];
        if (raw is! List) throw const FormatException('Поле textOverlays должно быть массивом.');
        return raw.asMap().entries.map((entry) {
          final value = entry.value;
          if (value is! Map) throw FormatException('Текстовый слой ${entry.key + 1} должен быть объектом.');
          final map = <String, dynamic>{};
          for (final field in value.entries) {
            if (field.key is! String) throw const FormatException('Некорректные поля текстового слоя.');
            map[field.key as String] = field.value;
          }
          final boldValue = map['bold'] ?? true;
          if (boldValue is! bool) throw const FormatException('Поле bold должно быть логическим.');
          final colorValue = map['color'] ?? '#FFFFFF';
          if (colorValue is! String) throw const FormatException('Поле color должно быть строкой.');
          return ProjectTextOverlay(
            text: _readString(map, 'text'),
            start: _readDouble(map, 'start'),
            end: _readDouble(map, 'end'),
            x: map.containsKey('x') ? _readDouble(map, 'x') : 0,
            y: map.containsKey('y') ? _readDouble(map, 'y') : 0.28,
            fontSize: map.containsKey('fontSize') ? _readDouble(map, 'fontSize') : 42,
            color: colorValue,
            bold: boldValue,
            opacity: map.containsKey('opacity') ? _readDouble(map, 'opacity') : 1,
          );
        }).toList();
      }

      final rawAudioPath = json['audioPath'];
      if (rawAudioPath != null && rawAudioPath is! String) {
        throw const FormatException('Поле audioPath должно быть строкой или null.');
      }

      return ProjectDocument(
        format: format,
        schemaVersion: schemaVersion < currentSchemaVersion ? currentSchemaVersion : schemaVersion,
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
        effectClips: readEffects(),
        transitions: readTransitions(),
        photoOverlays: readPhotoOverlays(),
        textOverlays: readTextOverlays(),
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
