import 'package:flutter_test/flutter_test.dart';
import 'package:server_dashboard/main.dart';

void main() {
  testWidgets('App builds without errors', (WidgetTester tester) async {
    await tester.pumpWidget(const ServerDashboardApp());
    await tester.pump();
  });
}