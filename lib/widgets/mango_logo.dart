import 'package:flutter/material.dart';

import '../app/theme.dart';

class MangoLogo extends StatelessWidget {
  const MangoLogo({super.key, this.size = 64});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFB84D), MangoColors.orange, Color(0xFFE65100)],
        ),
        boxShadow: [BoxShadow(color: MangoColors.orange.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      alignment: Alignment.center,
      child: Text('M',
          style: TextStyle(color: Colors.black, fontSize: size * 0.55, fontWeight: FontWeight.w900, height: 1)),
    );
  }
}
