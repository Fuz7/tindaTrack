import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/product_service.dart';
import '../services/sku.dart';
import '../theme/app_theme.dart';

/// "Add New Product" — a Flutter build of the Stitch design of that name
/// (project 14772063175572299152): photo slot, name, optional size, buy and
/// sell prices, opening stock, categories and a SKU, saved with a pinned
/// button.
///
/// Categories are multi-select; the first one picked is the product's main
/// category, marked MAIN, and is what the SKU is built from. The SKU fills
/// itself in from the name, size and main category until the owner types
/// their own. Photo upload and the stock tally calculator are not built yet.
class AddProductScreen extends StatefulWidget {
  const AddProductScreen({
    super.key,
    required this.onSave,
    this.existingCategories = const [],
    this.existingSkus = const {},
  });

  /// Saves the product to the on-device catalog, which reaches the server on
  /// its own time. The screen closes as soon as this is called rather than
  /// when it completes, so the cashier never waits on storage; a failure is
  /// shown as a snackbar on the screen underneath.
  final Future<void> Function(ProductDraft draft) onSave;

  /// Categories the store already uses, offered next to the defaults.
  final List<String> existingCategories;

  /// SKUs already in the catalog; a new one must differ, ignoring case.
  final Set<String> existingSkus;

  static const defaultCategories = [
    'Snacks',
    'Drinks',
    'Pantry',
    'Canned Goods',
    'Household',
  ];

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _buy = TextEditingController();
  final _sell = TextEditingController();
  final _stock = TextEditingController();
  final _size = TextEditingController();
  final _sku = TextEditingController();

  late final List<String> _categories = [
    ...AddProductScreen.defaultCategories,
    for (final c in widget.existingCategories)
      if (!AddProductScreen.defaultCategories.contains(c)) c,
  ];

  /// Picked categories in the order picked; the first is the main one.
  final _selected = <String>[];

  /// The random end of the suggested SKU, rolled once so the suggestion
  /// doesn't flicker as the owner types.
  late String _skuTag = randomSkuTag();

  /// The SKU last filled in automatically. While the field still holds it
  /// (or is blank), it keeps following the name, size and main category;
  /// once the owner types something else, it is theirs and is left alone.
  String _autoSku = '';

  @override
  void initState() {
    super.initState();
    _name.addListener(_refreshSku);
    _size.addListener(_refreshSku);
  }

  @override
  void dispose() {
    _name.dispose();
    _buy.dispose();
    _sell.dispose();
    _stock.dispose();
    _size.dispose();
    _sku.dispose();
    super.dispose();
  }

  bool get _skuIsAuto => _sku.text.isEmpty || _sku.text == _autoSku;

  void _refreshSku() {
    if (!_skuIsAuto) return;
    final suggestion =
        generateSku(
          name: _name.text,
          size: _size.text,
          mainCategory: _selected.firstOrNull,
          tag: _skuTag,
          taken: widget.existingSkus,
        ) ??
        '';
    // Keep the rolled tag if a clash forced a new one.
    if (suggestion.isNotEmpty) _skuTag = suggestion.split('-').last;
    _autoSku = suggestion;
    if (_sku.text != suggestion) _sku.text = suggestion;
    if (mounted) setState(() {}); // the helper line follows auto vs. own
  }

  void _toggleCategory(String category) {
    setState(() {
      if (!_selected.remove(category)) _selected.add(category);
    });
    _refreshSku();
  }

  String? _validateSku(String? value) {
    final sku = normalizeSku(value ?? '');
    if (sku.isEmpty) return null; // optional
    final taken = widget.existingSkus.any((s) => s.toUpperCase() == sku);
    return taken ? 'Another product already uses this SKU.' : null;
  }

