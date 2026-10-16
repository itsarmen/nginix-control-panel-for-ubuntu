import 'package:flutter_test/flutter_test.dart';
import 'package:nginix_control_panel/main.dart';

void main() {
  testWidgets('App builds without errors', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const NginixControlPanelApp());
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
  });
}