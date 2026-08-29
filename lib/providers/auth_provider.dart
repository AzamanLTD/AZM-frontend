// =============================================================================
// =============================================================================
// AZAMAN V2 — AUTH PROVIDER  (Riverpod-native exports)
// AZAMAN V2 — AUTH PROVIDER  (Riverpod-native exports)
//
//
// Phase 0a migration: the ChangeNotifier class is preserved verbatim so that
// Phase 0a migration: the ChangeNotifier class is preserved verbatim so that
// all existing legacy callsites (Provider.of, Consumer<AuthProvider>) keep
// all existing legacy callsites (Provider.of, Consumer<AuthProvider>) keep
// working until Phase 0b lands the mechanical mass-migration. The new
// `authProvider` and `authStateProvider` exports are the canonical Riverpod
// handles — every NEW callsite must read state through these.
//
// Riverpod consumption pattern (mandatory in all NEW code):
//   final auth = ref.watch(authProvider);                      // listens
//   ref.read(authProvider).setSessionFromLogin(loginUser);     // imperative
//
// Granular reads (V2 §3 immutability + select() doctrine):
//   final isVendor = ref.watch(authProvider.select((a) => a.isVendor));
//   final balance  = ref.watch(currentUserProvider.select((u) => u?.azmBalance));
//
// "Phantom user" hardening from the previous Polish Sprint is preserved.
// =============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/push_notification_service.dart';
import 'package:azaman/services/socket_service.dart';
import 'package:azaman/router/auth_guard.dart';

enum AuthStatus { idle, loading, authenticated, profileNotFound, unauthenticated, error }

class AuthProvider with ChangeNotifier {
  AuthProvider({this.ref});
  final Ref? ref;
  User? _user;
  AuthStatus _status = AuthStatus.idle;
  String? _error;
  int _hydrationGeneration = 0;
  bool _isDisposed = false;

  User? get user => _user;
  AuthStatus get status => _status;
  String? get error => _error;
  String? get token => _user?.token;
  bool get isAuthenticated => _user != null && _status == AuthStatus.authenticated;
  bool get isLoading => _status == AuthStatus.loading;
  bool get profileNotFound => _status == AuthStatus.profileNotFound;
  String get role => (_user?.role ?? 'USER').toUpperCase();
  bool get isVendor => role == 'VENDOR';
  bool get isAdmin => role == 'ADMIN';
  bool get isUser => role == 'USER';

  static final ValueNotifier<_AuthSnapshot> snapshot = ValueNotifier<_AuthSnapshot>(const _AuthSnapshot(user: null, status: AuthStatus.idle));

