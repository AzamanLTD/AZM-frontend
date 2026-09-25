# AZAMAN Phase 1 — Experience Architecture & Repository Audit

**Branch:** `phase-1-experience-architecture`  
**Scope:** AZM-frontend first; AZM-backend and AZM-businessPortal are architectural dependencies.  
**Status:** Foundation / audit baseline

## 1. Purpose

This phase deliberately does **not** replace working marketplace or storefront systems. The repository already contains substantial infrastructure for motion, Storefront SDUI, preview rendering, themes, templates, transit seat geometry, and Business Portal editing. The goal is to tighten the architecture around those existing systems instead of creating parallel abstractions.

## 2. Current architectural facts

### Frontend

- Riverpod is the canonical state-management layer.
- GoRouter is present for navigation.
- `MotionTokens` already centralizes durations, curves, staggering and reduced-motion behavior.
- `storefront/` already contains models, providers, services, widgets and core rendering infrastructure.
- `StorefrontRenderer` and `StorefrontPreviewRenderer` share the widget registry, which is the correct foundation for WYSIWYG parity.
- `LayoutJson` already carries schema-version information.
- Transit already has a dedicated high-performance `BusSeatSelector` using a geometry solver + `CustomPainter` + `InteractiveViewer`, rather than one Flutter widget per seat.
- The dependency graph already contains animation, cached networking, maps, realtime, Sentry, media, notifications and accessibility-relevant primitives.

### Business Portal

The storefront editor already provides a substantial authoring surface: canvas editing, widget palette, themes, templates, Magic Layout, undo/redo, history, health score, QR, analytics, preview and publishing. Phase 1 therefore treats the Portal as the **authoring environment** for the same storefront contract rather than designing a new editor from scratch.

### Backend

The backend already exposes and tests marketplace concepts including follows, advertising, stories, trust, penalties, reservations, transit vehicles/seats and Smart Escrow. Financial and marketplace flows must therefore integrate with existing backend contracts and idempotency rather than inventing client-side financial state machines.

## 3. Architectural decision

AZAMAN should converge on one experience pipeline:

```text
Business Portal
    │
    │ author / preview / validate / publish
    ▼
Storefront Contract
    │
    ├── schemaVersion
    ├── category
    ├── theme
    ├── components
    ├── component configuration
    ├── interaction configuration
    └── feature configuration
    │
    ▼
Validation + versioning + capability checks
    │
    ▼
Flutter Storefront Renderer
    │
    ├── Restaurant experience
    ├── Hotel experience
    ├── Transit experience
    └── Retail experience
```

The category should control **experience primitives**, not merely colors. A restaurant is not a generic storefront with a restaurant color; a hotel is not a generic grid with hotel data.

## 4. Non-negotiable rule: do not duplicate existing foundations

Before introducing a new utility, search for an existing implementation first.

Do **not** add:

- another motion-token file;
- another generic storefront renderer;
- another preview renderer;
- another seat-selection implementation;
- another state-management layer;
- another HTTP abstraction;
- another theme abstraction;
- another ad-hoc marketplace card framework.

If an existing foundation is inadequate, improve it at its source and migrate callers gradually.

## 5. Phase 1 priorities

### P1 — Experience contract

Create a documented contract between Portal and Flutter. Every storefront component should eventually have:

```text
id
kind
schemaVersion
position/order
visibility
content
style
interaction
analytics
capabilities
```

The renderer must ignore unknown optional fields safely and expose a controlled fallback for unknown component kinds.

### P2 — Capability model

Category-specific experiences should advertise capabilities instead of scattering `if (category == ...)` throughout screens.

Conceptual model:

```dart
enum StorefrontCapability {
  menuFlipbook,
  dishCustomization,
  reservation,
  hotelFloorMap,
  roomExplorer,
  transitSeatMap,
  boardingPass,
  retailProductGrid,
  productVariants,
  pickup,
  delivery,
}
```

The exact enum should be reconciled with the existing storefront models before implementation.

### P3 — Motion governance

Every new animation should consume `MotionTokens`. Simple mount/press/fade/slide effects should use the existing `flutter_animate` policy. Complex geometry may retain explicit controllers.

Animation priorities:

1. interaction feedback;
2. state transitions;
3. navigation continuity;
4. content discovery;
5. celebration.

Animation must never delay a financial action or hide whether a transaction succeeded.

### P4 — Performance budgets

Every new marketplace experience must be tested against:

- first meaningful paint;
- scroll smoothness;
- image decode pressure;
- rebuild frequency;
- animation controller count;
- memory pressure on long lists;
- offline/slow-network behavior.

The existing transit selector demonstrates the desired approach: solve geometry once, cache stable layout data, and avoid rebuilding expensive objects on every tap.

## 6. Marketplace experience architecture

### Restaurant

Primary interaction should remain the flip-book, but it should become a genuine ordering surface:

```text
Cover
 → section tabs
 → page turn
 → dish spotlight
 → customization
 → add to tray
 → tray preview
 → checkout
```

Use page-turn motion only for meaningful navigation. Avoid continuous decorative animation while the user is reading.

Recommended additions:

