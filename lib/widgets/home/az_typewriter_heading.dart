// =============================================================================
// AZAMAN — TYPEWRITER HEADING  (NEW-HOME §2)
//
// The Home greeting becomes a reactive text surface: characters type
// forward, the message holds, erases backward, then the next message types.
// NOT an AnimatedSwitcher cross-fade — an actual character-level state
// machine.
//
// Layering (the state machine is separately testable, per the brief):
//   * TypewriterMachine  — pure-ish ChangeNotifier owning one message at a
//                          time: typing → holding → erasing → typing. Timer
//                          driven; disposable; interruption-safe.
//   * HomeHeadingMessage / HeadingMessageSelector — priority selection.
//                          Priority 1 = verified actionable financial
//                          reminder, 2 = verified contextual account event,
//                          3 = baseline greeting, 4 = feature fallback.
//   * AzTypewriterHeading — the widget. Reuses AzGreetingBrain (NEW-D) for
//                          the greeting text and glyphs, plus the SAME real
//                          inputs (settled inflow today, susu due tomorrow)
//                          — no new data sources, nothing invented.
//
// Reduced motion (AzMotion, the authoritative resolver): the final current
// message appears immediately; no character-by-character animation.
//
// Feature messages are the brief's fixed fallback copy — they may NEVER
// fabricate availability, savings, rates, balances, offers or urgency.
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/home_shell_active_provider.dart';
import 'package:azaman/providers/home_summary_provider.dart';
import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/services/home_summary_service.dart'
    show TransactionSummary;
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/az_money.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/widgets/home/az_greeting_brain.dart';

// ── MESSAGE MODEL ────────────────────────────────────────────────────────

/// Priority order from the brief. Lower value == higher priority.
enum HomeHeadingPriority {
  /// 1 — verified actionable financial reminder (e.g. susu due tomorrow).
  reminder,

  /// 2 — verified contextual account event (e.g. money arrived today).
  event,

  /// 3 — baseline greeting (part of day + name).
  greeting,

  /// 4 — one useful AZM feature message, used as fallback only.
  feature,
}

class HomeHeadingMessage {
  final String text;
  final HomeHeadingPriority priority;
  final IconData? glyph;

  const HomeHeadingMessage({
    required this.text,
    required this.priority,
    this.glyph,
  });
}

/// The brief's exact fallback feature copy. Static, honest, never
/// data-dependent — these are the ONLY strings the heading may show when no
/// contextual signal exists.
const List<HomeHeadingMessage> kHeadingFeatureMessages = [
  HomeHeadingMessage(
    text: "Put money aside for something you're building.",
    priority: HomeHeadingPriority.feature,
    glyph: HugeIconsSolid.piggyBank,
  ),
  HomeHeadingMessage(
    text: 'Buy or sell directly with vendors.',
    priority: HomeHeadingPriority.feature,
    glyph: HugeIconsSolid.creditCard,
  ),
  HomeHeadingMessage(
    text: 'Save together with your circle.',
    priority: HomeHeadingPriority.feature,
    glyph: HugeIconsSolid.userGroup,
  ),
  HomeHeadingMessage(
    text: 'Explore places and businesses on Azaman.',
    priority: HomeHeadingPriority.feature,
    glyph: HugeIconsSolid.store01,
  ),
];

/// Pure priority selection — no widget, no providers, fully unit-testable.
///
/// The two contextual candidates come from the same authoritative inputs the
/// NEW-D greeting brain already reads; the selector never invents them. A
/// reminder outranks an event (brief §2 priority order); when neither
/// exists the baseline greeting wins.
class HeadingMessageSelector {
  const HeadingMessageSelector._();

  static HomeHeadingMessage? reminder({required bool susuDueTomorrow}) {
    if (!susuDueTomorrow) return null;
    return const HomeHeadingMessage(
      text: 'Your Susu contribution is due tomorrow',
      priority: HomeHeadingPriority.reminder,
      glyph: HugeIconsSolid.alertCircle,
    );
  }

  static HomeHeadingMessage? event({String? moneyArrivedToday}) {
    if (moneyArrivedToday == null) return null;
    return HomeHeadingMessage(
      text: 'Money arrived today · $moneyArrivedToday',
      priority: HomeHeadingPriority.event,
      glyph: HugeIconsSolid.moneyReceiveFlow01,
    );
  }

  /// The highest-priority contextual message, or null when only the
  /// greeting/feature ladder remains.
  static HomeHeadingMessage? topContextual({
    required bool susuDueTomorrow,
    String? moneyArrivedToday,
  }) {
    final r = reminder(susuDueTomorrow: susuDueTomorrow);
    if (r != null) return r;
    return event(moneyArrivedToday: moneyArrivedToday);
  }
}

