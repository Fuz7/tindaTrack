import 'package:flutter/material.dart';

import '../services/store_service.dart';
import '../theme/app_theme.dart';

/// "Join a Tindahan" — the Stitch "Join a Tindahan (Store List)" design
/// (project 14772063175572299152): the Pro stores whose owners added this
/// user's email as a helper, each with an Access button.
///
/// Both halves are handed in so the screen stays free of Firestore:
/// [loadInvites] finds the stores, [onAccess] joins one. Joining needs no
/// hand-off back — like creating a store, the write flips the store gate.
class JoinStoreScreen extends StatefulWidget {
  const JoinStoreScreen({
    super.key,
    required this.loadInvites,
    required this.onAccess,
  });

  final Future<List<StoreInvite>> Function() loadInvites;
  final Future<void> Function(StoreInvite invite) onAccess;

  @override
  State<JoinStoreScreen> createState() => _JoinStoreScreenState();
}

class _JoinStoreScreenState extends State<JoinStoreScreen> {
  late Future<List<StoreInvite>> _invites = widget.loadInvites();

  /// The store being joined, so only its button spins and the rest wait.
  String? _joining;

  void _retry() {
    setState(() {
      _invites = widget.loadInvites();
    });
  }

  Future<void> _access(StoreInvite invite) async {
    setState(() => _joining = invite.storeId);
    try {
      await widget.onAccess(invite);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not join ${invite.storeName}: $error')),
      );
    } finally {
      if (mounted) setState(() => _joining = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter - 8,
            16,
            AppSpacing.gutter,
            24,
          ),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Go back',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back),
                  color: AppColors.primary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Join a Tindahan',
                    style: AppTypography.headlineLg.copyWith(
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 4, bottom: 24),
              child: Text(
                'Select a store that has authorized your email.',
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: FutureBuilder<List<StoreInvite>>(
                future: _invites,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final invites = snapshot.data;
                  if (snapshot.hasError || invites == null) {
                    return _LoadError(onRetry: _retry);
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final invite in invites) ...[
                        _StoreCard(
                          invite: invite,
                          joining: _joining == invite.storeId,
                          onAccess: _joining == null
                              ? () => _access(invite)
                              : null,
                        ),
                        const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 20),
                      const _MissingStoreNote(),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({
    required this.invite,
    required this.joining,
    required this.onAccess,
  });

  final StoreInvite invite;
  final bool joining;

  /// Null while any store is being joined.
  final VoidCallback? onAccess;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceTonal,
        borderRadius: BorderRadius.circular(AppRadius.base),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: const Icon(
              Icons.storefront_outlined,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invite.storeName,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyLg.copyWith(
                    fontSize: 18,
                    color: AppColors.onSurface,
                  ),
                ),
                if (invite.ownerName.isNotEmpty)
                  Text(
                    invite.ownerName,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 44,
            child: FilledButton(
              onPressed: onAccess,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                // The theme's full-width minimum can't sit in a Row.
                minimumSize: const Size(96, 44),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
              child: joining
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onPrimary,
                      ),
                    )
                  : const Text(
                      'Access',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MissingStoreNote extends StatelessWidget {
  const _MissingStoreNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.base),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: AppColors.outline),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Don't see your store?",
                  style: AppTypography.bodyLg.copyWith(
                    fontSize: 15,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ask the store owner to invite your email address from '
                  'their settings menu.',
                  style: AppTypography.bodySm.copyWith(
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

/// The invite list needs the server; offline, say so and offer a retry.
class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          decoration: BoxDecoration(
            color: AppColors.errorContainer,
            borderRadius: BorderRadius.circular(AppRadius.base),
          ),
          child: Text(
            'Could not load your stores. Check your connection and try again.',
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onErrorContainer,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.stackMd),
        OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    );
  }
}
