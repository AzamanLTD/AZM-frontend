import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/worker_provider.dart';
import 'package:azaman/models/employee_models.dart';
import 'package:azaman/services/api_client.dart';

class WorkerTimeOffScreen extends ConsumerStatefulWidget {
  const WorkerTimeOffScreen({super.key});

  @override
  ConsumerState<WorkerTimeOffScreen> createState() => _WorkerTimeOffScreenState();
}

class _WorkerTimeOffScreenState extends ConsumerState<WorkerTimeOffScreen> {
  bool _submitting = false;

  Future<void> _submitRequest() async {
    setState(() => _submitting = true);
    try {
      final client = ref.read(apiClientProvider);
      final res = await client.post('/api/business-os/employees/time-off', {
        'type': _selectedType.name.toUpperCase(),
        'startDate': _startDate.toIso8601String(),
        'endDate': _endDate.toIso8601String(),
        'reason': _reasonController.text,
      });
      if (res.statusCode == 201) {
        ref.refresh(myTimeOffProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Time off request submitted'), backgroundColor: Colors.green));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit request'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  TimeOffType _selectedType = TimeOffType.personal;
  DateTime _startDate = DateTime.now().add(const Duration(days: 1));
  DateTime _endDate = DateTime.now().add(const Duration(days: 3));
  final _reasonController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final timeOffAsync = ref.watch(myTimeOffProvider);

    return Scaffold(
      backgroundColor: colors.scaffoldBackground,
      appBar: AppBar(
        title: Text('Time Off', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        backgroundColor: colors.surface,
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Request form
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surface, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Request Time Off', style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                // Type dropdown
                DropdownButtonFormField<TimeOffType>(
                  value: _selectedType,
                  decoration: InputDecoration(
                    labelText: 'Type',
                    labelStyle: TextStyle(color: colors.textTertiary, fontSize: 12),
                    filled: true, fillColor: colors.scaffoldBackground,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colors.border)),
                  ),
                  items: TimeOffType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.name))).toList(),
                  onChanged: (v) => setState(() => _selectedType = v!),
                ),
                const SizedBox(height: 12),
                // Date range
                Row(
                  children: [
                    Expanded(child: Text('From: ${_fmtDate(_startDate)}', style: TextStyle(color: colors.textSecondary, fontSize: 13))),
                    Expanded(child: Text('To: ${_fmtDate(_endDate)}', style: TextStyle(color: colors.textSecondary, fontSize: 13))),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _reasonController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Reason (optional)',
                    hintStyle: TextStyle(color: colors.textTertiary, fontSize: 13),
                    filled: true, fillColor: colors.scaffoldBackground,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colors.border)),
                  ),
                  style: TextStyle(color: colors.textPrimary, fontSize: 14),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submitRequest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.accent, foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _submitting
                        ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : Text('Submit Request', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Existing requests
          Text('My Requests', style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          timeOffAsync.when(
            loading: () => Center(child: CircularProgressIndicator(color: colors.accent)),
            error: (_, __) => Text('Unable to load', style: TextStyle(color: colors.textSecondary)),
            data: (requests) {
              if (requests.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: Text('No requests yet', style: TextStyle(color: colors.textTertiary, fontSize: 14))),
                );
              }
              return Column(
                children: requests.map((r) => _TimeOffTile(request: r, colors: colors)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

class _TimeOffTile extends StatelessWidget {
  final TimeOffRequest request;
  final dynamic colors;
  const _TimeOffTile({required this.request, required this.colors});

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (request.status) {
      TimeOffStatus.approved => colors.success,
      TimeOffStatus.pending => colors.warning,
      TimeOffStatus.rejected => colors.danger,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.beach_access, color: colors.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(request.type.name.toUpperCase(), style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                Text('${_fmtDate(request.startDate)} - ${_fmtDate(request.endDate)}',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                if (request.reason != null)
                  Text(request.reason!, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.textTertiary, fontSize: 11)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
            child: Text(request.status.name.toUpperCase(),
                style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}
