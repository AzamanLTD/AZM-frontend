// =============================================================================
// AZAMAN — MARKETPLACE SEARCH BINDING (nav-independent seam)
//
// There is no search field in `ContextualNavBand` / `PremiumBottomNav` today.
// The provider is bound to the explore-mode TextField through this object;
// when the nav gains an in-pill field it instantiates the same binding — the
// provider, placeholders and back semantics do not change.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/marketplace_search_provider.dart';
import 'package:azaman/widgets/marketplace/discovery/marketplace_placeholders.dart';

class MarketplaceSearchBinding {
  MarketplaceSearchBinding(this.ref);
  final WidgetRef ref;

  MarketplaceSearchNotifier get _n => ref.read(marketplaceSearchProvider.notifier);

  void onChanged(String text) => _n.changed(text);
  void onSubmit(String _) => _n.submit();
  void onFocus(bool focused) => _n.focus(focused);
  void clear() => _n.clear();

  List<String> placeholders(MarketplaceSearchState s, {String? storeName}) =>
      MarketplacePlaceholders.forScope(s.scope, world: s.worldWire, storeName: storeName);
}