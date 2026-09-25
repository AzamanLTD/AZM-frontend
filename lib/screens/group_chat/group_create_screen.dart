// =============================================================================
// GROUP CREATE SCREEN  (Master Sprint, 2026-05-27)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/group_chat_provider.dart';
import 'package:azaman/providers/theme_provider.dart';


class GroupCreateScreen extends ConsumerStatefulWidget {
  const GroupCreateScreen({super.key});

  @override
  ConsumerState<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends ConsumerState<GroupCreateScreen> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group name required.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(groupListProvider.notifier).create(
            name: _name.text.trim(),
            description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
          );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('New Group',
            style: TextStyle(
                color: colors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(colors, 'Group Name'),
            _input(colors, _name, hint: 'My Trading Crew'),
            const SizedBox(height: 14),
            _label(colors, 'Description (optional)'),
            _input(colors, _desc, hint: 'What is this group about?', maxLines: 3),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.isDark ? Colors.black : Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text(
                  _busy ? 'Creating…' : 'Create Group',
                  style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(AzamanColors colors, String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          s.toUpperCase(),
          style: TextStyle(
            color: colors.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      );

  Widget _input(AzamanColors colors, TextEditingController c,
      {String? hint, int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          hintStyle: TextStyle(color: colors.textTertiary, fontSize: 13),
        ),
      ),
    );
  }
}
