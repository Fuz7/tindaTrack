import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/store_service.dart';
import '../theme/app_theme.dart';
import '../widgets/create_store_scaffold.dart';

/// Step 1 of "Create New Tindahan" — the Stitch "Create New Tindahan Setup"
/// design (project 14772063175572299152).
///
/// Collects a [StoreDraft] and hands it upward; nothing is written here. That
/// is why the action reads "Continue" rather than the design's "Create Store &
/// Continue" — the store only exists once step 2 commits it.
class CreateStoreProfileScreen extends StatefulWidget {
  const CreateStoreProfileScreen({
    super.key,
    required this.onContinue,
    this.initialOwnerName,
  });

  final ValueChanged<StoreDraft> onContinue;

  /// Pre-fills the owner field, typically from the Google account name.
  final String? initialOwnerName;

  @override
  State<CreateStoreProfileScreen> createState() =>
      _CreateStoreProfileScreenState();
}

class _CreateStoreProfileScreenState extends State<CreateStoreProfileScreen> {
  static const _currencies = {
    'PHP': '₱ PHP (Philippine Peso)',
    'USD': r'$ USD (US Dollar)',
  };

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  late final _owner = TextEditingController(text: widget.initialOwnerName);
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _threshold = TextEditingController(text: '5');
  String _currency = 'PHP';

  @override
  void dispose() {
    _name.dispose();
    _owner.dispose();
    _phone.dispose();
    _address.dispose();
    _threshold.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    String? optional(TextEditingController c) {
      final text = c.text.trim();
      return text.isEmpty ? null : text;
    }

    widget.onContinue(
      StoreDraft(
        name: _name.text.trim(),
        ownerName: _owner.text.trim(),
        phone: optional(_phone),
        currency: _currency,
        address: optional(_address),
        lowStockThreshold: int.parse(_threshold.text),
      ),
    );
  }

  static String? _required(String? value) =>
      (value ?? '').trim().isEmpty ? 'Required' : null;

  static String? _validThreshold(String? value) {
    final n = int.tryParse(value ?? '');
    return n == null || n < 1 || n > 100 ? '1–100' : null;
  }

  @override
  Widget build(BuildContext context) {
    return CreateStoreScaffold(
      step: 1,
      stepLabel: 'Store Setup',
      actionLabel: 'Continue',
      onAction: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Field(
              label: 'Store Name',
              required: true,
              child: TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                validator: _required,
                style: _inputStyle,
                decoration: _decoration(
                  Icons.storefront_outlined,
                  "e.g., Aling Nena's Sari-Sari Store",
                ),
              ),
            ),
            _Field(
              label: 'Owner Name',
              required: true,
              child: TextFormField(
                controller: _owner,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                validator: _required,
                style: _inputStyle,
                decoration: _decoration(Icons.person_outline, 'Juan Dela Cruz'),
              ),
            ),
            _Field(
              label: 'Store Contact / Phone',
              optional: true,
              child: TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                style: _inputStyle,
                decoration: _decoration(
                  Icons.call_outlined,
                  '+63 912 345 6789',
                ),
              ),
            ),
            _Field(
              label: 'Primary Currency',
              child: DropdownButtonFormField<String>(
                initialValue: _currency,
                isExpanded: true,
                onChanged: (value) => setState(() => _currency = value!),
                icon: const Icon(
                  Icons.expand_more,
                  color: AppColors.outlineVariant,
                ),
                style: _inputStyle,
                decoration: _decoration(Icons.payments_outlined, null),
                items: [
                  for (final entry in _currencies.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value, overflow: TextOverflow.ellipsis),
                    ),
                ],
              ),
            ),
            _Field(
              label: 'Store Address / Landmark',
              optional: true,
              child: TextFormField(
                controller: _address,
                minLines: 2,
                maxLines: 2,
                textCapitalization: TextCapitalization.words,
                style: _inputStyle,
                decoration: _decoration(
                  Icons.location_on_outlined,
                  'e.g., Barangay San Antonio, Pasig City',
                  alignIconTop: true,
                ),
              ),
            ),
            _ThresholdCard(controller: _threshold, validator: _validThreshold),
            const SizedBox(height: AppSpacing.stackMd),
            const _InfoNote(),
          ],
        ),
      ),
    );
  }

  static final _inputStyle = AppTypography.bodyLg.copyWith(
    color: AppColors.onSurface,
  );

  static InputDecoration _decoration(
    IconData icon,
    String? hint, {
    bool alignIconTop = false,
  }) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.base),
          borderSide: BorderSide(color: color, width: width),
        );

    final prefix = Icon(icon, color: AppColors.outlineVariant);

    return InputDecoration(
      hintText: hint,
      hintStyle: AppTypography.bodyLg.copyWith(
        color: AppColors.outlineVariant,
        fontWeight: FontWeight.w400,
      ),
      prefixIcon: alignIconTop
          // Textarea: the icon sits on the first line, not mid-height.
          ? Padding(padding: const EdgeInsets.only(bottom: 24), child: prefix)
          : prefix,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      filled: true,
      fillColor: AppColors.surfaceContainerLowest,
      border: border(AppColors.surfaceBorder),
      enabledBorder: border(AppColors.surfaceBorder),
      focusedBorder: border(AppColors.primary, 2),
      errorBorder: border(AppColors.error),
      focusedErrorBorder: border(AppColors.error, 2),
    );
  }
}

/// Uppercase label (with required star or "(optional)") above an input.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.child,
    this.required = false,
    this.optional = false,
  });

  final String label;
  final Widget child;
  final bool required;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final labelStyle = AppTypography.labelCaps.copyWith(
      color: AppColors.onSurfaceVariant,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.stackMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: label.toUpperCase(),
                    children: [
                      if (required)
                        const TextSpan(
                          text: ' *',
                          style: TextStyle(color: AppColors.error),
                        ),
                    ],
                  ),
                  style: labelStyle,
                ),
              ),
              if (optional)
                const Text(
                  '(optional)',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.outlineVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.stackSm),
          child,
        ],
      ),
    );
  }
}

class _ThresholdCard extends StatelessWidget {
  const _ThresholdCard({required this.controller, required this.validator});

  final TextEditingController controller;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: color, width: width),
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.base),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.notification_important_outlined,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Low Stock Alert Threshold',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              SizedBox(
                width: 64,
                child: TextFormField(
                  controller: controller,
                  validator: validator,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 9,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceContainerLow,
                    errorStyle: const TextStyle(fontSize: 10),
                    border: border(AppColors.surfaceBorder),
                    enabledBorder: border(AppColors.surfaceBorder),
                    focusedBorder: border(AppColors.primary, 2),
                    errorBorder: border(AppColors.error),
                    focusedErrorBorder: border(AppColors.error, 2),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'units',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Notify when item stock falls below this count so you never run '
            'out of essential goods.',
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.base),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'You can invite collaborators and export or sync store data '
              'anytime in Settings after setup.',
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
