// =============================================================================
// BUSINESS DASHBOARD SCREEN — Flutter V3 Marketplace Sprint (2026-06-21)
//
// Owner-only management surface. Requires a registered business; if the user
// has none it redirects to the registration screen. Shows a 2×2 stats grid,
// the most recent orders, quick actions (add product, KYB, reviews, products),
// the owner's product list with edit/delete, and a KYB prompt banner when the
// business is not yet verified.
// =============================================================================

import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:image_picker/image_picker.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/business_profile_screen.dart';
import 'package:azaman/screens/marketplace/business_register_screen.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/azaman_confirm_sheet.dart';

// KYB document types (Section 13).
const _kKybTypes = <String, String>{
  'BUSINESS_REGISTRATION_CERT': 'Business Registration Certificate',
  'DIRECTOR_ID_FRONT': 'Director ID (Front)',
  'DIRECTOR_ID_BACK': 'Director ID (Back)',
  'TAX_IDENTIFICATION': 'Tax Identification',
  'PROOF_OF_ADDRESS': 'Proof of Address',
  'SELFIE_WITH_ID': 'Selfie with ID',
  'OTHER': 'Other',
};

class BusinessDashboardScreen extends ConsumerStatefulWidget {
  const BusinessDashboardScreen({super.key});

  @override
  ConsumerState<BusinessDashboardScreen> createState() =>
      _BusinessDashboardScreenState();
}

