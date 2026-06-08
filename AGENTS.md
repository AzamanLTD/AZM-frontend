# Azaman Project Overview

Azaman is a social finance (SoFi) platform tailored for Gen-Z, centered around a peer-to-peer economic engine. The project implements social savings mechanisms like "Susu" (Rotating Savings and Credit Associations), a gamified auction house for rewards, and a high-trust marketplace. It bridges traditional mobile money (MoMo) with stablecoin (USDC) infrastructure, featuring:

audience: young urban Africans, 18-35, smartphone-first, financially active but underserved by traditional banking. people who move money peer-to-peer regularly, might already use crypto informally, and are comfortable with fintech apps like Palmpay or OPay, binance and paxful but want something more trust-native and community-aware.

## 1) Handoff rules

When handing off work, think of these points:

1. What changed
2. What did not change
3. Validation run and results
4. Remaining risks / unknowns
5. Next recommended action


Validate assumptions with code search before implementing.

# Flutter Performance Best Practices

Flutter applications are performant by default, but avoiding common pitfalls ensures optimal performance. This guide outlines best practices to help you write highly efficient Flutter apps, with a focus on rendering, layout, and resource management.

---

## **Optimizing Rendering and Layout**

### **Minimize Expensive Operations**
Some operations consume more resources than others. Design your UI to avoid unnecessary expensive operations.

---

### **Control `build()` Cost**
The `build()` method can be called frequently. Optimize it with these strategies:

- **Avoid repetitive or costly work** in `build()` methods.
- **Split large widgets** into smaller, focused widgets based on:
  - Encapsulation
  - How often they change
- **Localize `setState()` calls**:
  - Calling `setState()` high in the widget tree triggers rebuilds for all descendants.
  - Restrict `setState()` to the smallest subtree affected by the change.
- **Use `const` constructors**:
  - Flutter skips rebuild work for widgets with `const` constructors.
  - Enable the `flutter_lints` package to get reminders for missing `const` constructors.
- **Prefer `StatelessWidget` over functions** for reusable UI components.

