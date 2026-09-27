# r42 — Process-Death Recovery: Exact-Instance Contract & Caller Audit

Follow-up to the independent close-out review (2026-09-27). The v2
operation-instance registry was correct, but its AUTOMATIC recovery rule —
"adopt the newest unfinished operation of the type" (`adoptPending`) — was
unsafe. With an older operation A (key K1, response lost) and a newer
operation B (key K2, response lost) both outstanding, the rule bound B; the
user's reconstruction of A then failed the fingerprint check and opened a
THIRD instance C (K3), orphaning A's key — the exact lost-identity bug the
registry exists to prevent.

## 1. The exact-instance recovery contract (what replaced the rule)

`adoptPending` is DELETED. Recovery now identifies the operation
**INSTANCE**, never merely its TYPE:

1. **Reconstruct first, match exactly.** The flow rebuilds the user's
   request and calls `DurableOperationRegistry.recoverExact(account, type,
   request)`. Only pending instances whose recorded fingerprint **exactly
   matches the reconstructed request** are candidates.
2. **Fail closed on ambiguity.** `DurableRecoveryAmbiguous` returns every
   matching candidate. The flow must present them and let the **user**
   pick (WithdrawalScreen shows a resumption dialog) or refuse. No
   heuristic — not newest, not oldest.
3. **Never replace or orphan.** A failed or ambiguous lookup mutates
   nothing. Older pending instances stay individually recoverable forever
   (until terminally resolved).
4. **In-session retries stay authoritative.** An armed
   `FinancialOperationRef` is exact already: `postFinancial` retries that
   instance by id. `recoverExact` is only for binding a ref after process
   death, when no ref survives.
5. **A materially different request** bound to no matching pending
   instance is a genuinely new operation — but the recovery identity of
   the older instance is never lost: it remains listed and resumable
   (Section 2).

The invariant this PR proves (registry- and wire-level, including full
simulated process death):

> A pending operation A must remain individually recoverable after process
> death even when newer operations of the same type also exist.

## 2. Two recovery paths, both explicit

| Path | Where | Mechanism |
|---|---|---|
| Submit-time exact recovery | `WithdrawalScreen` (flagship flow) | The reconstructed request is matched via `recoverExact`; unique -> resume same instance/same key; none -> genuinely new; ambiguous -> user picks from a dialog (`_bindRecoveredInstance`) |
| Recovery surface | `SecuritySettingsScreen` -> "Unfinished Financial Operations" | Every pending instance in the signed-in account's namespace is listed; the user explicitly resumes one; `ApiClient.retryRecovered` replays the STORED request snapshot — exact by construction (the snapshot IS the recorded fingerprint's body) with the ORIGINAL key |

`retryRecovered` is universal: it makes **every** `postFinancial` caller
process-death recoverable through the security screen without each flow
needing bespoke recovery UI, and it never guesses — the user selects the
instance from the list.

## 3. Caller audit — every `postFinancial` call site

Columns: **instance creation** (how a genuinely new instance begins) ·
**operationId retention** (how the id survives within a session) ·
**post-death recovery** (how the flow can locate the correct instance) ·
**fingerprint reconstruction** · **retirement** (identical for all:
postFinancial's disposition — 2xx and definitive pre-economic 4xx retire
that instance only; 401/409/429, 5xx and network loss retain it).

Unless noted, in-session refs live in memory (screen field or a
`_flowRefs` map keyed by target id) and are lost at process death —
recovery is through the security-settings surface (`retryRecovered`,
stored snapshot), which is exact and needs no reconstruction.

