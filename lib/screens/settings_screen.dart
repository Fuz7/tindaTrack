import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/product_repository.dart';
import '../services/store_service.dart';
import '../theme/app_theme.dart';

/// Store settings — the Stitch "Settings (Paywalled Allowed Emails)" design
/// (project 14772063175572299152): the store's name, owner and currency, the
/// Pro-locked staff email list, and how far this device has synced.
///
/// The allowed-emails list is a Pro feature: locked as the design has it,
/// and editable — add, rename, remove — once the store is on Pro.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.profile,
    required this.onSave,
    required this.syncStatus,
    required this.staff,
    required this.staffActions,
    required this.onUpgradePro,
    required this.userId,
  });

  /// The signed-in user. Unless it is the store's owner, the screen is read
  /// only and the helpers list is hidden.
  final String userId;

  /// The store's saved profile; null while it loads.
  final Stream<StoreProfile?> profile;

  /// Saves an edited profile. Completing is the server's acknowledgement, so
  /// the screen does not wait for it — it only reports a failure.
  final Future<void> Function(StoreProfile profile) onSave;

  final Stream<SyncStatus> syncStatus;

  /// The store's plan and helpers.
  final Stream<StoreStaff> staff;

  final StaffActions staffActions;

  /// Turns Pro on, once the owner confirms. Like [onSave], it completes on
  /// the server's acknowledgement and is not waited on; [staff] reports the
  /// change.
  final Future<void> Function() onUpgradePro;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// The writes behind the helpers list. Like [SettingsScreen.onSave], each
/// completes on the server's acknowledgement and is not waited on.
class StaffActions {
  const StaffActions({
    required this.add,
    required this.rename,
    required this.remove,
  });

  final Future<void> Function(StaffMember member) add;
  final Future<void> Function(StaffMember member, String name) rename;
  final Future<void> Function(StaffMember member) remove;
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _owner = TextEditingController();
  final _threshold = TextEditingController();
  String _currency = 'PHP';

  /// What is saved; null until the first profile arrives.
  StoreProfile? _saved;
  late final StreamSubscription<StoreProfile?> _profileSub;

  StoreProfile get _edited => StoreProfile(
    name: _name.text.trim(),
    ownerName: _owner.text.trim(),
    currency: _currency,
    // Unparseable reads as 0: it marks the form changed, and validation
    // stops it being saved.
    lowStockThreshold: int.tryParse(_threshold.text) ?? 0,
    ownerUid: _saved?.ownerUid,
  );

  bool get _dirty => _saved != null && _edited != _saved;

  /// Helpers see the store's details but can't change them, and don't see
  /// the helpers list at all. A store without an owner on record is treated
  /// as the viewer's own; Firestore rules still guard the writes.
  bool get _isOwner {
    final ownerUid = _saved?.ownerUid;
    return ownerUid == null || ownerUid == widget.userId;
  }

