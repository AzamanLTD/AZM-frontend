# Navigation defect — RED-run evidence (pre-fix), 2026-10-28

Real integration harness: the app's own global GoRouter (`appRouter`,
real route table + redirect + observers), real SplashScreen waterfall,
real MainWrapper shell, demo boot. Suite:
`test/router/startup_shell_navigation_integration_test.dart`
(commit state: diagnostics + postFrame splash fix only; the navigation
architecture UNCHANGED — the defect still in place).

Run: `flutter test --concurrency=1 test/router/startup_shell_navigation_integration_test.dart`
Result: `+1 -4` — "demo boot" PASSES; ALL FOUR journey tests FAIL
(Convert, Send, Settings, Marketplace destination), each on the
shell-element-identity assertion: a SECOND MainWrapper instance mounts
without the user requesting it.

## The captured NAV timeline (Convert journey)

```
[NAV] PUSH -> _PageBasedMaterialPageRoute[PAGE([<'/'>])]         ← cold start (splash)
[SPLASH] initState #1
[SPLASH] _exitTo fired after 2s branding floor (builder MainWrapper)
[NAV] REPLACE -> MaterialPageRoute[IMPERATIVE(anon)]  prev: PAGE('/')   ← pushReplacement: '/' page → ANONYMOUS MainWrapper #1.
[SPLASH] dispose #1
                                                                  ← GoRouter still believes location == '/': DIVERGENCE
[NAV] PUSH -> _PageBasedMaterialPageRoute[PAGE([<'/'>])]         ← user pushes /convert: GoRouter reconciles pages to
[NAV] PUSH -> _CustomTransitionPageRoute[PAGE([<'/convert'>])]     [/' splash page, /convert page] — a NEW SplashScreen
[SPLASH] initState #2                                             ← SPLASH RE-INSTANTIATED BELOW CONVERT
[SPLASH] _exitTo fired after 2s branding floor
[NAV] REPLACE -> MaterialPageRoute[IMPERATIVE(anon)]
        prev: _CustomTransitionPageRoute[PAGE([<'/convert'>])]   ← pushReplacement disposes THE TOPMOST ROUTE —
                                                                     THE CONVERT SCREEN — and lands MainWrapper #2.
Failure: shell element was RECREATED (duplicate MainWrapper is the defect)
```

## Root cause (proven)

1. The splash exit is an imperative `Navigator.pushReplacement` that
   swaps the router-owned `/` page for an anonymous `MainWrapper`
   route. GoRouter's declarative state still says location = `/`.
2. Every subsequent `context.push('/<destination>')` makes GoRouter
   rebuild the page stack from its state — `['/', '/<destination>`] —
   which re-instantiates SplashScreen BELOW the destination and evicts
   the anonymous shell route.
3. The hidden splash's waterfall completes ~2s later and calls
   `Navigator.pushReplacement` again. Per the framework source
   (`navigator.dart`, `_pushReplacementEntry` →
   `_history.lastWhere(_RouteEntry.isPresentPredicate).complete(...)`),
   pushReplacement disposes the TOPMOST route — the screen the user is
   looking at — and pushes a fresh MainWrapper: Home tab, fresh tab
   state, socket re-subscribe, provider refetch (the "part of Azaman
   did not load" reports).

Explains every reported symptom: the ~2s bounce to Home, "repeating
sometimes works" (the re-instantiated splash only fires once per
page-stack rebuild), unresponsive controls (multiple shell instances
fighting over the appShellBus/sockets), and partial-load error surfaces
on the recreated shell's refetches. Reproduced on physical devices,
Web, demo and authenticated modes — the mechanism is
mode-independent.
