import 'package:flutter/material.dart';

/// The File/Edit menu bar.
///
/// Every item is disabled: this is layout only. Phase 5.3 wires up Edit, and
/// Phase 9 wires up File.
class AppMenuBar extends StatelessWidget {
  const AppMenuBar({super.key});

  static const _fileItems = ['New', 'Open…', 'Save', 'Save As…', 'Export PNG…'];
  static const _editItems = ['Undo', 'Redo', 'Delete', 'Duplicate'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      // MenuBar centers its children and paints its own surface; neither is
      // wanted here.
      child: Align(
        alignment: Alignment.centerLeft,
        child: MenuBar(
          style: const MenuStyle(
            elevation: WidgetStatePropertyAll(0),
            backgroundColor: WidgetStatePropertyAll(Colors.transparent),
            surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
            shape: WidgetStatePropertyAll(RoundedRectangleBorder()),
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 4),
            ),
          ),
          children: [_menu('File', _fileItems), _menu('Edit', _editItems)],
        ),
      ),
    );
  }

  Widget _menu(String label, List<String> items) {
    return SubmenuButton(
      menuChildren: [
        for (final item in items)
          // Null onPressed renders the item disabled.
          MenuItemButton(onPressed: null, child: Text(item)),
      ],
      child: Text(label),
    );
  }
}
