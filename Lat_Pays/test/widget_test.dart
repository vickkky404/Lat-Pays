import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lat_pays/main.dart';
import 'package:lat_pays/services/storage_service.dart';

void main() {
  testWidgets('App launches smoke test', (WidgetTester tester) async {
    final storage = await StorageService.create();
    await tester.pumpWidget(LatPaysApp(storage: storage));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
