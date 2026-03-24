import 'dart:convert';

class MealEntry {
  final DateTime timestamp;
  final double price;
  final String category;
  final String? note;

  const MealEntry({
    required this.timestamp,
    required this.price,
    this.category = 'Other',
    this.note,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'price': price,
        'category': category,
        'note': note,
      };

  factory MealEntry.fromJson(Map<String, dynamic> json) => MealEntry(
        timestamp: DateTime.parse(json['timestamp'] as String),
        price: (json['price'] as num).toDouble(),
        category: json['category'] as String? ?? 'Other',
        note: json['note'] as String?,
      );

  static String encodeList(List<MealEntry> entries) =>
      jsonEncode(entries.map((e) => e.toJson()).toList());

  static List<MealEntry> decodeList(String source) {
    final List<dynamic> decoded = jsonDecode(source) as List<dynamic>;
    return decoded
        .map((e) => MealEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
