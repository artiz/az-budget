import 'dart:io';

import 'package:az_budget/app.dart';
import 'package:az_budget/budget/budget_service.dart';
import 'package:az_budget/l10n/app_localizations.dart';
import 'package:az_budget/ocr/engine_controller.dart';
import 'package:az_budget/storage/app_settings.dart';
import 'package:az_budget/theme.dart';
import 'package:az_budget/ui/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'budget_service_test.dart' show FakeFolder;

void main() {
  testWidgets('a missing amount is said at the field, not in a message behind the form', (tester) async {
    SharedPreferences.setMockInitialValues({'calendar_view': true});
    final settings = (await tester.runAsync(AppSettings.load))!;
    await tester.runAsync(() => settings.setFolder('tree', 'Budget'));
    final tmp = Directory.systemTemp.createTempSync('azform');
    final budget = BudgetService(folder: FakeFolder(File('test/fixtures/budget_small.xlsx').readAsBytesSync()), settings: settings, queueDir: tmp, clock: () => DateTime(2026, 3, 9));
    await tester.runAsync(budget.sync);
    await tester.binding.setSurfaceSize(const Size(400, 900));
    await tester.pumpWidget(
      AppScope(
        budget: budget,
        settings: settings,
        engine: EngineController(),
        child: MaterialApp(
          theme: azTheme(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const HomePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // From the calendar: "+ Buchung", a description and a note, no amount.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('09.03.2026'), findsOneWidget, reason: 'dated on the selected day');
    await tester.enterText(find.byKey(const ValueKey('description')), 'Eboba');
    await tester.enterText(find.byKey(const ValueKey('note')), '555');
    await tester.pump();
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Betrag eingeben'), findsOneWidget, reason: 'the amount field says what is missing');
    final amount = tester.widget<TextField>(find.byKey(const ValueKey('amount')));
    expect(amount.focusNode!.hasFocus, isTrue, reason: 'the cursor goes to the amount');

    // Something that is not an amount, then a real one: the error follows.
    await tester.enterText(find.byKey(const ValueKey('amount')), ',');
    await tester.pumpAndSettle(); // the field fades between error and helper text
    expect(find.text('Kein gültiger Betrag'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('amount')), '5,55');
    await tester.pumpAndSettle();
    expect(find.text('Kein gültiger Betrag'), findsNothing);
    expect(find.text('Betrag eingeben'), findsNothing);

    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    // Saving writes to disk (real I/O): wait for it, up to 5 s.
    for (var i = 0; i < 100 && !budget.entries.any((e) => e.description == 'Eboba'); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    final saved = budget.entries.where((e) => e.description == 'Eboba');
    expect(saved, hasLength(1));
    expect((saved.single.amount, saved.single.note, saved.single.date), (5.55, '555', DateTime(2026, 3, 9)));

    await tester.binding.setSurfaceSize(null);
    tmp.deleteSync(recursive: true);
  });

  testWidgets('no description is fine: category and amount are enough', (tester) async {
    SharedPreferences.setMockInitialValues({'calendar_view': true});
    final settings = (await tester.runAsync(AppSettings.load))!;
    await tester.runAsync(() => settings.setFolder('tree', 'Budget'));
    final tmp = Directory.systemTemp.createTempSync('azform2');
    final budget = BudgetService(folder: FakeFolder(File('test/fixtures/budget_small.xlsx').readAsBytesSync()), settings: settings, queueDir: tmp, clock: () => DateTime(2026, 3, 9));
    await tester.runAsync(budget.sync);
    final before = budget.entries.length;
    await tester.binding.setSurfaceSize(const Size(400, 900));
    await tester.pumpWidget(
      AppScope(
        budget: budget,
        settings: settings,
        engine: EngineController(),
        child: MaterialApp(
          theme: azTheme(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const HomePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('amount')), '555');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Betrag eingeben'), findsNothing);
    expect(find.text('Kategorie wählen'), findsNothing);
    for (var i = 0; i < 100 && budget.entries.length == before; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(budget.entries.length, before + 1);
    final e = budget.entries.singleWhere((e) => e.amount == 555); // entries are sorted by date
    expect((e.description, e.amount, e.date), ('', 555.0, DateTime(2026, 3, 9)));
    await tester.binding.setSurfaceSize(null);
    tmp.deleteSync(recursive: true);
  });
}
