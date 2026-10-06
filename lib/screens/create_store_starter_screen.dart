import 'package:flutter/material.dart';

import '../services/starter_pack.dart';
import '../services/store_service.dart';
import '../theme/app_theme.dart';
import '../widgets/create_store_scaffold.dart';

/// Step 2 of "Create New Tindahan" — the Stitch "Create New Tindahan Step 2 of
/// 2" design (project 14772063175572299152).
///
/// The store can launch empty or with the Pinoy Sari-Sari Starter Pack, a
/// Pro feature. There is no billing yet, so the Unlock offer is a
/// confirmation dialog that turns Pro on — the same stand-in Settings uses,
/// and the same pack that can be loaded there later.
///
/// Helper invites are still a Pro feature with nothing behind them, so they
/// render locked as the design shows and say so when tapped, rather than
/// pretending.
class CreateStoreStarterScreen extends StatefulWidget {
  const CreateStoreStarterScreen({
    super.key,
    required this.storeName,
    required this.onCreate,
  });

  /// Named in the confirmation dialog, so the owner sees what they are
  /// committing to before it is written.
  final String storeName;

  /// Writes the store with everything chosen here: Pro, the starter pack,
  /// and any helpers invited. Completes when it is saved; a throw is shown
  /// to the user and leaves them on this screen to retry.
  ///
  /// The store does not exist yet while this screen is open, so nothing
  /// chosen here is written until it does — it is all carried through here.
  final Future<void> Function({
    required bool isPro,
    required bool withStarterPack,
    required List<StaffMember> helpers,
  })
  onCreate;

  @override
  State<CreateStoreStarterScreen> createState() =>
      _CreateStoreStarterScreenState();
}

class _CreateStoreStarterScreenState extends State<CreateStoreStarterScreen> {
  bool _busy = false;

  /// Whether the owner took the Pro offer. Pro is one flag on the store, so
  /// taking it anywhere on this screen unlocks every Pro feature here — the
  /// starter pack and helper invites both.
  bool _pro = false;

  /// Whether the store launches with the starter pack.
  bool _withPack = false;

  /// Helpers to invite once the store exists. Held here, not written: there
  /// is no store to attach them to yet.
  final _helpers = <StaffMember>[];

  /// Pro has no billing yet, so this dialog stands in for the purchase —
  /// the same stand-in Settings uses.
  ///
  /// [choosePack] also selects the starter pack, since that is what the
  /// owner was reaching for when they came through the pack's Unlock.
  Future<void> _unlockPro({bool choosePack = false}) async {
    if (_pro) {
      if (choosePack) setState(() => _withPack = true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ConfirmDialog(
        title: 'Unlock TindaTrack Pro?',
        message:
            'Pro unlocks the Pinoy Sari-Sari Starter Pack — '
            '${starterPack.length} popular items, priced and ready to edit — '
            'and helper logins, so family or staff can ring sales on their '
            'own phones.\n\n'
            'Billing is not set up yet, so confirming turns Pro on for '
            '${widget.storeName} at no charge.',
        confirmLabel: 'Unlock Pro',
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _pro = true;
      if (choosePack) _withPack = true;
    });
  }

  void _addHelper(String email) {
    final clean = email.trim().toLowerCase();
    if (_helpers.any((h) => h.email == clean)) return;
    setState(
      () => _helpers.add(StaffMember(email: clean, name: _nameFrom(clean))),
    );
  }

  void _removeHelper(StaffMember helper) =>
      setState(() => _helpers.remove(helper));

  /// A readable first guess at the helper's name, from the email. The owner
  /// renames them in Settings once they have joined.
  static String _nameFrom(String email) {
    final local = email.split('@').first.replaceAll(RegExp(r'[._-]+'), ' ');
    return local
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  /// Both ways off this screen end on the dashboard, and neither can be taken
  /// back from inside the app, so each asks first.
  Future<void> _confirmCreate() => _confirmThenCreate(
    title: 'Create ${widget.storeName}?',
    message: _withPack
        ? 'Your tindahan starts with ${starterPack.length} products, priced '
              'and ready to edit, with no stock counted yet. It opens on the '
              'dashboard.'
        : 'Your tindahan starts with an empty catalog and opens on the '
              'dashboard. You can add products anytime.',
    confirmLabel: 'Create Store',
    withStarterPack: _withPack,
  );

  Future<void> _confirmSkip() => _confirmThenCreate(
    title: 'Skip inventory seed?',
    message:
        '${widget.storeName} will be created with no products. You can '
        'add them later from the POS screen or Settings.',
    confirmLabel: 'Skip & Create',
    withStarterPack: false,
  );

  Future<void> _confirmThenCreate({
    required String title,
    required String message,
    required String confirmLabel,
    required bool withStarterPack,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
      ),
    );
    if (confirmed != true || !mounted) return;
    await _create(withStarterPack: withStarterPack);
  }

  Future<void> _create({required bool withStarterPack}) async {
    setState(() => _busy = true);
    try {
      await widget.onCreate(
        isPro: _pro,
        withStarterPack: withStarterPack,
        helpers: List.unmodifiable(_helpers),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      CreateStoreScaffold.showMessage(
        context,
        'Could not create your tindahan: $error',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CreateStoreScaffold(
      step: 2,
      stepLabel: 'Starter Setup',
      actionLabel: 'Create Store & Continue',
      onAction: _confirmCreate,
      busy: _busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _ProgressCard(),
          const SizedBox(height: 20),
          _StarterInventorySection(
            pro: _pro,
            withPack: _withPack,
            onChoosePack: () => _unlockPro(choosePack: true),
            onChooseEmpty: () => setState(() => _withPack = false),
          ),
          const SizedBox(height: 20),
          _HelpersSection(
            pro: _pro,
            helpers: _helpers,
            onUnlockPro: _unlockPro,
            onAdd: _addHelper,
            onRemove: _removeHelper,
          ),
          const SizedBox(height: 20),
          const _OfflineNotice(),
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: _busy ? null : _confirmSkip,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.onSurfaceVariant,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('Skip inventory seed & finish later'),
            ),
          ),
        ],
      ),
    );
  }
}

