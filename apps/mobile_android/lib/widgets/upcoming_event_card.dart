import 'package:flutter/material.dart';

import '../social_service.dart';

/// Small tappable card shown on the Run tab idle state when the user has
/// RSVP'd "going" to a club event within the next 48 hours. Replaces the
/// last-run card in that window so the imminent commitment gets priority.
class UpcomingEventCard extends StatelessWidget {
  final EventView event;
  final VoidCallback? onTap;
  const UpcomingEventCard({super.key, required this.event, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final when = event.nextInstanceStart;
    final relative = _relativeFromNow(when);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primaryContainer,
              theme.colorScheme.surfaceContainerHighest,
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary,
              ),
              child: const Icon(Icons.event, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RSVP\'D · $relative',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      letterSpacing: 0.7,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    event.row.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 13,
                          color: theme.colorScheme.outline),
                      const SizedBox(width: 3),
                      Text(
                        fmtEventDate(when),
                        style: theme.textTheme.bodySmall,
                      ),
                      if (event.row.meetLabel != null) ...[
                        const SizedBox(width: 10),
                        Icon(Icons.place, size: 13,
                            color: theme.colorScheme.outline),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            event.row.meetLabel!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _relativeFromNow(DateTime when) {
    final diff = when.difference(DateTime.now());
    if (diff.inMinutes < 60) {
      return diff.inMinutes <= 1 ? 'Starting now' : 'In ${diff.inMinutes} min';
    }
    if (diff.inHours < 24) {
      return diff.inHours == 1 ? 'In 1 hour' : 'In ${diff.inHours} hours';
    }
    if (diff.inHours < 48) return 'Tomorrow';
    return 'In ${diff.inDays} days';
  }
}
