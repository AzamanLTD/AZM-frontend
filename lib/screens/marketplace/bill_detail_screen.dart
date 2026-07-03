import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// §37 — BillDetailScreen: Customer confirms a finalized dine-in bill.
/// Shows line items, subtotal, tax, tip, and grand total.
/// Customer can confirm (triggers escrow) or dispute.
class BillDetailScreen extends ConsumerStatefulWidget {
  final String tabId;
  const BillDetailScreen({super.key, required this.tabId});

  @override
  ConsumerState<BillDetailScreen> createState() => _BillDetailScreenState();
}

class _BillDetailScreenState extends ConsumerState<BillDetailScreen> {
  bool _isLoading = true;
  bool _isConfirming = false;
  Map<String, dynamic>? _tab;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTab();
  }

  Future<void> _loadTab() async {
    setState(() => _isLoading = true);
    try {
      // TODO: Wire to marketplace_extensions_service.dart fetchDineInTab
      await Future.delayed(const Duration(milliseconds: 500));
      setState(() {
        _isLoading = false;
        _tab = {
          'id': widget.tabId,
          'businessName': 'Loading...',
          'status': 'FINALIZED',
          'items': <Map<String, dynamic>>[],
          'totalAmount': 0.0,
        };
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _confirmBill() async {
    setState(() => _isConfirming = true);
    try {
      // TODO: Wire to marketplace_extensions_service.dart confirmDineInTab
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bill confirmed! Payment processing...'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
        context.pop();
      }
    } catch (e) {
      setState(() => _isConfirming = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Bill Details',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Color(0xFF64748B))),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _loadTab, child: const Text('Retry')),
                    ],
                  ),
                )
              : _buildBillContent(),
      bottomNavigationBar: _tab != null && _tab!['status'] == 'FINALIZED'
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isConfirming ? null : _confirmBill,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: _isConfirming
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Confirm & Pay',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildBillContent() {
    final items = (_tab?['items'] as List?) ?? [];
    final total = _tab?['totalAmount'] ?? 0.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Business info card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.restaurant, color: Color(0xFFF59E0B)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tab?['businessName'] ?? 'Restaurant',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tab #${widget.tabId.substring(0, 8)}',
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              _buildStatusChip(_tab?['status'] ?? 'OPEN'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Line items
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Items',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No items yet',
                      style: TextStyle(color: Color(0xFF94A3B8)),
                    ),
                  ),
                )
              else
                ...items.map((item) => _buildLineItem(item)),
              const Divider(height: 24),
              _buildTotalRow('Subtotal', total),
              const SizedBox(height: 6),
              _buildTotalRow('Tax', 0.0),
              const SizedBox(height: 6),
              _buildTotalRow('Tip', 0.0),
              const Divider(height: 20),
              _buildTotalRow('Total', total, isBold: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLineItem(Map<String, dynamic> item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${item['name']} × ${item['quantity'] ?? 1}',
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF334155),
              ),
            ),
          ),
          Text(
            '\$${((item['price'] ?? 0.0) * (item['quantity'] ?? 1)).toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, double amount, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isBold ? 16 : 14,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
            color: isBold ? const Color(0xFF0F172A) : const Color(0xFF64748B),
          ),
        ),
        Text(
          '\$${amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: isBold ? 18 : 14,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            color: isBold ? const Color(0xFF0F172A) : const Color(0xFF334155),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String status) {
    final color = switch (status) {
      'OPEN' => const Color(0xFF3B82F6),
      'FINALIZED' => const Color(0xFFF59E0B),
      'CLOSED' => const Color(0xFF10B981),
      _ => const Color(0xFF94A3B8),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
