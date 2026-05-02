import 'package:cltapp/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('renders calculator home', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const CltFlutterApp());
    await tester.pump();

    expect(find.text('CLT Brasil'), findsWidgets);
    expect(find.byType(ChoiceChip), findsNWidgets(7));
  });
}