  void _notBuilt(String feature) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$feature is not built yet.')));
  }

  Future<void> _addCustomCategory() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _CustomCategoryDialog(),
    );
    if (name == null || !mounted) return;
    setState(() {
      // Reuse a matching category, whatever its case, rather than add a
      // near-duplicate the Inventory chips would then show twice.
      final existing = _categories.where(
        (c) => c.toLowerCase() == name.toLowerCase(),
      );
      final category = existing.isEmpty ? name : existing.first;
      if (existing.isEmpty) _categories.add(category);
      if (!_selected.contains(category)) _selected.add(category);
    });
    _refreshSku();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final draft = ProductDraft(
      name: _name.text.trim(),
      sellCentavos: parseCentavos(_sell.text)!,
      buyCentavos: parseCentavos(_buy.text),
      stock: int.tryParse(_stock.text) ?? 0,
      size: _size.text.trim().isEmpty ? null : _size.text.trim(),
      sku: normalizeSku(_sku.text).isEmpty ? null : normalizeSku(_sku.text),
      categories: List.of(_selected),
    );

    final messenger = ScaffoldMessenger.of(context);
    widget.onSave(draft).catchError((Object _) {
      // Replace, not queue behind, the optimistic "added" message.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Could not save “${draft.name}”. Try again.')),
        );
    });
    Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('“${draft.name}” added.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const _Header(),
            Expanded(
              child: Form(
                key: _formKey,
                // Not a ListView: that builds lazily, and a field scrolled out
                // of view would be skipped by validate() and saved blank.
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    24,
                    AppSpacing.gutter,
                    24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Add New Product',
                        style: AppTypography.headlineMd.copyWith(
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Register a new item to your store inventory.',
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _ImageSlot(onTap: () => _notBuilt('Photo upload')),
                      const SizedBox(height: 32),
                      _Field(
                        label: 'PRODUCT NAME',
                        child: TextFormField(
                          controller: _name,
                          textInputAction: TextInputAction.next,
                          textCapitalization: TextCapitalization.words,
                          style: _inputStyle,
                          decoration: _decoration(
                            'e.g., San Miguel Pale Pilsen',
                          ),
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? 'Enter a product name.'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _Field(
                        label: 'SIZE (OPTIONAL)',
                        child: TextFormField(
                          controller: _size,
                          textInputAction: TextInputAction.next,
                          style: _inputStyle,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(20),
                          ],
                          decoration: _decoration('e.g., 330ml, 40g, Large'),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _Field(
                              label: 'BUY PRICE (₱)',
                              child: _PriceField(
                                controller: _buy,
                                validator: (_) => null, // optional
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.stackMd),
                          Expanded(
                            child: _Field(
                              label: 'SELL PRICE (₱)',
                              child: _PriceField(
                                controller: _sell,
                                validator: (value) =>
                                    (parseCentavos(value ?? '') ?? 0) == 0
                                    ? 'Enter a price.'
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _Field(
                        label: 'INITIAL STOCK COUNT',
                        child: TextFormField(
                          controller: _stock,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(5),
                          ],
                          style: _inputStyle,
                          decoration: _decoration('0').copyWith(
                            suffixIcon: IconButton(
                              tooltip: 'Tally stock',
                              icon: const Icon(Icons.calculate_outlined),
                              color: AppColors.onSurfaceVariant,
                              onPressed: () => _notBuilt('The stock tally'),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'CATEGORIES',
                              style: AppTypography.labelCaps.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _addCustomCategory,
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              minimumSize: const Size(0, 36),
                            ),
                            child: Text(
                              '+ ADD CUSTOM',
                              style: AppTypography.labelCaps,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: AppSpacing.stackSm,
                        runSpacing: AppSpacing.stackSm,
                        children: [
                          for (final category in _categories)
                            _CategoryTag(
                              label: category,
                              selected: _selected.contains(category),
                              main: _selected.firstOrNull == category,
                              onTap: () => _toggleCategory(category),
                            ),
                        ],
                      ),
                      if (_selected.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.stackSm),
                        Text(
                          'The first category picked is the main one.',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      _Field(
                        label: 'SKU',
                        child: TextFormField(
                          controller: _sku,
                          textCapitalization: TextCapitalization.characters,
                          style: _inputStyle,
                          inputFormatters: [
                            FilteringTextInputFormatter.deny(RegExp(r'\s')),
                            LengthLimitingTextInputFormatter(24),
                          ],
                          // Rebuild so the helper line tracks auto vs. own.
                          onChanged: (_) => setState(() {}),
                          decoration: _decoration('Fills in from the name')
                              .copyWith(
                                helperText: _skuIsAuto && _sku.text.isNotEmpty
                                    ? 'Suggested — type over it to use your own code.'
                                    : null,
                                helperStyle: AppTypography.bodySm.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                          validator: _validateSku,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _SaveBar(onPressed: _save),
          ],
        ),
      ),
    );
  }
}

/// Parses a peso amount typed as `12`, `12.5` or `12.50` into centavos, by
/// string rather than through a double so `0.1` is exactly 10. Null when
/// blank or malformed.
int? parseCentavos(String text) {
  final match = RegExp(r'^(\d+)(?:\.(\d{0,2}))?$').firstMatch(text.trim());
  if (match == null) return null;
  final cents = (match.group(2) ?? '').padRight(2, '0');
  return int.parse(match.group(1)!) * 100 + int.parse(cents);
}

const _inputStyle = TextStyle(
  fontSize: 16,
  height: 24 / 16,
  fontWeight: FontWeight.w500,
  color: AppColors.onSurface,
);

InputDecoration _decoration(String hint) {
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.base),
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecoration(
    hintText: hint,
    hintStyle: _inputStyle.copyWith(color: AppColors.outline),
    filled: true,
    fillColor: AppColors.surfaceContainerLowest,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    border: border(AppColors.surfaceBorder),
    enabledBorder: border(AppColors.surfaceBorder),
    focusedBorder: border(AppColors.primary, 2),
    errorBorder: border(AppColors.error),
    focusedErrorBorder: border(AppColors.error, 2),
  );
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSpacing.touchTarget,
      padding: const EdgeInsets.only(left: AppSpacing.gutter - 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.surfaceBorder)),
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
          Text(
            'Inventory',
            style: AppTypography.headlineMd.copyWith(color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}

class _ImageSlot extends StatelessWidget {
  const _ImageSlot({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The design's slot is square; capped so the form stays in reach on a
    // tall phone instead of opening on a screenful of dashed border.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: AspectRatio(
          aspectRatio: 1,
          child: Material(
            color: AppColors.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: onTap,
              child: CustomPaint(
                painter: const _DashedBorder(
                  color: AppColors.outlineVariant,
                  radius: AppRadius.md,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.add_a_photo_outlined,
                      size: 36,
                      color: AppColors.onSurfaceVariant,
                    ),
                    const SizedBox(height: AppSpacing.stackSm),
                    Text(
                      'UPLOAD PRODUCT IMAGE',
                      textAlign: TextAlign.center,
                      style: AppTypography.labelCaps.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The design's 2px dashed outline, which [BoxDecoration] can't draw.
class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const _dash = 6.0;
  static const _gap = 4.0;
  static const _width = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _width;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(_width / 2),
          Radius.circular(radius),
        ),
      );
    for (final metric in outline.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += _dash + _gap) {
        canvas.drawPath(metric.extractPath(d, d + _dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) =>
      old.color != color || old.radius != radius;
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.labelCaps.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.stackSm),
        child,
      ],
    );
  }
}

class _PriceField extends StatelessWidget {
  const _PriceField({required this.controller, required this.validator});

  final TextEditingController controller;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      inputFormatters: [
        // Up to ₱999,999.99, the keypad's ceiling.
        FilteringTextInputFormatter.allow(RegExp(r'^\d{0,6}(\.\d{0,2})?')),
      ],
      style: _inputStyle,
      decoration: _decoration('0.00'),
      validator: validator,
    );
  }
}

class _CategoryTag extends StatelessWidget {
  const _CategoryTag({
    required this.label,
    required this.selected,
    required this.main,
    required this.onTap,
  });

  final String label;
  final bool selected;

  /// The main category: tagged MAIN.
  final bool main;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = selected
        ? AppColors.onPrimaryContainer
        : AppColors.onSurface;
    return Semantics(
      selected: selected,
      button: true,
      hint: main ? 'Main category' : null,
      child: Material(
        color: selected
            ? AppColors.primaryContainer
            : AppColors.surfaceContainerLowest,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? AppColors.primary : AppColors.surfaceBorder,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: AppTypography.bodySm.copyWith(color: textColor),
                ),
                if (main) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.onPrimaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Text(
                      'MAIN',
                      style: AppTypography.labelCaps.copyWith(
                        fontSize: 9,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomCategoryDialog extends StatefulWidget {
  const _CustomCategoryDialog();

  @override
  State<_CustomCategoryDialog> createState() => _CustomCategoryDialogState();
}

class _CustomCategoryDialogState extends State<_CustomCategoryDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Custom category'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        maxLength: 24,
        decoration: const InputDecoration(hintText: 'e.g., Frozen'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.stackMd,
        AppSpacing.gutter,
        AppSpacing.stackMd,
      ),
      color: AppColors.surface,
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.save_outlined),
          label: Text(
            'Save Product',
            style: AppTypography.headlineMd.copyWith(
              color: AppColors.onPrimary,
            ),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
        ),
      ),
    );
  }
}
