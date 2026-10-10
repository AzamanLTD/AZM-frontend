// =============================================================================
// AZAMAN — RECEIVE & REQUEST
//
// Receive owns the destination (Fiat/Azaman ID or Crypto/Polygon). The Request
// composer is a second resting state of this same full-page surface, driven by
// the same resisted snap curve used by Home Recent. Normal requests are sent
// to the standalone payment-request API; this screen deliberately does not use
// FriendService.requestFunds, because that operation is chat-oriented.
// =============================================================================

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/friend_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/amount_input.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/amount_keypad.dart';
import 'package:azaman/widgets/odometer_number.dart';
import 'package:azaman/widgets/pull_down_dismissible_surface.dart';
import 'package:azaman/widgets/home/activity_doorway.dart'
    show ActivityHandoffPhysics;
import 'package:azaman/screens/deposit_screen.dart' show CryptoReceivePanel;

enum _ReceiveTab { fiat, crypto }

class ReceiveScreen extends ConsumerStatefulWidget {
  const ReceiveScreen({super.key});

  @override
  ConsumerState<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends ConsumerState<ReceiveScreen>
    with TickerProviderStateMixin {
  _ReceiveTab _tab = _ReceiveTab.fiat;
  late final AnimationController _requestProgress;
  final TextEditingController _searchController = TextEditingController();
  String _amountRaw = '';
  Map<String, dynamic>? _selectedRecipient;
  bool _creatingRequest = false;
  String? _requestError;
  double _dragStartValue = 0;
  double _dragPx = 0;
  double _armedDepth = 0;
  bool _armedHapticFired = false;
  Map<String, dynamic>? _lastCreatedRequest;
  String? _lastCreatedFingerprint;
  bool? _pendingLinkOnly;

  static const double _flingVelocity = 700;

  bool get _requestOpen => _requestProgress.value >= 0.5;
  bool get _requestOperationUnresolved => _requestOperation.operationId != null;
  double? get _amountValue => AmountInput.value(_amountRaw);
  bool get _reduceMotion => MediaQuery.of(context).disableAnimations;

  @override
  void initState() {
    super.initState();
    _requestProgress = AnimationController(
      vsync: this,
      duration: MotionTokens.emphasized,
      value: 0,
    )..addListener(_handleProgressTick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final contacts = ref.read(friendProvider);
      if (contacts.friends.isEmpty && !contacts.isLoading) {
        contacts.fetchFriends();
      }
    });
  }

  void _handleProgressTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _requestProgress
      ..removeListener(_handleProgressTick)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _closeSurface() {
    AzamanHaptics.navigation();
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  void _snapRequest(bool open) {
    _requestProgress.stop();
    _armedDepth = 0;
    _armedHapticFired = false;
    final target = open ? 1.0 : 0.0;
    if (_reduceMotion) {
      _requestProgress.value = target;
      return;
    }
    const spring = SpringDescription(mass: 1, stiffness: 480, damping: 40);
    _requestProgress.animateWith(
      SpringSimulation(spring, _requestProgress.value, target, 0),
    );
  }

  void _toggleRequest() {
    AzamanHaptics.nav();
    _snapRequest(!_requestOpen);
  }

  void _onRequestDragStart(DragStartDetails _) {
    _requestProgress.stop();
    _dragStartValue = _requestProgress.value;
    _dragPx = 0;
    _armedDepth = 0;
    _armedHapticFired = false;
  }

  void _onRequestDragUpdate(DragUpdateDetails details) {
    // Pull UP to open; pull DOWN from the selected header to return to Receive.
    final direction = _dragStartValue < 0.5 ? -1.0 : 1.0;
    _dragPx += details.delta.dy * direction;
    final raw = ActivityHandoffPhysics.progressFor(_dragPx);
    final curved = ActivityHandoffPhysics.revealFor(raw);
    _requestProgress.value =
        _dragStartValue < 0.5 ? curved : 1.0 - curved;

    _armedDepth = ActivityHandoffPhysics.armedFor(raw);
    if (!_armedHapticFired && ActivityHandoffPhysics.commits(raw)) {
      _armedHapticFired = true;
      AzamanHaptics.threshold();
    } else if (!ActivityHandoffPhysics.commits(raw)) {
      _armedHapticFired = false;
    }
  }

  void _onRequestDragEnd(DragEndDetails details) {
    final opening = _dragStartValue < 0.5;
    final directionalVelocity = opening
        ? -details.velocity.pixelsPerSecond.dy
        : details.velocity.pixelsPerSecond.dy;
    final commits = ActivityHandoffPhysics.commits(
          ActivityHandoffPhysics.progressFor(_dragPx),
        ) ||
        directionalVelocity >= _flingVelocity;
    _snapRequest(commits ? opening : !opening);
  }

  void _selectTab(_ReceiveTab next) {
    if (next == _tab) return;
    AzamanHaptics.toggle();
    if (next == _ReceiveTab.crypto) _snapRequest(false);
    setState(() {
      _tab = next;
      _requestError = null;
    });
  }

  void _copyAzamanId(String azamanId) {
    if (azamanId.trim().isEmpty) return;
    Clipboard.setData(ClipboardData(text: azamanId));
    AzamanHaptics.confirm();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Azaman ID copied')),
    );
  }

