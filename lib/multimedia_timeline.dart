/// First-class multi-media timeline model for GifCut.
///
/// This model is deliberately independent from the legacy single-source
/// ProjectDocument so the editor can migrate incrementally without breaking
/// existing projects. It is the persistence contract for schema-v4 projects.
import 'dart:convert';

enum TimelineMediaKind { video, image, audio }

enum TimelineTrackKind { video, image, audio, text, effects }

class TimelineAsset {
  const TimelineAsset({
    required this.id,
    required this.path,
    required this.kind,
    this.name = '',
    this.durationMs = 0,
    this.width = 0,
    this.height = 0,
  });

  final String id;
  final String path;
  final TimelineMediaKind kind;
  final String name;
  final int durationMs;
  final int width;
  final int height;

  Map<String, Object?> toJson() => {
    'id': id, 'path': path, 'kind': kind.name, 'name': name,
    'durationMs': durationMs, 'width': width, 'height': height,
  };

  factory TimelineAsset.fromJson(Map<String, dynamic> json) => TimelineAsset(
    id: _string(json, 'id'),
    path: _string(json, 'path'),
    kind: TimelineMediaKind.values.byName(_string(json, 'kind')),
    name: json['name'] is String ? json['name'] as String : '',
    durationMs: _integer(json, 'durationMs', fallback: 0),
    width: _integer(json, 'width', fallback: 0),
    height: _integer(json, 'height', fallback: 0),
  );
}

class TimelineTrack {
  const TimelineTrack({
    required this.id,
    required this.kind,
    required this.name,
    this.muted = false,
    this.locked = false,
    this.visible = true,
  });

  final String id;
  final TimelineTrackKind kind;
  final String name;
  final bool muted;
  final bool locked;
  final bool visible;

  Map<String, Object?> toJson() => {
    'id': id, 'kind': kind.name, 'name': name,
    'muted': muted, 'locked': locked, 'visible': visible,
  };

  factory TimelineTrack.fromJson(Map<String, dynamic> json) => TimelineTrack(
    id: _string(json, 'id'),
    kind: TimelineTrackKind.values.byName(_string(json, 'kind')),
    name: _string(json, 'name'),
    muted: json['muted'] == true,
    locked: json['locked'] == true,
    visible: json['visible'] != false,
  );
}

class TimelineClip {
  const TimelineClip({
    required this.id,
    required this.trackId,
    required this.startMs,
    required this.durationMs,
    this.assetId,
    this.sourceStartMs = 0,
    this.text,
    this.textStyle = const {},
    this.x = 0.5,
    this.y = 0.5,
    this.scale = 1,
    this.rotation = 0,
    this.opacity = 1,
    this.volume = 1,
  });

  final String id;
  final String trackId;
  final String? assetId;
  final int startMs;
  final int sourceStartMs;
  final int durationMs;
  final String? text;
  final Map<String, Object?> textStyle;
  final double x;
  final double y;
  final double scale;
  final double rotation;
  final double opacity;
  final double volume;

  int get endMs => startMs + durationMs;

  Map<String, Object?> toJson() => {
    'id': id, 'trackId': trackId, 'assetId': assetId,
    'startMs': startMs, 'sourceStartMs': sourceStartMs,
    'durationMs': durationMs, 'text': text, 'textStyle': textStyle,
    'x': x, 'y': y, 'scale': scale, 'rotation': rotation,
    'opacity': opacity, 'volume': volume,
  };

  factory TimelineClip.fromJson(Map<String, dynamic> json) => TimelineClip(
    id: _string(json, 'id'),
    trackId: _string(json, 'trackId'),
    assetId: json['assetId'] as String?,
    startMs: _integer(json, 'startMs'),
    sourceStartMs: _integer(json, 'sourceStartMs', fallback: 0),
    durationMs: _integer(json, 'durationMs'),
    text: json['text'] as String?,
    textStyle: json['textStyle'] is Map
        ? Map<String, Object?>.from(json['textStyle'] as Map)
        : const {},
    x: _number(json, 'x', 0.5),
    y: _number(json, 'y', 0.5),
    scale: _number(json, 'scale', 1),
    rotation: _number(json, 'rotation', 0),
    opacity: _number(json, 'opacity', 1),
    volume: _number(json, 'volume', 1),
  );
}

class MultimediaTimelineDocument {
  MultimediaTimelineDocument({
    this.schemaVersion = 1,
    required List<TimelineAsset> assets,
    required List<TimelineTrack> tracks,
    required List<TimelineClip> clips,
  }) : assets = List.unmodifiable(assets),
       tracks = List.unmodifiable(tracks),
       clips = List.unmodifiable(clips) {
    validate();
  }