  void _publish() {
    snapshot.value = _AuthSnapshot(user: _user, status: _status);
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  Future<AuthStatus> setSessionFromLogin(User loginUser) async {
    _user = loginUser;
    _status = AuthStatus.loading;
    _error = null;
    _publish();
    await fetchUserDetails();
    if (_status == AuthStatus.authenticated) syncFcmToken();
    return _status;
  }

  void setUser(User user) => setSessionFromLogin(user);

  Future<void> fetchUserDetails() async {
    if (_user == null || _user!.token.isEmpty) {
      _status = AuthStatus.unauthenticated;
      AuthGuard.isAuthenticated = false;
      _publish();
      return;
    }
    final generation = ++_hydrationGeneration;
    _status = AuthStatus.loading;
    _error = null;
    _publish();
    try {
      final response = await apiClient.get('/auth/me/${_user!.id}');
      if (generation != _hydrationGeneration) return;
      final body = jsonDecode(response.body);
      final Map<String, dynamic> profileJson = body is Map<String, dynamic>
          ? (body['user'] is Map<String, dynamic>
              ? body['user'] as Map<String, dynamic>
              : (body['data'] is Map<String, dynamic> ? body['data'] as Map<String, dynamic> : body))
          : <String, dynamic>{};
      _user = User.fromJson({...profileJson, 'token': _user!.token});
      _status = AuthStatus.authenticated;
      AuthGuard.isAuthenticated = true;
      _error = null;
      if (ref != null) {
        SocketService.instance.disconnect();
        SocketService.instance.initWithRef(ref!);
      }
      ref?.read(balanceDataProvider.notifier).state = BalanceData(
        availableBalance: _user!.availableBalance,
        vendorUnallocatedBalance: _user!.vendorUnallocatedBalance,
        escrowLockedBalance: _user!.escrowLockedBalance,
        disputeEscrowBalance: _user!.disputeEscrowBalance,
        azmBalance: _user!.azmBalance,
      );
    } on ApiException catch (e) {
      if (generation != _hydrationGeneration) return;
      if (e.statusCode == 404) {
        debugPrint('[Auth] Profile not found in DB — forcing setup flow.');
        await apiClient.clearAuthData();
        _user = null;
        _status = AuthStatus.profileNotFound;
        AuthGuard.isAuthenticated = false;
        _error = 'Profile not found. Please complete registration.';
      } else if (e.statusCode == 401) {
        debugPrint('[Auth] JWT rejected — clearing session.');
        await apiClient.clearAuthData();
        _user = null;
        _status = AuthStatus.unauthenticated;
        AuthGuard.isAuthenticated = false;
        _error = 'Session expired. Please log in again.';
      } else {
        debugPrint('[Auth] Profile fetch failed (${e.statusCode}): $e');
        _status = AuthStatus.error;
        AuthGuard.isAuthenticated = false;
        _error = e.toString();
      }
    } catch (e) {
      if (generation != _hydrationGeneration) return;
      debugPrint('[Auth] Profile fetch error: $e');
      _status = AuthStatus.error;
      AuthGuard.isAuthenticated = false;
      _error = 'Could not load profile. Check your connection.';
    } finally {
      _publish();
    }
  }

  Future<bool> checkAuthStatus() async {
    final ok = await apiClient.isAuthenticated();
    if (!ok) {
      _user = null;
      _status = AuthStatus.unauthenticated;
      AuthGuard.isAuthenticated = false;
      _publish();
    }
    return ok;
  }

  Future<void> logout() async {
    _hydrationGeneration++;
    await apiClient.logout();
    _user = null;
    _status = AuthStatus.unauthenticated;
    AuthGuard.isAuthenticated = false;
    _error = null;
    SocketService.instance.disconnect();
    _publish();
  }

  /// Live-update balances. Now accepts the full V2 ledger split — legacy
  /// callers only passing azm/available still work because every parameter
  /// is optional. Phase J (2026-05-25) dropped the legacy `lockedBalance`
  /// parameter; callers should use `escrowLockedBalance` instead.
  void updateBalance({
    double? azmBalance,
    double? availableBalance,
    double? vendorUnallocatedBalance,
    double? escrowLockedBalance,
    double? disputeEscrowBalance,
  }) {
    if (_user == null) return;
    _user = _user!.copyWith(
      azmBalance: azmBalance,
      availableBalance: availableBalance,
      vendorUnallocatedBalance: vendorUnallocatedBalance,
      escrowLockedBalance: escrowLockedBalance,
      disputeEscrowBalance: disputeEscrowBalance,
    );
    _publish();
  }

  void updateRole(String role) {
    if (_user == null) return;
    _user = _user!.copyWith(role: role);
    _publish();
  }

  /// Push a freshly-uploaded avatar URL into the live user snapshot so every
  /// surface reading `currentUserProvider` / `authProvider` (home header,
  /// settings drawer, etc.) reflects it immediately without a full refetch.
  void updateProfilePicture(String url) {
    if (_user == null) return;
    _user = _user!.copyWith(profilePictureUrl: url);
    _publish();
  }

  Future<void> syncFcmToken() async {
    if (_user == null || _user!.token.isEmpty) return;
    try {
      await PushNotificationService.instance.syncToken(_user!.token);
    } catch (e) {
      debugPrint('[Auth] FCM sync failed (non-fatal): $e');
    }
  }
}

@immutable
class _AuthSnapshot {
  final User? user;
  final AuthStatus status;
  const _AuthSnapshot({required this.user, required this.status});
}

// =============================================================================
// RIVERPOD HANDLES (canonical V2 access path)
// =============================================================================

final authProvider = ChangeNotifierProvider<AuthProvider>((ref) {
  return AuthProvider(ref: ref);
});

final currentUserProvider = StreamProvider<User?>((ref) {
  final controller = StreamController<User?>();
  void listener() => controller.add(AuthProvider.snapshot.value.user);
  AuthProvider.snapshot.addListener(listener);
  controller.add(AuthProvider.snapshot.value.user);
  ref.onDispose(() {
    AuthProvider.snapshot.removeListener(listener);
    controller.close();
  });
  return controller.stream;
});

final authStatusProvider = StreamProvider<AuthStatus>((ref) {
  final controller = StreamController<AuthStatus>();
  void listener() => controller.add(AuthProvider.snapshot.value.status);
  AuthProvider.snapshot.addListener(listener);
  controller.add(AuthProvider.snapshot.value.status);
  ref.onDispose(() {
    AuthProvider.snapshot.removeListener(listener);
    controller.close();
  });
  return controller.stream;
});

final isVendorProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserProvider).value;
  return (user?.role ?? '').toUpperCase() == 'VENDOR';
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  final status = ref.watch(authStatusProvider).value;
  final user = ref.watch(currentUserProvider).value;
  return user != null && status == AuthStatus.authenticated;
});