  /// Read-only fields for helpers: greyed, with a lock.
  InputDecoration _fieldDecoration(String? hint) {
    final decoration = _decoration(hint);
    if (_isOwner) return decoration;
    return decoration.copyWith(
      fillColor: AppColors.surfaceContainerHigh,
      suffixIcon: const Icon(
        Icons.lock_outline,
        size: 18,
        color: AppColors.outline,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _name.addListener(_changed);
    _owner.addListener(_changed);
    _threshold.addListener(_changed);
    _profileSub = widget.profile.listen((profile) {
      if (profile == null) return;
      // A change from another device replaces the fields only when there
      // are no edits here to lose.
      final wasDirty = _dirty;
      setState(() => _saved = profile);
      if (!wasDirty) _reset();
    });
  }

  @override
  void dispose() {
    _profileSub.cancel();
    _name.dispose();
    _owner.dispose();
    _threshold.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  void _reset() {
    final saved = _saved!;
    _name.text = saved.name;
    _owner.text = saved.ownerName;
    _threshold.text = '${saved.lowStockThreshold}';
    setState(() => _currency = saved.currency);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final profile = _edited;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saved = profile);
    widget
        .onSave(profile)
        .catchError(
          (Object error) => messenger.showSnackBar(
            SnackBar(content: Text('Could not save settings: $error')),
          ),
        );
    FocusScope.of(context).unfocus();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Settings saved.')));
  }

  Future<void> _confirmUpgrade() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _UpgradeDialog(storeName: _saved?.name ?? ''),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    widget.onUpgradePro().catchError(
      (Object error) => messenger.showSnackBar(
        SnackBar(content: Text('Could not upgrade to Pro: $error')),
      ),
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Pro is on. You can now add helpers.')),
      );
  }

  static String? _required(String? value) =>
      (value ?? '').trim().isEmpty ? 'Required' : null;

  /// Same bounds as the create flow.
  static String? _validThreshold(String? value) {
    final n = int.tryParse(value ?? '');
    return n == null || n < 1 || n > 100 ? '1–100' : null;
  }

  @override
  Widget build(BuildContext context) {
    final loaded = _saved != null;
    final isOwner = _isOwner;

    return Scaffold(
      backgroundColor: AppColors.surfaceContainerLowest,
      body: SafeArea(
        child: Column(
          children: [
            const _Header(),
            Expanded(
              child: !loaded
                  ? const Center(child: CircularProgressIndicator())
                  : Form(
                      key: _formKey,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.gutter),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!isOwner) const _HelperNote(),
                            _Field(
                              label: 'STORE NAME',
                              child: TextFormField(
                                controller: _name,
                                enabled: isOwner,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                validator: _required,
                                style: _inputStyle,
                                decoration: _fieldDecoration(
                                  "e.g., Aling Nena's Sari-Sari Store",
                                ),
                              ),
                            ),
                            _Field(
                              label: 'STORE OWNER NAME',
                              child: TextFormField(
                                controller: _owner,
                                enabled: isOwner,
                                textCapitalization: TextCapitalization.words,
                                validator: _required,
                                style: _inputStyle,
                                decoration: _fieldDecoration('Juan Dela Cruz'),
                              ),
                            ),
                            _Field(
                              label: 'CURRENCY',
                              child: DropdownButtonFormField<String>(
                                initialValue: _currency,
                                // Re-keyed so Discard and remote changes
                                // move the selection too.
                                key: ValueKey(_currency),
                                isExpanded: true,
                                // Null disables the dropdown for helpers.
                                onChanged: isOwner
                                    ? (value) =>
                                          setState(() => _currency = value!)
                                    : null,
                                disabledHint: Text(
                                  StoreDraft.currencies[_currency] ?? _currency,
                                  overflow: TextOverflow.ellipsis,
                                  style: _inputStyle,
                                ),
                                icon: Icon(
                                  isOwner
                                      ? Icons.expand_more
                                      : Icons.lock_outline,
                                  size: isOwner ? null : 18,
                                  color: isOwner
                                      ? AppColors.onSurfaceVariant
                                      : AppColors.outline,
                                ),
                                style: _inputStyle,
                                decoration: _fieldDecoration(null),
                                items: [
                                  for (final entry in {
                                    ...StoreDraft.currencies,
                                    // Keep a code this app doesn't list
                                    // pickable rather than crash on it.
                                    if (!StoreDraft.currencies.containsKey(
                                      _currency,
                                    ))
                                      _currency: _currency,
                                  }.entries)
                                    DropdownMenuItem(
                                      value: entry.key,
                                      child: Text(
                                        entry.value,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            _Field(
                              label: 'LOW STOCK ALERT',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 128,
                                        child: TextFormField(
                                          controller: _threshold,
                                          enabled: isOwner,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                            LengthLimitingTextInputFormatter(3),
                                          ],
                                          validator: _validThreshold,
                                          style: _inputStyle,
                                          decoration: _fieldDecoration('5'),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Wraps rather than running off a narrow
                                      // screen or under large text.
                                      Flexible(
                                        child: Padding(
                                          // Level with the input's text.
                                          padding: const EdgeInsets.only(
                                            top: 14,
                                          ),
                                          child: Text(
                                            'units or fewer',
                                            style: AppTypography.bodyLg
                                                .copyWith(
                                                  fontWeight: FontWeight.w400,
                                                  color: AppColors
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.stackSm),
                                  Text(
                                    'Products at or below this count are '
                                    'marked LOW STOCK and listed in '
                                    'Inventory and Analytics alerts.',
                                    style: AppTypography.bodySm.copyWith(
                                      color: AppColors.onSurfaceVariant,
                                      height: 1.375,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isOwner) ...[
                              const SizedBox(height: AppSpacing.stackSm),
                              _AllowedEmails(
                                staff: widget.staff,
                                actions: widget.staffActions,
                                onUnlockPro: _confirmUpgrade,
                              ),
                              const SizedBox(height: 24),
                            ],
                            _Field(
                              label: 'SYNC STATUS',
                              child: _SyncStatusCard(status: widget.syncStatus),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            if (loaded && isOwner)
              _Footer(
                onSave: _dirty ? _save : null,
                onDiscard: _dirty ? _reset : null,
              ),
          ],
        ),
      ),
    );
  }

  static final _inputStyle = AppTypography.bodyLg.copyWith(
    color: AppColors.onSurface,
  );

  static InputDecoration _decoration(String? hint) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.base),
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecoration(
      hintText: hint,
      hintStyle: AppTypography.bodyLg.copyWith(
        color: AppColors.outlineVariant,
        fontWeight: FontWeight.w400,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      filled: true,
      fillColor: AppColors.surfaceBright,
      border: border(AppColors.outlineVariant),
      enabledBorder: border(AppColors.outlineVariant),
      disabledBorder: border(AppColors.outlineVariant),
      focusedBorder: border(AppColors.primary, 2),
      errorBorder: border(AppColors.error),
      focusedErrorBorder: border(AppColors.error, 2),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSpacing.touchTarget,
      padding: const EdgeInsets.only(left: AppSpacing.gutter - 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.outlineVariant)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Go back',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
            color: AppColors.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          const Icon(Icons.storefront_outlined, color: AppColors.primary),
          const SizedBox(width: 12),
          Text(
            'Store Profile',
            style: AppTypography.headlineMd.copyWith(color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}

/// Green caps label above its content.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: AppTypography.labelCaps.copyWith(
              color: AppColors.primary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.stackSm),
          child,
        ],
      ),
    );
  }
}

// The design's amber Pro accents are Tailwind amber shades; the Monolith
// palette has no amber beyond the low-stock status color.
const _amber50 = Color(0xFFFFFBEB);
const _amber100 = Color(0xFFFEF3C7);
const _amber200 = Color(0xFFFDE68A);
const _amber300 = Color(0xFFFCD34D);
const _amber700 = Color(0xFFB45309);
const _amber800 = Color(0xFF92400E);
const _amber900 = Color(0xFF78350F);

/// The staff list: helpers' emails and the names their sales are recorded
/// under. Locked behind Pro; with Pro, helpers can be added, renamed and
/// removed. Each change is saved straight away, not with Save Changes.
class _AllowedEmails extends StatelessWidget {
  const _AllowedEmails({
    required this.staff,
    required this.actions,
    required this.onUnlockPro,
  });

  final Stream<StoreStaff> staff;
  final StaffActions actions;
  final VoidCallback onUnlockPro;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<StoreStaff>(
      stream: staff,
      builder: (context, snapshot) {
        final staff = snapshot.data;
        final isPro = staff?.isPro ?? false;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    'ALLOWED EMAILS (STAFF ACCESS)',
                    style: AppTypography.labelCaps.copyWith(
                      color: AppColors.primary,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                if (!isPro) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.lock_outline,
                    size: 16,
                    color: AppColors.outline,
                  ),
                ],
                const Spacer(),
                const _ProBadge(),
              ],
            ),
            const SizedBox(height: 12),
            if (isPro)
              _StaffEditor(members: staff!.members, actions: actions)
            else
              _LockedStaff(onUnlockPro: onUnlockPro),
          ],
        );
      },
    );
  }
}

/// With Pro: an email field to add a helper, and a row per helper with
/// rename and remove.
class _StaffEditor extends StatefulWidget {
  const _StaffEditor({required this.members, required this.actions});

  final List<StaffMember> members;
  final StaffActions actions;

  @override
  State<_StaffEditor> createState() => _StaffEditorState();
}

class _StaffEditorState extends State<_StaffEditor> {
  final _email = TextEditingController();
  String? _error;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  /// Runs a staff write without waiting on the server — Firestore's cache
  /// shows it at once — and reports only a failure.
  void _run(Future<void> write) {
    final messenger = ScaffoldMessenger.of(context);
    write.catchError(
      (Object error) => messenger.showSnackBar(
        SnackBar(content: Text('Could not save staff: $error')),
      ),
    );
  }

  Future<void> _add() async {
    final email = _email.text.trim().toLowerCase();
    final error = !_emailPattern.hasMatch(email)
        ? 'Enter a valid email address.'
        : widget.members.any((m) => m.email == email)
        ? 'That email is already on the list.'
        : null;
    setState(() => _error = error);
    if (error != null) return;

    final name = await _askName(email: email, initial: email.split('@').first);
    if (name == null || !mounted) return;
    _email.clear();
    _run(widget.actions.add(StaffMember(email: email, name: name)));
  }

  Future<void> _rename(StaffMember member) async {
    final name = await _askName(email: member.email, initial: member.name);
    if (name == null || name == member.name || !mounted) return;
    _run(widget.actions.rename(member, name));
  }

  void _remove(StaffMember member) {
    _run(widget.actions.remove(member));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Removed ${member.email}.'),
          // Re-adding keeps their user id, so a helper who had joined stays
          // joined.
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _run(widget.actions.add(member)),
          ),
        ),
      );
  }

