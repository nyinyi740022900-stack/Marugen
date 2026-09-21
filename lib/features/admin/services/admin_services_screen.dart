import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/service.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../services/presentation/service_providers.dart';

/// "Services" tab inside admin Knowledge — farm services like fish
/// recovery/quarantine or pond-renovation boarding, shown to customers
/// alongside Varieties/Guides.
class AdminServicesTab extends ConsumerWidget {
  const AdminServicesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(servicesProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.red,
        onPressed: () => _showServiceForm(context, ref),
        child: const Icon(Icons.add, color: AppColors.white),
      ),
      body: servicesAsync.when(
        data: (services) => services.isEmpty
            ? const EmptyState(
                icon: Icons.room_service_outlined,
                title: 'No services yet',
                subtitle: 'Tap + to add one.',
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: services.length,
                itemBuilder: (context, i) {
                  final s = services[i];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.offWhite,
                        backgroundImage: s.imageUrls.isNotEmpty
                            ? NetworkImage(s.imageUrls.first)
                            : null,
                        child: s.imageUrls.isEmpty
                            ? const Icon(Icons.room_service_outlined, color: AppColors.grey)
                            : null,
                      ),
                      title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        s.active ? (s.category ?? 'Active') : 'Hidden',
                        style: TextStyle(color: s.active ? AppColors.grey : AppColors.error),
                      ),
                      trailing: IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline, color: AppColors.error),
                        onPressed: () async {
                          final confirmed = await confirmDestructiveAction(
                            context,
                            title: 'Delete service?',
                            message: 'This permanently removes "${s.name}". This cannot be undone.',
                          );
                          if (!confirmed) return;
                          await ref.read(serviceRepositoryProvider).deleteService(s.id);
                          ref.invalidate(servicesProvider);
                        },
                      ),
                      onTap: () => _showServiceForm(context, ref, existing: s),
                    ),
                  );
                },
              ),
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.red),
        ),
        error: (e, _) => ErrorState(onRetry: () => ref.invalidate(servicesProvider)),
      ),
    );
  }

  void _showServiceForm(BuildContext context, WidgetRef ref, {Service? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ServiceFormSheet(existing: existing),
    );
  }
}

class _ServiceFormSheet extends ConsumerStatefulWidget {
  final Service? existing;
  const _ServiceFormSheet({this.existing});

  @override
  ConsumerState<_ServiceFormSheet> createState() => _ServiceFormSheetState();
}

class _ServiceFormSheetState extends ConsumerState<_ServiceFormSheet> {
  late final _nameCtrl = TextEditingController(text: widget.existing?.name);
  late final _descCtrl = TextEditingController(text: widget.existing?.description);
  late final _priceCtrl =
      TextEditingController(text: widget.existing?.price?.toString());
  late final _categoryCtrl = TextEditingController(text: widget.existing?.category);
  late bool _showPrice = widget.existing?.showPrice ?? true;
  late bool _active = widget.existing?.active ?? true;

  final List<String> _existingImageUrls = [];
  final List<XFile> _newImages = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _existingImageUrls.addAll(widget.existing?.imageUrls ?? const []);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _categoryCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picked = await ImagePicker().pickMultiImage(imageQuality: 85);
    setState(() => _newImages.addAll(picked));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final repo = ref.read(serviceRepositoryProvider);
      final payload = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'price': _priceCtrl.text.trim().isEmpty ? null : double.tryParse(_priceCtrl.text.trim()),
        'show_price': _showPrice,
        'category': _categoryCtrl.text.trim().isEmpty ? null : _categoryCtrl.text.trim(),
        'active': _active,
      };

      String id;
      if (widget.existing == null) {
        payload['image_urls'] = <String>[];
        id = await repo.upsertService(payload);
      } else {
        id = widget.existing!.id;
      }

      if (_newImages.isNotEmpty) {
        final urls = <String>[..._existingImageUrls];
        for (final img in _newImages) {
          final bytes = await img.readAsBytes();
          final ext = img.name.split('.').last;
          urls.add(await repo.uploadServiceImage(id, bytes, ext));
        }
        payload['image_urls'] = urls;
        await repo.upsertService(payload, id: id);
      } else if (widget.existing != null) {
        payload['image_urls'] = _existingImageUrls;
        await repo.upsertService(payload, id: id);
      }

      ref.invalidate(servicesProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'Add Service' : 'Edit Service',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Service name',
                  hintText: 'e.g. Fish Recovery & Quarantine'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _categoryCtrl,
              decoration: const InputDecoration(
                  labelText: 'Category (optional)', hintText: 'e.g. Health Care'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 4,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _priceCtrl,
              decoration: const InputDecoration(labelText: 'Price (SGD, optional)'),
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              subtitle: const Text('Off hides this from customers'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text('PHOTOS',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.8,
                    color: AppColors.grey)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final url in _existingImageUrls)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: Image.network(url, width: 72, height: 72, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: -6,
                        right: -6,
                        child: IconButton(
                          icon: const Icon(Icons.cancel, size: 18, color: AppColors.error),
                          onPressed: () => setState(() => _existingImageUrls.remove(url)),
                        ),
                      ),
                    ],
                  ),
                for (final img in _newImages)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: _PickedImageThumb(file: img),
                    ),
                  ),
                GestureDetector(
                  onTap: _pickImages,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.offWhite,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Icon(Icons.add_a_photo_outlined, color: AppColors.grey),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white))
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickedImageThumb extends StatelessWidget {
  final XFile file;
  const _PickedImageThumb({required this.file});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: file.readAsBytes(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        return Image.memory(snapshot.data!, fit: BoxFit.cover);
      },
    );
  }
}