// --- shared bits -----------------------------------------------------------

/// Confirm/cancel dialog in the design system's flat style: white card, 1px
/// border, 8px buttons. Pops `true` on confirm, `false` on cancel.
class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
  });

  final String title;
  final String message;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSpacing.containerMargin),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppColors.surfaceBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primaryFixed,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.storefront,
                  color: AppColors.onPrimaryFixed,
                ),
              ),
              const SizedBox(height: AppSpacing.stackMd),
              Text(
                title,
                style: AppTypography.headlineMd.copyWith(
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.stackSm),
              Text(
                message,
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                ),
                child: Text(confirmLabel),
              ),
              const SizedBox(height: AppSpacing.stackSm),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.onSurfaceVariant,
                ),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _cardShadow = [
  BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1)),
];

const _sectionTitleStyle = TextStyle(
  fontSize: 12,
  height: 16 / 12,
  fontWeight: FontWeight.w700,
  letterSpacing: 0.05 * 12,
  color: AppColors.onSurfaceVariant,
);

const _sectionBodyStyle = TextStyle(
  fontSize: 12,
  height: 1.4,
  color: AppColors.onSurfaceVariant,
);

/// Amber "PRO" tag. [icon] adds the lock used on section headers.
class _ProBadge extends StatelessWidget {
  const _ProBadge({this.icon = false});

