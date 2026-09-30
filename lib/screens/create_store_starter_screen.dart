import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/create_store_scaffold.dart';

/// Step 2 of "Create New Tindahan" — the Stitch "Create New Tindahan Step 2 of
/// 2" design (project 14772063175572299152).
///
/// Only the free path is live: the store launches with an empty catalog. The
/// starter pack and helper invites are TindaTrack Pro features with nothing
/// behind them yet, so they render as the design shows them — locked — and
/// tapping them says so instead of pretending.
class CreateStoreStarterScreen extends StatefulWidget {
  const CreateStoreStarterScreen({
    super.key,
    required this.storeName,
    required this.onCreate,
  });

  /// Named in the confirmation dialog, so the owner sees what they are
  /// committing to before it is written.
  final String storeName;

  /// Writes the store. Completes when it is saved; a throw is shown to the
  /// user and leaves them on this screen to retry.
  final Future<void> Function() onCreate;

  @override
  State<CreateStoreStarterScreen> createState() =>
      _CreateStoreStarterScreenState();
}

class _CreateStoreStarterScreenState extends State<CreateStoreStarterScreen> {
  bool _busy = false;

  /// Both ways off this screen end on the dashboard, and neither can be taken
  /// back from inside the app, so each asks first.
  Future<void> _confirmCreate() => _confirmThenCreate(
    title: 'Create ${widget.storeName}?',
    message:
        'Your tindahan starts with an empty catalog and opens on the '
        'dashboard. You can add products anytime.',
    confirmLabel: 'Create Store',
  );

  Future<void> _confirmSkip() => _confirmThenCreate(
    title: 'Skip inventory seed?',
    message:
        '${widget.storeName} will be created with no products. You can '
        'add them later from the POS screen.',
    confirmLabel: 'Skip & Create',
  );

  Future<void> _confirmThenCreate({
    required String title,
    required String message,
    required String confirmLabel,
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
    await _create();
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      await widget.onCreate();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      CreateStoreScaffold.showMessage(
        context,
        'Could not create your tindahan: $error',
      );
    }
  }

  void _proNotAvailable() {
    CreateStoreScaffold.showMessage(
      context,
      'TindaTrack Pro is not available yet.',
    );
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
          _StarterInventorySection(onPro: _proNotAvailable),
          const SizedBox(height: 20),
          _HelpersSection(onPro: _proNotAvailable),
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
  const _StarterInventorySection({required this.onPro});

  final VoidCallback onPro;

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
        _ModeSelector(onPro: onPro),
        const SizedBox(height: 12),
        _CleanSlateCard(onPro: onPro),
      ],
    );
  }
}

/// "Start Empty" / "Starter Pack" toggle. Start Empty is the only mode that
/// can be selected, so there is no state to hold.
class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.onPro});

  final VoidCallback onPro;

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
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(AppRadius.base),
                boxShadow: _cardShadow,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Start Empty',
                      style: AppTypography.bodySm.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'FREE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: InkWell(
              onTap: onPro,
              borderRadius: BorderRadius.circular(AppRadius.base),
              child: SizedBox(
                height: 40,
                child: Opacity(
                  opacity: 0.8,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.lock,
                          size: 18,
                          color: AppColors.statusLowStock,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Starter Pack',
                          style: AppTypography.bodySm.copyWith(
                            fontWeight: FontWeight.w500,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const _ProBadge(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CleanSlateCard extends StatelessWidget {
  const _CleanSlateCard({required this.onPro});

  final VoidCallback onPro;

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
                  child: const Icon(
                    Icons.lock,
                    size: 18,
                    color: AppColors.statusLowStock,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
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
                        'Pre-seeds 50+ popular snacks, sachets & drinks',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _SmallPrimaryButton(
                  label: 'Unlock',
                  icon: Icons.upgrade,
                  onPressed: onPro,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpersSection extends StatelessWidget {
  const _HelpersSection({required this.onPro});

  final VoidCallback onPro;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Expanded(
              child: Text('INVITE STORE HELPERS', style: _sectionTitleStyle),
            ),
            _ProBadge(icon: true),
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
          child: Column(
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
                    _SmallPrimaryButton(label: 'Upgrade', onPressed: onPro),
                  ],
                ),
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
