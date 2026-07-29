import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/trade_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/deposit_screen.dart';
import 'package:azaman/services/trade_account_service.dart';
import 'package:azaman/services/api_client.dart';
import 'dart:convert';


class VendorAdCreator extends ConsumerStatefulWidget {
  const VendorAdCreator({super.key});

  @override
  ConsumerState<VendorAdCreator> createState() => _VendorAdCreatorState();
}

class _VendorAdCreatorState extends ConsumerState<VendorAdCreator> {
  int _currentStep = 0;
  
  String adType = "SELL"; 
  String selectedAsset = "USDC"; 
  
  final TextEditingController _minLimitController = TextEditingController(text: "100");
  final TextEditingController _maxLimitController = TextEditingController(text: "5000");
  final TextEditingController _termsController = TextEditingController();

  // Phase F2: Trade account selection replaces fiat account multi-select
  TradeAccount? _selectedTradeAccount;
  List<TradeAccount> _approvedAccounts = [];
  
  double _availableBalance = 0.0;
  double _minCollateral = 500.0;
  bool _isLoadingData = true;
  bool _isPublishing = false;

  double _marginPercent = 0.0;

  TimeOfDay _activeHoursStart = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _activeHoursEnd = const TimeOfDay(hour: 22, minute: 0);
  int _maxPaymentWindow = 15;

  final List<String> _termsTemplates = [
    "No 3rd party payments accepted.",
    "Fast release. Do not include crypto words in memo.",
    "Please ensure your name matches the account.",
  ];

  @override
  void initState() {
    super.initState();
    _fetchVendorData(); 
  }

