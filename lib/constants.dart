import 'package:flutter/material.dart';

// 1. The Model
class P2POrder {
  final String id;
  final String coin;
  final double rate;
  final String paymentMethod;
  final DateTime timestamp;

  P2POrder({
    required this.id, 
    required this.coin, 
    required this.rate, 
    required this.paymentMethod,
    required this.timestamp, 
  });
}

// 2. The Global Notifier (The "Engine" that updates both screens)
ValueNotifier<List<P2POrder>> openTransactionsNotifier = ValueNotifier<List<P2POrder>>([]);