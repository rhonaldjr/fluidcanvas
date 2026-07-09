import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/app/app.dart';
import 'package:inkpad/ui/ui.dart';

void main() {
  testWidgets('app boots into the shell with the title InkPad', (tester) async {
    await tester.pumpWidget(const InkPadApp());

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'InkPad');
    expect(find.byType(AppShell), findsOneWidget);
  });
}
