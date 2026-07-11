// =============================================================================
// PDF RECEIPT SERVICE  (2026-07-11)
//
// Generates a branded Azaman PDF receipt for:
//   • Ticket / Escrow deals  (generateTicketReceipt)
//   • P2P transfers          (generateTransferReceipt)
//
// Uses the `pdf` and `printing` packages (already in pubspec.yaml).
// Triggers the native share / print sheet so the user can save to Files,
// send to WhatsApp, or print directly — no extra permissions needed.
// =============================================================================

import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:azaman/services/ticket_service.dart';

class PdfReceiptService {
  PdfReceiptService._();
  static const PdfReceiptService instance = PdfReceiptService._();

  // ── Brand palette ──────────────────────────────────────────────────────────
  static final _gold = PdfColor(0.831373, 0.686275, 0.215686);
  static final _dark = PdfColor(0.054902, 0.066667, 0.086275);
  static final _darkMid = PdfColor(0.101961, 0.121569, 0.168627);
  static final _grey = PdfColor(0.541176, 0.560784, 0.619608);
  static final _white = PdfColors.white;
  static final _green = PdfColor(0.133333, 0.772549, 0.368627);
  static final _red = PdfColor(0.937255, 0.266667, 0.266667);
  static final _amber = PdfColor(0.960784, 0.619608, 0.043137);

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Share a ticket deal receipt (escrow + messages summary).
  Future<void> shareTicketReceipt({
    required Ticket ticket,
    required String myAzmId,
    required String peerAzmId,
    required String peerName,
    List<String> messagesSummary = const [],
  }) async {
    final bytes = await _buildTicketPdf(
      ticket: ticket,
      myAzmId: myAzmId,
      peerAzmId: peerAzmId,
      peerName: peerName,
      messagesSummary: messagesSummary,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'azaman-ticket-${ticket.id}.pdf',
    );
  }

  /// Share a simple transfer receipt.
  Future<void> shareTransferReceipt({
    required String referenceId,
    required double amount,
    required String currency,
    required String fromAzmId,
    required String toName,
    required String toAzmId,
    required DateTime timestamp,
    required bool completed,
    String? memo,
  }) async {
    final bytes = await _buildTransferPdf(
      referenceId: referenceId,
      amount: amount,
      currency: currency,
      fromAzmId: fromAzmId,
      toName: toName,
      toAzmId: toAzmId,
      timestamp: timestamp,
      completed: completed,
      memo: memo,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'azaman-receipt-$referenceId.pdf',
    );
  }

  // ── Builders ───────────────────────────────────────────────────────────────

