import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/knowledge.dart';
import '../../knowledge/presentation/knowledge_providers.dart';
import '../../../shared/utils/error_message.dart';

/// One editable stage row (existing photo URL and/or a newly picked image
/// not yet uploaded).
class _StageDraft {
  final TextEditingController labelCtrl;
  final TextEditingController descCtrl;
  String? existingImageUrl;
  XFile? newImage;

  _StageDraft({String? label, String? description, this.existingImageUrl})
    : labelCtrl = TextEditingController(text: label),
      descCtrl = TextEditingController(text: description);

  void dispose() {
    labelCtrl.dispose();
    descCtrl.dispose();
  }
}

Future<void> showVarietyForm(
  BuildContext context,
  WidgetRef ref, {
  Variety? existing,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _VarietyFormSheet(existing: existing),
  );
}

class _VarietyFormSheet extends ConsumerStatefulWidget {
  final Variety? existing;
  const _VarietyFormSheet({this.existing});

  @override
  ConsumerState<_VarietyFormSheet> createState() => _VarietyFormSheetState();
}

class _VarietyFormSheetState extends ConsumerState<_VarietyFormSheet> {
  late final _nameCtrl = TextEditingController(text: widget.existing?.name);
  late final _descCtrl = TextEditingController(
    text: widget.existing?.description,
  );
  late final _traitsCtrl = TextEditingController(
    text: widget.existing?.traits.join(', '),
  );
  late String _category = widget.existing?.category ?? 'koi';

  String? _existingCoverUrl;
  XFile? _newCoverImage;
  final List<_StageDraft> _stages = [];
  bool _saving = false;
  bool _submitted = false;
  String? _saveError;
  late String? _savedId = widget.existing?.id;

  @override
  void initState() {
    super.initState();
    _existingCoverUrl = widget.existing?.imageUrl;
    for (final s in widget.existing?.stages ?? const <VarietyStage>[]) {
      _stages.add(
        _StageDraft(
          label: s.label,
          description: s.description,
          existingImageUrl: s.imageUrl,
        ),
      );
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _traitsCtrl.dispose();
    for (final s in _stages) {
      s.dispose();
    }
    super.dispose();
  }

  Future<void> _pickCoverImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (mounted && picked != null) setState(() => _newCoverImage = picked);
  }

