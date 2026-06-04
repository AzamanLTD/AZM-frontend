import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/utils/biometric_gate.dart';
import 'package:azaman/widgets/slide_to_confirm.dart';

class UploadProofScreen extends ConsumerStatefulWidget {
  final String orderId;

  const UploadProofScreen({super.key, required this.orderId});

  @override
  ConsumerState<UploadProofScreen> createState() => _UploadProofScreenState();
}

class _UploadProofScreenState extends ConsumerState<UploadProofScreen> {
  File? _imageFile;
  bool _isUploading = false;
  // Phase H3 — slide-key so the gate's onCancelled path can re-arm the
  // thumb after a failed/cancelled biometric prompt.
  final GlobalKey<SlideToConfirmState> _slideKey =
      GlobalKey<SlideToConfirmState>();

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);

      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      _showError("Could not open gallery. Check permissions.");
    }
  }

  // --- THE FIX: Upgraded to read exact server error responses ---
  Future<void> _handleUploadAndNotify() async {
    if (_imageFile == null) return;

    setState(() => _isUploading = true);

    try {
      // 1. Prepare Multipart Request using ApiClient.baseUrl
      var request = http.MultipartRequest(
        'POST', 
        Uri.parse('${ApiClient.baseUrl}/trades/upload-proof')
      );

      request.fields['tradeId'] = widget.orderId.replaceAll('#', '');
      request.files.add(await http.MultipartFile.fromPath('proof', _imageFile!.path));

      // 2. Send via apiClient (handles auth headers automatically)
      var response = await apiClient.multipart('/trades/upload-proof', request);

      if (response.statusCode == 200) {
        if (mounted) _showCompletionDialog();
      } else {
        // This will print the exact reason the server rejected it!
        debugPrint("SERVER REJECTED UPLOAD: ${response.body}");
        _showError("Upload failed: ${response.body}");
      }
    } catch (e) {
      _showError("Connection error. Try again.");
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    }
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ReleaseTimerDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Text("Order ${widget.orderId}", style: TextStyle(fontSize: 14, color: colors.textPrimary)),
        iconTheme: IconThemeData(color: colors.textPrimary),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text("Upload Proof", style: TextStyle(color: colors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 30),
            Stack(
              children: [
                GestureDetector(
                  onTap: _imageFile != null ? null : _pickImage,
                  child: Container(
                    height: 280,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _imageFile != null ? colors.accent : colors.textTertiary.withOpacity(0.3)),
                    ),
                    child: _imageFile == null
                        ? Center(child: Icon(Icons.add_a_photo, color: colors.accent, size: 40))
                        : ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(_imageFile!, fit: BoxFit.cover)),
                  ),
                ),
                if (_imageFile != null) Positioned(top: 10, right: 10, child: _buildRetakeButton(colors)),
              ],
            ),
            const Spacer(),
            // Phase H3 — slide-to-confirm + biometric pre-gate. The
            // "I HAVE PAID" gesture is the buyer's irreversible commitment
            // that funds have left their account; from the vendor's side it
            // unlocks the Release-crypto button. We swap the ElevatedButton
            // for SlideToConfirm so a reflex tap can't accidentally fire it,
            // then biometric-gate the slide for the same reason the vendor's
            // release is gated. The `enabled` prop makes the slider behave
            // like `ElevatedButton(onPressed: null)` when there's no image
            // yet — drags are rejected, so the user can't lock the slider
            // into _confirmed=true and then be stuck.
            SlideToConfirm(
              key: _slideKey,
              text: _imageFile == null
                  ? 'Take a photo to continue'
                  : 'Slide to notify seller',
              backgroundColor: colors.card,
              thumbColor: _imageFile == null
                  ? colors.textTertiary
                  : colors.accent,
              isLoading: _isUploading,
              enabled: _imageFile != null && !_isUploading,
              onConfirmed: () {
                AzamanBiometricGate.runSync(
                  context,
                  () {
                    AzamanHaptics.commit();
                    _handleUploadAndNotify();
                  },
                  reason: 'Authenticate to mark trade as paid',
                  onCancelled: () => _slideKey.currentState?.reset(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRetakeButton(AzamanColors colors) {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.sync, color: colors.textPrimary, size: 14), Text(" Change", style: TextStyle(color: colors.textPrimary, fontSize: 12))]),
      ),
    );
  }
}

// --- RELEASE TIMER DIALOG ---
//
// Phase H4 fix: was a plain StatefulWidget that referenced `ref.read(themeProvider)`
// in its build method, which couldn't compile (no ref in scope). Promoted to a
// ConsumerStatefulWidget so it can pull `AzamanColors` from the active theme,
// honoring the soul-doc rule that every UI surface references `AzamanColors`
// instead of hardcoded hex values.
class _ReleaseTimerDialog extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ReleaseTimerDialog> createState() => _ReleaseTimerDialogState();
}

class _ReleaseTimerDialogState extends ConsumerState<_ReleaseTimerDialog> {
  int _secondsRemaining = 300; 
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        if (_secondsRemaining > 0) {
          setState(() => _secondsRemaining--);
        } else {
          _timer?.cancel();
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String minutes = (_secondsRemaining ~/ 60).toString().padLeft(2, '0');
    String seconds = (_secondsRemaining % 60).toString().padLeft(2, '0');
    final colors = ref.watch(themeProvider).colors;

    return AlertDialog(
      backgroundColor: colors.card,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hourglass_bottom, color: colors.accent, size: 50),
          const SizedBox(height: 20),
          Text("Awaiting Vendor Release", style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text("$minutes:$seconds", style: TextStyle(color: colors.accent, fontSize: 32, fontWeight: FontWeight.bold)),
          Text("Average release time: 04:30", style: TextStyle(color: colors.textTertiary, fontSize: 11)),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: colors.accent),
            onPressed: () {
                // When they click close, pop back all the way to the dashboard
                Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text("CLOSE", style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

}
