import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';

class KycVerificationScreen extends ConsumerStatefulWidget {
  const KycVerificationScreen({super.key});

  @override
  ConsumerState<KycVerificationScreen> createState() => _KycVerificationScreenState();
}

class _KycVerificationScreenState extends ConsumerState<KycVerificationScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _idNumberController = TextEditingController();

  String _selectedIdType = 'National ID';
  final List<String> _idTypes = ['National ID', 'Passport', 'Driver\'s License'];

  File? _frontImage;
  File? _backImage;
  bool _isLoading = false;
  bool _isSuccess = false;

  // Current KYC status fetched from backend
  String? _currentStatus;
  bool _isCheckingStatus = true;

  final ImagePicker _picker = ImagePicker();
  final ApiClient _apiClient = ApiClient();

  @override
  void initState() {
    super.initState();
    _checkKycStatus();
  }

  Future<void> _checkKycStatus() async {
    try {
      final response = await _apiClient.get('/kyc/status');

      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body);
        setState(() {
          _currentStatus = data['kyc']?['kycStatus'];
          _isCheckingStatus = false;
        });
      } else {
        if (mounted) setState(() => _isCheckingStatus = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isCheckingStatus = false);
    }
  }

  Future<void> _pickImage(bool isFront) async {
    HapticFeedback.lightImpact();

    final colors = ref.read(themeProvider).colors;

    // Let user choose camera or gallery
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Select Image Source", style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _sourceOption(colors, Icons.camera_alt_rounded, "Camera", () => Navigator.pop(ctx, ImageSource.camera)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _sourceOption(colors, Icons.photo_library_rounded, "Gallery", () => Navigator.pop(ctx, ImageSource.gallery)),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (source == null) return;

    final XFile? pickedFile = await _picker.pickImage(source: source, imageQuality: 80);
    if (pickedFile != null && mounted) {
      setState(() {
        if (isFront) {
          _frontImage = File(pickedFile.path);
        } else {
          _backImage = File(pickedFile.path);
        }
      });
    }
  }

  Widget _sourceOption(AzamanColors colors, IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.divider),
        ),
        child: Column(
          children: [
            Icon(icon, color: colors.accent, size: 32),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Future<void> _submitKyc() async {
    final colors = ref.read(themeProvider).colors;

    if (_nameController.text.trim().isEmpty || _idNumberController.text.trim().isEmpty) {
      _showSnack("Please fill in all text fields.", colors.danger);
      return;
    }
    if (_frontImage == null) {
      _showSnack("Please upload the front of your ID.", colors.danger);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final uri = Uri.parse('${ApiClient.baseUrl}/kyc/submit');

      var request = http.MultipartRequest('POST', uri);

      request.fields['legalName'] = _nameController.text.trim();
      request.fields['idType'] = _selectedIdType;
      request.fields['idNumber'] = _idNumberController.text.trim();

      request.files.add(await http.MultipartFile.fromPath('idImages', _frontImage!.path));
      if (_backImage != null) {
        request.files.add(await http.MultipartFile.fromPath('idImages', _backImage!.path));
      }

      final response = await _apiClient.multipart('/kyc/submit', request);

      if (response.statusCode == 200) {
        HapticFeedback.heavyImpact();
        if (mounted) setState(() => _isSuccess = true);
      } else {
        final resData = jsonDecode(response.body);
        _showSnack(resData['message'] ?? "Upload failed.", colors.danger);
      }
    } catch (e) {
      _showSnack("Network Error. Please check your connection.", colors.danger);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg, Color bg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: bg, behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _idNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        title: Text("Identity Verification", style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
        centerTitle: true,
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      body: _isCheckingStatus
          ? Center(child: CircularProgressIndicator(color: colors.accent))
          : _buildBody(colors),
    );
  }

  Widget _buildBody(AzamanColors colors) {
    // If already verified
    if (_currentStatus == 'VERIFIED') return _buildStatusView(colors, "Verified", Icons.verified_user, colors.success, "Your identity has been verified. You have full Vendor access.");
    // If pending review
    if (_currentStatus == 'PENDING' && !_isSuccess) return _buildStatusView(colors, "Under Review", Icons.hourglass_top_rounded, colors.warning, "Your documents are being reviewed by our compliance team. You will be notified once approved.");
    // If just submitted
    if (_isSuccess) return _buildSuccessState(colors);
    // If rejected, allow resubmission
    if (_currentStatus == 'REJECTED') {
      return _buildFormState(colors, showRejectionBanner: true);
    }
    // Default: UNVERIFIED - show form
    return _buildFormState(colors);
  }

  Widget _buildStatusView(AzamanColors colors, String title, IconData icon, Color statusColor, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: statusColor.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: statusColor, size: 56),
            ),
            const SizedBox(height: 24),
            Text(title, style: TextStyle(color: colors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: colors.textSecondary, fontSize: 14, height: 1.5)),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.card,
                  foregroundColor: colors.textPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text("RETURN", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormState(AzamanColors colors, {bool showRejectionBanner = false}) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showRejectionBanner) ...[
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: colors.danger.withOpacity(0.05),
                border: Border.all(color: colors.danger.withOpacity(0.2)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: colors.danger, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text("Previous Submission Rejected", style: TextStyle(color: colors.danger, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text("Please resubmit with clearer documents.", style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                    ]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Security header
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: colors.success.withOpacity(0.05),
              border: Border.all(color: colors.success.withOpacity(0.2)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_person, color: colors.success, size: 30),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("Become a Verified Vendor", style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text("Verify your identity to unlock vendor privileges and higher trading limits.",
                        style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                  ]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),

          // Legal info section
          Text("LEGAL INFORMATION", style: TextStyle(color: colors.textTertiary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 15),
          _buildTextField(colors, "Full Legal Name", _nameController, Icons.person_outline),
          const SizedBox(height: 15),
          _buildDropdownField(colors),
          const SizedBox(height: 15),
          _buildTextField(colors, "ID Number", _idNumberController, Icons.badge_outlined),

          const SizedBox(height: 30),

          // Document upload section
          Text("DOCUMENT UPLOAD", style: TextStyle(color: colors.textTertiary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(child: _buildImageUploader(colors, "Front of ID", _frontImage, true)),
              const SizedBox(width: 15),
              Expanded(child: _buildImageUploader(colors, "Back of ID", _backImage, false)),
            ],
          ),

          const SizedBox(height: 40),

          // Submit button
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.isDark ? Colors.black : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              onPressed: _isLoading ? null : _submitKyc,
              child: _isLoading
                  ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: colors.isDark ? Colors.black : Colors.white, strokeWidth: 2))
                  : const Text("SUBMIT DOCUMENTS", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1, fontSize: 15)),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text("Your data is encrypted and stored securely.", style: TextStyle(color: colors.textTertiary, fontSize: 11)),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildTextField(AzamanColors colors, String hint, TextEditingController controller, IconData icon) {
    return TextField(
      controller: controller,
      style: TextStyle(color: colors.textPrimary),
      decoration: InputDecoration(
        filled: true,
        fillColor: colors.card,
        prefixIcon: Icon(icon, color: colors.textTertiary),
        hintText: hint,
        hintStyle: TextStyle(color: colors.textTertiary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: colors.accent.withOpacity(0.5))),
      ),
    );
  }

  Widget _buildDropdownField(AzamanColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(14)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedIdType,
          dropdownColor: colors.card,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down, color: colors.textTertiary),
          style: TextStyle(color: colors.textPrimary, fontSize: 15),
          items: _idTypes.map((type) {
            return DropdownMenuItem<String>(
              value: type,
              child: Row(children: [
                Icon(Icons.credit_card, color: colors.textTertiary, size: 20),
                const SizedBox(width: 10),
                Text(type),
              ]),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) setState(() => _selectedIdType = val);
          },
        ),
      ),
    );
  }

  Widget _buildImageUploader(AzamanColors colors, String label, File? image, bool isFront) {
    final bool hasImage = image != null;
    return GestureDetector(
      onTap: () => _pickImage(isFront),
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasImage ? colors.success : colors.divider,
            width: hasImage ? 2 : 1,
          ),
        ),
        child: hasImage
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(image, fit: BoxFit.cover),
                    Container(color: colors.background.withOpacity(0.3)),
                    Center(child: Icon(Icons.check_circle, color: colors.success, size: 35)),
                  ],
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_outlined, color: colors.accent.withOpacity(0.7), size: 30),
                  const SizedBox(height: 10),
                  Text(label, style: TextStyle(color: colors.textTertiary, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
      ),
    );
  }

  Widget _buildSuccessState(AzamanColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: colors.success.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(Icons.how_to_reg, color: colors.success, size: 56),
            ),
            const SizedBox(height: 24),
            Text("Under Review", style: TextStyle(color: colors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(
              "Your documents have been submitted securely. Our compliance team will review them shortly. You will be notified once approved.",
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.card,
                  foregroundColor: colors.textPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text("RETURN TO SETTINGS", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