class _BusinessDashboardScreenState
    extends ConsumerState<BusinessDashboardScreen> {
  final _service = BusinessService();
  BusinessStats? _stats;
  List<BusinessProduct> _products = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!ref.read(myBusinessProvider).hasLoaded) {
        await ref.read(myBusinessProvider.notifier).load();
      }
      _loadDashboard();
    });
  }

  Future<void> _loadDashboard() async {
    try {
      final results = await Future.wait([
        _service.getBusinessStats(),
        _service.getMyProducts(),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as BusinessStats;
        _products = (results[1] as ProductPage).products;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final myBiz = ref.watch(myBusinessProvider);

    // Redirect to register if no business once loaded.
    if (myBiz.hasLoaded && myBiz.profile == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => const BusinessRegisterScreen()),
          );
        }
      });
      return Scaffold(
        backgroundColor: colors.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final profile = myBiz.profile;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
        title: Text(profile?.businessName ?? 'My Business',
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800)),
        actions: [
          if (profile != null)
            IconButton(
              icon: Icon(Icons.storefront_outlined, color: colors.textSecondary),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BusinessProfileScreen(bizId: profile.bizId),
                ),
              ),
            ),
        ],
      ),
      body: _loading || profile == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDashboard,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (!profile.isKybVerified) _kybBanner(colors, profile),
                  if (_stats != null) _revenueChart(colors),
                  if (_stats != null) const SizedBox(height: 20),
                  _statsGrid(colors),
                  const SizedBox(height: 20),
                  _quickActions(colors, profile),
                  const SizedBox(height: 20),
                  _recentOrders(colors),
                  const SizedBox(height: 20),
                  _productsManagement(colors),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _kybBanner(AzamanColors colors, BusinessProfile profile) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, color: colors.warning, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Get verified',
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800)),
                Text('Submit KYB documents to earn the verified badge.',
                    style:
                        TextStyle(color: colors.textTertiary, fontSize: 12)),
              ],
            ),
          ),
          TextButton(
            onPressed: _openKybSheet,
            child: Text('Submit',
                style: TextStyle(
                    color: colors.warning, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _statsGrid(AzamanColors colors) {
    final s = _stats;
    final cards = [
      _StatData('Total Orders', '${s?.totalOrders ?? 0}',
          Icons.shopping_bag_outlined, colors.accent),
      _StatData('Completed', '${s?.completedOrders ?? 0}',
          Icons.check_circle_outline, colors.success),
      _StatData('Revenue', '${(s?.totalRevenue ?? 0).toStringAsFixed(2)}',
          Icons.account_balance_wallet_outlined, colors.success),
      _StatData('Avg Order', '${(s?.avgOrderValue ?? 0).toStringAsFixed(2)}',
          Icons.show_chart, colors.warning),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.7,
      children: cards.map((c) => _statCard(colors, c)).toList(),
    );
  }

  Widget _statCard(AzamanColors colors, _StatData data) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(data.icon, color: data.tint, size: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(data.value,
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w900)),
              Text(data.label,
                  style:
                      TextStyle(color: colors.textTertiary, fontSize: 11.5)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickActions(AzamanColors colors, BusinessProfile profile) {
    final actions = [
      ('Add Product', Icons.add_circle_outline, () => _openProductEditor()),
      (
        'View Reviews',
        Icons.star_outline,
        () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BusinessProfileScreen(bizId: profile.bizId),
              ),
            )
      ),
      ('Submit KYB', Icons.shield_outlined, _openKybSheet),
      (
        'My Products',
        Icons.storefront_outlined,
        () => _loadDashboard(),
      ),
    ];
    return Row(
      children: actions
          .map((a) => Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    AzamanHaptics.nav();
                    a.$3();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colors.accentSurface,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child:
                              Icon(a.$2, color: colors.accent, size: 22),
                        ),
                        const SizedBox(height: 6),
                        Text(a.$1,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _recentOrders(AzamanColors colors) {
    final orders = _stats?.recentOrders ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('RECENT ORDERS',
            style: TextStyle(
                color: colors.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8)),
        const SizedBox(height: 8),
        if (orders.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.divider),
            ),
            child: Text('No orders yet.',
                style: TextStyle(color: colors.textTertiary, fontSize: 13)),
          )
        else
          ...orders.take(5).map((o) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.divider),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(o.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700)),
                          Text(o.orderRef,
                              style: TextStyle(
                                  color: colors.textTertiary, fontSize: 11)),
                        ],
                      ),
                    ),
                    Text('${o.amountUsdc.toStringAsFixed(2)} USDC',
                        style: TextStyle(
                            color: colors.accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              )),
      ],
    );
  }

  // 7-day revenue bar chart (Marketplace Premium Upgrade, 2026-06-21).
  // Aggregates BusinessStats.recentOrders by day-of-week over the last 7 days.
  Widget _revenueChart(AzamanColors colors) {
    final orders = _stats?.recentOrders ?? const [];
    if (orders.isEmpty) return const SizedBox.shrink();
    // Build a day-of-week aggregation for the last 7 days.
    // Key = "Mon", "Tue", etc. Value = sum of order amounts.
    final now = DateTime.now();
    final days = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return d;
    });
    const dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final Map<String, double> totals = {};
    for (final d in days) {
      totals[dayLabels[d.weekday % 7]] = 0;
    }
    for (final o in orders) {
      final key = dayLabels[o.createdAt.weekday % 7];
      totals[key] = (totals[key] ?? 0) + o.amountUsdc;
    }
    final bars = days.asMap().entries.map((entry) {
      final label = dayLabels[entry.value.weekday % 7];
      final value = totals[label] ?? 0;
      return BarChartGroupData(
        x: entry.key,
        barRods: [
          BarChartRodData(
            toY: value,
            color: colors.accent,
            width: 18,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: (totals.values.isEmpty
                      ? 1
                      : totals.values.reduce((a, b) => a > b ? a : b)) *
                  1.2,
              color: colors.softSurface,
            ),
          ),
        ],
      );
    }).toList();
    final maxY = totals.values.isEmpty
        ? 10.0
        : (totals.values.reduce((a, b) => a > b ? a : b) * 1.3)
            .clamp(1.0, double.infinity);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '7-Day Revenue',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'USDC  ·  last 7 days',
            style: TextStyle(color: colors.textTertiary, fontSize: 11),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                barGroups: bars,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 4,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: colors.divider,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (value, meta) => Text(
                        value.toStringAsFixed(0),
                        style: TextStyle(
                            color: colors.textTertiary, fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, _) {
                        final i = value.toInt();
                        if (i < 0 || i >= days.length) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          dayLabels[days[i].weekday % 7],
                          style: TextStyle(
                              color: colors.textTertiary, fontSize: 10),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                      '${rod.toY.toStringAsFixed(2)} USDC',
                      TextStyle(
                        color: colors.isDark ? Colors.black : Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _productsManagement(AzamanColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('MY PRODUCTS',
                style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8)),
            const Spacer(),
            GestureDetector(
              onTap: () => _openProductEditor(),
              child: Text('+ Add',
                  style: TextStyle(
                      color: colors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_products.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.divider),
            ),
            child: Text('No products yet. Tap “Add” to create one.',
                style: TextStyle(color: colors.textTertiary, fontSize: 13)),
          )
        else
          ..._products.map((p) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.divider),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700)),
                          Text('${p.priceUsdc.toStringAsFixed(2)} USDC',
                              style: TextStyle(
                                  color: colors.accent, fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.edit_outlined,
                          size: 18, color: colors.textSecondary),
                      onPressed: () => _openProductEditor(existing: p),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_forever_outlined,
                          size: 18, color: colors.danger),
                      onPressed: () => _deleteProduct(p),
                    ),
                  ],
                ),
              )),
      ],
    );
  }

  Future<void> _deleteProduct(BusinessProduct p) async {
    final ok = await AzamanConfirmSheet.show(
      context,
      title: 'Delete Product',
      message: 'Remove "${p.name}" from your catalogue?',
      confirmLabel: 'Delete',
      destructive: true,
      icon: Icons.delete_forever_outlined,
    );
    if (ok != true) return;
    try {
      await _service.deleteProduct(p.id);
      if (mounted) {
        setState(() => _products =
            _products.where((x) => x.id != p.id).toList());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Delete failed: $e'),
          backgroundColor: ref.read(themeProvider).colors.danger,
        ));
      }
    }
  }

  Future<void> _openProductEditor({BusinessProduct? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProductEditorSheet(existing: existing),
    );
    if (saved == true) _loadDashboard();
  }

  Future<void> _openKybSheet() async {
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _KybSubmitSheet(),
    );
    if (submitted == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('KYB documents submitted for review.'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }
}

