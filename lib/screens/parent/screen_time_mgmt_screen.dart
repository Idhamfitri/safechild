import 'package:flutter/material.dart';
import '../../models/screen_time_models.dart';
import '../../services/screen_time_service.dart';
import '../../utils/app_theme.dart';
import 'package:intl/intl.dart';

class ScreenTimeMgmtScreen extends StatefulWidget {
  final String deviceId;
  final String deviceName;

  const ScreenTimeMgmtScreen({
    super.key,
    required this.deviceId,
    required this.deviceName,
  });

  @override
  State<ScreenTimeMgmtScreen> createState() => _ScreenTimeMgmtScreenState();
}

class _ScreenTimeMgmtScreenState extends State<ScreenTimeMgmtScreen> {
  final _service = ScreenTimeService();

  @override
  Widget build(BuildContext context) {
    // Nested inside another Scaffold, we should avoid duplicate appbars.
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLockToggle(),
            const SizedBox(height: 24),
            _buildPendingRequests(),
            const SizedBox(height: 24),
            _buildSchedules(),
          ],
        ),
      ),
    );
  }

  Widget _buildLockToggle() {
    return StreamBuilder<ScreenTimeLock>(
      stream: _service.watchLock(widget.deviceId),
      builder: (context, snapshot) {
        final lock = snapshot.data ?? ScreenTimeLock(
          lockId: widget.deviceId, 
          deviceId: widget.deviceId, 
          isLocked: false
        );
        
        final isLocked = lock.isLocked && lock.lockedBy == 'parent';

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                Icon(
                  isLocked ? Icons.lock : Icons.lock_open,
                  size: 48,
                  color: isLocked ? AppColors.error : AppColors.statusLinked,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Manual Device Lock',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  isLocked ? 'Device is currently LOCKED by you.' : 'Device is NOT manually locked.',
                  style: TextStyle(
                    color: isLocked ? AppColors.error : AppColors.textSub,
                  ),
                ),
                if (lock.isLocked && lock.lockedBy == 'schedule')
                   Container(
                     margin: const EdgeInsets.only(top: 12.0),
                     padding: const EdgeInsets.all(12),
                     decoration: BoxDecoration(
                       color: Colors.orange.withOpacity(0.1),
                       borderRadius: BorderRadius.circular(8),
                       border: Border.all(color: Colors.orange),
                     ),
                     child: const Row(
                       children: [
                         Icon(Icons.info_outline, color: Colors.orange, size: 20),
                         SizedBox(width: 8),
                         Expanded(
                           child: Text(
                             'Child screen already locked by a Schedule.',
                             style: TextStyle(color: Colors.orange, fontSize: 14, fontWeight: FontWeight.bold),
                           ),
                         ),
                       ],
                     ),
                   ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isLocked ? AppColors.background : AppColors.error,
                      foregroundColor: isLocked ? AppColors.primary : Colors.white,
                      side: isLocked ? const BorderSide(color: AppColors.primary) : null,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      _service.setManualLock(widget.deviceId, !isLocked);
                    },
                    child: Text(isLocked ? 'Unlock Device' : 'Lock Device Now'),
                  ),
                )
              ],
            ),
          ),
        );
      }
    );
  }

  Widget _buildPendingRequests() {
    return StreamBuilder<List<ScreenTimeRequest>>(
      stream: _service.watchPendingRequests(widget.deviceId),
      builder: (context, snapshot) {
        final requests = snapshot.data ?? [];
        if (requests.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pending Extension Requests',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...requests.map((r) => Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: AppColors.primary, width: 1)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: const Icon(Icons.timer, color: AppColors.primary),
                    title: Text('Request for ${r.requestedTime} minutes'),
                    subtitle: Text(DateFormat('hh:mm a, MMM dd').format(r.requestedAt)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: AppColors.error),
                          onPressed: () => _service.handleRequest(r.requestId, widget.deviceId, r.requestedTime, false),
                        ),
                        IconButton(
                          icon: const Icon(Icons.check, color: AppColors.primary),
                          onPressed: () => _service.handleRequest(r.requestId, widget.deviceId, r.requestedTime, true),
                        ),
                      ],
                    ),
                  ),
                ))
          ],
        );
      },
    );
  }

  Widget _buildSchedules() {
    return StreamBuilder<List<ScreenTimeSchedule>>(
      stream: _service.watchSchedules(widget.deviceId),
      builder: (context, snapshot) {
        final schedules = snapshot.data ?? [];
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Lock Schedules',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add Time'),
                  onPressed: _showAddScheduleDialog,
                )
              ],
            ),
            const SizedBox(height: 12),
            if (schedules.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('No active schedules.', style: TextStyle(color: AppColors.textSub)),
                ),
              ),
            ...schedules.map((s) {
              final daysStr = s.days.map((d) {
                switch(d) {
                  case 1: return 'Mon';
                  case 2: return 'Tue';
                  case 3: return 'Wed';
                  case 4: return 'Thu';
                  case 5: return 'Fri';
                  case 6: return 'Sat';
                  case 7: return 'Sun';
                  default: return '';
                }
              }).join(', ');
              
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  title: Text('${s.startTime} - ${s.endTime}'),
                  subtitle: Text(daysStr.isEmpty ? 'No days set' : daysStr),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.error),
                    onPressed: () => _service.deleteSchedule(s.scheduleId),
                  ),
                ),
              );
            }),
          ],
        );
      }
    );
  }

  Future<void> _showAddScheduleDialog() async {
    List<int> selectedDays = [1, 2, 3, 4, 5]; // default weekdays
    TimeOfDay? startT = const TimeOfDay(hour: 20, minute: 0);
    TimeOfDay? endT = const TimeOfDay(hour: 6, minute: 0);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            top: 24,
            left: 24,
            right: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add Schedule Block', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              
              // Days selector
              const Text('Select Days:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                children: [1, 2, 3, 4, 5, 6, 7].map((day) {
                   final isSelected = selectedDays.contains(day);
                   final label = ['M','T','W','T','F','S','S'][day-1];
                   return ChoiceChip(
                     label: Text(label),
                     selected: isSelected,
                     onSelected: (val) {
                       setModalState(() {
                         if (val) selectedDays.add(day);
                         else selectedDays.remove(day);
                       });
                     },
                   );
                }).toList(),
              ),
              const SizedBox(height: 20),
              
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final t = await showTimePicker(context: context, initialTime: startT!);
                        if (t != null) setModalState(() => startT = t);
                      },
                      child: Text(startT?.format(context) ?? 'Start Time'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final t = await showTimePicker(context: context, initialTime: endT!);
                        if (t != null) setModalState(() => endT = t);
                      },
                      child: Text(endT?.format(context) ?? 'End Time'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (startT == null || endT == null || selectedDays.isEmpty) return;
                    
                    final sTime = '${startT!.hour.toString().padLeft(2, '0')}:${startT!.minute.toString().padLeft(2, '0')}';
                    final eTime = '${endT!.hour.toString().padLeft(2, '0')}:${endT!.minute.toString().padLeft(2, '0')}';

                    final schedule = ScreenTimeSchedule(
                      scheduleId: '', // Firebase auto ID
                      deviceId: widget.deviceId,
                      scheduleName: 'Custom Schedule',
                      startTime: sTime,
                      endTime: eTime,
                      days: selectedDays,
                      isActive: true,
                      createdAt: DateTime.now(),
                    );
                    
                    _service.createSchedule(schedule);
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(16),
                  ),
                  child: const Text('Save Schedule Block'),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
