import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/commands/commands.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/system_fonts.dart';
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/ui.dart';

/// The families a fake machine has. Fontconfig is never run in a test.
const _installed = ['DejaVu Sans', 'Liberation Serif'];

Future<ProviderContainer> pumpShell(
  WidgetTester tester, {
  List<String> installed = _installed,
}) async {
  await tester.binding.setSurfaceSize(const Size(1100, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final container = ProviderContainer.test(
    overrides: [
      systemFontsProvider.overrideWith((ref) async => installed),
      // The test binding resolves every family to the same test font, so the
      // real probe would call them all missing.
      fontAvailabilityProvider.overrideWithValue(
        (family) => family.isEmpty || installed.contains(family),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AppShell()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

TextElement _text({String family = '', int color = 0x1B1B1FFF}) =>
    TextElement.plain(
      id: 't',
      x: 40,
      y: 40,
      w: 200,
      h: 60,
      text: 'hello',
    ).copyWith(fontFamily: family, colorRGBA: color);

/// Adds [element] and selects it.
void place(ProviderContainer c, TextElement element) {
  c.read(toolProvider.notifier).select(Tool.select);
  c.read(sessionsProvider.notifier)
    ..run(
      AddElementCommand(
        layerId: c.read(activeSessionProvider).activeLayer.id,
        element: element,
      ),
    )
    ..setSelection({element.id});
}

TextElement only(ProviderContainer c) => c
    .read(activeDocumentProvider)
    .layers
    .expand((l) => l.elements)
    .whereType<TextElement>()
    .single;

void main() {
  group('10.8 isFontAvailable', () {
    test('the empty family is the system default, always present', () {
      expect(isFontAvailable(''), isTrue);
    });

    test('the probe family is by construction absent', () {
      // In a test binding every family resolves to the same font, so this is
      // the one assertion the measurement can make here. The interesting case
      // is covered by overriding fontAvailabilityProvider.
      expect(isFontAvailable(kMissingFamilyProbe), isFalse);
    });

    test('the fallback list is non-empty and free of duplicates', () {
      expect(kFallbackFontFamilies, isNotEmpty);
      expect(
        kFallbackFontFamilies.toSet(),
        hasLength(kFallbackFontFamilies.length),
      );
    });
  });

  group('10.8 family picker', () {
    testWidgets('lists the system default and every installed family', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      place(container, _text());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('text-family')));
      await tester.pumpAndSettle();

      expect(find.text('System'), findsWidgets);
      for (final family in _installed) {
        expect(find.text(family), findsWidgets);
      }
    });

    testWidgets('choosing a family restyles the selected box, undoably', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      place(container, _text());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('text-family')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DejaVu Sans').last);
      await tester.pumpAndSettle();

      expect(only(container).fontFamily, 'DejaVu Sans');
      expect(container.read(textStyleProvider).fontFamily, 'DejaVu Sans');

      container.read(sessionsProvider.notifier).undo();
      await tester.pump();
      expect(only(container).fontFamily, '');
    });

    testWidgets('with nothing selected it only sets the default for new text', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      container.read(toolProvider.notifier).select(Tool.text);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('text-family')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Liberation Serif').last);
      await tester.pumpAndSettle();

      expect(container.read(textStyleProvider).fontFamily, 'Liberation Serif');
      expect(container.read(activeSessionProvider).canUndo, isFalse);
    });
  });

  group('10.8 missing font notice', () {
    testWidgets('a family this machine lacks is called out', (tester) async {
      final container = await pumpShell(tester);
      place(container, _text(family: 'Comic Sans MS'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('text-font-missing')), findsOneWidget);
      expect(find.text('missing'), findsOneWidget);
    });

    testWidgets('the picker still shows the family the file asked for', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      place(container, _text(family: 'Comic Sans MS'));
      await tester.pumpAndSettle();

      expect(find.text('Comic Sans MS'), findsWidgets);
    });

    testWidgets('an installed family is not called out', (tester) async {
      final container = await pumpShell(tester);
      place(container, _text(family: 'DejaVu Sans'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('text-font-missing')), findsNothing);
    });

    testWidgets('nor is the system default', (tester) async {
      final container = await pumpShell(tester);
      place(container, _text());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('text-font-missing')), findsNothing);
    });
  });

  group('10.8 text colour', () {
    testWidgets('the swatch opens the picker and recolours the box', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      place(container, _text());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('text-color')));
      await tester.pumpAndSettle();

      // The 4.3 dialog: pick a hue, then accept.
      final hue = tester.getCenter(find.byKey(const Key('hue-slider')));
      await tester.tapAt(hue);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('color-picker-ok')));
      await tester.pumpAndSettle();

      final picked = only(container).colorRGBA;
      expect(picked, isNot(0x1B1B1FFF), reason: 'the box took the new colour');
      expect(container.read(textStyleProvider).colorRGBA, picked);
      expect(container.read(recentColorsProvider), contains(picked));
      // One command for the add, one for the restyle.
      expect(
        container.read(activeSessionProvider).commands.undoStack,
        hasLength(2),
      );
    });

    testWidgets('cancelling changes nothing', (tester) async {
      final container = await pumpShell(tester);
      place(container, _text());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('text-color')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(only(container).colorRGBA, 0x1B1B1FFF);
      expect(container.read(activeSessionProvider).canUndo, isTrue); // the add
      expect(
        container.read(activeSessionProvider).commands.undoStack,
        hasLength(1),
      );
    });
  });
}
