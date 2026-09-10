import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../core/theme.dart';
import '../services/local_feeding_provider.dart';

/// Exact visual restoration of the original FeedingSection - zone
/// tabs, an add-schedule card with a time field and a stepper for
/// grams, and a schedule list with a toggle + delete per row. Backed
/// by SQLite now instead of a backend.
class LocalFeedingSection extends StatefulWidget {
  const LocalFeedingSection({super.key});

  @override
  State<LocalFeedingSection> createState() => _LocalFeedingSectionState();
}

class _LocalFeedingSectionState extends State<LocalFeedingSection> {
  String _selectedZone = 'zone_1';
  final _timeController = TextEditingController(text: '08:00');
  double _amount = 100;

  static const _zones = ['zone_1', 'zone_2', 'zone_3'];
  static const _zoneLabels = {'zone_1': 'Zone 1', 'zone_2': 'Zone 2', 'zone_3': 'Zone 3'};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LocalFeedingProvider>().fetchSchedules();
    });
  }

  Future<void> _onAdd() async {
    await context.read<LocalFeedingProvider>().createSchedule('${_timeController.text}:00', _amount, _selectedZone);
  }

  @override
  Widget build(BuildContext context) {
    final feeding = context.watch<LocalFeedingProvider>();
    final zoneSchedules = feeding.schedules.where((s) => s.zone == _selectedZone).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
          child: const Row(children: [
            Icon(LucideIcons.info, size: 14, color: AppColors.primary),
            SizedBox(width: 8),
            Expanded(child: Text('Feeds automatically while the app is open at the scheduled time. Use Feed Now for guaranteed feeding anytime.', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.3))),
          ]),
        ),
        Row(
          children: _zones.map((z) {
            final selected = z == _selectedZone;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedZone = z),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.primary : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: selected ? AppColors.primary : AppColors.border),
                    ),
                    child: Text(_zoneLabels[z]!, textAlign: TextAlign.center,
                        style: TextStyle(color: selected ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.card),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add Feeding Schedule', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 16),
              const Text('Time', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(controller: _timeController, decoration: const InputDecoration(hintText: '08:00')),
              const SizedBox(height: 16),
              Text('Feed Amount: ${_amount.toInt()}g', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
              Row(
                children: [
                  IconButton(icon: Icon(LucideIcons.minus), onPressed: () => setState(() => _amount = (_amount - 5).clamp(10, 500))),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(color: const Color(0xFFF9F9F9), borderRadius: BorderRadius.circular(12)),
                      child: Text('${_amount.toInt()}g', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  IconButton(icon: Icon(LucideIcons.plus), onPressed: () => setState(() => _amount = (_amount + 5).clamp(10, 500))),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _onAdd, child: const Text('Add Schedule'))),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (feeding.isLoading)
          const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: AppColors.primary)))
        else
          ...zoneSchedules.map((s) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppShadows.card),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${s.time.substring(0, 5)} · ${s.amountGrams.toInt()}g', style: const TextStyle(fontWeight: FontWeight.w600)),
                Row(children: [
                  Switch(value: s.active, activeThumbColor: AppColors.primary, onChanged: (v) => context.read<LocalFeedingProvider>().toggleSchedule(s.id, v)),
                  IconButton(icon: Icon(LucideIcons.trash2, color: AppColors.danger, size: 18), onPressed: () => context.read<LocalFeedingProvider>().deleteSchedule(s.id)),
                ]),
              ],
            ),
          )),
      ],
    );
  }

  @override
  void dispose() {
    _timeController.dispose();
    super.dispose();
  }
}