class _StatData {
  final String label;
  final String value;
  final IconData icon;
  final Color tint;
  _StatData(this.label, this.value, this.icon, this.tint);
}

// ─────────────────────────────────────────────────────────────────────────────
// Product editor sheet (create / edit)
// ─────────────────────────────────────────────────────────────────────────────

class _ProductEditorSheet extends ConsumerStatefulWidget {
  final BusinessProduct? existing;
  const _ProductEditorSheet({this.existing});

  @override
  ConsumerState<_ProductEditorSheet> createState() =>
      _ProductEditorSheetState();
}

class _ProductEditorSheetState extends ConsumerState<_ProductEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _deliveryCtrl;
  String? _imageUrl;
  File? _imageFile;
  bool _uploading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _priceCtrl =
        TextEditingController(text: e?.priceUsdc.toStringAsFixed(2) ?? '');
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _deliveryCtrl = TextEditingController(text: e?.estimatedDelivery ?? '');
    _imageUrl = e?.primaryImage;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _descCtrl.dispose();
    _deliveryCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() {
      _imageFile = File(picked.path);
      _uploading = true;
    });
    try {
      final url = await BusinessService().uploadBusinessImage(
        File(picked.path),
        folder: 'products',
      );
      if (mounted) {
        setState(() {
          _imageUrl = url;
          _uploading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final data = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'priceUsdc': double.tryParse(_priceCtrl.text.trim()) ?? 0,
      if (_descCtrl.text.trim().isNotEmpty)
        'description': _descCtrl.text.trim(),
      if (_deliveryCtrl.text.trim().isNotEmpty)
        'estimatedDelivery': _deliveryCtrl.text.trim(),
      if (_imageUrl != null) 'imageUrls': [_imageUrl],
    };
    try {
      final svc = BusinessService();
      if (widget.existing != null) {
        await svc.updateProduct(widget.existing!.id, data);
      } else {
        await svc.createProduct(data);
      }
      if (!mounted) return;
      AzamanHaptics.commit();
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Save failed: $e'),
        backgroundColor: ref.read(themeProvider).colors.danger,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.divider,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(widget.existing == null ? 'Add Product' : 'Edit Product',
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                Center(
                  child: GestureDetector(
                    onTap: _uploading ? null : _pickImage,
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: colors.card,
                        borderRadius: BorderRadius.circular(14),
                        image: _imageFile != null
                            ? DecorationImage(
                                image: FileImage(_imageFile!),
                                fit: BoxFit.cover)
                            : (_imageUrl != null
                                ? DecorationImage(
                                    image: NetworkImage(_imageUrl!),
                                    fit: BoxFit.cover)
                                : null),
                      ),
                      alignment: Alignment.center,
                      child: _uploading
                          ? const CircularProgressIndicator(strokeWidth: 2)
                          : (_imageFile == null && _imageUrl == null
                              ? Icon(Icons.image_outlined,
                                  color: colors.textTertiary, size: 26)
                              : null),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameCtrl,
                  style: TextStyle(color: colors.textPrimary),
                  decoration: _dec(colors, 'Product name'),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _priceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}')),
                  ],
                  style: TextStyle(color: colors.textPrimary),
                  decoration: _dec(colors, 'Price (USDC)'),
                  validator: (v) {
                    final p = double.tryParse((v ?? '').trim());
                    if (p == null || p <= 0) return 'Enter a valid price';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 3,
                  style: TextStyle(color: colors.textPrimary),
                  decoration: _dec(colors, 'Description (optional)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _deliveryCtrl,
                  style: TextStyle(color: colors.textPrimary),
                  decoration:
                      _dec(colors, 'Estimated delivery (optional)'),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor:
                          colors.isDark ? Colors.black : Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(widget.existing == null
                            ? 'Create Product'
                            : 'Save Changes'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _dec(AzamanColors colors, String label) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: colors.textTertiary, fontSize: 14),
        filled: true,
        fillColor: colors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// KYB submission sheet
// ─────────────────────────────────────────────────────────────────────────────

class _KybSubmitSheet extends ConsumerStatefulWidget {
  const _KybSubmitSheet();

  @override
  ConsumerState<_KybSubmitSheet> createState() => _KybSubmitSheetState();
}

class _KybSubmitSheetState extends ConsumerState<_KybSubmitSheet> {
  final _service = BusinessService();
  final Map<String, String> _uploaded = {}; // documentType -> url
  String? _uploadingType;
  bool _submitting = false;

  Future<void> _pick(String type) async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() => _uploadingType = type);
    try {
      final url = await BusinessService().uploadBusinessImage(
        File(picked.path),
        folder: 'kyb',
      );
      if (mounted) {
        setState(() {
          _uploaded[type] = url;
          _uploadingType = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _uploadingType = null);
    }
  }

  Future<void> _submit() async {
    if (_uploaded.isEmpty) return;
    setState(() => _submitting = true);
    try {
      final docs = _uploaded.entries
          .map((e) => {'documentType': e.key, 'documentUrl': e.value})
          .toList();
      await _service.submitKybDocuments(docs);
      if (!mounted) return;
      AzamanHaptics.commit();
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Submit failed: $e'),
        backgroundColor: ref.read(themeProvider).colors.danger,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.divider,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('Submit KYB Documents',
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Upload at least one document. Add more for faster review.',
                style: TextStyle(color: colors.textTertiary, fontSize: 12)),
            const SizedBox(height: 14),
            ..._kKybTypes.entries.map((e) {
              final done = _uploaded.containsKey(e.key);
              final busy = _uploadingType == e.key;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: busy ? null : () => _pick(e.key),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: done
                            ? colors.success.withValues(alpha: 0.5)
                            : colors.divider,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          done
                              ? Icons.check_circle_outline
                              : Icons.insert_drive_file_outlined,
                          color: done ? colors.success : colors.textTertiary,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(e.value,
                              style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600)),
                        ),
                        if (busy)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Text(done ? 'Replace' : 'Upload',
                              style: TextStyle(
                                  color: colors.accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed:
                    _submitting || _uploaded.isEmpty ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.isDark ? Colors.black : Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text('Submit ${_uploaded.length} document(s)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
