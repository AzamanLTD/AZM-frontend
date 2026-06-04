import 'package:flutter/material.dart';

// This is the model that defines what an order looks like
class P2POrder {
  final String id;
  final double rate;
  final String coin;
  final DateTime timestamp;

  P2POrder({
    required this.id, 
    required this.rate, 
    required this.coin, 
    required this.timestamp
  });
}

// THIS IS THE GLOBAL VARIABLE
// Now it's defined in one neutral place.
ValueNotifier<List<P2POrder>> openTransactionsNotifier = ValueNotifier<List<P2POrder>>([]);