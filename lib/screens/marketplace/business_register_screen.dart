// =============================================================================
// BUSINESS REGISTER SCREEN — Flutter V3 Marketplace Sprint (2026-06-21)
//
// One-time registration form for creating a BusinessProfile: name, category,
// description, website, contact email, phone, address, country and an optional
// logo (image_picker → BusinessService.uploadBusinessImage → logoUrl). On success it seeds
// myBusinessProvider and lands the user on their new business profile.
//
// Guard: if the user already has a business, this screen redirects to its
// profile instead of letting them register twice.
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:image_picker/image_picker.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/business_profile_screen.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/utils/azaman_haptics.dart';

// A focused set of country codes (ISO 3166-1 alpha-2). Extend as needed.
const _kCountries = <String, String>{
  'GH': 'Ghana',
  'NG': 'Nigeria',
  'KE': 'Kenya',
  'ZA': 'South Africa',
  'TZ': 'Tanzania',
  'UG': 'Uganda',
  'RW': 'Rwanda',
  'CI': 'Côte d\'Ivoire',
  'SN': 'Senegal',
  'CM': 'Cameroon',
  'EG': 'Egypt',
  'US': 'United States',
  'GB': 'United Kingdom',
  'CA': 'Canada',
  'IN': 'India',
};

class BusinessRegisterScreen extends ConsumerStatefulWidget {
  const BusinessRegisterScreen({super.key});

  @override
  ConsumerState<BusinessRegisterScreen> createState() =>
      _BusinessRegisterScreenState();
}

