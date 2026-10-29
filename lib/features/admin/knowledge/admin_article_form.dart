import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/knowledge.dart';
import '../../knowledge/presentation/knowledge_providers.dart';
import '../../../shared/utils/error_message.dart';

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
  late final _bodyCtrl = TextEditingController(
    text: widget.existing?.bodyMarkdown,
  );
  String? _existingCoverUrl;
  XFile? _newCoverImage;
  bool _saving = false;
  bool _submitted = false;
  String? _saveError;
  late String? _savedId = widget.existing?.id;

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
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (mounted && picked != null) setState(() => _newCoverImage = picked);
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (_titleCtrl.text.trim().isEmpty || _bodyCtrl.text.trim().isEmpty) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final coverImage = _newCoverImage;
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final repo = ref.read(knowledgeRepositoryProvider);
      final payload = <String, dynamic>{
        'title': _titleCtrl.text.trim(),
        'body_markdown': _bodyCtrl.text.trim(),
      };
      // Only stamp published_at on first publish — editing shouldn't bump
      // it back to the top of the "newest first" guide list.
      if (_savedId == null) {
        payload['published_at'] = DateTime.now().toIso8601String();
      }
      final id = await repo.upsertArticle(payload, id: _savedId);
      _savedId = id;

      if (coverImage != null) {
        final bytes = await coverImage.readAsBytes();
        final ext = coverImage.name.split('.').last;
        final url = await repo.uploadArticleImage(id, bytes, ext);
        await repo.upsertArticle({'cover_image_url': url}, id: id);
      }

      container.invalidate(articlesProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(
          () => _saveError = friendlyErrorMessage(
            e,
            fallback: 'Could not save the article. Please try again.',
            context: 'admin.article_form',
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
              widget.existing == null ? 'Add Guide' : 'Edit Guide',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.lg),
            GestureDetector(
              onTap: _pickCoverImage,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Container(
                  height: 140,
                  width: double.infinity,
                  color: AppPalette.of(context).surfaceMuted,
                  child: _newCoverImage != null
                      ? _PickedImageThumb(file: _newCoverImage!)
                      : (_existingCoverUrl != null
                            ? Image.network(
                                _existingCoverUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Icon(
                                  Icons.broken_image_outlined,
                                  color: AppPalette.of(context).textMuted,
                                ),
                              )
                            : Icon(
                                Icons.add_a_photo_outlined,
                                color: AppPalette.of(context).textMuted,
                              )),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                labelText: 'Title',
                errorText: _submitted && _titleCtrl.text.trim().isEmpty
                    ? 'Enter a title.'
                    : null,
                errorMaxLines: 3,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _bodyCtrl,
              decoration: InputDecoration(
                labelText: 'Content',
                errorText: _submitted && _bodyCtrl.text.trim().isEmpty
                    ? 'Enter guide content.'
                    : null,
                errorMaxLines: 3,
              ),
              maxLines: 8,
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
