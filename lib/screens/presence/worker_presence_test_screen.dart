// lib/screens/presence/worker_presence_test_screen.dart
// =============================================================================
// AZAMAN — WORKER PRESENCE TEST (Part 6.6 §H)
//
// Staff-mode entry. Runs a scan with PresenceScanPurpose.workerTest, which
// the controller routes so that NO customer PresenceEvent is emitted, no
// visit/session is created, and nothing reaches a conversion, order,
// payment, notification or revenue metric.
//
// This wave has no backend worker-test endpoint and no BusinessPortal button.
// The screen proves the seam and the fake result path only.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/nearby_presence_controller.dart';
import 'package:azaman/providers/worker_provider.dart';
import 'package:azaman/services/presence/presence_models.dart';

class WorkerPresenceTestScreen extends ConsumerStatefulWidget {
  const WorkerPresenceTestScreen({super.key, required this.locationId});

  /// The branch this staff member is testing, from
  /// `azaman://presence/verify?locationId=<id>`.
  final String locationId;

  @override
  ConsumerState<WorkerPresenceTestScreen> createState() =>
      _WorkerPresenceTestScreenState();
}

class _WorkerPresenceTestScreenState
    extends ConsumerState<WorkerPresenceTestScreen> {
  PresenceScanOutcome? _outcome;
  bool _running = false;

  Future<void> _run() async {
    setState(() => _running = true);
    final outcome = await ref
        .read(nearbyPresenceControllerProvider.notifier)
        .runWorkerTest();
    if (!mounted) return;
    setState(() {
      _outcome = outcome;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final employee = ref.watch(myEmployeeProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Presence test')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The sentence the directive requires, verbatim.
            Text(
              'Runs a test only. It will not open the customer storefront.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            Text(
              'Location: ${widget.locationId}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (employee != null) ...[
              const SizedBox(height: 4),
              Text(
                'Staff context: business ${employee.businessProfileId} · '
                'employee ${employee.id}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _running ? null : _run,
              child: Text(_running ? 'Scanning…' : 'Run test scan'),
            ),
            const SizedBox(height: 24),
            if (_outcome != null) _Outcome(outcome: _outcome!),
          ],
        ),
      ),
    );
  }
}

class _Outcome extends StatelessWidget {
  const _Outcome({required this.outcome});
  final PresenceScanOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final text = switch (outcome) {
      ScanFound(:final observations) => 'Saw ${observations.length} beacon(s).',
      ScanNone() => 'No beacons in range.',
      ScanBluetoothOff() => 'Bluetooth is off.',
      ScanPermissionDenied() => 'Bluetooth permission denied.',
      ScanPermissionPermanentlyDenied() =>
        'Bluetooth permission is blocked in settings.',
      ScanUnsupported() => 'This build has no hardware scanner (stub).',
      ScanFailed(:final reason) => 'Scan failed: $reason',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Test result', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(text),
        const SizedBox(height: 8),
        Text(
          'No customer presence was recorded.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
