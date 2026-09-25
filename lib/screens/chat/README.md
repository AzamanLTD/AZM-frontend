# Azaman Phase 3.3: Chat UI Components

## Overview
This directory contains the premium chat interfaces for Azaman's P2P trading platform.

## Components

### 1. Transaction Chat Screen (`transaction_chat_screen.dart`)
Premium chat interface for active P2P trades with:
- **Draggable Countdown Overlay**: Floating, draggable timer widget with glassmorphism effects
- **Ripple Extension Chips**: +15m and +30m buttons above keyboard for time extension requests
- **Live Countdown**: Real-time countdown ticker with visual warnings when time is low
- **Premium Dark Theme**: Golden accents with glassmorphism effects
- **Security Banner**: Warning banner for trade safety
- **Message Types**: Support for text, system, time request, and time approval messages

**Usage:**
```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => TransactionChatScreen(
      tradeId: 'trade_123',
      otherUserName: 'John Doe',
      otherUserId: 'user_456',
      tradeAmount: 100.00,
      tradeCurrency: 'USDT',
    ),
  ),
);
```

### 2. Direct Message Screen (`direct_message_screen.dart`)
Social chat interface with crypto transfer capabilities:
- **Action Button**: Prominent + button next to message input for value transfers
- **Glassmorphism Bottom Sheet**: Dark-themed bottom sheet with BackdropFilter blur
- **Number Pad Input**: Custom number pad for entering transfer amounts
- **Biometric Authentication**: Local authentication for secure transfers
- **Transaction Bubbles**: Special message bubbles for crypto transfers
- **Premium UI**: Cyan accent colors with golden send button

**Usage:**
```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => DirectMessageScreen(
      chatId: 'chat_789',
      contactId: 'contact_123',
      contactName: 'Jane Smith',
      contactAzamanId: 'AZM_JANE_123',
    ),
  ),
);
```

### 3. Chat Provider (`../providers/chat_provider.dart`)
Riverpod-based state management for both chat screens:
- **TransactionChatNotifier**: Manages transaction chat state with countdown timer
- **DirectChatNotifier**: Manages direct message chat state
- **Message Types**: Enum for different message categories
- **Time Extension Logic**: Built-in support for ripple extensions

## Features

### Glassmorphism Effects
All components use `BackdropFilter` with blur effects for premium glass-like UI:
```dart
BackdropFilter(
  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
  child: Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(...),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: colors.glow.withOpacity(0.3)),
    ),
  ),
)
```

### Draggable Countdown
The countdown overlay in Transaction Chat is fully draggable:
- Users can reposition it anywhere on screen
- Changes color to red when < 5 minutes remain
- Auto-disables chat when time expires

### In-Chat Value Transfers
Direct Message screen supports sending crypto without leaving chat:
1. Tap the + button next to message input
2. Bottom sheet appears with number pad
3. Enter amount and tap Send
4. Biometric authentication required
5. Transaction message appears in chat

## Design System
- **Primary Accent**: Golden (`colors.glow`)
- **Secondary Accent**: Cyan (`colors.accentSecondary`)
- **Background**: Deep dark (`colors.background`)
- **Surface**: Elevated dark (`colors.surface`, `colors.card`)
- **Success**: Green for completed transactions
- **Danger**: Red for warnings and errors

## Dependencies
- `flutter_riverpod`: State management
- `provider`: Theme access
- `local_auth`: Biometric authentication
- `dart:ui`: BackdropFilter for glassmorphism

## Integration Notes
Both screens use Riverpod for state management but access the theme via Provider for compatibility with existing app architecture.

The countdown timer in Transaction Chat uses a `Timer.periodic` to update every second. Remember to cancel it in `dispose()`.

Transaction messages and crypto transfers are currently mocked. In production, wire these to your backend API and socket service.
