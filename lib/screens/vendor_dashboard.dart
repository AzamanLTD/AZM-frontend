import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert'; 
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/trade_provider.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/azm_spend_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/socket_service.dart';
import 'package:azaman/services/api_client.dart';
import 'vendor_ad_creator.dart';
import 'trade_accounts_screen.dart';
import 'vendor_trade_execution.dart';
import 'vendor_settings_screen.dart';
import 'vendor_analytics_screen.dart';
import 'package:azaman/widgets/azaman_empty_state.dart';
import 'package:azaman/widgets/nav_transitions.dart';
import 'package:azaman/widgets/az_pull_to_refresh.dart';


class VendorDashboard extends ConsumerStatefulWidget {
  const VendorDashboard({super.key});

  @override
  ConsumerState<VendorDashboard> createState() => _VendorDashboardState();
}

class _VendorDashboardState extends ConsumerState<VendorDashboard> with TickerProviderStateMixin {
  List<Map<String, dynamic>> pendingTrades = [];
  bool isOnline = true;
  bool _isBalanceVisible = true;
  
  double _availableBalance = 0.0;
  // Phase J (2026-05-25): renamed from _lockedBalance and rebound from the
  // dropped V1 `lockedBalance` column to the V2 `escrowLockedBalance`. The
  // "LOCKED (IN ESCROW)" UI label now reflects real active-trade locks for
  // the first time — the legacy column was always 0.0 (write-dead).
  double _escrowLockedBalance = 0.0;
  double _vendorUnallocatedBalance = 0.0;

  bool _isLoadingTrades = true;

  // Named socket callback so dispose() can detach just ours,
  // leaving the provider-level global balance listener intact.
  dynamic Function(dynamic)? _balanceHandler; // <-- FIXED STRICT TYPING HERE

