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

## Guarded at the route (26 routes)

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

## Guarded inside the screen, not at the route

These read `moneyAccessProvider` themselves, so a route-level guard would be
redundant. They were listed as unguarded in the first version of this file
because the audit only looked at route blocks; a screen-level gate is invisible
from the router.

| Route | Mechanism |
| --- | --- |
| `/transactions` | `TransactionHistoryScreen` watches `moneyAccessProvider` |

## Money-bearing routes still open — candidates, not conclusions

Each needs one decision: gate it, gate a section, or record why it is not money.

| Route | What it plausibly exposes |
| --- | --- |
| `/business-market/orders`, `/business-market/invoices`, `/business-market/invoices/:invoiceId` | invoices and money owed; business-side, needs a product call on whether a locked member may still see business paperwork |
| `/marketplace/transit/:tripId/seats` | seat prices at the payment boundary; the seat map is catalogue, the purchase is not |
| `/loyalty-cards`, `/wallet-pass/:passType/:itemId` | stored-value representations; points are not money, but a wallet pass can carry value |
| `/susu/position-picker` | picks a hand before joining; intermediate step, not an amount |

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