  /// The helper's display name, as a dialog; null if cancelled.
  Future<String?> _askName({required String email, required String initial}) {
    return showDialog<String>(
      context: context,
      builder: (context) => _NameDialog(email: email, initial: initial),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                style: AppTypography.bodyLg.copyWith(
                  color: AppColors.onSurface,
                ),
                decoration: _SettingsScreenState._decoration(
                  'Enter helper email address',
                ).copyWith(errorText: _error),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: AppSpacing.touchTarget,
              child: FilledButton(
                onPressed: _add,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  // The theme's full-width minimum can't sit in a Row.
                  minimumSize: const Size(0, AppSpacing.touchTarget),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.base),
                  ),
                ),
                child: const Text(
                  'Add',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        if (widget.members.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'No helpers yet. Add the Google email a helper signs in with.',
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
        for (final member in widget.members) ...[
          const SizedBox(height: 8),
          _StaffRow(
            member: member,
            onEdit: () => _rename(member),
            onRemove: () => _remove(member),
          ),
        ],
      ],
    );
  }
}

class _StaffRow extends StatelessWidget {
  const _StaffRow({
    required this.member,
    required this.onEdit,
    required this.onRemove,
  });

  final StaffMember member;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final name = member.name.trim();

    return Container(
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.base),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline, size: 18, color: AppColors.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'No name' : name,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyLg.copyWith(
                    color: name.isEmpty
                        ? AppColors.outline
                        : AppColors.onSurface,
                  ),
                ),
                Text(
                  member.email,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  member.hasJoined ? 'Joined' : 'Waiting to join',
                  style: AppTypography.bodySm.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: member.hasJoined
                        ? AppColors.primary
                        : AppColors.outline,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit name',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 20),
            color: AppColors.primary,
          ),
          IconButton(
            tooltip: 'Remove helper',
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline, size: 20),
            color: AppColors.actionDestructive,
          ),
        ],
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.email, required this.initial});

  final String email;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Helper name'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sales by ${widget.email} are recorded under this name.',
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => _submit(),
            decoration: _SettingsScreenState._decoration('e.g., Maria'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ListenableBuilder(
          listenable: _name,
          builder: (context, _) => FilledButton(
            onPressed: _name.text.trim().isEmpty ? null : _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size(64, AppSpacing.touchTarget),
            ),
            child: const Text('Save'),
          ),
        ),
      ],
    );
  }
}