  final bool icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.statusLowStock,
        borderRadius: BorderRadius.circular(icon ? 6 : 4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon) ...[
            const Icon(Icons.lock, size: 13, color: AppColors.onPrimary),
            const SizedBox(width: 3),
          ],
          Text(
            'PRO',
            style: TextStyle(
              fontSize: icon ? 11 : 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: AppColors.onPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small emerald button used for "Unlock" and "Upgrade".
class _SmallPrimaryButton extends StatelessWidget {
  const _SmallPrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(AppRadius.base),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.base),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: AppColors.onPrimary),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- sections ---------------------------------------------------------------

class _ProgressCard extends StatelessWidget {
  const _ProgressCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: _cardShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: AppColors.primaryFixed,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  size: 13,
                  color: AppColors.onPrimaryFixed,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Store Profile',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySm.copyWith(
                    fontWeight: FontWeight.w500,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              const Spacer(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '——',
                  style: TextStyle(color: AppColors.outlineVariant),
                ),
              ),
              const Spacer(),
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Text(
                  '2',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Starter Setup',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: const LinearProgressIndicator(
              value: 1,
              minHeight: 6,
              color: AppColors.primary,
              backgroundColor: AppColors.surfaceContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _StarterInventorySection extends StatelessWidget {
  const _StarterInventorySection({
    required this.pro,
    required this.withPack,
    required this.onChoosePack,
    required this.onChooseEmpty,
  });

  /// Whether the store is on Pro, which is what unlocks the pack.
  final bool pro;

  /// Whether the starter pack is the chosen mode.
  final bool withPack;

  /// Offers Pro, and selects the pack once taken.
  final VoidCallback onChoosePack;
  final VoidCallback onChooseEmpty;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('STARTER INVENTORY SETUP', style: _sectionTitleStyle),
                  SizedBox(height: 2),
                  Text(
                    'Seed popular Pinoy sari-sari items immediately or launch '
                    'blank.',
                    style: _sectionBodyStyle,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.secondaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bolt,
                    size: 13,
                    color: AppColors.onSecondaryContainer,
                  ),
                  SizedBox(width: 3),
                  Text(
                    'Instant',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ModeSelector(
          pro: pro,
          withPack: withPack,
          onChoosePack: onChoosePack,
          onChooseEmpty: onChooseEmpty,
        ),
        const SizedBox(height: 12),
        _CleanSlateCard(
          pro: pro,
          withPack: withPack,
          onChoosePack: onChoosePack,
        ),
      ],
    );
  }
}

/// "Start Empty" / "Starter Pack" toggle.
///
/// Starter Pack carries a lock until the owner takes the Pro offer; after
/// that both halves select normally, so the choice can still be changed
/// before the store is written.
class _ModeSelector extends StatelessWidget {
  const _ModeSelector({
    required this.pro,
    required this.withPack,
    required this.onChoosePack,
    required this.onChooseEmpty,
  });

  final bool pro;
  final bool withPack;
  final VoidCallback onChoosePack;
  final VoidCallback onChooseEmpty;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeChip(
              label: 'Start Empty',
              selected: !withPack,
              onTap: onChooseEmpty,
              trailing: const _ModeTag('FREE'),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _ModeChip(
              label: 'Starter Pack',
              selected: withPack,
              // Locked until Pro is taken; after that it selects like the
              // other half, so the owner can still change their mind.
              locked: !pro,
              onTap: onChoosePack,
              trailing: pro ? const _ModeTag("PRO") : const _ProBadge(),
            ),
          ),
        ],
      ),
    );
  }
}

/// One half of [_ModeSelector]: raised and in the brand colour when it is
/// the chosen mode, flat otherwise.
class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.trailing,
    this.locked = false,
  });

  final String label;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.base),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: selected ? AppColors.surfaceContainerLowest : null,
          borderRadius: BorderRadius.circular(AppRadius.base),
          boxShadow: selected ? _cardShadow : null,
        ),
        child: Opacity(
          opacity: selected || !locked ? 1 : 0.8,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  locked
                      ? Icons.lock
                      : selected
                      ? Icons.check_circle_outline
                      : Icons.circle_outlined,
                  size: 18,
                  color: locked ? AppColors.statusLowStock : color,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: AppTypography.bodySm.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: color,
                  ),
                ),
                const SizedBox(width: 6),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The small square tag beside a mode's name.
