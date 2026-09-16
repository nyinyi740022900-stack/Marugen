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
  ConsumerState<AdminProductEditScreen> createState() => _AdminProductEditScreenState();
}

class _AdminProductEditScreenState extends ConsumerState<AdminProductEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
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

  // Variants (size/weight options) — only shown for restockable goods
  // (fish_food/accessories). Existing rows carry their variant id so
  // _save() knows to update rather than insert; ids removed from this
  // list between load and save get deleted.
  final List<_VariantRow> _variants = [];
  final Set<String> _deletedVariantIds = {};

  bool get isLiveFish =>
      _category == ProductCategory.koi || _category == ProductCategory.arowana;

  /// Restockable goods (fish_food/accessories) — the only categories that
  /// ever get a variant picker. Never koi/arowana: each fish is one
  /// specific animal, not a set of size/weight options.
  bool get supportsVariants => !isLiveFish;

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
    final product = await ProductRepository().fetchProductById(widget.productId!);
    if (product != null) {
      _nameCtrl.text = product.name;
      _descCtrl.text = product.description ?? '';
      _priceCtrl.text = product.price?.toString() ?? '';
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
      for (final v in product.variants) {
        _variants.add(_VariantRow.existing(v));
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
    setState(() => _variants.removeAt(index));
  }

  Future<void> _saveVariants(String productId, ProductRepository repo) async {
    for (final id in _deletedVariantIds) {
      await repo.deleteVariant(id);
    }
    for (var i = 0; i < _variants.length; i++) {
      final row = _variants[i];
      final label = row.labelCtrl.text.trim();
      if (label.isEmpty) continue; // skip incomplete rows silently
      final payload = {
        'product_id': productId,
        'label': label,
        'price': double.tryParse(row.priceCtrl.text.trim()) ?? 0,
        'stock_quantity': int.tryParse(row.stockCtrl.text.trim()) ?? 0,
        'sort_order': i,
      };
      if (row.id == null) {
        await repo.createVariant(payload);
      } else {
        await repo.updateVariant(row.id!, payload);
      }
    }
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
      final categoryValue =
          _category == ProductCategory.fishFood ? 'fish_food' : _category.name;

      final payload = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'category': categoryValue,
        'price': _priceCtrl.text.trim().isEmpty ? null : double.tryParse(_priceCtrl.text.trim()),
        'video_url': _videoUrlCtrl.text.trim().isEmpty ? null : _videoUrlCtrl.text.trim(),
        'show_price': _showPrice,
        'stock_quantity': int.tryParse(_stockCtrl.text.trim()) ?? 0,
        if (isLiveFish)
          'fish_details': {
            'variety': _varietyCtrl.text.trim().isEmpty ? null : _varietyCtrl.text.trim(),
            'size_cm': double.tryParse(_sizeCtrl.text.trim()),
            'breeder': _breederCtrl.text.trim().isEmpty ? null : _breederCtrl.text.trim(),
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
      // that already succeeded above.
      if (supportsVariants) {
        try {
          await _saveVariants(productId, repo);
        } catch (_) {
          // Non-fatal — product itself saved fine.
        }
      }

      ref.invalidate(productListProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
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
            'This permanently removes "${_nameCtrl.text.trim().isEmpty ? 'this product' : _nameCtrl.text.trim()}". This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ProductRepository().deleteProduct(widget.productId!);
    ref.invalidate(productListProvider);
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
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
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
                    child: Image.network(_existingImageUrls[i],
                        width: 80, height: 80, fit: BoxFit.cover),
                  ),
                for (var i = 0; i < _newImages.length; i++)
                  _EditableThumbnail(
                    onRemove: () => _removeNewImage(i),
                    child: Image.file(File(_newImages[i].path),
                        width: 80, height: 80, fit: BoxFit.cover),
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
                    child: const Icon(Icons.add_a_photo_outlined, color: AppColors.grey),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text('Tap a photo\'s × to remove it. First photo is the cover image.',
                style: TextStyle(fontSize: 11.5, color: AppColors.greySoft)),
            const SizedBox(height: AppSpacing.xl),
            const _SectionLabel('BASIC INFO'),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<ProductCategory>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final c in ProductCategory.values)
                  DropdownMenuItem(value: c, child: Text(categoryLabel(c))),
              ],
              onChanged: (v) => setState(() => _category = v ?? ProductCategory.koi),
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
                  style: TextStyle(fontSize: 12, color: AppColors.grey, height: 1.4),
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
                      decoration: const InputDecoration(labelText: 'Price (SGD)'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                    TextFormField(
                      controller: _stockCtrl,
                      decoration: InputDecoration(
                        labelText:
                            isLiveFish ? 'Stock (0 or 1 — unique fish)' : 'Stock quantity',
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
                hintText: 'https://example.com/video.mp4',
              ),
              keyboardType: TextInputType.url,
            ),
            if (supportsVariants) ...[
              const SizedBox(height: AppSpacing.xl),
              const _SectionLabel('VARIANTS'),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Add size/weight options (e.g. 500g, 1kg) each with their own price & stock.',
                style: TextStyle(fontSize: 11.5, color: AppColors.greySoft),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (var i = 0; i < _variants.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _VariantEditRow(
                    row: _variants[i],
                    onRemove: () => _removeVariantRow(i),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _addVariantRow,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Variant'),
              ),
            ],
            if (isLiveFish) ...[
              const SizedBox(height: AppSpacing.xl),
              const _SectionLabel('FISH DETAILS'),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _varietyCtrl,
                decoration: const InputDecoration(labelText: 'Variety (e.g. Kohaku)'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _sizeCtrl,
                decoration: const InputDecoration(labelText: 'Size (cm)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white))
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
    return Text(text,
        style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 0.8,
            color: AppColors.grey));
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

  _VariantRow._({this.id, required this.labelCtrl, required this.priceCtrl, required this.stockCtrl});

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
  const _VariantEditRow({required this.row, required this.onRemove});

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
              decoration: const InputDecoration(labelText: 'Label', hintText: 'e.g. 1kg', isDense: true),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: row.priceCtrl,
              decoration: const InputDecoration(labelText: 'Price', isDense: true),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: row.stockCtrl,
              decoration: const InputDecoration(labelText: 'Stock', isDense: true),
              keyboardType: TextInputType.number,
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