- persistent section index;
- page progress indicator;
- dish image prefetch for adjacent pages;
- sticky tray affordance;
- animated quantity controls;
- dietary/allergen indicators;
- kitchen availability state;
- pickup/delivery/reservation mode;
- order-status transition after checkout.

### Hotel

Hotel should be spatial rather than card-grid-first:

```text
Hotel hero
 → amenity discovery
 → floor selector
 → floor plan
 → available room highlights
 → room selection
 → room-specific gallery
 → room layout
 → amenities
 → rate / cancellation
 → booking
```

The selected room must be a first-class object. Tapping a room should expose its actual room number/identifier, floor, bed configuration, occupancy, layout, photos and rate when available.

### Transit

Transit should feel like a journey rather than a ticket marketplace card:

```text
Trip discovery
 → operator / vehicle
 → boarding context
 → deck/floor
 → seat map
 → seat confirmation
 → passenger details
 → payment
 → boarding pass
```

The current seat selector foundation is good. Future work should focus on visual hierarchy, seat context, accessibility, selected-seat storytelling and transition continuity rather than replacing the geometry engine.

### Retail

Retail should be merchandise-first and visually distinct from restaurants/hotels:

```text
Store hero
 → curated boxes / collections
 → product discovery
 → product detail
 → variant selection
 → quantity
 → cart
 → delivery/pickup
 → order tracking
```

Recommended signature component: **Collection Box**. A business can publish boxes such as “New Arrivals”, “Staff Picks”, “Weekend Essentials”, “Bundle & Save”, or category-specific curated sets. Each box can have its own layout density and merchandising rule.

## 7. Store page redesign principle

A marketplace business page should not be a banner followed by generic sections.

Instead, the Portal should compose a narrative using category-specific primitives.

Example:

```text
Restaurant:
  identity → open status → menu → popular dishes → story → reservation → reviews

Hotel:
  identity → availability → floors → rooms → amenities → location → policies

Transit:
  operator → next departures → route → vehicle → seats → boarding information

Retail:
  identity → collections → products → offers → delivery → reviews
```

The Portal should control ordering, visibility, sizing, content, media and selected style properties while the Flutter client enforces safe bounds and capability compatibility.

## 8. WYSIWYG parity requirements

The Portal preview and Flutter production renderer should consume the same widget registry and the same normalized storefront JSON.

A component is not considered production-ready if:

- it renders differently in Portal preview and Flutter without an intentional responsive reason;
- its configuration can be authored in Portal but is ignored in Flutter;
- its Flutter representation cannot be represented in the Portal;
- invalid configuration can publish without validation.

## 9. Financial interaction rule

Escrow, salary advance, transfers and marketplace payments are financial state machines. The UI can animate state, but the backend remains authoritative.

Client requirements:

- every mutating financial request must tolerate retry;
- never infer success from animation completion;
- show pending/confirmed/failed distinctly;
- preserve transaction IDs;
- prevent duplicate taps while a request is in flight;
- recover gracefully after app termination;
- refresh authoritative state after reconnect;
- show escrow party/state clearly to both sides.

Smart Escrow should be reachable from chat as an action and also as a dedicated transaction workspace.

## 10. Employee experience direction

Employee functionality should be treated as a role-aware workspace surfaced from Settings rather than as unrelated screens.

Conceptual hierarchy:

```text
Settings
 └── Workspaces
      ├── Company A
      │    ├── Today
      │    ├── Schedule
      │    ├── Tasks
      │    ├── Team
      │    ├── Chat
      │    ├── Payroll
      │    └── Requests
      └── Company B
```

Salary advance should be represented as an explicit financial product with:

- employer eligibility;
- configurable maximum percentage;
- available amount;
- fee/interest disclosure;
- repayment date;
- repayment amount;
- application status;
- repayment history.

The client must never calculate the authoritative repayment amount independently of the backend.

## 11. Quality gates for every future phase

Before merging a feature:

1. `flutter analyze` must be clean.
2. Existing tests must pass.
3. New stateful components require widget tests.
4. Financial actions require retry/idempotency tests at the integration boundary.
5. Storefront components require Portal-preview and Flutter-renderer parity checks.
6. Animations require reduced-motion coverage.
7. Marketplace lists require loading, empty, error and offline states.
8. Every tappable control needs an accessible semantic label.
9. No animation may be the sole indication of a financial state change.
10. Expensive painters/layout solvers must not run unnecessarily during ordinary state updates.

## 12. What Phase 1 intentionally does NOT do

This phase does not redesign every screen. It establishes the guardrails that let the later marketplace, employee, chat and escrow work remain coherent.

The next implementation phases should modify existing foundations rather than introducing parallel systems.

## 13. Agent implementation rule

For every future agent task, require this sequence:

```text
1. Inspect current implementation.
2. Identify reusable foundation.
3. State what is being changed and why it is materially better.
4. Implement the smallest coherent architectural change.
5. Add tests.
6. Run analyzer/tests/build where available.
7. Inspect regressions.
8. Commit only validated work.
```

A feature that merely looks different is not an improvement. A feature must improve usability, clarity, performance, accessibility, reliability, or business capability without degrading the parts that already work.
