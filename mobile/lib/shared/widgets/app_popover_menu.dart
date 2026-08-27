import 'package:flutter/material.dart';

const _popoverForest = Color(0xFF174936);
const _popoverPaper = Color(0xFFFFFDF7);
const _popoverSelected = Color(0xFFE4F0E7);
const _popoverBorder = Color(0xFFE2DDCF);

class AppPopoverAction<T> {
  const AppPopoverAction({
    required this.value,
    required this.label,
    required this.icon,
    this.selected = false,
    this.destructive = false,
  });

  final T value;
  final String label;
  final IconData icon;
  final bool selected;
  final bool destructive;
}

class AppPopoverMenu<T> extends StatelessWidget {
  const AppPopoverMenu({
    super.key,
    required this.actions,
    required this.onSelected,
    required this.child,
    this.tooltip,
    this.minWidth = 190,
  });

  final List<AppPopoverAction<T>> actions;
  final ValueChanged<T> onSelected;
  final Widget child;
  final String? tooltip;
  final double minWidth;

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
    tooltip: tooltip,
    position: PopupMenuPosition.under,
    offset: const Offset(0, 8),
    color: _popoverPaper,
    surfaceTintColor: Colors.transparent,
    shadowColor: const Color(0x331A352B),
    elevation: 10,
    constraints: BoxConstraints(minWidth: minWidth, maxWidth: 244),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: _popoverBorder),
    ),
    menuPadding: const EdgeInsets.all(7),
    onSelected: onSelected,
    itemBuilder: (context) => [
      for (final action in actions)
        PopupMenuItem<T>(
          value: action.value,
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: action.selected ? _popoverSelected : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: action.destructive
                          ? const Color(0xFFFFE9E5)
                          : action.selected
                          ? const Color(0xFFD1E6D7)
                          : const Color(0xFFF2EFE7),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      action.icon,
                      size: 17,
                      color: action.destructive
                          ? const Color(0xFFB33A2E)
                          : _popoverForest,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      action.label,
                      style: TextStyle(
                        color: action.destructive
                            ? const Color(0xFF9F3027)
                            : const Color(0xFF20332B),
                        fontWeight: action.selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (action.selected)
                    const Icon(
                      Icons.check_rounded,
                      size: 19,
                      color: _popoverForest,
                    ),
                ],
              ),
            ),
          ),
        ),
    ],
    child: child,
  );
}
