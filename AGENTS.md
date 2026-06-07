# Azaman Project Overview

Azaman is a social finance (SoFi) platform tailored for Gen-Z, centered around a peer-to-peer economic engine. The project implements social savings mechanisms like "Susu" (Rotating Savings and Credit Associations), a gamified auction house for rewards, and a high-trust marketplace. It bridges traditional mobile money (MoMo) with stablecoin (USDC) infrastructure, featuring:

- **Susu Engine**: Collaborative savings groups with cycle-based payouts, trust scoring, and member vouching.
- **P2P Marketplace**: A trust-based environment for trading and transactions between users.
- **Gamified Rewards**: Auction-based systems and leaderboards to drive engagement and distribute benefits.
- **Cross-Border Banking**: Multi-currency account management and smart-routing for payments.
- **Social Core**: Integrated chat, friend networks, and trust metrics to ensure community-driven security.

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