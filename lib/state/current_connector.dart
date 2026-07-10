import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/domain/models/models.dart';

/// The connector being dragged out, or `null` between drags.
///
/// Lives beside [currentShapeProvider]: it is drawn live into the active layer
/// and never reaches the document until the pointer lifts.
class CurrentConnectorNotifier extends Notifier<Connector?> {
  @override
  Connector? build() => null;

  void set(Connector connector) => state = connector;

  void clear() => state = null;
}

final currentConnectorProvider =
    NotifierProvider<CurrentConnectorNotifier, Connector?>(
      CurrentConnectorNotifier.new,
    );
