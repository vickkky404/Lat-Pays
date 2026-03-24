import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/meal_entry.dart';

class StorageService {
  static const String _entriesKey = 'meal_entries';
  static const String _priceKey = 'meal_price';
  static const String _themeKey = 'app_theme';
  static const double _defaultPrice = 85.0;

  final SharedPreferences _prefs;
  List<MealEntry>? _cachedEntries;

  StorageService._(this._prefs);

  static Future<StorageService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService._(prefs);
  }

  // --------------- Theme Mode ---------------

  ThemeMode getThemeMode() {
    final val = _prefs.getString(_themeKey);
    if (val == 'light') return ThemeMode.light;
    if (val == 'dark') return ThemeMode.dark;
    return ThemeMode.system;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setString(_themeKey, mode.name);
  }

  // --------------- Meal Price ---------------

  double getMealPrice() => _prefs.getDouble(_priceKey) ?? _defaultPrice;

  Future<void> setMealPrice(double price) =>
      _prefs.setDouble(_priceKey, price);

  // --------------- Meal Entries ---------------

  List<MealEntry> getAllEntries() {
    if (_cachedEntries != null) return List.from(_cachedEntries!);
    
    final raw = _prefs.getString(_entriesKey);
    if (raw == null || raw.isEmpty) {
      _cachedEntries = [];
      return [];
    }
    _cachedEntries = MealEntry.decodeList(raw);
    return List.from(_cachedEntries!);
  }

  Future<void> addEntry(MealEntry entry) async {
    final entries = getAllEntries()..add(entry);
    _cachedEntries = entries;
    await _prefs.setString(_entriesKey, MealEntry.encodeList(entries));
  }

  Future<void> removeEntry(MealEntry entry) async {
    final entries = getAllEntries();
    entries.removeWhere((e) => e.timestamp == entry.timestamp);
    _cachedEntries = entries;
    await _prefs.setString(_entriesKey, MealEntry.encodeList(entries));
  }

  List<MealEntry> getEntriesForMonth(int year, int month) {
    return getAllEntries()
        .where((e) => e.timestamp.year == year && e.timestamp.month == month)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp)); // newest first
  }

  double getTotalForMonth(int year, int month) {
    return getEntriesForMonth(year, month)
        .fold(0.0, (sum, e) => sum + e.price);
  }
}