  Future<void> _fetchVendorData() async {
    final auth = ref.read(authProvider);
    if (auth.user?.id == null) return;

    try {
      final userRes = await apiClient.get('/auth/me/${auth.user!.id}');

      // Phase F2: Fetch approved trade accounts instead of generic wallet accounts
      final approved = await TradeAccountService.getApprovedAccounts();

      // Fetch vendor min collateral from global settings
      double minCollateral = 500.0; // fallback
      try {
        final settingsRes = await apiClient.get('/users/dashboard', requireAuth: true);
        if (settingsRes.statusCode == 200) {
          final settingsBody = jsonDecode(settingsRes.body);
          // The dashboard endpoint doesn't expose vendorMinCollateral yet,
          // so we use the fallback. The backend enforces the real value.
        }
      } catch (_) {
        // Non-fatal — use fallback
      }

      if (mounted) {
        setState(() {
          if (userRes.statusCode == 200) {
            final body = jsonDecode(userRes.body);
            // API returns { success, data: {...} } — unwrap the data key
            final userData = body['data'] ?? body['user'] ?? body;
            // Use vendorUnallocatedBalance (trading pool) as the liquidity source for ads
            _availableBalance = double.tryParse(userData['vendorUnallocatedBalance']?.toString() ?? '0') ?? 0.0;
          }
          
          _approvedAccounts = approved;
          _minCollateral = minCollateral;
          _isLoadingData = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  void _showDepositModal() {
    // Phase H10 BUGFIX (2026-05-27): the previous version showed a
    // dead snackbar ("Deposit flow opening..."). Now actually opens the
    // unified DepositScreen so the vendor can top up collateral
    // without leaving the ad-creator flow. Pop returns to the creator
    // where the balance check re-runs on Step 1's "Next" tap.
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DepositScreen()),
    ).then((_) {
      // Refetch balance after returning so the collateral check uses
      // the latest available balance (a successful deposit settles
      // async, but a fresh fetch reflects any synchronous credit).
      _fetchVendorData();
    });
  }

  /// Phase H10 BUGFIX (2026-05-27): the BE expects `HH:mm` 24-hour
  /// strings for activeHoursStart / activeHoursEnd. The previous
  /// version used `TimeOfDay.format(context)` which returns a
  /// localized string ("8:00 AM" / "08:00") depending on the device
  /// locale — broken on 12-hour locales (BE rejects or stores garbage).
  /// This helper always emits 24-hour zero-padded HH:mm.
  String _formatTimeWire(TimeOfDay t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  // --- PHASE F2: NOW USES tradeProvider.createAd() with tradeAccountId ---
  Future<void> _publishAd() async {
    if (_selectedTradeAccount == null) {
      _showSnackBar("Select a verified trade account.", isError: true);
      return;
    }
    
    final auth = ref.read(authProvider);
    final trade = ref.read(tradeProvider);
    final token = auth.user?.token ?? auth.token;
    
    if (token == null) {
      _showSnackBar("Authentication error. Please re-login.", isError: true);
      return;
    }

    setState(() => _isPublishing = true);

    // Phase F2: pricePerUSD is informational only (no GHS oracle math).
    // Default 1.0 means "1 USDC = 1 USD" (parity). The vendor margin is
    // applied as a percentage on top of the trade amount by the backend.
    final adData = {
      "type": adType,
      "crypto": selectedAsset,
      "margin": _marginPercent,
      "vendorMargin": _marginPercent,
      "pricePerUSD": 1.0 + (_marginPercent / 100),
      "minLimit": double.tryParse(_minLimitController.text) ?? 0.0,
      "maxLimit": double.tryParse(_maxLimitController.text) ?? 0.0,
      "paymentMethod": _selectedTradeAccount!.methodType,
      "tradeAccountId": _selectedTradeAccount!.id,
      "terms": _termsController.text.trim(),
      // Phase H10 BUGFIX: emit canonical 24-hour HH:mm strings so the
      // BE receives consistent values regardless of device locale.
      "activeHoursStart": _formatTimeWire(_activeHoursStart),
      "activeHoursEnd": _formatTimeWire(_activeHoursEnd),
      "maxPaymentWindow": _maxPaymentWindow,
    };

    final success = await trade.createAd(adData, token);

    if (mounted) {
      setState(() => _isPublishing = false);

      if (success) {
        HapticFeedback.heavyImpact();
        _showSnackBar("Ad Published Successfully!", isError: false);
        Navigator.pop(context);
      } else {
        _showSnackBar("Failed to publish ad. Check collateral.", isError: true);
      }
    }
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? const Color(0xFFF6465D) : const Color(0xFF02C076),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  void dispose() {
    _minLimitController.dispose();
    _maxLimitController.dispose();
    _termsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text("Post Ad", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colors.textPrimary)),
        leading: IconButton(icon: Icon(Icons.cancel_outlined, color: colors.textPrimary), onPressed: () => Navigator.pop(context)),
      ),
      body: _isLoadingData 
        ? Center(child: CircularProgressIndicator(color: colors.accent))
        : Column(
            children: [
              _buildTypeToggle(), 
              _buildStepIndicator(colors.accent),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: SingleChildScrollView(
                    key: ValueKey<int>(_currentStep),
                    padding: const EdgeInsets.all(20),
                    child: _buildCurrentStepContent(),
                  ),
                ),
              ),
              _buildBottomNavigation(colors.accent),
            ],
          ),
    );
  }

