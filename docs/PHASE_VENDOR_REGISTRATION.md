# Phase V — Vendor Registration & Pull Tab Gating

> **Status:** In development
> **Scope:** Frontend pull-tab UX redesign + full vendor application flow
> **Dependencies:** Backend KYC routes (existing), new vendor application endpoint (TBD)

---

## 1. Problem Statement

The vendor pull tab on the user dashboard currently allows non-vendors to drag
past 50% and open a basic `VendorApplyScreen` with minimal requirements (just ID
upload + payment methods). This doesn't match the product intent of:

1. **Gating non-vendors early** — they should only be able to drag ~15% before
   being snapped back with a clear popup explaining vendor requirements.
2. **Requiring Binance-level verification** — becoming a vendor should require
   comprehensive identity verification, proof of address, financial background,
   and acceptance of vendor terms.
3. **Directing users to the Azaman website** — users should understand the full
   responsibilities of being a vendor before committing.

---

## 2. Pull Tab Behavior (Redesigned)

### 2.1 Vendor Users (role === VENDOR)
- Tab label: **"FOR VENDOR"**
- Drag threshold: **50% of screen width** (unchanged)
- Action on threshold: Opens `VendorDashboard`

### 2.2 Non-Vendor Users (role === USER)
- Tab label: **"BECOME VENDOR"**
- **Hard drag limit: 15% of screen width** — drag clamped, cannot go further
- On release from any drag position: **Snap back with rubber-band animation**
- On snap back: **Show vendor requirement popup** (bottom sheet)
- Light haptic on drag limit hit
- The popup contains:
  - Creative header explaining vendor benefits
  - Link to Azaman website vendor section
  - Quick requirements summary
  - "Start Application" CTA (if user wants to proceed without reading website)

---

## 3. Vendor Application Requirements (Binance-Level KYC)

Based on Binance's P2P merchant verification process, we require:

### 3.1 Personal Identity (Step 1)
- **Legal full name** (as appears on government ID)
- **Date of birth**
- **Country of residence**
- **Government-issued ID** (front + back photo):
  - National ID / Ghana Card
  - International Passport
  - Driver's License
- **Selfie with ID** (liveness check)

### 3.2 Proof of Address (Step 2)
- **Document upload** (one of):
  - Utility bill (within 3 months)
  - Bank statement (within 3 months)
  - Government-issued letter
- **Residential address** (street, city, region, postal code)

### 3.3 Financial Background (Step 3)
- **Source of funds** (dropdown):
  - Employment income
  - Business income
  - Investments
  - Savings
  - Other (explain)
- **Monthly trading volume estimate** (dropdown ranges):
  - $0 – $1,000
  - $1,000 – $5,000
  - $5,000 – $20,000
  - $20,000+
- **Previous P2P/crypto trading experience** (yes/no + platform names)

### 3.4 Payment Methods (Step 4)
- **At least 2 payment methods** required (from supported list):
  - Mobile Money (MTN, Vodafone, AirtelTigo)
  - Bank Transfer (local banks)
  - CashApp / Zelle / Venmo / PayPal (for USD trades)
- **Account details for each** (verified on first trade)

### 3.5 Collateral & Terms (Step 5)
- **Minimum collateral deposit: $500 USDT** (locked during vendor status)
- **Accept vendor terms & conditions** — including:
  - Maximum response time commitments (5 min for order acceptance)
  - Dispute resolution cooperation
  - No price manipulation
  - Account suspension for repeated failures
- **Agree to platform fee structure** (margins, exit fees)

---

## 4. Vendor Information Website Section

Direct users to: `https://azaman.me/vendors` (to be created)

Content should include:
- What it means to be a vendor on Azaman
- Income potential and fee structure
- Responsibilities and expectations
- Risks and collateral requirements
- FAQ for prospective vendors
- Success stories / case studies (future)

**Important:** Users can choose NOT to open the link and continue the
registration process directly from the app. The link is informational,
not a blocker.

---

