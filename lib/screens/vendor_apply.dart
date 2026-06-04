// =============================================================================
// VENDOR APPLY SCREEN — Multi-Step Vendor Registration (Binance-Level KYC)
//
// 5-step registration process:
//   Step 1: Personal Identity (legal name, DOB, country, ID upload + selfie)
//   Step 2: Proof of Address (document upload + residential address)
//   Step 3: Financial Background (source of funds, volume, experience)
//   Step 4: Payment Methods (minimum 2 required)
//   Step 5: Collateral & Terms (accept terms, confirm collateral)
//
// Phase V (2026-05): Complete rewrite from basic ID-only form to comprehensive
// vendor verification matching Binance P2P merchant standards.
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';


class VendorApplyScreen extends ConsumerStatefulWidget {
  const VendorApplyScreen({super.key});

  @override
  ConsumerState<VendorApplyScreen> createState() => _VendorApplyScreenState();
}

class _VendorApplyScreenState extends ConsumerState<VendorApplyScreen> {
  int _currentStep = 0;
  bool _isSubmitting = false;

  // Step 1: Personal Identity
  final _legalNameCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  String _selectedCountry = 'Ghana';
  String _selectedIdType = 'National ID';
  File? _idFront;
  File? _idBack;
  File? _selfieWithId;

  // Step 2: Proof of Address
  File? _addressProof;
  final _streetCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _regionCtrl = TextEditingController();
  final _postalCtrl = TextEditingController();

  // Step 3: Financial Background
  String _sourceOfFunds = 'Employment income';
  final _sourceOtherCtrl = TextEditingController();
  String _monthlyVolume = '\$0 – \$1,000';
  bool _hasPreviousExperience = false;
  final _previousPlatformsCtrl = TextEditingController();


  // Step 4: Payment Methods
  List<Map<String, String>> _paymentMethods = [];
  final _pmTypeCtrl = TextEditingController();
  final _pmDetailsCtrl = TextEditingController();

  // Step 5: Terms
  bool _acceptedTerms = false;
  bool _acceptedFees = false;
  bool _acceptedResponseTime = false;

  final _picker = ImagePicker();

  final List<String> _countries = [
    'Ghana', 'Nigeria', 'Kenya', 'South Africa', 'United States',
    'United Kingdom', 'Canada', 'Germany', 'France', 'Other',
  ];

  final List<String> _idTypes = [
    'National ID', 'International Passport', 'Driver\'s License',
  ];

  final List<String> _fundSources = [
    'Employment income', 'Business income', 'Investments',
    'Savings', 'Other',
  ];

  final List<String> _volumeRanges = [
    '\$0 – \$1,000', '\$1,000 – \$5,000',
    '\$5,000 – \$20,000', '\$20,000+',
  ];

  @override
  void dispose() {
    _legalNameCtrl.dispose();
    _dobCtrl.dispose();
    _streetCtrl.dispose();
    _cityCtrl.dispose();
    _regionCtrl.dispose();
    _postalCtrl.dispose();
    _sourceOtherCtrl.dispose();
    _previousPlatformsCtrl.dispose();
    _pmTypeCtrl.dispose();
    _pmDetailsCtrl.dispose();
    super.dispose();
  }


  Future<void> _pickImage(String target) async {
    try {
      final source = await _showImageSourcePicker();
      if (source == null) return;
      final file = await _picker.pickImage(source: source, imageQuality: 80);
      if (file == null) return;
      setState(() {
        switch (target) {
          case 'id_front': _idFront = File(file.path); break;
          case 'id_back': _idBack = File(file.path); break;
          case 'selfie': _selfieWithId = File(file.path); break;
          case 'address': _addressProof = File(file.path); break;
        }
      });
    } catch (e) {
      debugPrint('Image pick error: $e');
    }
  }

  Future<ImageSource?> _showImageSourcePicker() async {
    final colors = ref.read(themeProvider).colors;
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.camera_alt_rounded, color: colors.accent),
              title: Text('Camera', style: TextStyle(color: colors.textPrimary)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_rounded, color: colors.accent),
              title: Text('Gallery', style: TextStyle(color: colors.textPrimary)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }


