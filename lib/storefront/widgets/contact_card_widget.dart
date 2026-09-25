import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/storefront_models.dart';

class ContactCardWidget extends StatelessWidget {
  final Map<String, dynamic> props;
  final StorefrontBusinessInfo business;

  const ContactCardWidget({super.key, required this.props, required this.business});

  @override
  Widget build(BuildContext context) {
    final showPhone = props['showPhone'] ?? true;
    final showWhatsApp = props['showWhatsApp'] ?? true;
    final showEmail = props['showEmail'] ?? true;
    final showWebsite = props['showWebsite'] ?? false;

    final phone = business.phoneNumber;
    // Normalize phone: strip non-digits for tel/WhatsApp links
    final rawPhone = phone?.replaceAll(RegExp(r'[^\d+]'), '') ?? '';

    final buttons = <Widget>[];
    if (showPhone && phone != null && phone.isNotEmpty) {
      buttons.add(_contactButton(Icons.phone, 'Call', 'tel:$rawPhone'));
    }
    if (showWhatsApp && phone != null && phone.isNotEmpty) {
      final waNumber = rawPhone.startsWith('+') ? rawPhone.substring(1) : rawPhone;
      buttons.add(_contactButton(Icons.chat, 'WhatsApp', 'https://wa.me/$waNumber'));
    }
    if (showEmail) buttons.add(_contactButton(Icons.email, 'Email', 'mailto:contact@example.com'));
    if (showWebsite) buttons.add(_contactButton(Icons.language, 'Website', 'https://example.com'));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Wrap(spacing: 10, runSpacing: 10, children: buttons),
    );
  }

  Widget _contactButton(IconData icon, String label, String url) {
    return Builder(builder: (ctx) {
      return ActionChip(
        avatar: Icon(icon, size: 16, color: Theme.of(ctx).colorScheme.primary),
        label: Text(label, style: TextStyle(fontSize: 13, color: Theme.of(ctx).colorScheme.onSurface)),
        onPressed: () => _launchUrl(url),
        backgroundColor: Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.08),
        side: BorderSide.none,
      );
    });
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }
}