  Future<void> _pickStageImage(_StageDraft stage) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (mounted && picked != null) setState(() => stage.newImage = picked);
  }

  void _addStage() => setState(() => _stages.add(_StageDraft()));

  void _removeStage(int i) => setState(() => _stages.removeAt(i).dispose());

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final coverImage = _newCoverImage;
    final stages = _stages
        .map(
          (stage) => (
            label: stage.labelCtrl.text.trim(),
            description: stage.descCtrl.text.trim(),
            imageUrl: stage.existingImageUrl,
            newImage: stage.newImage,
          ),
        )
        .toList(growable: false);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final repo = ref.read(knowledgeRepositoryProvider);
      final id = await repo.upsertVariety({
        'name': _nameCtrl.text.trim(),
        'category': _category,
        'description': _descCtrl.text.trim(),
        'traits': _traitsCtrl.text
            .split(',')
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList(),
      }, id: _savedId);
      _savedId = id;

      var coverUrl = _existingCoverUrl;
      if (coverImage != null) {
        final bytes = await coverImage.readAsBytes();
        final ext = coverImage.name.split('.').last;
        coverUrl = await repo.uploadVarietyImage(id, bytes, ext);
      }

      final stagePayload = <Map<String, dynamic>>[];
      for (final s in stages) {
        if (s.label.isEmpty) continue;
        var imageUrl = s.imageUrl;
        if (s.newImage != null) {
          final bytes = await s.newImage!.readAsBytes();
          final ext = s.newImage!.name.split('.').last;
          imageUrl = await repo.uploadVarietyImage(id, bytes, ext);
        }
        stagePayload.add({
          'label': s.label,
          'image_url': imageUrl,
          'description': s.description.isEmpty ? null : s.description,
        });
      }

      await repo.upsertVariety({
        'image_url': coverUrl,
        'stages': stagePayload,
      }, id: id);

      container.invalidate(varietiesProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(
          () => _saveError = friendlyErrorMessage(
            e,
            fallback: 'Could not save the variety. Please try again.',
            context: 'admin.variety_form',
          ),
        );
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
            Text(
              widget.existing == null ? 'Add Variety' : 'Edit Variety',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.lg),
            Center(
              child: GestureDetector(
                onTap: _pickCoverImage,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppPalette.of(context).surfaceMuted,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    image: _newCoverImage != null
                        ? null // shown via FutureBuilder below for web/io compat
                        : (_existingCoverUrl != null
                              ? DecorationImage(
                                  image: NetworkImage(_existingCoverUrl!),
                                  fit: BoxFit.cover,
                                )
                              : null),
                  ),
                  child: _newCoverImage != null
                      ? _PickedImageThumb(file: _newCoverImage!)
                      : (_existingCoverUrl == null
                            ? Icon(
                                Icons.add_a_photo_outlined,
                                color: AppPalette.of(context).textMuted,
                              )
                            : null),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: 'Name',
                errorText: _submitted && _nameCtrl.text.trim().isEmpty
                    ? 'Enter a name.'
                    : null,
                errorMaxLines: 3,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _category,
              items: const [
                DropdownMenuItem(value: 'koi', child: Text('Koi')),
                DropdownMenuItem(value: 'arowana', child: Text('Arowana')),
              ],
              onChanged: (v) => setState(() => _category = v ?? 'koi'),
              decoration: const InputDecoration(labelText: 'Category'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 3,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _traitsCtrl,
              decoration: const InputDecoration(
                labelText: 'Traits (comma-separated)',
                hintText: 'e.g. Red & white, Metallic scales',
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(
                  'GROWTH STAGES',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.8,
                    color: AppPalette.of(context).textMuted,
                  ),
                ),
                TextButton.icon(
                  onPressed: _addStage,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add stage'),
                ),
              ],
            ),
            Text(
              'e.g. Tosai (under 1yr) → Nisai (2yr) → Sansai (3yr), one photo each',
              style: TextStyle(
                fontSize: 12,
                color: AppPalette.of(context).textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (var i = 0; i < _stages.length; i++)
              Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  border: Border.all(color: AppPalette.of(context).border),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final photo = GestureDetector(
                      onTap: () => _pickStageImage(_stages[i]),
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppPalette.of(context).surfaceMuted,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          image:
                              _stages[i].newImage == null &&
                                  _stages[i].existingImageUrl != null
                              ? DecorationImage(
                                  image: NetworkImage(
                                    _stages[i].existingImageUrl!,
                                  ),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: _stages[i].newImage != null
                            ? _PickedImageThumb(file: _stages[i].newImage!)
                            : (_stages[i].existingImageUrl == null
                                  ? Icon(
                                      Icons.add_a_photo_outlined,
                                      size: 18,
                                      color: AppPalette.of(context).textMuted,
                                    )
                                  : null),
                      ),
                    );
                    final fields = Column(
                      children: [
                        TextField(
                          controller: _stages[i].labelCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Stage label',
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _stages[i].descCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Note (optional)',
                            isDense: true,
                          ),
                        ),
                      ],
                    );
                    final remove = IconButton(
                      tooltip: 'Remove stage',
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: AppPalette.of(context).textMuted,
                      ),
                      onPressed: () => _removeStage(i),
                    );
                    if (constraints.maxWidth < 360 &&
                        MediaQuery.textScalerOf(context).scale(14) > 21) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: [photo, const Spacer(), remove]),
                          const SizedBox(height: AppSpacing.sm),
                          fields,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        photo,
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: fields),
                        remove,
                      ],
                    );
                  },
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            if (_saveError != null) ...[
              Text(
                _saveError!,
                style: TextStyle(color: AppPalette.of(context).error),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
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
          ],
        ),
      ),
    );
  }
}

/// Renders a freshly picked [XFile] without needing `dart:io` (works on
/// web too) by reading its bytes.
class _PickedImageThumb extends StatelessWidget {
  final XFile file;
  const _PickedImageThumb({required this.file});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: file.readAsBytes(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Image.memory(snapshot.data!, fit: BoxFit.cover),
        );
      },
    );
  }
}
