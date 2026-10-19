import 'package:flutter/material.dart';

import '../models/build_job_model.dart';
import 'status_badge.dart';

class ProjectCard extends StatelessWidget {
  const ProjectCard({super.key, required this.job, this.onTap, this.trailing});
  final BuildJob job;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(job.projectName.isEmpty ? job.id : job.projectName,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text('${job.packageName}  •  ${job.versionName}',
                        style: Theme.of(context).textTheme.bodySmall, textDirection: TextDirection.ltr),
                    const SizedBox(height: 2),
                    Text(job.createdAt.toLocal().toString().substring(0, 16),
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                StatusBadge(job.stage),
                if (trailing != null) trailing!,
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