  final int schemaVersion;
  final List<TimelineAsset> assets;
  final List<TimelineTrack> tracks;
  final List<TimelineClip> clips;

  void validate() {
    if (schemaVersion != 1) {
      throw FormatException('Unsupported multimedia timeline schema: $schemaVersion');
    }
    _unique(assets.map((e) => e.id), 'asset');
    _unique(tracks.map((e) => e.id), 'track');
    _unique(clips.map((e) => e.id), 'clip');
    final assetById = {for (final asset in assets) asset.id: asset};
    final trackById = {for (final track in tracks) track.id: track};

    for (final asset in assets) {
      if (asset.id.trim().isEmpty || asset.path.trim().isEmpty ||
          asset.durationMs < 0 || asset.width < 0 || asset.height < 0) {
        throw const FormatException('Invalid media asset.');
      }
    }
    for (final track in tracks) {
      if (track.id.trim().isEmpty || track.name.trim().isEmpty) {
        throw const FormatException('Invalid timeline track.');
      }
    }
    for (final clip in clips) {
      final track = trackById[clip.trackId];
      if (clip.id.trim().isEmpty || track == null || clip.startMs < 0 ||
          clip.sourceStartMs < 0 || clip.durationMs <= 0 ||
          !clip.x.isFinite || !clip.y.isFinite || !clip.scale.isFinite ||
          clip.scale <= 0 || !clip.rotation.isFinite ||
          !clip.opacity.isFinite || clip.opacity < 0 || clip.opacity > 1 ||
          !clip.volume.isFinite || clip.volume < 0) {
        throw const FormatException('Invalid timeline clip.');
      }
      if (track.kind == TimelineTrackKind.text) {
        if (clip.text == null || clip.text!.trim().isEmpty || clip.assetId != null) {
          throw const FormatException('Text clips require text and cannot reference a media asset.');
        }
      } else {
        final assetId = clip.assetId;
        final asset = assetId == null ? null : assetById[assetId];
        if (asset == null) throw const FormatException('Media clip references a missing asset.');
        final compatible = switch (track.kind) {
          TimelineTrackKind.video => asset.kind == TimelineMediaKind.video,
          TimelineTrackKind.image => asset.kind == TimelineMediaKind.image,
          TimelineTrackKind.audio => asset.kind == TimelineMediaKind.audio,
          TimelineTrackKind.effects => false,
          TimelineTrackKind.text => false,
        };
        if (!compatible) throw const FormatException('Media asset type does not match its track.');
        if (asset.durationMs > 0 &&
            clip.sourceStartMs + clip.durationMs > asset.durationMs) {
          throw const FormatException('Clip exceeds the source asset duration.');
        }
      }
    }
  }

  Map<String, Object?> toJson() => {
    'format': 'g3ficut-multimedia-timeline',
    'schemaVersion': schemaVersion,
    'assets': assets.map((e) => e.toJson()).toList(),
    'tracks': tracks.map((e) => e.toJson()).toList(),
    'clips': clips.map((e) => e.toJson()).toList(),
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory MultimediaTimelineDocument.decode(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic> ||
          decoded['format'] != 'g3ficut-multimedia-timeline') {
        throw const FormatException('Not a GifCut multimedia timeline.');
      }
      final assets = _objects(decoded['assets'], 'assets')
          .map(TimelineAsset.fromJson).toList();
      final tracks = _objects(decoded['tracks'], 'tracks')
          .map(TimelineTrack.fromJson).toList();
      final clips = _objects(decoded['clips'], 'clips')
          .map(TimelineClip.fromJson).toList();
      return MultimediaTimelineDocument(
        schemaVersion: _integer(decoded, 'schemaVersion'),
        assets: assets, tracks: tracks, clips: clips,
      );
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Invalid multimedia timeline: $error');
    }
  }
}

void _unique(Iterable<String> ids, String label) {
  final values = ids.toList();
  if (values.any((id) => id.trim().isEmpty) || values.toSet().length != values.length) {
    throw FormatException('Timeline $label identifiers must be non-empty and unique.');
  }
}

List<Map<String, dynamic>> _objects(Object? value, String field) {
  if (value is! List || value.any((e) => e is! Map)) {
    throw FormatException('Field $field must be an array of objects.');
  }
  return value.map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Field $key must be a non-empty string.');
  }
  return value;
}

int _integer(Map<String, dynamic> json, String key, {int? fallback}) {
  final value = json[key] ?? fallback;
  if (value is! int) throw FormatException('Field $key must be an integer.');
  return value;
}

double _number(Map<String, dynamic> json, String key, double fallback) {
  final value = json[key] ?? fallback;
  if (value is! num) throw FormatException('Field $key must be numeric.');
  return value.toDouble();
}
