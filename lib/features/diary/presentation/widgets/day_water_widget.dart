import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/water_intake_entity.dart';
import 'package:opennutritracker/core/utils/water_format.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Inspection only: historical totals carry no assumption about past goals.
class DayWaterWidget extends StatelessWidget {
  final List<WaterIntakeEntity> entries;
  const DayWaterWidget({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final sorted = [...entries]
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    final total = entries.fold(0, (sum, entry) => sum + entry.amountMl);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        key: const Key('diary-water'),
        leading: const Icon(Icons.water_drop_outlined),
        title: Text(s.trendsWaterLabel),
        subtitle: Text('${WaterFormat.litresText(total)} ${s.litreLabel}'),
        children: [
          if (sorted.isEmpty) ListTile(title: Text(s.nothingAddedLabel)),
          for (final entry in sorted)
            ListTile(
              title: Text('${entry.amountMl} ml'),
              subtitle: Text(
                entry.id.startsWith('lifesum-estimated-water-')
                    ? s.lifesumImportWaterTitle
                    : MaterialLocalizations.of(context).formatTimeOfDay(
                        TimeOfDay.fromDateTime(entry.dateTime),
                        alwaysUse24HourFormat:
                            MediaQuery.alwaysUse24HourFormatOf(context),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}