// ── STATE MACHINE ────────────────────────────────────────────────────────

enum TypewriterPhase { idle, typing, holding, erasing }

/// Character-level type → hold → erase → type state machine. Owns ONE
/// current message at a time and OWNS the cycle: when a message finishes
/// typing it HOLDS for [holdDuration], then asks [nextMessage] for what
/// comes next (null = hold again, same string = hold again, a different
/// string = erase, then type it). Scheduling a different message while
/// one is showing interrupts cleanly: the current text erases first, then
/// the new message types.
///
/// The hold IS the rotation cadence — there is no hidden always-running
/// timer in the widget. While the host surface is inactive the machine is
/// PAUSED (timers cancelled, text kept); on resume the cycle continues
/// from where it stopped, so nothing rotates while the user is elsewhere.
///
/// Char pace: one deliberate constant. MotionTokens' fastest tempo is
/// 90ms (instantFeedback), which covers ~4 characters at typing speed; the
/// step below is that tempo ÷ 4 so the whole heading still reads as the
/// app's motion system, not a foreign rhythm. Erasing runs faster (60% of
/// the step): deletion is grammar, not content — the eye should move on.
class TypewriterMachine extends ChangeNotifier {
  TypewriterMachine({
    this.typeStep = const Duration(milliseconds: 22),
    this.eraseStep = const Duration(milliseconds: 13),
    this.holdDuration = const Duration(seconds: 9),
    this.nextMessage,
    this.instant = false,
  });

  final Duration typeStep;
  final Duration eraseStep;
  final Duration holdDuration;

  /// The rotation source: asked at every hold end. Returning null (or the
  /// unchanged current message) means "keep holding" — the machine re-arms
  /// the hold.
  final String? Function()? nextMessage;

  /// Reduced-motion mode: characters appear instantly, no per-char timers,
  /// but the hold/rotation semantics are preserved.
  final bool instant;

  String _shown = '';
  String _target = '';
  TypewriterPhase _phase = TypewriterPhase.idle;
  Timer? _timer;
  bool _paused = false;

  String get shownText => _shown;
  String get targetText => _target;
  TypewriterPhase get phase => _phase;
  bool get paused => _paused;

  /// Schedules [message]. If it is already the current message (shown,
  /// typing or held) this is a NO-OP — no erase, no retype. A DIFFERENT
  /// message while text is shown erases first, then types.
  void showMessage(String message) {
    if (message == _target) return; // identical → never reanimate
    _target = message;
    _cancel();
    if (_shown.isEmpty) {
      _startTyping();
    } else {
      _startErasing();
    }
  }

  /// The message appears immediately; the hold cycle still runs.
  void showImmediately(String message) {
    _cancel();
    _target = message;
    _shown = message;
    _phase = TypewriterPhase.idle;
    notifyListeners();
    _hold();
  }

  /// Pause the cycle: cancel timers, keep the shown text. Idempotent.
  void pause() {
    if (_paused) return;
    _paused = true;
    _cancel();
    notifyListeners();
  }

  /// Resume from wherever the cycle paused: a held message re-arms its
  /// hold; a partial type/erase continues from the same character.
  void resume() {
    if (!_paused) return;
    _paused = false;
    switch (_phase) {
      case TypewriterPhase.holding:
        _hold();
      case TypewriterPhase.typing:
        _startTyping();
      case TypewriterPhase.erasing:
        _startErasing();
      case TypewriterPhase.idle:
        // A completed message that never armed a hold (paused exactly on
        // the completion tick): re-arm the hold so the cycle continues.
        _hold();
    }
    notifyListeners();
  }

  void _startTyping() {
    _cancel();
    if (_shown == _target) {
      _hold();
      return;
    }
    if (instant) {
      _shown = _target;
      _phase = TypewriterPhase.idle;
      notifyListeners();
      _hold();
      return;
    }
    _phase = TypewriterPhase.typing;
    notifyListeners();
    _timer = Timer.periodic(typeStep, (_) {
      if (_shown.length >= _target.length) {
        _cancel();
        _hold();
        return;
      }
      _shown = _target.substring(0, _shown.length + 1);
      notifyListeners();
      // The message completes ON its final character tick — the completed
      // state must not wait for one more (cancelled) tick.
      if (_shown.length >= _target.length) {
        _cancel();
        _hold();
      }
    });
  }

