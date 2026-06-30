import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/screens/admin/ai_operations_screen.dart';


class AiCommandMenu extends ConsumerStatefulWidget {
  const AiCommandMenu({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AiCommandMenu(),
    );
  }

  @override
  ConsumerState<AiCommandMenu> createState() => _AiCommandMenuState();
}

class _AiCommandMenuState extends ConsumerState<AiCommandMenu>
    with SingleTickerProviderStateMixin {
  List<dynamic> _capabilities = [];
  bool _isLoading = true;
  String? _error;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _fetchCapabilities();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _fetchCapabilities() async {
    try {
      final response = await apiClient.get('/admin/ai/capabilities');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _capabilities = data['capabilities'] ?? [];
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() {
          _error = 'Failed to load capabilities';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _error = 'Network error';
        _isLoading = false;
      });
    }
  }

  IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('cfo') || n.contains('financial')) return Icons.account_balance_outlined;
    if (n.contains('dispute')) return Icons.gavel;
    if (n.contains('queue')) return Icons.playlist_add;
    if (n.contains('match')) return Icons.handshake_outlined;
    return Icons.auto_awesome;
  }

  Color _colorFor(String name, AzamanColors c) {
    final n = name.toLowerCase();
    if (n.contains('cfo') || n.contains('financial')) return c.success;
    if (n.contains('dispute')) return c.danger;
    if (n.contains('queue')) return c.warning;
    if (n.contains('match')) return c.accent;
    return c.accent;
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          _buildHandle(colors),
          _buildHeader(colors),
          Expanded(
            child: _isLoading
                ? _buildLoading(colors)
                : _error != null
                    ? _buildError(colors)
                    : _buildCapabilitiesList(colors),
          ),
          SizedBox(height: bottomInset),
        ],
      ),
    );
  }

  Widget _buildHandle(AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: colors.textTertiary.withOpacity(0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader(AzamanColors colors) {
    return FadeTransition(
      opacity: _pulseController,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: colors.accent.withOpacity(0.15)),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colors.accent.withOpacity(0.2),
                    colors.accent.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.auto_awesome, color: colors.accent, size: 22),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI COMMAND CENTER',
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Neural capabilities active',
                  style: TextStyle(color: colors.textTertiary, fontSize: 11),
                ),
              ],
            ),
            const Spacer(),
            IconButton(
              icon: Icon(Icons.refresh, color: colors.textTertiary, size: 18),
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _fetchCapabilities();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading(AzamanColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: colors.accent),
          const SizedBox(height: 16),
          Text(
            'Syncing neural network...',
            style: TextStyle(color: colors.textTertiary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildError(AzamanColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_outlined, color: colors.danger.withOpacity(0.5), size: 48),
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: colors.textTertiary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: Colors.black,
              elevation: 0,
            ),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
            onPressed: () {
              setState(() {
                _isLoading = true;
                _error = null;
              });
              _fetchCapabilities();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCapabilitiesList(AzamanColors colors) {
    if (_capabilities.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.psychology_outlined, color: colors.textTertiary.withOpacity(0.3), size: 48),
            const SizedBox(height: 12),
            Text(
              'No AI capabilities reported',
              style: TextStyle(color: colors.textTertiary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _capabilities.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final cap = _capabilities[index];
        final name = cap['name'] ?? 'Capability ${index + 1}';
        final desc = cap['description'] ?? '';
        final status = cap['status'] ?? 'idle';
        final isActive = status == 'active';
        final icon = _iconFor(name);
        final color = _colorFor(name, colors);

        return Container(
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isActive
                  ? color.withOpacity(0.4)
                  : colors.divider,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                if (name.toLowerCase().contains('cfo') ||
                    name.toLowerCase().contains('financial')) {
                  HapticFeedback.mediumImpact();
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AiOperationsScreen(),
                    ),
                  );
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: isActive ? colors.success : colors.textTertiary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (desc.isNotEmpty)
                            Text(
                              desc,
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
