import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class AiOperationsScreen extends ConsumerStatefulWidget {
  const AiOperationsScreen({super.key});

  @override
  ConsumerState<AiOperationsScreen> createState() => _AiOperationsScreenState();
}

class _AiOperationsScreenState extends ConsumerState<AiOperationsScreen> {
  bool _isLoadingInsights = true;
  bool _isLoadingCandidates = true;
  Map<String, dynamic> _cfoInsights = {};
  List<dynamic> _discountCandidates = [];
  String? _insightError;
  String? _candidatesError;
  final Map<int, TextEditingController> _discountControllers = {};
  final Map<int, TextEditingController> _durationControllers = {};
  final Set<int> _approvingIds = {};

  @override
  void initState() {
    super.initState();
    _fetchCfoInsights();
    _fetchDiscountCandidates();
  }

  @override
  void dispose() {
    for (final c in _discountControllers.values) {
      c.dispose();
    }
    for (final c in _durationControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchCfoInsights() async {
    try {
      final auth = ref.read(authProvider);
      final token = auth.token;
      if (token == null) return;
      final response = await apiClient.get('/admin/ai/cfo-insights');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _cfoInsights = data['insights'] ?? {};
            _isLoadingInsights = false;
          });
        }
      } else {
        if (mounted) setState(() {
          _insightError = 'Failed to load CFO insights';
          _isLoadingInsights = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _insightError = 'Network error';
        _isLoadingInsights = false;
      });
    }
  }

  Future<void> _fetchDiscountCandidates() async {
    try {
      final auth = ref.read(authProvider);
      final token = auth.token;
      if (token == null) return;
      final response = await apiClient.get('/admin/ai/discount-candidates');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _discountCandidates = data['candidates'] ?? [];
            _isLoadingCandidates = false;
            for (final c in _discountCandidates) {
              final id = c['id'] ?? 0;
              _discountControllers[id] = TextEditingController(text: '10');
              _durationControllers[id] = TextEditingController(text: '7');
            }
          });
        }
      } else {
        if (mounted) setState(() {
          _candidatesError = 'Failed to load candidates';
          _isLoadingCandidates = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _candidatesError = 'Network error';
        _isLoadingCandidates = false;
      });
    }
  }

  Future<void> _approveDiscount(int userId) async {
    setState(() => _approvingIds.add(userId));
    try {
      final auth = ref.read(authProvider);
      final token = auth.token;
      if (token == null) return;

      final discountPct = double.tryParse(
            _discountControllers[userId]?.text ?? '',
          ) ??
          10;
      final durationDays = int.tryParse(
            _durationControllers[userId]?.text ?? '',
          ) ??
          7;

      final response = await apiClient.post('/admin/ai/approve-discount', {
        'userId': userId,
        'discountPercent': discountPct,
        'durationDays': durationDays,
      });

      if (response.statusCode == 200) {
        HapticFeedback.heavyImpact();
        if (mounted) {
          setState(() {
            _discountCandidates.removeWhere((c) => (c['id'] ?? 0) == userId);
          });
          _showSnack('Discount approved for user #$userId', isError: false);
        }
      } else {
        final data = jsonDecode(response.body);
        if (mounted) {
          _showSnack(data['message'] ?? 'Approval failed', isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Network error during approval', isError: true);
      }
    } finally {
      if (mounted) setState(() => _approvingIds.remove(userId));
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    if (!mounted) return;
    final colors = ref.read(themeProvider).colors;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? colors.danger : colors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: colors.accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(HugeIconsSolid.sparkles, color: Color(0xFFD4AF37), size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              'AI OPERATIONS',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(HugeIconsSolid.refresh01, color: colors.textTertiary),
            onPressed: () {
              setState(() {
                _isLoadingInsights = true;
                _isLoadingCandidates = true;
                _insightError = null;
                _candidatesError = null;
              });
              _fetchCfoInsights();
              _fetchDiscountCandidates();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildCfoSection(colors),
          const SizedBox(height: 24),
          _buildDiscountSection(colors),
        ],
      ),
    );
  }

  // ============================================================
  // SECTION 1: AI CFO INSIGHTS
  // ============================================================
  Widget _buildCfoSection(AzamanColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('AI CFO INSIGHTS', HugeIconsSolid.bank, colors),
        const SizedBox(height: 12),
        _isLoadingInsights
            ? _loadingCard(colors)
            : _insightError != null
                ? _errorCard(_insightError!, colors)
                : _buildInsightCards(colors),
      ],
    );
  }

  Widget _buildInsightCards(AzamanColors colors) {
    final maticBurn = _cfoInsights['maticBurnRate']?.toString() ?? '0.0025';
    final maticLabel = _cfoInsights['maticBurnLabel']?.toString() ?? 'MATIC / tx';
    final apiRenewals = _cfoInsights['upcomingApiRenewals'];
    final renewalDate = _cfoInsights['nextRenewalDate']?.toString() ?? '2026-06-01';
    final renewalCost = _cfoInsights['renewalCost']?.toString() ?? '150';
    final monthlyBurn = _cfoInsights['monthlyMaticBurn']?.toString() ?? '12.4';
    final treasuryHealth = _cfoInsights['treasuryHealth']?.toString() ?? 'Stable';

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _insightCard(
                HugeIconsSolid.fire,
                'MATIC Burn',
                '$maticBurn $maticLabel',
                '${monthlyBurn} MATIC / mo',
                colors.danger,
                colors,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _insightCard(
                HugeIconsSolid.wallet01,
                'Treasury',
                treasuryHealth,
                '${_cfoInsights['treasuryBalance'] ?? '---'} MATIC',
                colors.success,
                colors,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (apiRenewals != null && apiRenewals is List)
          ...apiRenewals.map<Widget>((r) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _renewalTile(r, colors),
              )),
        if (apiRenewals == null)
          _insightCard(
            HugeIconsSolid.refresh01,
            'Next API Renewal',
            renewalDate,
            '\$${renewalCost} USD',
            colors.warning,
            colors,
          ),
      ],
    );
  }

  Widget _insightCard(
    IconData icon,
    String label,
    String value,
    String sub,
    Color highlight,
    AzamanColors colors,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: highlight.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: highlight, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            style: TextStyle(color: colors.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _renewalTile(dynamic renewal, AzamanColors colors) {
    final name = renewal['name'] ?? 'API Service';
    final date = renewal['date'] ?? 'Unknown';
    final cost = renewal['cost'] ?? '0';
    final daysLeft = renewal['daysLeft']?.toString() ?? '--';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.warning.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(HugeIconsSolid.refresh01, color: colors.warning, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Renewal: $date',
                  style: TextStyle(color: colors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$$cost',
                style: TextStyle(
                  color: colors.warning,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Text(
                '${daysLeft}d left',
                style: TextStyle(color: colors.textTertiary, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SECTION 2: DISCOUNT CREDIT APPROVAL
  // ============================================================
  Widget _buildDiscountSection(AzamanColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('DISCOUNT CREDIT APPROVAL', HugeIconsSolid.percent, colors),
        const SizedBox(height: 6),
        Text(
          'Users who have hit milestones — review and grant fee discounts.',
          style: TextStyle(color: colors.textTertiary, fontSize: 11),
        ),
        const SizedBox(height: 12),
        ..._buildDiscountContent(colors),
      ],
    );
  }

  List<Widget> _buildDiscountContent(AzamanColors colors) {
    if (_isLoadingCandidates) return [_loadingCard(colors)];
    if (_candidatesError != null) return [_errorCard(_candidatesError!, colors)];
    if (_discountCandidates.isEmpty) return [_emptyCandidates(colors)];
    return List.generate(
      _discountCandidates.length,
      (i) => Padding(
        padding: EdgeInsets.only(
          bottom: i < _discountCandidates.length - 1 ? 12 : 0,
        ),
        child: _buildCandidateCard(_discountCandidates[i], colors),
      ),
    );
  }

  Widget _emptyCandidates(AzamanColors colors) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        children: [
          Icon(HugeIconsSolid.party, color: colors.success.withOpacity(0.4), size: 40),
          const SizedBox(height: 12),
          Text(
            'No discount candidates right now',
            style: TextStyle(color: colors.textTertiary, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            'Users appear here when they hit milestones',
            style: TextStyle(color: colors.textTertiary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildCandidateCard(dynamic candidate, AzamanColors colors) {
    final id = candidate['id'] ?? 0;
    final username = candidate['username'] ?? 'User #$id';
    final milestone = candidate['milestone'] ?? 'N/A';
    final trades = candidate['trades']?.toString() ?? '0';
    final volume = candidate['volume']?.toString() ?? '0';
    final isApproving = _approvingIds.contains(id);

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.accent.withOpacity(0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    HugeIconsSolid.award01,
                    color: colors.success,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        username,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Milestone: $milestone',
                        style: TextStyle(color: colors.accent, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$trades trades',
                    style: TextStyle(
                      color: colors.accent,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 50),
              child: Text(
                'Volume: GHS $volume',
                style: TextStyle(color: colors.textSecondary, fontSize: 11),
              ),
            ),
            const SizedBox(height: 14),
            Divider(color: colors.divider, height: 1),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Discount %',
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _discountControllers[id],
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          suffixText: '%',
                          suffixStyle: TextStyle(color: colors.textTertiary),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          filled: true,
                          fillColor: colors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Duration',
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _durationControllers[id],
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          suffixText: 'days',
                          suffixStyle: TextStyle(color: colors.textTertiary),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          filled: true,
                          fillColor: colors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.success.withOpacity(0.15),
                  foregroundColor: colors.success,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  disabledBackgroundColor: colors.divider,
                ),
                icon: isApproving
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.success,
                        ),
                      )
                    : const Icon(HugeIconsSolid.checkmarkCircle01, size: 18),
                label: Text(
                  isApproving ? 'APPROVING...' : 'APPROVE DISCOUNT CREDIT',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                onPressed:
                    isApproving ? null : () => _approveDiscount(id),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SHARED HELPERS
  // ============================================================
  Widget _sectionHeader(String title, IconData icon, AzamanColors colors) {
    return Row(
      children: [
        Icon(icon, size: 16, color: colors.textTertiary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: colors.textTertiary,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _loadingCard(AzamanColors colors) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: CircularProgressIndicator(color: colors.accent),
      ),
    );
  }

  Widget _errorCard(String msg, AzamanColors colors) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.danger.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(HugeIconsSolid.alertCircle, color: colors.danger, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              msg,
              style: TextStyle(color: colors.textTertiary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