  Widget _buildTypeToggle() {
    final colors = ref.watch(themeProvider).colors;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      height: 40,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => adType = "SELL"),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: adType == "SELL" ? const Color(0xFFF6465D) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text("SELL Crypto", style: TextStyle(color: adType == "SELL" ? Colors.white : Colors.white54, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => adType = "BUY"),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: adType == "BUY" ? const Color(0xFF02C076) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text("BUY Crypto", style: TextStyle(color: adType == "BUY" ? Colors.white : Colors.white54, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepOne() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel("Asset"),
        _buildAssetDropdown(),
        const SizedBox(height: 35),
        
        _sectionLabel("Your Margin"),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ref.read(themeProvider).colors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ref.read(themeProvider).colors.accent.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.analytics_outlined, color: ref.read(themeProvider).colors.accent, size: 18),
                  const SizedBox(width: 8),
                  Text("+${_marginPercent.toStringAsFixed(1)}%",
                      style: TextStyle(color: ref.read(themeProvider).colors.accent, fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: ref.read(themeProvider).colors.accent,
                  inactiveTrackColor: ref.read(themeProvider).colors.accent.withValues(alpha: 0.2),
                  thumbColor: ref.read(themeProvider).colors.accent,
                  overlayColor: ref.read(themeProvider).colors.accent.withValues(alpha: 0.1),
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                ),
                child: Slider(
                  value: _marginPercent,
                  min: 0.0,
                  max: 10.0,
                  divisions: 40,
                  onChanged: (v) => setState(() => _marginPercent = v),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "At +${_marginPercent.toStringAsFixed(1)}%, "
                "you make \$${(_marginPercent * 0.5).toStringAsFixed(2)} profit on "
                "a \$50 trade, \$${(_marginPercent * 5).toStringAsFixed(2)} on \$500",
                style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 35),
        // Phase F2: Flat fee model explanation (replaces GHS oracle section)
        _sectionLabel("Fee Structure"),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: ref.read(themeProvider).colors.card, 
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ref.read(themeProvider).colors.accent.withValues(alpha: 0.3))
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.percent, color: Color(0xFFF0B90B), size: 20),
                  SizedBox(width: 10),
                  Text("Flat 2% Platform Fee", style: TextStyle(color: Color(0xFFF0B90B), fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 15),
              const Text(
                "All P2P trades have a flat 2% USDC fee applied at settlement. "
                "Trades are priced in USD (1:1 with USDC). Your margin is on top of this.",
                style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 15),
                child: Divider(color: Colors.white10),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Trades < \$1,000:", style: TextStyle(color: Colors.white54, fontSize: 12)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFF02C076).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                    child: const Text("60% Admin / 40% Vendor", style: TextStyle(color: Color(0xFF02C076), fontWeight: FontWeight.bold, fontSize: 11)),
                  )
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Trades > \$1,000:", style: TextStyle(color: Colors.white54, fontSize: 12)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFF02C076).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                    child: const Text("50% Admin / 50% Vendor", style: TextStyle(color: Color(0xFF02C076), fontWeight: FontWeight.bold, fontSize: 11)),
                  )
                ],
              ),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildStepTwo() {
    bool hasCollateral = _availableBalance >= _minCollateral;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel("Total Available Liquidity"),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: ref.read(themeProvider).colors.card, borderRadius: BorderRadius.circular(12)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("${_availableBalance.toStringAsFixed(2)} $selectedAsset", style: TextStyle(color: hasCollateral ? Colors.white : const Color(0xFFF6465D), fontSize: 24, fontWeight: FontWeight.bold)),
              GestureDetector(
                onTap: _showDepositModal,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: ref.read(themeProvider).colors.accent, borderRadius: BorderRadius.circular(6)),
                  child: const Text("+ Deposit", style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        ),
        
        const SizedBox(height: 10),

        if (!hasCollateral)
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF6465D).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFF6465D).withValues(alpha: 0.3))),
            child: const Row(
              children: [
                Icon(Icons.error_outline, color: Color(0xFFF6465D), size: 16),
                SizedBox(width: 8),
                Expanded(child: Text("Minimum \$500 collateral required to post an ad.", style: TextStyle(color: Color(0xFFF6465D), fontSize: 11))),
              ],
            ),
          ),

        const SizedBox(height: 15),
        Row(
          children: [
            Expanded(child: _buildStyledTextField(label: "Min Limit ($selectedAsset)", controller: _minLimitController, suffixText: "\$")),
            const SizedBox(width: 15),
            Expanded(child: _buildStyledTextField(label: "Max Limit ($selectedAsset)", controller: _maxLimitController, suffixText: "\$")),
          ],
        ),

        const SizedBox(height: 30),
        const Divider(color: Colors.white10),
        const SizedBox(height: 15),
        _sectionLabel("Active Hours"),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildTimePicker("Start", _activeHoursStart, (t) => setState(() => _activeHoursStart = t))),
            const SizedBox(width: 15),
            Expanded(child: _buildTimePicker("End", _activeHoursEnd, (t) => setState(() => _activeHoursEnd = t))),
          ],
        ),

        const SizedBox(height: 20),
        _sectionLabel("Max Payment Window"),
        const SizedBox(height: 8),
        _buildMaxWindowDropdown(),
      ],
    );
  }

  Widget _buildStepThree() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Phase F2: Select a single approved TradeAccount
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Select Payment Account", style: TextStyle(color: ref.read(themeProvider).colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
            GestureDetector(
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Go to Settings → Trade Accounts to add new accounts."))),
              child: Text("+ Add New", style: TextStyle(color: ref.read(themeProvider).colors.accent, fontSize: 12, fontWeight: FontWeight.bold)),
            )
          ],
        ),
        const SizedBox(height: 8),
        const Text("Choose the verified account where buyers will send fiat (or receive fiat for BUY ads).", style: TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 20),
        
        if (_approvedAccounts.isEmpty)
           Container(
             padding: const EdgeInsets.all(20),
             decoration: BoxDecoration(color: ref.read(themeProvider).colors.card, borderRadius: BorderRadius.circular(12)),
             child: const Center(child: Text("No verified Trade Accounts found.\nSubmit accounts in Settings → Trade Accounts\nand wait for admin approval.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12))),
           )
        else
          ..._approvedAccounts.map((account) {
            final bool isSelected = _selectedTradeAccount?.id == account.id;
            
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _selectedTradeAccount = isSelected ? null : account;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: isSelected ? ref.read(themeProvider).colors.accent.withValues(alpha: 0.1) : ref.read(themeProvider).colors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isSelected ? ref.read(themeProvider).colors.accent : Colors.transparent, width: 1.5),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected ? Icons.check_circle_outline : Icons.circle_outlined,
                      color: isSelected ? ref.read(themeProvider).colors.accent : Colors.white24,
                      size: 20,
                    ),
                    const SizedBox(width: 15),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(SupportedMethod.displayName(account.methodType), style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontWeight: FontWeight.bold, fontSize: 14)),
                        Text(account.displayLabel, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        
        const SizedBox(height: 30),
        const Divider(color: Colors.white10),
        const SizedBox(height: 15),

        Text("Terms of Trade", style: TextStyle(color: ref.read(themeProvider).colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 10),
        
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _termsTemplates.map((template) {
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ActionChip(
                  label: const Text("Use Template"),
                  backgroundColor: ref.read(themeProvider).colors.card,
                  labelStyle: TextStyle(color: ref.read(themeProvider).colors.accent, fontSize: 10),
                  onPressed: () {
                    setState(() {
                      _termsController.text = template;
                    });
                  },
                ),
              );
            }).toList(),
          ),
        ),
        
        const SizedBox(height: 12),
        TextField(
          controller: _termsController,
          maxLines: 4,
          style: TextStyle(color: ref.read(themeProvider).colors.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: "Enter your terms here...",
            hintStyle: const TextStyle(color: Colors.white24),
            filled: true, 
            fillColor: ref.read(themeProvider).colors.card,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildStepIndicator(Color gold) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 40),
      child: Row(
        children: List.generate(3, (i) => Expanded(
          child: Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: _currentStep >= i ? gold : ref.read(themeProvider).colors.card,
                child: Text("${i + 1}", style: TextStyle(color: _currentStep >= i ? Colors.black : Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              if (i < 2) Expanded(child: Container(height: 2, color: _currentStep > i ? gold : ref.read(themeProvider).colors.card)),
            ],
          ),
        )),
      ),
    );
  }

  Widget _buildAssetDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: ref.read(themeProvider).colors.card, borderRadius: BorderRadius.circular(12)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedAsset,
          dropdownColor: ref.read(themeProvider).colors.card,
          isExpanded: true,
          style: TextStyle(color: ref.read(themeProvider).colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
          items: ["USDT", "USDC"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (v) => setState(() => selectedAsset = v!),
        ),
      ),
    );
  }

  Widget _buildTimePicker(String label, TimeOfDay time, ValueChanged<TimeOfDay> onPicked) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(label),
        GestureDetector(
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: time,
              builder: (context, child) {
                return Theme(
                  data: ThemeData.dark().copyWith(
                    colorScheme: ColorScheme.dark(
                      primary: ref.read(themeProvider).colors.accent,
                      onPrimary: Colors.black,
                    ),
                  ),
                  child: child!,
                );
              },
            );
            if (picked != null) onPicked(picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: ref.read(themeProvider).colors.card,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.access_time, color: ref.read(themeProvider).colors.accent, size: 18),
                const SizedBox(width: 12),
                Text(
                  time.format(context),
                  style: TextStyle(color: ref.read(themeProvider).colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMaxWindowDropdown() {
    const List<int> options = [15, 30, 45, 60];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: ref.read(themeProvider).colors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _maxPaymentWindow,
          isExpanded: true,
          dropdownColor: ref.read(themeProvider).colors.card,
          style: TextStyle(color: ref.read(themeProvider).colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
          items: options.map((m) {
            final label = m < 60 ? "${m}m" : "1h";
            return DropdownMenuItem(value: m, child: Text(label));
          }).toList(),
          onChanged: (v) {
            if (v != null) setState(() => _maxPaymentWindow = v);
          },
        ),
      ),
    );
  }

  Widget _buildStyledTextField({required String label, required TextEditingController controller, required String suffixText}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(label),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(color: ref.read(themeProvider).colors.textPrimary, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            filled: true, fillColor: ref.read(themeProvider).colors.card,
            suffixText: suffixText,
            suffixStyle: TextStyle(color: ref.read(themeProvider).colors.accent),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8.0),
    child: Text(text, style: const TextStyle(color: Colors.white54, fontSize: 12)),
  );

  Widget _buildBottomNavigation(Color gold) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          if (_currentStep > 0) 
            Expanded(child: TextButton(onPressed: () => setState(() => _currentStep--), child: const Text("Back", style: TextStyle(color: Colors.white54)))),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: gold, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: _isPublishing ? null : () {
                
                if (_currentStep == 1) {
                  double maxLimit = double.tryParse(_maxLimitController.text) ?? 0.0;
                  double minLimit = double.tryParse(_minLimitController.text) ?? 0.0;
                  
                  if (_availableBalance < _minCollateral) {
                    _showSnackBar("You need at least \$${_minCollateral.toStringAsFixed(0)} in your trading pool to post.", isError: true);
                    return;
                  }
                  // Allow max limit up to the full trading pool (with small tolerance for floating point)
                  if (maxLimit > _availableBalance + 0.01) {
                    _showSnackBar("Max limit cannot exceed your trading pool (\$${_availableBalance.toStringAsFixed(2)}).", isError: true);
                    return;
                  }
                  if (minLimit > maxLimit) {
                    _showSnackBar("Min limit cannot be greater than max limit.", isError: true);
                    return;
                  }
                  // Phase H10 BUGFIX: validate active hours so a vendor
                  // can't accidentally post an ad with start == end (a
                  // zero-length active window, ad never matches a buyer)
                  // or with end before start (which the BE may quietly
                  // accept and produce a never-active ad).
                  final startMin = _activeHoursStart.hour * 60 + _activeHoursStart.minute;
                  final endMin = _activeHoursEnd.hour * 60 + _activeHoursEnd.minute;
                  if (startMin == endMin) {
                    _showSnackBar("Active-hours start and end can't be the same.", isError: true);
                    return;
                  }
                }

                // Phase H10 BUGFIX: validate Step 2 (publish) at the
                // step boundary instead of inside _publishAd, so the
                // "Publish" button disables visibly when no account is
                // selected and the user gets feedback BEFORE the
                // submit-and-rollback flow.
                if (_currentStep == 2 && _selectedTradeAccount == null) {
                  _showSnackBar("Select a verified trade account to continue.", isError: true);
                  return;
                }

                if (_currentStep < 2) {
                  setState(() => _currentStep++);
                } else {
                  _publishAd();
                }
              },
              child: _isPublishing 
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2)) 
                : Text(_currentStep == 2 ? "Publish Ad" : "Next", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStepContent() {
    if (_currentStep == 0) return _buildStepOne();
    if (_currentStep == 1) return _buildStepTwo();
    return _buildStepThree();
  }
}