  bool _canProceed() {
    switch (_currentStep) {
      case 0: // Identity
        return _legalNameCtrl.text.trim().isNotEmpty &&
            _dobCtrl.text.trim().isNotEmpty &&
            _idFront != null &&
            _selfieWithId != null;
      case 1: // Address
        return _addressProof != null &&
            _streetCtrl.text.trim().isNotEmpty &&
            _cityCtrl.text.trim().isNotEmpty &&
            _regionCtrl.text.trim().isNotEmpty;
      case 2: // Financial
        return true; // All have defaults
      case 3: // Payment methods
        return _paymentMethods.length >= 2;
      case 4: // Terms
        return _acceptedTerms && _acceptedFees && _acceptedResponseTime;
      default:
        return false;
    }
  }

  void _nextStep() {
    if (_currentStep < 4) {
      HapticFeedback.lightImpact();
      setState(() => _currentStep++);
    } else {
      _submitApplication();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }


  /// Upload vendor documents (ID front/back, selfie, address proof) and return URLs.
  /// Returns a map of field names to uploaded URLs, or null on failure.
  Future<Map<String, String>?> _uploadDocuments() async {
    final uri = Uri.parse('${ApiClient.baseUrl}/vendor/upload-docs');
    final request = http.MultipartRequest('POST', uri);

    // Attach files that exist
    if (_idFront != null) {
      request.files.add(await http.MultipartFile.fromPath('idFront', _idFront!.path));
    }
    if (_idBack != null) {
      request.files.add(await http.MultipartFile.fromPath('idBack', _idBack!.path));
    }
    if (_selfieWithId != null) {
      request.files.add(await http.MultipartFile.fromPath('selfie', _selfieWithId!.path));
    }
    if (_addressProof != null) {
      request.files.add(await http.MultipartFile.fromPath('addressProof', _addressProof!.path));
    }

    if (request.files.isEmpty) return {};

    final response = await apiClient.multipart('/vendor/upload-docs', request);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final urls = Map<String, String>.from(data['urls'] ?? {});
      return urls;
    }
    return null;
  }

