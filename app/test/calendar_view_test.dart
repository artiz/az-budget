import 'dart:io';

import 'package:az_budget/app.dart';
import 'package:az_budget/budget/budget_service.dart';
import 'package:az_budget/l10n/app_localizations.dart';
import 'package:az_budget/ocr/engine_controller.dart';
import 'package:az_budget/storage/app_settings.dart';
import 'package:az_budget/ui/calendar_view.dart';
import 'package:az_budget/ui/entries_page.dart';
import 'package:az_budget/ui/home_page.dart';
import 'package:az_budget/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'budget_service_test.dart' show FakeFolder;

void main() {
  test('day amounts: sign, whole units, the currency; thousands from 10 000 as K', () {
    expect(calendarAmount(-120), '-120 €');
    expect(calendarAmount(3200), matches(RegExp(r'^\+3[.\s\u00A0\u202F]200 €$')));
    expect(calendarAmount(-1294.6), matches(RegExp(r'^-1[.\s\u00A0\u202F]295 €$')));
    expect(calendarAmount(-52000), '-52K €');
    expect(calendarAmount(0), '0 €');
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

    final flows = dailyFlow(file, budget.entries, 2026, 3);
    expect(flows, isNotEmpty);
    final busiest = flows.entries.reduce((a, b) => a.value <= b.value ? a : b).key;
    final cell = find.byKey(ValueKey('calendar-day-$busiest'));
    expect(flows[busiest], lessThan(0), reason: 'a day of spending is negative');
    expect(find.descendant(of: cell, matching: find.text(calendarAmount(flows[busiest]!))), findsOneWidget);
    expect(calendarAmount(flows[busiest]!), startsWith('-'));
    // Payday: the salary shows as a positive flow.
    final payday = budget.entries.firstWhere((e) => e.date.month == 3 && (file.category(e.category)?.isIncome ?? false));
    expect(flows[payday.date.day], greaterThan(0));
    expect(find.descendant(of: find.byKey(ValueKey('calendar-day-${payday.date.day}')), matching: find.text(calendarAmount(flows[payday.date.day]!))), findsOneWidget);
    await tester.tap(cell);
    await tester.pumpAndSettle();
    expect(day.value, DateTime(2026, 3, busiest));
    final booked = budget.entries.where((e) => e.date.month == 3 && e.date.day == busiest).length;
    expect(find.byType(EntryTile), findsNWidgets(booked));

    // Summary: Einnahmen, Ausgaben, Saldo of the day and of the month so far.
    final summary = find.byKey(const ValueKey('calendar-summary'));
    for (final h in ['Einnahmen', 'Ausgaben', 'Saldo']) {
      expect(find.descendant(of: summary, matching: find.text(h)), findsOneWidget);
    }
    final march = budget.entries.where((e) => e.date.year == 2026 && e.date.month == 3);
    final dayT = BookingTotals.of(file, march.where((e) => e.date.day == busiest));
    final soFar = BookingTotals.of(file, march.where((e) => e.date.day <= busiest));
    for (final v in [euro(dayT.income), euro(dayT.expenses), euro(dayT.saldo, showPlus: true), euro(soFar.income), euro(soFar.expenses), euro(soFar.saldo, showPlus: true)]) {
      expect(
        find.descendant(of: summary, matching: find.text(v)),
        findsWidgets,
        reason: v,
      );
    }
    // The whole month: the same numbers as the overview (expenses as in the
    // limit check), and the day cells add up to the Saldo.
    final all = BookingTotals.of(file, march);
    expect(all.expenses, closeTo(budget.monthExpenses(3), 0.001));
    expect(flows.values.fold(0.0, (s, v) => s + v), closeTo(all.saldo, 0.001));

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

  testWidgets('the whole bookings screen fits a 360 dp phone in both views', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = (await tester.runAsync(AppSettings.load))!;
    await tester.runAsync(() => settings.setFolder('tree', 'Budget'));
    final tmp = Directory.systemTemp.createTempSync('azcal360');
    final budget = BudgetService(folder: FakeFolder(File('test/fixtures/budget_small.xlsx').readAsBytesSync()), settings: settings, queueDir: tmp, clock: () => DateTime(2026, 3, 9));
    await tester.runAsync(budget.sync);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    for (final calendar in [false, true]) {
      await tester.runAsync(() => settings.setCalendarView(calendar));
      await tester.pumpWidget(
        AppScope(
          budget: budget,
          settings: settings,
          engine: EngineController(),
          child: MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: const Locale('de'), home: const HomePage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BudgetCalendar), calendar ? findsOneWidget : findsNothing);
      // An overflow is reported as an exception and fails the test by itself.
      expect(tester.takeException(), isNull, reason: calendar ? 'calendar' : 'list');
    }
    await tester.binding.setSurfaceSize(null);
    tmp.deleteSync(recursive: true);
  });
}