  void _startErasing() {
    _cancel();
    if (instant || _shown.isEmpty) {
      _shown = '';
      _phase = TypewriterPhase.idle;
      notifyListeners();
      _startTyping();
      return;
    }
    _phase = TypewriterPhase.erasing;
    notifyListeners();
    _timer = Timer.periodic(eraseStep, (_) {
      if (_shown.isEmpty) {
        _cancel();
        _startTyping();
        return;
      }
      _shown = _shown.substring(0, _shown.length - 1);
      notifyListeners();
      if (_shown.isEmpty) {
        // Same rule as typing: the state transition lands on the tick that
        // completes it.
        _cancel();
        _startTyping();
      }
    });
  }

  /// THE HOLD — a real phase with a real duration. When it elapses the
  /// machine asks its rotation source what comes next; only a DIFFERENT
  /// message interrupts the hold.
  void _hold() {
    if (_shown != _target) {
      // Defensive: only complete messages can hold. A partially-typed
      // message (paused mid-type) resumes typing instead.
      _startTyping();
      return;
    }
    _phase = TypewriterPhase.holding;
    notifyListeners();
    _cancel();
    _timer = Timer(holdDuration, () {
      if (_paused) return;
      final next = nextMessage?.call();
      if (next != null && next.isNotEmpty && next != _target) {
        _target = next;
        _startErasing();
        return;
      }
      // Nothing new: hold again.
      _hold();
    });
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }
}

// ── WIDGET ────────────────────────────────────────────────────────────────

/// The heading surface. Composes:
///   * contextual supersedes — a NEW priority-1/2 message interrupts whatever
///     is showing (identical strings no-op, never reanimating).
///   * a generous fallback rotation — when nothing contextual exists, the
///     greeting types once, then feature messages rotate one at a time on a
///     slow cadence. Never a rapid advertising carousel, never a perpetual
///     ticker: the rotation is the MACHINE's hold phase, and the machine is
///     PAUSED whenever Home is not the shell's active tab.
class AzTypewriterHeading extends ConsumerStatefulWidget {
  const AzTypewriterHeading({super.key});

  @override
  ConsumerState<AzTypewriterHeading> createState() =>
      _AzTypewriterHeadingState();
}

class _AzTypewriterHeadingState extends ConsumerState<AzTypewriterHeading> {
  /// The rotation source the machine asks at every hold end: the current
  /// CONTEXTUAL message when one exists (a contextual message holds until
  /// it changes — no carousel), otherwise the fallback ladder (greeting
  /// first, then feature copy, one at a time).
  String? _nextRotationMessage() {
    final contextual = _currentContextual();
    if (contextual != null) return contextual.text; // holds until it changes
    if (_scheduled == null) return _greetingMessage().text;
    final next = kHeadingFeatureMessages[
        _featureIndex % kHeadingFeatureMessages.length];
    _featureIndex++;
    return next.text;
  }

  late final TypewriterMachine _machine = TypewriterMachine(
      holdDuration: _featureRotationInterval,
      nextMessage: _nextRotationMessage);
  int _featureIndex = 0;
  HomeHeadingMessage? _scheduled;

  /// Generous pause between fallback rotations (brief §2) — also the hold
  /// duration of every completed message. Long enough to read comfortably
  /// twice; feature copy is a fallback, not a ticker.
  static const _featureRotationInterval = Duration(seconds: 9);

