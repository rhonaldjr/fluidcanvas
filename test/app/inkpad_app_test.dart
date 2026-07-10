import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/app/app.dart';
import 'package:inkpad/ui/ui.dart';

void main() {
  testWidgets('app boots into the shell with the title InkPad', (tester) async {
    // main.dart supplies the ProviderScope; the canvas reads the active
    // document, so the widget cannot be pumped bare.
    await tester.pumpWidget(const ProviderScope(child: InkPadApp()));

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'InkPad');
    expect(find.byType(AppShell), findsOneWidget);
  });
}
