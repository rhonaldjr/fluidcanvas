import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/state/brush.dart';
import 'package:inkpad/state/shape_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bounds on the autosave interval, in minutes. Zero turns autosave off.
const int kMinAutosaveMinutes = 0;
const int kMaxAutosaveMinutes = 60;

/// The settings that outlive a run, and what they start as.
///
/// Everything here is a *default* applied to new work, not a document
/// property: changing the default canvas size never resizes an open document,
/// and changing the default brush never repaints a stroke already drawn.
class Preferences {
  const Preferences({
    this.canvasWidth = 1920,
    this.canvasHeight = 1080,
    this.fitNewToWindow = true,
    this.autosaveMinutes = 3,
    this.brush = const Brush(),
    this.shapeStyle = const ShapeStyle(),
    this.themeMode = ThemeMode.system,
  });

  /// What File → New offers before the user changes it.
  final int canvasWidth;
  final int canvasHeight;
  final bool fitNewToWindow;

  /// How often dirty documents autosave. Zero disables it entirely.
  final int autosaveMinutes;

  final Brush brush;
  final ShapeStyle shapeStyle;
  final ThemeMode themeMode;

  bool get autosaveEnabled => autosaveMinutes > 0;

  Duration get autosaveInterval => Duration(minutes: autosaveMinutes);

  Preferences copyWith({
    int? canvasWidth,
    int? canvasHeight,
    bool? fitNewToWindow,
    int? autosaveMinutes,
    Brush? brush,
    ShapeStyle? shapeStyle,
    ThemeMode? themeMode,
  }) => Preferences(
    canvasWidth: canvasWidth ?? this.canvasWidth,
    canvasHeight: canvasHeight ?? this.canvasHeight,
    fitNewToWindow: fitNewToWindow ?? this.fitNewToWindow,
    autosaveMinutes: autosaveMinutes ?? this.autosaveMinutes,
    brush: brush ?? this.brush,
    shapeStyle: shapeStyle ?? this.shapeStyle,
    themeMode: themeMode ?? this.themeMode,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Preferences &&
          canvasWidth == other.canvasWidth &&
          canvasHeight == other.canvasHeight &&
          fitNewToWindow == other.fitNewToWindow &&
          autosaveMinutes == other.autosaveMinutes &&
          brush == other.brush &&
          shapeStyle == other.shapeStyle &&
          themeMode == other.themeMode;

  @override
  int get hashCode => Object.hash(
    canvasWidth,
    canvasHeight,
    fitNewToWindow,
    autosaveMinutes,
    brush,
    shapeStyle,
    themeMode,
  );
}

/// The keys the preferences live under. Named, not derived, because renaming a
/// field must not silently forget what a user has already set.
abstract final class PrefKeys {
  static const canvasWidth = 'pref.canvasWidth';
  static const canvasHeight = 'pref.canvasHeight';
  static const fitNewToWindow = 'pref.fitNewToWindow';
  static const autosaveMinutes = 'pref.autosaveMinutes';
  static const brushColor = 'pref.brush.color';
  static const brushWidth = 'pref.brush.width';
  static const shapeStroke = 'pref.shape.strokeColor';
  static const shapeFill = 'pref.shape.fillColor';
  static const shapeWidth = 'pref.shape.strokeWidth';
  static const shapeStyle = 'pref.shape.strokeStyle';
  static const themeMode = 'pref.themeMode';
}

/// Loads and saves [Preferences].
///
/// A stored value that is out of range — hand-edited, or written by a build
/// with different limits — is clamped rather than trusted, so a bad file
/// cannot produce a 0px brush or a 3px canvas.
class PreferencesNotifier extends AsyncNotifier<Preferences> {
  @override
  Future<Preferences> build() async {
    final prefs = await SharedPreferences.getInstance();
    const fallback = Preferences();

    return Preferences(
      canvasWidth: prefs.getInt(PrefKeys.canvasWidth) ?? fallback.canvasWidth,
      canvasHeight:
          prefs.getInt(PrefKeys.canvasHeight) ?? fallback.canvasHeight,
      fitNewToWindow:
          prefs.getBool(PrefKeys.fitNewToWindow) ?? fallback.fitNewToWindow,
      autosaveMinutes:
          (prefs.getInt(PrefKeys.autosaveMinutes) ?? fallback.autosaveMinutes)
              .clamp(kMinAutosaveMinutes, kMaxAutosaveMinutes),
      brush: Brush(
        colorRGBA:
            prefs.getInt(PrefKeys.brushColor) ?? fallback.brush.colorRGBA,
        baseWidth:
            (prefs.getDouble(PrefKeys.brushWidth) ?? fallback.brush.baseWidth)
                .clamp(kMinBrushWidth, kMaxBrushWidth),
      ),
      shapeStyle: ShapeStyle(
        strokeColorRGBA:
            prefs.getInt(PrefKeys.shapeStroke) ??
            fallback.shapeStyle.strokeColorRGBA,
        fillColorRGBA:
            prefs.getInt(PrefKeys.shapeFill) ??
            fallback.shapeStyle.fillColorRGBA,
        strokeWidth:
            (prefs.getDouble(PrefKeys.shapeWidth) ??
                    fallback.shapeStyle.strokeWidth)
                .clamp(1, 64),
        strokeStyle: _enumFrom(
          StrokeStyle.values,
          prefs.getInt(PrefKeys.shapeStyle),
          fallback.shapeStyle.strokeStyle,
        ),
      ),
      themeMode: _enumFrom(
        ThemeMode.values,
        prefs.getInt(PrefKeys.themeMode),
        fallback.themeMode,
      ),
    );
  }

