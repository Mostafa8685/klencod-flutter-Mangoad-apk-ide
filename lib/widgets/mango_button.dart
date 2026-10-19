import 'package:flutter/material.dart';

import '../app/theme.dart';

class MangoButton extends StatelessWidget {
  const MangoButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.outlined = false,
    this.color,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool outlined;
  final Color? color;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = color ?? MangoColors.orange;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (loading)
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
        else if (icon != null)
          Icon(icon, size: 20),
        if (loading || icon != null) const SizedBox(width: 8),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    final size = const Size.fromHeight(50);
    final cb = loading ? null : onPressed;
    return outlined
        ? OutlinedButton(
            onPressed: cb,
            style: OutlinedButton.styleFrom(minimumSize: size, shape: shape, side: BorderSide(color: c), foregroundColor: c),
            child: child,
          )
        : FilledButton(
            onPressed: cb,
            style: FilledButton.styleFrom(
              minimumSize: size,
              shape: shape,
              backgroundColor: c,
              foregroundColor: c == MangoColors.orange ? Colors.black : Colors.white,
            ),
            child: child,
          );
  }
}
