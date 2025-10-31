import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:myapp/screens/settings_screen.dart';
import 'package:myapp/screens/attendance_screen.dart';
import 'package:myapp/providers/settings_provider.dart';
import 'package:myapp/providers/theme_provider.dart';
import 'package:myapp/providers/student_provider.dart';
import 'package:myapp/providers/attendance_provider.dart';

void main() {
  testWidgets('SettingsScreen headings visible in dark theme', (WidgetTester tester) async {
    final darkTheme = ThemeData.dark();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MaterialApp(
        theme: darkTheme,
        home: const SettingsScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    final schoolFinder = find.text('School Information');
    expect(schoolFinder, findsOneWidget);

    final textWidget = tester.widget<Text>(schoolFinder);
    expect(textWidget.style?.color ?? DefaultTextStyle.of(tester.element(schoolFinder)).style.color, isNotNull);
  });

  testWidgets('AttendanceScreen key labels visible in dark theme', (WidgetTester tester) async {
    final darkTheme = ThemeData.dark();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => StudentProvider()),
        ChangeNotifierProvider(create: (_) => AttendanceProvider()),
      ],
      child: MaterialApp(
        theme: darkTheme,
        home: const AttendanceScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    final dateFinder = find.text('Date');
    expect(dateFinder, findsOneWidget);

    final textWidget = tester.widget<Text>(dateFinder);
    expect(textWidget.style?.color ?? DefaultTextStyle.of(tester.element(dateFinder)).style.color, isNotNull);
  });
}
