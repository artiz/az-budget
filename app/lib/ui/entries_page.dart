/// Home: the bookings table over the full height, with the quick tiles
/// learned from the file in a panel that drops down from the status line;
/// or, switched next to the quick tiles, a month calendar with the selected
/// day's bookings below it.
library;

import 'package:flutter/material.dart';

import '../app.dart';
import '../budget/budget_file.dart';
import '../budget/budget_service.dart';
import '../budget/entry_suggest.dart';
import '../core/text_normalize.dart';
import '../l10n/app_localizations.dart';
import '../theme.dart';
import 'calendar_view.dart';
import 'entry_actions.dart';
import 'entry_sheet.dart';
import 'widgets.dart';

class EntriesPage extends StatefulWidget {
  const EntriesPage({super.key, required this.budget, required this.onOpenSettings, this.calendarDay});
  final BudgetService budget;
  final VoidCallback onOpenSettings;

  /// The day selected in the calendar view (null in the list view): a new
  /// booking from the page's "+" button is dated on it.
  final ValueNotifier<DateTime?>? calendarDay;

  @override
  State<EntriesPage> createState() => _EntriesPageState();
}

class _EntriesPageState extends State<EntriesPage> {
  static const int _pageSize = 20;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  int _visible = _pageSize;
  bool _loadingMore = false;
  bool _tilesOpen = false;