/// Without Pro: an upsell card over a disabled preview of the email input
/// and the rows it would fill.
class _LockedStaff extends StatelessWidget {
  const _LockedStaff({required this.onUnlockPro});

  final VoidCallback onUnlockPro;

  static const _examples = ['helper1@gmail.com', 'family@tindatrack.com'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_amber50, Color(0x80FEF3C7)],
            ),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: _amber300.withValues(alpha: 0.8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.statusLowStock.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.base),
                    ),
                    child: const Icon(
                      Icons.group_add_outlined,
                      color: _amber700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Multi-Device Staff Sync',
                              style: AppTypography.bodyLg.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.onSurface,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _amber200,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                              ),
                              child: const Text(
                                'Pro',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _amber900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Allow cashier helpers or family members to log in '
                          'and sync sales in real-time across multiple '
                          'phones.',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                            height: 1.375,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 44,
                child: FilledButton.icon(
                  onPressed: onUnlockPro,
                  icon: const Icon(Icons.stars_outlined, color: _amber300),
                  label: const Text(
                    'Unlock Pro & Add Helpers',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.base),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // A preview of what Pro unlocks: visible, but not interactive.
        ExcludeSemantics(
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: AppSpacing.touchTarget,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(AppRadius.base),
                            border: Border.all(color: AppColors.outlineVariant),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.lock_outline,
                                size: 18,
                                color: AppColors.outline,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Enter helper email address',
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.bodyLg.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        height: AppSpacing.touchTarget,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(AppRadius.base),
                          border: Border.all(color: AppColors.outlineVariant),
                        ),
                        child: Text(
                          'Add',
                          style: AppTypography.bodyLg.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  for (final email in _examples) ...[
                    const SizedBox(height: 8),
                    _LockedEmailRow(email: email),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Tells a helper why the store's details are locked.
class _HelperNote extends StatelessWidget {
  const _HelperNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(AppSpacing.gutter),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.base),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "You're signed in as a helper. Only the store owner can change "
              'these details.',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
                height: 1.375,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks before turning Pro on. Returns true on Confirm.
class _UpgradeDialog extends StatelessWidget {
  const _UpgradeDialog({required this.storeName});

  final String storeName;

  @override
  Widget build(BuildContext context) {
    final store = storeName.trim().isEmpty ? 'this tindahan' : storeName;

    return AlertDialog(
      icon: const Icon(
        Icons.workspace_premium_outlined,
        size: 32,
        color: _amber700,
      ),
      title: const Text('Upgrade to Pro?'),
      content: Text(
        'Turn on Multi-Device Staff Sync for $store. You can then add '
        'helpers who log in and ring up sales on their own phones.',
        style: AppTypography.bodySm.copyWith(
          color: AppColors.onSurfaceVariant,
          height: 1.375,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            minimumSize: const Size(64, AppSpacing.touchTarget),
          ),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}

class _ProBadge extends StatelessWidget {
  const _ProBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _amber100,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: _amber300),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium_outlined, size: 13, color: _amber700),
          SizedBox(width: 4),
          Text(
            'PRO',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _amber800,
            ),
          ),
        ],
      ),
    );
  }
}