  /// Writes [next] and applies it to the live brush and shape style.
  Future<void> save(Preferences next) async {
    state = AsyncData(next);
    _applyToSession(next);

    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setInt(PrefKeys.canvasWidth, next.canvasWidth),
      prefs.setInt(PrefKeys.canvasHeight, next.canvasHeight),
      prefs.setBool(PrefKeys.fitNewToWindow, next.fitNewToWindow),
      prefs.setInt(PrefKeys.autosaveMinutes, next.autosaveMinutes),
      prefs.setInt(PrefKeys.brushColor, next.brush.colorRGBA),
      prefs.setDouble(PrefKeys.brushWidth, next.brush.baseWidth),
      prefs.setInt(PrefKeys.shapeStroke, next.shapeStyle.strokeColorRGBA),
      prefs.setInt(PrefKeys.shapeFill, next.shapeStyle.fillColorRGBA),
      prefs.setDouble(PrefKeys.shapeWidth, next.shapeStyle.strokeWidth),
      prefs.setInt(PrefKeys.shapeStyle, next.shapeStyle.strokeStyle.index),
      prefs.setInt(PrefKeys.themeMode, next.themeMode.index),
    ]);
  }

  /// Forgets every stored preference and returns to the defaults.
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      for (final key in [
        PrefKeys.canvasWidth,
        PrefKeys.canvasHeight,
        PrefKeys.fitNewToWindow,
        PrefKeys.autosaveMinutes,
        PrefKeys.brushColor,
        PrefKeys.brushWidth,
        PrefKeys.shapeStroke,
        PrefKeys.shapeFill,
        PrefKeys.shapeWidth,
        PrefKeys.shapeStyle,
        PrefKeys.themeMode,
      ])
        prefs.remove(key),
    ]);
    const defaults = Preferences();
    state = const AsyncData(defaults);
    _applyToSession(defaults);
  }

  /// The default brush and shape style are what the toolbar starts holding.
  void _applyToSession(Preferences next) {
    ref.read(brushProvider.notifier)
      ..setColor(next.brush.colorRGBA)
      ..setWidth(next.brush.baseWidth);
    ref.read(shapeStyleProvider.notifier).set(next.shapeStyle);
  }
}

final preferencesProvider =
    AsyncNotifierProvider<PreferencesNotifier, Preferences>(
      PreferencesNotifier.new,
    );

/// The theme the app is drawn with. Falls back to the system while loading.
final themeModeProvider = Provider<ThemeMode>(
  (ref) => ref.watch(preferencesProvider).value?.themeMode ?? ThemeMode.system,
);

/// Reads [values] by stored index, tolerating an index no build has.
T _enumFrom<T>(List<T> values, int? index, T fallback) =>
    index != null && index >= 0 && index < values.length
    ? values[index]
    : fallback;
