import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'dart:convert';

final openSwapsProvider = FutureProvider<List<dynamic>>((ref) async {
  final client = ref.read(apiClientProvider);
  try {
    final res = await client.get('/api/business-os/employees/shifts/open');
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['swaps'] as List<dynamic>? ?? [];
  } catch (_) {
    return [];
  }
});

class WorkerSwapsScreen extends ConsumerWidget {
  const WorkerSwapsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final swapsAsync = ref.watch(openSwapsProvider);

    return Scaffold(
      backgroundColor: colors.scaffoldBackground,
      appBar: AppBar(
        title: const Text('Open Shift Swaps', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        backgroundColor: colors.surface,
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      body: swapsAsync.when(
        loading: () => Center(child: CircularProgressIndicator(color: colors.accent)),
        error: (_, __) => Center(child: Text('Unable to load swaps', style: TextStyle(color: colors.textSecondary))),
        data: (swaps) {
          if (swaps.isEmpty) {
            return Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.swap_horiz, size: 48, color: colors.textTertiary),
                const SizedBox(height: 12),
                Text('No open swap requests', style: TextStyle(color: colors.textSecondary, fontSize: 15)),
              ],
            ));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: swaps.length,
            itemBuilder: (context, i) {
              final swap = swaps[i] as Map<String, dynamic>;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.surface, borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.border, width: 1),
                ),
                child: Row(
                  children: [
                    Icon(Icons.swap_horiz, color: colors.accent, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Shift Swap Available', style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                          if (swap['reason'] != null)
                            Text(swap['reason'], style: TextStyle(color: colors.textSecondary, fontSize: 12),
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        // Claim swap — would need POST /shifts/swaps/:id/claim
                      },
                      child: Text('Claim', style: TextStyle(color: colors.accent, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