  Future<Uint8List> _buildTicketPdf({
    required Ticket ticket,
    required String myAzmId,
    required String peerAzmId,
    required String peerName,
    required List<String> messagesSummary,
  }) async {
    final doc = pw.Document();
    final dateFmt = DateFormat('dd MMM yyyy, HH:mm');

    final statusColor = switch (ticket.status) {
      TicketStatus.open => _amber,
      TicketStatus.closed => _green,
      TicketStatus.cancelled => _red,
    };
    final statusLabel = switch (ticket.status) {
      TicketStatus.open => 'OPEN',
      TicketStatus.closed => 'COMPLETED',
      TicketStatus.cancelled => 'CANCELLED',
    };
    final typeLabel = switch (ticket.type) {
      TicketType.escrow => 'Escrow',
      TicketType.buy => 'Buy',
      TicketType.sell => 'Sell',
      TicketType.serviceSwap => 'Service Swap',
    };

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _header(statusColor, statusLabel),
            pw.SizedBox(height: 24),
            _sectionTitle('DEAL DETAILS'),
            pw.SizedBox(height: 8),
            _infoCard([
              _row('Ticket ID', '#${ticket.id}'),
              _row('Type', '$typeLabel Deal'),
              _row('Amount', '${ticket.targetAmount.toStringAsFixed(2)} ${ticket.targetCurrency}'),
              _row('Created', dateFmt.format(ticket.createdAt.toLocal())),
              if (ticket.closedAt != null)
                _row('Closed', dateFmt.format(ticket.closedAt!.toLocal())),
              if (ticket.memo != null && ticket.memo!.isNotEmpty)
                _row('Terms', ticket.memo!),
            ]),
            pw.SizedBox(height: 16),
            _sectionTitle('PARTIES'),
            pw.SizedBox(height: 8),
            _infoCard([
              _row('Initiator (You)', myAzmId),
              _row('Counterparty', '$peerName  ·  $peerAzmId'),
            ]),
            if (messagesSummary.isNotEmpty) ...[
              pw.SizedBox(height: 16),
              _sectionTitle('CONVERSATION LOG'),
              pw.SizedBox(height: 8),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: _darkMid,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: messagesSummary
                      .map((m) => pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(vertical: 3),
                            child: pw.Text(m,
                                style: pw.TextStyle(
                                  color: _white,
                                  fontSize: 9,
                                )),
                          ))
                      .toList(),
                ),
              ),
            ],
            pw.Spacer(),
            _footer(),
          ],
        ),
      ),
    );
    return doc.save();
  }

  Future<Uint8List> _buildTransferPdf({
    required String referenceId,
    required double amount,
    required String currency,
    required String fromAzmId,
    required String toName,
    required String toAzmId,
    required DateTime timestamp,
    required bool completed,
    String? memo,
  }) async {
    final doc = pw.Document();
    final dateFmt = DateFormat('dd MMM yyyy, HH:mm');

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _header(completed ? _green : _red, completed ? 'COMPLETED' : 'FAILED'),
            pw.SizedBox(height: 24),
            _sectionTitle('TRANSFER DETAILS'),
            pw.SizedBox(height: 8),
            _infoCard([
              _row('Reference', referenceId),
              _row('Amount', '${amount.toStringAsFixed(2)} $currency'),
              _row('Date & Time', dateFmt.format(timestamp.toLocal())),
              _row('From', fromAzmId),
              _row('To', '$toName  ·  $toAzmId'),
              if (memo != null && memo.isNotEmpty) _row('Note', memo),
            ]),
            pw.Spacer(),
            _footer(),
          ],
        ),
      ),
    );
    return doc.save();
  }

  // ── Shared sub-builders ────────────────────────────────────────────────────

  pw.Widget _header(PdfColor statusColor, String statusLabel) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        color: _dark,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: _gold, width: 0.8),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'AZAMAN',
                style: pw.TextStyle(
                  color: _gold,
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'OFFICIAL TRANSACTION RECEIPT',
                style: pw.TextStyle(color: _grey, fontSize: 9, letterSpacing: 1.5),
              ),
            ],
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: pw.BoxDecoration(
              color: statusColor,
              borderRadius: pw.BorderRadius.circular(20),
            ),
            child: pw.Text(
              statusLabel,
              style: pw.TextStyle(
                color: _dark,
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _sectionTitle(String title) => pw.Text(
        title,
        style: pw.TextStyle(
          color: _gold,
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 1.5,
        ),
      );

  pw.Widget _infoCard(List<pw.Widget> rows) => pw.Container(
        padding: const pw.EdgeInsets.all(16),
        decoration: pw.BoxDecoration(
          color: _darkMid,
          borderRadius: pw.BorderRadius.circular(10),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: rows,
        ),
      );

  pw.Widget _row(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 5),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 120,
              child: pw.Text(
                label,
                style: pw.TextStyle(color: _grey, fontSize: 9),
              ),
            ),
            pw.Expanded(
              child: pw.Text(
                value,
                style: pw.TextStyle(
                  color: _white,
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );

  pw.Widget _footer() => pw.Column(
        children: [
          pw.Divider(color: _grey, thickness: 0.3),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Azaman Financial Services  ·  azaman.app',
                style: pw.TextStyle(color: _grey, fontSize: 8),
              ),
              pw.Text(
                'Generated ${DateFormat('dd MMM yyyy').format(DateTime.now())}',
                style: pw.TextStyle(color: _grey, fontSize: 8),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              'This is an auto-generated document. Do not alter.',
              style: pw.TextStyle(color: _grey, fontSize: 7),
            ),
          ),
        ],
      );
}
