import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/knowledge.dart';
import '../../knowledge/presentation/knowledge_providers.dart';

Future<void> showArticleForm(
  BuildContext context,
  WidgetRef ref, {
  KnowledgeArticle? existing,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ArticleFormSheet(existing: existing),
  );
}

class _ArticleFormSheet extends ConsumerStatefulWidget {
  final KnowledgeArticle? existing;
  const _ArticleFormSheet({this.existing});

  @override
  ConsumerState<_ArticleFormSheet> createState() => _ArticleFormSheetState();
}

class _ArticleFormSheetState extends ConsumerState<_ArticleFormSheet> {
  late final _titleCtrl = TextEditingController(text: widget.existing?.title);
  late final _bodyCtrl = TextEditingController(text: widget.existing?.bodyMarkdown);
  String? _existingCoverUrl;
  XFile? _newCoverImage;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _existingCoverUrl = widget.existing?.coverImageUrl;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCoverImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) setState(() => _newCoverImage = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final repo = ref.read(knowledgeRepositoryProvider);
      final payload = <String, dynamic>{
        'title': _titleCtrl.text.trim(),
        'body_markdown': _bodyCtrl.text.trim(),
      };
      // Only stamp published_at on first publish — editing shouldn't bump
      // it back to the top of the "newest first" guide list.
      if (widget.existing == null) {
        payload['published_at'] = DateTime.now().toIso8601String();
      }
      final id = await repo.upsertArticle(payload, id: widget.existing?.id);

      if (_newCoverImage != null) {
        final bytes = await _newCoverImage!.readAsBytes();
        final ext = _newCoverImage!.name.split('.').last;
        final url = await repo.uploadArticleImage(id, bytes, ext);
        await repo.upsertArticle({'cover_image_url': url}, id: id);
      }

      ref.invalidate(articlesProvider);
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
            Text(widget.existing == null ? 'Add Guide' : 'Edit Guide',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.lg),
            GestureDetector(
              onTap: _pickCoverImage,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Container(
                  height: 140,
                  width: double.infinity,
                  color: AppColors.offWhite,
                  child: _newCoverImage != null
                      ? _PickedImageThumb(file: _newCoverImage!)
                      : (_existingCoverUrl != null
                          ? Image.network(_existingCoverUrl!, fit: BoxFit.cover)
                          : const Icon(Icons.add_a_photo_outlined, color: AppColors.grey)),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
                controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _bodyCtrl,
              decoration: const InputDecoration(labelText: 'Content'),
              maxLines: 8,
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white))
                  : const Text('Publish'),
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
