// =============================================================================
// AZAMAN — Notification Preferences & Quiet Hours
//
// Users can:
//   • Toggle per-category notifications (money, social, chat, system, etc.)
//   • Set quiet hours (mute all non-critical notifications during a time range)
//   • Choose which categories bypass quiet hours (emergencies, security)
//   • Per-channel toggles (push, in-app, email)
// =============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class NotificationPreferencesScreen extends ConsumerStatefulWidget {
  const NotificationPreferencesScreen({super.key});
  @override
  ConsumerState<NotificationPreferencesScreen> createState() => _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState extends ConsumerState<NotificationPreferencesScreen> {
  bool _loading = true;
  bool _saving = false;

  // Channel toggles
  bool _pushEnabled = true;
  bool _inAppEnabled = true;
  bool _emailEnabled = false;

  // Quiet hours
  bool _quietHoursEnabled = false;
  TimeOfDay _quietStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _quietEnd = const TimeOfDay(hour: 7, minute: 0);

  // Per-category toggles
  final Map<String, bool> _categoryToggles = {
    'money': true,
    'social': true,
    'chat': true,
    'security': true, // always-on for quiet hours bypass
    'system': true,
    'vendor': true,
    'admin': true,
  };

  // Categories that bypass quiet hours
  final Map<String, bool> _bypassQuiet = {
    'money': false,
    'social': false,
    'chat': false,
    'security': true, // security always bypasses
    'system': false,
    'vendor': false,
    'admin': false,
  };

  final _categoryInfo = {
    'money':   ('Money & Transactions', HugeIconsSolid.moneyReceiveFlow01, 'color'),
    'social':  ('Social & Stories', HugeIconsSolid.userGroup, 'color'),
    'chat':    ('Messages', HugeIconsSolid.message01, 'color'),
    'security':('Security Alerts', HugeIconsSolid.lockKey, 'color'),
    'system':  ('System Updates', HugeIconsSolid.shield01, 'color'),
    'vendor':  ('Vendor & Marketplace', HugeIconsSolid.store01, 'color'),
    'admin':   ('Admin & Account', HugeIconsSolid.userCircle, 'color'),
  };

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final res = await ApiClient().get('/api/users/me/notification-preferences');
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>? ?? {};
      setState(() {
        _pushEnabled = data['pushEnabled'] as bool? ?? true;
        _inAppEnabled = data['inAppEnabled'] as bool? ?? true;
        _emailEnabled = data['emailEnabled'] as bool? ?? false;
        _quietHoursEnabled = data['quietHoursEnabled'] as bool? ?? false;
        if (data['quietStart'] != null) {
          final parts = (data['quietStart'] as String).split(':');
          _quietStart = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        }
        if (data['quietEnd'] != null) {
          final parts = (data['quietEnd'] as String).split(':');
          _quietEnd = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        }
        final cats = data['categories'] as Map<String, dynamic>? ?? {};
        cats.forEach((key, value) {
          if (_categoryToggles.containsKey(key)) {
            _categoryToggles[key] = value as bool;
          }
        });
        final bypass = data['bypassQuiet'] as Map<String, dynamic>? ?? {};
        bypass.forEach((key, value) {
          if (_bypassQuiet.containsKey(key)) {
            _bypassQuiet[key] = value as bool;
          }
        });
        _loading = false;
      });
    } catch (_) {
      // Defaults are fine if endpoint doesn't exist yet
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ApiClient().put('/api/users/me/notification-preferences', {
        'pushEnabled': _pushEnabled,
        'inAppEnabled': _inAppEnabled,
        'emailEnabled': _emailEnabled,
        'quietHoursEnabled': _quietHoursEnabled,
        'quietStart': '${_quietStart.hour.toString().padLeft(2, '0')}:${_quietStart.minute.toString().padLeft(2, '0')}',
        'quietEnd': '${_quietEnd.hour.toString().padLeft(2, '0')}:${_quietEnd.minute.toString().padLeft(2, '0')}',
        'categories': _categoryToggles,
        'bypassQuiet': _bypassQuiet,
      });
      if (mounted) {
        AzamanHaptics.commit();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification preferences saved'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    if (_loading) {
      return Scaffold(
        backgroundColor: colors.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Text('Notification Preferences', style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: colors.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_saving)
            Padding(padding: const EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: colors.accent)))
          else
            TextButton(onPressed: _save, child: Text('Save', style: TextStyle(color: colors.accent, fontWeight: FontWeight.w700))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Channels ──────────────────────────────────────────────
          _sectionHeader('Delivery Channels', colors),
          _toggleTile(
            'Push Notifications',
            'Receive notifications on your device',
            HugeIconsSolid.alert01,
            colors,
            _pushEnabled,
            (v) => setState(() => _pushEnabled = v),
          ),
          _toggleTile(
            'In-App Notifications',
            'Show notifications while using the app',
            HugeIconsSolid.smartPhone01,
            colors,
            _inAppEnabled,
            (v) => setState(() => _inAppEnabled = v),
          ),
          _toggleTile(
            'Email Notifications',
            'Receive a summary via email',
            HugeIconsSolid.mail01,
            colors,
            _emailEnabled,
            (v) => setState(() => _emailEnabled = v),
          ),

          const SizedBox(height: 24),

          // ── Quiet Hours ────────────────────────────────────────────
          _sectionHeader('Quiet Hours', colors),
          _card(colors, child: Column(
            children: [
              SwitchListTile(
                value: _quietHoursEnabled,
                onChanged: (v) => setState(() => _quietHoursEnabled = v),
                title: Text('Enable Quiet Hours', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600)),
                subtitle: Text('Mute non-critical notifications during set hours', style: TextStyle(color: colors.textTertiary, fontSize: 12)),
                activeThumbColor: colors.accent,
              ),
              if (_quietHoursEnabled) ...[
                ListTile(
                  leading: Icon(Icons.nightlight_round, color: colors.accent, size: 20),
                  title: Text('Start', style: TextStyle(color: colors.textSecondary, fontSize: 14)),
                  trailing: Text(_formatTime(_quietStart), style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
                  onTap: () => _pickTime(true),
                ),
                ListTile(
                  leading: Icon(Icons.wb_sunny_outlined, color: colors.accent, size: 20),
                  title: Text('End', style: TextStyle(color: colors.textSecondary, fontSize: 14)),
                  trailing: Text(_formatTime(_quietEnd), style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
                  onTap: () => _pickTime(false),
                ),
              ],
            ],
          )),

          const SizedBox(height: 24),

          // ── Categories ─────────────────────────────────────────────
          _sectionHeader('Notification Categories', colors),
          ..._categoryToggles.keys.map((cat) => _categoryTile(cat, colors)),

          if (_quietHoursEnabled) ...[
            const SizedBox(height: 24),
            _sectionHeader('Bypass Quiet Hours', colors),
            Text('These categories will always notify, even during quiet hours',
              style: TextStyle(color: colors.textTertiary, fontSize: 12)),
            const SizedBox(height: 8),
            ..._bypassQuiet.keys.map((cat) => _bypassTile(cat, colors)),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(title, style: TextStyle(color: colors.accent, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
    ).animate().fadeIn(duration: 200.ms);
  }

  Widget _card(AzamanColors colors, {required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }

  Widget _toggleTile(String title, String subtitle, IconData icon, AzamanColors colors, bool value, ValueChanged<bool> onChanged) {
    return _card(colors, child: SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Text(title, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle, style: TextStyle(color: colors.textTertiary, fontSize: 12)),
      secondary: Icon(icon, color: colors.accent, size: 22),
      activeThumbColor: colors.accent,
    ));
  }

  Widget _categoryTile(String cat, AzamanColors colors) {
    final info = _categoryInfo[cat]!;
    return _card(colors, child: SwitchListTile(
      value: _categoryToggles[cat]!,
      onChanged: (v) => setState(() => _categoryToggles[cat] = v),
      title: Row(
        children: [
          Icon(info.$2, color: colors.accent, size: 22),
          const SizedBox(width: 12),
          Text(info.$1, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
        ],
      ),
      activeThumbColor: colors.accent,
    ));
  }

  Widget _bypassTile(String cat, AzamanColors colors) {
    final info = _categoryInfo[cat]!;
    final isLocked = cat == 'security'; // always bypasses
    return _card(colors, child: SwitchListTile(
      value: _bypassQuiet[cat]!,
      onChanged: isLocked ? null : (v) => setState(() => _bypassQuiet[cat] = v),
      title: Row(
        children: [
          Icon(isLocked ? HugeIconsSolid.lockKey : info.$2, color: colors.accent, size: 20),
          const SizedBox(width: 12),
          Text(info.$1, style: TextStyle(
            color: isLocked ? colors.textTertiary : colors.textPrimary,
            fontWeight: FontWeight.w600, fontSize: 14,
          )),
        ],
      ),
      activeThumbColor: colors.accent,
    ));
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _quietStart : _quietEnd,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _quietStart = picked;
        } else {
          _quietEnd = picked;
        }
      });
    }
  }

  String _formatTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final ampm = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:${t.minute.toString().padLeft(2, '0')} $ampm';
  }
}
