import '../../../shared/widgets/sized_network_image.dart'
    show SizedNetworkImage, uploadImageMaxSide;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/product.dart';
import '../../shop/data/product_repository.dart';
import '../../shop/presentation/shop_providers.dart';
import '../../../shared/utils/error_message.dart';
import '../../../shared/utils/image_upload.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/discard_changes_guard.dart';
import '../../../shared/widgets/section_label.dart';

/// Create/edit form for a product. Pass `productId == null` to create new.
class AdminProductEditScreen extends ConsumerStatefulWidget {
  final String? productId;

  /// Replaces the gallery picker for the certificate photo in tests.
  @visibleForTesting
  final Future<XFile?> Function()? certificatePicker;

  const AdminProductEditScreen({
    super.key,
    this.productId,
    this.certificatePicker,
  });

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
  final _shippingWeightCtrl = TextEditingController();
  final _packedSize = _PackedSizeControllers();
  final _salePriceCtrl = TextEditingController();
  final _videoUrlCtrl = TextEditingController();
  final _stockCtrl = TextEditingController(text: '1');
  final _varietyCtrl = TextEditingController();
  final _sizeCtrl = TextEditingController();
  final _breederCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();

  ProductCategory _category = ProductCategory.koi;
  bool _showPrice = true;
  bool _hasCertificate = false;

  /// The certificate photo: already uploaded, or a local file that uploads
  /// on Save like the product photos. Null when there is none.
  _Photo? _certificate;

  /// The fish details as loaded, so saving keeps what this form has no
  /// field for (keys written by a newer version of the app).
  FishDetails? _loadedFish;

  /// Stored gender text. The form offers Unknown / Male / Female; any
  /// other stored wording is kept until staff pick one of those.
  String? _gender;

  /// Photos in display order (first = cover). Each is either already
  /// uploaded (`url`) or still a local file; uploads happen on Save, one
  /// by one, and a failure marks just that photo so it can be retried.
  final List<_Photo> _photos = [];
  String? _uploadNote;
  bool _loading = false;
  bool _initialLoad = true;
  bool _productMissing = false;
  String? _loadError;
  String? _createdProductId;

  // Variants (weight options) — only shown for restockable goods
  // (fish_food/accessories). Existing rows carry their variant id so
  // _save() knows to update rather than insert; ids removed from this
  // list between load and save get deleted.
  final List<_VariantRow> _variants = [];
  final Set<String> _deletedVariantIds = {};

  // Product-level size labels (e.g. pellet Small/Medium/Large) — independent
  // of weight price; stock is entered in the weight×size matrix below.
  final List<_SizeRow> _sizeRows = [];

  /// Matrix cells keyed by the identity of their weight row and size row
  /// (see [_cellKey]), never by position or label text: duplicating,
  /// removing or reordering a row, or renaming a size, must not move a
  /// quantity to another cell or reset it.
  final Map<String, TextEditingController> _sizeStockCtrls = {};
  final _fillAllStockCtrl = TextEditingController();

  /// What the form held when it finished loading (or opened blank), for
  /// the unsaved-changes guard; refreshed after a successful save.
  String? _baseline;

  String _fingerprint() => [
    _nameCtrl.text,
    _descCtrl.text,
    _priceCtrl.text,
    _shippingWeightCtrl.text,
    _packedSize.length.text,
    _packedSize.width.text,
    _packedSize.height.text,
    _salePriceCtrl.text,
    _videoUrlCtrl.text,
    _stockCtrl.text,
    _varietyCtrl.text,
    _sizeCtrl.text,
    _breederCtrl.text,
    _ageCtrl.text,
    _category.name,
    _showPrice,
    _gender ?? '',
    _hasCertificate,
    _certificate == null ? '' : _certificate!.url ?? _certificate!.file!.path,
    _photos.map((ph) => ph.url ?? ph.file!.path).join(','),
    for (final v in _variants) ...[
      v.id,
      v.labelCtrl.text,
      v.priceCtrl.text,
      v.stockCtrl.text,
      v.weightCtrl.text,
      v.packedSize.length.text,
      v.packedSize.width.text,
      v.packedSize.height.text,
    ],
    _sizeRows.map((r) => r.ctrl.text).join(','),
    // By position, so a row added and then removed again is not a change.
    for (var v = 0; v < _variants.length; v++)
      for (var z = 0; z < _sizeRows.length; z++)
        '$v:$z=${_sizeStockCtrls[_cellKey(_variants[v], _sizeRows[z])]?.text ?? '0'}',
  ].join('\u0001');

  bool get _dirty => _baseline != null && _fingerprint() != _baseline;

