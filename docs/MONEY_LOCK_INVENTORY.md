# Money lock inventory

What the member money privacy lock actually covers today, taken from
`lib/router/app_router.dart` by reading each `GoRoute` block rather than by
searching for the guard word (a search attributes a later guard to an earlier
route, which is how the first version of this list was wrong).

The rule the lock enforces: a member who has not unlocked money on Home can
still browse catalogues, businesses, social surfaces and stories. They must not
see balances, amounts, references, saved bill details, payment initiations or
receipts, and a blocked surface must exclude that content from accessibility
semantics rather than blur it.

Two mechanisms exist:

- `MoneyRouteGuard` — the whole route renders a locked explanation instead of
  the screen. Used where the screen has no reason to exist while locked.
- `MoneyLockGate` — a section inside an otherwise browsable screen. Used where
  the screen is a catalogue and only part of it is money (`/bills` is the model
  case: the hub is public, `YOUR BILLS` is gated).

## Guarded at the route (32 routes)

The count is the table below, row by row. `test/router/money_lock_route_coverage_test.dart`
enforces 27 of them by name; the four Bills child routes (`/bills/add`, `/bills/pay/:accountId`,
`/bills/request`, `/bills/request/:requestId`) are enforced by the Bills suite, and `/bills`
is listed because the hub itself is deliberately public with only its saved section gated.

| Route | Mechanism | Notes |
| --- | --- | --- |
| `/account/activity` | `MoneyRouteGuard` | amounts and references in the feed |
| `/bills/add` | `MoneyRouteGuard` | a saved reference is money |
| `/bills/pay/:accountId` | `MoneyRouteGuard` | quote and payment |
| `/bills/request` | `MoneyRouteGuard` | shares account details with a contact |
| `/bills/request/:requestId` | `MoneyRouteGuard` | shared bill details |
| `/bills` | hub public, `YOUR BILLS` in `MoneyLockGate` | catalogue stays browsable |
| `/savings` | `MoneyRouteGuard` inside `BubbleMorphDestination` | Hero pair preserved |
| `/payment-requests` | `MoneyRouteGuard` | request amounts |
| `/request/:token` | `MoneyRouteGuard` | public link to a money request |
| `/receive` | `MoneyRouteGuard` | address and QR |
| `/deposit` | `MoneyRouteGuard` | funding |
| `/send` | `MoneyRouteGuard` | transfer |
| `/withdraw` | `MoneyRouteGuard` | payout destination |
| `/convert` | `MoneyRouteGuard` | GHS/USDC conversion |
| `/card-transfer` | `MoneyRouteGuard` | card-to-card |
| `/susu` | `MoneyRouteGuard` | group balances |
| `/susu/:id` | `MoneyRouteGuard` | group ledger |
| `/susu/:id/contract` | `MoneyRouteGuard` | contract terms and amounts |
| `/spending-insights` | `MoneyRouteGuard` | spending totals |
| `/round-up` | `MoneyRouteGuard` | round-up savings amounts |
| `/my-orders` | `MoneyRouteGuard` | order totals and payment state |
| `/trade/:tradeId` | `MoneyRouteGuard` | trade amount, counterparty, payment method |
| `/vault/:vaultId/yield` | `MoneyRouteGuard` | vault yield figures |
| `/storefront/staking` | `MoneyRouteGuard` | staked amounts and yield |
| `/susu/completion` | `MoneyRouteGuard` | group payout amounts |
| `/worker/payroll` | `MoneyRouteGuard` | wage amounts |
| `/worker/ewa` | `MoneyRouteGuard` | earned wage access |
| `/business-market/dine-in/:tabId` | `MoneyRouteGuard` | a running tab is money owed |
| `/business-market/orders` | `MoneyRouteGuard` | order totals and payment state |
| `/business-market/invoices` | `MoneyRouteGuard` | amounts owed and paid |
| `/business-market/invoices/:invoiceId` | `MoneyRouteGuard` | invoice amount, payment state, private paperwork |
| `/wallet-pass/:passType/:itemId` | `MoneyRouteGuard` | a pass can carry stored value and payment credentials |

## Guarded inside the screen, not at the route

These read `moneyAccessProvider` themselves, so a route-level guard would be
redundant. They were listed as unguarded in the first version of this file
because the audit only looked at route blocks; a screen-level gate is invisible
from the router.

| Route | Mechanism |
| --- | --- |
| `/transactions` | `TransactionHistoryScreen` watches `moneyAccessProvider` |

## The four open surfaces: decided 2026-10-31

Each was a candidate, not a conclusion. The owner decided all four. A section
gate is not a route gate, so the "guarded at the route" count does not include
the two that are gated inside the screen.

| Surface | Decision | Where the gate lives |
| --- | --- | --- |
| Business paperwork (`/business-market/orders`, `/business-market/invoices`, `/business-market/invoices/:invoiceId`) | **Gated at the route.** Order totals, amounts owed, payment state and attached private paperwork are the member's money, even when the document is business-shaped. | `MoneyRouteGuard` on all three routes |
| Transit seats (`/marketplace/transit/:tripId/seats`) | **Section gated.** The seat map, the fare and the selection stay browsable: they are catalogue. Reserving and paying are not. | `MoneyLockGate(compact: true)` wraps only the dock's commitment button ("Continue to book"). Because the guard replaces the button, a locked tap cannot hold a seat. |
| Loyalty (`/loyalty-cards`, `/wallet-pass/:passType/:itemId`) | **Split.** Points are not money, so the loyalty list stays open. A wallet pass is a stored-value representation and can carry payment credentials. | `/loyalty-cards` unguarded (points only: `pointsBalance` is the sole money-shaped field, and it is reproducible, not owned money); `/wallet-pass/...` behind `MoneyRouteGuard` |
| Susu position picker (`/susu/position-picker`) | **Stays open.** It chooses a hand before joining. It shows no amount, holds no money and commits nothing; the commitment is the contract at `/susu/:id/contract`, already gated. | none here; `/susu`, `/susu/:id`, `/susu/:id/contract` and `/susu/completion` remain route-guarded |

Why the picker is genuinely not money: it renders a wheel of positions, a legend
and the member list, and calls back with an index. There is no quote, no hold, no
payment call and no balance in the widget, so gating it would hide browsing
without protecting anything.

## Deliberately not gated

`/marketplace`, `/business-market`, `/business/:bizId`, `/worker` profiles,
`/friends`, `/messages`, `/notifications`, `/settings`, `/profile/edit`,
`/discover/storefronts`, `/loyalty-cards`, `/marketplace/transit/:tripId/seats`
(the route; its commitment is gated inside), `/susu/position-picker`, story
surfaces. Prices on a public menu, a business profile or a story are catalogue
data; the member is not exposing their own money by looking at them.

## Rules for adding a surface

1. Money the member owns, owes, has paid, or is about to pay: gate it.
2. A catalogue with a money section: `MoneyLockGate` the section, keep the rest
   browsable.
3. Never render a real amount behind a blur. Either the section is gated, or the
   amount is not built at all.
4. A blocked tap gives selection haptics and a hint pointing at the Home lock.
   It never navigates, quotes, requests or pays.
5. The backend remains the authority for authz, KYC, limits and idempotency.
   This lock is a local privacy gate, not a security boundary.
