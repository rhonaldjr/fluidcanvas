// Riverpod providers and notifiers.
//
// DocumentSession is one open document plus its own command stack, selection,
// viewport, file path, and dirty flag. There is no global "current document" —
// resolve it from the active session.
export 'brush.dart';
export 'current_shape.dart';
export 'current_stroke.dart';
export 'document_session.dart';
export 'layer_cache_provider.dart';
export 'marquee.dart';
export 'recent_colors.dart';
export 'sessions_notifier.dart';
export 'shape_style.dart';
export 'stabilizer_strength.dart';
export 'text_editing.dart';
export 'tool.dart';
export 'view_state.dart';