**Resources:**
- [Performance considerations (StatefulWidget API)](https://api.flutter.dev/flutter/widgets/StatefulWidget-class.html)
- [Widgets vs Helper Methods (Flutter YouTube)](https://www.youtube.com/watch?v=...)

---

### **Efficient String Building**
- **Avoid `+` for string concatenation in loops**:
  - Each `+` creates a new `String` object, which is inefficient.
  - Use **`StringBuffer`** instead:
    ```dart
    final buffer = StringBuffer();
    buffer.write('Hello');
    buffer.write(' World');
    final result = buffer.toString(); // "Hello World"
    ```

---

### **Use `saveLayer()` Thoughtfully**
`saveLayer()` is an expensive operation that allocates an offscreen buffer, disrupting GPU rendering throughput.

#### **When is `saveLayer()` Required?**
- Dynamically displaying overlapping shapes with transparency (e.g., server-generated shapes).

#### **Debugging `saveLayer()` Calls**
- Check the **DevTools Performance view** for `saveLayer()` events.
- Enable `PerformanceOverlayLayer.checkerboardOffscreenLayers` to visualize offscreen layers.

#### **Minimizing `saveLayer()` Calls**
- **Precompute overlapping shapes** with static transparency and cache them.
- **Refactor painting logic** to avoid overlaps.
- **Avoid packages** that excessively use `saveLayer()`. Contact the package maintainer for alternatives.

**Widgets that may trigger `saveLayer()`:**
- `ShaderMask`
- `ColorFilter`
- `Chip` (if `disabledColorAlpha != 0xff`)
- `Text` (if `overflowShader` is used)

---

### **Minimize Opacity and Clipping**
- **Opacity**:
  - Avoid wrapping widgets in `Opacity` if possible.
  - For images, apply opacity directly (e.g., `ColorFilter` or `FadeInImage`).
  - For shapes/text, use semi-transparent colors instead of `Opacity`.
- **Clipping**:
  - Clipping is less expensive than `saveLayer()` but still costly.
  - Use `borderRadius` for rounded corners instead of clipping.
  - Avoid `Clip.antiAliasWithSaveLayer` unless necessary.

---

## **Optimizing Grids and Lists**

### **Be Lazy!**
- Use **lazy builders** (e.g., `ListView.builder`, `GridView.builder`) to build only visible items.
- Avoid building all items at startup.

**Resources:**
- [Working with Long Lists](https://docs.flutter.dev/ui/widgets/layout#working-with-long-lists)
- [ListView.builder API](https://api.flutter.dev/flutter/widgets/ListView/ListView.builder.html)

---

### **Avoid Intrinsic Passes**
Intrinsic passes (e.g., polling all cells for uniform sizing) slow down layout.

#### **Debugging Intrinsic Passes**
- Enable **Track layouts** in DevTools to monitor layout passes.
- Intrinsic events are labeled as `$runtimeType intrinsics`.

#### **Avoiding Intrinsic Passes**
- Set **fixed cell sizes** upfront.
- Use an **anchor cell** to size other cells relative to it.
- Write a **custom `RenderObject`** to optimize layout.

**Resource:**
- [Flutter Architectural Overview: Layout and Rendering](https://docs.flutter.dev/resources/architectural-overview#layout-and-rendering)

---

## **Frame Budget: 16ms**
- **60Hz display**: 16ms per frame (8ms for build, 8ms for render).
- **120Hz display**: 8ms per frame (total).
- **Why 60fps?**
  - Smooth visual experience.
  - Lower frame times improve battery life and thermal performance.

**Goal**: Render frames in **≤16ms** (or ≤8ms for 120fps).

---

## **Common Pitfalls**
Avoid these behaviors to prevent performance issues:

1. **Avoid `Opacity` in animations**:
   - Use `AnimatedOpacity` or `FadeInImage` instead.
2. **Avoid rebuilding static subtrees in `AnimatedBuilder`**:
   - Build static subtrees once and pass them as `child` to `AnimatedBuilder`.
3. **Avoid clipping in animations**:
   - Pre-clip images before animating.
4. **Avoid `Column()`/`ListView()` with concrete `List<Widget>` children**:
   - Use lazy builders for off-screen children.
5. **Avoid overriding `operator ==` on widgets**:
   - Overriding `==` can cause **O(N²) performance degradation**.
   - **Exception**: Leaf widgets (no children) with rare configuration changes.
   - **Better alternative**: Cache widgets.

**Resources:**
- [Performance Optimizations (AnimatedBuilder)](https://api.flutter.dev/flutter/widgets/AnimatedBuilder-class.html)
- [Opacity Animation Considerations](https://api.flutter.dev/flutter/widgets/Opacity-class.html)
- [ListView Lifecycle](https://api.flutter.dev/flutter/widgets/ListView-class.html)

---
## **Additional Resources**
- [Optimizing Flutter Web Apps](https://medium.com/flutter/optimizing-performance-in-flutter-web-apps-with-tree-shaking-and-deferred-loading-520537594534)
- [Improving Perceived Performance](https://medium.com/flutter/improving-perceived-performance-with-image-placeholders-precaching-and-disabled-navigation-63990c785594)
- [Building Performant Flutter Widgets](https://medium.com/flutter/building-performant-flutter-widgets-508965b678)

# Fintech App Design Guidelines

## Core Design Direction

Build the app like a modern consumer fintech product, not like a trading terminal.

The interface should feel:

* Simple
* Safe
* Fast
* Trustworthy
* Easy to scan
* Native to mobile
* Light and calm

Use a clean white or soft gray background, large readable numbers, rounded cards, clear actions, and one strong brand accent color.

## Visual Style

### Use a Clean Fintech Layout

Prefer:

* White or very light gray backgrounds
* Large balance text
* Rounded cards
* Pill shaped buttons
* Clear spacing
* Simple icons
* Minimal borders
* Soft shadows only when needed

Avoid:

* Dense tables
* Overloaded dashboards
* Too many colors
* Complex charts on the home screen
* Crypto exchange style clutter
* Unclear icons without labels

## Typography

Use strong hierarchy.

Recommended structure:

```md
Large: Main balance, buy amount, portfolio value
Medium: Section titles, card titles, important actions
Small: Labels, helper text, secondary data
```

Rules:

* Main money values must be immediately visible.
* Do not hide important financial data behind small text.
* Use readable font sizes.
* Avoid long paragraphs inside main flows.
* Use short labels.

## Color System

Use one main accent color.

Examples:

```md
Purple: crypto buying, trading, wallet actions
Green: money movement, transfer success, rewards
Blue: neutral finance actions
Black: primary serious actions
Light gray: secondary surfaces and inactive buttons
```

Rules:

* Use accent color only for primary actions, active states, and key highlights.
* Use green for positive financial movement or success.
* Use red only for danger, failed payments, cancellation, losses, or destructive actions.
* Do not use many competing accent colors.
* Keep the interface calm.

## Cards and Components

Use cards to group financial information.

Good card use cases:

* Total balance
* Crypto holdings
* Recent transactions
* Referral offer
* Verification prompt
* Savings goal
* Payment method
* Transfer status
* Scheduled payment

Rules:

* Cards should have rounded corners.
* Cards should show one clear purpose.
* Do not put unrelated actions inside the same card.
* Do not overload a card with too much data.
* Important cards should be easy to scan in 2 seconds.

## Buttons

Use pill shaped buttons for main actions.

Examples:

```md
Buy
Sell
Send
Add money
Request
Continue
Confirm
Cancel transfer
```

Rules:

* Primary button should be visually dominant.
* Secondary actions should be less visually loud.
* Destructive actions must not look like primary actions.
* Place the main CTA where the user naturally expects it.
* Do not place destructive buttons where users expect “Next” or “Continue”.

## Home Dashboard

The dashboard should answer the user’s main question immediately:

```md
How much money do I have?
What changed recently?
What can I do next?
```

Must show:

* Total balance or portfolio value
* Main actions
* Recent transactions or holdings
* Important alerts only
* Clear navigation

Avoid:

* Too many widgets
* Too many promotions
* Too many charts
* Too many feature cards
* Forcing users to click before seeing their balance

## Balance Display

The balance should be visible right after login.

Rules:

* Do not bury the balance.
* Do not require account selection if the user has only one account.
* Show available balance clearly.
* If there are multiple balances, label them properly.
* Make it clear what is spendable, invested, pending, or locked.

Bad:

```md
User logs in → selects account → taps confirm → sees balance
```

Good:

```md
User logs in → sees total balance instantly
```

## Navigation

Navigation should be simple and predictable.

Recommended bottom tabs:

```md
Home
Assets
Trade / Payments
Portfolio
Settings
```

Or:

```md
Home
Card
Recipients
Payments
Profile
```

Rules:

* Use clear labels.
* Use familiar icons.
* Keep main navigation visible.
* Do not invent unusual navigation patterns.
* Do not use hidden menus for core actions.
* Do not make users search for basic features.

## Login and Security

Login should be fast but secure.

Rules:

* Support biometrics when possible.
* Keep login screen focused.
* Do not overload login with promotions or unrelated options.
* Provide clear access to help.
* Provide clear onboarding for new users.
* Keep security steps understandable.

The login screen should focus on one main action:

```md
Log in
```

Secondary actions:

```md
Create account
Forgot password
Help
```

## Transfers and Payments

Money movement must be effortless.

Rules:

* Do not show a huge list of payment types upfront.
* Ask for the key information first.
* Detect payment type from the entered account, phone number, wallet address, or recipient.
* Split long forms into clear steps.
* Show recipient, amount, fee, and delivery time before confirmation.
* Always provide a final review screen.

Payment flow should be:

```md
Choose recipient
Enter amount
Review details
Confirm
Show result
```

## Payment Feedback

After every payment or trade action, show clear feedback.

Success screen must include:

* Success status
* Amount
* Recipient or asset
* Date/time
* Reference if needed
* Next actions

Failure screen must include:

* Clear failure reason
* What the user can do next
* Support option if needed

Good next actions:

```md
Done
Make another payment
Share receipt
View transaction
Contact support
```

Avoid vague messages like:

```md
Something went wrong.
```

Use:

```md
Payment failed because your balance is too low.
Add money or choose a smaller amount.
```

## Buy and Sell Crypto Flow

For crypto buying, keep it simple.

Buy flow should show:

* Fiat amount
* Crypto equivalent
* Selected asset
* Payment method
* Fee
* Exchange rate
* Final amount received
* Continue button

Rules:

* Let users enter fiat first.
* Show crypto equivalent instantly.
* Use preset amount chips.
* Make asset selection clear.
* Show fees before final confirmation.
* Do not hide risk, rate, or processing status.

## Verification and Trust

Verification should feel useful, not annoying.

Rules:

* Explain why verification is needed.
* Use simple language.
* Show expected time.
* Show progress.
* Do not block the whole app unless legally required.
* Make verification card visible but not aggressive.

Example:

```md
Verify your account

This helps keep your account safe and unlocks higher limits.
It should only take a few minutes.
```

## Transactions

Transactions must be easy to scan and search.

Each transaction should show:

* Merchant or recipient
* Amount
* Direction: incoming or outgoing
* Date/time
* Status
* Asset or currency if needed

Rules:

* Group transactions by date.
* Use subtle color to separate incoming and outgoing.
* Provide search.
* Provide filters.
* Allow full transaction history.
* Do not limit users to only recent transactions.

Filters should include:

```md
Date
Amount
Currency
Asset
Status
Recipient
Category
```

## Transfer Status

For pending transfers, show a timeline.

A good status page includes:

* Current status
* Completed steps
* Pending steps
* Estimated completion time
* Cancel option if allowed
* Details tab

Example statuses:

```md
You set up your transfer
We received your money
Your money is being processed
We pay out your money
Recipient receives the money
```

Rules:

* Use plain language.
* Show progress visually.
* Do not leave users guessing.
* Make cancellation clear if available.

## Support

Support must be easy to find.

Rules:

* Provide support from account, payments, cards, and failed transaction screens.
* Give estimated wait time if chat is not instant.
* Let users attach screenshots or documents.
* Show message status: sent, received, seen.
* Prioritize urgent financial issues.

Support topics should include:

```md
Payment issue
Card issue
Account access
Verification
Fraud or suspicious activity
Crypto transaction
Refund
```

## Cards and Account Details

Users must be able to view and copy important details.

Allow users to:

* View account number
* View IBAN or local bank details
* Copy account details
* Share account details
* View card details if allowed
* Copy card number
* Freeze or block card quickly

Rules:

* Protect sensitive details with authentication.
* Never expose sensitive data without user intent.
* Make copy and share actions obvious.
* Do not force users to use desktop for basic details.

## Card Blocking

Card blocking must be fast.

Rules:

* Let users freeze or block a card directly inside the app.
* Do not force a phone call for urgent card blocking.
* Ask the reason after the action, not before if urgency is high.
* Provide fraud reporting after blocking.
* Show what happens next.

Emergency flow:

```md
Card screen
Freeze card
Confirm
Card frozen
Report suspicious transactions
```

## Scheduled and Recurring Payments

Scheduled payments should be easy to review.

Show:

* Recipient
* Amount
* Date
* Frequency
* Status
* Next payment date

Rules:

* Do not hide recipient names.
* Allow editing.
* Allow cancellation.
* Allow paying early if supported.
* Show both completed and upcoming payments.

Recurring payment setup should be split into steps:

```md
Recipient
Amount
Frequency
Start date
Review
Confirm
```

## Budgeting and Insights

Budgeting should reduce work, not create more work.

Rules:

* Auto categorize transactions.
* Let users edit categories.
* Show monthly spending.
* Show remaining budget.
* Use progress bars.
* Warn users before overspending.
* Keep insights simple and actionable.

Good insight:

```md
You have $120 left for food this month.
```

Bad insight:

```md
Category performance deviation: 73%.
```

## Savings

Savings should feel easy and motivating.

Rules:

* Let users create savings goals quickly.
* Show progress toward goal.
* Allow recurring savings.
* Allow spare change saving if relevant.
* Let users personalize goal name and image.
* Make add money and withdraw actions obvious.

Savings card should show:

```md
Goal name
Saved amount
Target amount
Progress
Add money
Withdraw
```

## Accessibility

The app must be usable by everyone.

Rules:

* Use high contrast text.
* Do not rely only on color.
* Use readable font sizes.
* Support screen readers.
* Make buttons large enough to tap.
* Add labels to icons.
* Avoid tiny gray text for important financial information.

Minimum standards:

```md
Important text must be readable.
Buttons must be easy to tap.
Errors must be clear.
Money values must not depend only on color.
```

## Mobile Native Behavior

The app should feel native, not like a website inside a phone.

Rules:

* Use bottom sheets for focused actions.
* Use native keyboard types for amount inputs.
* Keep main CTA fixed near the bottom when appropriate.
* Respect safe areas.
* Use haptic feedback for important confirmations if supported.
* Keep loading states smooth.
* Avoid full page reload feeling.

## Error Handling

Errors must be specific and useful.

Each error should explain:

* What happened
* Why it happened
* What the user can do next

Examples:

```md
Your payment could not be completed because your balance is too low.
Add money or enter a smaller amount.
```

```md
We could not verify this wallet address.
Check the address and try again.
```

Avoid:

```md
Error 400
Failed
Invalid request
Something went wrong
```

## Loading and Empty States

Never leave screens blank.

Empty states should explain:

* What is missing
* Why it matters
* What the user can do

Examples:

```md
No transactions yet.
Your transactions will appear here after your first payment.
```

```md
No crypto holdings.
Buy crypto to start building your portfolio.
```

Loading states should:

* Use skeleton cards
* Avoid jumping layouts
* Show progress for long actions
* Never make users wonder if the app froze

## Content and Copywriting

Use short, direct, human language.

Rules:

* Avoid financial jargon unless necessary.
* Explain technical terms.
* Use active voice.
* Keep labels short.
* Make risk and fees clear.
* Do not use vague button text.

Good:

```md
Buy Ethereum
Add money
Send to bank account
Freeze card
Share receipt
```

Bad:

```md
Proceed
Initiate operation
Execute transaction
Manage financial instrument
```

## Trust and Compliance UX

Fintech apps must make users feel safe.

Always show:

* Fees before confirmation
* Exchange rate before confirmation
* Delivery time
* Transaction status
* Risk notices when needed
* Verification requirements
* Security actions

Rules:

* Do not hide costs.
* Do not use confusing dark patterns.
* Do not make cancellation unclear.
* Do not make risky actions look casual.
* Always confirm destructive actions.

## Primary Screen Checklist

Before finalizing any screen, check:

```md
What is the main user goal on this screen?
Is that goal visually obvious?
Can the user understand the screen in 3 seconds?
Is the main action clear?
Are secondary actions less dominant?
Is there any unnecessary information?
Is the money value clear?
Are fees, risks, and statuses visible where needed?
Can the user recover from mistakes?
Does the screen feel safe?
```

## Core Agent Rules

When designing or generating fintech app screens, agents must follow these rules:

1. Show the most important financial information first.
2. Keep each screen focused on one main task.
3. Use large readable money values.
4. Use rounded cards and clear spacing.
5. Use one main accent color.
6. Make primary actions obvious.
7. Keep destructive actions visually separate.
8. Reduce choices when the user is trying to complete a task.
9. Always provide clear feedback after payments, transfers, and trades.
10. Never hide fees, exchange rates, or transaction status.
11. Make support easy to access.
12. Make transaction history searchable and filterable.
13. Make account and card details easy to view, copy, and share.
14. Make urgent security actions fast.
15. Do not overload the dashboard.
16. Prefer native mobile patterns.
17. Use plain language.
18. Design for trust before decoration.
19. Always refer to the reference images in the `@ref/` folder for visual guidance on layout, spacing, and structural design.

## Final Design Principle

A fintech app should make money feel understandable and controllable.

The user should always know:

```md
How much they have
Where their money is
What action they can take
What will happen next
Whether the action succeeded
How to get help if something goes wrong
```
