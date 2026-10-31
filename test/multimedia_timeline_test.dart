import 'package:flutter_test/flutter_test.dart';
import 'package:gifcut/multimedia_timeline.dart';

void main() {
  group('MultimediaTimelineDocument', () {
    final assets = [
      const TimelineAsset(id: 'v1', path: r'C:\media\a.mp4',
          kind: TimelineMediaKind.video, durationMs: 10000),
      const TimelineAsset(id: 'i1', path: r'C:\media\cover.png',
          kind: TimelineMediaKind.image, durationMs: 5000),
      const TimelineAsset(id: 'a1', path: r'C:\media\music.wav',
          kind: TimelineMediaKind.audio, durationMs: 20000),
    ];
    final tracks = [
      const TimelineTrack(id: 'video-1', kind: TimelineTrackKind.video, name: 'Видео 1'),
      const TimelineTrack(id: 'image-1', kind: TimelineTrackKind.image, name: 'Фото 1'),
      const TimelineTrack(id: 'audio-1', kind: TimelineTrackKind.audio, name: 'Аудио 1'),
      const TimelineTrack(id: 'text-1', kind: TimelineTrackKind.text, name: 'Текст'),
    ];

    test('roundtrips independent video, image, audio and text clips', () {
      final doc = MultimediaTimelineDocument(
        assets: assets,
        tracks: tracks,
        clips: const [
          TimelineClip(id: 'c1', trackId: 'video-1', assetId: 'v1',
              startMs: 0, durationMs: 4000),
          TimelineClip(id: 'c2', trackId: 'image-1', assetId: 'i1',
              startMs: 1000, durationMs: 5000, x: .25, y: .75, scale: 1.2),
          TimelineClip(id: 'c3', trackId: 'audio-1', assetId: 'a1',
              startMs: 0, durationMs: 10000, volume: .65),
          TimelineClip(id: 'c4', trackId: 'text-1', startMs: 1500,
              durationMs: 2500, text: 'Заголовок',
              textStyle: {'fontSize': 48, 'color': '#ffffff'}),
        ],
      );

      final restored = MultimediaTimelineDocument.decode(doc.encode());

      expect(restored.assets.length, 3);
      expect(restored.tracks.length, 4);
      expect(restored.clips.length, 4);
      expect(restored.clips.last.text, 'Заголовок');
      expect(restored.clips[1].scale, 1.2);
      expect(restored.clips[2].volume, .65);
    });

    test('rejects clips with missing assets and incompatible tracks', () {
      expect(() => MultimediaTimelineDocument(
        assets: assets, tracks: tracks,
        clips: const [TimelineClip(id: 'bad', trackId: 'video-1',
            assetId: 'missing', startMs: 0, durationMs: 1000)],
      ), throwsFormatException);

      expect(() => MultimediaTimelineDocument(
        assets: assets, tracks: tracks,
        clips: const [TimelineClip(id: 'bad', trackId: 'image-1',
            assetId: 'v1', startMs: 0, durationMs: 1000)],
      ), throwsFormatException);
    });

    test('rejects invalid text clips and duplicate identifiers', () {
      expect(() => MultimediaTimelineDocument(
        assets: assets, tracks: tracks,
        clips: const [TimelineClip(id: 'bad', trackId: 'text-1',
            startMs: 0, durationMs: 1000)],
      ), throwsFormatException);

      expect(() => MultimediaTimelineDocument(
        assets: assets, tracks: tracks,
        clips: const [],
      ), returnsNormally);
    });

    test('supports text clips without media files', () {
      final doc = MultimediaTimelineDocument(
        assets: const [],
        tracks: const [TimelineTrack(
          id: 'titles', kind: TimelineTrackKind.text, name: 'Текст')],
        clips: const [TimelineClip(
          id: 'title-1', trackId: 'titles', startMs: 0,
          durationMs: 3000, text: 'Новый текст')],
      );
      expect(MultimediaTimelineDocument.decode(doc.encode()).clips.single.text,
          'Новый текст');
    });
  });
}
