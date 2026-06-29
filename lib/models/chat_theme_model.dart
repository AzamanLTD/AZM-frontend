import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

enum ChatWallpaper { none, midnight, galaxy, forest, ocean, minimal, geometric }

class ChatThemeModel {
  final String chatId;
  final ChatWallpaper wallpaper;
  final Color? customBubbleColor;

  const ChatThemeModel({
    required this.chatId,
    this.wallpaper = ChatWallpaper.none,
    this.customBubbleColor,
  });

  ChatThemeModel copyWith({
    ChatWallpaper? wallpaper,
    Color? customBubbleColor,
  }) {
    return ChatThemeModel(
      chatId: chatId,
      wallpaper: wallpaper ?? this.wallpaper,
      customBubbleColor: customBubbleColor ?? this.customBubbleColor,
    );
  }

  String get wallpaperAsset {
    if (wallpaper == ChatWallpaper.none) return '';
    return 'assets/chat_wallpapers/wp_${wallpaper.name}.jpg';
  }
}

class ChatThemeNotifier extends StateNotifier<ChatThemeModel> {
  ChatThemeNotifier({required String chatId})
      : super(ChatThemeModel(chatId: chatId)) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'chat_theme_${state.chatId}';
    final wp = prefs.getString(key) ?? 'none';
    state = state.copyWith(
      wallpaper: ChatWallpaper.values.firstWhere(
        (e) => e.name == wp,
        orElse: () => ChatWallpaper.none,
      ),
    );
  }

  Future<void> setWallpaper(ChatWallpaper wp) async {
    state = state.copyWith(wallpaper: wp);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chat_theme_${state.chatId}', wp.name);
  }

  Future<void> setCustomBubbleColor(Color? color) async {
    state = state.copyWith(customBubbleColor: color);
  }
}

final chatThemeProvider = StateNotifierProvider.family<ChatThemeNotifier, ChatThemeModel, String>(
  (ref, chatId) => ChatThemeNotifier(chatId: chatId),
);