  void _setAmount(String raw) {
    if (_requestOperationUnresolved) return;
    setState(() {
      _amountRaw = raw;
      _requestError = null;
      _lastCreatedRequest = null;
      _lastCreatedFingerprint = null;
    });
  }

  void _onAmountKey(String key) {
    _setAmount(AmountInput.applyKey(_amountRaw, key));
  }

  List<Map<String, dynamic>> _visibleRecipients(FriendProvider contacts) {
    final query = _searchController.text.trim();
    if (query.length >= 2) return contacts.searchResults;
    return contacts.friends;
  }

  String _recipientName(Map<String, dynamic> user) {
    final value = user['username'] ??
        user['friendUsername'] ??
        user['displayName'] ??
        user['name'];
    return value?.toString().trim().isNotEmpty == true
        ? value.toString()
        : 'Azaman contact';
  }

  String _recipientId(Map<String, dynamic> user) {
    return (user['userId'] ?? user['friendId'] ?? user['id'] ?? '').toString();
  }

  Future<void> _search(String query) async {
    if (_requestOperationUnresolved) return;
    setState(() {
      _selectedRecipient = null;
      _requestError = null;
      _lastCreatedRequest = null;
      _lastCreatedFingerprint = null;
    });
    if (query.trim().length >= 2) {
      await ref.read(friendProvider).searchUsers(query.trim());
    } else {
      ref.read(friendProvider).clearSearch();
    }
  }

