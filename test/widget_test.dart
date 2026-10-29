import 'package:flutter_test/flutter_test.dart';
import 'package:clipforge/main.dart';

void main() {
  testWidgets('ClipForge editor opens with import and timeline controls', (tester) async {
    await tester.pumpWidget(const ClipForgeApp());
    await tester.pump();

    expect(find.text('ClipForge'), findsOneWidget);
    expect(find.text('Импорт видео'), findsOneWidget);
    expect(find.text('ТАЙМЛАЙН'), findsOneWidget);
    expect(find.text('Ваше видео появится здесь'), findsOneWidget);
  });
}
