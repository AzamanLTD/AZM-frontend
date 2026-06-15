import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/trade_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/socket_service.dart';
import 'package:azaman/widgets/chat_interface.dart';
import 'package:azaman/widgets/ai_command_menu.dart';
import 'package:azaman/widgets/ai_dispute_summary.dart';
import 'package:azaman/config.dart';
import 'package:azaman/widgets/azaman_empty_state.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class AdminWarRoomScreen extends ConsumerStatefulWidget {
  const AdminWarRoomScreen({super.key});

  @override
  ConsumerState<AdminWarRoomScreen> createState() => _AdminWarRoomScreenState();
}

class _AdminWarRoomScreenState extends ConsumerState<AdminWarRoomScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  Map<String, dynamic> _stats = {};
  List<dynamic> _disputes = [];
  List<dynamic> _allLiveTrades = [];
  List<dynamic> _kycApplications = [];
  List<dynamic> _vendorApplications = [];

  late AnimationController _radarController;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _fetchGodModeData();
  }

  @override
  void dispose() {
    _radarController.dispose();
    super.dispose();
  }

  Future<void> _fetchGodModeData() async {
    setState(() => _isLoading = true);
    try {
      final auth = ref.read(authProvider);
      final token = auth.token;

      if (token == null) {
        debugPrint("Admin: No auth token available");
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final responses = await Future.wait([
        apiClient.get('/admin/stats'),
        apiClient.get('/admin/disputes'),
        apiClient.get('/admin/trades/live'),
        apiClient.get('/admin/kyc/pending'),
        apiClient.get('/vendor/applications?status=PENDING'),
      ]);

      if (mounted) {
        setState(() {
          if (responses[0].statusCode == 200) {
            _stats = jsonDecode(responses[0].body)['stats'] ?? {};
          }
          if (responses[1].statusCode == 200) {
            _disputes = jsonDecode(responses[1].body)['disputes'] ?? [];
          }
          if (responses[2].statusCode == 200) {
            _allLiveTrades = jsonDecode(responses[2].body)['trades'] ?? [];
          }
          if (responses[3].statusCode == 200) {
            _kycApplications = jsonDecode(responses[3].body)['applications'] ?? [];
          }
          if (responses[4].statusCode == 200) {
            _vendorApplications = jsonDecode(responses[4].body)['applications'] ?? [];
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Admin Fetch Error: $e");
      _showSnack("Network Error: Could not connect to Admin Engine.", isError: true);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resolveDispute(String tradeId, String endpoint, String note) async {
    try {
      final response = await apiClient.post('/admin/disputes/$endpoint', {
        "tradeId": tradeId,
        "adminNotes": note,
      });

      if (response.statusCode == 200) {
        HapticFeedback.heavyImpact();
        _showSnack("Resolution enforced successfully.", isError: false);
        _fetchGodModeData();
      } else {
        final data = jsonDecode(response.body);
        _showSnack(data['message'] ?? "Failed to enforce resolution.", isError: true);
      }
    } catch (e) {
      _showSnack("Network Error during resolution.", isError: true);
    }
  }

  Future<void> _handleKycAction(int userId, bool approve, {String? reason}) async {
    try {
      final endpoint = approve ? 'approve' : 'reject';

      final body = <String, dynamic>{'userId': userId};
      if (!approve && reason != null) body['reason'] = reason;

      final response = await apiClient.post('/admin/kyc/$endpoint', body);

      if (response.statusCode == 200) {
        HapticFeedback.heavyImpact();
        _showSnack(approve ? "KYC Approved. User promoted to Vendor." : "KYC Rejected.", isError: false);
        _fetchGodModeData();
      } else {
        final data = jsonDecode(response.body);
        _showSnack(data['message'] ?? "Action failed.", isError: true);
      }
    } catch (e) {
      _showSnack("Network Error.", isError: true);
    }
  }

  Future<void> _handleVendorApplicationAction(String applicationId, bool approve, {String? reason, String? adminNotes}) async {
    try {
      final body = <String, dynamic>{
        'decision': approve ? 'APPROVED' : 'REJECTED',
      };
      if (!approve && reason != null) body['reason'] = reason;
      if (adminNotes != null) body['adminNotes'] = adminNotes;

      final response = await apiClient.post('/vendor/applications/$applicationId/review', body);

      if (response.statusCode == 200) {
        HapticFeedback.heavyImpact();
        _showSnack(approve ? "Vendor Application Approved. User upgraded to VENDOR." : "Vendor Application Rejected.", isError: false);
        _fetchGodModeData();
      } else {
        final data = jsonDecode(response.body);
        _showSnack(data['message'] ?? "Action failed.", isError: true);
      }
    } catch (e) {
      _showSnack("Network Error.", isError: true);
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    if (!mounted) return;
    final colors = ref.read(themeProvider).colors;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: isError ? colors.danger : colors.success, behavior: SnackBarBehavior.floating),
    );
  }

  // ============================================================
  // ADMIN CHAT INTERCEPTOR
  // ============================================================
  void _openChatInterceptor(Map<String, dynamic> trade) {
    final tradeId = trade['id'].toString();
    // Renamed local from `tradeProvider` to `tp` to avoid shadowing the
    // top-level Riverpod `tradeProvider` symbol.
    final tp = ref.read(tradeProvider);
    final auth = ref.read(authProvider);

    tp.joinTradeRoom(tradeId);

    final List<Map<String, dynamic>> chatMessages = [];
    final rawMessages = trade['messages'] ?? [];
    final String vendorId = (trade['vendorId'] ?? trade['vendor']?['id'] ?? 0).toString();
    final String adminId = auth.user?.id ?? '';

    for (var msg in rawMessages) {
      final String senderId = (msg['senderId'] ?? 0).toString();
      String role;
      if (senderId == adminId || (msg['text'] ?? '').contains('SYSTEM ADMIN')) {
        role = 'admin';
      } else if (senderId == vendorId) {
        role = 'vendor';
      } else {
        role = 'user';
      }

      chatMessages.add({
        "sender": role,
        "text": msg['text'] ?? msg['content'] ?? "",
        "type": msg['imagePath'] != null ? 'image' : 'text',
        "imagePath": msg['imagePath'],
        "time": _formatTime(msg['createdAt']),
        "status": "read",
      });
    }

    final String buyerName = trade['user']?['username'] ?? 'Buyer';
    final String vendorName = trade['vendor']?['username'] ?? 'Vendor';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _AdminChatInterceptScreen(
          tradeId: tradeId,
          buyerName: buyerName,
          vendorName: vendorName,
          initialMessages: chatMessages,
          adminUserId: adminId,
          tradeStatus: trade['status'] ?? 'UNKNOWN',
          onResolve: (String endpoint, String note) {
            _resolveDispute(tradeId, endpoint, note);
          },
        ),
      ),
    ).then((_) {
      tp.leaveTradeRoom(tradeId);
    });
  }

  String _formatTime(String? dateStr) {
    if (dateStr == null) return "";
    try {
      final date = DateTime.parse(dateStr).toLocal();
      String hour = date.hour > 12 ? (date.hour - 12).toString() : (date.hour == 0 ? "12" : date.hour.toString());
      String min = date.minute.toString().padLeft(2, '0');
      String ampm = date.hour >= 12 ? "PM" : "AM";
      return "$hour:$min $ampm";
    } catch (e) {
      return "";
    }
  }

  void _viewProofDialog(String? proofUrl) {
    if (proofUrl == null || proofUrl.isEmpty) {
      _showSnack("No payment proof was uploaded for this trade.", isError: true);
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: InteractiveViewer(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              proofUrl.startsWith('http') ? proofUrl : '${AppConfig.baseUrl}$proofUrl',
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: colors.surface,
          title: Row(
            children: [
              FadeTransition(
                opacity: _radarController,
                child: Icon(HugeIconsSolid.radar01, color: colors.danger, size: 22),
              ),
              const SizedBox(width: 10),
              Text("OVERSIGHT COMMAND",
                  style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            ],
          ),
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 4),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accent.withOpacity(0.12),
                  foregroundColor: colors.accent,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: colors.accent.withOpacity(0.3)),
                  ),
                ),
                icon: const Icon(HugeIconsSolid.sparkles, size: 14),
                label: const Text('AI CMD', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
                onPressed: () => AiCommandMenu.show(context),
              ),
            ),
            IconButton(icon: Icon(HugeIconsSolid.refresh01, color: colors.textTertiary), onPressed: _fetchGodModeData),
          ],
          bottom: TabBar(
            isScrollable: true,
            indicatorColor: colors.accent,
            labelColor: colors.accent,
            unselectedLabelColor: colors.textTertiary,
            labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            tabs: [
              const Tab(text: "LIVE NETWORK"),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("DISPUTES"),
                    if (_disputes.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(color: colors.danger, shape: BoxShape.circle),
                        child: Text("${_disputes.length}",
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("KYC"),
                    if (_kycApplications.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(color: colors.warning, shape: BoxShape.circle),
                        child: Text("${_kycApplications.length}",
                            style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("VENDORS"),
                    if (_vendorApplications.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(color: colors.accent, shape: BoxShape.circle),
                        child: Text("${_vendorApplications.length}",
                            style: TextStyle(color: colors.isDark ? Colors.black : Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        body: _isLoading
            ? Center(child: CircularProgressIndicator(color: colors.accent))
            : TabBarView(
                children: [
                  _buildLiveNetworkTab(colors),
                  _buildDisputesTab(colors),
                  _buildKycTab(colors),
                  _buildVendorsTab(colors),
                ],
              ),
      ),
    );
  }

  // ============================================================
  // TAB 1: LIVE NETWORK
  // ============================================================
  Widget _buildLiveNetworkTab(AzamanColors colors) {
    return RefreshIndicator(
      color: colors.accent,
      backgroundColor: colors.card,
      onRefresh: _fetchGodModeData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(15),
        children: [
          _buildStatsGrid(colors),
          const SizedBox(height: 25),
          Text("GLOBAL TRANSACTION FEED",
              style: TextStyle(color: colors.textTertiary, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          const SizedBox(height: 15),
          if (_allLiveTrades.isEmpty)
            const AzamanEmptyState(icon: HugeIconsSolid.wifi01, title: "No Active Trades", subtitle: "No trades are currently live on the network.", compact: true)
          else
            ..._allLiveTrades.map((trade) => _buildMasterTradeCard(trade, isDispute: false, colors: colors)),
        ],
      ),
    );
  }

  // ============================================================
  // TAB 2: DISPUTES
  // ============================================================
  Widget _buildDisputesTab(AzamanColors colors) {
    return RefreshIndicator(
      color: colors.danger,
      backgroundColor: colors.card,
      onRefresh: _fetchGodModeData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(15),
        children: [
          if (_disputes.isEmpty)
            const AzamanEmptyState(icon: HugeIconsSolid.shield01, title: "Platform is Secure", subtitle: "No active disputes.", compact: true)
          else
            ..._disputes.map((d) => _buildMasterTradeCard(d, isDispute: true, colors: colors)),
        ],
      ),
    );
  }

  // ============================================================
  // TAB 3: KYC APPROVALS
  // ============================================================
  Widget _buildKycTab(AzamanColors colors) {
    return RefreshIndicator(
      color: colors.warning,
      backgroundColor: colors.card,
      onRefresh: _fetchGodModeData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(15),
        children: [
          if (_kycApplications.isEmpty)
            const AzamanEmptyState(icon: HugeIconsSolid.shield01, title: "No Pending KYC", subtitle: "No pending KYC applications.", compact: true)
          else
            ..._kycApplications.map((app) => _buildKycCard(app, colors)),
        ],
      ),
    );
  }

  // ============================================================
  // TAB 4: VENDOR APPLICATIONS
  // ============================================================
  Widget _buildVendorsTab(AzamanColors colors) {
    return RefreshIndicator(
      color: colors.accent,
      backgroundColor: colors.card,
      onRefresh: _fetchGodModeData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(15),
        children: [
          if (_vendorApplications.isEmpty)
            const AzamanEmptyState(icon: HugeIconsSolid.store01, title: "No Pending Applications", subtitle: "No vendor applications awaiting review.", compact: true)
          else
            ..._vendorApplications.map((app) => _buildVendorApplicationCard(app, colors)),
        ],
      ),
    );
  }

  Widget _buildVendorApplicationCard(dynamic application, AzamanColors colors) {
    final user = application['user'] ?? {};
    final String username = user['username'] ?? 'Unknown';
    final String email = user['email'] ?? '';
    final String legalName = application['legalName'] ?? 'N/A';
    final String country = application['country'] ?? 'N/A';
    final String idType = application['idType'] ?? 'N/A';
    final String sourceOfFunds = application['sourceOfFunds'] ?? 'N/A';
    final String volumeEstimate = application['monthlyVolumeEstimate'] ?? 'N/A';
    final String applicationId = application['id'] ?? '';
    final String kycStatus = user['kycStatus'] ?? 'NONE';
    final int tradesCompleted = user['tradesCompleted'] ?? 0;
    final List<dynamic> paymentMethods = application['paymentMethods'] ?? [];
    final String? idFrontUrl = application['idImageFront'];
    final String? selfieUrl = application['selfieWithId'];
    final String? addressProofUrl = application['proofOfAddress'];

    String dateStr = "";
    try {
      final dt = DateTime.parse(application['createdAt']).toLocal();
      dateStr = "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}";
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.accent.withOpacity(0.3)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: colors.accent,
          collapsedIconColor: colors.textTertiary,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: colors.accent.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(HugeIconsSolid.store01, color: colors.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(username, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(legalName, style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                ]),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: colors.accent.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                    child: Text("PENDING", style: TextStyle(color: colors.accent, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 4),
                  Text("$tradesCompleted trades", style: TextStyle(color: colors.textTertiary, fontSize: 10)),
                ],
              ),
            ],
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.background.withOpacity(0.5),
                borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _rowDetail("Email", email, colors),
                  const SizedBox(height: 8),
                  _rowDetail("Country", country, colors),
                  const SizedBox(height: 8),
                  _rowDetail("ID Type", idType, colors),
                  const SizedBox(height: 8),
                  _rowDetail("Source of Funds", sourceOfFunds, colors),
                  const SizedBox(height: 8),
                  _rowDetail("Monthly Volume", volumeEstimate, colors),
                  const SizedBox(height: 8),
                  _rowDetail("KYC Status", kycStatus, colors),
                  const SizedBox(height: 8),
                  _rowDetail("Applied", dateStr, colors),
                  const SizedBox(height: 8),
                  _rowDetail("Payment Methods", "${paymentMethods.length} added", colors),

                  Divider(color: colors.divider, height: 25),

                  // Document previews
                  Text("DOCUMENTS", style: TextStyle(color: colors.textTertiary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _buildDocPreview(colors, "ID Front", idFrontUrl)),
                      const SizedBox(width: 10),
                      Expanded(child: _buildDocPreview(colors, "Selfie", selfieUrl)),
                      const SizedBox(width: 10),
                      Expanded(child: _buildDocPreview(colors, "Address", addressProofUrl)),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.danger.withOpacity(0.15),
                            foregroundColor: colors.danger,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(HugeIconsSolid.cancel01, size: 18),
                          label: const Text("Reject", style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: () => _showVendorRejectDialog(applicationId, username, colors),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.success.withOpacity(0.15),
                            foregroundColor: colors.success,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(HugeIconsSolid.checkmarkCircle01, size: 18),
                          label: const Text("Approve", style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: () => _showVendorApproveDialog(applicationId, username, colors),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showVendorApproveDialog(String applicationId, String username, AzamanColors colors) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.card,
        title: Text("Approve $username as Vendor?", style: TextStyle(color: colors.textPrimary)),
        content: Text(
          "This will upgrade the user's role to VENDOR, revoke existing sessions, and send a confirmation email.",
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Cancel", style: TextStyle(color: colors.textTertiary))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: colors.success, foregroundColor: Colors.white, elevation: 0),
            onPressed: () {
              Navigator.pop(ctx);
              _handleVendorApplicationAction(applicationId, true);
            },
            child: const Text("Approve", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showVendorRejectDialog(String applicationId, String username, AzamanColors colors) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.card,
        title: Text("Reject $username?", style: TextStyle(color: colors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Provide a reason (optional):", style: TextStyle(color: colors.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 3,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: "e.g. Blurry ID, insufficient funds proof...",
                hintStyle: TextStyle(color: colors.textTertiary, fontSize: 12),
                filled: true,
                fillColor: colors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Cancel", style: TextStyle(color: colors.textTertiary))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: colors.danger, foregroundColor: Colors.white, elevation: 0),
            onPressed: () {
              Navigator.pop(ctx);
              _handleVendorApplicationAction(applicationId, false, reason: reasonController.text.isNotEmpty ? reasonController.text : null);
            },
            child: const Text("Reject", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildKycCard(dynamic application, AzamanColors colors) {
    final String username = application['username'] ?? 'Unknown';
    final String email = application['email'] ?? '';
    final String legalName = application['legalName'] ?? 'N/A';
    final String idType = application['idType'] ?? 'N/A';
    final String idNumber = application['idNumber'] ?? 'N/A';
    final String? frontUrl = application['idImageFront'];
    final String? backUrl = application['idImageBack'];
    final int userId = application['id'] ?? 0;

    String dateStr = "";
    try {
      final dt = DateTime.parse(application['createdAt']).toLocal();
      dateStr = "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}";
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.warning.withOpacity(0.3)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: colors.warning,
          collapsedIconColor: colors.textTertiary,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: colors.warning.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(HugeIconsSolid.userSearch01, color: colors.warning, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(username, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(legalName, style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: colors.warning.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                child: Text("PENDING", style: TextStyle(color: colors.warning, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.background.withOpacity(0.5),
                borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _rowDetail("Email", email, colors),
                  const SizedBox(height: 8),
                  _rowDetail("ID Type", idType, colors),
                  const SizedBox(height: 8),
                  _rowDetail("ID Number", idNumber, colors),
                  const SizedBox(height: 8),
                  _rowDetail("Applied", dateStr, colors),

                  Divider(color: colors.divider, height: 25),

                  // Document previews
                  Text("DOCUMENTS", style: TextStyle(color: colors.textTertiary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _buildDocPreview(colors, "Front", frontUrl)),
                      const SizedBox(width: 10),
                      Expanded(child: _buildDocPreview(colors, "Back", backUrl)),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.danger.withOpacity(0.15),
                            foregroundColor: colors.danger,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(HugeIconsSolid.cancel01, size: 18),
                          label: const Text("Reject", style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: () => _showRejectDialog(userId, username, colors),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.success.withOpacity(0.15),
                            foregroundColor: colors.success,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(HugeIconsSolid.checkmarkCircle01, size: 18),
                          label: const Text("Approve", style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: () => _showApproveDialog(userId, username, colors),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocPreview(AzamanColors colors, String label, String? imageUrl) {
    return GestureDetector(
      onTap: () {
        if (imageUrl == null || imageUrl.isEmpty) {
          _showSnack("No $label image uploaded.", isError: true);
          return;
        }
        final fullUrl = imageUrl.startsWith('http') ? imageUrl : '${AppConfig.baseUrl}$imageUrl';
        showDialog(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: Colors.transparent,
            child: InteractiveViewer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(fullUrl, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    padding: const EdgeInsets.all(40),
                    color: colors.card,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(HugeIconsSolid.image01, color: colors.danger, size: 48),
                      const SizedBox(height: 12),
                      Text("Failed to load image", style: TextStyle(color: colors.textSecondary)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: imageUrl != null ? colors.accent.withOpacity(0.3) : colors.divider),
        ),
        child: imageUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      imageUrl.startsWith('http') ? imageUrl : '${AppConfig.baseUrl}$imageUrl',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Center(child: Icon(HugeIconsSolid.image01, color: colors.textTertiary)),
                    ),
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        color: colors.background.withOpacity(0.7),
                        child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: colors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(HugeIconsSolid.image01, color: colors.textTertiary, size: 24),
                  const SizedBox(height: 4),
                  Text("No $label", style: TextStyle(color: colors.textTertiary, fontSize: 10)),
                ],
              ),
      ),
    );
  }

  void _showApproveDialog(int userId, String username, AzamanColors colors) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.card,
        title: Text("Approve $username?", style: TextStyle(color: colors.textPrimary)),
        content: Text(
          "This will verify the user's identity and promote them to Vendor status.",
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Cancel", style: TextStyle(color: colors.textTertiary))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: colors.success, foregroundColor: Colors.white, elevation: 0),
            onPressed: () {
              Navigator.pop(ctx);
              _handleKycAction(userId, true);
            },
            child: const Text("Approve", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showRejectDialog(int userId, String username, AzamanColors colors) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.card,
        title: Text("Reject $username?", style: TextStyle(color: colors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Provide a reason (optional):", style: TextStyle(color: colors.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 3,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: "e.g. Blurry ID photo, name mismatch...",
                hintStyle: TextStyle(color: colors.textTertiary, fontSize: 12),
                filled: true,
                fillColor: colors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Cancel", style: TextStyle(color: colors.textTertiary))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: colors.danger, foregroundColor: Colors.white, elevation: 0),
            onPressed: () {
              Navigator.pop(ctx);
              _handleKycAction(userId, false, reason: reasonController.text.isNotEmpty ? reasonController.text : null);
            },
            child: const Text("Reject", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SHARED WIDGETS
  // ============================================================
  Widget _buildStatsGrid(AzamanColors colors) {
    return Row(
      children: [
        Expanded(child: _statCard("Total Users", _stats['totalUsers']?.toString() ?? "0", HugeIconsSolid.userGroup, colors.accent, colors)),
        const SizedBox(width: 10),
        Expanded(child: _statCard("Vol (GHS)", "${_stats['totalFiatVolume'] ?? 0}", HugeIconsSolid.presentationBarChart01, colors.warning, colors)),
        const SizedBox(width: 10),
        Expanded(child: _statCard("Profit", "${_stats['totalAdminProfit'] ?? 0}", HugeIconsSolid.bank, colors.success, colors)),
      ],
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color highlight, AzamanColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: highlight.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: highlight.withOpacity(0.8), size: 20),
          const SizedBox(height: 10),
          Text(value, style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text(title, style: TextStyle(color: colors.textTertiary, fontSize: 9), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildMasterTradeCard(Map<String, dynamic> trade, {required bool isDispute, required AzamanColors colors}) {
    Color cardColor = isDispute ? colors.danger : colors.accent;
    String status = trade['status'] ?? "UNKNOWN";

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardColor.withOpacity(0.3)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: cardColor,
          collapsedIconColor: colors.textTertiary,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: cardColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                child: Text("Trade #${trade['id']}", style: TextStyle(color: cardColor, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              Text("${trade['amountFiat']} GHS", style: TextStyle(color: colors.warning, fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              children: [
                Icon(HugeIconsSolid.circle, size: 8, color: _getStatusColor(status, colors)),
                const SizedBox(width: 5),
                Text(status, style: TextStyle(color: _getStatusColor(status, colors), fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: colors.background.withOpacity(0.5),
                borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _rowDetail("Buyer", trade['user']?['username'] ?? "Unknown", colors),
                  const SizedBox(height: 8),
                  _rowDetail("Vendor", trade['vendor']?['username'] ?? "Unknown", colors),
                  const SizedBox(height: 8),
                  _rowDetail("Method", trade['paymentMethod'] ?? "N/A", colors),
                  const SizedBox(height: 8),
                  _rowDetail("USD Escrow", "\$${trade['amountCrypto']}", colors),
                  Divider(color: colors.divider, height: 25),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _actionButton(HugeIconsSolid.receiptDollar, "Receipt", () => _viewProofDialog(trade['proofUrl']), colors),
                      _actionButton(HugeIconsSolid.chat01, "Intercept", () => _openChatInterceptor(trade), colors),
                    ],
                  ),

                  if (isDispute) ...[
                    AiDisputeSummary(
                      similarType: 'disputed trades',
                      count: _disputes.length,
                      timeframe: 'active',
                      recommendedAction: 'Review chat logs before enforcing',
                      confidence: 94,
                      historicalResolutions: [
                        {'label': 'Buyer wins — proof provided', 'outcome': 'resolved', 'detail': '2 days ago'},
                        {'label': 'Vendor wins — no payment proof', 'outcome': 'vendor win', 'detail': '5 days ago'},
                        {'label': 'Escrow split — partial delivery', 'outcome': 'split', 'detail': '1 week ago'},
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text("ENFORCE RESOLUTION", style: TextStyle(color: colors.danger, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: colors.danger.withOpacity(0.2), foregroundColor: colors.danger, elevation: 0),
                            onPressed: () => _actionDialog(trade, "Vendor", colors),
                            child: const Text("Rule for Vendor"),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: colors.success.withOpacity(0.2), foregroundColor: colors.success, elevation: 0),
                            onPressed: () => _actionDialog(trade, "Buyer", colors),
                            child: const Text("Rule for Buyer"),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status, AzamanColors colors) {
    if (status == 'COMPLETED') return colors.success;
    if (status == 'PAID') return colors.warning;
    if (status == 'DISPUTED') return colors.danger;
    if (status == 'PENDING_PAYMENT') return colors.accent;
    return colors.textTertiary;
  }

  Widget _actionButton(IconData icon, String label, VoidCallback onTap, AzamanColors colors) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(backgroundColor: colors.divider, radius: 20, child: Icon(icon, color: colors.textPrimary, size: 18)),
          const SizedBox(height: 5),
          Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _rowDetail(String label, String value, AzamanColors colors) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: colors.textTertiary, fontSize: 12)),
        Text(value, style: TextStyle(color: colors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  void _actionDialog(Map<String, dynamic> trade, String winner, AzamanColors colors) {
    bool isVendorWin = winner == "Vendor";
    final reasonController = TextEditingController();
    final splitController = TextEditingController(text: '50');
    bool isSplit = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: colors.card,
          title: Text("Resolve: Trade #${trade['id']}", style: TextStyle(color: colors.textPrimary, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isVendorWin
                    ? "Ruling: VENDOR WINS — escrow returned to vendor."
                    : "Ruling: BUYER WINS — escrow released to buyer.",
                style: TextStyle(color: isVendorWin ? colors.danger : colors.success, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              // Split toggle
              Row(
                children: [
                  Expanded(
                    child: Text("Or split escrow?", style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                  ),
                  Switch(
                    value: isSplit,
                    activeColor: colors.accent,
                    onChanged: (v) => setDialogState(() => isSplit = v),
                  ),
                ],
              ),
              if (isSplit) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: splitController,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: "Buyer gets X% (e.g. 60)",
                    hintStyle: TextStyle(color: colors.textTertiary, fontSize: 12),
                    suffixText: "% to buyer",
                    suffixStyle: TextStyle(color: colors.textTertiary, fontSize: 11),
                    filled: true,
                    fillColor: colors.background,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLines: 2,
                style: TextStyle(color: colors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: "Reason (required, min 10 chars)...",
                  hintStyle: TextStyle(color: colors.textTertiary, fontSize: 12),
                  filled: true,
                  fillColor: colors.background,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Cancel", style: TextStyle(color: colors.textTertiary))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: isVendorWin ? colors.danger : colors.success, elevation: 0),
              onPressed: () {
                final reason = reasonController.text.trim();
                if (reason.length < 10) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: const Text("Reason must be at least 10 characters."), backgroundColor: colors.danger),
                  );
                  return;
                }
                Navigator.pop(ctx);
                _resolveDisputeStructured(
                  trade['id'].toString(),
                  isSplit ? 'SPLIT' : (isVendorWin ? 'VENDOR_WINS' : 'BUYER_WINS'),
                  reason,
                  isSplit ? (int.tryParse(splitController.text) ?? 50) : null,
                );
              },
              child: Text(isSplit ? "Split & Resolve" : "Confirm", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resolveDisputeStructured(String tradeId, String ruling, String reason, int? buyerPercent) async {
    try {
      final body = <String, dynamic>{
        'ruling': ruling,
        'reason': reason,
      };
      if (buyerPercent != null) body['buyerPercent'] = buyerPercent;

      final response = await apiClient.post('/admin/disputes/$tradeId/resolve', body);

      if (response.statusCode == 200) {
        HapticFeedback.heavyImpact();
        _showSnack("Dispute resolved ($ruling).", isError: false);
        _fetchGodModeData();
      } else {
        final data = jsonDecode(response.body);
        _showSnack(data['message'] ?? "Resolution failed.", isError: true);
      }
    } catch (e) {
      _showSnack("Network Error during resolution.", isError: true);
    }
  }
}

// ============================================================
// ADMIN CHAT INTERCEPT SCREEN
// ============================================================
class _AdminChatInterceptScreen extends ConsumerStatefulWidget {
  final String tradeId;
  final String buyerName;
  final String vendorName;
  final List<Map<String, dynamic>> initialMessages;
  final String adminUserId;
  final String tradeStatus;
  final void Function(String endpoint, String note)? onResolve;

  const _AdminChatInterceptScreen({
    required this.tradeId,
    required this.buyerName,
    required this.vendorName,
    required this.initialMessages,
    required this.adminUserId,
    this.tradeStatus = 'UNKNOWN',
    this.onResolve,
  });

  @override
  ConsumerState<_AdminChatInterceptScreen> createState() => _AdminChatInterceptScreenState();
}

class _AdminChatInterceptScreenState extends ConsumerState<_AdminChatInterceptScreen> {
  late List<Map<String, dynamic>> _messages;

  @override
  void initState() {
    super.initState();
    _messages = List.from(widget.initialMessages);

    // Renamed local from `tradeProvider` to `tp` to avoid shadowing the
    // top-level Riverpod `tradeProvider` symbol.
    final tp = ref.read(tradeProvider);
    SocketService.instance.rawSocket?.on('new_trade_message', _onNewMessage);
  }

  void _onNewMessage(dynamic data) {
    if (mounted) {
      setState(() {
        _messages.add({
          "sender": data['sender'] == 'buyer' ? 'user' : (data['sender'] ?? 'vendor'),
          "text": data['text'] ?? data['content'] ?? "",
          "type": data['type'] ?? "text",
          "imagePath": data['imagePath'],
          "time": "Just now",
          "status": "read",
        });
      });
    }
  }

  void _showGodModeConfirm(BuildContext context, AzamanColors colors, {required bool isBuyerWin}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(HugeIconsSolid.alertCircle, color: isBuyerWin ? colors.success : colors.danger, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isBuyerWin ? "Force Release to Buyer?" : "Refund to Vendor?",
                style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          isBuyerWin
              ? "This will force-release the escrowed assets and credit AZM to the buyer. This action is IRREVERSIBLE."
              : "This will cancel the trade and return the escrowed USDT to the vendor. This action is IRREVERSIBLE.",
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Cancel", style: TextStyle(color: colors.textTertiary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isBuyerWin ? colors.success : colors.danger,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              widget.onResolve?.call(
                isBuyerWin ? 'force-release' : 'force-cancel',
                "Admin resolved via God Mode intercept.",
              );
              Navigator.pop(context); // Close intercept screen
            },
            child: Text("Confirm ${isBuyerWin ? 'Release' : 'Refund'}",
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    final tp = ref.read(tradeProvider);
    SocketService.instance.rawSocket?.off('new_trade_message', _onNewMessage);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tp = ref.read(tradeProvider);
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("INTERCEPT: Trade #${widget.tradeId}",
                style: TextStyle(color: colors.danger, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1)),
            Text("${widget.buyerName} \u2194 ${widget.vendorName}",
                style: TextStyle(color: colors.textTertiary, fontSize: 11)),
          ],
        ),
        leading: IconButton(
          icon: Icon(HugeIconsSolid.arrowLeft01, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: colors.danger.withOpacity(0.1),
              border: Border(bottom: BorderSide(color: colors.danger.withOpacity(0.3))),
            ),
            child: Row(
              children: [
                Icon(HugeIconsSolid.shield01, color: colors.danger, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "GOD MODE \u2014 Messages appear as SYSTEM ADMIN to both parties.",
                    style: TextStyle(color: colors.danger, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ChatInterface(
              socket: SocketService.instance.rawSocket!,
              tradeId: widget.tradeId,
              myRole: 'admin',
              messages: _messages,
              isTyping: false,
              onSendMessage: (text, imagePath) {
                if (text.isNotEmpty) {
                  setState(() {
                    _messages.add({
                      "sender": "admin",
                      "text": text,
                      "type": "text",
                      "status": "sent",
                      "time": "Just now",
                    });
                  });
                  SocketService.instance.emit('send_trade_message', {
                    'tradeId': widget.tradeId,
                    'text': text,
                    'senderId': 'admin',
                    'adminUserId': widget.adminUserId,
                    'type': 'text',
                  });
                }
              },
            ),
          ),
          // GOD MODE RESOLUTION BUTTONS
          if (widget.tradeStatus == 'DISPUTED' && widget.onResolve != null)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(top: BorderSide(color: colors.divider)),
              ),
              child: Column(
                children: [
                  Text("GOD MODE RESOLUTION",
                      style: TextStyle(color: colors.danger, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 56,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.success,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            icon: const Icon(HugeIconsSolid.judge, size: 22),
                            label: const Text("FORCE RELEASE\nTO BUYER",
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                            onPressed: () => _showGodModeConfirm(context, colors, isBuyerWin: true),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 56,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.danger,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            icon: const Icon(HugeIconsSolid.undo, size: 22),
                            label: const Text("REFUND\nTO VENDOR",
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                            onPressed: () => _showGodModeConfirm(context, colors, isBuyerWin: false),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