  Future<Map<String, dynamic>> _createRequest({
    required bool linkOnly,
  }) async {
    final amount = _amountValue;
    final recipient = _selectedRecipient;
    if (amount == null) {
      throw StateError('Enter an amount greater than zero.');
    }
    if (!linkOnly && (recipient == null || _recipientId(recipient).isEmpty)) {
      throw StateError('Choose an Azaman contact to request money from.');
    }

    // Contract for the standalone request API: this is intentionally separate
    // from /friends/transfer/request, which emits chat-oriented transfer
    // requests. The backend PR must implement this contract before release.
    final response = await apiClient.postFinancial(
      '/payment-requests',
      {
        'amount': amount.toStringAsFixed(2),
        'currency': 'GHS',
        'requestMode': linkOnly ? 'LINK' : 'DIRECT',
        if (!linkOnly && recipient != null && _recipientId(recipient).isNotEmpty)
          'recipientUserId': _recipientId(recipient),
      },
      operationType: 'payment.request.create',
      ref: _requestOperation,
    );
    final decoded = jsonDecode(response.body);
    final root = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    final data = root['data'] is Map<String, dynamic>
        ? root['data'] as Map<String, dynamic>
        : root;
    final request = data['request'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(data['request'] as Map<String, dynamic>)
        : Map<String, dynamic>.from(data);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        message: (root['message'] ?? 'Could not create the payment request.')
            .toString(),
        statusCode: response.statusCode,
        code: root['code']?.toString(),
      );
    }
    return request;
  }

  final FinancialOperationRef _requestOperation = FinancialOperationRef();

  Future<void> _submitRequest({required bool linkOnly}) async {
    if (_creatingRequest) return;
    setState(() {
      _creatingRequest = true;
      _requestError = null;
    });

    try {
      final fingerprint =
          '${_amountValue!.toStringAsFixed(2)}|GHS|${linkOnly ? 'LINK' : 'DIRECT'}|${_selectedRecipient == null ? '' : _recipientId(_selectedRecipient!)}';
      final reuseCreatedRequest = _lastCreatedRequest != null &&
          _lastCreatedFingerprint == fingerprint;
      if (!reuseCreatedRequest) {
        if (_requestOperationUnresolved && _pendingLinkOnly != linkOnly) {
          throw StateError(
            'An earlier request may still be processing. Retry the same action before starting a different one.',
          );
        }
        if (!_requestOperationUnresolved) _pendingLinkOnly = linkOnly;
      }

      final request = reuseCreatedRequest
          ? _lastCreatedRequest!
          : await _createRequest(linkOnly: linkOnly);
      if (!mounted) return;
      _lastCreatedRequest = request;
      _lastCreatedFingerprint = fingerprint;
      _pendingLinkOnly = null;
      final shareUrl = (request['shareUrl'] ?? request['requestUrl'] ?? '')
          .toString();
      if (linkOnly) {
        if (shareUrl.isEmpty) {
          throw StateError(
            'The server created the request but did not return its share link.',
          );
        }
        await Share.share('Pay my request on Azaman: $shareUrl');
      } else {
        await _showCreatedRequest(request, shareUrl);
      }
    } catch (error) {
      if (!mounted) return;
      final unresolved = _requestOperationUnresolved;
      if (!unresolved) _pendingLinkOnly = null;
      setState(() {
        _requestError = unresolved
            ? 'We could not confirm the result. Retry the same action before changing this request.'
            : error is StateError
                ? error.message
                : error is ApiException
                    ? error.message
                    : 'Could not create the request. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _creatingRequest = false);
    }
  }

  Future<void> _showCreatedRequest(
    Map<String, dynamic> request,
    String shareUrl,
  ) async {
    final colors = ref.read(themeProvider).colors;
    final amount =
        request['amount']?.toString() ?? _amountValue?.toStringAsFixed(2) ?? '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: colors.card,
        title: Text(
          'Request created',
          style: AzText.title.copyWith(color: colors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'GH₵ $amount',
              style: AzText.titleXl.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AzSpace.sm),
            Text(
              'Your request exists independently of chat. You can share its '
              'dedicated link without creating a chat message.',
              style: AzText.body.copyWith(color: colors.textSecondary),
            ),
            if (shareUrl.isNotEmpty) ...[
              const SizedBox(height: AzSpace.md),
              SelectableText(
                shareUrl,
                style: AzText.body.copyWith(color: colors.accent),
              ),
            ],
          ],
        ),
        actions: [
          if (shareUrl.isNotEmpty)
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: shareUrl));
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Copy link'),
            ),
          if (shareUrl.isNotEmpty)
            TextButton(
              onPressed: () {
                Share.share('Pay my request on Azaman: $shareUrl');
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Share link'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final user = ref.watch(authProvider).user;
    final azamanId = user?.azamanId?.trim() ?? '';
    final progress = _tab == _ReceiveTab.fiat
        ? _requestProgress.value.clamp(0.0, 1.0).toDouble()
        : 0.0;
    final armed = _reduceMotion ? 0.0 : _armedDepth;
    final scale = _reduceMotion ? 1.0 : 1.0 + 0.14 * progress + 0.045 * armed;
    final wobble = _reduceMotion ? 0.0 : ActivityHandoffPhysics.wobbleFor(armed);

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        bottom: false,
        child: PullDownDismissibleSurface(
          onDismiss: _closeSurface,
          canDismiss: () => !_requestOpen,
          onDismissRejected: () => _snapRequest(false),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ReceiveHeader(
                colors: colors,
                onClose: _closeSurface,
                onOpenRequests: () => context.push(AzRoutes.paymentRequests),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                child: Row(
                  children: [
                    _ReceiveTabButton(
                      label: 'Fiat',
                      selected: _tab == _ReceiveTab.fiat,
                      onTap: () => _selectTab(_ReceiveTab.fiat),
                    ),
                    const SizedBox(width: 28),
                    _ReceiveTabButton(
                      label: 'Crypto',
                      selected: _tab == _ReceiveTab.crypto,
                      onTap: () => _selectTab(_ReceiveTab.crypto),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _tab == _ReceiveTab.crypto
                    ? const CryptoReceivePanel()
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final top = ui.lerpDouble(
                            constraints.maxHeight - 58,
                            4,
                            progress,
                          )!;
                          final panelTop = 58.0 * progress;
                          final panelBottom = 68.0 * (1.0 - progress);

                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    AzSpace.lg,
                                    panelTop,
                                    AzSpace.lg,
                                    panelBottom,
                                  ),
                                  child: Stack(
                                    children: [
                                      IgnorePointer(
                                        ignoring: progress > 0.15,
                                        child: Opacity(
                                          opacity: 1.0 - progress,
                                          child: _buildReceiveDetails(
                                            colors,
                                            azamanId,
                                          ),
                                        ),
                                      ),
                                      IgnorePointer(
                                        ignoring: progress < 0.85,
                                        child: Opacity(
                                          opacity: progress,
                                          child: _buildRequestComposer(
                                            colors,
                                            constraints.maxHeight,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Positioned(
                                top: top,
                                left: 0,
                                right: 0,
                                child: Center(
                                  child: GestureDetector(
                                    key: const ValueKey('receive-request-toggle'),
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _toggleRequest,
                                    onVerticalDragStart: _onRequestDragStart,
                                    onVerticalDragUpdate: _onRequestDragUpdate,
                                    onVerticalDragEnd: _onRequestDragEnd,
                                    child: Transform.rotate(
                                      angle: wobble,
                                      child: Transform.scale(
                                        scale: scale,
                                        child: _RequestBubble(
                                          colors: colors,
                                          progress: progress,
                                          selected: _requestOpen,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReceiveDetails(AzamanColors colors, String azamanId) {
    final idAvailable = azamanId.isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: AzSpace.lg, bottom: AzSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Receive money',
            style: AzText.titleXl.copyWith(color: colors.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AzSpace.sm),
          Text(
            'Share your dedicated Azaman ID to receive money.',
            style: AzText.body.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AzSpace.lg),
          if (idAvailable)
            Container(
              padding: const EdgeInsets.all(AzSpace.md),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: colors.border),
              ),
              child: QrImageView(
                data: azamanId,
                version: QrVersions.auto,
                size: 184,
                eyeStyle: QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: colors.textPrimary,
                ),
                dataModuleStyle: QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: colors.textPrimary,
                ),
              ),
            )
          else
            Container(
              width: 184,
              height: 184,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: colors.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AzSpace.md),
                child: Text(
                  'Your Azaman ID is not available yet.',
                  style: AzText.body.copyWith(color: colors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          const SizedBox(height: AzSpace.lg),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AzSpace.lg,
              vertical: AzSpace.md,
            ),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your Azaman ID',
                        style: AzText.bodyS.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        idAvailable ? azamanId : 'Unavailable',
                        style: AzText.title.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Copy Azaman ID',
                  onPressed: idAvailable ? () => _copyAzamanId(azamanId) : null,
                  icon: Icon(
                    Icons.copy_rounded,
                    color: idAvailable
                        ? colors.textPrimary
                        : colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AzSpace.md),
          Text(
            'The Request button opens a separate request composer. Creating a '
            'request does not automatically send anything in chat.',
            style: AzText.bodyS.copyWith(color: colors.textTertiary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRequestComposer(AzamanColors colors, double availableHeight) {
    final contacts = ref.watch(friendProvider);
    final compact = availableHeight < 680;
    final recipients = _visibleRecipients(contacts);
    final amountDisplay = AmountInput.display(_amountRaw);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AzSpace.md),
        Text(
          'Request money',
          style: AzText.titleXl.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          'Choose an amount and who should receive the request.',
          style: AzText.bodyS.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AzSpace.sm),
        Center(
          child: OdometerNumber(
            value: 'GH₵ $amountDisplay',
            style: AzText.display.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
            semanticsLabel: 'Request amount, Ghanaian cedis $amountDisplay',
          ),
        ),
        const SizedBox(height: AzSpace.sm),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AzSpace.sm,
          runSpacing: 4,
          children: [
            for (final amount in const [10, 20, 50, 100])
              ActionChip(
                label: Text('GH₵ $amount'),
                onPressed: (_creatingRequest || _requestOperationUnresolved)
                    ? null
                    : () => _setAmount(amount.toString()),
                visualDensity: VisualDensity.compact,
                backgroundColor: colors.softSurface,
                side: BorderSide(color: colors.border),
                labelStyle: AzText.bodyS.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        const SizedBox(height: AzSpace.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: AmountKeypad(
            onKey: _onAmountKey,
            enabled: !_creatingRequest && !_requestOperationUnresolved,
            rowHeight: compact ? 34 : 40,
          ),
        ),
        const SizedBox(height: AzSpace.xs),
        Text(
          'Request from',
          style: AzText.body.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: compact ? 40 : 44,
          child: TextField(
            controller: _searchController,
            enabled: !_requestOperationUnresolved && !_creatingRequest,
            onChanged: _search,
            style: AzText.body.copyWith(color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search an Azaman contact',
              hintStyle: AzText.body.copyWith(color: colors.textTertiary),
              prefixIcon: Icon(Icons.search, color: colors.textTertiary),
              filled: true,
              fillColor: colors.card,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colors.accent, width: 1.5),
              ),
            ),
          ),
        ),
        if (_selectedRecipient != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                label: Text(_recipientName(_selectedRecipient!)),
                onDeleted: _requestOperationUnresolved || _creatingRequest
                    ? null
                    : () => setState(() {
                        _selectedRecipient = null;
                        _lastCreatedRequest = null;
                        _lastCreatedFingerprint = null;
                      }),
                backgroundColor: colors.softSurface,
                side: BorderSide(color: colors.border),
              ),
            ),
          ),
        if (_requestError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _requestError!,
              style: AzText.bodyS.copyWith(color: colors.danger),
            ),
          ),
        const SizedBox(height: 4),
        Expanded(
          child: recipients.isEmpty
              ? Center(
                  child: Text(
                    contacts.isLoading
                        ? 'Searching contacts…'
                        : _searchController.text.trim().length >= 2
                            ? 'No matching Azaman users found.'
                            : 'Your Azaman contacts will appear here. Search by name or username.',
                    textAlign: TextAlign.center,
                    style: AzText.bodyS.copyWith(color: colors.textTertiary),
                  ),
                )
              : ListView.separated(
                  itemCount: recipients.length.clamp(0, 5).toInt(),
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: colors.border),
                  itemBuilder: (context, index) {
                    final recipient = recipients[index];
                    final selected = _selectedRecipient != null &&
                        _recipientId(_selectedRecipient!) ==
                            _recipientId(recipient);
                    final name = _recipientName(recipient);
                    final username = recipient['username']?.toString();
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 17,
                        backgroundColor: colors.softSurface,
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: AzText.bodyS.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      title: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AzText.body.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: username == null
                          ? null
                          : Text(
                              '@$username',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AzText.bodyS.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                      trailing: Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        color: selected ? colors.accent : colors.textTertiary,
                        size: 20,
                      ),
                      onTap: _requestOperationUnresolved || _creatingRequest
                          ? null
                          : () {
                              AzamanHaptics.toggle();
                              setState(() {
                                _selectedRecipient = recipient;
                                _requestError = null;
                                _lastCreatedRequest = null;
                                _lastCreatedFingerprint = null;
                              });
                            },
                    );
                  },
                ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            0,
            AzSpace.sm,
            0,
            12 + MediaQuery.of(context).padding.bottom,
          ),
          child: Row(
            children: [
              Expanded(
                child: _RequestActionButton(
                  key: const ValueKey('receive-request-submit'),
                  label: _creatingRequest ? 'Creating…' : 'Request',
                  primary: true,
                  enabled: !_creatingRequest &&
                      _amountValue != null &&
                      _selectedRecipient != null &&
                      (!_requestOperationUnresolved || _pendingLinkOnly == false),
                  onTap: () => _submitRequest(linkOnly: false),
                  colors: colors,
                ),
              ),
              const SizedBox(width: AzSpace.sm),
              Expanded(
                child: _RequestActionButton(
                  key: const ValueKey('receive-request-link'),
                  label: 'Open request link',
                  primary: false,
                  enabled: !_creatingRequest &&
                      _amountValue != null &&
                      (!_requestOperationUnresolved || _pendingLinkOnly == true),
                  onTap: () => _submitRequest(linkOnly: true),
                  colors: colors,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReceiveHeader extends StatelessWidget {
  const _ReceiveHeader({
    required this.colors,
    required this.onClose,
    required this.onOpenRequests,
  });

  final AzamanColors colors;
  final VoidCallback onClose;
  final VoidCallback onOpenRequests;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Close Receive',
            child: GestureDetector(
              onTap: onClose,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colors.softSurface,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.close,
                  size: 18,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Receive',
              style: AzText.title.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Payment requests',
            onPressed: onOpenRequests,
            icon: Icon(Icons.receipt_long_rounded, color: colors.textPrimary),
          ),

        ],
      ),
    );
  }
}

class _ReceiveTabButton extends StatelessWidget {
  const _ReceiveTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label receive tab',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AzText.body.copyWith(
                  color: selected
                      ? colors.colorScheme.primary
                      : colors.colorScheme.onSurface.withValues(alpha: 0.58),
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              AnimatedContainer(
                duration: MotionTokens.control,
                curve: MotionTokens.enter,
                height: 2,
                width: selected ? 28 : 8,
                decoration: BoxDecoration(
                  color: selected
                      ? colors.colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestBubble extends StatelessWidget {
  const _RequestBubble({
    required this.colors,
    required this.progress,
    required this.selected,
  });

  final AzamanColors colors;
  final double progress;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final active = progress.clamp(0.0, 1.0).toDouble();
    final idleSurface = colors.softSurface;
    final activeSurface = colors.isDark
        ? const Color(0xFF254B39)
        : const Color(0xFFC9DDCF);
    final idleInk = colors.textTertiary;
    final activeInk = colors.isDark
        ? const Color(0xFFD9EBDD)
        : const Color(0xFF254B39);

    return Semantics(
      button: true,
      selected: selected,
      label: selected ? 'Request section, selected. Tap to return to Receive.' : 'Open Request section',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AzSpace.xl,
          vertical: AzSpace.sm,
        ),
        decoration: BoxDecoration(
          color: Color.lerp(idleSurface, activeSurface, active),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Color.lerp(colors.border, activeSurface, active)!,
          ),
          boxShadow: active > 0.5
              ? [
                  BoxShadow(
                    color: activeSurface.withValues(alpha: 0.16 * active),
                    blurRadius: 14 * active,
                    spreadRadius: 0.5 * active,
                  ),
                ]
              : null,
        ),
        child: Text(
          'Request',
          style: AzText.body.copyWith(
            color: Color.lerp(idleInk, activeInk, active),
            fontWeight: FontWeight.w800,
            letterSpacing: 0.1,
          ),
        ),
      ),
    );
  }
}

class _RequestActionButton extends StatelessWidget {
  const _RequestActionButton({
    super.key,
    required this.label,
    required this.primary,
    required this.enabled,
    required this.onTap,
    required this.colors,
  });

  final String label;
  final bool primary;
  final bool enabled;
  final VoidCallback onTap;
  final AzamanColors colors;

  @override
  Widget build(BuildContext context) {
    final bg = primary ? colors.accent : colors.card;
    final fg = primary ? colors.onAccent : colors.textPrimary;
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: MotionTokens.control,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: enabled ? bg : colors.softSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: primary
                  ? Colors.transparent
                  : colors.border,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AzText.body.copyWith(
              color: enabled ? fg : colors.textTertiary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
