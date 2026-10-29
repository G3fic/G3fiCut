import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:g3ficut/project_document.dart';

ProjectDocument makeProject({
  String format = ProjectDocument.formatId,
  int schemaVersion = ProjectDocument.currentSchemaVersion,
  String appVersion = '0.3.0',
  String videoPath = r'C:\media\sample.mp4',
  int videoDurationMs = 12000,
  List<ProjectClipRange> videoClips = const [
    ProjectClipRange(0, 4),
    ProjectClipRange(5, 12),
  ],
  int selectedClipIndex = 1,
  String? audioPath = r'C:\media\sample_audio.wav',
  int audioDurationMs = 12000,
  double audioClipStart = 1.25,
  double audioClipEnd = 9.5,
  double timelineZoom = 40,
  int playheadMs = 6200,
}) =>
    ProjectDocument(
      format: format,
      schemaVersion: schemaVersion,
      appVersion: appVersion,
      videoPath: videoPath,
      videoDurationMs: videoDurationMs,
      videoClips: videoClips,
      selectedClipIndex: selectedClipIndex,
      audioPath: audioPath,
      audioDurationMs: audioDurationMs,
      audioClipStart: audioClipStart,
      audioClipEnd: audioClipEnd,
      timelineZoom: timelineZoom,
      playheadMs: playheadMs,
    );

void main() {
  group('ProjectDocument', () {
    test('encode/decode roundtrip preserves the complete edit state', () {
      final original = makeProject();

      final decoded = ProjectDocument.decode(original.encode());

      expect(decoded.format, ProjectDocument.formatId);
      expect(decoded.schemaVersion, ProjectDocument.currentSchemaVersion);
      expect(decoded.appVersion, '0.3.0');
      expect(decoded.videoPath, r'C:\media\sample.mp4');
      expect(decoded.videoDurationMs, 12000);
      expect(decoded.videoClips, [
        const ProjectClipRange(0, 4),
        const ProjectClipRange(5, 12),
      ]);
      expect(decoded.selectedClipIndex, 1);
      expect(decoded.audioPath, r'C:\media\sample_audio.wav');
      expect(decoded.audioDurationMs, 12000);
      expect(decoded.audioClipStart, 1.25);
      expect(decoded.audioClipEnd, 9.5);
      expect(decoded.timelineZoom, 40);
      expect(decoded.playheadMs, 6200);
    });

    test('rejects an unknown format and an unsupported schema version', () {
      final wrongFormat = makeProject(format: 'other-editor').toJson();
      expect(() => ProjectDocument.fromJson(wrongFormat), throwsFormatException);

      final wrongVersion = makeProject(schemaVersion: 999).toJson();
      expect(() => ProjectDocument.fromJson(wrongVersion), throwsFormatException);
    });

    test('rejects invalid, negative, non-finite and reversed video ranges', () {
      expect(
        () => makeProject(videoClips: [const ProjectClipRange(-1, 2)]),
        throwsFormatException,
      );
      expect(
        () => makeProject(videoClips: [const ProjectClipRange(3, 2)]),
        throwsFormatException,
      );
      expect(
        () => makeProject(videoClips: [const ProjectClipRange(0, double.infinity)]),
        throwsFormatException,
      );
      expect(
        () => makeProject(videoClips: [const ProjectClipRange(0, 13)]),
        throwsFormatException,
      );
    });

    test('rejects a selected clip index outside the timeline', () {
      expect(
        () => makeProject(selectedClipIndex: 2),
        throwsFormatException,
      );
      expect(
        () => makeProject(selectedClipIndex: -1),
        throwsFormatException,
      );
    });

    test('allows an empty video timeline only with selection index zero', () {
      expect(
        () => makeProject(videoClips: const [], selectedClipIndex: 0),
        returnsNormally,
      );
      expect(
        () => makeProject(videoClips: const [], selectedClipIndex: 1),
        throwsFormatException,
      );
    });

    test('requires zero audio boundaries when the audio path is absent', () {
      expect(
        () => makeProject(audioPath: null, audioClipStart: 0, audioClipEnd: 0),
        returnsNormally,
      );
      expect(
        () => makeProject(audioPath: null, audioClipStart: 1, audioClipEnd: 2),
        throwsFormatException,
      );
    });

    test('rejects invalid audio bounds and zoom outside supported range', () {
      expect(
        () => makeProject(audioClipStart: -1),
        throwsFormatException,
      );
      expect(
        () => makeProject(audioClipStart: 10, audioClipEnd: 9),
        throwsFormatException,
      );
      expect(
        () => makeProject(timelineZoom: 7.9),
        throwsFormatException,
      );
      expect(
        () => makeProject(timelineZoom: 160.1),
        throwsFormatException,
      );
    });

    test('rejects malformed JSON and non-object JSON roots', () {
      expect(() => ProjectDocument.decode('{bad json'), throwsFormatException);
      expect(() => ProjectDocument.decode(jsonEncode(['not', 'a', 'project'])), throwsFormatException);
    });
  });
}
