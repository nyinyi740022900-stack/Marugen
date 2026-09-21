import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/product.dart';
import '../../shop/data/product_repository.dart';
import '../../shop/presentation/shop_providers.dart';

/// Create/edit form for a product. Pass `productId == null` to create new.
class AdminProductEditScreen extends ConsumerStatefulWidget {
  final String? productId;
  const AdminProductEditScreen({super.key, this.productId});

  @override
  ConsumerState<AdminProductEditScreen> createState() =>
      _AdminProductEditScreenState();
}

class _AdminProductEditScreenState
    extends ConsumerState<AdminProductEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _salePriceCtrl = TextEditingController();
  final _videoUrlCtrl = TextEditingController();
  final _stockCtrl = TextEditingController(text: '1');
  final _varietyCtrl = TextEditingController();
  final _sizeCtrl = TextEditingController();
  final _breederCtrl = TextEditingController();

  ProductCategory _category = ProductCategory.koi;
  bool _showPrice = true;
  bool _hasCertificate = false;
  final List<XFile> _newImages = [];
  final List<String> _existingImageUrls = [];
  bool _loading = false;
  bool _initialLoad = true;

  // Variants (weight options) — only shown for restockable goods
  // (fish_food/accessories). Existing rows carry their variant id so
  // _save() knows to update rather than insert; ids removed from this
  // list between load and save get deleted.
  final List<_VariantRow> _variants = [];
  final Set<String> _deletedVariantIds = {};

  // Product-level size labels (e.g. pellet Small/Medium/Large) — independent
  // of weight price; stock is entered in the weight×size matrix below.
  final List<TextEditingController> _sizeOptionCtrls = [];

  /// Matrix cells keyed by "$variantIndex::$sizeLabel".
  final Map<String, TextEditingController> _sizeStockCtrls = {};
  final _fillAllStockCtrl = TextEditingController();

  bool get isLiveFish =>
      _category == ProductCategory.koi || _category == ProductCategory.arowana;

  /// Every category can list options now — weight options for food, or
  /// individual fish/varieties for a batch listing (e.g. "Japan Imported
  /// Koi Selection" photographed as one group shot, sold as separate
  /// Kohaku/Showa/etc. picks underneath).
  bool get supportsVariants => true;

  /// The pellet-size × weight stock matrix only makes sense for
  /// restockable goods — a live fish option is one specific animal, not a
  /// bag with a size choice.
  bool get supportsSizeMatrix => !isLiveFish;

  bool get _usesSizeStockMatrix =>
      supportsSizeMatrix && _collectedSizeOptions().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    if (widget.productId == null) {
      setState(() => _initialLoad = false);
      return;
    }
    final product = await ProductRepository().fetchProductById(
      widget.productId!,
    );
    if (product != null) {
      _nameCtrl.text = product.name;
      _descCtrl.text = product.description ?? '';
      _priceCtrl.text = product.price?.toString() ?? '';
      _salePriceCtrl.text = product.salePrice?.toString() ?? '';
      _videoUrlCtrl.text = product.videoUrl ?? '';
      _stockCtrl.text = '${product.stockQuantity}';
      _category = product.category;
      _showPrice = product.showPrice;
      _existingImageUrls.addAll(product.imageUrls);
      if (product.fishDetails != null) {
        _varietyCtrl.text = product.fishDetails!.variety ?? '';
        _sizeCtrl.text = product.fishDetails!.sizeCm?.toString() ?? '';
        _breederCtrl.text = product.fishDetails!.breeder ?? '';
        _hasCertificate = product.fishDetails!.hasCertificate;
      }
      for (var i = 0; i < product.variants.length; i++) {
        final v = product.variants[i];
        _variants.add(_VariantRow.existing(v));
        for (final size in product.sizeOptions) {
          _sizeStockCtrls['$i::$size'] = TextEditingController(
            text: '${v.sizeStocks[size] ?? 0}',
          );
        }
      }
      for (final size in product.sizeOptions) {
        _sizeOptionCtrls.add(TextEditingController(text: size));
      }
    }
    if (mounted) setState(() => _initialLoad = false);
  }

  void _addVariantRow() {
    setState(() => _variants.add(_VariantRow.blank()));
  }

  void _removeVariantRow(int index) {
    final row = _variants[index];
    if (row.id != null) _deletedVariantIds.add(row.id!);
    final sizes = _collectedSizeOptions();
    for (final size in sizes) {
      _sizeStockCtrls.remove('$index::$size')?.dispose();
    }
    // Re-key controllers after the hole so indices stay aligned with rows.
    final rekeyed = <String, TextEditingController>{};
    for (final entry in _sizeStockCtrls.entries) {
      final parts = entry.key.split('::');
      if (parts.length != 2) continue;
      final i = int.tryParse(parts[0]);
      if (i == null) continue;
      if (i < index) {
        rekeyed[entry.key] = entry.value;
      } else if (i > index) {
        rekeyed['${i - 1}::${parts[1]}'] = entry.value;
      }
    }
    _sizeStockCtrls
      ..clear()
      ..addAll(rekeyed);
    setState(() => _variants.removeAt(index));
  }

  void _addSizeOptionRow() {
    setState(() => _sizeOptionCtrls.add(TextEditingController()));
  }

  void _removeSizeOptionRow(int index) {
    final removedLabel = _sizeOptionCtrls[index].text.trim();
    final ctrl = _sizeOptionCtrls.removeAt(index);
    ctrl.dispose();
    if (removedLabel.isNotEmpty) {
      for (var i = 0; i < _variants.length; i++) {
        _sizeStockCtrls.remove('$i::$removedLabel')?.dispose();
      }
    }
    setState(() {});
  }

  List<String> _collectedSizeOptions() {
    final seen = <String>{};
    final out = <String>[];
    for (final ctrl in _sizeOptionCtrls) {
      final label = ctrl.text.trim();
      if (label.isEmpty || seen.contains(label)) continue;
      seen.add(label);
      out.add(label);
    }
    return out;
  }

  TextEditingController _sizeStockCtrl(int variantIndex, String size) {
    return _sizeStockCtrls.putIfAbsent(
      '$variantIndex::$size',
      () => TextEditingController(text: '0'),
    );
  }

  /// Sets every weight×size cell to the Fill all value (empty → 0).
  void _fillAllSizeStocks() {
    final qty = int.tryParse(_fillAllStockCtrl.text.trim()) ?? 0;
    final clamped = qty < 0 ? 0 : qty;
    final sizes = _collectedSizeOptions();
    for (var i = 0; i < _variants.length; i++) {
      if (_variants[i].labelCtrl.text.trim().isEmpty) continue;
      for (final size in sizes) {
        _sizeStockCtrl(i, size).text = '$clamped';
      }
    }
    setState(() {});
  }

  Future<void> _saveVariants(String productId, ProductRepository repo) async {
    for (final id in _deletedVariantIds) {
      await repo.deleteVariant(id);
    }
    final sizes = _collectedSizeOptions();
    final useMatrix = sizes.isNotEmpty;

    for (var i = 0; i < _variants.length; i++) {
      final row = _variants[i];
      final label = row.labelCtrl.text.trim();
      if (label.isEmpty) continue; // skip incomplete rows silently
      final payload = {
        'product_id': productId,
        'label': label,
        'price': double.tryParse(row.priceCtrl.text.trim()) ?? 0,
        // Weight-level stock is unused when the size matrix owns inventory.
        'stock_quantity': useMatrix
            ? 0
            : int.tryParse(row.stockCtrl.text.trim()) ?? 0,
        'sort_order': i,
      };
      final String variantId;
      if (row.id == null) {
        variantId = (await repo.createVariant(payload)).id;
      } else {
        await repo.updateVariant(row.id!, payload);
        variantId = row.id!;
      }
      if (useMatrix) {
        for (final size in sizes) {
          final qty =
              int.tryParse(_sizeStockCtrl(i, size).text.trim()) ?? 0;
          await repo.upsertVariantSizeStock(
            variantId: variantId,
            sizeLabel: size,
            stockQuantity: qty,
          );
        }
      }
    }
    await repo.deleteOrphanSizeStocks(
      productId: productId,
      keepSizes: sizes,
    );
  }

  Future<void> _pickImages() async {
    final picked = await ImagePicker().pickMultiImage(imageQuality: 85);
    setState(() => _newImages.addAll(picked));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final repo = ProductRepository();
      final categoryValue = _category == ProductCategory.fishFood
          ? 'fish_food'
          : _category.name;

      final payload = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        'category': categoryValue,
        'price': _priceCtrl.text.trim().isEmpty
            ? null
            : double.tryParse(_priceCtrl.text.trim()),
        'sale_price': _salePriceCtrl.text.trim().isEmpty
            ? null
            : double.tryParse(_salePriceCtrl.text.trim()),
        'video_url': _videoUrlCtrl.text.trim().isEmpty
            ? null
            : _videoUrlCtrl.text.trim(),
        'show_price': _showPrice,
        'stock_quantity': int.tryParse(_stockCtrl.text.trim()) ?? 0,
        // Clear size list when switching a restockable product to live fish.
        'size_options':
            supportsSizeMatrix ? _collectedSizeOptions() : <String>[],
        if (isLiveFish)
          'fish_details': {
            'variety': _varietyCtrl.text.trim().isEmpty
                ? null
                : _varietyCtrl.text.trim(),
            'size_cm': double.tryParse(_sizeCtrl.text.trim()),
            'breeder': _breederCtrl.text.trim().isEmpty
                ? null
                : _breederCtrl.text.trim(),
            'has_certificate': _hasCertificate,
          }
        else
          'fish_details': null,
      };

      String productId;
      if (widget.productId == null) {
        // Insert first (without images) so we get a generated id to
        // namespace uploaded files under.
        payload['image_urls'] = <String>[];
        productId = await repo.createProduct(payload);
      } else {
        productId = widget.productId!;
      }

      // Upload any newly picked images, then merge with existing URLs.
      if (_newImages.isNotEmpty) {
        final urls = <String>[..._existingImageUrls];
        for (final img in _newImages) {
          final bytes = await img.readAsBytes();
          final ext = img.name.split('.').last;
          final url = await repo.uploadProductImage(productId, bytes, ext);
          urls.add(url);
        }
        payload['image_urls'] = urls;
        await repo.updateProduct(productId, payload);
      } else if (widget.productId != null) {
        payload['image_urls'] = _existingImageUrls;
        await repo.updateProduct(productId, payload);
      }

      // Variants only ever apply to restockable goods; skip entirely for
      // live fish even if stale rows somehow exist. Failures here (e.g.
      // migration 0008 not applied yet) shouldn't block the product save
      // that already succeeded above — but the admin still needs to know,
      // otherwise a product can silently end up with no weight/size
      // variants and no signal that anything went wrong.
      var variantSaveFailed = false;
      if (supportsVariants) {
        try {
          await _saveVariants(productId, repo);
        } catch (_) {
          variantSaveFailed = true;
        }
      }

      refreshAdminProducts(ref);
      if (mounted) {
        if (variantSaveFailed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Product saved, but weight/size variants failed to save — please edit and try again.',
              ),
              backgroundColor: AppColors.error,
              duration: Duration(seconds: 4),
            ),
          );
          await Future.delayed(const Duration(milliseconds: 1200));
        }
        if (mounted) context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete() async {
    if (widget.productId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text(
          'This permanently removes "${_nameCtrl.text.trim().isEmpty ? 'this product' : _nameCtrl.text.trim()}". This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ProductRepository().deleteProduct(widget.productId!);
    refreshAdminProducts(ref);
    if (mounted) context.pop();
  }

  void _removeExistingImage(int index) {
    setState(() => _existingImageUrls.removeAt(index));
  }

  void _removeNewImage(int index) {
    setState(() => _newImages.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    if (_initialLoad) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.productId == null ? 'New Product' : 'Edit Product'),
        actions: [
          if (widget.productId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            const _SectionLabel('PHOTOS'),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (var i = 0; i < _existingImageUrls.length; i++)
                  _EditableThumbnail(
                    onRemove: () => _removeExistingImage(i),
                    child: Image.network(
                      _existingImageUrls[i],
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                    ),
                  ),
                for (var i = 0; i < _newImages.length; i++)
                  _EditableThumbnail(
                    onRemove: () => _removeNewImage(i),
                    child: Image.file(
                      File(_newImages[i].path),
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                    ),
                  ),
                InkWell(
                  onTap: _pickImages,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.offWhite,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: AppColors.lightGrey),
                    ),
                    child: const Icon(
                      Icons.add_a_photo_outlined,
                      color: AppColors.grey,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap a photo\'s × to remove it. First photo is the cover image.',
              style: TextStyle(fontSize: 11.5, color: AppColors.grey),
            ),
            const SizedBox(height: AppSpacing.xl),
            const _SectionLabel('BASIC INFO'),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<ProductCategory>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final c in ProductCategory.values)
                  DropdownMenuItem(value: c, child: Text(categoryLabel(c))),
              ],
              onChanged: (v) =>
                  setState(() => _category = v ?? ProductCategory.koi),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 3,
            ),
            const SizedBox(height: AppSpacing.xl),
            const _SectionLabel('PRICING & STOCK'),
            const SizedBox(height: AppSpacing.sm),
            if (supportsVariants && _variants.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.offWhite,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Text(
                  'This product has variants below — their price & stock are used '
                  'instead of the fields here. The price/stock below are ignored '
                  'once at least one variant exists.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.grey,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            Opacity(
              opacity: supportsVariants && _variants.isNotEmpty ? 0.45 : 1,
              child: IgnorePointer(
                ignoring: supportsVariants && _variants.isNotEmpty,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _priceCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Price (SGD)',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      controller: _salePriceCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Sale price (SGD, optional)',
                        hintText: 'Leave blank for no discount',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show price to customers'),
                      subtitle: const Text('Off = "Contact for price"'),
                      value: _showPrice,
                      onChanged: (v) => setState(() => _showPrice = v),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (isLiveFish)
                      // A live fish is one animal, not a countable
                      // quantity — a plain 0/1 switch is the one-tap
                      // action a farm admin needs at a show or after an
                      // in-person sale, instead of typing a number into a
                      // generic stock field. Bound to the same
                      // `stock_quantity` column the checkout/DB triggers
                      // already read (see 0010_payment_integrity.sql) —
                      // no schema change needed.
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Available for sale in app'),
                        subtitle: Text(
                          _stockCtrl.text.trim() == '0'
                              ? 'Off — shows as "Sold" to customers'
                              : 'On — customers can buy this fish',
                        ),
                        value: _stockCtrl.text.trim() != '0',
                        onChanged: (v) =>
                            setState(() => _stockCtrl.text = v ? '1' : '0'),
                      )
                    else
                      TextFormField(
                        controller: _stockCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Stock quantity',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _videoUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'Video URL (optional)',
                hintText: 'YouTube link, or a direct .mp4 URL',
              ),
              keyboardType: TextInputType.url,
            ),
            if (supportsVariants) ...[
              const SizedBox(height: AppSpacing.xl),
              _SectionLabel(isLiveFish ? 'FISH OPTIONS' : 'WEIGHT VARIANTS'),
              const SizedBox(height: AppSpacing.sm),
              Text(
                isLiveFish
                    ? 'For a batch photo (e.g. "Japan Imported Koi Selection") — list each '
                        'fish/variety separately so shoppers can pick which one. Leave empty '
                        'for a single fish with no picks.'
                    : (_usesSizeStockMatrix
                        ? 'Add weight options (e.g. 2kg, 5kg) with price. Stock is set in the size matrix below.'
                        : 'Add weight options (e.g. 2kg, 5kg) each with their own price & stock.'),
                style: const TextStyle(fontSize: 11.5, color: AppColors.grey),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (var i = 0; i < _variants.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _VariantEditRow(
                    row: _variants[i],
                    hideStock: _usesSizeStockMatrix,
                    labelHint: isLiveFish ? 'e.g. Kohaku' : 'e.g. 1kg',
                    onLabelChanged: (_) => setState(() {}),
                    onRemove: () => _removeVariantRow(i),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _addVariantRow,
                icon: const Icon(Icons.add, size: 18),
                label: Text(isLiveFish ? 'Add Fish Option' : 'Add Weight'),
              ),
            ],
            if (supportsSizeMatrix) ...[
              const SizedBox(height: AppSpacing.xl),
              const _SectionLabel('SIZE OPTIONS'),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Pellet/size labels (e.g. Small, Medium, Large). Price stays on weight; '
                'each weight×size cell has its own stock.',
                style: TextStyle(fontSize: 11.5, color: AppColors.grey),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (var i = 0; i < _sizeOptionCtrls.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _SizeOptionEditRow(
                    controller: _sizeOptionCtrls[i],
                    onRemove: () => _removeSizeOptionRow(i),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _addSizeOptionRow,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Size'),
              ),
              if (_usesSizeStockMatrix &&
                  _variants.any((v) => v.labelCtrl.text.trim().isNotEmpty)) ...[
                const SizedBox(height: AppSpacing.xl),
                const _SectionLabel('STOCK BY WEIGHT × SIZE'),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'Enter how many bags you have for each combination, or fill all at once.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.grey),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _fillAllStockCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Fill all',
                          hintText: 'e.g. 10',
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    ElevatedButton(
                      onPressed: _fillAllSizeStocks,
                      child: const Text('Apply'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                _SizeStockMatrix(
                  variantLabels: [
                    for (final v in _variants)
                      if (v.labelCtrl.text.trim().isNotEmpty)
                        v.labelCtrl.text.trim(),
                  ],
                  variantIndexes: [
                    for (var i = 0; i < _variants.length; i++)
                      if (_variants[i].labelCtrl.text.trim().isNotEmpty) i,
                  ],
                  sizes: _collectedSizeOptions(),
                  controllerFor: _sizeStockCtrl,
                ),
              ],
            ],
            if (isLiveFish) ...[
              const SizedBox(height: AppSpacing.xl),
              const _SectionLabel('FISH DETAILS'),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _varietyCtrl,
                decoration: const InputDecoration(
                  labelText: 'Variety (e.g. Kohaku)',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _sizeCtrl,
                decoration: const InputDecoration(labelText: 'Size (cm)'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _breederCtrl,
                decoration: const InputDecoration(labelText: 'Breeder / Farm'),
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Has certificate'),
                value: _hasCertificate,
                onChanged: (v) => setState(() => _hasCertificate = v),
              ),
            ],
            const SizedBox(height: AppSpacing.xxl),
            ElevatedButton(
              onPressed: _loading ? null : _save,
              child: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  : const Text('Save'),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

/// Small "SECTION LABEL" caption, matching the grey letter-spaced headers
/// used on the product detail / order detail screens — groups this long
/// form into scannable chunks instead of one undifferentiated field list.
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 12,
        letterSpacing: 0.8,
        color: AppColors.grey,
      ),
    );
  }
}

/// Image thumbnail with a small remove ("×") badge — the picker previously
/// had no way to drop a photo short of deleting the whole product.
class _EditableThumbnail extends StatelessWidget {
  final Widget child;
  final VoidCallback onRemove;
  const _EditableThumbnail({required this.child, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: child,
        ),
        Positioned(
          right: -6,
          top: -6,
          child: Material(
            color: AppColors.black,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 14, color: AppColors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Editable state for one variant row in the form. Holds its own
/// [TextEditingController]s so field state survives rebuilds; [id] is
/// null for a row the admin just added (not yet saved to Supabase).
class _VariantRow {
  final String? id;
  final TextEditingController labelCtrl;
  final TextEditingController priceCtrl;
  final TextEditingController stockCtrl;

  _VariantRow._({
    this.id,
    required this.labelCtrl,
    required this.priceCtrl,
    required this.stockCtrl,
  });

  factory _VariantRow.blank() => _VariantRow._(
    labelCtrl: TextEditingController(),
    priceCtrl: TextEditingController(),
    stockCtrl: TextEditingController(text: '0'),
  );

  factory _VariantRow.existing(ProductVariant v) => _VariantRow._(
    id: v.id,
    labelCtrl: TextEditingController(text: v.label),
    priceCtrl: TextEditingController(text: v.price.toString()),
    stockCtrl: TextEditingController(text: '${v.stockQuantity}'),
  );
}

/// One row in the VARIANTS section — label / price / stock fields plus a
/// remove button, matching the compact card style used elsewhere in this
/// form.
class _VariantEditRow extends StatelessWidget {
  final _VariantRow row;
  final VoidCallback onRemove;
  final bool hideStock;
  final String labelHint;
  final ValueChanged<String>? onLabelChanged;
  const _VariantEditRow({
    required this.row,
    required this.onRemove,
    this.hideStock = false,
    this.labelHint = 'e.g. 1kg',
    this.onLabelChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: row.labelCtrl,
              onChanged: onLabelChanged,
              decoration: InputDecoration(
                labelText: 'Label',
                hintText: labelHint,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: row.priceCtrl,
              decoration: const InputDecoration(
                labelText: 'Price',
                isDense: true,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
          ),
          if (!hideStock) ...[
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: row.stockCtrl,
                decoration: const InputDecoration(
                  labelText: 'Stock',
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: AppColors.grey),
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

/// Single label row for the SIZE OPTIONS section.
class _SizeOptionEditRow extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onRemove;
  final ValueChanged<String>? onChanged;
  const _SizeOptionEditRow({
    required this.controller,
    required this.onRemove,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: controller,
              onChanged: onChanged,
              decoration: const InputDecoration(
                labelText: 'Size',
                hintText: 'e.g. Small',
                isDense: true,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: AppColors.grey),
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

/// Compact editable grid: one row per weight, one column per size.
class _SizeStockMatrix extends StatelessWidget {
  final List<String> variantLabels;
  final List<int> variantIndexes;
  final List<String> sizes;
  final TextEditingController Function(int variantIndex, String size)
      controllerFor;

  const _SizeStockMatrix({
    required this.variantLabels,
    required this.variantIndexes,
    required this.sizes,
    required this.controllerFor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: AppShadows.card,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 72,
                  child: Text(
                    'Weight',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.grey,
                    ),
                  ),
                ),
                for (final size in sizes)
                  SizedBox(
                    width: 72,
                    child: Text(
                      size,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.grey,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            for (var r = 0; r < variantLabels.length; r++) ...[
              Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      variantLabels[r],
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (final size in sizes)
                    SizedBox(
                      width: 72,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: TextFormField(
                          controller: controllerFor(variantIndexes[r], size),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                          ),
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              if (r < variantLabels.length - 1)
                const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }
}
