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

## Guarded today (20 routes)

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

## Money-bearing routes with no gate — candidates, not conclusions

These were found by reading route blocks, not by watching them run. Each needs
one decision: gate it, gate a section of it, or record why it is not money.

| Route | What it plausibly exposes |
| --- | --- |
| `/transactions` | transaction list (may be a legacy duplicate of `/account/activity`) |
| `/storefront/staking` | staked amounts and yield |
| `/vault/:vaultId/yield` | vault yield figures |
| `/business-market/orders`, `/business-market/invoices`, `/business-market/invoices/:invoiceId` | invoices and money owed |
| `/business-market/dine-in/:tabId` | a running tab to pay |
| `/marketplace/transit/:tripId/seats` | seat prices at the payment boundary |
| `/worker/payroll`, `/worker/ewa` | payroll and earned-wage amounts |
| `/loyalty-cards`, `/wallet-pass/:passType/:itemId` | stored-value representations |
| `/susu/position-picker`, `/susu/completion` | susu hand and payout amounts |

## Deliberately not gated

`/marketplace`, `/business-market`, `/business/:bizId`, `/worker` profiles,
`/friends`, `/messages`, `/notifications`, `/settings`, `/profile/edit`,
`/discover/storefronts`, story surfaces. Prices on a public menu, a business
profile or a story are catalogue data; the member is not exposing their own
money by looking at them.

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
