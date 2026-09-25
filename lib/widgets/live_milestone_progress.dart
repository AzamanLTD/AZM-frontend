import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/widgets/milestone_progress.dart';

class LiveMilestoneProgress extends StatefulWidget {
  const LiveMilestoneProgress({super.key});

  @override
  State<LiveMilestoneProgress> createState() => _LiveMilestoneProgressState();
}

class _LiveMilestoneProgressState extends State<LiveMilestoneProgress> {
  double _currentVolume = 0;
  double _targetVolume = 100000;
  String _tierName = 'STANDARD';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _fetchMilestones();
  }

  Future<void> _fetchMilestones() async {
    try {
      final res = await apiClient.get('/users/me/milestones');

      if (res.statusCode == 200 && mounted) {
        final body = jsonDecode(res.body);
        final data = body['data'] ?? body;
        setState(() {
          _currentVolume = (data['currentVolume'] as num?)?.toDouble() ?? 0;
          _targetVolume = (data['targetVolume'] as num?)?.toDouble() ?? 100000;
          _tierName = data['tierName']?.toString() ?? 'STANDARD';
          _loaded = true;
        });
      }
    } catch (e) {
      debugPrint('LiveMilestoneProgress fetch error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const MilestoneProgress(
        currentVolume: 0,
        targetVolume: 100000,
        tierName: 'Loading...',
      );
    }
    return MilestoneProgress(
      currentVolume: _currentVolume,
      targetVolume: _targetVolume,
      tierName: _tierName,
    );
  }
}
