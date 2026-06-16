import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/vault/vault_list_screen.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/widgets/savings_goal_sheet.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class SavingsScreen extends ConsumerStatefulWidget {
  const SavingsScreen({super.key});

  @override
  ConsumerState<SavingsScreen> createState() => _SavingsScreenState();
}

class _SavingsScreenState extends ConsumerState<SavingsScreen> {
  Map<String, dynamic>? _overview;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchOverview();
  }

  Future<void> _fetchOverview() async {
    try {
      final response = await apiClient.get('/savings/overview');

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _overview = body['data'];
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('[Savings] Fetch error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }

    return RefreshIndicator(
      color: colors.accent,
      onRefresh: _fetchOverview,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(colors),
            const SizedBox(height: 16),
            _buildBalance(colors),
            const SizedBox(height: 12),
            _buildCurrencyPill(colors),
            const SizedBox(height: 32),
            _buildSectionLabel(colors, 'Here are some things you can do'),
            const SizedBox(height: 16),
            _buildActionGrid(colors),
            const SizedBox(height: 32),
            _buildSectionLabel(colors, 'Your savings goals'),
            const SizedBox(height: 16),
            _buildGoalsRow(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AzamanColors colors) {
    final username = ref.watch(authProvider).user?.username ?? '';
    final greeting = username.isEmpty ? 'Hi there,' : 'Hi $username,';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            greeting,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.2,
            ),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => HapticFeedback.selectionClick(),
          child: SizedBox(
            width: 30,
            height: 30,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Icon(HugeIconsSolid.notification01,
                    color: colors.textPrimary, size: 24),
                Positioned(
                  top: 3,
                  right: 4,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colors.danger,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.background, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBalance(AzamanColors colors) {
    final total = (_overview?['totalSavedGhs'] as num?)?.toDouble() ?? 0;
    return Text(
      _formatAmount(total),
      style: TextStyle(
        color: colors.textPrimary,
        fontSize: 40,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
        height: 1.0,
      ),
    );
  }

  Widget _buildCurrencyPill(AzamanColors colors) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('\u{1F1EC}\u{1F1ED}', style: TextStyle(fontSize: 18)),
        const SizedBox(width: 6),
        Text(
          'GHS',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(width: 2),
        Icon(HugeIconsSolid.arrowDown01, color: colors.textTertiary, size: 16),
      ],
    );
  }

  Widget _buildSectionLabel(AzamanColors colors, String text) {
    return Text(
      text,
      style: TextStyle(
        color: colors.textTertiary,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.2,
      ),
    );
  }

  Widget _buildActionGrid(AzamanColors colors) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ActionCard(
                colors: colors,
                icon: HugeIconsSolid.flag01,
                tint: colors.textPrimary,
                background: colors.accent.withOpacity(0.07),
                title: 'New goal',
                subtitle: 'Save toward a target amount',
                onTap: () => _showCreateGoalSheet(colors),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _ActionCard(
                colors: colors,
                icon: HugeIconsSolid.lock,
                tint: colors.textPrimary,
                background: colors.success.withOpacity(0.08),
                title: 'Open a vault',
                subtitle: 'Lock funds, earn rewards',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const VaultListScreen()),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _ActionCard(
                colors: colors,
                icon: HugeIconsSolid.userGroup,
                tint: colors.textPrimary,
                background: colors.warning.withOpacity(0.10),
                title: 'Join a Susu',
                subtitle: 'Group rotational savings',
                onTap: () => context.push('/susu'),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _ActionCard(
                colors: colors,
                icon: HugeIconsSolid.wallet01,
                tint: colors.textPrimary,
                background: colors.softSurface,
                title: 'Quick deposit',
                subtitle: 'Add money to your savings',
                onTap: () => context.push('/deposit'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGoalsRow(AzamanColors colors) {
    final goals = (_overview?['goals'] as List?) ?? [];

    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: goals.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _GoalCircle(
              colors: colors,
              isAdd: true,
              label: 'Add',
              onTap: () => _showCreateGoalSheet(colors),
            );
          }
          final goal = Map<String, dynamic>.from(goals[index - 1] as Map);
          final name = goal['name']?.toString() ?? 'Goal';
          return _GoalCircle(
            colors: colors,
            label: name.split(' ').first,
            initials: _initials(name),
            onTap: () {
              HapticFeedback.selectionClick();
              SavingsGoalSheet.show(
                context,
                goal: goal,
                onChanged: _fetchOverview,
              );
            },
          );
        },
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    final buffer = StringBuffer();
    for (final part in parts.take(2)) {
      buffer.write(part[0].toUpperCase());
    }
    return buffer.toString();
  }

  String _formatAmount(double value) {
    final fixed = value.toStringAsFixed(2);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final buffer = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(',');
      buffer.write(intPart[i]);
    }
    return '${buffer.toString()}.${parts[1]}';
  }

  void _showCreateGoalSheet(AzamanColors colors) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CreateGoalSheet(onCreated: _fetchOverview),
    );
  }
}

// =============================================================================
// CREATE GOAL BOTTOM SHEET
// =============================================================================
class _CreateGoalSheet extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _CreateGoalSheet({required this.onCreated});

  @override
  ConsumerState<_CreateGoalSheet> createState() => _CreateGoalSheetState();
}

class _CreateGoalSheetState extends ConsumerState<_CreateGoalSheet> {
  final _nameController = TextEditingController(text: 'My Savings');
  final _targetController = TextEditingController();
  final _amountController = TextEditingController();
  String _frequency = 'WEEKLY';
  bool _isLocked = true;
  bool _isSubmitting = false;

  Future<void> _submit() async {
    if (_targetController.text.isEmpty || _amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final response = await apiClient.post('/savings/goals', {
        'name': _nameController.text,
        'targetAmountGhs': double.tryParse(_targetController.text) ?? 0,
        'frequencyAmount': double.tryParse(_amountController.text) ?? 0,
        'frequency': _frequency,
        'isLocked': _isLocked,
      });

      if (response.statusCode == 201) {
        widget.onCreated();
        if (mounted) Navigator.pop(context);
        HapticFeedback.heavyImpact();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: colors.divider, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          Text('Create Savings Goal', style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),

          TextField(
            controller: _nameController,
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Goal Name',
              labelStyle: TextStyle(color: colors.textTertiary),
              filled: true,
              fillColor: colors.card,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _targetController,
            keyboardType: TextInputType.number,
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Target Amount (GHS)',
              labelStyle: TextStyle(color: colors.textTertiary),
              filled: true,
              fillColor: colors.card,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Amount per deposit (GHS)',
              labelStyle: TextStyle(color: colors.textTertiary),
              filled: true,
              fillColor: colors.card,
            ),
          ),
          const SizedBox(height: 12),

          // Frequency selector
          DropdownButtonFormField<String>(
            value: _frequency,
            dropdownColor: colors.card,
            style: TextStyle(color: colors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Frequency',
              labelStyle: TextStyle(color: colors.textTertiary),
              filled: true,
              fillColor: colors.card,
            ),
            items: ['DAILY', 'WEEKLY', 'BIWEEKLY', 'MONTHLY']
                .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                .toList(),
            onChanged: (v) => setState(() => _frequency = v!),
          ),
          const SizedBox(height: 12),

          // Lock toggle
          SwitchListTile(
            title: Text('Lock funds until target reached', style: TextStyle(color: colors.textPrimary, fontSize: 14)),
            subtitle: Text('2% penalty for early withdrawal', style: TextStyle(color: colors.textTertiary, fontSize: 11)),
            value: _isLocked,
            activeColor: colors.accent,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() => _isLocked = v),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.isDark ? Colors.black : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSubmitting
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: colors.isDark ? Colors.black : Colors.white))
                  : const Text('Create Goal', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    _amountController.dispose();
    super.dispose();
  }
}

class _ActionCard extends StatelessWidget {
  final AzamanColors colors;
  final IconData icon;
  final Color tint;
  final Color background;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.colors,
    required this.icon,
    required this.tint,
    required this.background,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AspectRatio(
        aspectRatio: 1.12,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: tint, size: 26),
              const Spacer(),
              Text(
                title,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 12.5,
                  height: 1.3,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalCircle extends StatelessWidget {
  final AzamanColors colors;
  final String label;
  final String? initials;
  final bool isAdd;
  final VoidCallback onTap;

  const _GoalCircle({
    required this.colors,
    required this.label,
    required this.onTap,
    this.initials,
    this.isAdd = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isAdd ? colors.softSurface : colors.accent.withOpacity(0.14),
              ),
              child: isAdd
                  ? Icon(HugeIconsSolid.add01,
                      color: colors.textSecondary, size: 26)
                  : Text(
                      initials ?? '?',
                      style: TextStyle(
                        color: colors.accent,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 64,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
