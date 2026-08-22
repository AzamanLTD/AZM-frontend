// =============================================================================
// SHARED VAULT SCREEN — Phase 4 (2026-07-28)
//
// Shared savings goals for couples, families, and groups.
// Multiple contributors can deposit into a single vault with:
//   • Shared progress tracking
//   • Individual contribution breakdowns
//   • Optional co-owner permissions (deposit/withdraw)
//   • Group chat link to vault
//   • Celebration animation on milestone hits
//
// Reference: Revolut Shared Vaults, Monzo Shared Pots, Splitwise group goals
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'dart:convert';

import 'package:azaman/services/api_client.dart';
import 'package:azaman/widgets/nav_transitions.dart';
import 'package:azaman/widgets/az_pull_to_refresh.dart';

// ── Models ──────────────────────────────────────────────────────────────────

class SharedVault {
  final String id;
  final String name;
  final String? emoji;
  final double targetAmountUsdc;
  final double currentAmountUsdc;
  final String status; // ACTIVE | COMPLETED | CANCELLED
  final DateTime startDate;
  final DateTime? maturityDate;
  final String creatorName;
  final String creatorAzamanId;
  final List<SharedVaultMember> members;
  final bool isCoOwner;
  final String? linkedChatId;
  final DateTime createdAt;

  SharedVault({
    required this.id,
    required this.name,
    this.emoji,
    required this.targetAmountUsdc,
    required this.currentAmountUsdc,
    required this.status,
    required this.startDate,
    this.maturityDate,
    required this.creatorName,
    required this.creatorAzamanId,
    required this.members,
    required this.isCoOwner,
    this.linkedChatId,
    required this.createdAt,
  });

  factory SharedVault.fromJson(Map<String, dynamic> j) => SharedVault(
        id: j['id'] as String,
        name: j['name'] as String,
        emoji: j['emoji'] as String?,
        targetAmountUsdc: (j['targetAmountUsdc'] as num?)?.toDouble() ?? 0,
        currentAmountUsdc: (j['currentAmountUsdc'] as num?)?.toDouble() ?? 0,
        status: j['status'] as String? ?? 'ACTIVE',
        startDate: DateTime.tryParse(j['startDate'] as String? ?? '') ?? DateTime.now(),
        maturityDate: j['maturityDate'] != null ? DateTime.tryParse(j['maturityDate']) : null,
        creatorName: j['creatorName'] as String? ?? 'Unknown',
        creatorAzamanId: j['creatorAzamanId'] as String? ?? '',
        isCoOwner: j['isCoOwner'] as bool? ?? false,
        linkedChatId: j['linkedChatId'] as String?,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        members: (j['members'] as List<dynamic>? ?? [])
            .map((m) => SharedVaultMember.fromJson(m as Map<String, dynamic>))
            .toList(),
      );

  double get progress => targetAmountUsdc > 0
      ? (currentAmountUsdc / targetAmountUsdc).clamp(0.0, 1.0)
      : 0.0;

  bool get isCompleted => status == 'COMPLETED';
}

class SharedVaultMember {
  final String userId;
  final String name;
  final String? avatarUrl;
  final double contributedUsdc;
  final String role; // OWNER | CO_OWNER | CONTRIBUTOR
  final DateTime joinedAt;

  SharedVaultMember({
    required this.userId,
    required this.name,
    this.avatarUrl,
    required this.contributedUsdc,
    required this.role,
    required this.joinedAt,
  });

  factory SharedVaultMember.fromJson(Map<String, dynamic> j) => SharedVaultMember(
        userId: j['userId'] as String? ?? '',
        name: j['name'] as String? ?? 'Unknown',
        avatarUrl: j['avatarUrl'] as String?,
        contributedUsdc: (j['contributedUsdc'] as num?)?.toDouble() ?? 0,
        role: j['role'] as String? ?? 'CONTRIBUTOR',
        joinedAt: DateTime.tryParse(j['joinedAt'] as String? ?? '') ?? DateTime.now(),
      );

  bool get isOwner => role == 'OWNER';
  bool get isCoOwner => role == 'CO_OWNER';
}

// ── Provider ────────────────────────────────────────────────────────────────

