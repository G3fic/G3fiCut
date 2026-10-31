import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gifcut/project_document.dart';

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
  List<ProjectEffectClip> effectClips = const [],
  List<ProjectTransition> transitions = const [],
  List<ProjectPhotoOverlay> photoOverlays = const [],
  List<ProjectTextOverlay> textOverlays = const [],
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
      effectClips: effectClips,
      transitions: transitions,
      photoOverlays: photoOverlays,
      textOverlays: textOverlays,
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
      expect(decoded.schemaVersion, ProjectDocument.currentSchemaVersion);
      expect(decoded.videoClips, [
        const ProjectClipRange(0, 4, timelineStart: 0),
        const ProjectClipRange(5, 12, timelineStart: 5),
      ]);
      expect(decoded.selectedClipIndex, 1);
      expect(decoded.audioPath, r'C:\media\sample_audio.wav');
      expect(decoded.audioDurationMs, 12000);
      expect(decoded.audioClipStart, 1.25);
      expect(decoded.audioClipEnd, 9.5);
      expect(decoded.timelineZoom, 40);
      expect(decoded.playheadMs, 6200);
    });

    test('migrates schema v1 ranges in historical export order', () {
      final legacy = makeProject(schemaVersion: 1).toJson();
      for (final rawClip in legacy['videoClips'] as List) {
        (rawClip as Map<String, dynamic>).remove('timelineStart');
      }
      final migrated = ProjectDocument.decode(jsonEncode(legacy));
      expect(migrated.schemaVersion, ProjectDocument.currentSchemaVersion);
      expect(migrated.videoClips, [
        const ProjectClipRange(0, 4, timelineStart: 0),
        const ProjectClipRange(5, 12, timelineStart: 4),
      ]);
      expect(migrated.videoClips.last.timelineEnd, 11);
    });

    test('preserves identical source ranges at different sequence positions', () {
      final original = makeProject(
        videoClips: const [
          ProjectClipRange(0, 4, timelineStart: 0),
          ProjectClipRange(0, 4, timelineStart: 4),
        ],
        selectedClipIndex: 1,
        playheadMs: 6500,
      );
      final decoded = ProjectDocument.decode(original.encode());
      expect(decoded.videoClips[1].start, 0);
      expect(decoded.videoClips[1].timelineStart, 4);
      expect(decoded.playheadMs, 6500);
    });

    test('roundtrip preserves timeline effect blocks and per-cut transitions', () {
      final original = makeProject(
        videoClips: const [
          ProjectClipRange(0, 4, timelineStart: 0),
          ProjectClipRange(5, 9, timelineStart: 4),
        ],
        selectedClipIndex: 1,
        playheadMs: 4500,
        effectClips: const [
          ProjectEffectClip(type: 'Сепия', start: 1.5, end: 3.25),
          ProjectEffectClip(type: 'Размытие', start: 6, end: 8),
        ],
        transitions: const [
          ProjectTransition(type: 'Растворение', at: 4, duration: 0.5),
        ],
      );

      final decoded = ProjectDocument.decode(original.encode());

      expect(decoded.effectClips, original.effectClips);
      expect(decoded.transitions, original.transitions);
    });

    test('schema v2 projects migrate without timeline annotations', () {
      final legacy = makeProject(schemaVersion: 2).toJson()
        ..remove('effectClips')
        ..remove('transitions');

      final migrated = ProjectDocument.decode(jsonEncode(legacy));

      expect(migrated.schemaVersion, ProjectDocument.currentSchemaVersion);
      expect(migrated.effectClips, isEmpty);
      expect(migrated.transitions, isEmpty);
    });

    test('rejects unsupported effect types and transitions not attached to a cut', () {
      expect(
        () => makeProject(
          effectClips: const [
            ProjectEffectClip(type: 'Unknown', start: 1, end: 2),
          ],
        ),
        throwsFormatException,
      );
      expect(
        () => makeProject(
          transitions: const [
            ProjectTransition(type: 'Затемнение', at: 4, duration: 0.5),
          ],
        ),
        throwsFormatException,
      );
      expect(
        () => makeProject(
          videoClips: const [
            ProjectClipRange(0, 4, timelineStart: 0),
            ProjectClipRange(5, 9, timelineStart: 4),
          ],
          transitions: const [
            ProjectTransition(type: 'Unknown', at: 4, duration: 0.5),
          ],
        ),
        throwsFormatException,
      );
    });

    test('accepts and roundtrips all built-in transition types', () {
      final transitionTypes = ProjectTransition.supportedTypes.toList()..sort();
      for (final type in transitionTypes) {
        final project = makeProject(
          videoClips: const [
            ProjectClipRange(0, 4, timelineStart: 0),
            ProjectClipRange(5, 9, timelineStart: 4),
          ],
          transitions: [ProjectTransition(type: type, at: 4, duration: 0.5)],
        );
        expect(ProjectDocument.decode(project.encode()).transitions.single.type, type);
      }
    });

    test('accepts and roundtrips every registered timeline effect', () {
      for (final type in ProjectEffectClip.supportedTypes) {
        final project = makeProject(
          effectClips: [ProjectEffectClip(type: type, start: 1, end: 2)],
        );
        expect(ProjectDocument.decode(project.encode()).effectClips.single.type, type);
      }
    });


    test('schema v4 roundtrip preserves timed photo and text layers', () {
      final original = makeProject(
        photoOverlays: const [
          ProjectPhotoOverlay(
            path: r'C:\\media\\logo.png',
            x: 0.2,
            y: -0.1,
            scale: 1.4,
            rotation: 12,
            opacity: 0.8,
            start: 1.5,
            end: 8,
          ),
        ],
        textOverlays: const [
          ProjectTextOverlay(
            text: 'Заголовок',
            start: 2,
            end: 6.5,
            x: 0.1,
            y: -0.25,
            fontSize: 56,
            color: '#FFD166',
            bold: false,
            opacity: 0.9,
          ),
        ],
      );

      final decoded = ProjectDocument.decode(original.encode());

      expect(decoded.schemaVersion, 4);
      expect(decoded.photoOverlays.single.path, r'C:\\media\\logo.png');
      expect(decoded.photoOverlays.single.start, 1.5);
      expect(decoded.photoOverlays.single.end, 8);
      expect(decoded.photoOverlays.single.scale, 1.4);
      expect(decoded.textOverlays.single.text, 'Заголовок');
      expect(decoded.textOverlays.single.color, '#FFD166');
      expect(decoded.textOverlays.single.fontSize, 56);
      expect(decoded.textOverlays.single.bold, isFalse);
      expect(decoded.textOverlays.single.opacity, 0.9);
    });

    test('legacy schema v3 projects migrate with empty photo and text layers', () {
      final legacy = makeProject(schemaVersion: 3).toJson()
        ..remove('photoOverlays')
        ..remove('textOverlays');

      final migrated = ProjectDocument.decode(jsonEncode(legacy));

      expect(migrated.schemaVersion, ProjectDocument.currentSchemaVersion);
      expect(migrated.photoOverlays, isEmpty);
      expect(migrated.textOverlays, isEmpty);
    });

    test('rejects malformed photo and text layer timing or formatting', () {
      expect(
        () => makeProject(
          photoOverlays: const [
            ProjectPhotoOverlay(path: 'logo.png', start: 2, end: 1),
          ],
        ),
        throwsFormatException,
      );
      expect(
        () => makeProject(
          textOverlays: const [
            ProjectTextOverlay(text: ' ', start: 0, end: 2),
          ],
        ),
        throwsFormatException,
      );
      expect(
        () => makeProject(
          textOverlays: const [
            ProjectTextOverlay(text: 'Title', start: 0, end: 2, color: 'red'),
          ],
        ),
        throwsFormatException,
      );
    });

    test('rejects an unknown format and an unsupported schema version', () {
      final wrongFormat = makeProject().toJson()..['format'] = 'other-editor';
      expect(() => ProjectDocument.fromJson(wrongFormat), throwsFormatException);

      final wrongVersion = makeProject().toJson()..['schemaVersion'] = 999;
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
        () => makeProject(audioPath: null, audioDurationMs: 0, audioClipStart: 0, audioClipEnd: 0),
        returnsNormally,
      );
      expect(
        () => makeProject(audioPath: null, audioDurationMs: 0, audioClipStart: 1, audioClipEnd: 2),
        throwsFormatException,
      );
      expect(
        () => makeProject(audioPath: null, audioDurationMs: 1, audioClipStart: 0, audioClipEnd: 0),
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
