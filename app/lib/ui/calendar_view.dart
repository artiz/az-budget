/// Month calendar for the bookings screen: each day shows its money flow
/// (spending as "-424 €", income as "+3 200 €"); tapping a day selects it (its bookings are listed below the grid by
/// the page). Weeks start on Monday. Only the months of the loaded year
/// file are reachable, since that file holds the bookings.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../budget/budget_file.dart';
import 'widgets.dart';

/// Spending per day of [year]/[month]: expense bookings only (not income,
/// not transfers), keyed by day of the month.
Map<int, double> dailyExpenses(BudgetFile file, List<BudgetEntry> entries, int year, int month) {
  final out = <int, double>{};
  for (final e in entries) {
    if (e.date.year != year || e.date.month != month) continue;
    if (!(file.category(e.category)?.isExpense ?? false)) continue;
    out[e.date.day] = (out[e.date.day] ?? 0) + e.amount;
  }
  return out;
}

/// Money flow per day of [year]/[month]: income minus spending, so a day
/// of shopping is negative and payday positive. Transfers between accounts
/// are left out. (Bookings store spending positive and income negative.)
Map<int, double> dailyFlow(BudgetFile file, List<BudgetEntry> entries, int year, int month) {
  final out = <int, double>{};
  for (final e in entries) {
    if (e.date.year != year || e.date.month != month) continue;
    final cat = file.category(e.category);
    if (cat == null || !(cat.isExpense || cat.isIncome)) continue;
    out[e.date.day] = (out[e.date.day] ?? 0) - e.amount;
  }
  return out;
}

/// A day's flow in a calendar cell: sign, whole units and the currency,
/// thousands as "12K" from 10 000 on so it fits a seventh of a phone's width.
String calendarAmount(double v) {
  final a = v.abs();
  final s = a >= 10000 ? '${(a / 1000).round()}K' : NumberFormat('#,##0', 'de_AT').format(a.round());
  final sign = v < 0 ? '-' : (v > 0 ? '+' : '');
  return '$sign$s $moneySymbol';
}

class BudgetCalendar extends StatelessWidget {
  const BudgetCalendar({super.key, required this.year, required this.month, required this.selected, required this.today, required this.totals, required this.onSelect, required this.onMonth});

  final int year;
  final int month;
  final DateTime selected;
  final DateTime today;

  /// Money flow per day of the month (see [dailyFlow]).
  final Map<int, double> totals;
  final ValueChanged<DateTime> onSelect;

  /// Step to another month: -1 or +1. Not called beyond the year.
  final ValueChanged<int> onMonth;

  bool get _canPrev => month > 1;
  bool get _canNext => month < 12;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final first = DateTime(year, month);
    final days = DateUtils.getDaysInMonth(year, month);
    final lead = first.weekday - 1; // Monday first
    final weeks = ((lead + days) / 7).ceil();
    // Monday 1 Jan 2024 + i: the weekday names in the app's language.
    final names = [for (var i = 0; i < 7; i++) DateFormat.E(locale).format(DateTime(2024, 1, 1 + i)).replaceAll('.', '').toUpperCase()];
    final title = DateFormat.yMMMM(locale).format(first);
    return GestureDetector(
      // Swipe left/right: next/previous month.
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -200 && _canNext) onMonth(1);
        if (v > 200 && _canPrev) onMonth(-1);
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(key: const ValueKey('calendar-prev'), visualDensity: VisualDensity.compact, icon: const Icon(Icons.chevron_left), onPressed: _canPrev ? () => onMonth(-1) : null),
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(key: const ValueKey('calendar-next'), visualDensity: VisualDensity.compact, icon: const Icon(Icons.chevron_right), onPressed: _canNext ? () => onMonth(1) : null),
              ],
            ),
            Row(
              children: [
                for (final n in names)
                  Expanded(
                    child: Text(
                      n,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            for (var w = 0; w < weeks; w++)
              Row(
                children: [
                  for (var c = 0; c < 7; c++)
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final day = w * 7 + c - lead + 1;
                          if (day < 1 || day > days) return const SizedBox(height: 46);
                          return _DayCell(
                            day: day,
                            total: totals[day],
                            selected: selected.year == year && selected.month == month && selected.day == day,
                            today: today.year == year && today.month == month && today.day == day,
                            onTap: () => onSelect(DateTime(year, month, day)),
                          );
                        },
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.total, required this.selected, required this.today, required this.onTap});
  final int day;
  final double? total;
  final bool selected;
  final bool today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.onPrimaryContainer : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.all(1.5),
      child: Material(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: today ? BorderSide(color: scheme.primary, width: 1.5) : BorderSide.none,
        ),
        child: InkWell(
          key: ValueKey('calendar-day-$day'),
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: 43,
            // Shrinks instead of overflowing with a large system font size.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$day',
                    style: TextStyle(fontSize: 15, fontWeight: today || selected ? FontWeight.w700 : FontWeight.w500, color: fg),
                  ),
                  if (total != null && total!.abs() >= 0.5)
                    Text(
                      calendarAmount(total!),
                      maxLines: 1,
                      // Income in the list's income colour.
                      style: TextStyle(fontSize: 10, height: 1.1, color: selected ? fg : (total! > 0 ? scheme.tertiary : scheme.onSurfaceVariant)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Spending on the selected day and in its month up to that day.
class CalendarSummary extends StatelessWidget {
  const CalendarSummary({super.key, required this.dayLabel, required this.dayAmount, required this.monthLabel, required this.monthAmount});
  final String dayLabel;
  final double dayAmount;
  final String monthLabel;
  final double monthAmount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget cell(String label, double v, CrossAxisAlignment align) => Expanded(
      child: Column(
        crossAxisAlignment: align,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          Text(euro(v), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ],
      ),
    );
    return Container(
      color: scheme.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [cell(dayLabel, dayAmount, CrossAxisAlignment.start), cell(monthLabel, monthAmount, CrossAxisAlignment.end)]),
    );
  }
}