| # | Caller | Endpoint | Operation TYPE | Post-death recovery |
|---|---|---|---|---|
| 1 | `screens/withdrawal_screen.dart` `_fiatRef` | `/withdraw/fiat` | `withdrawal.fiat` | **Submit-time `recoverExact`** + ambiguity dialog + recovery surface |
| 2 | `screens/withdrawal_screen.dart` `_walletRef` | `/wallet/withdraw` | `withdrawal.wallet` | **Submit-time `recoverExact`** + ambiguity dialog + recovery surface |
| 3 | `screens/deposit_screen.dart` `_initiateRef` | `/deposit/fiat/initiate/moolre` | deposit initiate (Moolre) | Recovery surface (snapshot replay) |
| 4 | `screens/vendor_dashboard.dart` `_transferRef` | `/wallet/internal-transfer` | vendor internal transfer | Recovery surface |
| 5 | `screens/vendor_trade_execution.dart` `_acceptRef` | `/trades/accept` | trade accept | Recovery surface |
| 6 | `screens/vendor_trade_execution.dart` `_releaseRef` | `/p2p/complete` | escrow release | Recovery surface |
| 7 | `screens/vault/shared_vault_screen.dart` `_createRef` | `/shared-vaults` | shared-vault create | Recovery surface |
| 8 | `screens/vault/shared_vault_screen.dart` `_depositRef` | `/shared-vaults/<id>/deposit` | shared-vault deposit | Recovery surface |
| 9 | `screens/marketplace/cart_screen.dart` `_checkoutRef` | cart checkout | marketplace checkout | Recovery surface |
| 10 | `storefront/widgets/retail_collection_box_widget.dart` `_checkoutRef` | retail collection box checkout | storefront checkout | Recovery surface |
| 11 | `providers/marketplace_provider.dart` `_initiateRef` | `/trades/initiate` | trade initiate | Recovery surface |
| 12 | `providers/vault_provider.dart` (deposit) | `/vaults/<id>/deposit` | `deposit.<vaultId>` | Recovery surface |
| 13 | `providers/vault_provider.dart` (break) | `/vaults/<id>/break` | `break.<vaultId>` | Recovery surface |
| 14 | `providers/susu_provider.dart` `_createRef` | `/susu/groups` | susu group create | Recovery surface |
| 15 | `providers/susu_provider.dart` `_contractRefs[susuId]` | `/susu/groups/<id>/contract` | `contract.<susuId>` | Recovery surface |
| 16 | `providers/susu_provider.dart` (vouch) | `/susu/vouches` | `vouch.<vouchRecordId>` | Recovery surface |
| 17 | `services/susu_service.dart` `_flowRefs['create']` | `/susu` | susu create | Recovery surface |
| 18 | `services/susu_service.dart` `_flowRefs['cancel.<id>']` | `/susu/<id>/cancel` | `cancel.<susuId>` | Recovery surface |
| 19 | `services/susu_service.dart` `_flowRefs['contract.<id>']` | `/susu/<id>/contract/accept` | `contract.<susuId>` | Recovery surface |
| 20 | `services/susu_service.dart` `_flowRefs['redeem.<token>']` | `/susu/invites/<token>/redeem` | `redeem.<token>` | Recovery surface |
| 21 | `services/friend_service.dart` `send.<friendshipId>` | `/friends/transfer/send` | friend transfer (legacy `clientRequestId` reused as the header value — one identity) | Recovery surface |
| 22 | `services/escrow_service.dart` (per-operation ref) | escrow actions | escrow action types | Recovery surface |
| 23 | `widgets/savings_goal_sheet.dart` `_depositRef` | savings deposit | savings goal deposit | Recovery surface |
| 24 | `widgets/savings_goal_sheet.dart` `_withdrawRef` | savings withdraw | savings goal withdraw | Recovery surface |

**Instance creation (all rows):** a call with an unarmed (or
terminal/cleared) ref, or a ref whose recorded fingerprint does not match
the (reconstructed) request, begins a genuinely new durable instance —
minted and persisted before the first request. The registry never
deduplicates by body.

**Fingerprint reconstruction:** rows 1–2 recompute
`DurableOperationRegistry.fingerprintOf(reconstructedRequest)` at submit
time. All rows (including 1–2 via the surface) replay the STORED snapshot
through `retryRecovered`, whose fingerprint matches by construction.

**Retirement (all rows):** per-instance only; sibling instances are
untouched.

## 4. Security review — request snapshots in SharedPreferences

**What is stored:** `DurableOperation.request` — the full request body the
flow sent (amount, recipient phone/destination, network, optional
references, ids such as `savedAccountId`/`feeDiscountTierId`). It exists
for one purpose: exact reconstruction for safe resumption. No credentials
are ever stored (tokens live in `flutter_secure_storage`).

**Threat model (documented, per the close-out review's request):**
SharedPreferences is Android's plaintext app-private sandbox
(`/data/data/<pkg>/shared_prefs`) and iOS NSUserDefaults-backed plist in
the app container. Protection is OS-level app sandboxing + device lock —
NOT encryption at rest. Exposure requires a rooted/jailbroken device, an
exploited backup extraction, or forensic access to an unlocked device.
Records are transient: retirement removes them as soon as an operation
reaches a terminal outcome, so exposure shrinks to the set of genuinely
unresolved operations.

**Minimization analysis:** the snapshot cannot be minimized without
breaking the guarantee it exists for — resumption requires the full body
to replay (the backend fingerprint check fails closed on a materially
different body, so partial bodies cannot be resumed). The
durable-before-request invariant must not be weakened.

**Recommendation before real-user onboarding (not done in this PR):**
migrate the registry's storage to `flutter_secure_storage`
(Android Keystore / iOS Keychain) or `EncryptedSharedPreferences`, keeping
the same write-before-request invariant, and audit how long unresolved
records can remain pending (a periodic "stale operation" reconciliation
against the backend, surfaced to the user — never auto-pruned). The
registry's storage layer is a single `_store()` accessor plus an injectable
writer, so the migration is contained.

## 5. Proof map (tests)

- `test/utils/durable_operation_registry_test.dart` — close-out group:
  the full post-death lifecycle (A=50/K1, B=75/K2, death, reconstruction
  recovers A not B, retry K1, B intact K2, then B with K2, no third key);
  identical bodies -> ambiguous, fail closed, both independently
  retryable; `DurableRecoveryNone` for unmatched bodies (no journal
  mutation); account-scoped recovery; `pending(fingerprint:)` selector.
- `test/services/api_client_idempotency_test.dart` — wire-level: the same
  lifecycle over real HTTP headers with a fully simulated process death;
  identical bodies fail closed on the wire; `retryRecovered` replays a
  post-death instance under its ORIGINAL key.