final sharedVaultsProvider =
    FutureProvider<List<SharedVault>>((ref) async {
  final res = await apiClient.get('/shared-vaults');
  if (res.statusCode != 200) return [];
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  final data = body['data'] ?? body;
  return (data as List<dynamic>? ?? [])
      .map((v) => SharedVault.fromJson(v as Map<String, dynamic>))
      .toList();
});

final sharedVaultDetailProvider =
    FutureProvider.family<SharedVault?, String>((ref, id) async {
  final res = await apiClient.get('/shared-vaults/$id');
  if (res.statusCode != 200) return null;
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  final data = body['data'] ?? body;
  return SharedVault.fromJson(data as Map<String, dynamic>);
});

// ── Screen ──────────────────────────────────────────────────────────────────

class SharedVaultScreen extends ConsumerStatefulWidget {
  const SharedVaultScreen({super.key});

  @override
  ConsumerState<SharedVaultScreen> createState() => _SharedVaultScreenState();
}

class _SharedVaultScreenState extends ConsumerState<SharedVaultScreen> {
  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final vaultsAsync = ref.watch(sharedVaultsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Shared Vaults',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.person_add, color: colors.textPrimary, size: 20),
            onPressed: () => _showCreateSheet(colors),
            tooltip: 'Create Shared Vault',
          ),
        ],
      ),
      body: AzPullToRefresh(
        color: colors.accent,
        backgroundColor: colors.card,
        onRefresh: () async => ref.refresh(sharedVaultsProvider),
        child: vaultsAsync.when(
          loading: () => Center(child: CircularProgressIndicator(color: colors.accent)),
          error: (_, __) => _buildEmptyState(colors),
          data: (vaults) {
            if (vaults.isEmpty) return _buildEmptyState(colors);
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
              itemCount: vaults.length,
              itemBuilder: (context, i) => _SharedVaultCard(
                vault: vaults[i],
                colors: colors,
                onTap: () => pushWithVerticalTransition(context, SharedVaultDetailScreen(vaultId: vaults[i].id)),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: colors.accent,
        foregroundColor: colors.isDark ? Colors.black : Colors.white,
        onPressed: () => _showCreateSheet(colors),
        icon: const Icon(Icons.add, size: 20),
        label: const Text('New Shared Vault', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildEmptyState(AzamanColors colors) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Center(
          child: Column(
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.accent.withValues(alpha: 0.08),
                ),
                child: Icon(Icons.groups, size: 36, color: colors.accent),
              ),
              const SizedBox(height: 20),
              Text(
                'Save Together, Grow Together',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Create a shared vault with your partner,\nfamily, or friends',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => _showCreateSheet(colors),
                child: Text('Create your first shared vault →',
                  style: TextStyle(color: colors.accent, fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showCreateSheet(AzamanColors colors) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _CreateSharedVaultSheet(colors: colors),
    );
  }
}

// ── Shared Vault Card ────────────────────────────────────────────────────────

class _SharedVaultCard extends StatelessWidget {
  final SharedVault vault;
  final AzamanColors colors;
  final VoidCallback onTap;

  const _SharedVaultCard({required this.vault, required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final progress = vault.progress;
    final remaining = vault.targetAmountUsdc - vault.currentAmountUsdc;
    final memberAvatars = vault.members.take(4).toList();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.divider),
          boxShadow: [
            BoxShadow(
              color: colors.isDark ? Colors.black.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    vault.emoji ?? '🎯',
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vault.name,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        vault.isCoOwner ? 'Co-owner' : 'Contributor',
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (vault.isCompleted)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('Goal reached!',
                      style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.w700)),
                  )
                else
                  Text(
                    '${remaining.toStringAsFixed(2)} USDC left',
                    style: TextStyle(color: colors.textTertiary, fontSize: 11),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: colors.divider,
                valueColor: AlwaysStoppedAnimation(
                  vault.isCompleted ? Colors.green : colors.accent,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${vault.currentAmountUsdc.toStringAsFixed(2)} USDC',
                  style: TextStyle(color: colors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${vault.targetAmountUsdc.toStringAsFixed(2)} USDC',
                  style: TextStyle(color: colors.textTertiary, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Member avatars + count
            Row(
              children: [
                ...memberAvatars.asMap().entries.map((entry) {
                  final i = entry.key;
                  final m = entry.value;
                  return Transform.translate(
                    offset: Offset(-i * 14.0, 0),
                    child: CircleAvatar(
                      radius: 13,
                      backgroundColor: colors.surface,
                      backgroundImage: m.avatarUrl != null ? NetworkImage(m.avatarUrl!) : null,
                      child: m.avatarUrl == null
                          ? Text(m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                              style: TextStyle(color: colors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700))
                          : null,
                    ),
                  );
                }),
                if (vault.members.length > 4)
                  Transform.translate(
                    offset: const Offset(-4 * 14.0, 0),
                    child: CircleAvatar(
                      radius: 13,
                      backgroundColor: colors.divider,
                      child: Text('+${vault.members.length - 4}',
                        style: TextStyle(color: colors.textSecondary, fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  ),
                const SizedBox(width: 8),
                Text(
                  '${vault.members.length} ${vault.members.length == 1 ? "person" : "people"}',
                  style: TextStyle(color: colors.textTertiary, fontSize: 11),
                ),
                const Spacer(),
                if (vault.maturityDate != null)
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 12, color: colors.textTertiary),
                      const SizedBox(width: 3),
                      Text(
                        _formatDaysLeft(vault.maturityDate!),
                        style: TextStyle(color: colors.textTertiary, fontSize: 11),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms, delay: const Duration(milliseconds: 50));
  }

  String _formatDaysLeft(DateTime date) {
    final days = date.difference(DateTime.now()).inDays;
    if (days <= 0) return 'Matured';
    if (days == 1) return '1 day left';
    return '$days days left';
  }
}

// ── Create Shared Vault Sheet ───────────────────────────────────────────────

class _CreateSharedVaultSheet extends ConsumerStatefulWidget {
  final AzamanColors colors;
  const _CreateSharedVaultSheet({required this.colors});

  @override
  ConsumerState<_CreateSharedVaultSheet> createState() => _CreateSharedVaultSheetState();
}

class _CreateSharedVaultSheetState extends ConsumerState<_CreateSharedVaultSheet> {
  final _name = TextEditingController();
  final _target = TextEditingController();
  String _emoji = '🎯';
  DateTime? _maturity;
  final _inviteControllers = <TextEditingController>[TextEditingController()];
  bool _submitting = false;

  static const _emojiOptions = ['🎯', '🏖️', '🏠', '🚗', '💍', '🎓', '✈️', '💼', '👶', '🎁'];

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    for (final c in _inviteControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty || _target.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please fill in name and target amount'),
        duration: Duration(seconds: 2),
      ));
      return;
    }

    setState(() => _submitting = true);
    try {
      final invites = _inviteControllers
          .map((c) => c.text.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      final res = await apiClient.post('/shared-vaults', {
        'name': _name.text.trim(),
        'emoji': _emoji,
        'targetAmountUsdc': double.parse(_target.text.trim()),
        'maturityDate': _maturity?.toIso8601String(),
        'inviteAzamanIds': invites,
      });

      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 201) {
        Navigator.pop(context);
        ref.refresh(sharedVaultsProvider);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Shared vault created! Invitations sent.'),
          duration: Duration(seconds: 2),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(jsonDecode(res.body)['message'] ?? 'Failed to create vault'),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Network error. Try again.'),
          duration: Duration(seconds: 2),
        ));
      }
    }
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: colors.divider, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 16),
              Text('New Shared Vault',
                style: TextStyle(color: colors.textPrimary, fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('Save together with family or friends',
                style: TextStyle(color: colors.textSecondary, fontSize: 13)),
              const SizedBox(height: 24),

              // Emoji picker
              Text('Choose an emoji', style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: _emojiOptions.map((e) => GestureDetector(
                  onTap: () { HapticFeedback.selectionClick(); setState(() => _emoji = e); },
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: _emoji == e ? colors.accent.withValues(alpha: 0.15) : colors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _emoji == e ? colors.accent.withValues(alpha: 0.4) : colors.divider,
                      ),
                    ),
                    child: Center(child: Text(e, style: const TextStyle(fontSize: 20))),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 20),

              // Name field
              _FieldLabel(text: 'Vault Name', colors: colors),
              const SizedBox(height: 6),
              _TextField(
                controller: _name,
                hint: 'e.g. Family Trip to Cape Coast',
                colors: colors,
                icon: Icons.label_outline,
              ),
              const SizedBox(height: 16),

              // Target amount
              _FieldLabel(text: 'Target Amount (USDC)', colors: colors),
              const SizedBox(height: 6),
              _TextField(
                controller: _target,
                hint: '500.00',
                colors: colors,
                icon: Icons.attach_money,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              ),
              const SizedBox(height: 16),

              // Maturity date (optional)
              _FieldLabel(text: 'Target Date (Optional)', colors: colors),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now().add(const Duration(days: 30)),
                    firstDate: DateTime.now().add(const Duration(days: 7)),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                    builder: (ctx, child) => Theme(
                      data: Theme.of(ctx).copyWith(
                        colorScheme: ColorScheme.dark(
                          primary: colors.accent,
                          onPrimary: Colors.white,
                          surface: colors.card,
                          onSurface: colors.textPrimary,
                        ),
                      ),
                      child: child!,
                    ),
                  );
                  if (date != null) setState(() => _maturity = date);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.divider),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today, size: 18, color: colors.textTertiary),
                      const SizedBox(width: 10),
                      Text(
                        _maturity != null
                            ? '${_maturity!.day}/${_maturity!.month}/${_maturity!.year}'
                            : 'Pick a date',
                        style: TextStyle(
                          color: _maturity != null ? colors.textPrimary : colors.textTertiary,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      if (_maturity != null)
                        GestureDetector(
                          onTap: () => setState(() => _maturity = null),
                          child: Icon(Icons.close, size: 16, color: colors.textTertiary),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Invite members
              _FieldLabel(text: 'Invite by Azaman ID', colors: colors),
              const SizedBox(height: 6),
              ..._inviteControllers.asMap().entries.map((entry) {
                final i = entry.key;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _TextField(
                          controller: entry.value,
                          hint: '@azaman_id',
                          colors: colors,
                          icon: Icons.alternate_email,
                        ),
                      ),
                      if (_inviteControllers.length > 1) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            entry.value.dispose();
                            setState(() => _inviteControllers.removeAt(i));
                          },
                          child: Icon(Icons.remove_circle, color: colors.danger, size: 22),
                        ),
                      ],
                    ],
                  ),
                );
              }),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () => setState(() => _inviteControllers.add(TextEditingController())),
                icon: Icon(Icons.add, size: 18, color: colors.accent),
                label: Text('Add another', style: TextStyle(color: colors.accent, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 24),

              // Submit button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.isDark ? Colors.black : Colors.white,
                    disabledBackgroundColor: colors.accent.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _submitting
                      ? SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation(colors.isDark ? Colors.black : Colors.white)))
                      : const Text('Create & Send Invites', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Detail Screen ────────────────────────────────────────────────────────────

class SharedVaultDetailScreen extends ConsumerStatefulWidget {
  final String vaultId;
  const SharedVaultDetailScreen({required this.vaultId, super.key});

  @override
  ConsumerState<SharedVaultDetailScreen> createState() => _SharedVaultDetailScreenState();
}

class _SharedVaultDetailScreenState extends ConsumerState<SharedVaultDetailScreen> {
  final _depositAmount = TextEditingController();

  @override
  void dispose() {
    _depositAmount.dispose();
    super.dispose();
  }

  Future<void> _deposit(SharedVault vault) async {
    final amount = double.tryParse(_depositAmount.text.trim());
    if (amount == null || amount <= 0) return;

    try {
      final res = await apiClient.post('/shared-vaults/${vault.id}/deposit', {
        'amountUsdc': amount,
      });
      if (!mounted) return;
      if (res.statusCode == 200) {
        Navigator.pop(context); // close deposit sheet
        ref.refresh(sharedVaultDetailProvider(widget.vaultId));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Deposited $amount USDC! 🎉'),
          duration: const Duration(seconds: 2),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(jsonDecode(res.body)['message'] ?? 'Deposit failed'),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Network error'),
          duration: Duration(seconds: 2),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final vaultAsync = ref.watch(sharedVaultDetailProvider(widget.vaultId));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Shared Vault',
          style: TextStyle(color: colors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: vaultAsync.when(
        loading: () => Center(child: CircularProgressIndicator(color: colors.accent)),
        error: (_, __) => Center(child: Text('Failed to load', style: TextStyle(color: colors.textSecondary))),
        data: (vault) {
          if (vault == null) return Center(child: Text('Vault not found', style: TextStyle(color: colors.textSecondary)));
          final progress = vault.progress;
          final maxContributor = vault.members.isNotEmpty
              ? vault.members.reduce((a, b) => a.contributedUsdc > b.contributedUsdc ? a : b)
              : null;

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero progress card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        colors.accent.withValues(alpha: 0.12),
                        colors.card,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: colors.divider),
                  ),
                  child: Column(
                    children: [
                      Text(vault.emoji ?? '🎯', style: const TextStyle(fontSize: 40)),
                      const SizedBox(height: 8),
                      Text(vault.name,
                        style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 16),
                      // Circular progress
                      SizedBox(
                        width: 120, height: 120,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 120, height: 120,
                              child: CircularProgressIndicator(
                                value: progress,
                                strokeWidth: 10,
                                backgroundColor: colors.divider,
                                valueColor: AlwaysStoppedAnimation(
                                  vault.isCompleted ? Colors.green : colors.accent,
                                ),
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('${(progress * 100).toInt()}%',
                                  style: TextStyle(color: colors.textPrimary, fontSize: 24, fontWeight: FontWeight.w900)),
                                Text('${vault.currentAmountUsdc.toStringAsFixed(0)}/${vault.targetAmountUsdc.toStringAsFixed(0)}',
                                  style: TextStyle(color: colors.textTertiary, fontSize: 10)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!vault.isCompleted)
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: ElevatedButton.icon(
                            onPressed: () => _showDepositSheet(vault, colors),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add Contribution', style: TextStyle(fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.accent,
                              foregroundColor: colors.isDark ? Colors.black : Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Members breakdown
                Text('Contributors',
                  style: TextStyle(color: colors.textSecondary, fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                ...vault.members.map((m) {
                  final pct = vault.currentAmountUsdc > 0
                      ? (m.contributedUsdc / vault.currentAmountUsdc * 100)
                      : 0.0;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colors.divider),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: colors.card,
                          backgroundImage: m.avatarUrl != null ? NetworkImage(m.avatarUrl!) : null,
                          child: m.avatarUrl == null
                              ? Text(m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                                  style: TextStyle(color: colors.textSecondary, fontSize: 14, fontWeight: FontWeight.w700))
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(m.name,
                                    style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
                                  if (m.isOwner) ...[
                                    const SizedBox(width: 5),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: colors.accent.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text('Owner',
                                        style: TextStyle(color: colors.accent, fontSize: 9, fontWeight: FontWeight.w700)),
                                    ),
                                  ] else if (m.isCoOwner) ...[
                                    const SizedBox(width: 5),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: colors.divider,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text('Co-owner',
                                        style: TextStyle(color: colors.textTertiary, fontSize: 9, fontWeight: FontWeight.w700)),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              // Individual progress bar
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: (pct / 100).clamp(0.0, 1.0),
                                  minHeight: 4,
                                  backgroundColor: colors.divider,
                                  valueColor: AlwaysStoppedAnimation(
                                    m == maxContributor ? colors.accent : colors.textTertiary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(m.contributedUsdc.toStringAsFixed(2),
                              style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
                            Text('${pct.toStringAsFixed(0)}%',
                              style: TextStyle(color: colors.textTertiary, fontSize: 10)),
                          ],
                        ),
                      ],
                    ),
                  );
                }),

                if (vault.linkedChatId != null) ...[
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        // Navigate to linked chat
                      },
                      icon: Icon(Icons.chat_bubble_outline, size: 18, color: colors.accent),
                      label: Text('Vault Chat', style: TextStyle(color: colors.accent, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: colors.accent.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _showDepositSheet(SharedVault vault, AzamanColors colors) {
    _depositAmount.clear();
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: colors.divider, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 16),
              Text('Contribute to ${vault.name}',
                style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              _TextField(
                controller: _depositAmount,
                hint: 'Amount in USDC',
                colors: colors,
                icon: Icons.attach_money,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => _deposit(vault),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.isDark ? Colors.black : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text('Deposit', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  final AzamanColors colors;
  const _FieldLabel({required this.text, required this.colors});

  @override
  Widget build(BuildContext context) => Text(text,
    style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600));
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final AzamanColors colors;
  final IconData icon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const _TextField({
    required this.controller,
    required this.hint,
    required this.colors,
    required this.icon,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Icon(icon, size: 18, color: colors.textTertiary),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: colors.textTertiary, fontSize: 14),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
