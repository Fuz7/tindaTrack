import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/product_repository.dart';
import '../services/store_service.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'inventory_screen.dart';

/// The signed-in, store-ready shell: TindaTrack app bar on top, the four-tab
/// bottom navigation below, and the selected tab in between — the frame of
/// the Stitch "Home - Active Cart" design.
///
/// Home and Inventory exist so far. The other tabs render as the design shows
/// them and say they are not built yet when tapped, rather than silently doing
/// nothing.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.user,
    required this.storeId,
    this.createProductRepository = ProductRepository.forStore,
    this.watchLowStockThreshold = StoreService.lowStockThresholdOf,
  });

  final User user;
  final String storeId;

  /// The on-device catalog, Firestore-backed by default; tests swap in a
  /// fake server.
  final ProductRepository Function(String storeId) createProductRepository;
  final Stream<int> Function(String storeId) watchLowStockThreshold;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _home = 0;
  static const _inventory = 1;

  int _tab = _home;

  /// One catalog for both tabs, so a product added in Inventory is
  /// searchable on Home at once.
  late final ProductRepository _products = widget.createProductRepository(
    widget.storeId,
  )..load();

  /// Built on first visit, then kept in the [IndexedStack] so switching tabs
  /// neither drops the cart nor re-subscribes.
  Widget? _inventoryTab;

  /// Built once so rebuilding the shell does not re-subscribe.
  late final Widget _homeTab = HomeScreen(
    products: _products.watch(),
    lowStockThreshold: widget.watchLowStockThreshold(widget.storeId),
    onCompleteSale: _products.recordSale,
  );

  @override
  void dispose() {
    _products.dispose();
    super.dispose();
  }

  void _select(int tab) {
    setState(() {
      _tab = tab;
      if (tab == _inventory) {
        _inventoryTab ??= InventoryScreen(
          products: _products.watch(),
          lowStockThreshold: widget.watchLowStockThreshold(widget.storeId),
          onSaveProduct: _products.add,
          onUpdateProduct: _products.update,
          onDeleteProduct: _products.delete,
          onAdjustStock: _products.adjustStock,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _TopBar(user: widget.user),
      body: IndexedStack(
        index: _tab,
        children: [_homeTab, _inventoryTab ?? const SizedBox.shrink()],
      ),
      bottomNavigationBar: _BottomNav(
        selected: _tab,
        onSelect: _select,
        builtTabs: const {_home, _inventory},
      ),
    );
  }
}

class _TopBar extends StatelessWidget implements PreferredSizeWidget {
  const _TopBar({required this.user});

  final User user;

  @override
  Size get preferredSize => const Size.fromHeight(AppSpacing.touchTarget + 1);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: AppSpacing.touchTarget,
          padding: const EdgeInsets.only(left: AppSpacing.gutter),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.outlineVariant)),
          ),
          child: Row(
            children: [
              _Avatar(user: user),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'TindaTrack',
                  style: AppTypography.headlineMd.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
              _SettingsMenu(user: user),
            ],
          ),
        ),
      ),
    );
  }
}

/// Google profile photo, falling back to the first initial when there is no
/// photo or it fails to load (e.g. offline on a cold image cache).
class _Avatar extends StatelessWidget {
  const _Avatar({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final name = (user.displayName ?? user.email ?? '').trim();
    final initial = Text(
      name.isEmpty ? '?' : name[0].toUpperCase(),
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        color: AppColors.onPrimaryContainer,
      ),
    );
    final photo = user.photoURL;

    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: AppColors.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: photo == null
          ? initial
          : Image.network(
              photo,
              width: 32,
              height: 32,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => initial,
            ),
    );
  }
}

/// The design's settings gear. Settings is not built yet, so for now it holds
/// the one account action the app has: signing out.
class _SettingsMenu extends StatelessWidget {
  const _SettingsMenu({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<VoidCallback>(
      tooltip: 'Settings',
      icon: const Icon(Icons.settings_outlined, color: AppColors.primary),
      color: AppColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.base),
        side: const BorderSide(color: AppColors.surfaceBorder),
      ),
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Text(
            user.email ?? user.displayName ?? 'Signed in',
            style: AppTypography.bodySm.copyWith(color: AppColors.outline),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: AuthService.signOut,
          child: Row(
            children: [
              Icon(Icons.logout, size: 20, color: AppColors.onSurfaceVariant),
              SizedBox(width: 12),
              Text('Sign out'),
            ],
          ),
        ),
      ],
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.selected,
    required this.onSelect,
    required this.builtTabs,
  });

  static const _tabs = [
    (icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Home'),
    (
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2,
      label: 'Inventory',
    ),
    (
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
      label: 'Transactions',
    ),
    (
      icon: Icons.analytics_outlined,
      selectedIcon: Icons.analytics,
      label: 'Analytics',
    ),
  ];

  final int selected;
  final ValueChanged<int> onSelect;

  /// Tabs that exist; tapping any other says it is not built yet.
  final Set<int> builtTabs;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64, // h-16
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final (index, tab) in _tabs.indexed)
                _NavItem(
                  icon: index == selected ? tab.selectedIcon : tab.icon,
                  label: tab.label,
                  selected: index == selected,
                  onTap: builtTabs.contains(index)
                      ? () => onSelect(index)
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;

  /// Null for a tab that is not built yet.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: selected ? AppColors.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: selected
              ? null
              : onTap ??
                    () {
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(content: Text('$label is not built yet.')),
                        );
                    },
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              semanticLabel: label,
              color: selected
                  ? AppColors.onPrimaryContainer
                  : AppColors.onSecondaryFixedVariant,
            ),
          ),
        ),
      ),
    );
  }
}
