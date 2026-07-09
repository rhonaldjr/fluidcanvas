import 'package:flutter/material.dart';
import 'package:inkpad/ui/ui.dart';

/// Root widget: owns theming and hosts the app shell.
class InkPadApp extends StatelessWidget {
  const InkPadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InkPad',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.blueGrey),
      home: const AppShell(),
    );
  }
}
