import 'package:flutter/material.dart';
import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';

/// Extracted from business_profile_screen.dart to reduce its size.
/// Booking tab that renders a category-specific CTA card.
class BusinessBookTab extends StatelessWidget {
  final BusinessProfile business;
  final AzamanColors colors;
  final void Function(String route)? onNavigate;
  final VoidCallback? onOpenOrderSheet;
  final VoidCallback? onOpenCatalogView;

  const BusinessBookTab({
    super.key,
    required this.business,
    required this.colors,
    this.onNavigate,
    this.onOpenOrderSheet,
    this.onOpenCatalogView,
  });

  @override
  Widget build(BuildContext context) {
    switch (business.category) {
      case 'HOSPITALITY':
      case 'REAL_ESTATE':
        return _bookCtaCard(
          icon: Icons.hotel_outlined,
          title: 'Book a Room',
          subtitle: 'Browse room types, pick your dates, and reserve with an escrow-backed deposit.',
          buttonLabel: 'Browse Rooms',
          onTap: () => onNavigate?.call('/business-market/${business.id}/hotel-booking'),
        );
      case 'LOGISTICS':
        return _bookCtaCard(
          icon: Icons.directions_bus_filled_outlined,
          title: 'Book a Seat',
          subtitle: 'See upcoming trips, pick your seat on the live seat map, and reserve instantly.',
          buttonLabel: 'View Trips',
          onTap: () => onNavigate?.call('/business-market/${business.id}/transit'),
        );
      case 'FOOD_BEVERAGE':
        return _bookCtaCard(
          icon: Icons.table_restaurant_outlined,
          title: 'Reserve a Table',
          subtitle: 'Request a dine-in reservation — the business will confirm or counter-propose a time.',
          buttonLabel: 'Request Reservation',
          onTap: () => onOpenOrderSheet?.call(),
        );
      case 'RETAIL':
      case 'TECHNOLOGY':
        return _bookCtaCard(
          icon: Icons.shopping_bag_outlined,
          title: 'Shop the Catalog',
          subtitle: 'Browse everything this business sells and check out with escrow-backed payment protection.',
          buttonLabel: 'Shop Now',
          onTap: () => onOpenCatalogView?.call(),
        );
      case 'HEALTH_WELLNESS':
      case 'FREELANCE_SERVICES':
        return _bookCtaCard(
          icon: Icons.design_services_outlined,
          title: 'Book a Service',
          subtitle: 'Pick a listed service or package and request it — the business confirms your booking directly.',
          buttonLabel: 'View Services',
          onTap: () => onOpenOrderSheet?.call(),
        );
      case 'EDUCATION':
        return _bookCtaCard(
          icon: Icons.school_outlined,
          title: 'Enroll in a Course',
          subtitle: 'Browse available courses and enroll — your payment is held in escrow until access is confirmed.',
          buttonLabel: 'View Courses',
          onTap: () => onOpenOrderSheet?.call(),
        );
      case 'ENTERTAINMENT':
        return _bookCtaCard(
          icon: Icons.confirmation_number_outlined,
          title: 'Get Tickets',
          subtitle: 'Browse tickets and experiences from this business and secure yours with escrow protection.',
          buttonLabel: 'View Tickets',
          onTap: () => onOpenOrderSheet?.call(),
        );
      case 'FINANCIAL_SERVICES':
        return _bookCtaCard(
          icon: Icons.account_balance_outlined,
          title: 'View Plans',
          subtitle: "Browse this business's financial products and services and request the one you need.",
          buttonLabel: 'View Plans',
          onTap: () => onOpenOrderSheet?.call(),
        );
      default:
        return _bookCtaCard(
          icon: Icons.storefront_outlined,
          title: 'Browse Offerings',
          subtitle: 'See what this business offers and request it directly — payments are escrow-protected.',
          buttonLabel: 'View Offerings',
          onTap: () => onOpenOrderSheet?.call(),
        );
    }
  }

  Widget _bookCtaCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonLabel,
    required VoidCallback onTap,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colors.accentSurface,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: colors.accent),
            ),
            const SizedBox(height: 18),
            Text(title,
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              onPressed: onTap,
              child: Text(buttonLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }
}
