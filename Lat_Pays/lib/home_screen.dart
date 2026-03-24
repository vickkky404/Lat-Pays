import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:ui';
import '../models/meal_entry.dart';
import '../services/storage_service.dart';
import 'main.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  StorageService? _storage;
  List<MealEntry> _monthEntries = [];
  double _mealPrice = 85.0;
  bool _loading = true;

  late AnimationController _fabController;
  late Animation<double> _fabScale;
  DateTime _viewDate = DateTime.now();

  final GlobalKey<SliverAnimatedListState> _listKey = GlobalKey<SliverAnimatedListState>();

  @override
  void initState() {
    super.initState();
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _fabScale = Tween<double>(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(parent: _fabController, curve: Curves.easeInOut),
    );
    _init();
  }

  @override
  void dispose() {
    _fabController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final storage = await StorageService.create();
    _storage = storage;
    _loadEntries();
  }

  void _loadEntries() {
    if (_storage == null) return;
    final entries = _storage!.getEntriesForMonth(_viewDate.year, _viewDate.month);
    setState(() {
      _mealPrice = _storage!.getMealPrice();
      _monthEntries = entries;
      _loading = false;
    });
  }

  Future<void> _changeMonth(int offset) async {
    HapticFeedback.lightImpact();
    setState(() {
      _viewDate = DateTime(_viewDate.year, _viewDate.month + offset);
      _loading = true;
    });
    await Future.delayed(const Duration(milliseconds: 150));
    _loadEntries();
  }

  Future<void> _jumpToToday() async {
    HapticFeedback.mediumImpact();
    final now = DateTime.now();
    if (_viewDate.year == now.year && _viewDate.month == now.month) return;
    setState(() {
      _viewDate = DateTime(now.year, now.month);
      _loading = true;
    });
    await Future.delayed(const Duration(milliseconds: 150));
    _loadEntries();
  }

  Future<void> _logMeal() async {
    if (_storage == null) return;

    final result = await _showAddMealDialog();
    if (result == null) return;

    final DateTime entryTime = result['timestamp'];
    
    // Switch view to the month of the entry if it's different
    if (entryTime.year != _viewDate.year || entryTime.month != _viewDate.month) {
      setState(() {
        _viewDate = DateTime(entryTime.year, entryTime.month);
        _loading = true;
      });
      _loadEntries();
    }

    await _fabController.forward();
    await _fabController.reverse();

    final entry = MealEntry(
      timestamp: entryTime,
      price: _mealPrice,
      category: result['category'],
      note: result['note'],
    );
    
    await _storage!.addEntry(entry);
    
    // Refresh the list as insertion point depends on timestamp
    _loadEntries();
    
    HapticFeedback.mediumImpact();
  }

  Future<void> _removeMeal(int index) async {
    if (_storage == null) return;
    
    final entry = _monthEntries[index];
    await _storage!.removeEntry(entry);

    final removedItem = _monthEntries.removeAt(index);
    _listKey.currentState?.removeItem(
      index,
      (context, animation) => _EntryItem(
        entry: removedItem,
        animation: animation,
        index: index,
        onDelete: () {},
        isRemoving: true,
      ),
      duration: const Duration(milliseconds: 300),
    );

    setState(() {});
    HapticFeedback.lightImpact();
  }

  double get _totalThisMonth => _monthEntries.fold(0.0, (s, e) => s + e.price);
  
  double get _dailyAverage {
    if (_monthEntries.isEmpty) return 0.0;
    final now = DateTime.now();
    final daysInMonth = (_viewDate.month == now.month && _viewDate.year == now.year)
        ? now.day
        : DateTime(_viewDate.year, _viewDate.month + 1, 0).day;
    return _totalThisMonth / daysInMonth;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isCurrentMonth = _viewDate.year == DateTime.now().year && _viewDate.month == DateTime.now().month;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: _loading 
        ? const Center(child: RepaintBoundary(child: CircularProgressIndicator()))
        : CustomScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              _buildAppBar(colorScheme, textTheme, isCurrentMonth),
              SliverToBoxAdapter(
                child: _SummaryCard(
                  total: _totalThisMonth,
                  avg: _dailyAverage,
                  count: _monthEntries.length,
                  onSettings: _showChangePriceDialog,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Text('Recent Log', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.ios_share_rounded, size: 20),
                        onPressed: _exportData,
                        tooltip: 'Export',
                      ),
                    ],
                  ),
                ),
              ),
              if (_monthEntries.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 140),
                  sliver: SliverAnimatedList(
                    key: _listKey,
                    initialItemCount: _monthEntries.length,
                    itemBuilder: (context, index, animation) {
                      return _EntryItem(
                        entry: _monthEntries[index],
                        animation: animation,
                        index: index,
                        onDelete: () => _removeMeal(index),
                      );
                    },
                  ),
                ),
            ],
          ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _FAB(scale: _fabScale, price: _mealPrice, onPressed: _logMeal),
    );
  }

  Widget _buildAppBar(ColorScheme colorScheme, TextTheme textTheme, bool isCurrentMonth) {
    return SliverAppBar(
      expandedHeight: 100,
      collapsedHeight: 64,
      pinned: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: colorScheme.surface,
      centerTitle: false,
      title: Text(
        'Lat Pays',
        style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -1),
      ),
      actions: [
        if (!isCurrentMonth)
          IconButton(
            onPressed: _jumpToToday,
            icon: Icon(Icons.today_rounded, color: colorScheme.primary),
            tooltip: 'Back to Today',
          ),
        _ThemeToggle(),
        _MonthPicker(viewDate: _viewDate, onChange: _changeMonth),
        const SizedBox(width: 8),
      ],
    );
  }

  void _exportData() {
    final buffer = StringBuffer();
    buffer.writeln('Meal Log - ${DateFormat('MMMM yyyy').format(_viewDate)}');
    buffer.writeln('Total: ₹$_totalThisMonth\n');
    for (var e in _monthEntries) {
      buffer.writeln('${DateFormat('dd/MM/yy hh:mm a').format(e.timestamp)} - ${e.category} - ₹${e.price} ${e.note != null ? "(${e.note})" : ""}');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Log copied to clipboard!')),
    );
  }

  Future<Map<String, dynamic>?> _showAddMealDialog() async {
    String category = 'Lunch';
    DateTime selectedDate = DateTime.now();
    final noteController = TextEditingController();
    
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 16),
                  Text('New Meal Log', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 24),
                  
                  // Date Picker Row
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        if (!context.mounted) return;
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(selectedDate),
                        );
                        if (time != null) {
                          setModalState(() {
                            selectedDate = DateTime(
                              picked.year, picked.month, picked.day,
                              time.hour, time.minute
                            );
                          });
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today_rounded, size: 18, color: Theme.of(ctx).colorScheme.primary),
                          const SizedBox(width: 12),
                          Text(
                            DateFormat('EEEE, d MMMM · hh:mm a').format(selectedDate),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          const Icon(Icons.edit_rounded, size: 16),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: ['Breakfast', 'Lunch', 'Dinner', 'Other'].map((cat) {
                        final isSelected = category == cat;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text(cat),
                            selected: isSelected,
                            onSelected: (val) => setModalState(() => category = cat),
                            showCheckmark: false,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: noteController,
                    decoration: InputDecoration(
                      hintText: 'Add a note (optional)',
                      filled: true,
                      fillColor: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, {
                      'category': category, 
                      'note': noteController.text.trim(),
                      'timestamp': selectedDate,
                    }),
                    style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
                    child: const Text('Confirm Entry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showChangePriceDialog() async {
    final controller = TextEditingController(text: _mealPrice.toStringAsFixed(0));
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 12, 32, 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 32),
                Text('Settings', style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 24),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  autofocus: true,
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900),
                  decoration: InputDecoration(
                    prefixText: '₹',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    filled: true,
                    fillColor: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: () {
                    final p = double.tryParse(controller.text);
                    if (p != null) {
                      _storage?.setMealPrice(p);
                      setState(() => _mealPrice = p);
                      Navigator.pop(ctx);
                    }
                  },
                  style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 60)),
                  child: const Text('Update Default Price'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Optimized & Repaint-Aware Components ──

class _SummaryCard extends StatelessWidget {
  final double total;
  final double avg;
  final int count;
  final VoidCallback onSettings;

  const _SummaryCard({required this.total, required this.avg, required this.count, required this.onSettings});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            gradient: LinearGradient(
              colors: [colorScheme.primary, colorScheme.primary.withValues(alpha: 0.85)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(color: colorScheme.primary.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 10)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('MONTHLY TOTAL', style: textTheme.labelSmall?.copyWith(color: colorScheme.onPrimary.withValues(alpha: 0.7), fontWeight: FontWeight.w900, letterSpacing: 1)),
                        const SizedBox(height: 4),
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: total),
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeOutCubic,
                          builder: (_, value, _) => Text(
                            '₹${NumberFormat('#,##0').format(value)}',
                            style: textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900, color: colorScheme.onPrimary, letterSpacing: -1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _GlassButton(icon: Icons.tune_rounded, onTap: onSettings),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  _StatTile(label: 'Avg/Day', value: '₹${avg.toStringAsFixed(0)}', icon: Icons.insights_rounded),
                  const SizedBox(width: 12),
                  _StatTile(label: 'Logged', value: '$count', icon: Icons.fastfood_rounded),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryItem extends StatelessWidget {
  final MealEntry entry;
  final Animation<double> animation;
  final int index;
  final VoidCallback onDelete;
  final bool isRemoving;

  const _EntryItem({required this.entry, required this.animation, required this.index, required this.onDelete, this.isRemoving = false});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return FadeTransition(
      opacity: animation,
      child: SizeTransition(
        sizeFactor: animation,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Dismissible(
            key: ValueKey(entry.timestamp.millisecondsSinceEpoch),
            direction: isRemoving ? DismissDirection.none : DismissDirection.endToStart,
            onDismissed: (_) => onDelete(),
            background: _DeleteBackground(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  _CategoryIcon(category: entry.category),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.category, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        Text(
                          '${DateFormat('EEE, d MMM').format(entry.timestamp)} · ${DateFormat('hh:mm a').format(entry.timestamp)}',
                          style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                        if (entry.note != null && entry.note!.isNotEmpty)
                           Padding(
                             padding: const EdgeInsets.only(top: 4),
                             child: Text(entry.note!, style: textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                           ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('₹${entry.price.toStringAsFixed(0)}', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: colorScheme.primary)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryIcon extends StatelessWidget {
  final String category;
  const _CategoryIcon({required this.category});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    IconData icon;
    switch (category) {
      case 'Breakfast': icon = Icons.wb_twilight_rounded; break;
      case 'Lunch': icon = Icons.wb_sunny_rounded; break;
      case 'Dinner': icon = Icons.nightlight_round; break;
      default: icon = Icons.restaurant_rounded;
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
      child: Icon(icon, size: 22, color: colorScheme.primary),
    );
  }
}

class _FAB extends StatelessWidget {
  final Animation<double> scale;
  final double price;
  final VoidCallback onPressed;
  const _FAB({required this.scale, required this.price, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ScaleTransition(
      scale: scale,
      child: RepaintBoundary(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(32), boxShadow: [
            BoxShadow(color: colorScheme.primary.withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 8)),
          ]),
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 68), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add_circle_outline_rounded, size: 26),
                const SizedBox(width: 12),
                const Text('Log New Meal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: colorScheme.onPrimary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                  child: Text('₹${price.toStringAsFixed(0)}', style: TextStyle(color: colorScheme.onPrimary, fontWeight: FontWeight.w900, fontSize: 14)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeMode = LatPaysApp.of(context).themeMode;
    IconData icon = themeMode == ThemeMode.system ? Icons.brightness_auto_rounded : themeMode == ThemeMode.light ? Icons.light_mode_rounded : Icons.dark_mode_rounded;

    return IconButton(
      icon: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: colorScheme.surfaceContainerHigh, shape: BoxShape.circle), child: Icon(icon, size: 18)),
      onPressed: () {
        final modes = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
        LatPaysApp.of(context).setThemeMode(modes[(modes.indexOf(themeMode) + 1) % 3]);
        HapticFeedback.selectionClick();
      },
    );
  }
}

class _MonthPicker extends StatelessWidget {
  final DateTime viewDate;
  final Function(int) onChange;
  const _MonthPicker({required this.viewDate, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(icon: const Icon(Icons.keyboard_arrow_left_rounded, size: 20), onPressed: () => onChange(-1)),
          Text(DateFormat('MMM yy').format(viewDate), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
          IconButton(icon: const Icon(Icons.keyboard_arrow_right_rounded, size: 20), onPressed: () => onChange(1)),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _StatTile({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: colorScheme.onPrimary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            Icon(icon, size: 16, color: colorScheme.onPrimary.withValues(alpha: 0.8)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(color: colorScheme.onPrimary.withValues(alpha: 0.6), fontWeight: FontWeight.w700, fontSize: 10), overflow: TextOverflow.ellipsis),
                Text(value, style: TextStyle(color: colorScheme.onPrimary, fontWeight: FontWeight.w900, fontSize: 14), overflow: TextOverflow.ellipsis),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: colorScheme.onPrimary.withValues(alpha: 0.15), shape: BoxShape.circle),
        child: Icon(icon, color: colorScheme.onPrimary, size: 20),
      ),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.only(right: 24),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer, borderRadius: BorderRadius.circular(24)),
    child: Icon(Icons.delete_forever_rounded, color: Theme.of(context).colorScheme.onErrorContainer),
  );
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.layers_clear_rounded, size: 64, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)),
        const SizedBox(height: 16),
        Text('No data for this month', style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    ),
  );
}