  // Cached provider reference to avoid ref.read() during dispose().
  TradeProvider? _trade;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initRealtimeListeners();
      _fetchVendorBalances();
      _fetchPendingTrades(); 
      _fetchVendorAds(); // --- PHASE 8: Fetch real ads from API ---
    });
  }

  // --- PHASE 8: FETCH VENDOR'S OWN ADS ---
  Future<void> _fetchVendorAds() async {
    // Renamed local from `tradeProvider` to `trade` throughout this file
    // to avoid shadowing the top-level Riverpod `tradeProvider` symbol.
    final auth = ref.read(authProvider);
    final trade = ref.read(tradeProvider);
    final token = auth.user?.token ?? auth.token;
    if (token == null) return;
    await trade.fetchMyAds(token);
  }

  Future<void> _fetchVendorBalances() async {
    final auth = ref.read(authProvider);
    final userId = auth.user?.id;

    if (userId == null) return;

    try {
      final response = await apiClient.get('/auth/me/$userId');

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        // API returns { success, data: {...} } or { success, user: {...} } or flat
        final data = body['data'] ?? body['user'] ?? body;
        if (mounted) {
          setState(() {
            _availableBalance = double.tryParse(data['availableBalance']?.toString() ?? "0.0") ?? 0.0;
            _escrowLockedBalance = double.tryParse(data['escrowLockedBalance']?.toString() ?? "0.0") ?? 0.0;
            _vendorUnallocatedBalance = double.tryParse(data['vendorUnallocatedBalance']?.toString() ?? "0.0") ?? 0.0;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching balances: $e");
    }
  }

  Future<void> _fetchPendingTrades() async {
    try {
      final auth = ref.read(authProvider);
      final vendorId = auth.user?.id;

      final response = await apiClient.get('/trades/history');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List history = data['history'] ?? [];

        final activeTrades = history.where((t) {
          final isVendor = t['vendorId'].toString() == vendorId.toString();
          final isActive = t['status'] != 'COMPLETED' && t['status'] != 'CANCELLED';
          return isVendor && isActive;
        }).toList();

        if (mounted) {
          setState(() {
            pendingTrades = activeTrades.map<Map<String, dynamic>>((t) => {
              'tradeId': t['id'].toString(),
              'amount': t['amountFiat'].toString(),
              // Phase H3 — forward typed fields so the release-crypto sheet
              // shows real numbers, not 0.00 USDT / 0.00 GHS. The legacy
              // `amount` key (stringified fiat) is kept for backwards
              // compat with consumers that haven't migrated yet.
              'amountFiat': (t['amountFiat'] as num?)?.toDouble(),
              'amountCrypto': (t['amountCrypto'] as num?)?.toDouble(),
              'crypto': t['crypto']?.toString(),
              'currency': t['currency']?.toString(),
              'userName': 'Buyer #${t['userId']}',
              'paymentMethod': t['paymentMethod'] ?? 'Bank Transfer',
              'status': t['status'],
              'timestamp': DateTime.parse(t['createdAt'])
            }).toList();
            _isLoadingTrades = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching trades: $e");
      if (mounted) setState(() => _isLoadingTrades = false);
    }
  }

  void _initRealtimeListeners() {
    _trade = ref.read(tradeProvider);
    final auth = ref.read(authProvider);
    final socket = SocketService.instance.rawSocket; 
    final userId = auth.user?.id;

    if (userId == null || socket == null) return;

    // Phase P3: Room joining is handled by SocketService.init() in MainWrapper.
    // No need to re-join here.

    // Phase 15: use a NAMED handler so dispose() can detach only this
    // callback instead of nuking every balance_update listener.
    handler(data) {
      if (!mounted) return null;
      setState(() {
        if (data is Map && data['availableBalance'] != null) {
          _availableBalance = double.tryParse(data['availableBalance'].toString()) ?? _availableBalance;
        }
        if (data is Map && data['escrowLockedBalance'] != null) {
          _escrowLockedBalance = double.tryParse(data['escrowLockedBalance'].toString()) ?? _escrowLockedBalance;
        }
        if (data is Map && data['vendorUnallocatedBalance'] != null) {
          _vendorUnallocatedBalance = double.tryParse(data['vendorUnallocatedBalance'].toString()) ?? _vendorUnallocatedBalance;
        }
      });
      return null;
    }
    
    _balanceHandler = handler;
    socket.on('balance_update', handler);

    socket.on('new_trade_request', (data) {
      HapticFeedback.heavyImpact(); 
      if (mounted) {
        setState(() {
          pendingTrades.insert(0, {
            'tradeId': data['tradeId'].toString(), 
            'amount': data['amount'].toString(),
            // Phase H3 — forward typed fields when the socket payload has
            // them (newer backend emits both legacy `amount` and the typed
            // `amountFiat`/`amountCrypto`). Older payloads still work via
            // the `amount` fallback in _ReleaseCryptoSheet.
            'amountFiat': (data['amountFiat'] as num?)?.toDouble(),
            'amountCrypto': (data['amountCrypto'] as num?)?.toDouble(),
            'crypto': data['crypto']?.toString(),
            'currency': data['currency']?.toString(),
            'userName': data['buyerName'] ?? 'Buyer',
            'paymentMethod': 'Bank Transfer',
            'status': 'NEW',
            'timestamp': DateTime.now()
          });
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("NEW ORDER: \$${data['amount']} from ${data['buyerName']}"),
            backgroundColor: const Color(0xFF02C076),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: "VIEW", 
              textColor: Colors.black, 
              onPressed: () => _autoTriggerTradeExecution(pendingTrades.first)
            ),
          )
        );
      }
    });
  }

  void _autoTriggerTradeExecution(Map<String, dynamic> tradeData) {
    HapticFeedback.selectionClick();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => VendorTradeExecution(tradeData: tradeData)),
    ).then((_) {
      _fetchPendingTrades(); 
      _fetchVendorBalances();
    });
  }

  // --- PHASE 8: HANDLE AD TOGGLE ---
  Future<void> _handleAdToggle(int adId) async {
    final auth = ref.read(authProvider);
    final trade = ref.read(tradeProvider);
    final token = auth.user?.token ?? auth.token;
    if (token == null) return;

    HapticFeedback.selectionClick();
    final success = await trade.toggleAdStatus(adId, token);
    
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Failed to toggle ad status."),
          backgroundColor: Color(0xFFF6465D),
        )
      );
    }
  }

  @override
  void dispose() {
    // Phase P3: Detach our per-screen listeners from the unified socket.
    final socket = SocketService.instance.rawSocket;
    if (socket != null) {
      if (_balanceHandler != null) {
        socket.off('balance_update', _balanceHandler);
      }
      socket.off('new_trade_request');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color azamanGold = ref.read(themeProvider).colors.accent;
    const Color binanceGreen = Color(0xFF02C076);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            const TechBackground(), 
            
            SafeArea(
              child: Column(
                children: [
                  _buildPremiumHeader(azamanGold, binanceGreen),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    child: _todayGlance(ref.read(themeProvider).colors),
                  ),
                  const SizedBox(height: 16),
                  _buildProtocolBalanceCard(azamanGold),
                  
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TabBar(
                      indicatorColor: azamanGold,
                      labelColor: azamanGold,
                      unselectedLabelColor: Colors.white24,
                      indicatorSize: TabBarIndicatorSize.label,
                      dividerColor: Colors.transparent,
                      tabs: [
                        Tab(child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text("OPEN ORDERS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            if (pendingTrades.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                child: Text("${pendingTrades.length}", style: const TextStyle(fontSize: 10, color: Colors.white)),
                              )
                            ]
                          ],
                        )),
                        // --- PHASE 8: SHOW AD COUNT IN TAB ---
                        Tab(child: Consumer(
                          builder: (context, ref, _) {
                            final tp = ref.watch(tradeProvider);
                            final adCount = tp.myActiveAds.where((a) => a['status'] == 'ACTIVE').length;
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text("MY ADS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                if (adCount > 0) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: azamanGold.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                                    child: Text("$adCount", style: TextStyle(fontSize: 10, color: azamanGold, fontWeight: FontWeight.bold)),
                                  )
                                ]
                              ],
                            );
                          },
                        )),
                      ],
                    ),
                  ),

                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildTradeTab(azamanGold),
                        _buildAdTab(azamanGold),
                      ],
                    ),
                  ),
                  
                  _buildPostAdButton(azamanGold),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- WIDGETS ---

  // "Today at a Glance" horizontal stats row (P2P Premium Sprint, 2026-06-21).
  // Computed live from pendingTrades + the already-loaded balances. The trade
  // maps in this screen carry `timestamp` (a DateTime) and `amountFiat`; there
  // is no acceptedAt field, so the average-response metric shows "–" until that
  // data is available rather than fabricating a value.
  Widget _todayGlance(AzamanColors colors) {
    final now = DateTime.now();
    final todayTrades = pendingTrades.where((t) {
      final created = _glanceCreated(t);
      return created != null &&
          created.year == now.year &&
          created.month == now.month &&
          created.day == now.day;
    }).toList();

    // Volume locked in escrow today
    final todayVolume = todayTrades.fold<double>(
        0, (s, t) => s + ((t['amountFiat'] as num?)?.toDouble() ?? 0));

    // Avg response time (createdAt → first status change, in minutes)
    double avgResponseMin = 0;
    final responseTimes = <double>[];
    for (final t in todayTrades) {
      final created = _glanceCreated(t);
      final accepted =
          DateTime.tryParse(t['acceptedAt']?.toString() ?? '');
      if (created != null && accepted != null) {
        responseTimes.add(accepted.difference(created).inSeconds / 60.0);
      }
    }
    if (responseTimes.isNotEmpty) {
      avgResponseMin =
          responseTimes.reduce((a, b) => a + b) / responseTimes.length;
    }

    final stats = [
      _GlanceStat(
        icon: Icons.shopping_bag_outlined,
        label: 'Today\'s Trades',
        value: '${todayTrades.length}',
        color: colors.accent,
      ),
      _GlanceStat(
        icon: Icons.swap_horiz,
        label: 'Today\'s Volume',
        value: '\$${_fmt(todayVolume)}',
        color: colors.success,
      ),
      _GlanceStat(
        icon: Icons.account_balance_wallet_outlined,
        label: 'Escrow Locked',
        value: '\$${_fmt(_escrowLockedBalance)}',
        color: colors.warning,
      ),
      _GlanceStat(
        icon: Icons.access_time,
        label: 'Avg Response',
        value: responseTimes.isEmpty
            ? '–'
            : '${avgResponseMin.toStringAsFixed(1)} min',
        color: colors.textSecondary,
      ),
      _GlanceStat(
        icon: Icons.check_circle_outline,
        label: 'Available',
        value: '\$${_fmt(_availableBalance)}',
        color: colors.success,
      ),
    ];

    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: stats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final s = stats[i];
          return Container(
            width: 130,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(s.icon, size: 13, color: s.color),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        s.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  s.value,
                  style: TextStyle(
                    color: s.color,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Extract the created timestamp from a pendingTrades entry. The maps store
  /// it under `timestamp` as a DateTime (see _fetchPendingTrades), with an ISO
  /// `createdAt` fallback for any payload that uses that key instead.
  DateTime? _glanceCreated(Map<String, dynamic> t) {
    final ts = t['timestamp'];
    if (ts is DateTime) return ts;
    return DateTime.tryParse(
        t['timestamp']?.toString() ?? t['createdAt']?.toString() ?? '');
  }

  String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  Widget _buildPremiumHeader(Color gold, Color green) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              // Back button — the vendor portal is a pushed route reached
              // from the P2P pull-tab, so it MUST offer a way home.
              // Without this the user gets stranded on the dashboard.
              IconButton(
                icon: Icon(Icons.arrow_back, color: gold, size: 20),
                tooltip: 'Back',
                onPressed: () {
                  HapticFeedback.lightImpact();
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                },
              ),
              const SizedBox(width: 4),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("VENDOR PROTOCOL", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1)),
                  Text(isOnline ? "NODE: ACTIVE" : "NODE: OFFLINE", style: TextStyle(color: isOnline ? green : Colors.white24, fontSize: 9, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.analytics_outlined, color: gold),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  pushWithVerticalTransition(context, const VendorAnalyticsScreen());
                },
              ),
              IconButton(
                icon: Icon(Icons.settings_outlined, color: gold), 
                onPressed: () {
                  HapticFeedback.lightImpact();
                  pushWithVerticalTransition(context, VendorSettingsScreen(pendingTradeCount: pendingTrades.length,));
                },
              ),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: isOnline, 
                  activeThumbColor: green, 
                  onChanged: (val) {
                    setState(() => isOnline = val);
                    SocketService.instance.emit('toggle_online', {'isOnline': val});
                  }
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProtocolBalanceCard(Color gold) {
    double totalFunding = _vendorUnallocatedBalance + _escrowLockedBalance;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(colors: [Colors.white.withValues(alpha: 0.05), Colors.transparent]),
        border: Border.all(color: gold.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("VENDOR TRADING OVERVIEW", style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
              Icon(Icons.shield_outlined, color: gold.withValues(alpha: 0.5), size: 18),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                _isBalanceVisible ? totalFunding.toStringAsFixed(2) : "••••••", 
                style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)
              ),
              const SizedBox(width: 8),
              const Text("USDC", style: TextStyle(color: Colors.white38, fontSize: 12)),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => setState(() => _isBalanceVisible = !_isBalanceVisible),
                child: Icon(_isBalanceVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.white24, size: 18),
              )
            ],
          ),
          const SizedBox(height: 16),
          // Three-column balance breakdown
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("TRADING POOL", style: TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(_isBalanceVisible ? "\$${_vendorUnallocatedBalance.toStringAsFixed(2)}" : "•••", style: TextStyle(color: gold, fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text("IN ESCROW", style: TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(_isBalanceVisible ? "\$${_escrowLockedBalance.toStringAsFixed(2)}" : "•••", style: const TextStyle(color: Color(0xFFF6465D), fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text("WALLET", style: TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(_isBalanceVisible ? "\$${_availableBalance.toStringAsFixed(2)}" : "•••", style: const TextStyle(color: Color(0xFF02C076), fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Transfer buttons
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _showTransferSheet('TO_POOL'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: gold.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.arrow_forward, size: 14, color: gold),
                        const SizedBox(width: 6),
                        Text("Fund Pool", style: TextStyle(color: gold, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => _showTransferSheet('FROM_POOL'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF02C076).withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.arrow_back, size: 14, color: Color(0xFF02C076)),
                        SizedBox(width: 6),
                        Text("To Wallet", style: TextStyle(color: Color(0xFF02C076), fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showTransferSheet(String direction) {
    final maxAmount = direction == 'TO_POOL' ? _availableBalance : _vendorUnallocatedBalance;
    final fromLabel = direction == 'TO_POOL' ? 'Available Wallet' : 'Trading Pool';
    final toLabel = direction == 'TO_POOL' ? 'Trading Pool' : 'Available Wallet';
    final colors = ref.read(themeProvider).colors;
    final accentColor = direction == 'TO_POOL' ? colors.accent : const Color(0xFF02C076);

    if (maxAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No funds in $fromLabel to transfer.'), backgroundColor: Colors.red),
      );
      return;
    }

    final amountController = TextEditingController();
    double confirmDragX = 0;
    bool isConfirmed = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final enteredAmount = double.tryParse(amountController.text) ?? 0;
          final isValidAmount = enteredAmount > 0 && enteredAmount <= maxAmount;

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          direction == 'TO_POOL' ? Icons.account_balance_wallet_outlined : Icons.arrow_back,
                          color: accentColor, size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Transfer Funds', style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                            Text('$fromLabel → $toLabel', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Amount input
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: colors.textPrimary, fontSize: 28, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: InputDecoration(
                      hintText: '0.00',
                      hintStyle: TextStyle(color: colors.textTertiary),
                      prefixText: '\$ ',
                      prefixStyle: TextStyle(color: colors.textSecondary, fontSize: 28),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: colors.divider)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: colors.divider)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: accentColor)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Available: \$${maxAmount.toStringAsFixed(2)}', style: TextStyle(color: colors.textTertiary, fontSize: 12)),
                  const SizedBox(height: 12),

                  // Quick amount buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [25, 50, 75, 100].map((pct) {
                      final amt = maxAmount * pct / 100;
                      return GestureDetector(
                        onTap: () {
                          amountController.text = amt.toStringAsFixed(2);
                          setSheetState(() {});
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colors.divider),
                          ),
                          child: Text('$pct%', style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // Slide to confirm
                  if (isValidAmount) ...[
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final trackWidth = constraints.maxWidth;
                        const thumbSize = 56.0;
                        final maxDrag = trackWidth - thumbSize;

                        return GestureDetector(
                          onHorizontalDragUpdate: (details) {
                            setSheetState(() {
                              confirmDragX = (confirmDragX + details.delta.dx).clamp(0.0, maxDrag);
                            });
                            if (confirmDragX >= maxDrag * 0.9 && !isConfirmed) {
                              isConfirmed = true;
                              HapticFeedback.heavyImpact();
                              Navigator.pop(ctx);
                              _executeTransfer(direction, enteredAmount);
                            }
                          },
                          onHorizontalDragEnd: (_) {
                            if (!isConfirmed) {
                              setSheetState(() => confirmDragX = 0);
                            }
                          },
                          child: Container(
                            height: 56,
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                            ),
                            child: Stack(
                              children: [
                                // Track fill
                                Positioned.fill(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      width: confirmDragX + thumbSize,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        color: accentColor.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(28),
                                      ),
                                    ),
                                  ),
                                ),
                                // Label
                                Center(
                                  child: Text(
                                    'Slide to confirm transfer',
                                    style: TextStyle(color: accentColor.withValues(alpha: 0.7), fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                // Thumb
                                Positioned(
                                  left: confirmDragX,
                                  top: 4,
                                  child: Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: accentColor,
                                      borderRadius: BorderRadius.circular(24),
                                      boxShadow: [BoxShadow(color: accentColor.withValues(alpha: 0.4), blurRadius: 8)],
                                    ),
                                    child: const Icon(Icons.arrow_forward, color: Colors.white, size: 22),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ] else ...[
                    Container(
                      height: 56,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: colors.divider.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Center(
                        child: Text(
                          'Enter amount to continue',
                          style: TextStyle(color: colors.textTertiary, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _executeTransfer(String direction, double amount) async {
    try {
      final response = await apiClient.post('/wallet/internal-transfer', {
        'direction': direction,
        'amount': amount,
      });

      if (response.statusCode == 200) {
        HapticFeedback.heavyImpact();
        // Refresh balances and wait for completion
        await _fetchVendorBalances();
        // Small delay to ensure setState has propagated
        await Future.delayed(const Duration(milliseconds: 100));
        // Show success dialog with updated balance breakdown
        if (mounted) _showTransferSuccess(direction, amount);
      } else {
        final data = jsonDecode(response.body);
        throw Exception(data['message'] ?? 'Transfer failed');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transfer failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showTransferSuccess(String direction, double amount) {
    final colors = ref.read(themeProvider).colors;
    final toLabel = direction == 'TO_POOL' ? 'Trading Pool' : 'Available Wallet';

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF02C076).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_outline, color: Color(0xFF02C076), size: 48),
              ),
              const SizedBox(height: 16),
              Text('Transfer Complete', style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(
                '\$${amount.toStringAsFixed(2)} moved to $toLabel',
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),
              // Balance breakdown
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _balanceRow('Trading Pool', _vendorUnallocatedBalance, colors.accent, colors),
                    const SizedBox(height: 10),
                    _balanceRow('In Escrow', _escrowLockedBalance, const Color(0xFFF6465D), colors),
                    const SizedBox(height: 10),
                    _balanceRow('Available Wallet', _availableBalance, const Color(0xFF02C076), colors),
                    Divider(color: colors.divider, height: 20),
                    _balanceRow('Total', _availableBalance + _vendorUnallocatedBalance + _escrowLockedBalance, colors.textPrimary, colors, isBold: true),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Done', style: TextStyle(color: colors.accent, fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _balanceRow(String label, double amount, Color color, dynamic colors, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        Text(
          '\$${amount.toStringAsFixed(2)}',
          style: TextStyle(color: color, fontSize: 13, fontWeight: isBold ? FontWeight.w900 : FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildTradeTab(Color gold) {
    if (_isLoadingTrades) {
      return Center(child: CircularProgressIndicator(color: ref.read(themeProvider).colors.accent));
    }
    if (pendingTrades.isEmpty) return const AzamanEmptyState(icon: Icons.radar, title: "No Active Orders", subtitle: "New trade requests will appear here.");
    
    return ListView.builder(
      itemCount: pendingTrades.length,
      padding: const EdgeInsets.all(20),
      itemBuilder: (context, index) {
        if (index == 0) {
          return PulseCard(child: _buildTradeCard(pendingTrades[index], gold));
        }
        return _buildTradeCard(pendingTrades[index], gold);
      },
    );
  }

  Widget _buildTradeCard(Map<String, dynamic> trade, Color gold) {
    return GestureDetector(
      onTap: () => _autoTriggerTradeExecution(trade),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ref.read(themeProvider).colors.card,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: gold.withValues(alpha: 0.3)), 
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 5))]
        ),
        child: Row(
          children: [
            CircleAvatar(backgroundColor: gold.withValues(alpha: 0.1), child: Icon(Icons.notifications_outlined, color: gold, size: 20)),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("BUYER: ${trade['userName']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text("${trade['amount']} GHS", style: TextStyle(color: gold, fontWeight: FontWeight.w900, fontSize: 18)),
                  const SizedBox(height: 4),
                  Text("STATUS: ${trade['status']}", style: const TextStyle(color: Colors.white24, fontSize: 10)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: gold, borderRadius: BorderRadius.circular(8)),
              child: const Text("VIEW", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }

  // ============================================================
  // --- PHASE 8: REDESIGNED AD TAB WITH REAL DATA & TOGGLES ---
  // ============================================================

  Widget _buildAdTab(Color gold) {
    return Consumer(
      builder: (context, ref, _) {
        // Local var renamed from `tradeProvider` to `trade` to avoid
        // shadowing the top-level Riverpod `tradeProvider` symbol.
        final trade = ref.watch(tradeProvider);
        if (trade.isLoadingAds) {
          return Center(child: CircularProgressIndicator(color: ref.read(themeProvider).colors.accent));
        }

        final ads = trade.myActiveAds;
        if (ads.isEmpty) return const AzamanEmptyState(icon: Icons.layers_outlined, title: "No Advertisements Yet", subtitle: "Create your first ad to start receiving trade requests.");

        return AzPullToRefresh(
          color: gold,
          backgroundColor: ref.read(themeProvider).colors.card,
          onRefresh: _fetchVendorAds,
          child: ListView.builder(
            itemCount: ads.length,
            padding: const EdgeInsets.all(20),
            physics: const AlwaysScrollableScrollPhysics(),
            itemBuilder: (context, index) => _buildAdCard(ads[index], gold),
          ),
        );
      },
    );
  }

  Widget _buildAdCard(Map<String, dynamic> ad, Color gold) {
    final bool isBuy = ad['type'] == "BUY";
    final bool isActive = ad['status'] == 'ACTIVE';
    final double price = (ad['pricePerUSD'] as num?)?.toDouble() ?? 0.0;
    final double minLimit = (ad['minLimit'] as num?)?.toDouble() ?? 0.0;
    final double maxLimit = (ad['maxLimit'] as num?)?.toDouble() ?? 0.0;
    final String paymentMethod = ad['paymentMethod'] ?? 'Bank Transfer';
    final String? terms = ad['terms'];
    final double? margin = (ad['margin'] as num?)?.toDouble();
    final int adId = ad['id'];

    final Color typeColor = isBuy ? const Color(0xFF02C076) : const Color(0xFFF6465D);

    return AnimatedOpacity(
      opacity: isActive ? 1.0 : 0.5,
      duration: const Duration(milliseconds: 300),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: ref.read(themeProvider).colors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? gold.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.05),
            width: isActive ? 1.2 : 0.5,
          ),
          boxShadow: [
            if (isActive)
              BoxShadow(
                color: gold.withValues(alpha: 0.06),
                blurRadius: 16,
                spreadRadius: -2,
              ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 1,
              offset: const Offset(0, 0),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- ROW 1: Type Badge + Toggle Switch ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: typeColor.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        isBuy ? "BUY" : "SELL",
                        style: TextStyle(color: typeColor, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      ad['crypto'] ?? 'USDT',
                      style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
                // --- THE TOGGLE SWITCH ---
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFF02C076).withValues(alpha: 0.1)
                            : Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isActive ? "LIVE" : "OFF",
                        style: TextStyle(
                          color: isActive ? const Color(0xFF02C076) : Colors.white24,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Transform.scale(
                      scale: 0.7,
                      child: Switch(
                        value: isActive,
                        activeThumbColor: const Color(0xFF02C076),
                        inactiveTrackColor: Colors.white10,
                        onChanged: (_) => _handleAdToggle(adId),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 14),

            // --- ROW 2: Price ---
            Text(
              "${price.toStringAsFixed(2)} GHS / \$1",
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
            ),

            const SizedBox(height: 14),
            
            // --- ROW 3: Limits + Method ---
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
              ),
              child: Column(
                children: [
                  _adDetailRow("Limits", "\$${minLimit.toStringAsFixed(0)} – \$${maxLimit.toStringAsFixed(0)}"),
                  const SizedBox(height: 8),
                  _adDetailRow("Method", paymentMethod),
                  if (margin != null) ...[
                    const SizedBox(height: 8),
                    _adDetailRow("Margin", "${margin.toStringAsFixed(1)}%"),
                  ],
                ],
              ),
            ),

            // --- ROW 4: Terms (if any) ---
            if (terms != null && terms.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.note_outlined, color: gold.withValues(alpha: 0.5), size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      terms,
                      style: const TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            // --- ROW 5: Boost Button (Phase E2) ---
            if (isActive) ...[
              const SizedBox(height: 14),
              _buildBoostButton(ad, gold),
            ],
          ],
        ),
      ),
    );
  }

  Widget _adDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        Text(value, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ── Phase E2: Ad Boost Button & Sheet ─────────────────────────────────────

  Widget _buildBoostButton(Map<String, dynamic> ad, Color gold) {
    final bool isBoosted = ad['isBoosted'] == true;
    final String? boostExpiresAt = ad['boostExpiresAt']?.toString();
    final bool boostActive = isBoosted &&
        boostExpiresAt != null &&
        DateTime.tryParse(boostExpiresAt)?.isAfter(DateTime.now()) == true;

    if (boostActive) {
      // Show "Boosted" badge with remaining time
      final expires = DateTime.parse(boostExpiresAt);
      final remaining = expires.difference(DateTime.now());
      final label = remaining.inHours > 24
          ? '${(remaining.inHours / 24).ceil()}d left'
          : remaining.inHours > 0
              ? '${remaining.inHours}h left'
              : '${remaining.inMinutes}m left';

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF02C076).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF02C076).withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.rocket_launch_outlined,
                size: 14, color: Color(0xFF02C076)),
            const SizedBox(width: 6),
            Text(
              'BOOSTED  \u2022  $label',
              style: const TextStyle(
                color: Color(0xFF02C076),
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => _showBoostSheet(ad, gold),
              child: Text(
                'EXTEND',
                style: TextStyle(
                  color: gold,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () => _showBoostSheet(ad, gold),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: gold.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: gold.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.rocket_launch_outlined, size: 14, color: gold),
            const SizedBox(width: 6),
            Text(
              'BOOST AD',
              style: TextStyle(
                color: gold,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            Text(
              'from 15 AZM',
              style: TextStyle(
                color: gold.withValues(alpha: 0.6),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBoostSheet(Map<String, dynamic> ad, Color gold) {
    final int adId = ad['id'];

    showModalBottomSheet(
      context: context,
      backgroundColor: ref.read(themeProvider).colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AdBoostSheet(
        adId: adId,
        gold: gold,
        onBoostSuccess: () {
          _fetchVendorAds(); // Refresh ads to show the boosted state
          Navigator.pop(ctx);
        },
      ),
    );
  }

  Widget _buildPostAdButton(Color gold) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context, 
                  MaterialPageRoute(builder: (_) => const VendorAdCreator()),
                ).then((_) => _fetchVendorAds()); // Refresh ads after returning
              },
              icon: const Icon(Icons.add),
              label: const Text("CREATE NEW AD"),
              style: ElevatedButton.styleFrom(
                backgroundColor: gold.withValues(alpha: 0.1),
                foregroundColor: gold,
                side: BorderSide(color: gold.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TradeAccountsScreen()),
                );
              },
              icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
              label: const Text("MANAGE TRADE ACCOUNTS"),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// "Today at a Glance" stat descriptor (P2P Premium Sprint, 2026-06-21).
class _GlanceStat {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _GlanceStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
}

// --- Phase E2: Ad Boost Bottom Sheet ---

class _AdBoostSheet extends ConsumerStatefulWidget {
  final int adId;
  final Color gold;
  final VoidCallback onBoostSuccess;

  const _AdBoostSheet({
    required this.adId,
    required this.gold,
    required this.onBoostSuccess,
  });

  @override
  ConsumerState<_AdBoostSheet> createState() => _AdBoostSheetState();
}

class _AdBoostSheetState extends ConsumerState<_AdBoostSheet> {
  String? _selectedBoostId;
  bool _isBoosting = false;

  static const _boostOptions = [
    {'id': 'boost_24h', 'label': '24 Hours', 'cost': 15, 'desc': 'Featured at top of marketplace for 1 day'},
    {'id': 'boost_72h', 'label': '3 Days', 'cost': 35, 'desc': 'Featured placement for 72 hours'},
    {'id': 'boost_7d', 'label': '7 Days', 'cost': 80, 'desc': 'Premium featured spot for a full week'},
  ];

  Future<void> _handleBoost() async {
    if (_selectedBoostId == null || _isBoosting) return;

    setState(() => _isBoosting = true);

    final result = await ref
        .read(azmSpendProvider.notifier)
        .boostAd(widget.adId, _selectedBoostId!);

    if (!mounted) return;
    setState(() => _isBoosting = false);

    if (result != null) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Ad boosted for ${result.boostDuration}! (-${result.azmSpent.toInt()} AZM)',
        ),
        backgroundColor: const Color(0xFF02C076),
        behavior: SnackBarBehavior.floating,
      ));
      widget.onBoostSuccess();
    } else {
      final error = ref.read(azmSpendProvider).error ?? 'Failed to boost ad';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error),
        backgroundColor: const Color(0xFFF6465D),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  void initState() {
    super.initState();
    ref.read(azmSpendProvider.notifier).primeIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    final spendState = ref.watch(azmSpendProvider);
    final azmBalance = spendState.options?.currentBalance ?? 0.0;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Title
          Row(
            children: [
              Icon(Icons.rocket_launch_outlined, color: widget.gold, size: 22),
              const SizedBox(width: 10),
              const Text(
                'BOOST AD',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: widget.gold.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${azmBalance.toStringAsFixed(1)} AZM',
                  style: TextStyle(
                    color: widget.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Boosted ads appear at the top of the marketplace so buyers see your offer first.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 20),
          // Boost options
          ..._boostOptions.map((opt) {
            final id = opt['id'] as String;
            final label = opt['label'] as String;
            final cost = opt['cost'] as int;
            final desc = opt['desc'] as String;
            final isSelected = _selectedBoostId == id;
            final canAfford = azmBalance >= cost;

            return GestureDetector(
              onTap: canAfford
                  ? () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedBoostId = isSelected ? null : id);
                    }
                  : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isSelected
                      ? widget.gold.withValues(alpha: 0.08)
                      : Colors.white.withValues(alpha: canAfford ? 0.03 : 0.01),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? widget.gold
                        : canAfford
                            ? Colors.white12
                            : Colors.white.withValues(alpha: 0.04),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              color: canAfford ? Colors.white : Colors.white30,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            desc,
                            style: TextStyle(
                              color: canAfford ? Colors.white38 : Colors.white12,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? widget.gold.withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$cost AZM',
                        style: TextStyle(
                          color: isSelected
                              ? widget.gold
                              : canAfford
                                  ? Colors.white54
                                  : Colors.white24,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          // Confirm button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed:
                  _selectedBoostId != null && !_isBoosting ? _handleBoost : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.gold,
                foregroundColor: Colors.black,
                disabledBackgroundColor: Colors.white10,
                disabledForegroundColor: Colors.white24,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _isBoosting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.black, strokeWidth: 2),
                    )
                  : const Text(
                      'CONFIRM BOOST',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: 1,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// --- ANIMATION HELPERS (unchanged) ---

class PulseCard extends StatefulWidget {
  final Widget child;
  const PulseCard({super.key, required this.child});
  @override
  State<PulseCard> createState() => _PulseCardState();
}

class _PulseCardState extends State<PulseCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);
    _animation = Tween<double>(begin: 1.0, end: 1.02).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _animation, child: widget.child);
  }
}

class TechBackground extends StatelessWidget {
  const TechBackground({super.key});
  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: CustomPaint(
        painter: GridPainter(),
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.02)..strokeWidth = 0.5;
    for (double i = 0; i < size.width; i += 40) { canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint); }
    for (double i = 0; i < size.height; i += 40) { canvas.drawLine(Offset(0, i), Offset(size.width, i), paint); }
  }
  @override bool shouldRepaint(CustomPainter oldDelegate) => false;
}