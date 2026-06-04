import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';

class P2PBuySheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> vendor; // Pass the selected vendor data
  final List<Map<String, dynamic>> allVendors; // Pass all available vendors for matching

  const P2PBuySheet({super.key, required this.vendor, required this.allVendors});

  @override
  ConsumerState<P2PBuySheet> createState() => _P2PBuySheetState();
}

class _P2PBuySheetState extends ConsumerState<P2PBuySheet> {
  final TextEditingController _amountController = TextEditingController();
  String? _warningMessage;
  Map<String, dynamic>? _alternativeVendor;
  bool _canRequestIncrease = false;

  void _checkLiquidity(String value) {
    double? enteredAmount = double.tryParse(value);
    if (enteredAmount == null) return;

    setState(() {
      _warningMessage = null;
      _alternativeVendor = null;
      _canRequestIncrease = false;

      // 1. Check if above current vendor's max limit
      if (enteredAmount > widget.vendor['maxLimit']) {
        _canRequestIncrease = true;
        
        // 2. Search for an alternative vendor with the same payment method but higher liquidity
        try {
          _alternativeVendor = widget.allVendors.firstWhere((v) =>
              v['id'] != widget.vendor['id'] &&
              v['paymentMethod'] == widget.vendor['paymentMethod'] &&
              v['maxLimit'] >= enteredAmount &&
              v['isOnline'] == true);
          
          if (_alternativeVendor != null) {
            _warningMessage = "${_alternativeVendor!['name']} has enough liquidity for this trade.";
          }
        } catch (e) {
          _warningMessage = "Amount exceeds vendor limit. You can request an increase.";
        }
      } 
      // 3. Check if below min limit
      else if (enteredAmount < widget.vendor['minLimit']) {
        _warningMessage = "Min limit is \$${widget.vendor['minLimit']}";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        left: 20, right: 20, top: 20
      ),
      decoration: BoxDecoration(
        color: ref.read(themeProvider).colors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Buy ${widget.vendor['crypto']}", 
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          
          // Price Info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Price", style: TextStyle(color: Colors.white54)),
              Text("\$${widget.vendor['price']}", 
                style: const TextStyle(color: Color(0xFFF0B90B), fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 20),

          // Amount Input
          TextField(
            controller: _amountController,
            onChanged: _checkLiquidity,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white, fontSize: 24),
            decoration: InputDecoration(
              hintText: "Enter Amount",
              hintStyle: const TextStyle(color: Colors.white24),
              suffixText: "USD",
              suffixStyle: const TextStyle(color: Color(0xFFF0B90B)),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
            ),
          ),
          
          // Dynamic Warning / Suggestion Box
          if (_warningMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _alternativeVendor != null ? Colors.blue.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _alternativeVendor != null ? Icons.lightbulb : Icons.warning_amber_rounded,
                      color: _alternativeVendor != null ? Colors.blue : Colors.orange,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_warningMessage!, 
                        style: TextStyle(color: _alternativeVendor != null ? Colors.blue : Colors.orange, fontSize: 12)),
                    ),
                    if (_alternativeVendor != null)
                      TextButton(
                        onPressed: () { /* Navigator to other vendor */ },
                        child: const Text("SWITCH", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                      )
                  ],
                ),
              ),
            ),

          const SizedBox(height: 15),
          Text("Limit: \$${widget.vendor['minLimit']} - \$${widget.vendor['maxLimit']}", 
            style: const TextStyle(color: Colors.white38, fontSize: 12)),
          
          const SizedBox(height: 30),

          // Action Buttons
          Row(
            children: [
              if (_canRequestIncrease)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFF0B90B)),
                        minimumSize: const Size(0, 50),
                      ),
                      onPressed: () {
                        // Logic to send "Request Limit Increase" via Socket/API
                      },
                      child: const Text("REQUEST LIMIT", style: TextStyle(color: Color(0xFFF0B90B))),
                    ),
                  ),
                ),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF0B90B),
                    disabledBackgroundColor: Colors.white10,
                    minimumSize: const Size(0, 50),
                  ),
                  onPressed: _warningMessage == null && _amountController.text.isNotEmpty 
                    ? () { /* Start Trade Logic */ } 
                    : null,
                  child: const Text("BUY", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}