  /// Selected calendar day; null until the calendar is first shown.
  DateTime? _day;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() => _visible = _pageSize));
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Next page when the list is near its end; the data is in memory, so the
  /// "load" is just a deferred rebuild that keeps scrolling smooth.
  void _onScroll() {
    if (_loadingMore || !_scroll.hasClients) return;
    if (_scroll.position.extentAfter < 400) {
      _loadingMore = true;
      Future<void>.delayed(const Duration(milliseconds: 50), () {
        if (!mounted) return;
        setState(() {
          _visible += _pageSize;
          _loadingMore = false;
        });
      });
    }
  }

  Future<void> _addFromTile(QuickTile tile) async {
    final l = AppLocalizations.of(context);
    final budget = widget.budget;
    setState(() => _tilesOpen = false);
    final entry = await showEntrySheet(
      context,
      budget: budget,
      title: l.confirmEntry,
      draft: EntryDraft(category: tile.category, description: tile.description, amount: tile.amount.abs()),
    );
    if (entry == null || !mounted) return;
    await saveNewEntry(context, budget, entry);
  }

  List<BudgetEntry> _filtered(List<BudgetEntry> all) {
    final q = normalize(_search.text.trim());
    if (q.isEmpty) return all;
    final words = q.split(' ');
    return [
      for (final e in all)
        if (words.every((w) => normalize('${e.description} ${e.category} ${e.note} ${e.amount.toStringAsFixed(2)} ${e.amount.toStringAsFixed(2).replaceAll('.', ',')}').contains(w))) e,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final budget = widget.budget;
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: budget,
      builder: (context, _) {
        if (budget.state == SyncState.noFolder) {
          return EmptyHint(
            icon: Icons.folder_open_outlined,
            text: l.chooseFolderHint,
            action: FilledButton.icon(onPressed: widget.onOpenSettings, icon: const Icon(Icons.folder_outlined), label: Text(l.chooseFolder)),
          );
        }
        final all = budget.entries.reversed.toList();
        final settings = AppScope.of(context).settings;
        final tiles = budget.suggestions.quickTiles(limit: 12, perCategory: 3, pinned: settings.pinnedTiles);
        final shown = _filtered(all);
        final count = shown.length < _visible ? shown.length : _visible;
        final stranded = budget.strandedPending;
        final calendar = settings.calendarView && budget.file != null && budget.year != null;
        final day = calendar ? _calendarDayFor(budget) : null;
        // Read when the "+" button is pressed; nothing listens, so setting it here is safe.
        widget.calendarDay?.value = day;
        return Column(
          children: [
            SyncStatusBar(
              budget: budget,
              onTap: budget.sync,
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tiles.isNotEmpty)
                    Flexible(
                      child: FilledButton.tonalIcon(
                        onPressed: () => setState(() => _tilesOpen = !_tilesOpen),
                        icon: Icon(_tilesOpen ? Icons.expand_less : Icons.bolt_outlined, size: 18),
                        label: Text(l.quickEntries, maxLines: 1, overflow: TextOverflow.ellipsis),
                        style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 12)),
                      ),
                    ),
                  if (budget.file != null) ...[
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                      key: const ValueKey('calendar-toggle'),
                      tooltip: calendar ? l.listView : l.calendarView,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(calendar ? Icons.view_list_outlined : Icons.calendar_month_outlined, size: 20),
                      onPressed: () async {
                        await settings.setCalendarView(!calendar);
                        if (mounted) setState(() {}); // the page rebuilds on the budget, not the settings
                      },
                    ),
                  ],
                ],
              ),
            ),
            if (stranded.isNotEmpty)
              MaterialBanner(
                content: Text(l.strandedPending(stranded.length, stranded.first.date.year)),
                leading: const Icon(Icons.event_busy_outlined),
                actions: [TextButton(onPressed: () => editEntry(context, budget, stranded.first), child: Text(l.fixDate))],
              ),
            if (budget.currentYearMissing)
              MaterialBanner(
                content: Text(l.yearFileMissing(budget.currentYear)),
                leading: const Icon(Icons.calendar_month_outlined),
                actions: [TextButton(onPressed: () => createYearFile(context, budget), child: Text(l.createYearFile(budget.currentYear)))],
              ),
            if (budget.freshFileYear != null && budget.file != null)
              MaterialBanner(
                content: Text(l.fileCreatedNotice(budget.freshFileYear!, languageDisplayName(budget.file!.language))),
                leading: const Icon(Icons.auto_awesome_outlined),
                actions: [TextButton(onPressed: budget.dismissFreshFile, child: Text(l.gotIt))],
              ),
            // The quick tiles drop down over the top of the table.
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.topCenter,
              child: _tilesOpen && tiles.isNotEmpty
                  ? ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.42),
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          border: Border(bottom: BorderSide(color: scheme.outline, width: 2)),
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [for (final t in tiles) _QuickTileChip(tile: t, onTap: () => _addFromTile(t), onLongPress: () => _togglePin(context, t.key, t.pinned))],
                          ),
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            if (calendar)
              Expanded(child: _calendarBody(context, budget, day!))
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: l.searchHint(all.length),
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    suffixIcon: _search.text.isEmpty ? null : IconButton(icon: const Icon(Icons.clear), onPressed: _search.clear),
                  ),
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? EmptyHint(icon: Icons.receipt_long_outlined, text: l.noEntries)
                    : RefreshIndicator(
                        onRefresh: budget.sync,
                        child: ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.only(bottom: 88),
                          itemCount: count + (count < shown.length ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i >= count) {
                              return const Padding(
                                padding: EdgeInsets.all(12),
                                child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                              );
                            }
                            final e = shown[i];
                            final dayStart = i > 0 && !_sameDay(shown[i - 1].date, e.date);
                            return _entryRow(context, e, zebra: i.isOdd, dayStart: dayStart);
                          },
                        ),
                      ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// One booking: tap edits, swipe right pins it to the quick tiles, swipe
  /// left deletes, "+" adds to it. The same in the list and the calendar.
  Widget _entryRow(BuildContext context, BudgetEntry e, {required bool zebra, required bool dayStart}) {
    final l = AppLocalizations.of(context);
    final budget = widget.budget;
    final settings = AppScope.of(context).settings;
    final scheme = Theme.of(context).colorScheme;
    final pinKey = QuickTile.tileKey(e.category, e.description);
    return Dismissible(
      key: ValueKey(e.pendingId ?? 'row-${e.date.year}-${e.row}'),
      direction: e.description.isEmpty ? DismissDirection.endToStart : DismissDirection.horizontal,
      // Swipe right: pin to the quick tiles (the row stays); swipe left: delete.
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          await _togglePin(context, pinKey, settings.isPinnedTile(pinKey));
          return false;
        }
        return confirmDeleteEntry(context, budget, e);
      },
      background: Container(
        color: scheme.primaryContainer,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: Icon(settings.isPinnedTile(pinKey) ? Icons.push_pin_outlined : Icons.push_pin, color: scheme.onPrimaryContainer),
      ),
      secondaryBackground: Container(
        color: scheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: EntryTile(
        entry: e,
        zebra: zebra,
        dayStart: dayStart,
        onTap: () => editEntry(context, budget, e),
        onLongPress: e.description.isEmpty ? null : () => _togglePin(context, pinKey, settings.isPinnedTile(pinKey)),
        trailing: IconButton(
          tooltip: l.addToEntryShort,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add_circle_outline, size: 20),
          onPressed: () => addToEntryDialog(context, budget, e),
        ),
      ),
    );
  }

  /// The calendar's day: kept while it is in the loaded year; otherwise
  /// today in the current year, or the last booked day of another year.
  DateTime _calendarDayFor(BudgetService budget) {
    final year = budget.year!;
    final d = _day;
    if (d != null && d.year == year) return d;
    final now = budget.now;
    if (year == now.year) return _day = DateTime(now.year, now.month, now.day);
    final booked = [
      for (final e in budget.entries)
        if (e.date.year == year) e.date,
    ];
    if (booked.isEmpty) return _day = DateTime(year);
    final last = booked.reduce((a, b) => a.isAfter(b) ? a : b);
    return _day = DateTime(last.year, last.month, last.day);
  }

  Widget _calendarBody(BuildContext context, BudgetService budget, DateTime day) {
    final l = AppLocalizations.of(context);
    final file = budget.file!;
    final rows = [
      for (final e in budget.entries)
        if (_sameDay(e.date, day)) e,
    ];
    return Column(
      children: [
        BudgetCalendar(
          year: day.year,
          month: day.month,
          selected: day,
          today: budget.now,
          totals: dailyFlow(file, budget.entries, day.year, day.month),
          onSelect: (d) => setState(() => _day = d),
          onMonth: (step) => setState(() {
            final m = day.month + step;
            final now = budget.now;
            // Today when the month has it, else the 1st.
            _day = now.year == day.year && now.month == m ? DateTime(now.year, now.month, now.day) : DateTime(day.year, m);
          }),
        ),
        Builder(
          builder: (context) {
            final monthSoFar = BookingTotals.of(file, budget.entries.where((e) => e.date.year == day.year && e.date.month == day.month && e.date.day <= day.day));
            return CalendarSummary(
              dayLabel: dateDm(day),
              day: BookingTotals.of(file, rows),
              monthLabel: l.monthToDate(dateDm(day)),
              month: monthSoFar,
              monthExpensesColor: limitColor(context, budget.limitLevel(monthSoFar.expenses)),
            );
          },
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: budget.sync,
            child: rows.isEmpty
                ? ListView(
                    padding: const EdgeInsets.only(bottom: 88),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(child: Text(l.noEntriesDay)),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: rows.length,
                    itemBuilder: (context, i) => _entryRow(context, rows[i], zebra: i.isOdd, dayStart: false),
                  ),
          ),
        ),
      ],
    );
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// Long press on a tile or a row: pin the (category, description) to the
  /// quick tiles, or unpin it.
  Future<void> _togglePin(BuildContext context, String key, bool pinned) async {
    final l = AppLocalizations.of(context);
    final settings = AppScope.of(context).settings;
    final messenger = ScaffoldMessenger.of(context);
    await settings.togglePinnedTile(key);
    if (!mounted) return;
    setState(() => _tilesOpen = _tilesOpen || !pinned);
    messenger.showSnackBar(SnackBar(content: Text(pinned ? l.tileUnpinned : l.tilePinned), duration: const Duration(seconds: 2)));
  }
}

class _QuickTileChip extends StatelessWidget {
  const _QuickTileChip({required this.tile, required this.onTap, this.onLongPress});
  final QuickTile tile;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final budget = AppScope.of(context).budget;
    final cat = budget.file?.category(tile.category);
    final color = categoryColor(tile.category, Theme.of(context).brightness, hex: cat?.color);
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border(
              top: BorderSide(color: color, width: 3),
              left: BorderSide(color: scheme.outline),
              right: BorderSide(color: scheme.outline),
              bottom: BorderSide(color: scheme.outline),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: tile.category,
                child: Icon(categoryIcon(cat, tile.category), size: 18, color: color),
              ),
              const SizedBox(width: 8),
              Text(tile.amount == 0 ? tile.description : '${tile.description} · ${euroShort(tile.amount)}', style: const TextStyle(fontWeight: FontWeight.w600)),
              if (tile.pinned) ...[const SizedBox(width: 6), Icon(Icons.push_pin, size: 14, color: scheme.onSurfaceVariant)],
            ],
          ),
        ),
      ),
    );
  }
}
