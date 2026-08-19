import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import 'package:azaman/providers/theme_provider.dart';

class StickerSheet extends StatefulWidget {
  final void Function(String assetPath, bool isAnimated) onStickerSelected;

  const StickerSheet({
    super.key,
    required this.onStickerSelected,
  });

  @override
  State<StickerSheet> createState() => _StickerSheetState();
}

class _StickerSheetState extends State<StickerSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  static const _staticStickers = [
    'assets/stickers/static/wave.png',
    'assets/stickers/static/laugh.png',
    'assets/stickers/static/cool.png',
    'assets/stickers/static/sad.png',
    'assets/stickers/static/thumbsup.png',
    'assets/stickers/static/fire.png',
  ];

  static const _animatedStickers = [
    'assets/stickers/animated/confetti.json',
    'assets/stickers/animated/clap.json',
    'assets/stickers/animated/heart.json',
    'assets/stickers/animated/money.json',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = ThemeProvider.getColors(AzamanTheme.light);

    return Container(
      height: 360,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.textTertiary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TabBar(
            controller: _tabController,
            labelColor: colors.textPrimary,
            unselectedLabelColor: colors.textTertiary,
            indicatorColor: colors.accent,
            tabs: const [
              Tab(text: '😊 Expressions'),
              Tab(text: '✨ Animated'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildStaticGrid(colors),
                _buildAnimatedGrid(colors),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaticGrid(AzamanColors colors) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _staticStickers.length,
      itemBuilder: (_, i) {
        return GestureDetector(
          onTap: () {
            widget.onStickerSelected(_staticStickers[i], false);
            Navigator.pop(context);
          },
          child: Image.asset(
            _staticStickers[i],
            width: 70,
            height: 70,
            fit: BoxFit.contain,
          ),
        );
      },
    );
  }

  Widget _buildAnimatedGrid(AzamanColors colors) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _animatedStickers.length,
      itemBuilder: (_, i) {
        return GestureDetector(
          onTap: () {
            widget.onStickerSelected(_animatedStickers[i], true);
            Navigator.pop(context);
          },
          child: Lottie.asset(
            _animatedStickers[i],
            width: 70,
            height: 70,
            repeat: true,
          ),
        );
      },
    );
  }
}
