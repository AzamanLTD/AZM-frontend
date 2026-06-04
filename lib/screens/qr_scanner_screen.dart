// =============================================================================
// AZAMAN — QR SCANNER SCREEN
//
// Camera-based QR code scanner for adding friends. Scans azaman://user/{username}
// deep links from other users' Share Profile QR codes.
//
// Flow:
//   1. Opens camera with QR scanner overlay
//   2. Detects QR → parses azaman://user/{username}
//   3. Searches user via GET /friends/search?q={username}
//   4. Shows confirmation bottom sheet with user details
//   5. Sends friend request on confirm
//
// Accessible from:
//   - ShareProfileScreen (future "Scan" tab)
//   - Settings drawer QR button (long-press or second tap)
// =============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';

class QrScannerScreen extends ConsumerStatefulWidget {
  const QrScannerScreen({super.key});

  @override
  ConsumerState<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends ConsumerState<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool _isProcessing = false;
  String? _lastScanned;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final rawValue = barcode.rawValue!;

    // Prevent duplicate processing of same code
    if (rawValue == _lastScanned) return;
    _lastScanned = rawValue;

    // Parse azaman://user/{username}
    final username = _parseAzamanUri(rawValue);
    if (username == null) {
      _showSnack('Invalid QR code. Expected an Azaman profile QR.');
      // Reset after 2s to allow re-scanning
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _lastScanned = null;
      });
      return;
    }

    // Check not scanning own QR
    final myUsername = ref.read(authProvider).user?.username;
    if (username == myUsername) {
      _showSnack("That's your own QR code!");
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _lastScanned = null;
      });
      return;
    }

    setState(() => _isProcessing = true);
    _controller.stop();
    _searchAndConfirm(username);
  }

  /// Parse azaman://user/{username} URI. Returns username or null.
  String? _parseAzamanUri(String raw) {
    // Support both azaman://user/username and plain @username
    if (raw.startsWith('azaman://user/')) {
      final username = raw.substring('azaman://user/'.length).trim();
      return username.isNotEmpty ? username : null;
    }
    // Fallback: if raw is just a username (no URI), accept it
    if (raw.startsWith('@')) {
      return raw.substring(1).trim();
    }
    return null;
  }

  Future<void> _searchAndConfirm(String username) async {
    final colors = ref.read(themeProvider).colors;

    try {
      final response = await apiClient.get('/friends/search?q=$username');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final users = List<Map<String, dynamic>>.from(data['users'] ?? []);

        // Find exact match
        final match = users.firstWhere(
          (u) => (u['username'] as String?)?.toLowerCase() == username.toLowerCase(),
          orElse: () => <String, dynamic>{},
        );

        if (match.isEmpty) {
          _showSnack('User @$username not found.');
          _resetScanner();
          return;
        }

        if (!mounted) return;

        // Show confirmation bottom sheet
        final confirmed = await _showConfirmSheet(match, colors);
        if (confirmed == true) {
          await _sendFriendRequest(match, colors);
        } else {
          _resetScanner();
        }
      } else {
        _showSnack('Failed to search user. Try again.');
        _resetScanner();
      }
    } catch (e) {
      _showSnack('Network error. Please try again.');
      _resetScanner();
    }
  }

  Future<bool?> _showConfirmSheet(Map<String, dynamic> user, AzamanColors colors) {
    final username = user['username'] ?? 'Unknown';
    final userId = user['id'];
    final tradesCompleted = user['tradesCompleted'] ?? 0;

    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: colors.accent.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  username[0].toUpperCase(),
                  style: TextStyle(color: colors.accent, fontSize: 26, fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '@$username',
              style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '$tradesCompleted trades completed',
              style: TextStyle(color: colors.textTertiary, fontSize: 12),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.isDark ? Colors.black : Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text('Send Friend Request', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: colors.textTertiary)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendFriendRequest(Map<String, dynamic> user, AzamanColors colors) async {
    final userId = user['id'];
    if (userId == null) {
      _showSnack('Invalid user data.');
      _resetScanner();
      return;
    }

    try {
      final response = await apiClient.post('/friends/request', {
        'addresseeId': userId is int ? userId : int.tryParse(userId.toString()) ?? 0,
        'message': 'Added via QR scan',
      });

      if (response.statusCode == 200 || response.statusCode == 201) {
        HapticFeedback.heavyImpact();
        _showSnack('Friend request sent to @${user['username']}!', isSuccess: true);
        // Close scanner after success
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) Navigator.pop(context);
      } else {
        final body = jsonDecode(response.body);
        _showSnack(body['message'] ?? 'Failed to send request.');
        _resetScanner();
      }
    } catch (e) {
      _showSnack('Network error sending request.');
      _resetScanner();
    }
  }

  void _resetScanner() {
    if (mounted) {
      setState(() {
        _isProcessing = false;
        _lastScanned = null;
      });
      _controller.start();
    }
  }

  void _showSnack(String msg, {bool isSuccess = false}) {
    if (!mounted) return;
    final colors = ref.read(themeProvider).colors;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isSuccess ? colors.success : colors.danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(
          'Scan QR Code',
          style: TextStyle(color: colors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on_rounded, color: Colors.white70),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera feed
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // Overlay with cutout
          _ScannerOverlay(colors: colors),

          // Bottom hint
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _isProcessing ? 'Processing...' : 'Point camera at an Azaman QR code',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Scanner overlay with transparent cutout in the center
class _ScannerOverlay extends StatelessWidget {
  final AzamanColors colors;
  const _ScannerOverlay({required this.colors});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scanAreaSize = constraints.maxWidth * 0.7;
        final top = (constraints.maxHeight - scanAreaSize) / 2 - 40;
        final left = (constraints.maxWidth - scanAreaSize) / 2;

        return Stack(
          children: [
            // Dark overlay
            ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Colors.black54,
                BlendMode.srcOut,
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  Positioned(
                    top: top,
                    left: left,
                    child: Container(
                      width: scanAreaSize,
                      height: scanAreaSize,
                      decoration: BoxDecoration(
                        color: Colors.red, // Any color — will be cut out
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Corner accents
            Positioned(
              top: top,
              left: left,
              child: _CornerAccent(color: colors.accent, position: _Corner.topLeft),
            ),
            Positioned(
              top: top,
              right: left,
              child: _CornerAccent(color: colors.accent, position: _Corner.topRight),
            ),
            Positioned(
              bottom: constraints.maxHeight - top - scanAreaSize,
              left: left,
              child: _CornerAccent(color: colors.accent, position: _Corner.bottomLeft),
            ),
            Positioned(
              bottom: constraints.maxHeight - top - scanAreaSize,
              right: left,
              child: _CornerAccent(color: colors.accent, position: _Corner.bottomRight),
            ),
          ],
        );
      },
    );
  }
}

enum _Corner { topLeft, topRight, bottomLeft, bottomRight }

class _CornerAccent extends StatelessWidget {
  final Color color;
  final _Corner position;
  const _CornerAccent({required this.color, required this.position});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 30,
      child: CustomPaint(
        painter: _CornerPainter(color: color, position: position),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final _Corner position;
  _CornerPainter({required this.color, required this.position});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    switch (position) {
      case _Corner.topLeft:
        path.moveTo(0, size.height * 0.6);
        path.lineTo(0, 4);
        path.quadraticBezierTo(0, 0, 4, 0);
        path.lineTo(size.width * 0.6, 0);
        break;
      case _Corner.topRight:
        path.moveTo(size.width * 0.4, 0);
        path.lineTo(size.width - 4, 0);
        path.quadraticBezierTo(size.width, 0, size.width, 4);
        path.lineTo(size.width, size.height * 0.6);
        break;
      case _Corner.bottomLeft:
        path.moveTo(0, size.height * 0.4);
        path.lineTo(0, size.height - 4);
        path.quadraticBezierTo(0, size.height, 4, size.height);
        path.lineTo(size.width * 0.6, size.height);
        break;
      case _Corner.bottomRight:
        path.moveTo(size.width * 0.4, size.height);
        path.lineTo(size.width - 4, size.height);
        path.quadraticBezierTo(size.width, size.height, size.width, size.height - 4);
        path.lineTo(size.width, size.height * 0.4);
        break;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