class _LockedEmailRow extends StatelessWidget {
  const _LockedEmailRow({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.base),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline, size: 18, color: AppColors.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              email,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySm.copyWith(color: AppColors.onSurface),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _amber100.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 12, color: _amber800),
                SizedBox(width: 4),
                Text(
                  'Requires Pro',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _amber800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.edit_outlined, size: 18, color: AppColors.outline),
        ],
      ),
    );
  }
}

/// Whether this device's changes have reached the server, and when they
/// last all had.
class _SyncStatusCard extends StatefulWidget {
  const _SyncStatusCard({required this.status});

  final Stream<SyncStatus> status;

  @override
  State<_SyncStatusCard> createState() => _SyncStatusCardState();
}

class _SyncStatusCardState extends State<_SyncStatusCard> {
  /// Keeps "N minutes ago" honest while the screen stays open.
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  static String _ago(DateTime time) {
    final elapsed = DateTime.now().difference(time);
    String plural(int n, String unit) => '$n $unit${n == 1 ? '' : 's'} ago';
    if (elapsed.inMinutes < 1) return 'just now';
    if (elapsed.inHours < 1) return plural(elapsed.inMinutes, 'minute');
    if (elapsed.inDays < 1) return plural(elapsed.inHours, 'hour');
    return plural(elapsed.inDays, 'day');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncStatus>(
      stream: widget.status,
      builder: (context, snapshot) {
        final status = snapshot.data;
        final lastSynced = status?.lastSyncedAt;

        final (Color dot, String title) = switch (status) {
          null => (AppColors.outline, 'Status: Checking…'),
          SyncStatus(:final pending) when pending > 0 => (
            AppColors.statusLowStock,
            'Status: $pending change${pending == 1 ? '' : 's'} waiting',
          ),
          SyncStatus(lastSyncedAt: null) => (
            AppColors.outline,
            'Status: Not synced yet',
          ),
          _ => (AppColors.statusInStock, 'Status: Synced'),
        };

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.base),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(Icons.circle, size: 14, color: dot),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.bodyLg.copyWith(
                        color: AppColors.onSurface,
                      ),
                    ),
                    Text(
                      lastSynced == null
                          ? 'Changes are kept on this phone until online.'
                          : 'Last synced: ${_ago(lastSynced)}',
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
      },
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.onSave, required this.onDiscard});

  /// Null while nothing has changed.
  final VoidCallback? onSave;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.base),
    );
    const label = TextStyle(fontSize: 16, fontWeight: FontWeight.w700);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLow,
        border: Border(top: BorderSide(color: AppColors.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: AppSpacing.touchTarget,
            child: FilledButton(
              onPressed: onSave,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                disabledBackgroundColor: AppColors.surfaceContainerHighest,
                shape: shape,
              ),
              child: const Text('Save Changes', style: label),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: AppSpacing.touchTarget,
            child: OutlinedButton(
              onPressed: onDiscard,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.onSurfaceVariant,
                side: const BorderSide(color: AppColors.outlineVariant),
                shape: shape,
              ),
              child: const Text('Discard Changes', style: label),
            ),
          ),
        ],
      ),
    );
  }
}
