// Local pulse: two compact truthful lines at most. Hidden when there is
// nothing real to say.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/experience/gateways/marketplace_discovery_gateway.dart';
import 'package:azaman/providers/marketplace_discovery_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/business_hours.dart';
import 'package:azaman/widgets/marketplace/discovery/utility_rail.dart';

class LocalPulseModel {
  final int? openNow; // null → line hidden
  final int? nearby; // within 2 km; null → line hidden
  const LocalPulseModel({this.openNow, this.nearby});
  bool get isEmpty => (openNow ?? 0) == 0 && (nearby ?? 0) == 0;
}

LocalPulseModel buildLocalPulse(DiscoverySnapshot s, Set<DiscoverySignal> supported) {
  final open = supported.contains(DiscoverySignal.openNow)
      ? s.catalog.where((b) => b.openStateAt(s.now) == OpenState.open).length
      : null;
  final near = (supported.contains(DiscoverySignal.nearby) && s.distanceKmByBusinessId != null)
      ? s.catalog.where((b) => (s.distanceOf(b) ?? double.infinity) <= 2.0).length
      : null;
  return LocalPulseModel(openNow: open, nearby: near);
}

final localPulseProvider = Provider<LocalPulseModel>((ref) {
  final s = ref.watch(discoverySnapshotProvider);
  final supported = ref.watch(marketplaceDiscoveryGatewayProvider).supportedSignals;
  return buildLocalPulse(s, supported);
});

class LocalPulse extends ConsumerWidget {
  final ValueChanged<UtilityFilter> onFilter;
  const LocalPulse({super.key, required this.onFilter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(localPulseProvider);
    if (model.isEmpty) return const SizedBox.shrink();
    final colors = ref.watch(themeProvider).colors;
    return Padding(
      key: const ValueKey('marketplace_local_pulse'),
      padding: const EdgeInsets.fromLTRB(AzSpace.lg, AzSpace.lg, AzSpace.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((model.openNow ?? 0) > 0)
            _line(colors, '${model.openNow} places open now', colors.success,
                () => onFilter(UtilityFilter.openNow)),
          if ((model.nearby ?? 0) > 0)
            _line(colors, '${model.nearby} within 2 km', colors.accent,
                () => onFilter(UtilityFilter.nearMe)),
        ],
      ),
    );
  }

  Widget _line(AzamanColors colors, String text, Color dot, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AzSpace.xs),
        child: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: AzSpace.sm),
          Text(text, style: AzText.bodyS.copyWith(color: colors.textSecondary)),
        ]),
      ),
    );
  }
}