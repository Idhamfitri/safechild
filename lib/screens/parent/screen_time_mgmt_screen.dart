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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: StreamBuilder<ScreenTimeLock>(
        stream: _service.watchLock(widget.deviceId),
        builder: (context, snapshot) {
          final lock = snapshot.data ?? ScreenTimeLock(
            lockId: widget.deviceId, 
            deviceId: widget.deviceId, 
            isLocked: false
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (lock.isLocked && lock.unlockedAt != null)
                   Container(
                     margin: const EdgeInsets.only(bottom: 20.0),
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
                _buildLockToggle(lock),
                const SizedBox(height: 24),
                _buildPendingRequests(),
                const SizedBox(height: 24),
                _buildSchedules(),
              ],
            ),
          );
        }
      ),
    );
  }

  Widget _buildLockToggle(ScreenTimeLock lock) {
    final isManualLock = lock.isLocked && lock.unlockedAt == null;
    final isScheduleActive = lock.isLocked && lock.unlockedAt != null;
    final isLocked = lock.isLocked; // True if locked by ANY reason

    return Center(
      child: Column(
        children: [
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () {
              if (isScheduleActive) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Device is already locked by a schedule. Turn off the schedule to unlock."),
                    backgroundColor: Colors.orange,
                    behavior: SnackBarBehavior.floating,
                  )
                );
                return;
              }
              _service.setManualLock(widget.deviceId, !isManualLock);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isLocked ? AppColors.error : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: (isLocked ? AppColors.error : AppColors.primary).withOpacity(isLocked ? 0.4 : 0.1),
                    blurRadius: 20,
                    spreadRadius: isLocked ? 10 : 2,
                    offset: const Offset(0, 8),
                  )
                ],
                border: Border.all(
                  color: isLocked ? Colors.transparent : AppColors.primary.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: Center(
                child: Icon(
                  isLocked ? Icons.lock : Icons.power_settings_new,
                  size: 60,
                  color: isLocked ? Colors.white : AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isScheduleActive 
                ? 'SCHEDULE LOCK ACTIVE' 
                : (isLocked ? 'MANUAL LOCK ACTIVE' : 'TAP TO LOCK'),
            style: TextStyle(
              fontSize: 16, 
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: isLocked ? AppColors.error : AppColors.textSub,
            ),
          ),
          const SizedBox(height: 10),

        ],
      ),
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
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(DateFormat('hh:mm a, MMM dd').format(r.requestedAt)),
                        if (r.reason.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text('"${r.reason}"', style: const TextStyle(fontStyle: FontStyle.italic)),
                          ),
                      ],
                    ),
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
                  case 'monday': return 'Mon';
                  case 'tuesday': return 'Tue';
                  case 'wednesday': return 'Wed';
                  case 'thursday': return 'Thu';
                  case 'friday': return 'Fri';
                  case 'saturday': return 'Sat';
                  case 'sunday': return 'Sun';
                  default: return '';
                }
              }).join(', ');
              
              final icons = [
                 Icons.lock,
                 Icons.school,
                 Icons.book,
                 Icons.nightlight_round,
                 Icons.restaurant,
                 Icons.sports_esports,
              ];
              final icon = icons[s.iconIndex % icons.length];
              
              return AnimatedOpacity(
                opacity: s.isActive ? 1.0 : 0.5,
                duration: const Duration(milliseconds: 300),
                child: Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: Icon(icon, color: s.isActive ? AppColors.primary : Colors.grey),
                    title: Text(s.scheduleName, 
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                )),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text('${s.startTime} - ${s.endTime}', style: const TextStyle(fontSize: 13, color: Colors.black87)),
                        const SizedBox(height: 2),
                        Text(daysStr.isEmpty ? 'No days set' : daysStr, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: s.isActive,
                          onChanged: (val) => _service.toggleScheduleActive(s.scheduleId, val),
                          activeColor: AppColors.primary,
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppColors.error),
                          onPressed: () => _service.deleteSchedule(s.scheduleId),
                        ),
                      ],
                    ),
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
    final nameController = TextEditingController();
    List<String> selectedDays = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday']; // default weekdays
    TimeOfDay? startT = const TimeOfDay(hour: 20, minute: 0);
    TimeOfDay? endT = const TimeOfDay(hour: 6, minute: 0);
    int selectedIconParams = 0; // 0: lock, 1: school, 2: book, 3: night, 4: food, 5: game

    final iconSet = [
                 Icons.lock,
                 Icons.school,
                 Icons.book,
                 Icons.nightlight_round,
                 Icons.restaurant,
                 Icons.sports_esports,
    ];

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
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Add Schedule Block', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Schedule Name',
                    hintText: 'e.g. School, Study, Bedtime',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                const Text('Select Icon:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: List.generate(iconSet.length, (index) {
                     final isSelected = selectedIconParams == index;
                     return GestureDetector(
                       onTap: () {
                         setModalState(() => selectedIconParams = index);
                       },
                       child: Container(
                         padding: const EdgeInsets.all(8),
                         decoration: BoxDecoration(
                           color: isSelected ? AppColors.primary.withOpacity(0.2) : Colors.transparent,
                           border: Border.all(color: isSelected ? AppColors.primary : Colors.grey.shade400),
                           shape: BoxShape.circle,
                         ),
                         child: Icon(iconSet[index], color: isSelected ? AppColors.primary : Colors.grey),
                       ),
                     );
                  }),
                ),
                const SizedBox(height: 16),
                
                // Days selector
                const Text('Select Days:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  children: List.generate(7, (index) {
                     const daysList = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
                     const labels = ['M','T','W','T','F','S','S'];
                     final day = daysList[index];
                     final label = labels[index];
                     final isSelected = selectedDays.contains(day);
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
                  }),
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
                      final name = nameController.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a schedule name!')));
                        return;
                      }
                      if (startT == null || endT == null || selectedDays.isEmpty) return;
                      
                      final sTime = '${startT!.hour.toString().padLeft(2, '0')}:${startT!.minute.toString().padLeft(2, '0')}';
                      final eTime = '${endT!.hour.toString().padLeft(2, '0')}:${endT!.minute.toString().padLeft(2, '0')}';

                      final schedule = ScreenTimeSchedule(
                        scheduleId: '', // Firebase auto ID
                        deviceId: widget.deviceId,
                        scheduleName: name,
                        iconIndex: selectedIconParams,
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
      ),
    );
  }
}
