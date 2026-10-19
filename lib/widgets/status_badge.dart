import 'package:flutter/material.dart';

import '../app/localization.dart';
import '../models/build_job_model.dart';
import '../app/theme.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.stage, {super.key});
  final BuildStage stage;

  @override
  Widget build(BuildContext context) {
    final color = switch (stage) {
      BuildStage.completed => const Color(0xFF3FB950),
      BuildStage.failed => const Color(0xFFF85149),
      BuildStage.waiting => Colors.grey,
      _ => MangoColors.orange,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(L.t('stage_${stage.name}'), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
