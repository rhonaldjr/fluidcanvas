import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/app/app.dart';

/// [args] carries a `.skd` the OS was asked to open with InkPad.
void main(List<String> args) {
  runApp(ProviderScope(child: InkPadApp(startupFiles: skdPathsIn(args))));
}