  /// What the unsaved-changes guard was last built with. Typing in a field
  /// does not rebuild this screen, so the form asks for a rebuild when the
  /// answer flips; otherwise a text-only edit could be backed out of
  /// without the "Discard changes?" question.
  bool _guardDirty = false;

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
    setState(() {
      _initialLoad = true;
      _loadError = null;
      _productMissing = false;
    });
    try {
      await _fetchExisting();
    } catch (error) {
      if (!mounted) return;
      _loadError = friendlyErrorMessage(
        error,
        fallback: 'Could not load this product. Please try again.',
        context: 'admin.product_edit.load',
      );
    } finally {
      if (mounted) {
        setState(() {
          _initialLoad = false;
          _baseline = _fingerprint();
        });
      }
    }
  }

  Future<void> _fetchExisting() async {
    if (widget.productId == null) return;
    final product = await ProductRepository().fetchProductById(
      widget.productId!,
    );
    if (!mounted) return;
    _productMissing = product == null;
    if (product != null) {
      _nameCtrl.text = product.name;
      _descCtrl.text = product.description ?? '';
      _priceCtrl.text = product.price?.toString() ?? '';
      _shippingWeightCtrl.text = product.shippingWeightKg?.toString() ?? '';
      _packedSize.load(product.packedDimensions);
      _salePriceCtrl.text = product.salePrice?.toString() ?? '';
      _videoUrlCtrl.text = product.videoUrl ?? '';
      _stockCtrl.text = '${product.stockQuantity}';
      _category = product.category;
      _showPrice = product.showPrice;
      _photos.addAll(product.imageUrls.map(_Photo.uploaded));
      if (product.fishDetails != null) {
        _varietyCtrl.text = product.fishDetails!.variety ?? '';
        _sizeCtrl.text = product.fishDetails!.sizeCm?.toString() ?? '';
        _breederCtrl.text = product.fishDetails!.breeder ?? '';
        _hasCertificate = product.fishDetails!.hasCertificate;
        _ageCtrl.text = product.fishDetails!.age ?? '';
        _gender = product.fishDetails!.gender;
        final certificateUrl = product.fishDetails!.certificateImageUrl;
        _certificate = certificateUrl == null
            ? null
            : _Photo.uploaded(certificateUrl);
        _loadedFish = product.fishDetails;
      }
      for (final size in product.sizeOptions) {
        _sizeRows.add(_SizeRow(size));
      }
      for (final v in product.variants) {
        final row = _VariantRow.existing(v);
        _variants.add(row);
        for (final size in _sizeRows) {
          _sizeStockCtrls[_cellKey(row, size)] = TextEditingController(
            text: '${v.sizeStocks[size.label] ?? 0}',
          );
        }
      }
    }
  }

  /// Brings the first field with an error into view; on a long form the
  /// red text is otherwise somewhere above or below the Save button.
  void _scrollToFirstError() {
    FormFieldState<dynamic>? first;
    void visit(Element element) {
      if (first != null) return;
      if (element is StatefulElement &&
          element.state is FormFieldState<dynamic> &&
          (element.state as FormFieldState<dynamic>).hasError) {
        first = element.state as FormFieldState<dynamic>;
        return;
      }
      element.visitChildren(visit);
    }

    _formKey.currentContext?.visitChildElements(visit);
    final target = first;
    if (target != null) {
      Scrollable.ensureVisible(
        target.context,
        alignment: 0.2,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(content: Text('Check the highlighted fields.')),
      );
  }

  static bool _isFish(ProductCategory c) =>
      c == ProductCategory.koi || c == ProductCategory.arowana;

  /// Switching between live fish and goods throws away the other kind's
  /// details on save (fish fields vs weight options), so say so first
  /// when there is anything to lose.
  Future<void> _changeCategory(ProductCategory next) async {
    if (next == _category) return;
    final crossing = _isFish(next) != _isFish(_category);
    final hasFishData =
        _varietyCtrl.text.trim().isNotEmpty ||
        _sizeCtrl.text.trim().isNotEmpty ||
        _breederCtrl.text.trim().isNotEmpty ||
        _ageCtrl.text.trim().isNotEmpty ||
        _certificate != null;
    final hasGoodsData =
        _variants.any((v) => v.labelCtrl.text.trim().isNotEmpty) ||
        _sizeRows.any((r) => r.label.isNotEmpty);
    if (crossing && (hasFishData || hasGoodsData)) {
      final ok = await confirmAction(
        context,
        title: 'Change product type?',
        message: _isFish(next)
            ? 'Weight options and size stock are not used for live fish and will be removed when you save.'
            : 'Variety, size and breeder details are not used for goods and will be removed when you save.',
        confirmLabel: 'Change',
      );
      if (!ok || !mounted) {
        // Put the dropdown back to the current value.
        setState(() {});
        return;
      }
    }
    setState(() => _category = next);
  }

  void _addVariantRow() {
    setState(() => _variants.add(_VariantRow.blank()));
  }

  /// One tap per common bag size instead of Add → type kg → fix label.
  void _addWeightChip(double kg) {
    final label = _optionLabelFromKg(kg.toString());
    if (_variants.any((v) => v.labelCtrl.text.trim() == label)) return;
    final row = _VariantRow.blank();
    row.weightCtrl.text = kg % 1 == 0 ? kg.toInt().toString() : kg.toString();
    row.updateWeightLabel(row.weightCtrl.text);
    // Carry the last row's price as a starting point; it is usually close.
    if (_variants.isNotEmpty) {
      row.priceCtrl.text = _variants.last.priceCtrl.text;
    }
    setState(() => _variants.add(row));
  }

  /// Copies a weight row (price, kg, packed size) as a new unsaved row,
  /// so a second similar size is one tap plus a label edit. Its weight ×
  /// size cells start at 0 (stock that does not exist yet must be typed),
  /// and every other row keeps its own cells.
  void _duplicateVariantRow(int index) {
    final src = _variants[index];
    final row = _VariantRow.blank();
    row.priceCtrl.text = src.priceCtrl.text;
    row.weightCtrl.text = src.weightCtrl.text;
    row.stockCtrl.text = src.stockCtrl.text;
    row.packedSize.length.text = src.packedSize.length.text;
    row.packedSize.width.text = src.packedSize.width.text;
    row.packedSize.height.text = src.packedSize.height.text;
    setState(() => _variants.insert(index + 1, row));
  }

  void _removeVariantRow(int index) {
    final row = _variants[index];
    if (row.id != null) _deletedVariantIds.add(row.id!);
    _sizeStockCtrls.removeWhere((key, ctrl) {
      if (!key.startsWith('${row.uid}::')) return false;
      ctrl.dispose();
      return true;
    });
    setState(() => _variants.removeAt(index));
  }

  void _addSizeOptionRow() {
    setState(() => _sizeRows.add(_SizeRow('')));
  }

  /// Removing a size deletes its stock for every weight on save, so a size
  /// that holds stock asks first.
  Future<void> _removeSizeOptionRow(_SizeRow size) async {
    final hasStock = _variants.any(
      (v) =>
          (int.tryParse(
                _sizeStockCtrls[_cellKey(v, size)]?.text.trim() ?? '',
              ) ??
              0) >
          0,
    );
    if (hasStock) {
      final ok = await confirmDestructiveAction(
        context,
        title: 'Remove size "${size.label}"?',
        message: 'Its stock for every weight will be deleted when you save.',
        confirmLabel: 'Remove',
      );
      if (!ok || !mounted) return;
    }
    if (!_sizeRows.remove(size)) return;
    _sizeStockCtrls.removeWhere((key, ctrl) {
      if (!key.endsWith('::${size.uid}')) return false;
      ctrl.dispose();
      return true;
    });
    size.ctrl.dispose();
    setState(() {});
  }

  /// The size rows that count: named, and the first of any repeated name.
  List<_SizeRow> _activeSizeRows() {
    final seen = <String>{};
    return [
      for (final row in _sizeRows)
        if (row.label.isNotEmpty && seen.add(row.label)) row,
    ];
  }

  List<String> _collectedSizeOptions() => [
    for (final row in _activeSizeRows()) row.label,
  ];

  static String _cellKey(_VariantRow variant, _SizeRow size) =>
      '${variant.uid}::${size.uid}';

  TextEditingController _sizeStockCtrl(_VariantRow variant, _SizeRow size) {
    return _sizeStockCtrls.putIfAbsent(
      _cellKey(variant, size),
      () => TextEditingController(text: '0'),
    );
  }

  /// Sets every weight×size cell to the Fill all value (empty → 0).
  void _fillAllSizeStocks() {
    final qty = int.tryParse(_fillAllStockCtrl.text.trim()) ?? 0;
    final clamped = qty < 0 ? 0 : qty;
    final sizes = _activeSizeRows();
    for (final variant in _variants) {
      if (variant.labelCtrl.text.trim().isEmpty) continue;
      for (final size in sizes) {
        _sizeStockCtrl(variant, size).text = '$clamped';
      }
    }
    setState(() {});
  }

  Future<void> _saveVariants(String productId, ProductRepository repo) async {
    for (final id in List<String>.of(_deletedVariantIds)) {
      if (!mounted) return;
      await repo.deleteVariant(id);
    }
    if (!mounted) return;
    // Live fish have no size matrix, even if stale size rows linger.
    final sizes = supportsSizeMatrix ? _activeSizeRows() : const <_SizeRow>[];
    final useMatrix = sizes.isNotEmpty;

    for (var i = 0; i < _variants.length; i++) {
      if (!mounted) return;
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
        'packed_dimensions': isLiveFish ? null : row.packedSize.value?.toMap(),
        'shipping_weight_kg': isLiveFish
            ? null
            : double.tryParse(row.weightCtrl.text.trim()),
      };
      final String variantId;
      if (row.id == null) {
        variantId = (await repo.createVariant(payload)).id;
      } else {
        await repo.updateVariant(row.id!, payload);
        variantId = row.id!;
      }
      if (!mounted) return;
      if (useMatrix) {
        for (final size in sizes) {
          if (!mounted) return;
          final qty = int.tryParse(_sizeStockCtrl(row, size).text.trim()) ?? 0;
          await repo.upsertVariantSizeStock(
            variantId: variantId,
            sizeLabel: size.label,
            stockQuantity: qty,
          );
        }
      }
    }
    if (!mounted) return;
    await repo.deleteOrphanSizeStocks(
      productId: productId,
      keepSizes: [for (final size in sizes) size.label],
    );
  }

  Future<void> _pickImages() async {
    if (_loading) return;
    final picked = await ImagePicker().pickMultiImage(
      imageQuality: 85,
      maxWidth: uploadImageMaxSide,
      maxHeight: uploadImageMaxSide,
    );
    if (mounted && !_loading) {
      setState(() => _photos.addAll(picked.map(_Photo.local)));
    }
  }

  Future<void> _pickCertificate() async {
    if (_loading) return;
    final picked =
        await (widget.certificatePicker ??
            () => ImagePicker().pickImage(
              source: ImageSource.gallery,
              imageQuality: 85,
              maxWidth: uploadImageMaxSide,
              maxHeight: uploadImageMaxSide,
            ))();
    if (picked != null && mounted && !_loading) {
      setState(() => _certificate = _Photo.local(picked));
    }
  }

  /// Retry a failed certificate upload right away when the product already
  /// exists; the link itself is written by the next Save.
  Future<void> _retryCertificate() async {
    final photo = _certificate;
    if (photo == null) return;
    final productId = widget.productId ?? _createdProductId;
    if (productId == null || _loading) {
      setState(() => photo.status = _PhotoStatus.ready);
      return;
    }
    await _uploadPhoto(ProductRepository(), productId, photo);
  }

  /// `fish_details` as it should be stored: the form's fields over whatever
  /// was loaded, so keys this form does not edit survive a save. The
  /// certificate photo goes with the certificate: switching "Has
  /// certificate" off, or removing the photo, drops its key.
  Map<String, dynamic> _fishDetailsPayload() {
    String? text(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    return FishDetails(
      variety: text(_varietyCtrl),
      sizeCm: double.tryParse(_sizeCtrl.text.trim()),
      gender: _gender,
      breeder: text(_breederCtrl),
      hasCertificate: _hasCertificate,
      age: text(_ageCtrl),
      certificateImageUrl: _hasCertificate ? _certificate?.url : null,
      unknownKeys: _loadedFish?.unknownKeys ?? const {},
    ).toMap();
  }

  Future<void> _save() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) {
      _scrollToFirstError();
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _loading = true);
    final pending = _photos.where((ph) => ph.url == null).toList();
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
        'packed_dimensions': isLiveFish ? null : _packedSize.value?.toMap(),
        'shipping_weight_kg': isLiveFish
            ? null
            : double.tryParse(_shippingWeightCtrl.text.trim()),
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
        'size_options': supportsSizeMatrix
            ? _collectedSizeOptions()
            : <String>[],
        'fish_details': isLiveFish ? _fishDetailsPayload() : null,
      };

      String productId;
      final creating = widget.productId == null && _createdProductId == null;
      if (creating) {
        // Insert first (without images) so we get a generated id to
        // namespace uploaded files under.
        payload['image_urls'] = <String>[];
        productId = await repo.createProduct(payload);
        _createdProductId = productId;
      } else {
        productId = widget.productId ?? _createdProductId!;
      }

      if (!mounted) return;
      // Upload new photos one at a time with visible progress. A failed
      // photo is marked for retry instead of aborting the whole save, so
      // the ones that worked are never thrown away.
      var failedPhotos = 0;
      for (var i = 0; i < pending.length; i++) {
        if (!mounted) return;
        setState(
          () => _uploadNote = 'Uploading photo ${i + 1} of ${pending.length}…',
        );
        if (!await _uploadPhoto(repo, productId, pending[i])) failedPhotos++;
      }
      // The certificate photo uploads the same way, and its link is
      // written with the fish details below.
      final certificate = _certificate;
      final uploadCertificate =
          isLiveFish &&
          _hasCertificate &&
          certificate != null &&
          certificate.url == null;
      var certificateFailed = false;
      if (uploadCertificate) {
        if (!mounted) return;
        setState(() => _uploadNote = 'Uploading certificate photo…');
        certificateFailed = !await _uploadPhoto(repo, productId, certificate);
      }
      if (!mounted) return;
      setState(() => _uploadNote = null);
      payload['image_urls'] = _photos
          .map((ph) => ph.url)
          .whereType<String>()
          .toList();
      if (isLiveFish) payload['fish_details'] = _fishDetailsPayload();
      if (pending.isNotEmpty || uploadCertificate || !creating) {
        await repo.updateProduct(productId, payload);
      }
      if (failedPhotos > 0 || certificateFailed) {
        if (!mounted) return;
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                failedPhotos == 0
                    ? "The certificate photo didn't upload. Tap it to retry, then Save."
                    : certificateFailed
                    ? "Some photos, including the certificate photo, didn't upload. Tap each to retry, then Save."
                    : failedPhotos == 1
                    ? "1 photo didn't upload. Tap it to retry, then Save."
                    : "$failedPhotos photos didn't upload. Tap each to retry, then Save.",
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        return;
      }

      if (!mounted) return;
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

      if (!mounted) return;
      refreshAdminProducts(ref);
      if (mounted) {
        if (variantSaveFailed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyErrorMessage(
                e,
                fallback: 'Could not save the product. Please try again.',
                context: 'admin.product_edit',
              ),
            ),
          ),
        );
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
            child: Text(
              'Delete',
              style: TextStyle(color: AppPalette.of(context).error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ProductRepository().deleteProduct(widget.productId!);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      // 23503: order_items still reference this product (it has been
      // ordered). Previously this failed silently with no feedback.
      final message = e.code == '23503'
          ? 'This product has orders, so it can\'t be deleted. Turn off '
                '"Available for sale in app" to stop selling it.'
          : friendlyErrorMessage(
              e,
              fallback: 'Could not delete the product. Please try again.',
              context: 'admin.product_edit',
            );
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              e,
              fallback: 'Could not delete the product. Please try again.',
              context: 'admin.product_edit',
            ),
          ),
        ),
      );
      return;
    }
    refreshAdminProducts(ref);
    if (mounted) context.pop();
  }

  void _removePhoto(_Photo photo) => setState(() => _photos.remove(photo));

  void _makeCover(_Photo photo) => setState(() {
    _photos.remove(photo);
    _photos.insert(0, photo);
  });

  void _reorderPhotos(int from, int to) => setState(() {
    final photo = _photos.removeAt(from);
    _photos.insert(to, photo);
  });

  /// Uploads one local photo; returns false (and marks it) on failure.
  Future<bool> _uploadPhoto(
    ProductRepository repo,
    String productId,
    _Photo photo,
  ) async {
    setState(() => photo.status = _PhotoStatus.uploading);
    try {
      final bytes = await photo.file!.readAsBytes();
      final url = await repo.uploadProductImage(
        productId,
        bytes,
        photo.file!.name.split('.').last,
      );
      if (!mounted) return false;
      setState(() {
        photo.url = url;
        photo.status = _PhotoStatus.ready;
      });
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => photo.status = _PhotoStatus.failed);
        // Retrying will not help a file the bucket refuses: say why.
        final message = friendlyErrorMessage(
          e,
          fallback: '',
          context: 'admin.product_photo',
        );
        if (message == imageUploadRejectedMessage) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(SnackBar(content: Text(message)));
        }
      }
      return false;
    }
  }

  /// Retry a single failed photo right away when the product already
  /// exists; otherwise it simply joins the next Save.
  Future<void> _retryPhoto(_Photo photo) async {
    final productId = widget.productId ?? _createdProductId;
    if (productId == null || _loading) {
      setState(() => photo.status = _PhotoStatus.ready);
      return;
    }
    final ok = await _uploadPhoto(ProductRepository(), productId, photo);
    if (ok && mounted) {
      try {
        await ProductRepository().updateProduct(productId, {
          'image_urls': _photos
              .map((ph) => ph.url)
              .whereType<String>()
              .toList(),
        });
      } catch (_) {
        // The next Save writes the list again.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initialLoad) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null || _productMissing) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Product')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _productMissing ? 'Product not found' : _loadError!,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton(
                  onPressed: _loadExisting,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    // A blank form has no load step; take its baseline on first build.
    _baseline ??= _fingerprint();
    _guardDirty = _dirty;
    return DiscardChangesGuard(
      dirty: _guardDirty,
      busy: _loading,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.productId == null ? 'New Product' : 'Edit Product',
          ),
          actions: [
            if (widget.productId != null)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete product',
                onPressed: _loading ? null : _delete,
              ),
          ],
        ),
        // Save is pinned under the form, so it stays in reach however far
        // down the change was. As the bottom bar (not part of the body)
        // snackbars appear above it; the padding lifts it over the keyboard.
        bottomNavigationBar: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: _SaveBar(
            dirty: _guardDirty,
            saving: _loading,
            note: _uploadNote,
            onSave: _save,
          ),
        ),
        body: AbsorbPointer(
          absorbing: _loading,
          child: Form(
            key: _formKey,
            onChanged: () {
              if (_dirty != _guardDirty) setState(() {});
            },
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                const _SectionLabel('PHOTOS'),
                const SizedBox(height: AppSpacing.sm),
                _PhotoStrip(
                  photos: _photos,
                  enabled: !_loading,
                  onAdd: _pickImages,
                  onRemove: _removePhoto,
                  onMakeCover: _makeCover,
                  onRetry: _retryPhoto,
                  onReorder: _reorderPhotos,
                ),
                const SizedBox(height: 4),
                Text(
                  'First photo is the cover. Hold and drag to reorder, or tap a photo for Make cover / Remove.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppPalette.of(context).textMuted,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                const _SectionLabel('BASIC INFO'),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    helperText: 'Required',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<ProductCategory>(
                  key: ValueKey('category-${_category.name}'),
                  isExpanded: true,
                  itemHeight: math.max(
                    kMinInteractiveDimension,
                    32 + MediaQuery.textScalerOf(context).scale(16),
                  ),
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    for (final c in ProductCategory.values)
                      DropdownMenuItem(value: c, child: Text(categoryLabel(c))),
                  ],
                  onChanged: (v) => _changeCategory(v ?? ProductCategory.koi),
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
                      color: AppPalette.of(context).surfaceMuted,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      'This product has options below. Each option has its '
                      'own price and stock; sale price is not available for '
                      'products with options yet.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppPalette.of(context).textMuted,
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
                        if (!isLiveFish) ...[
                          TextFormField(
                            controller: _shippingWeightCtrl,
                            decoration: const InputDecoration(
                              labelText: 'kg',
                              helperText:
                                  'Weight of one item. Example: 500g = 0.5 kg.',
                              helperMaxLines: 10,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            validator: _validateShippingWeight,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          _PackedSizeFields(
                            controllers: _packedSize,
                            enabled: _variants.isEmpty,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                        TextFormField(
                          controller: _priceCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Price (SGD)',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: _moneyInput,
                          // Variant prices replace this one once any exist.
                          validator: (v) =>
                              supportsVariants && _variants.isNotEmpty
                              ? null
                              : _validatePrice(v, required: _showPrice),
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
                          inputFormatters: _moneyInput,
                          validator: (v) {
                            if (supportsVariants && _variants.isNotEmpty) {
                              return null;
                            }
                            final error = _validatePrice(v, required: false);
                            if (error != null || v!.trim().isEmpty) {
                              return error;
                            }
                            final price = double.tryParse(
                              _priceCtrl.text.trim(),
                            );
                            return price != null &&
                                    double.parse(v.trim()) >= price
                                ? 'Sale price must be lower than the price'
                                : null;
                          },
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
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                // Outside the block above: it applies to products with
                // options too, so it must stay usable when that is disabled.
                const SizedBox(height: AppSpacing.sm),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show price to customers'),
                  subtitle: const Text('Off = "Contact for price"'),
                  value: _showPrice,
                  onChanged: (v) => setState(() => _showPrice = v),
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
                  _SectionLabel(
                    isLiveFish ? 'FISH OPTIONS' : 'WEIGHT VARIANTS',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    isLiveFish
                        ? 'For a batch photo (e.g. "Japan Imported Koi Selection") — list each '
                              'fish/variety separately so shoppers can pick which one. Leave empty '
                              'for a single fish with no picks.'
                        : (_usesSizeStockMatrix
                              ? 'Add weight options (e.g. 2kg, 5kg) with price. Stock is set in the size matrix below.'
                              : 'Add weight options (e.g. 2kg, 5kg) each with their own price & stock.'),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppPalette.of(context).textMuted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (var i = 0; i < _variants.length; i++)
                    Padding(
                      key: ValueKey('variant-row-${_variants[i].uid}'),
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _VariantEditRow(
                        showShippingWeight: !isLiveFish,
                        row: _variants[i],
                        hideStock: _usesSizeStockMatrix,
                        labelHint: isLiveFish ? 'e.g. Kohaku' : 'e.g. 1kg',
                        onLabelChanged: (_) => setState(() {}),
                        onRemove: () => _removeVariantRow(i),
                        onDuplicate: isLiveFish
                            ? null
                            : () => _duplicateVariantRow(i),
                      ),
                    ),
                  if (!isLiveFish) ...[
                    // The bag sizes this shop actually stocks.
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        // Only the sizes not listed yet.
                        for (final kg in const [0.5, 1.0, 2.0, 5.0, 10.0, 15.0])
                          if (!_variants.any(
                            (v) =>
                                v.labelCtrl.text.trim() ==
                                _optionLabelFromKg(kg.toString()),
                          ))
                            ActionChip(
                              avatar: const Icon(Icons.add, size: 16),
                              label: Text(
                                _optionLabelFromKg(kg.toString()) ?? '',
                              ),
                              onPressed: () => _addWeightChip(kg),
                            ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  OutlinedButton.icon(
                    onPressed: _addVariantRow,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(
                      isLiveFish ? 'Add Fish Option' : 'Add custom option',
                    ),
                  ),
                ],
                if (supportsSizeMatrix) ...[
                  const SizedBox(height: AppSpacing.xl),
                  const _SectionLabel('SIZE OPTIONS'),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Pellet/size labels (e.g. Small, Medium, Large). Price stays on weight; '
                    'each weight×size cell has its own stock.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppPalette.of(context).textMuted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final size in _sizeRows)
                    Padding(
                      key: ValueKey('size-row-${size.uid}'),
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _SizeOptionEditRow(
                        controller: size.ctrl,
                        onRemove: () => _removeSizeOptionRow(size),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _addSizeOptionRow,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Size'),
                  ),
                  if (_usesSizeStockMatrix &&
                      _variants.any(
                        (v) => v.labelCtrl.text.trim().isNotEmpty,
                      )) ...[
                    const SizedBox(height: AppSpacing.xl),
                    const _SectionLabel('STOCK BY WEIGHT × SIZE'),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Enter how many bags you have for each combination, or fill all at once.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppPalette.of(context).textMuted,
                      ),
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
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
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
                      variants: [
                        for (final v in _variants)
                          if (v.labelCtrl.text.trim().isNotEmpty) v,
                      ],
                      sizes: _activeSizeRows(),
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
                    validator: _validateSizeCm,
                  ),
                  // Gender, like age, describes one animal.
                  if (_variants.isEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    _GenderField(
                      value: _gender,
                      onChanged: (v) => setState(() => _gender = v),
                    ),
                  ],
                  // Age and the certificate photo describe one animal, so
                  // a batch listing (fish options) does not offer them.
                  if (_variants.isEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _ageCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Age',
                        hintText: 'e.g. 2 years, Tosai',
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(
                          FishDetails.maxAgeLength,
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _breederCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Breeder / Farm',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Has certificate'),
                    value: _hasCertificate,
                    onChanged: (v) => setState(() => _hasCertificate = v),
                  ),
                  if (_hasCertificate && _variants.isEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _CertificatePhotoField(
                      photo: _certificate,
                      enabled: !_loading,
                      onPick: _pickCertificate,
                      onRemove: () => setState(() => _certificate = null),
                      onRetry: _retryCertificate,
                    ),
                  ],
                  if (_variants.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Gender, age and a certificate photo describe one fish, '
                      'so they are not used for a listing with fish options.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppPalette.of(context).textMuted,
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
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
    return SectionLabel(text);
  }
}

/// Image thumbnail with a small remove ("×") badge — the picker previously
/// had no way to drop a photo short of deleting the whole product.
enum _PhotoStatus { ready, uploading, failed }

class _Photo {
  String? url;
  final XFile? file;
  _PhotoStatus status = _PhotoStatus.ready;
  _Photo.uploaded(String this.url) : file = null;
  _Photo.local(XFile this.file) : url = null;
}

/// The certificate photo under "Has certificate": an add tile, or the photo
/// with the same upload states and actions as a product photo.
class _CertificatePhotoField extends StatelessWidget {
  final _Photo? photo;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  final VoidCallback onRetry;
  const _CertificatePhotoField({
    required this.photo,
    required this.enabled,
    required this.onPick,
    required this.onRemove,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final photo = this.photo;
    final caption = photo == null
        ? 'Optional. Customers can open it from the product page.'
        : photo.status == _PhotoStatus.failed
        ? "Didn't upload. Tap the photo to retry."
        : photo.status == _PhotoStatus.uploading
        ? 'Uploading…'
        : photo.url == null
        ? 'Uploads when you save.'
        : 'Customers can open it from the product page.';
    return Row(
      children: [
        if (photo == null)
          Semantics(
            button: true,
            label: 'Add certificate photo',
            child: InkWell(
              onTap: enabled ? onPick : null,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Container(
                width: _PhotoStrip._tile,
                height: _PhotoStrip._tile,
                decoration: BoxDecoration(
                  color: palette.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: palette.border),
                ),
                child: Icon(
                  Icons.add_a_photo_outlined,
                  color: palette.textMuted,
                ),
              ),
            ),
          )
        else
          _PhotoTile(
            photo: photo,
            label: 'Certificate photo',
            isCover: false,
            enabled: enabled,
            onRemove: onRemove,
            onMakeCover: null,
            onRetry: onRetry,
          ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Certificate photo',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                caption,
                style: TextStyle(
                  fontSize: 12,
                  color: photo?.status == _PhotoStatus.failed
                      ? palette.error
                      : palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Horizontal, reorderable photo strip: cover badge on the first tile,
/// upload state per tile, long-press to drag, tap for actions.
class _PhotoStrip extends StatelessWidget {
  final List<_Photo> photos;
  final bool enabled;
  final VoidCallback onAdd;
  final ValueChanged<_Photo> onRemove;
  final ValueChanged<_Photo> onMakeCover;
  final ValueChanged<_Photo> onRetry;
  final void Function(int from, int to) onReorder;
  const _PhotoStrip({
    required this.photos,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
    required this.onMakeCover,
    required this.onRetry,
    required this.onReorder,
  });

  static const _tile = 88.0;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SizedBox(
      height: _tile + 8,
      child: Row(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.symmetric(vertical: 4),
              proxyDecorator: (child, _, _) => Material(
                color: Colors.transparent,
                elevation: 6,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: child,
              ),
              itemCount: photos.length,
              onReorderItem: enabled ? onReorder : (_, _) {},
              itemBuilder: (context, i) {
                final photo = photos[i];
                return Padding(
                  key: ValueKey(photo),
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: ReorderableDelayedDragStartListener(
                    index: i,
                    enabled: enabled,
                    child: _PhotoTile(
                      photo: photo,
                      isCover: i == 0,
                      enabled: enabled,
                      onRemove: () => onRemove(photo),
                      onMakeCover: i == 0 ? null : () => onMakeCover(photo),
                      onRetry: () => onRetry(photo),
                    ),
                  ),
                );
              },
            ),
          ),
          Semantics(
            button: true,
            label: 'Add photos',
            child: InkWell(
              onTap: enabled ? onAdd : null,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Container(
                width: _tile,
                height: _tile,
                decoration: BoxDecoration(
                  color: palette.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: palette.border),
                ),
                child: Icon(
                  Icons.add_a_photo_outlined,
                  color: palette.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final _Photo photo;

  /// What a screen reader calls it; "Cover photo" / "Photo" when null.
  final String? label;
  final bool isCover;
  final bool enabled;
  final VoidCallback onRemove;
  final VoidCallback? onMakeCover;
  final VoidCallback onRetry;
  const _PhotoTile({
    required this.photo,
    this.label,
    required this.isCover,
    required this.enabled,
    required this.onRemove,
    required this.onMakeCover,
    required this.onRetry,
  });

  Future<void> _showActions(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (photo.status == _PhotoStatus.failed)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Retry upload'),
                onTap: () => Navigator.pop(ctx, 'retry'),
              ),
            if (onMakeCover != null)
              ListTile(
                leading: const Icon(Icons.star_outline),
                title: const Text('Make cover photo'),
                onTap: () => Navigator.pop(ctx, 'cover'),
              ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: AppPalette.of(ctx).error,
              ),
              title: Text(
                'Remove photo',
                style: TextStyle(color: AppPalette.of(ctx).error),
              ),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'retry':
        onRetry();
      case 'cover':
        onMakeCover?.call();
      case 'remove':
        onRemove();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final Widget image = photo.url != null
        ? SizedNetworkImage(
            imageUrl: photo.url!,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => ColoredBox(
              color: palette.surfaceMuted,
              child: const Icon(Icons.broken_image_outlined),
            ),
          )
        : Image.file(File(photo.file!.path), fit: BoxFit.cover);
    final status = photo.status;
    return Semantics(
      button: true,
      label:
          '${label ?? (isCover ? 'Cover photo' : 'Photo')}'
          '${status == _PhotoStatus.failed ? ', upload failed' : ''}'
          '${status == _PhotoStatus.uploading ? ', uploading' : ''}',
      child: InkWell(
        onTap: enabled ? () => _showActions(context) : null,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: SizedBox(
          width: _PhotoStrip._tile,
          height: _PhotoStrip._tile,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Stack(
              fit: StackFit.expand,
              children: [
                image,
                if (isCover)
                  Positioned(
                    left: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: const Text(
                        'Cover',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                if (status == _PhotoStatus.uploading)
                  const ColoredBox(
                    color: Color(0x80000000),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.white,
                        ),
                      ),
                    ),
                  ),
                if (status == _PhotoStatus.failed)
                  ColoredBox(
                    color: AppColors.error.withValues(alpha: 0.78),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh, color: AppColors.white),
                          SizedBox(height: 2),
                          Text(
                            'Retry',
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (photo.url == null && status == _PhotoStatus.ready)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: const Text(
                        'New',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.black,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Editable state for one variant row in the form. Holds its own
/// [TextEditingController]s so field state survives rebuilds; [id] is
/// null for a row the admin just added (not yet saved to Supabase).
class _VariantRow {
  static int _nextUid = 0;

  /// Identity of this row for as long as the form is open; matrix cells
  /// are keyed by it so they follow the row wherever it moves.
  final int uid = _nextUid++;
  final String? id;
  final TextEditingController labelCtrl;
  final TextEditingController priceCtrl;
  final TextEditingController stockCtrl;
  final TextEditingController weightCtrl;
  final packedSize = _PackedSizeControllers();
  String? _generatedLabel;

  _VariantRow._({
    this.id,
    required this.labelCtrl,
    required this.priceCtrl,
    required this.stockCtrl,
    required this.weightCtrl,
  }) : _generatedLabel = _optionLabelFromKg(weightCtrl.text);

  void updateWeightLabel(String value) {
    final next = _optionLabelFromKg(value);
    // Keep a custom name such as 500ml, 2L or Small when weight changes.
    if (labelCtrl.text.trim().isEmpty || labelCtrl.text == _generatedLabel) {
      labelCtrl.text = next ?? '';
    }
    _generatedLabel = next;
  }

  factory _VariantRow.blank() => _VariantRow._(
    labelCtrl: TextEditingController(),
    priceCtrl: TextEditingController(),
    stockCtrl: TextEditingController(text: '0'),
    weightCtrl: TextEditingController(),
  );

  factory _VariantRow.existing(ProductVariant v) => (_VariantRow._(
    id: v.id,
    labelCtrl: TextEditingController(text: v.label),
    priceCtrl: TextEditingController(text: v.price.toString()),
    stockCtrl: TextEditingController(text: '${v.stockQuantity}'),
    weightCtrl: TextEditingController(
      text: v.shippingWeightKg?.toString() ?? '',
    ),
  )..packedSize.load(v.packedDimensions));
}

/// One row in the VARIANTS section — label / price / stock fields plus a
/// remove button, matching the compact card style used elsewhere in this
/// form.
class _VariantEditRow extends StatelessWidget {
  final _VariantRow row;
  final VoidCallback onRemove;
  final VoidCallback? onDuplicate;
  final bool hideStock;
  final bool showShippingWeight;
  final String labelHint;
  final ValueChanged<String>? onLabelChanged;
  const _VariantEditRow({
    required this.row,
    required this.onRemove,
    this.onDuplicate,
    this.hideStock = false,
    this.showShippingWeight = false,
    this.labelHint = 'e.g. 1kg',
    this.onLabelChanged,
  });

  @override
  Widget build(BuildContext context) {
    final label = TextFormField(
      controller: row.labelCtrl,
      onChanged: onLabelChanged,
      decoration: InputDecoration(
        labelText: 'Label',
        hintText: labelHint,
        helperText: showShippingWeight
            ? 'Auto from kg; edit only if needed.'
            : null,
        helperMaxLines: 5,
        isDense: true,
      ),
    );
    final price = TextFormField(
      controller: row.priceCtrl,
      decoration: const InputDecoration(labelText: 'Price', isDense: true),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: _moneyInput,
      // Rows without a label are skipped on save.
      validator: (v) =>
          row.labelCtrl.text.trim().isEmpty ? null : _validatePrice(v),
    );
    final weight = TextFormField(
      controller: row.weightCtrl,
      onChanged: (value) {
        row.updateWeightLabel(value);
        onLabelChanged?.call(row.labelCtrl.text);
      },
      decoration: const InputDecoration(labelText: 'kg', isDense: true),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: _validateShippingWeight,
    );
    final stock = TextFormField(
      controller: row.stockCtrl,
      decoration: const InputDecoration(labelText: 'Stock', isDense: true),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    );
    final remove = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onDuplicate != null)
          IconButton(
            tooltip: 'Duplicate option',
            icon: Icon(
              Icons.copy_outlined,
              size: 18,
              color: AppPalette.of(context).textMuted,
            ),
            onPressed: onDuplicate,
          ),
        IconButton(
          tooltip: 'Remove option',
          icon: Icon(
            Icons.close,
            size: 18,
            color: AppPalette.of(context).textMuted,
          ),
          onPressed: onRemove,
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppPalette.of(context).surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 520 ||
                  MediaQuery.textScalerOf(context).scale(14) / 14 > 1.3) {
                return Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: label),
                        remove,
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (showShippingWeight &&
                        (constraints.maxWidth < 340 ||
                            MediaQuery.textScalerOf(context).scale(14) > 18))
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          price,
                          const SizedBox(height: AppSpacing.sm),
                          weight,
                          if (!hideStock) ...[
                            const SizedBox(height: AppSpacing.sm),
                            stock,
                          ],
                        ],
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: price),
                          if (showShippingWeight) ...[
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(child: weight),
                          ],
                          if (!hideStock) ...[
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(child: stock),
                          ],
                        ],
                      ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: label),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(flex: 2, child: price),
                  if (showShippingWeight) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(flex: 2, child: weight),
                  ],
                  if (!hideStock) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(flex: 2, child: stock),
                  ],
                  remove,
                ],
              );
            },
          ),
          if (showShippingWeight)
            // Nobody fills packed dimensions per bag on a normal restock;
            // the shop-level default in Settings covers it. Keep the
            // fields one tap away for the odd oversized item.
            // Its own Material: the row card is a plain decorated box, so
            // the tile's ink would otherwise be painted underneath it.
            Material(
              type: MaterialType.transparency,
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  initiallyExpanded: row.packedSize.value != null,
                  title: Text(
                    'Advanced: packed size',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppPalette.of(context).textMuted,
                    ),
                  ),
                  children: [_PackedSizeFields(controllers: row.packedSize)],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One size label in the form, with an identity that survives renaming.
class _SizeRow {
  static int _nextUid = 0;
  final int uid = _nextUid++;
  final TextEditingController ctrl;
  _SizeRow(String label) : ctrl = TextEditingController(text: label);
  String get label => ctrl.text.trim();
}

/// "Gender" for a single fish: Unknown (nothing stored), Male or Female.
class _GenderField extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _GenderField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final current = value?.trim().toLowerCase();
    final selected = current == 'male'
        ? 'Male'
        : current == 'female'
        ? 'Female'
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Gender',
          style: TextStyle(
            fontSize: 12.5,
            color: AppPalette.of(context).textMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            for (final option in const [null, 'Male', 'Female'])
              ChoiceChip(
                label: Text(option ?? 'Unknown'),
                selected: selected == option,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (_) => onChanged(option),
              ),
          ],
        ),
      ],
    );
  }
}

/// Save, pinned under the form. Enabled once something has changed; while
/// saving it shows the same progress text the upload loop reports.
class _SaveBar extends StatelessWidget {
  final bool dirty;
  final bool saving;
  final String? note;
  final VoidCallback onSave;
  const _SaveBar({
    required this.dirty,
    required this.saving,
    required this.note,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: palette.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.sm,
            AppSpacing.xl,
            AppSpacing.sm,
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: saving || !dirty ? null : onSave,
              child: saving
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.white,
                          ),
                        ),
                        if (note != null) ...[
                          const SizedBox(width: 10),
                          Flexible(child: Text(note!)),
                        ],
                      ],
                    )
                  : const Text('Save'),
            ),
          ),
        ),
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
        color: AppPalette.of(context).surface,
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
          // The glyph stays small; the button around it is a full 48pt
          // target with a name for screen readers.
          IconButton(
            tooltip: 'Remove size',
            icon: Icon(
              Icons.close,
              size: 18,
              color: AppPalette.of(context).textMuted,
            ),
            onPressed: onRemove,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
        ],
      ),
    );
  }
}

/// Compact editable grid: one row per weight, one column per size.
class _SizeStockMatrix extends StatelessWidget {
  final List<_VariantRow> variants;
  final List<_SizeRow> sizes;
  final TextEditingController Function(_VariantRow variant, _SizeRow size)
  controllerFor;

  const _SizeStockMatrix({
    required this.variants,
    required this.sizes,
    required this.controllerFor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppPalette.of(context).surface,
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
                SizedBox(
                  width: 72,
                  child: Text(
                    'Weight',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.of(context).textMuted,
                    ),
                  ),
                ),
                for (final size in sizes)
                  SizedBox(
                    width: 72,
                    child: Text(
                      size.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.of(context).textMuted,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final variant in variants) ...[
              Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      variant.labelCtrl.text.trim(),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (final size in sizes)
                    SizedBox(
                      // The field keeps its state with its cell, not with
                      // its position in the grid.
                      key: ValueKey('cell-${variant.uid}-${size.uid}'),
                      width: 72,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Semantics(
                          label:
                              'Stock for ${variant.labelCtrl.text.trim()}, '
                              '${size.label}',
                          child: TextFormField(
                            controller: controllerFor(variant, size),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (variant != variants.last)
                const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }
}

final _moneyInput = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
final _money = RegExp(r'^\d+(\.\d{1,2})?$');

/// A mistyped variant price used to save as S$0.00 and a mistyped product
/// price as "Contact for price"; migration 0072 refuses both server-side.
String? _validatePrice(String? value, {bool required = true}) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return required ? 'Enter a price' : null;
  if (!_money.hasMatch(text)) return 'Enter an amount like 12.50';
  return double.parse(text) > 0 ? null : 'Price must be more than 0';
}

String? _validateSizeCm(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  final cm = double.tryParse(text);
  return cm == null || !cm.isFinite || cm <= 0
      ? 'Enter the length in cm, e.g. 45'
      : null;
}

String? _validateShippingWeight(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final weight = double.tryParse(value.trim());
  return weight == null || !weight.isFinite || weight <= 0
      ? 'Enter a positive weight in kg.'
      : null;
}

String? _optionLabelFromKg(String input) {
  final kg = double.tryParse(input.trim());
  if (kg == null || !kg.isFinite || kg <= 0) return null;
  final value = kg < 1 ? kg * 1000 : kg;
  final number = value.toStringAsFixed(6).replaceFirst(RegExp(r'\.?0+$'), '');
  return '$number${kg < 1 ? 'g' : 'kg'}';
}

/// Packed dimensions of one individually wrapped unit, not the bare product.
class _PackedSizeControllers {
  final length = TextEditingController();
  final width = TextEditingController();
  final height = TextEditingController();
  List<TextEditingController> get fields => [length, width, height];
  void load(PackedDimensions? value) {
    length.text = value?.lengthCm.toString() ?? '';
    width.text = value?.widthCm.toString() ?? '';
    height.text = value?.heightCm.toString() ?? '';
  }

  PackedDimensions? get value => PackedDimensions.fromMap({
    'length_cm': double.tryParse(length.text.trim()),
    'width_cm': double.tryParse(width.text.trim()),
    'height_cm': double.tryParse(height.text.trim()),
  });
  String? validate(String? text) {
    if (fields.every((field) => field.text.trim().isEmpty)) return null;
    final number = double.tryParse(text?.trim() ?? '');
    return number == null || !number.isFinite || number <= 0
        ? 'Enter a positive size.'
        : null;
  }
}

class _PackedSizeFields extends StatelessWidget {
  final _PackedSizeControllers controllers;
  final bool enabled;
  const _PackedSizeFields({required this.controllers, this.enabled = true});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Packed size (optional)',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      const Text(
        'One packed unit, including its box. Enter all three sizes or leave blank.',
      ),
      const SizedBox(height: AppSpacing.sm),
      LayoutBuilder(
        builder: (context, constraints) {
          final vertical =
              constraints.maxWidth < 340 ||
              MediaQuery.textScalerOf(context).scale(14) > 18;
          final fields = [
            for (final entry in {
              'Length (cm)': controllers.length,
              'Width (cm)': controllers.width,
              'Height (cm)': controllers.height,
            }.entries)
              TextFormField(
                controller: entry.value,
                decoration: InputDecoration(
                  labelText: entry.key,
                  isDense: true,
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                enabled: enabled,
                validator: enabled ? controllers.validate : null,
              ),
          ];
          return vertical
              ? Column(
                  children: [
                    for (final field in fields)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: field,
                      ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < fields.length; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.sm),
                      Expanded(child: fields[i]),
                    ],
                  ],
                );
        },
      ),
    ],
  );
}