## 5. Backend Requirements (Follow-Up)

### 5.1 New Endpoint: `POST /api/vendor/apply`
```json
{
  "legalName": "string",
  "dateOfBirth": "ISO date",
  "country": "string",
  "idType": "NATIONAL_ID | PASSPORT | DRIVERS_LICENSE",
  "selfieWithId": "file upload",
  "proofOfAddress": "file upload",
  "addressStreet": "string",
  "addressCity": "string",
  "addressRegion": "string",
  "addressPostal": "string",
  "sourceOfFunds": "EMPLOYMENT | BUSINESS | INVESTMENTS | SAVINGS | OTHER",
  "sourceOfFundsOther": "string (if OTHER)",
  "monthlyVolumeEstimate": "TIER_1 | TIER_2 | TIER_3 | TIER_4",
  "hasPreviousExperience": "boolean",
  "previousPlatforms": "string",
  "paymentMethods": [{ "type": "string", "details": {} }],
  "acceptedTerms": "boolean",
  "collateralAmount": "number (>= 500)"
}
```

### 5.2 New Endpoint: `GET /api/vendor/application-status`
Returns current application status: `NONE | PENDING | APPROVED | REJECTED`

### 5.3 Admin Review Queue
- Admin dashboard gets new "Vendor Applications" tab
- Admin can approve/reject with notes
- Approval triggers role change `USER → VENDOR` + token version bump

---

## 6. Frontend Implementation Plan

### Phase V-1: Pull Tab Gating (this PR)
- [x] Clamp non-vendor drag to 15%
- [x] Snap-back animation on release
- [x] Show vendor requirement popup on snap-back
- [x] Include website link in popup
- [x] "Start Application" button in popup
- [x] 3-pull confirmation flow (1st: info, 2nd: confirm prompt, 3rd: open registration)
- [x] 5-second timeout between pulls (resets if user delays)

### Phase V-2: Vendor Application Screen (this PR)
- [x] Multi-step form (5 steps with progress indicator)
- [x] All fields from Section 3 above
- [x] File upload for ID/selfie/address proof
- [x] Terms acceptance step
- [x] Submit to backend (mocked for now, wires to POST /api/vendor/apply)
- [x] Application status check screen

### Phase V-3: Backend Integration (follow-up PR)
- [x] Create Prisma `VendorApplication` model
- [x] Implement POST /api/vendor/apply endpoint
- [x] Implement GET /api/vendor/application-status endpoint
- [x] Admin review endpoint POST /api/vendor/applications/:id/review
- [x] Admin list endpoint GET /api/vendor/applications
- [x] Auto-role-upgrade on approval (USER → VENDOR + tokenVersion bump)
- [ ] Email notifications for status changes
- [ ] File upload integration for ID/selfie/address docs

---

## 7. Migration: Raw HTTP → ApiClient

As part of this PR, all remaining screens using raw `http.*` calls are migrated
to use the centralized `ApiClient` singleton. Files migrated:

1. `lib/screens/profile_screen.dart`
2. `lib/screens/referral_screen.dart`
3. `lib/screens/savings_screen.dart`
4. `lib/screens/saved_wallets_screen.dart`
5. `lib/screens/trades_tab_screen.dart`
6. `lib/screens/trade_summary_screen.dart`
7. `lib/screens/upload_proof.dart`
8. `lib/screens/vendor_dashboard.dart`
9. `lib/screens/vendor_ad_creator.dart`
10. `lib/screens/vendor_deposit_screen.dart`
11. `lib/screens/vendor_settings_screen.dart`
12. `lib/screens/vendor_trade_execution.dart`
13. `lib/screens/kyc_verification_screen.dart`
14. `lib/screens/user_local_payment_methods.dart`
15. `lib/screens/admin/corporate_purchase_screen.dart`
16. `lib/screens/profile_details_screen.dart`
17. `lib/services/push_notification_service.dart`
18. `lib/services/receipt_service.dart`
19. `lib/services/trade_account_service.dart`
