/// Store-scoped search predicate (Overhaul 03 §1.3).
///
/// Every vertical body filters its loaded data with the same rule so that a
/// query typed while a store is open behaves identically for dishes,
/// products, rooms and trips. The predicate is intentionally dumb: substring
/// match on name, description and tags, case-insensitive. Ranking belongs to
/// the backend search; this is a local sieve.
bool matchesStoreQuery(
  String query, {
  required String name,
  String? description,
  List<String> tags = const [],
}) {
  final q = query.trim();
  if (q.isEmpty) return true;
  final l = q.toLowerCase();
  if (name.toLowerCase().contains(l)) return true;
  if (description != null && description.toLowerCase().contains(l)) return true;
  for (final t in tags) {
    if (t.toLowerCase().contains(l)) return true;
  }
  return false;
}