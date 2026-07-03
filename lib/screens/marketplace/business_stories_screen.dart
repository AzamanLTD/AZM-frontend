import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class BusinessStoriesScreen extends StatelessWidget {
  final String bizId;
  const BusinessStoriesScreen({super.key, required this.bizId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => context.pop(),
        ),
      ),
      body: Center(
        child: Text(
          'Business Stories for $bizId',
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
      ),
    );
  }
}