class _ModeTag extends StatelessWidget {
  const _ModeTag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _CleanSlateCard extends StatelessWidget {
  const _CleanSlateCard({
    required this.pro,
    required this.withPack,
    required this.onChoosePack,
  });

  final bool pro;

  /// Whether the pack is already chosen, so the row reads as included
  /// rather than still offering itself.
  final bool withPack;
  final VoidCallback onChoosePack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.surfaceBorder),
        boxShadow: _cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.inventory_2_outlined,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Clean Slate Selected',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primaryFixed,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: const Text(
                  'Ready to launch',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onPrimaryFixed,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Your tindahan launches immediately with an empty catalog. You can '
            'add products from the Inventory tab anytime.',
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.surfaceBorder),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.base),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    withPack ? Icons.check_circle : Icons.lock,
                    size: 18,
                    color: withPack
                        ? AppColors.primary
                        : AppColors.statusLowStock,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Pinoy Sari-Sari Starter Pack',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface,
                            ),
                          ),
                          _ProBadge(),
                        ],
                      ),
                      Text(
                        withPack
                            ? "Included — ${starterPack.length} items, ready to edit"
                            : "Pre-seeds ${starterPack.length} snacks, sachets & drinks",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (!withPack)
                  _SmallPrimaryButton(
                    label: pro ? "Use Pack" : "Unlock",
                    icon: Icons.upgrade,
                    onPressed: onChoosePack,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Invite Store Helpers": locked behind Pro, and once unlocked a list of
/// Gmail addresses collected for the store that is about to be created.
///
/// Nothing is written here — there is no store to attach a helper to yet —
/// so the invites are held and sent the moment the store exists.
class _HelpersSection extends StatefulWidget {
  const _HelpersSection({
    required this.pro,
    required this.helpers,
    required this.onUnlockPro,
    required this.onAdd,
    required this.onRemove,
  });

  final bool pro;
  final List<StaffMember> helpers;
  final VoidCallback onUnlockPro;
  final ValueChanged<String> onAdd;
  final ValueChanged<StaffMember> onRemove;

  @override
  State<_HelpersSection> createState() => _HelpersSectionState();
}

class _HelpersSectionState extends State<_HelpersSection> {
  final _email = TextEditingController();
  String? _error;

  /// Enough to catch a typo, not enough to argue about: the address is only
  /// ever matched against the Google account a helper signs in with.
  static final _looksLikeEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _add() {
    final value = _email.text.trim().toLowerCase();
    final problem = switch (value) {
      '' => 'Enter an email address.',
      _ when !_looksLikeEmail.hasMatch(value) =>
        'That is not an email address.',
      _ when widget.helpers.any((h) => h.email == value) =>
        'That helper is already invited.',
      _ => null,
    };
    setState(() => _error = problem);
    if (problem != null) return;
    widget.onAdd(value);
    _email.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('INVITE STORE HELPERS', style: _sectionTitleStyle),
            ),
            if (widget.pro)
              const _ModeTag('PRO')
            else
              const _ProBadge(icon: true),
          ],
        ),
        const SizedBox(height: 2),
        const Text(
          'Add trusted staff or family Gmail accounts who can ring sales on '
          'their own mobile phones.',
          style: _sectionBodyStyle,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: _cardShadow,
          ),
          child: widget.pro ? _unlocked() : _locked(),
        ),
      ],
    );
  }

  Widget _unlocked() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _add(),
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.alternate_email, size: 18),
                  prefixIconConstraints: const BoxConstraints(minWidth: 34),
                  hintText: 'helper.maria@gmail.com',
                  hintStyle: const TextStyle(
                    fontSize: 12,
                    color: AppColors.outline,
                  ),
                  errorText: _error,
                  errorStyle: const TextStyle(fontSize: 11),
                  filled: true,
                  fillColor: AppColors.surfaceContainerLow,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.base),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _SmallPrimaryButton(label: 'Add', icon: Icons.add, onPressed: _add),
          ],
        ),
        if (widget.helpers.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'No helpers yet. They join by signing in with the Google '
              'account you list here.',
              style: _sectionBodyStyle,
            ),
          ),
        for (final helper in widget.helpers)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.person_outline,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    helper.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => widget.onRemove(helper),
                  icon: const Icon(Icons.close, size: 18),
                  color: AppColors.onSurfaceVariant,
                  tooltip: 'Remove ${helper.email}',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        if (widget.helpers.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Invited when your tindahan is created. You can rename them in '
              'Settings once they join.',
              style: _sectionBodyStyle,
            ),
          ),
      ],
    );
  }

  Widget _locked() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A locked preview of the invite form, as in the design.
        const IgnorePointer(
          child: Opacity(opacity: 0.5, child: _HelperFormPreview()),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(AppRadius.base),
            border: Border.all(color: AppColors.surfaceBorder),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.workspace_premium_outlined,
                size: 18,
                color: AppColors.statusLowStock,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text.rich(
                  TextSpan(
                    text:
                        'Unlock multi-device cashier logins & staff '
                        'permissions with ',
                    children: [
                      TextSpan(
                        text: 'TindaTrack Pro',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      TextSpan(text: '.'),
                    ],
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SmallPrimaryButton(
                label: 'Upgrade',
                onPressed: widget.onUnlockPro,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HelperFormPreview extends StatelessWidget {
  const _HelperFormPreview();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppRadius.base),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.alternate_email,
                        size: 18,
                        color: AppColors.outline,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'helper.maria@gmail.com',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppRadius.base),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add,
                      size: 16,
                      color: AppColors.onSurfaceVariant,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Add',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadius.base),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.statusInStock,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    'helper.maria@gmail.com',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'CASHIER',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: AppColors.primaryFixed,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.cloud_sync,
              size: 18,
              color: AppColors.onPrimaryFixed,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '100% Offline Capable',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'No internet? TindaTrack keeps tallying sales without '
                  'interruption. All inventory and ledger receipts will safely '
                  'sync once reconnected.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.6,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
