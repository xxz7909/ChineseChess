import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_chess/main.dart';

void main() {
  testWidgets('App launches', (WidgetTester tester) async {
    await tester.pumpWidget(const ChineseChessApp());
    expect(find.text('中国象棋'), findsOneWidget);
  });
}