  @override
  void initState() {
    super.initState();
    // The first message is scheduled on the first frame (providers readable).
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncMessage());
  }

  @override
  void dispose() {
    _machine.dispose();
    super.dispose();
  }

  /// A settled, COMPLETED credit that landed today — the same authoritative
  /// /wallet/history snapshot Home already renders, the same helper logic
  /// the NEW-D greeting used. Null when nothing qualifies.
  static String? _settledInflowToday(List<TransactionSummary> txns) {
    for (final t in txns) {
      if (!t.isCredit || t.status != 'COMPLETED') continue;
      final created = t.createdAt;
      if (created == null) continue;
      final now = DateTime.now();
      if (created.year == now.year &&
          created.month == now.month &&
          created.day == now.day) {
        return t.symbol == 'GHS'
            ? AzMoney.ghs(t.amount)
            : AzMoney.usdc(t.amount);
      }
    }
    return null;
  }

  /// True when an ACTIVE Susu group's next pending cycle runs tomorrow —
  /// same authoritative `nextCycle` the hub tile counts down from.
  static bool _susuDueTomorrow(List<SusuSummary> groups) {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    for (final g in groups) {
      if (g.status != SusuStatus.active) continue;
      final runAt = g.nextCycle?.scheduledRunAt;
      if (runAt == null) continue;
      if (runAt.year == tomorrow.year &&
          runAt.month == tomorrow.month &&
          runAt.day == tomorrow.day) {
        return true;
      }
    }
    return false;
  }

  /// The highest-priority CONTEXTUAL message, or null. Derived from the
  /// already-loaded Home inputs only — no extra fetch, nothing invented.
  HomeHeadingMessage? _currentContextual() {
    final summary = ref.read(homeSummaryProvider);
    final susuGroups = ref.read(susuListProvider).valueOrNull ?? const [];
    return HeadingMessageSelector.topContextual(
      susuDueTomorrow: _susuDueTomorrow(susuGroups),
      moneyArrivedToday: _settledInflowToday(summary.recentTransactions),
    );
  }

  /// Baseline greeting via the NEW-D brain (part of day + name).
  HomeHeadingMessage _greetingMessage() {
    final username = ref.read(authProvider).user?.username ?? '';
    final line = AzGreetingBrain.resolve(AzGreetingInputs(
      now: DateTime.now(),
      username: username,
      moneyArrivedToday: null,
      escrowReleasingInHours: null,
      susuDueTomorrow: false,
      depositAwaitingApproval: false,
    ));
    return HomeHeadingMessage(
      text: line.text,
      priority: HomeHeadingPriority.greeting,
      glyph: AzGreetingBrain.glyphFor(line.tone),
    );
  }

  /// A contextual message interrupts IMMEDIATELY when the real inputs
  /// change — it does not wait for the machine's hold to elapse.
  void _maybeSupersedeContextual(bool shellActive) {
    if (!mounted || !shellActive) return;
    final contextual = _currentContextual();
    if (contextual != null) _schedule(contextual);
  }

  void _schedule(HomeHeadingMessage message) {
    if (_scheduled != null && _scheduled!.text == message.text) return;
    _scheduled = message;
    if (!AzMotion.of(context).travel) {
      _machine.showImmediately(message.text);
    } else {
      _machine.showMessage(message.text);
    }
    // AUDIT §7: the scheduling path itself honours shell visibility —
    // if Home is NOT the active tab at the moment a message is armed,
    // the machine pauses immediately (timers cancelled, text kept).
    // Realistically reachable only when a message arms between builds
    // (the post-frame first schedule, or a contextual supersede landing
    // on a rebuild where the tab already switched); the shell must
    // never see rotation from an inactive tab.
    if (!ref.read(homeShellActiveProvider) && !_machine.paused) {
      _machine.pause();
    }
    if (mounted) setState(() {});
  }

  /// First-frame schedule: contextual first (priority), else greeting.
  void _syncMessage() {
    if (!mounted || _scheduled != null) return;
    final contextual = _currentContextual();
    _schedule(contextual ?? _greetingMessage());
  }

  @override
  Widget build(BuildContext context) {
    final azColors = ref.watch(themeProvider).colors;
    // Watch the real inputs so provider-driven changes (a refresh landing a
    // settled inflow, a susu cycle appearing) supersede on this build.
    ref.watch(homeSummaryProvider.select((s) => s.recentTransactions.length));
    ref.watch(susuListProvider);

    // AUDIT — the typewriter must not rotate while Home is not the shell's
    // active tab (MainWrapper keeps pages mounted): the machine is paused
    // the instant Home loses active visibility and resumes on re-entry.
    final shellActive = ref.watch(homeShellActiveProvider);
    if (shellActive && _machine.paused) {
      _machine.resume();
    } else if (!shellActive && !_machine.paused && _scheduled != null) {
      _machine.pause();
    }

    // Contextual supersede is event/state driven: a fresh higher-priority
    // message arrives through ref.listen on the real inputs, not through a
    // polling timer. (The machine still asks its rotation source at every
    // hold end, so nothing is lost while the inputs are quiet.)
    ref.listen(
        homeSummaryProvider
            .select((s) => s.recentTransactions.length), (_, __) {
      _maybeSupersedeContextual(shellActive);
    });
    ref.listen(susuListProvider, (_, __) {
      _maybeSupersedeContextual(shellActive);
    });

    final glyph = _scheduled?.glyph;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AzSpace.lg),
      child: AnimatedBuilder(
        animation: _machine,
        builder: (context, _) => Row(
          children: [
            if (glyph != null) ...[
              Icon(glyph, size: 20, color: azColors.accent),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                _machine.shownText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AzText.display.copyWith(color: azColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
