import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Vendor live-presence state. When `isOnline` flips, the marketplace updates
/// in real-time for every viewer.
class VendorProvider with ChangeNotifier {
  bool _isOnline = false;
  bool get isOnline => _isOnline;

  void toggleStatus() {
    _isOnline = !_isOnline;
    notifyListeners();
  }
}

// =============================================================================
// RIVERPOD HANDLE  (canonical V2 access path)
//
// Read in NEW code via:
//   final isOnline = ref.watch(vendorProvider).isOnline;
//   ref.read(vendorProvider).toggleStatus();
//
// Granular read so only the dot/text repaints when status flips:
//   final online = ref.watch(vendorProvider.select((v) => v.isOnline));
// =============================================================================
final vendorProvider = ChangeNotifierProvider<VendorProvider>((ref) {
  return VendorProvider();
});
