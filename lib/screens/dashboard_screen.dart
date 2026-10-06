import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/product_repository.dart';
import '../services/product_service.dart';
import '../services/starter_pack.dart';
import '../services/store_service.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'analytics_screen.dart';
import 'inventory_screen.dart';
import 'settings_screen.dart';
import 'transactions_screen.dart';

/// The signed-in, store-ready shell: TindaTrack app bar on top, the four-tab
/// bottom navigation below, and the selected tab in between — the frame of
/// the Stitch "Home - Active Cart" design.
///
/// Every tab is built: Home, Inventory, Transactions and Analytics. A tab
/// left out of `builtTabs` says it is not built yet when tapped, rather than
/// silently doing nothing.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.user,
    required this.storeId,
    this.createProductRepository = ProductRepository.forStore,
    this.watchLowStockThreshold = StoreService.lowStockThresholdOf,
    this.watchStoreProfile = StoreService.profileOf,
    this.updateStoreProfile = StoreService.updateProfile,
    this.watchStoreStaff = StoreService.staffOf,
  });

  final User user;
  final String storeId;

  /// The store.s products and sales, live from Firestore by default; tests
  /// swap in a fake server.
  final ProductRepository Function(String storeId) createProductRepository;
  final Stream<int> Function(String storeId) watchLowStockThreshold;
  final Stream<StoreProfile?> Function(String storeId) watchStoreProfile;
  final Future<void> Function(String storeId, StoreProfile profile)
  updateStoreProfile;
  final Stream<StoreStaff> Function(String storeId) watchStoreStaff;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _home = 0;
  static const _inventory = 1;
  static const _transactions = 2;
  static const _analytics = 3;

  int _tab = _home;

  /// One listener per list, shared by every tab, so a product added in
  /// Inventory is searchable on Home at once.
  late final ProductRepository _products = widget.createProductRepository(
    widget.storeId,
  )..load();

  /// Built on first visit, then kept in the [IndexedStack] so switching tabs
  /// neither drops the cart nor re-subscribes.
  Widget? _inventoryTab;
  Widget? _transactionsTab;
  Widget? _analyticsTab;

  /// Analytics' "Restock Now" asks Inventory to show what needs restocking.
  final _needsAttention = ValueNotifier(false);

  /// Built once so rebuilding the shell does not re-subscribe.
  late final Widget _homeTab = HomeScreen(
    products: _products.watch(),
    lowStockThreshold: widget.watchLowStockThreshold(widget.storeId),
    onCompleteSale: ({required items, required receivedCentavos}) =>
        _products.recordSale(
          items: items,
          receivedCentavos: receivedCentavos,
          cashier: _cashier,
        ),
  );

  /// Who is ringing up sales on this device, read at the moment of each sale
  /// so a rename in Settings applies to the next one. A helper on the store's
  /// allowed-emails list goes by the name the owner gave them; anyone else is
  /// the owner, under the store's owner name — or, if that is blank, their
  /// Google name (falling back to the email's local part).
  Cashier get _cashier {
    final helper = _staff?.memberFor(
      uid: widget.user.uid,
      email: widget.user.email,
    );
    if (helper != null && helper.name.trim().isNotEmpty) {
      return Cashier(uid: widget.user.uid, name: helper.name.trim());
    }
    final ownerName = _profile?.ownerName.trim() ?? '';
    return Cashier.owner(
      widget.user.uid,
      name: ownerName.isNotEmpty ? ownerName : _googleName(widget.user),
    );
  }

  StoreProfile? _profile;
  StoreStaff? _staff;
  late final StreamSubscription<StoreProfile?> _profileSub;
  late final StreamSubscription<StoreStaff> _staffSub;

  @override
  void initState() {
    super.initState();
    _profileSub = widget
        .watchStoreProfile(widget.storeId)
        .listen((profile) => _profile = profile, onError: (_) {});
    _staffSub = widget
        .watchStoreStaff(widget.storeId)
        .listen((staff) => _staff = staff, onError: (_) {});
  }

  static String? _googleName(User user) {
    final displayName = user.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    final email = user.email?.trim();
    if (email != null && email.contains('@')) return email.split('@').first;
    return null;
  }

  @override
  void dispose() {
    _profileSub.cancel();
    _staffSub.cancel();
    _needsAttention.dispose();
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
          needsAttentionRequest: _needsAttention,
        );
      }
      if (tab == _transactions) {
        _transactionsTab ??= TransactionsScreen(
          sales: _products.watchSales(),
          products: _products.watch(),
          onRefund: _products.voidSale,
          onEdit:
              (
                sale, {
                required items,
                required receivedCentavos,
                required customerName,
              }) => _products.editSale(
                sale,
                items: items,
                receivedCentavos: receivedCentavos,
                customerName: customerName,
                editor: _cashier,
              ),
        );
      }
      if (tab == _analytics) {
        _analyticsTab ??= AnalyticsScreen(
          sales: _products.watchSales(),
          products: _products.watch(),
          lowStockThreshold: widget.watchLowStockThreshold(widget.storeId),
          onRestock: () {
            _needsAttention.value = true;
            _select(_inventory);
          },
        );
      }
    });
  }

  void _openSettings() {
    final id = widget.storeId;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          profile: widget.watchStoreProfile(id),
          onSave: (profile) => widget.updateStoreProfile(id, profile),
          syncStatus: _products.watchSyncStatus(),
          staff: widget.watchStoreStaff(id),
          staffActions: StaffActions(
            add: (member) => StoreService.addStaff(id, member),
            rename: (member, name) =>
                StoreService.renameStaff(id, member.email, name),
            remove: (member) => StoreService.removeStaff(id, member.email),
          ),
          onUpgradePro: () => StoreService.upgradeToPro(id),
          onLoadStarterPack: () => _products.addAllMissing(starterPack),
          userId: widget.user.uid,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _TopBar(user: widget.user, onOpenSettings: _openSettings),
      body: IndexedStack(
        index: _tab,
        children: [
          _homeTab,
          _inventoryTab ?? const SizedBox.shrink(),
          _transactionsTab ?? const SizedBox.shrink(),
          _analyticsTab ?? const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: _BottomNav(
        selected: _tab,
        onSelect: _select,
        builtTabs: const {_home, _inventory, _transactions, _analytics},
      ),
    );
  }
}

class _TopBar extends StatelessWidget implements PreferredSizeWidget {
  const _TopBar({required this.user, required this.onOpenSettings});

  final User user;
  final VoidCallback onOpenSettings;

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
              _SettingsMenu(user: user, onOpenSettings: onOpenSettings),
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

/// The design's settings gear: the signed-in account, the store's Settings,
/// and signing out.
class _SettingsMenu extends StatelessWidget {
  const _SettingsMenu({required this.user, required this.onOpenSettings});

  final User user;
  final VoidCallback onOpenSettings;

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
        PopupMenuItem(
          value: onOpenSettings,
          child: const Row(
            children: [
              Icon(
                Icons.storefront_outlined,
                size: 20,
                color: AppColors.onSurfaceVariant,
              ),
              SizedBox(width: 12),
              Text('Settings'),
            ],
          ),
        ),
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
