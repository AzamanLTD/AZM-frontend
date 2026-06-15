import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/trade_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/socket_service.dart';
import 'package:azaman/config.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class VendorSettingsScreen extends ConsumerStatefulWidget {
  final int pendingTradeCount;

  const VendorSettingsScreen({super.key, this.pendingTradeCount = 0});

  @override
  ConsumerState<VendorSettingsScreen> createState() => _VendorSettingsScreenState();
}

class _VendorSettingsScreenState extends ConsumerState<VendorSettingsScreen>
    with TickerProviderStateMixin {
  late bool _isActive;
  late TabController _tabController;

  bool _isLoadingTradeAccounts = true;
  bool _isLoadingPayouts = true;
  List<Map<String, dynamic>> _tradeAccounts = [];
  List<Map<String, dynamic>> _payoutDestinations = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final tp = ref.read(tradeProvider);
    _isActive = tp.isMerchantOnline;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchTradeAccounts();
      _fetchPayoutDestinations();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onToggleChanged(bool val) {
    HapticFeedback.mediumImpact();
    final tp = ref.read(tradeProvider);

    if (!val && widget.pendingTradeCount > 0) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          final colors = ref.read(themeProvider).colors;
          return AlertDialog(
            backgroundColor: colors.card,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(HugeIconsSolid.alertCircle,
                    color: colors.warning, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Active Trades Detected",
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16),
                  ),
                ),
              ],
            ),
            content: Text(
              "You have ${widget.pendingTradeCount} active trade(s). Allow buyers to finish paying, or auto-cancel unpaid trades?",
              style: TextStyle(
                  color: colors.textSecondary, fontSize: 13, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text("Keep Active",
                    style:
                        TextStyle(color: colors.textTertiary, fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.warning,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() => _isActive = false);
                  tp.toggleMerchantStatus();
                  SocketService.instance.emit('toggle_online', {'isOnline': false});
                },
                child: const Text("Go Offline",
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      );
      return;
    }

    setState(() => _isActive = val);
    tp.toggleMerchantStatus();
    SocketService.instance.emit('toggle_online', {'isOnline': val});
  }

  Future<void> _fetchTradeAccounts() async {
    setState(() => _isLoadingTradeAccounts = true);
    try {
      final res = await apiClient.get('/wallet/saved');
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        final all = List<Map<String, dynamic>>.from(data['wallets'] ?? []);
        final cryptoNetworks = ['BINANCE_ID', 'TRC20', 'ERC20_BEP20', 'Crypto Wallet'];
        _tradeAccounts = all.where((w) {
          final prov = (w['provider'] ?? w['network'] ?? '').toString();
          return !cryptoNetworks.any((c) => prov.contains(c));
        }).toList();
      }
    } catch (e) {
      debugPrint('fetchTradeAccounts error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingTradeAccounts = false);
    }
  }

  Future<void> _fetchPayoutDestinations() async {
    setState(() => _isLoadingPayouts = true);
    try {
      final res = await apiClient.get('/wallet/saved');
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        final all = List<Map<String, dynamic>>.from(data['wallets'] ?? []);
        final cryptoNetworks = ['BINANCE_ID', 'TRC20', 'ERC20_BEP20', 'Crypto Wallet'];
        _payoutDestinations = all.where((w) {
          final prov = (w['provider'] ?? w['network'] ?? w['type'] ?? '').toString();
          return cryptoNetworks.any((c) => prov.contains(c));
        }).toList();
      }
    } catch (e) {
      debugPrint('fetchPayoutDestinations error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingPayouts = false);
    }
  }

  void _showAddTradeAccountSheet() {
    final colors = ref.read(themeProvider).colors;
    final picker = ImagePicker();

    String selectedMethod = 'CashApp';
    final methodCtrl = TextEditingController();
    final accountNameCtrl = TextEditingController();
    final detailCtrl = TextEditingController();
    final secondaryCtrl = TextEditingController();
    XFile? verificationScreenshot;
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final isBank = selectedMethod == 'Bank Transfer';
          final isCashApp = selectedMethod == 'CashApp';
          final isPayPal = selectedMethod == 'PayPal';
          final isVenmo = selectedMethod == 'Venmo';
          final isZelle = selectedMethod == 'Zelle';

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 18,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.divider,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Add Trade Account',
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedMethod,
                    decoration: InputDecoration(
                      labelText: 'Payment Method',
                      labelStyle: TextStyle(color: colors.textTertiary),
                      filled: true,
                      fillColor: colors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colors.divider),
                      ),
                    ),
                    dropdownColor: colors.surface,
                    style: TextStyle(color: colors.textPrimary),
                    items: ['CashApp', 'Zelle', 'Venmo', 'PayPal',
                        'Apple Pay', 'Bank Transfer']
                        .map((m) => DropdownMenuItem(
                            value: m, child: Text(m)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setSheet(() => selectedMethod = val);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  _buildField(
                      controller: methodCtrl,
                      label: 'Account Nickname / Label',
                      colors: colors),
                  const SizedBox(height: 10),
                  if (isCashApp) ...[
                    _buildField(
                        controller: accountNameCtrl,
                        label: 'CashApp Account Name',
                        colors: colors),
                    const SizedBox(height: 10),
                    _buildField(
                        controller: detailCtrl,
                        label: '\$Cashtag',
                        colors: colors),
                    const SizedBox(height: 10),
                    _buildField(
                        controller: secondaryCtrl,
                        label: 'Associated Email or Phone (Optional)',
                        colors: colors,
                        required: false),
                  ] else if (isBank) ...[
                    _buildField(
                        controller: accountNameCtrl,
                        label: 'Bank Name (e.g. Chase, BOA)',
                        colors: colors),
                    const SizedBox(height: 10),
                    _buildField(
                        controller: methodCtrl,
                        label: 'Account Holder Full Name',
                        colors: colors),
                    const SizedBox(height: 10),
                    _buildField(
                        controller: detailCtrl,
                        label: 'Account Number',
                        colors: colors,
                        keyboardType: TextInputType.number),
                    const SizedBox(height: 10),
                    _buildField(
                        controller: secondaryCtrl,
                        label: 'Routing Number',
                        colors: colors,
                        keyboardType: TextInputType.number),
                  ] else if (isPayPal) ...[
                    _buildField(
                        controller: accountNameCtrl,
                        label: 'Registered Name',
                        colors: colors),
                    const SizedBox(height: 10),
                    _buildField(
                        controller: detailCtrl,
                        label: 'PayPal Email Address',
                        colors: colors),
                    const SizedBox(height: 10),
                    _buildField(
                        controller: secondaryCtrl,
                        label: 'PayPal.me Link (Optional)',
                        colors: colors,
                        required: false),
                  ] else if (isVenmo) ...[
                    _buildField(
                        controller: accountNameCtrl,
                        label: 'Registered Full Name',
                        colors: colors),
                    const SizedBox(height: 10),
                    _buildField(
                        controller: detailCtrl,
                        label: 'Venmo Username / Phone / Email',
                        colors: colors),
                  ] else if (isZelle) ...[
                    _buildField(
                        controller: accountNameCtrl,
                        label: 'Registered Full Name',
                        colors: colors),
                    const SizedBox(height: 10),
                    _buildField(
                        controller: detailCtrl,
                        label: 'Zelle Email or Phone Number',
                        colors: colors),
                  ] else ...[
                    _buildField(
                        controller: accountNameCtrl,
                        label: 'Registered Full Name',
                        colors: colors),
                    const SizedBox(height: 10),
                    _buildField(
                        controller: detailCtrl,
                        label: 'Username, Email, or Phone',
                        colors: colors),
                  ],
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () async {
                      HapticFeedback.selectionClick();
                      final picked = await picker.pickImage(
                          source: ImageSource.gallery, imageQuality: 70);
                      if (picked != null) {
                        setSheet(() => verificationScreenshot = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 16),
                      decoration: BoxDecoration(
                        color: verificationScreenshot != null
                            ? colors.success.withOpacity(0.1)
                            : colors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: verificationScreenshot != null
                              ? colors.success
                              : colors.divider,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            verificationScreenshot != null
                                ? HugeIconsSolid.checkmarkCircle01
                                : HugeIconsSolid.camera01,
                            color: verificationScreenshot != null
                                ? colors.success
                                : colors.textTertiary,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              verificationScreenshot != null
                                  ? 'Screenshot selected'
                                  : 'Upload Verification Screenshot *',
                              style: TextStyle(
                                color: verificationScreenshot != null
                                    ? colors.success
                                    : colors.textTertiary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor:
                          colors.isDark ? Colors.black : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      if (verificationScreenshot == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Verification screenshot required')),
                        );
                        return;
                      }
                      Navigator.pop(ctx);
                      await _saveTradeAccount(
                        method: selectedMethod,
                        label: methodCtrl.text.trim(),
                        accountName: accountNameCtrl.text.trim(),
                        primaryDetail: detailCtrl.text.trim(),
                        secondaryDetail: secondaryCtrl.text.trim(),
                        screenshot: verificationScreenshot!,
                      );
                    },
                    child: const Text('SAVE ACCOUNT',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _saveTradeAccount({
    required String method,
    required String label,
    required String accountName,
    required String primaryDetail,
    String secondaryDetail = '',
    required XFile screenshot,
  }) async {
    try {
      final uri = Uri.parse('${AppConfig.apiUrl}/wallet/saved');
      final req = http.MultipartRequest('POST', uri)
        ..files.add(
            await http.MultipartFile.fromPath('file', screenshot.path))
        ..fields['type'] = method
        ..fields['label'] = label.isNotEmpty ? label : method
        ..fields['address'] = primaryDetail
        ..fields['accountName'] = accountName
        ..fields['secondaryDetail'] = secondaryDetail;

      final responseData = await apiClient.multipart('/wallet/saved', req);
      final ok = responseData.statusCode == 200 || responseData.statusCode == 201;

      if (mounted) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok
                ? 'Trade account saved'
                : 'Failed to save — ${responseData.body}'),
            backgroundColor:
                ok ? colorsSuccess(context) : colorsDanger(context),
          ),
        );
        if (ok) _fetchTradeAccounts();
      }
    } catch (e) {
      debugPrint('saveTradeAccount error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Network error: $e'),
              backgroundColor: colorsDanger(context)),
        );
      }
    }
  }

  void _showAddPayoutSheet() {
    final colors = ref.read(themeProvider).colors;

    bool isWeb3 = false;
    String selectedProvider = 'MTN MoMo';
    final nicknameCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 18,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.divider,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Add Payout Destination',
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  _buildField(
                      controller: nicknameCtrl,
                      label: 'Nickname (e.g. "My Binance", "MTN Wallet")',
                      colors: colors),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setSheet(() => isWeb3 = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: !isWeb3
                                  ? colors.accent.withOpacity(0.15)
                                  : colors.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: !isWeb3
                                    ? colors.accent
                                    : colors.divider,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(HugeIconsSolid.smartPhone01,
                                    size: 16,
                                    color: !isWeb3
                                        ? colors.accent
                                        : colors.textTertiary),
                                const SizedBox(width: 6),
                                Text('Local Fiat/MoMo',
                                    style: TextStyle(
                                      color: !isWeb3
                                          ? colors.accent
                                          : colors.textTertiary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    )),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setSheet(() => isWeb3 = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: isWeb3
                                  ? colors.accent.withOpacity(0.15)
                                  : colors.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isWeb3
                                    ? colors.accent
                                    : colors.divider,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(HugeIconsSolid.internet,
                                    size: 16,
                                    color: isWeb3
                                        ? colors.accent
                                        : colors.textTertiary),
                                const SizedBox(width: 6),
                                Text('External Web3 Wallet',
                                    style: TextStyle(
                                      color: isWeb3
                                          ? colors.accent
                                          : colors.textTertiary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    )),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (isWeb3) ...[
                    _buildField(
                        controller: addressCtrl,
                        label: 'Wallet Address (TRC20 / ERC20 / BEP20)',
                        colors: colors),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: 'TRC20',
                      decoration: InputDecoration(
                        labelText: 'Network',
                        labelStyle: TextStyle(color: colors.textTertiary),
                        filled: true,
                        fillColor: colors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: colors.divider),
                        ),
                      ),
                      dropdownColor: colors.surface,
                      style: TextStyle(color: colors.textPrimary),
                      items: ['TRC20', 'ERC20', 'BEP20', 'BINANCE_ID']
                          .map((n) =>
                              DropdownMenuItem(value: n, child: Text(n)))
                          .toList(),
                      onChanged: (_) {},
                    ),
                  ] else ...[
                    _buildField(
                        controller: phoneCtrl,
                        label: 'Phone Number (e.g. 024XXXXXXX)',
                        colors: colors,
                        keyboardType: TextInputType.number),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedProvider,
                      decoration: InputDecoration(
                        labelText: 'Provider',
                        labelStyle: TextStyle(color: colors.textTertiary),
                        filled: true,
                        fillColor: colors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: colors.divider),
                        ),
                      ),
                      dropdownColor: colors.surface,
                      style: TextStyle(color: colors.textPrimary),
                      items: ['MTN MoMo', 'Telecel Cash', 'AirtelTigo Money',
                          'Bank Transfer']
                          .map((p) =>
                              DropdownMenuItem(value: p, child: Text(p)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setSheet(() => selectedProvider = val);
                        }
                      },
                    ),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor:
                          colors.isDark ? Colors.black : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      Navigator.pop(ctx);
                      await _savePayoutDestination(
                        nickname: nicknameCtrl.text.trim(),
                        isWeb3: isWeb3,
                        address: addressCtrl.text.trim(),
                        phone: phoneCtrl.text.trim(),
                        provider: selectedProvider,
                      );
                    },
                    child: const Text('SAVE DESTINATION',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _savePayoutDestination({
    required String nickname,
    required bool isWeb3,
    String address = '',
    String phone = '',
    String provider = 'MTN MoMo',
  }) async {
    try {
      final res = await apiClient.post('/wallet/saved', {
        if (isWeb3) ...{
          'type': 'Crypto Wallet',
          'label': nickname.isNotEmpty ? nickname : 'Web3 Wallet',
          'address': address,
          'network': provider,
        } else ...{
          'type': provider,
          'label': nickname.isNotEmpty ? nickname : provider,
          'address': phone,
        }
      });

      final ok = res.statusCode == 200 || res.statusCode == 201;
      if (mounted) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(ok ? 'Payout destination saved' : 'Failed to save'),
            backgroundColor:
                ok ? colorsSuccess(context) : colorsDanger(context),
          ),
        );
        if (ok) _fetchPayoutDestinations();
      }
    } catch (e) {
      debugPrint('savePayoutDestination error: $e');
    }
  }

  Future<void> _deleteAccount(int id) async {
    try {
      await apiClient.delete('/wallet/saved/$id');
      HapticFeedback.lightImpact();
      _fetchTradeAccounts();
    } catch (_) {}
  }

  Future<void> _deletePayout(int id) async {
    try {
      await apiClient.delete('/wallet/saved/$id');
      HapticFeedback.lightImpact();
      _fetchPayoutDestinations();
    } catch (_) {}
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required AzamanColors colors,
    TextInputType? keyboardType,
    bool required = true,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: TextStyle(color: colors.textPrimary),
      validator: required
          ? (v) =>
              (v == null || v.trim().isEmpty) ? 'This field is required' : null
          : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: colors.textTertiary),
        filled: true,
        fillColor: colors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.accent),
        ),
      ),
    );
  }

  // Public-ish helpers retained with their original signatures so callers
  // do not need to be touched. The BuildContext parameter is now unused
  // — kept only to preserve the signature; ref is sourced from the
  // ConsumerState's built-in `ref` member.
  Color colorsSuccess(BuildContext context) =>
      ref.read(themeProvider).colors.success;
  Color colorsDanger(BuildContext context) =>
      ref.read(themeProvider).colors.danger;

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    const Color gold = Color(0xFFD4AF37);
    const Color green = Color(0xFF02C076);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(HugeIconsSolid.arrowLeft01, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Vendor Settings",
          style: TextStyle(
              color: colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: gold.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isActive ? "NODE: ACTIVE" : "NODE: OFFLINE",
                      style: TextStyle(
                        color: _isActive ? green : colors.textTertiary,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isActive
                          ? "You are visible to buyers."
                          : "New requests will not be routed.",
                      style: TextStyle(
                          color: colors.textTertiary, fontSize: 11),
                    ),
                  ],
                ),
                Transform.scale(
                  scale: 1.1,
                  child: Switch(
                    value: _isActive,
                    activeColor: green,
                    inactiveTrackColor: Colors.white10,
                    onChanged: _onToggleChanged,
                  ),
                ),
              ],
            ),
          ),
          if (widget.pendingTradeCount > 0)
            Container(
              margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.warning.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.warning.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(HugeIconsSolid.exchange01, color: colors.warning, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "${widget.pendingTradeCount} active trade(s) in progress",
                      style: TextStyle(
                          color: colors.warning,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          TabBar(
            controller: _tabController,
            indicatorColor: gold,
            labelColor: gold,
            unselectedLabelColor: colors.textTertiary,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(text: 'Fiat Trade Accounts'),
              Tab(text: 'Payout Destinations'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTradeAccountsTab(colors),
                _buildPayoutsTab(colors),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) {
          final isTab1 = _tabController.index == 0;
          return FloatingActionButton(
            backgroundColor: gold,
            foregroundColor: Colors.black,
            onPressed: () {
              HapticFeedback.selectionClick();
              if (isTab1) {
                _showAddTradeAccountSheet();
              } else {
                _showAddPayoutSheet();
              }
            },
            child: const Icon(HugeIconsSolid.add01, size: 28),
          );
        },
      ),
    );
  }

  Widget _buildTradeAccountsTab(AzamanColors colors) {
    if (_isLoadingTradeAccounts) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_tradeAccounts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(HugeIconsSolid.wallet01,
                size: 56, color: colors.textTertiary),
            const SizedBox(height: 16),
            Text('No trade accounts yet',
                style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            const SizedBox(height: 6),
            Text(
              'Tap + to add a Fiat Trade Account\nbuyers can pay into.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textTertiary, fontSize: 12),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchTradeAccounts,
      color: colors.accent,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _tradeAccounts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _buildAccountTile(_tradeAccounts[i], colors, false),
      ),
    );
  }

  Widget _buildPayoutsTab(AzamanColors colors) {
    if (_isLoadingPayouts) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_payoutDestinations.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(HugeIconsSolid.wallet01,
                size: 56, color: colors.textTertiary),
            const SizedBox(height: 16),
            Text('No payout destinations yet',
                style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            const SizedBox(height: 6),
            Text(
              'Tap + to add a Local Fiat/MoMo or\nExternal Web3 Wallet for payouts.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textTertiary, fontSize: 12),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchPayoutDestinations,
      color: colors.accent,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _payoutDestinations.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _buildAccountTile(_payoutDestinations[i], colors, true),
      ),
    );
  }

  Widget _buildAccountTile(
      Map<String, dynamic> account, AzamanColors colors, bool isPayout) {
    final String provider =
        account['provider'] ?? account['network'] ?? account['type'] ?? 'UNKNOWN';
    final String label = account['label'] ?? '';
    final String address = account['address'] ?? '';
    final int id = int.tryParse(account['id']?.toString() ?? '0') ?? 0;

    final bool isCrypto = provider == 'BINANCE_ID' ||
        provider == 'TRC20' ||
        provider == 'ERC20_BEP20' ||
        provider == 'Crypto Wallet';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: isCrypto
                ? colors.accent.withOpacity(0.15)
                : colors.success.withOpacity(0.15),
            child: Icon(
              isCrypto ? HugeIconsSolid.internet : HugeIconsSolid.bank,
              color: isCrypto ? colors.accent : colors.success,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.isNotEmpty ? label : provider,
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  address,
                  style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      fontFamily: isCrypto ? 'monospace' : null),
                ),
                const SizedBox(height: 2),
                Text(
                  provider,
                  style:
                      TextStyle(color: colors.textTertiary, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(HugeIconsSolid.delete01, color: colors.danger),
            onPressed: () {
              HapticFeedback.lightImpact();
              if (isPayout) {
                _deletePayout(id);
              } else {
                _deleteAccount(id);
              }
            },
          ),
        ],
      ),
    );
  }
}
