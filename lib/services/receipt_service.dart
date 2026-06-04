import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:azaman/services/api_client.dart';

// =============================================================================
// AZAMAN — RECEIPT SERVICE (Phase Q11-FE)
//
// Downloads PDF receipts from the backend and opens them with the system viewer.
// Endpoints:
//   GET /api/receipts/trade/:tradeId      — PDF for completed trade
//   GET /api/receipts/withdrawal/:id      — PDF for completed withdrawal
//
// Both require auth (JWT in header). Response is binary PDF with
// Content-Disposition: attachment.
// =============================================================================

class ReceiptService {
  /// Download a trade receipt PDF and open it with the system viewer.
  /// Returns the file path on success, or throws on failure.
  static Future<String> downloadTradeReceipt(String tradeId) async {
    return _downloadAndOpen(
      '/receipts/trade/$tradeId',
      'azaman-trade-receipt-$tradeId.pdf',
    );
  }

  /// Download a withdrawal receipt PDF and open it with the system viewer.
  /// Returns the file path on success, or throws on failure.
  static Future<String> downloadWithdrawalReceipt(String withdrawalId) async {
    return _downloadAndOpen(
      '/receipts/withdrawal/$withdrawalId',
      'azaman-withdrawal-receipt-$withdrawalId.pdf',
    );
  }

  /// Internal: fetch the PDF binary, save to temp dir, open with system viewer.
  static Future<String> _downloadAndOpen(String endpoint, String filename) async {
    // Use apiClient.get() which handles auth and headers automatically.
    // The response body will be binary PDF data.
    final response = await apiClient.get(endpoint);

    // Save PDF to temporary directory
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(response.bodyBytes);

    // Open with system PDF viewer
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      debugPrint('[ReceiptService] OpenFilex result: ${result.message}');
      // File was saved successfully even if viewer failed to open
    }

    return file.path;
  }
}
