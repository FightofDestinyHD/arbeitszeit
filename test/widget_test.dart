import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arbeitszeit/main.dart';

void main() {
  testWidgets('App renders work time home page', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('de_DE', null);

    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Arbeitszeit'), findsOneWidget);
    expect(find.textContaining('Heute:'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
  });
}