class _BusinessRegisterScreenState
    extends ConsumerState<BusinessRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  // Type-specific controllers
  final _vehicleTypeCtrl = TextEditingController();
  final _vehiclePlateCtrl = TextEditingController();
  final _routeInfoCtrl = TextEditingController();
  final _cuisineTypeCtrl = TextEditingController();
  final _diningStyleCtrl = TextEditingController();
  final _openingHoursCtrl = TextEditingController();
  final _roomTypesCtrl = TextEditingController();
  final _amenitiesCtrl = TextEditingController();
  final _checkInTimeCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  String _category = BusinessCategories.values.first.wire;
  String _country = 'GH';
  String? _logoUrl;
  File? _logoFile;
  bool _uploadingLogo = false;
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _websiteCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    
    _vehicleTypeCtrl.dispose();
    _vehiclePlateCtrl.dispose();
    _routeInfoCtrl.dispose();
    _cuisineTypeCtrl.dispose();
    _diningStyleCtrl.dispose();
    _openingHoursCtrl.dispose();
    _roomTypesCtrl.dispose();
    _amenitiesCtrl.dispose();
    _checkInTimeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() {
      _logoFile = File(picked.path);
      _uploadingLogo = true;
    });
    try {
      final url = await BusinessService().uploadBusinessImage(
        File(picked.path),
        folder: 'logos',
      );
      if (!mounted) return;
      setState(() {
        _logoUrl = url;
        _uploadingLogo = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingLogo = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Logo upload failed: $e'),
        backgroundColor: ref.read(themeProvider).colors.danger,
      ));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final data = <String, dynamic>{
        'businessName': _nameCtrl.text.trim(),
        'category': _category,
        'country': _country,
        if (_descCtrl.text.trim().isNotEmpty)
          'description': _descCtrl.text.trim(),
        if (_websiteCtrl.text.trim().isNotEmpty)
          'website': _websiteCtrl.text.trim(),
        if (_emailCtrl.text.trim().isNotEmpty)
          'contactEmail': _emailCtrl.text.trim(),
        if (_phoneCtrl.text.trim().isNotEmpty)
          'phoneNumber': _phoneCtrl.text.trim(),
        if (_addressCtrl.text.trim().isNotEmpty)
          'address': _addressCtrl.text.trim(),
        if (_logoUrl != null) 'logoUrl': _logoUrl,
      };
      final profile = await BusinessService().registerBusiness(data);
      if (!mounted) return;
      ref.read(myBusinessProvider.notifier).setProfile(profile);
      AzamanHaptics.commit();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Business registered! BIZ ID: ${profile.bizId}'),
        behavior: SnackBarBehavior.floating,
      ));
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => BusinessProfileScreen(bizId: profile.bizId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Registration failed: $e'),
        backgroundColor: ref.read(themeProvider).colors.danger,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final existing = ref.watch(myBusinessProvider).profile;

    // Guard — already registered → push them to their profile.
    if (existing != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => BusinessProfileScreen(bizId: existing.bizId),
            ),
          );
        }
      });
      return Scaffold(
        backgroundColor: colors.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
        title: Text('Register Business',
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(child: _logoPicker(colors)),
            const SizedBox(height: 20),
            _field(colors, _nameCtrl, 'Business name', required: true,
                validator: (v) {
              final t = (v ?? '').trim();
              if (t.length < 2) return 'At least 2 characters';
              if (t.length > 100) return 'Max 100 characters';
              return null;
            }),
            const SizedBox(height: 12),
            _categorySelector(colors),
            const SizedBox(height: 12),
            _typeSpecificFields(colors),
            const SizedBox(height: 12),
            _field(colors, _descCtrl, 'Description (optional)',
                maxLines: 3, maxLength: 500),
            const SizedBox(height: 12),
            _field(colors, _websiteCtrl, 'Website (optional)',
                keyboardType: TextInputType.url),
            const SizedBox(height: 12),
            _field(colors, _emailCtrl, 'Contact email (optional)',
                keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 12),
            _field(colors, _phoneCtrl, 'Phone number (optional)',
                keyboardType: TextInputType.phone),
            const SizedBox(height: 12),
            _field(colors, _addressCtrl, 'Address (optional)'),
            const SizedBox(height: 12),
            _countryDropdown(colors),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.isDark ? Colors.black : Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Create Business',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _logoPicker(AzamanColors colors) {
    return GestureDetector(
      onTap: _uploadingLogo ? null : _pickLogo,
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: colors.card,
          shape: BoxShape.circle,
          border: Border.all(color: colors.divider),
          image: _logoFile != null
              ? DecorationImage(
                  image: FileImage(_logoFile!), fit: BoxFit.cover)
              : null,
        ),
        alignment: Alignment.center,
        child: _uploadingLogo
            ? const CircularProgressIndicator(strokeWidth: 2)
            : (_logoFile == null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.camera_alt_outlined,
                          color: colors.textTertiary, size: 24),
                      const SizedBox(height: 4),
                      Text('Logo',
                          style: TextStyle(
                              color: colors.textTertiary, fontSize: 11)),
                    ],
                  )
                : null),
      ),
    );
  }

  Widget _categorySelector(AzamanColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Business Type',
            style: TextStyle(
                color: colors.textTertiary,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        // Primary categories — large cards
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: BusinessCategories.primary.map((cat) {
            final selected = _category == cat.wire;
            return GestureDetector(
              onTap: () => setState(() => _category = cat.wire),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: selected
                      ? cat.color.withOpacity(0.12)
                      : colors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected
                        ? cat.color.withOpacity(0.5)
                        : colors.divider,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(cat.icon,
                        size: 20,
                        color: selected ? cat.color : colors.textSecondary),
                    const SizedBox(width: 8),
                    Text(cat.label,
                        style: TextStyle(
                            color: selected
                                ? cat.color
                                : colors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        // Secondary categories — compact dropdown
        DropdownButtonFormField<String>(
          value: BusinessCategories.secondary.any((c) => c.wire == _category)
              ? _category
              : null,
          isExpanded: true,
          dropdownColor: colors.card,
          hint: Text('Or select another category',
              style: TextStyle(color: colors.textTertiary, fontSize: 13)),
          decoration: _decoration(colors, 'Other Categories'),
          items: BusinessCategories.secondary
              .map((c) => DropdownMenuItem(
                    value: c.wire,
                    child: Row(children: [
                      Icon(c.icon, size: 18, color: c.color),
                      const SizedBox(width: 8),
                      Text(c.label,
                          style: TextStyle(color: colors.textPrimary)),
                    ]),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) setState(() => _category = v);
          },
        ),
      ],
    );
  }

  Widget _typeSpecificFields(AzamanColors colors) {
    final cat = BusinessCategories.fromWire(_category);

    // TRANSIT — vehicle & route info
    if (_category == 'LOGISTICS') {
      return Column(
        children: [
          const SizedBox(height: 12),
          _field(colors, _vehicleTypeCtrl, 'Vehicle Type (e.g. Bus, Minivan)'),
          const SizedBox(height: 12),
          _field(colors, _vehiclePlateCtrl, 'Vehicle Plate (optional)'),
          const SizedBox(height: 12),
          _field(colors, _routeInfoCtrl, 'Primary Route (e.g. Accra - Kumasi)',
              maxLines: 2),
        ],
      );
    }

    // RESTAURANTS — cuisine & dining info
    if (_category == 'FOOD_BEVERAGE') {
      return Column(
        children: [
          const SizedBox(height: 12),
          _field(colors, _cuisineTypeCtrl, 'Cuisine Type (e.g. Ghanaian, Continental)'),
          const SizedBox(height: 12),
          _field(colors, _diningStyleCtrl, 'Dining Style (e.g. Fine Dining, Casual)',
              maxLines: 2),
          const SizedBox(height: 12),
          _field(colors, _openingHoursCtrl, 'Opening Hours (e.g. 8AM - 10PM)'),
        ],
      );
    }

    // HOTELS — room & amenity info
    if (_category == 'REAL_ESTATE') {
      return Column(
        children: [
          const SizedBox(height: 12),
          _field(colors, _roomTypesCtrl, 'Room Types (e.g. Single, Double, Suite)',
              maxLines: 2),
          const SizedBox(height: 12),
          _field(colors, _amenitiesCtrl, 'Amenities (e.g. WiFi, Pool, AC)',
              maxLines: 2),
          const SizedBox(height: 12),
          _field(colors, _checkInTimeCtrl, 'Check-in Time (e.g. 2PM)'),
        ],
      );
    }

    // No type-specific fields for other categories
    return const SizedBox.shrink();
  }

  Widget _countryDropdown(AzamanColors colors) {
    return DropdownButtonFormField<String>(
      value: _country,
      isExpanded: true,
      dropdownColor: colors.card,
      decoration: _decoration(colors, 'Country'),
      items: _kCountries.entries
          .map((e) => DropdownMenuItem(
                value: e.key,
                child: Text('${e.value} (${e.key})',
                    style: TextStyle(color: colors.textPrimary)),
              ))
          .toList(),
      onChanged: (v) {
        if (v != null) setState(() => _country = v);
      },
    );
  }

  Widget _field(
    AzamanColors colors,
    TextEditingController ctrl,
    String label, {
    bool required = false,
    int maxLines = 1,
    int? maxLength,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      style: TextStyle(color: colors.textPrimary),
      decoration: _decoration(colors, label).copyWith(counterText: ''),
      validator: validator ??
          (required
              ? (v) => (v ?? '').trim().isEmpty ? 'Required' : null
              : null),
    );
  }

  InputDecoration _decoration(AzamanColors colors, String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: colors.textTertiary, fontSize: 14),
      filled: true,
      fillColor: colors.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.accent, width: 1.2),
      ),
    );
  }
}
