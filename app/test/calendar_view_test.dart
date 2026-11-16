import 'dart:io';

import 'package:az_budget/app.dart';
import 'package:az_budget/budget/budget_service.dart';
import 'package:az_budget/l10n/app_localizations.dart';
import 'package:az_budget/ocr/engine_controller.dart';
import 'package:az_budget/storage/app_settings.dart';
import 'package:az_budget/ui/calendar_view.dart';
import 'package:az_budget/ui/entries_page.dart';
import 'package:az_budget/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'budget_service_test.dart' show FakeFolder;

void main() {
  test('day totals: whole units, thousands from 10 000 as K', () {
    expect(calendarAmount(0.4), '0');
    expect(calendarAmount(120), '120');
    // Thousands grouped as everywhere in the app (de_AT: a narrow space).
    expect(calendarAmount(1294.6), matches(RegExp(r'^1[.\s\u00A0\u202F]295$')));
    expect(calendarAmount(9999), matches(RegExp(r'^9[.\s\u00A0\u202F]999$')));
    expect(calendarAmount(52000), '52K');
    expect(calendarAmount(-30), '-30');
  });

  testWidgets('calendar view: switched next to the quick tiles, days show their spending, a day lists its bookings', (tester) async {
    SharedPreferences.setMockInitialValues({});
    // Real I/O never completes under the test's fake async clock: run it outside.
    final settings = (await tester.runAsync(AppSettings.load))!;
    await tester.runAsync(() => settings.setFolder('tree', 'Budget'));
    final tmp = Directory.systemTemp.createTempSync('azcal');
    final budget = BudgetService(folder: FakeFolder(File('test/fixtures/budget_small.xlsx').readAsBytesSync()), settings: settings, queueDir: tmp, clock: () => DateTime(2026, 4, 10));
    await tester.runAsync(budget.sync);
    final file = budget.file!;
    final day = ValueNotifier<DateTime?>(null);

    // A phone's width: the status line must fit the new button.
    await tester.binding.setSurfaceSize(const Size(360, 800));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: AppScope(
          budget: budget,
          settings: settings,
          engine: EngineController(),
          child: Scaffold(
            body: EntriesPage(budget: budget, onOpenSettings: () {}, calendarDay: day),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BudgetCalendar), findsNothing, reason: 'the list is the default');
    expect(day.value, isNull);

    await tester.tap(find.byKey(const ValueKey('calendar-toggle')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero)); // the setting is saved
    await tester.pumpAndSettle();
    expect(settings.calendarView, isTrue, reason: 'remembered');
    expect(find.byType(BudgetCalendar), findsOneWidget);
    expect(find.text('April 2026'), findsOneWidget, reason: 'opens on today');
    expect(day.value, DateTime(2026, 4, 10), reason: 'a new booking is dated on the selected day');
    expect(find.text('Keine Buchungen an diesem Tag.'), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-next')), findsOneWidget);

    // Back to March, the last month with bookings in the fixture.
    await tester.tap(find.byKey(const ValueKey('calendar-prev')));
    await tester.pumpAndSettle();
    expect(find.text('März 2026'), findsOneWidget);
    expect(day.value, DateTime(2026, 3, 1));

    final totals = dailyExpenses(file, budget.entries, 2026, 3);
    expect(totals, isNotEmpty);
    final busiest = totals.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final cell = find.byKey(ValueKey('calendar-day-${busiest.key}'));
    expect(find.descendant(of: cell, matching: find.text(calendarAmount(busiest.value))), findsOneWidget);
    await tester.tap(cell);
    await tester.pumpAndSettle();
    expect(day.value, DateTime(2026, 3, busiest.key));
    final booked = budget.entries.where((e) => e.date.month == 3 && e.date.day == busiest.key).length;
    expect(find.byType(EntryTile), findsNWidgets(booked));
    // Summary: that day, and the month up to it.
    final toDate = totals.entries.where((t) => t.key <= busiest.key).fold(0.0, (s, t) => s + t.value);
    expect(find.text(euro(busiest.value)), findsWidgets);
    expect(find.text(euro(toDate)), findsWidgets);
    // The same spending as the month's expenses elsewhere (no income, no transfers).
    expect(totals.values.fold(0.0, (s, v) => s + v), closeTo(budget.monthExpenses(3), 0.001));

    // Swipe right: February.
    await tester.fling(find.byType(BudgetCalendar), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Februar 2026'), findsOneWidget);

    // Back to the list.
    await tester.tap(find.byKey(const ValueKey('calendar-toggle')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.byType(BudgetCalendar), findsNothing);
    expect(day.value, isNull, reason: 'the "+" button books today again');

    await tester.binding.setSurfaceSize(null);
    tmp.deleteSync(recursive: true);
  });
}
