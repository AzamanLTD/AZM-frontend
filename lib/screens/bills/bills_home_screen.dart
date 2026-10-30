// AZAMAN — BILLS (Hub)
//
// The Home Bills bubble lands here. What this screen can offer is decided by
// the SERVER, not by this file: a biller catalogue that the backend reports it
// can actually reach, and nothing invented when it reports none.
//
// Deliberately NOT done here: no hardcoded billers from FEX's published guide,
// no sample accounts, no sample amounts, no placeholder "recent payments". A
// member who arrives while the facility is unavailable sees a truthful state
// and cannot walk into a fake confirmation.
//
// The gateway is an interface so the screen is testable BEFORE the backend
// contract lands, and so the empty state is not the only path ever exercised.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/bills/bills_gateway.dart';
import 'package:azaman/theme/az_text.dart';

class BillsHomeScreen extends ConsumerStatefulWidget {
  const BillsHomeScreen({super.key});

  @override
  ConsumerState<BillsHomeScreen> createState() => _BillsHomeScreenState();
}

class _BillsHomeScreenState extends ConsumerState<BillsHomeScreen> {
  late Future<BillsAvailability> _availability;

  @override
  void initState() {
    super.initState();
    _availability = ref.read(billsGatewayProvider).availability();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    return Scaffold(
      backgroundColor: colors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: colors.scaffoldBackground,
        elevation: 0,
        title: Text(
          'Bills',
          style: AzText.title.copyWith(color: colors.textPrimary),
        ),
      ),
      body: FutureBuilder<BillsAvailability>(
        future: _availability,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: colors.mutedAccent,
              ),
            );
          }
          if (snapshot.hasError ||
              snapshot.data == null ||
              !snapshot.data!.isAvailable) {
            return _UnavailableState(colors: colors);
          }
          return _AvailableState(availability: snapshot.data!, colors: colors);
        },
      ),
    );
  }
}

/// The honest state. It says what is true, offers no dead ends, and invents
/// nothing.
class _UnavailableState extends StatelessWidget {
  const _UnavailableState({required this.colors});

  final AzamanColors colors;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colors.textTertiary, width: 1),
            ),
            child: Icon(
              HugeIconsSolid.invoice01,
              size: 30,
              color: colors.mutedAccent,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Bill payments are not available yet',
            textAlign: TextAlign.center,
            style: AzText.title.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 10),
          Text(
            'Electricity, water, television and internet billers appear here '
            'once we can pay them. Nothing is charged, and nothing can be '
            'paid, until then.',
            textAlign: TextAlign.center,
            style: AzText.body.copyWith(
              color: colors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Reachable billers, exactly as the server reports them.
class _AvailableState extends StatelessWidget {
  const _AvailableState({required this.availability, required this.colors});

  final BillsAvailability availability;
  final AzamanColors colors;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      itemCount: availability.categories.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final category = availability.categories[i];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.divider),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  category.label,
                  style: AzText.title.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${category.billerCount}',
                style: AzText.body.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
        );
      },
    );
  }
}
