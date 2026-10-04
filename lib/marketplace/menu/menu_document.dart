/// Canonical restaurant menu model (Overhaul 03 §3.1).
///
/// The flip-book (`RestaurantNativeMenuJourney`) and the list view both read a
/// single immutable [MenuDocument] built from the catalog data the storefront
/// already loads (`CatalogSection`, `BusinessProduct`, `RestaurantDish`).
/// Prices and availability are *carried*, never computed here — the
/// authoritative unit price still comes from `restaurantEffectiveUnitPrice`
/// at commit time.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/marketplace/experiences/restaurant/restaurant_experience.dart';
import 'package:azaman/marketplace/store_query.dart';
import 'package:azaman/models/business_models.dart';
import 'package:azaman/utils/business_hours.dart';

class MenuItemView {
  final BusinessProduct product;

  /// Modifier/option source when the business exposes one; null otherwise.
  final RestaurantDish? dish;

  /// `product.isActive` ∧ the chapter's availability window contains `now`.
  final bool availableNow;

  const MenuItemView({
    required this.product,
    required this.dish,
    required this.availableNow,
  });

  String get id => product.id;
  List<String> get tags => product.tags;
}

class MenuChapter {
  final String id;
  final String title;
  final String? description;
  final String? imageUrl;

  /// `"06:00 – 11:00"` when the section declares a window, else null.
  final String? availabilityLabel;
  final List<MenuItemView> items;

  const MenuChapter({
    required this.id,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.availabilityLabel,
    required this.items,
  });

  /// Identifier used for the synthesised chapter holding uncategorised items.
  static const moreId = '__more';
}

class MenuDocument {
  /// Ordered by `displayOrder`; uncategorised products last as "More".
  final List<MenuChapter> chapters;

  const MenuDocument(this.chapters);

  static const empty = MenuDocument(<MenuChapter>[]);

  bool get isEmpty => chapters.every((c) => c.items.isEmpty);
  Iterable<MenuItemView> get items => chapters.expand((c) => c.items);

  MenuItemView? byId(String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Same predicate every vertical uses for store-scoped search (§1.3).
  /// Empty chapters are dropped; the document identity is preserved for an
  /// empty query so memoised consumers do not rebuild.
  MenuDocument filtered(String query) {
    if (query.trim().isEmpty) return this;
    final out = <MenuChapter>[];
    for (final c in chapters) {
      final kept = c.items
          .where((i) => matchesStoreQuery(
                query,
                name: i.product.name,
                description: i.product.description,
                tags: i.tags,
              ))
          .toList(growable: false);
      if (kept.isNotEmpty) {
        out.add(MenuChapter(
          id: c.id,
          title: c.title,
          description: c.description,
          imageUrl: c.imageUrl,
          availabilityLabel: c.availabilityLabel,
          items: kept,
        ));
      }
    }
    return MenuDocument(out);
  }

  /// Builds the document from catalog data. Inactive sections are omitted;
  /// a section window (`availableFrom`/`availableTo`, `"HH:mm"`) is evaluated
  /// with the same parser as store hours (`BusinessHours.stateOfRange`), so
  /// `"06:00"-"11:00"` and overnight windows behave identically everywhere.
  static MenuDocument build({
    required List<CatalogSection> sections,
    required List<BusinessProduct> uncategorised,
    required Map<String, RestaurantDish> dishesById,
    required DateTime now,
  }) {
    final sorted = [...sections]
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    MenuItemView view(BusinessProduct p, bool sectionOpen) => MenuItemView(
          product: p,
          dish: dishesById[p.id],
          availableNow: p.isActive && sectionOpen,
        );

    bool sectionOpen(CatalogSection s) {
      if (s.availableFrom == null || s.availableTo == null) return true;
      final state =
          BusinessHours.stateOfRange('${s.availableFrom}-${s.availableTo}', now);
      // Unknown (malformed window) never hides food; only a parsed "closed"
      // marks items unavailable.
      return state != OpenState.closed;
    }

    final chapters = <MenuChapter>[
      for (final s in sorted.where((s) => s.isActive))
        MenuChapter(
          id: s.id,
          title: s.name,
          description: s.description,
          imageUrl: s.imageUrl,
          availabilityLabel: (s.availableFrom != null && s.availableTo != null)
              ? '${s.availableFrom} – ${s.availableTo}'
              : null,
          items: s.products
              .map((p) => view(p, sectionOpen(s)))
              .toList(growable: false),
        ),
      if (uncategorised.isNotEmpty)
        MenuChapter(
          id: MenuChapter.moreId,
          title: 'More',
          description: null,
          imageUrl: null,
          availabilityLabel: null,
          items: uncategorised.map((p) => view(p, true)).toList(growable: false),
        ),
    ];
    return MenuDocument(chapters);
  }
}

/// §3.5 — chapters whose titles read like courses, in meal order. Pure
/// navigation aid; empty when fewer than two courses are present.
List<MenuChapter> mealPathChapters(MenuDocument document) {
  const order = ['starter', 'main', 'side', 'drink', 'dessert'];
  final found = <int, MenuChapter>{};
  for (final c in document.chapters) {
    final t = c.title.toLowerCase();
    for (var i = 0; i < order.length; i++) {
      if (t.contains(order[i]) && !found.containsKey(i)) {
        found[i] = c;
        break;
      }
    }
  }
  if (found.length < 2) return const [];
  final keys = found.keys.toList()..sort();
  return [for (final k in keys) found[k]!];
}

/// §3.3 — which rendering of the shared document the user prefers.
enum MenuViewMode { flipBook, list }

class MenuViewModeNotifier extends StateNotifier<MenuViewMode> {
  static const prefsKey = 'az_menu_view_mode';

  MenuViewModeNotifier() : super(MenuViewMode.flipBook) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (!mounted || raw == null) return;
      state = MenuViewMode.values.firstWhere(
        (m) => m.name == raw,
        orElse: () => MenuViewMode.flipBook,
      );
    } catch (_) {
      // Preference storage is best-effort.
    }
  }

  Future<void> set(MenuViewMode mode) async {
    if (state == mode) return;
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, mode.name);
    } catch (_) {}
  }
}

final menuViewModeProvider =
    StateNotifierProvider<MenuViewModeNotifier, MenuViewMode>(
  (_) => MenuViewModeNotifier(),
);