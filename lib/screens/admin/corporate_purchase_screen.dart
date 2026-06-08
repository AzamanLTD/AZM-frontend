import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class CorporatePurchaseScreen extends ConsumerStatefulWidget {
  const CorporatePurchaseScreen({super.key});

  @override
  ConsumerState<CorporatePurchaseScreen> createState() => _CorporatePurchaseScreenState();
}

class _CorporatePurchaseScreenState extends ConsumerState<CorporatePurchaseScreen> {
  final _discountRateController = TextEditingController();
  final _marketRateController = TextEditingController();
  final _usdcAmountController = TextEditingController();
  final _fiatSentController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  File? _receiptImage;
  bool _isUploading = false;
  bool _isSubmitted = false;

  @override
  void dispose() {
    _discountRateController.dispose();
    _marketRateController.dispose();
    _usdcAmountController.dispose();
    _fiatSentController.dispose();
    super.dispose();
  }

  Future<void> _pickReceipt() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (picked != null) {
        setState(() => _receiptImage = File(picked.path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gallery error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _submitOtcLog() async {
    if (!_formKey.currentState!.validate()) return;
    if (_receiptImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Receipt screenshot is required"), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiClient.baseUrl}/admin/otc/log'),
      );

      request.fields['discountRate'] = _discountRateController.text.trim();
      request.fields['marketRate'] = _marketRateController.text.trim();
      request.fields['usdcAmount'] = _usdcAmountController.text.trim();
      request.fields['fiatSent'] = _fiatSentController.text.trim();
      request.files.add(await http.MultipartFile.fromPath('receipt', _receiptImage!.path));

      final response = await apiClient.multipart('/admin/otc/log', request);

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
        HapticFeedback.heavyImpact();
        setState(() => _isSubmitted = true);
        _showSuccessDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("OTC log failed: ${response.body}"),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Network error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showSuccessDialog() {
    final colors = ref.read(themeProvider).colors;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(HugeIconsSolid.checkmarkCircle01, color: colors.success, size: 56),
            const SizedBox(height: 16),
            Text(
              'OTC Logged Successfully',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The corporate purchase record has been submitted to the ledger.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop();
                },
                child: const Text('DONE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            ),
          ],
        ),
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
              child: Icon(HugeIconsSolid.bank, color: colors.accent, size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              'CORPORATE PURCHASE',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
      body: _isSubmitted
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(HugeIconsSolid.checkmarkCircle01, color: colors.success, size: 80),
                  const SizedBox(height: 20),
                  Text(
                    'OTC Recorded',
                    style: TextStyle(color: colors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Receipt logged to the corporate ledger.',
                    style: TextStyle(color: colors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader('MANUAL OTC LOGGING', HugeIconsSolid.noteEdit, colors),
                    const SizedBox(height: 6),
                    Text(
                      'Record a corporate OTC trade with exact financial details.',
                      style: TextStyle(color: colors.textTertiary, fontSize: 12),
                    ),
                    const SizedBox(height: 24),

                    _buildFormField(
                      controller: _discountRateController,
                      label: 'DISCOUNT RATE (%)',
                      hint: 'e.g. 2.5',
                      prefix: '%',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      colors: colors,
                    ),
                    const SizedBox(height: 16),

                    _buildFormField(
                      controller: _marketRateController,
                      label: 'ACTUAL MARKET RATE',
                      hint: 'e.g. 15.85',
                      prefix: 'GHS',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      colors: colors,
                    ),
                    const SizedBox(height: 16),

                    _buildFormField(
                      controller: _usdcAmountController,
                      label: 'EXACT USDC AMOUNT BOUGHT',
                      hint: 'e.g. 5000.00',
                      prefix: 'USDC',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      colors: colors,
                    ),
                    const SizedBox(height: 16),

                    _buildFormField(
                      controller: _fiatSentController,
                      label: 'EXACT FIAT SENT (inc. charges)',
                      hint: 'e.g. 79250.00',
                      prefix: 'GHS',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      colors: colors,
                    ),
                    const SizedBox(height: 28),

                    _buildSectionHeader('TRANSACTION RECEIPT', HugeIconsSolid.receiptDollar, colors),
                    const SizedBox(height: 4),
                    Text(
                      'Upload a clear screenshot of the payment confirmation. This is mandatory.',
                      style: TextStyle(color: colors.textTertiary, fontSize: 12),
                    ),
                    const SizedBox(height: 16),

                    _buildReceiptPicker(colors),
                    const SizedBox(height: 32),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _receiptImage == null
                              ? colors.accent.withOpacity(0.5)
                              : colors.accent,
                          foregroundColor: Colors.black,
                          disabledBackgroundColor: colors.divider,
                          disabledForegroundColor: colors.textTertiary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: (_isUploading) ? null : _submitOtcLog,
                        icon: _isUploading
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.black,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(HugeIconsSolid.cloudUpload),
                        label: Text(
                          _isUploading ? 'SUBMITTING...' : 'LOG OTC TO LEDGER',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, AzamanColors colors) {
    return Row(
      children: [
        Icon(icon, color: colors.accent, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required String prefix,
    required TextInputType keyboardType,
    required AzamanColors colors,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colors.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
          keyboardType: keyboardType,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Required';
            if (double.tryParse(v.trim()) == null) return 'Enter a valid number';
            return null;
          },
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: colors.textTertiary.withOpacity(0.5)),
            prefixText: '$prefix ',
            prefixStyle: TextStyle(
              color: colors.accent,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            filled: true,
            fillColor: colors.card,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colors.accent.withOpacity(0.5)),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colors.danger.withOpacity(0.5)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colors.danger),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReceiptPicker(AzamanColors colors) {
    return GestureDetector(
      onTap: _pickReceipt,
      child: Container(
        width: double.infinity,
        height: 220,
        decoration: BoxDecoration(
          color: _receiptImage == null
              ? colors.card
              : colors.card.withOpacity(0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _receiptImage == null
                ? colors.accent.withOpacity(0.3)
                : colors.success.withOpacity(0.6),
            width: _receiptImage == null ? 1.5 : 2.5,
          ),
        ),
        child: _receiptImage == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.accent.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      HugeIconsSolid.camera01,
                      color: colors.accent,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'TAP TO UPLOAD RECEIPT',
                    style: TextStyle(
                      color: colors.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'PNG, JPG — Max 10MB',
                    style: TextStyle(color: colors.textTertiary, fontSize: 11),
                  ),
                ],
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Image.file(
                      _receiptImage!,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: GestureDetector(
                      onTap: _pickReceipt,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(HugeIconsSolid.refresh01, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'Change',
                              style: TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: colors.success.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(HugeIconsSolid.checkmarkCircle01, color: Colors.white, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'RECEIPT ATTACHED',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