  Future<void> _submitApplication() async {
    setState(() => _isSubmitting = true);
    final colors = ref.read(themeProvider).colors;

    try {
      // Step 1: Upload documents first
      final uploadedUrls = await _uploadDocuments();
      if (uploadedUrls == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Failed to upload documents. Please try again.'),
              backgroundColor: colors.danger,
            ),
          );
        }
        return;
      }

      // Step 2: Build payload with uploaded URLs
      final payload = {
        'legalName': _legalNameCtrl.text.trim(),
        'dateOfBirth': _dobCtrl.text.trim(),
        'country': _selectedCountry,
        'idType': _selectedIdType,
        'addressStreet': _streetCtrl.text.trim(),
        'addressCity': _cityCtrl.text.trim(),
        'addressRegion': _regionCtrl.text.trim(),
        'addressPostal': _postalCtrl.text.trim(),
        'sourceOfFunds': _sourceOfFunds,
        'sourceOfFundsOther': _sourceOtherCtrl.text.trim(),
        'monthlyVolumeEstimate': _monthlyVolume,
        'hasPreviousExperience': _hasPreviousExperience,
        'previousPlatforms': _previousPlatformsCtrl.text.trim(),
        'paymentMethods': _paymentMethods,
        'acceptedTerms': true,
        'collateralAmount': 500,
        // Include uploaded document URLs
        'idImageFront': uploadedUrls['idFront'],
        'idImageBack': uploadedUrls['idBack'],
        'selfieWithId': uploadedUrls['selfie'],
        'proofOfAddress': uploadedUrls['addressProof'],
      };

      final response = await apiClient.post('/vendor/apply', payload);

      if (response.statusCode == 201 || response.statusCode == 200) {
        HapticFeedback.heavyImpact();
        if (mounted) _showSuccessDialog();
      } else {
        final data = jsonDecode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message'] ?? 'Application failed'),
              backgroundColor: colors.danger,
            ),
          );
        }
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: colors.danger),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Network error. Please try again.'),
            backgroundColor: colors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }


  void _showSuccessDialog() {
    final colors = ref.read(themeProvider).colors;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.success.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle_rounded, color: colors.success, size: 48),
            ),
            const SizedBox(height: 20),
            Text(
              'Application Submitted!',
              style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              'Our team will review your application within 24-48 hours. '
              'You\'ll receive a notification once approved.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.isDark ? Colors.black : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
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
    final stepTitles = [
      'Personal Identity',
      'Proof of Address',
      'Financial Background',
      'Payment Methods',
      'Collateral & Terms',
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        title: Text(
          'Vendor Application',
          style: TextStyle(color: colors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        iconTheme: IconThemeData(color: colors.textPrimary),
        actions: [
          TextButton(
            onPressed: () async {
              final uri = Uri.parse('https://azaman.me/vendors');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: Text('Learn More', style: TextStyle(color: colors.accent, fontSize: 12)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Progress indicator
          _buildProgressBar(colors, stepTitles),

          // Step content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _buildStepContent(colors),
            ),
          ),

          // Bottom navigation
          _buildBottomNav(colors),
        ],
      ),
    );
  }


  Widget _buildProgressBar(AzamanColors colors, List<String> titles) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      child: Column(
        children: [
          // Step dots
          Row(
            children: List.generate(5, (i) {
              final isActive = i == _currentStep;
              final isDone = i < _currentStep;
              return Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 24, height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDone
                            ? colors.success
                            : isActive
                                ? colors.accent
                                : colors.divider,
                      ),
                      child: Center(
                        child: isDone
                            ? const Icon(Icons.check, color: Colors.white, size: 14)
                            : Text(
                                '${i + 1}',
                                style: TextStyle(
                                  color: isActive ? (colors.isDark ? Colors.black : Colors.white) : colors.textTertiary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                    if (i < 4)
                      Expanded(
                        child: Container(
                          height: 2,
                          color: i < _currentStep ? colors.success : colors.divider,
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Text(
            'Step ${_currentStep + 1}: ${titles[_currentStep]}',
            style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }


  Widget _buildStepContent(AzamanColors colors) {
    switch (_currentStep) {
      case 0: return _buildStep1Identity(colors);
      case 1: return _buildStep2Address(colors);
      case 2: return _buildStep3Financial(colors);
      case 3: return _buildStep4PaymentMethods(colors);
      case 4: return _buildStep5Terms(colors);
      default: return const SizedBox.shrink();
    }
  }

  Widget _buildBottomNav(AzamanColors colors) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: _prevStep,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colors.divider),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Back', style: TextStyle(color: colors.textSecondary, fontWeight: FontWeight.w600)),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _canProceed() && !_isSubmitting ? _nextStep : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accent,
                disabledBackgroundColor: colors.divider,
                foregroundColor: colors.isDark ? Colors.black : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSubmitting
                  ? SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.isDark ? Colors.black : Colors.white,
                      ),
                    )
                  : Text(
                      _currentStep == 4 ? 'Submit Application' : 'Continue',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
            ),
          ),
        ],
      ),
    );
  }


  // =========================================================================
  // STEP 1: Personal Identity
  // =========================================================================
  Widget _buildStep1Identity(AzamanColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(colors, 'Legal Full Name'),
        _textField(colors, _legalNameCtrl, 'As it appears on your ID', Icons.person_rounded),
        const SizedBox(height: 16),

        _sectionLabel(colors, 'Date of Birth'),
        _textField(colors, _dobCtrl, 'DD/MM/YYYY', Icons.calendar_today_rounded,
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: DateTime(2000, 1, 1),
              firstDate: DateTime(1940),
              lastDate: DateTime.now().subtract(const Duration(days: 6570)), // 18+
            );
            if (date != null) {
              _dobCtrl.text = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
              setState(() {});
            }
          },
        ),
        const SizedBox(height: 16),

        _sectionLabel(colors, 'Country of Residence'),
        _dropdown(colors, _selectedCountry, _countries, (v) => setState(() => _selectedCountry = v!)),
        const SizedBox(height: 16),

        _sectionLabel(colors, 'ID Type'),
        _dropdown(colors, _selectedIdType, _idTypes, (v) => setState(() => _selectedIdType = v!)),
        const SizedBox(height: 16),

        _sectionLabel(colors, 'Government ID — Front'),
        _imageUploadCard(colors, _idFront, 'id_front', 'Upload front of your ID'),
        const SizedBox(height: 12),

        _sectionLabel(colors, 'Government ID — Back (Optional)'),
        _imageUploadCard(colors, _idBack, 'id_back', 'Upload back of your ID'),
        const SizedBox(height: 12),

        _sectionLabel(colors, 'Selfie Holding Your ID'),
        _imageUploadCard(colors, _selfieWithId, 'selfie', 'Take a selfie holding your ID next to your face'),
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.warning.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.warning.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, color: colors.warning, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Ensure your face and all ID details are clearly visible. Blurry images will be rejected.',
                  style: TextStyle(color: colors.textSecondary, fontSize: 11, height: 1.3),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }


  // =========================================================================
  // STEP 2: Proof of Address
  // =========================================================================
  Widget _buildStep2Address(AzamanColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(colors, 'Proof of Address Document'),
        Text(
          'Upload a utility bill, bank statement, or government letter dated within the last 3 months.',
          style: TextStyle(color: colors.textTertiary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        _imageUploadCard(colors, _addressProof, 'address', 'Upload proof of address'),
        const SizedBox(height: 20),

        _sectionLabel(colors, 'Street Address'),
        _textField(colors, _streetCtrl, 'House number and street name', Icons.location_on_rounded),
        const SizedBox(height: 16),

        _sectionLabel(colors, 'City'),
        _textField(colors, _cityCtrl, 'City or town', Icons.location_city_rounded),
        const SizedBox(height: 16),

        _sectionLabel(colors, 'Region / State'),
        _textField(colors, _regionCtrl, 'Region or state', Icons.map_rounded),
        const SizedBox(height: 16),

        _sectionLabel(colors, 'Postal Code (Optional)'),
        _textField(colors, _postalCtrl, 'Postal / ZIP code', Icons.markunread_mailbox_rounded),
      ],
    );
  }


  // =========================================================================
  // STEP 3: Financial Background
  // =========================================================================
  Widget _buildStep3Financial(AzamanColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(colors, 'Source of Funds'),
        _dropdown(colors, _sourceOfFunds, _fundSources, (v) => setState(() => _sourceOfFunds = v!)),
        if (_sourceOfFunds == 'Other') ...[
          const SizedBox(height: 12),
          _textField(colors, _sourceOtherCtrl, 'Please explain', Icons.edit_rounded),
        ],
        const SizedBox(height: 20),

        _sectionLabel(colors, 'Expected Monthly Trading Volume'),
        _dropdown(colors, _monthlyVolume, _volumeRanges, (v) => setState(() => _monthlyVolume = v!)),
        const SizedBox(height: 20),

        _sectionLabel(colors, 'Previous P2P / Crypto Trading Experience'),
        SwitchListTile(
          value: _hasPreviousExperience,
          onChanged: (v) => setState(() => _hasPreviousExperience = v),
          title: Text(
            'I have traded crypto before',
            style: TextStyle(color: colors.textPrimary, fontSize: 14),
          ),
          activeColor: colors.accent,
          contentPadding: EdgeInsets.zero,
        ),
        if (_hasPreviousExperience) ...[
          _textField(
            colors, _previousPlatformsCtrl,
            'Which platforms? (e.g. Binance P2P, Paxful)',
            Icons.list_alt_rounded,
          ),
        ],
      ],
    );
  }


  // =========================================================================
  // STEP 4: Payment Methods (min 2 required)
  // =========================================================================
  Widget _buildStep4PaymentMethods(AzamanColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Add at least 2 payment methods you can receive payments through.',
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Text(
          '${_paymentMethods.length}/2 minimum added',
          style: TextStyle(
            color: _paymentMethods.length >= 2 ? colors.success : colors.warning,
            fontSize: 12, fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),

        // Added methods list
        ..._paymentMethods.asMap().entries.map((entry) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.divider),
          ),
          child: Row(
            children: [
              Icon(Icons.payment_rounded, color: colors.accent, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.value['type'] ?? '', style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(entry.value['details'] ?? '', style: TextStyle(color: colors.textTertiary, fontSize: 11)),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: colors.danger, size: 18),
                onPressed: () => setState(() => _paymentMethods.removeAt(entry.key)),
              ),
            ],
          ),
        )),

        const SizedBox(height: 12),

        // Add new method form
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.accent.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add Payment Method', style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              _textField(colors, _pmTypeCtrl, 'Type (e.g. MTN MoMo, CashApp, Bank)', Icons.category_rounded),
              const SizedBox(height: 10),
              _textField(colors, _pmDetailsCtrl, 'Account details (number/tag/email)', Icons.info_outline_rounded),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    if (_pmTypeCtrl.text.trim().isEmpty || _pmDetailsCtrl.text.trim().isEmpty) return;
                    setState(() {
                      _paymentMethods.add({
                        'type': _pmTypeCtrl.text.trim(),
                        'details': _pmDetailsCtrl.text.trim(),
                      });
                      _pmTypeCtrl.clear();
                      _pmDetailsCtrl.clear();
                    });
                    HapticFeedback.lightImpact();
                  },
                  icon: Icon(Icons.add_rounded, color: colors.accent, size: 18),
                  label: Text('Add', style: TextStyle(color: colors.accent)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colors.accent.withOpacity(0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }


  // =========================================================================
  // STEP 5: Collateral & Terms
  // =========================================================================
  Widget _buildStep5Terms(AzamanColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Collateral info card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.accent.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.accent.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.shield_rounded, color: colors.accent, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Collateral Requirement',
                      style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'A minimum of \$500 USDT will be locked as collateral during your active vendor period. '
                'This protects buyers and ensures you have skin in the game. '
                'Collateral is fully refundable if you choose to deactivate your vendor account.',
                style: TextStyle(color: colors.textSecondary, fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Required: ', style: TextStyle(color: colors.textTertiary, fontSize: 14)),
                    Text('\$500.00 USDT', style: TextStyle(color: colors.accent, fontSize: 18, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        _sectionLabel(colors, 'Vendor Agreement'),
        const SizedBox(height: 8),

        _checkboxTile(
          colors,
          'I accept the Vendor Terms & Conditions',
          'Including dispute resolution, no price manipulation, and account suspension rules.',
          _acceptedTerms,
          (v) => setState(() => _acceptedTerms = v ?? false),
        ),
        _checkboxTile(
          colors,
          'I understand the platform fee structure',
          'Margins, exit fees, and gas fee splitting as outlined in the vendor agreement.',
          _acceptedFees,
          (v) => setState(() => _acceptedFees = v ?? false),
        ),
        _checkboxTile(
          colors,
          'I commit to 5-minute response times',
          'Orders not accepted within 5 minutes may be auto-cancelled and affect my rating.',
          _acceptedResponseTime,
          (v) => setState(() => _acceptedResponseTime = v ?? false),
        ),

        const SizedBox(height: 16),

        // Website link reminder
        GestureDetector(
          onTap: () async {
            final uri = Uri.parse('https://azaman.me/vendors');
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          child: Row(
            children: [
              Icon(Icons.open_in_new_rounded, color: colors.accent, size: 16),
              const SizedBox(width: 8),
              Text(
                'Read full vendor agreement on azaman.me/vendors',
                style: TextStyle(color: colors.accent, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }


  // =========================================================================
  // SHARED WIDGETS
  // =========================================================================

  Widget _sectionLabel(AzamanColors colors, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _textField(
    AzamanColors colors,
    TextEditingController controller,
    String hint,
    IconData icon, {
    VoidCallback? onTap,
  }) {
    return TextField(
      controller: controller,
      readOnly: onTap != null,
      onTap: onTap,
      onChanged: (_) => setState(() {}),
      style: TextStyle(color: colors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: colors.textTertiary, fontSize: 13),
        prefixIcon: Icon(icon, color: colors.accent, size: 20),
        filled: true,
        fillColor: colors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.accent.withOpacity(0.5)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _dropdown(AzamanColors colors, String value, List<String> items, ValueChanged<String?> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        dropdownColor: colors.card,
        style: TextStyle(color: colors.textPrimary, fontSize: 14),
        decoration: const InputDecoration(border: InputBorder.none),
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: onChanged,
      ),
    );
  }


  Widget _imageUploadCard(AzamanColors colors, File? file, String target, String hint) {
    return GestureDetector(
      onTap: () => _pickImage(target),
      child: Container(
        height: file != null ? 180 : 100,
        width: double.infinity,
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: file != null ? colors.success.withOpacity(0.4) : colors.divider,
          ),
        ),
        child: file == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_rounded, color: colors.accent, size: 28),
                  const SizedBox(height: 8),
                  Text(hint, style: TextStyle(color: colors.textTertiary, fontSize: 12)),
                ],
              )
            : Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(file, width: double.infinity, height: 180, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 8, right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: colors.success,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, color: Colors.white, size: 14),
                    ),
                  ),
                  Positioned(
                    bottom: 8, right: 8,
                    child: GestureDetector(
                      onTap: () => _pickImage(target),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh_rounded, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text('Change', style: TextStyle(color: Colors.white, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _checkboxTile(
    AzamanColors colors,
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool?> onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: value ? colors.success.withOpacity(0.05) : colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value ? colors.success.withOpacity(0.3) : colors.divider,
        ),
      ),
      child: CheckboxListTile(
        value: value,
        onChanged: onChanged,
        activeColor: colors.success,
        title: Text(title, style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(color: colors.textTertiary, fontSize: 11)),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
    );
  }
}
