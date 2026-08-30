# AZM Platform Architecture

## Purpose

AZM is being built as a unified financial, commerce, mobility, hospitality, and social platform. The architecture must let new verticals reuse the same identity, trust, money, realtime, presentation, and observability foundations instead of creating parallel systems.

The guiding rule is:

> **One platform, many experiences, one source of truth for money and state.**

A vertical may have its own domain rules and UI, but it must plug into shared platform contracts.

## Master delivery sequence

The product roadmap follows this order unless a dependency or safety review proves a different sequence is necessary:

1. Foundation
2. Retail
3. Hotel
4. Transit
5. Restaurant
6. Escrow
7. Employee
8. EWA — only after the required compliance and product boundaries are ready
9. Portal V2
10. Analytics and performance

The sequence is intentionally dependency-driven. Retail establishes the reusable storefront/commerce primitives; hotel, transit, and restaurant then consume those foundations instead of becoming independent product stacks.

## System layers

### 1. Identity and trust

Identity is shared across every vertical. Authorization is evaluated at the server boundary for every protected operation.

Trust primitives include:

- authenticated customer identity
- business ownership and business identity
- KYC/KYB boundaries where applicable
- roles and permissions
- customer/business isolation
- abuse and risk controls
- immutable auditability for sensitive actions

No client-side role, price, balance, inventory, or payment state is authoritative.

### 2. Unified money layer

All financial activity ultimately uses the platform's existing ledger/transaction foundations.

Domain services may describe a payment as checkout, escrow funding, invoice payment, booking payment, payroll, EWA, or another business concept, but they must resolve into authoritative financial state transitions.

Financial operations must be:

- idempotent
- authorized
- auditable
- retry-safe
- concurrency-safe
- explicitly stateful
- reconcilable

A UI success state is never treated as proof that money moved. The backend transaction/ledger state is authoritative.

### 3. Domain verticals

Each vertical owns its domain rules while sharing platform primitives.

#### Retail

`Storefront → collection → product discovery → quick look → variant/modifier → cart → checkout → order → fulfillment`

#### Hotel

`Search/date context → room discovery → availability → room selection → booking → payment/escrow → stay state`

#### Transit

`Vehicle/context → route/trip → seat map → hold → payment → ticket/boarding pass → journey state`

#### Restaurant

`Flip-book/menu → customization → tray/cart → checkout → preparation → tracking → completion`

The same checkout, identity, notification, realtime, analytics, and money principles apply across these journeys, while each vertical retains its own domain state machine.

### 4. Storefront / SDUI presentation layer

Storefront presentation is server-driven, but the server does not send arbitrary executable UI.

The normalized flow is:

`Portal/editor → Storefront Contract → Flutter models → Widget Registry → Renderer`

The Flutter registry maps stable `widgetType` identifiers to trusted native implementations. Unknown widget types must fail safely through a fallback renderer.

The contract should remain platform-neutral so the same storefront definition can eventually be consumed by the customer app, Business Portal previews, and future clients without duplicating layout logic.

Existing storefront primitives include:

- hero/header
- product grid
- collections
- reviews
- contact/location
- promotions
- social feed
- live statistics
- video/media
- action surfaces

New widgets should be added to the shared registry rather than implemented as one-off screens.

### 5. Realtime layer

Realtime is a delivery mechanism, not the source of truth.

Sockets/WebRTC/push may communicate:

- order changes
- payment/escrow events
- chat
- presence
- social activity
- merchant/customer notifications
- live operational state

Every realtime event must be safe to receive more than once, safe to receive late, and safe to receive out of order. Clients reconcile against authoritative state where necessary.

### 6. Social layer

Social is a first-class platform capability, not a marketing add-on.

The long-term experience is intended to connect:

`people → businesses → places → products/services → activity → conversation → discovery → transaction`

Existing foundations such as friendships, business follows, chat, reviews, social notifications, and storefront social surfaces should converge into a coherent graph instead of separate isolated features.

Commerce activity should be able to become social discovery without leaking private financial information. Examples include public reviews, followed-business activity, recommendations, shared experiences, and merchant/community interactions.

Private financial details, balances, payment instruments, and sensitive transaction metadata must never become social events by accident.

### 7. Notifications and eventing

Notifications are derived from domain events rather than being the mechanism that changes state.

A durable state transition happens first; notifications then fan out through the appropriate channels:

`domain event → notification policy → realtime/push/in-app delivery`

Delivery may fail or repeat without rolling back the underlying transaction.

### 8. Observability and reconciliation

As AZM becomes a financial platform, every critical flow needs enough information to answer:

- What happened?
- Who initiated it?
- What state existed before it?
- What state exists now?
- Which financial transaction was created?
- Was the request retried?
- Which service/event caused the transition?
- Can the result be reconciled later?

Critical money/order transitions should therefore be observable without exposing sensitive information to clients.

## State-machine discipline

Every important domain object should have explicit legal transitions.

For example, an order may progress through a controlled lifecycle such as:

`CREATED → AWAITING_PAYMENT → PAID → DELIVERED → COMPLETED`

with separately defined cancellation/refund/dispute paths.

Rules:

- illegal transitions are rejected
- terminal states cannot be resurrected by stale events
- duplicate events are harmless
- concurrent transitions are serialized or conditionally committed
- historical state is preserved where required for audit/reconciliation

## Data authority

Authority is deliberately layered:

- **Client:** intent, presentation, optimistic interaction
- **API:** authorization and domain validation
- **Service/domain layer:** business rules
- **Database transaction:** atomic state/inventory guarantees
- **Ledger/payment subsystem:** authoritative financial movement
- **Realtime/push:** eventual delivery of state changes

The client must never become the final arbiter of a financial or inventory decision.

## Performance architecture

Performance is treated as a platform concern.

Flutter startup should render the first meaningful frame with only minimum synchronous initialization. Non-critical hydration—authentication restoration where possible, sockets, WebRTC, push foreground setup, business state, trade history, and secondary hydration—should be coordinated after the first frame.

Navigation should lazily mount expensive experiences while preserving state where user experience requires it.

Rendering should favor:

- lazy lists
- bounded image decoding
- stable widget keys
- localized rebuilds
- cached/normalized data
- explicit disposal of realtime/media resources

Performance work must be measured on physical devices/profile builds rather than inferred from source inspection alone.

## Vertical-extension rule

When adding a new vertical, do not create a second version of an existing primitive.

Instead ask:

1. Which shared contract does this consume?
2. Which new domain state does it introduce?
3. Which existing money/realtime/notification primitives can it reuse?
4. Which part must remain vertical-specific?
5. Can the Business Portal configure it through the same normalized contract?
6. Can the customer app render it through the existing registry?
7. How will it be audited, retried, reconciled, and observed?

This keeps AZM extensible as the number of countries, merchants, transactions, and social interactions grows.

## Current implementation focus

The immediate retail batch is hardening the first complete commerce transaction path:

`Storefront → variant → cart → idempotent checkout → authoritative validation → inventory reservation → payment/escrow → order → history → fulfillment`

The work is intentionally strengthening the foundation that hotel, transit, restaurant, escrow, and future social experiences will reuse.
