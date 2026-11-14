import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/home_banner.dart';
import '../../../shared/utils/error_message.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/sized_network_image.dart'
    show SizedNetworkImage, uploadImageMaxSide;
import '../../../shared/widgets/skeleton.dart';
import '../../banners/presentation/hero_banner_carousel.dart';
import '../../banners/presentation/home_banner_providers.dart';

/// Admin › More › Home Banners: the slides of the Shop tab's hero carousel.
/// Drag to reorder, switch to show/hide, tap to edit, + to add.
class AdminBannersScreen extends ConsumerWidget {
  const AdminBannersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bannersAsync = ref.watch(adminHomeBannersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Home Banners')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add banner',
        backgroundColor: AppColors.red,
        onPressed: () => _openForm(context),
        child: const Icon(Icons.add, color: AppColors.white),
      ),
      body: bannersAsync.when(
        data: (banners) => banners.isEmpty
            ? const EmptyState(
                icon: Icons.view_carousel_outlined,
                title: 'No banners yet',
                subtitle:
                    'Tap + to add a slide. Customers see live slides at the '
                    'top of the Shop tab.',
              )
            : _BannerList(banners: banners),
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            ListRowSkeleton(),
            SizedBox(height: 12),
            ListRowSkeleton(),
          ],
        ),
        error: (_, _) =>
            ErrorState(onRetry: () => ref.invalidate(adminHomeBannersProvider)),
      ),
    );
  }

  static void _openForm(BuildContext context, {HomeBanner? existing}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => BannerFormScreen(existing: existing),
      ),
    );
  }
}

class _BannerList extends ConsumerStatefulWidget {
  final List<HomeBanner> banners;
  const _BannerList({required this.banners});

  @override
  ConsumerState<_BannerList> createState() => _BannerListState();
}

class _BannerListState extends ConsumerState<_BannerList> {
  late List<HomeBanner> _order = List.of(widget.banners);
  final _busy = <String>{};

  @override
  void didUpdateWidget(_BannerList old) {
    super.didUpdateWidget(old);
    if (old.banners != widget.banners) _order = List.of(widget.banners);
  }

  /// [to] is already adjusted for the removed row (onReorderItem).
  Future<void> _reorder(int from, int to) async {
    final previous = List.of(_order);
    setState(() {
      final item = _order.removeAt(from);
      _order.insert(to, item);
    });
    try {
      await ref
          .read(homeBannerRepositoryProvider)
          .saveOrder(_order.map((b) => b.id).toList());
      ref.invalidate(adminHomeBannersProvider);
      ref.invalidate(liveHomeBannersProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _order = previous);
      _toast(
        friendlyErrorMessage(
          e,
          fallback: 'Could not save the new order. Please try again.',
          context: 'admin.banner_reorder',
        ),
      );
    }
  }

  Future<void> _setActive(HomeBanner banner, bool active) async {
    setState(() => _busy.add(banner.id));
    try {
      await ref.read(homeBannerRepositoryProvider).upsertBanner({
        'active': active,
      }, id: banner.id);
      ref.invalidate(adminHomeBannersProvider);
      ref.invalidate(liveHomeBannersProvider);
      if (mounted) _toast(active ? 'Banner shown' : 'Banner hidden');
    } catch (e) {
      if (mounted) {
        _toast(
          friendlyErrorMessage(
            e,
            fallback: 'Could not update the banner. Please try again.',
            context: 'admin.banner_toggle',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(banner.id));
    }
  }

  void _toast(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: _order.length,
      onReorderItem: _reorder,
      itemBuilder: (context, i) {
        final b = _order[i];
        return _BannerRow(
          key: ValueKey(b.id),
          banner: b,
          index: i,
          schedule: b.scheduleAt(now),
          busy: _busy.contains(b.id),
          onToggle: (v) => _setActive(b, v),
          onTap: () => AdminBannersScreen._openForm(context, existing: b),
        );
      },
    );
  }
}

class _BannerRow extends StatelessWidget {
  final HomeBanner banner;
  final int index;
  final BannerSchedule schedule;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;
  const _BannerRow({
    super.key,
    required this.banner,
    required this.index,
    required this.schedule,
    required this.busy,
    required this.onToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final (label, color) = switch (schedule) {
      BannerSchedule.live => ('Live', palette.success),
      BannerSchedule.scheduled => ('Scheduled', palette.warning),
      BannerSchedule.ended => ('Ended', palette.textMuted),
      BannerSchedule.hidden => ('Hidden', palette.error),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: SizedBox(
                  width: 84,
                  height: 46,
                  child: SizedNetworkImage(
                    imageUrl: banner.imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, _) =>
                        ColoredBox(color: palette.surfaceMuted),
                    errorWidget: (_, _, _) => ColoredBox(
                      color: palette.surfaceMuted,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: palette.textMuted,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      banner.title ?? 'Image only',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: banner.title == null
                            ? palette.textMuted
                            : palette.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 2,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                        if (_scheduleText(banner) case final text?)
                          Text(
                            text,
                            style: TextStyle(
                              fontSize: 12,
                              color: palette.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Semantics(
                label: 'Show banner',
                child: Switch.adaptive(
                  value: banner.active,
                  onChanged: busy ? null : onToggle,
                ),
              ),
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.drag_handle),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String? _scheduleText(HomeBanner b) {
    final f = DateFormat('d MMM, HH:mm');
    if (b.startsAt != null && b.endsAt != null) {
      return '${f.format(b.startsAt!)} – ${f.format(b.endsAt!)}';
    }
    if (b.startsAt != null) return 'From ${f.format(b.startsAt!)}';
    if (b.endsAt != null) return 'Until ${f.format(b.endsAt!)}';
    return null;
  }
}

/// Add/edit one slide. Full-screen so the live preview, the schedule and
/// the unsaved-changes guard all have room.
class BannerFormScreen extends ConsumerStatefulWidget {
  final HomeBanner? existing;
  const BannerFormScreen({super.key, this.existing});

  @override
  ConsumerState<BannerFormScreen> createState() => _BannerFormScreenState();
}

class _BannerFormScreenState extends ConsumerState<BannerFormScreen> {
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _subtitle = TextEditingController(text: widget.existing?.subtitle);
  late final _cta = TextEditingController(text: widget.existing?.ctaLabel);
  late final _link = TextEditingController(text: widget.existing?.linkUrl);
  late bool _active = widget.existing?.active ?? true;
  late DateTime? _startsAt = widget.existing?.startsAt;
  late DateTime? _endsAt = widget.existing?.endsAt;
  XFile? _picked;
  Uint8List? _pickedBytes;
  bool _saving = false;
  bool _submitted = false;
  String? _saveError;

  bool get _dirty {
    final e = widget.existing;
    return _picked != null ||
        _title.text.trim() != (e?.title ?? '') ||
        _subtitle.text.trim() != (e?.subtitle ?? '') ||
        _cta.text.trim() != (e?.ctaLabel ?? '') ||
        _link.text.trim() != (e?.linkUrl ?? '') ||
        _active != (e?.active ?? true) ||
        _startsAt != e?.startsAt ||
        _endsAt != e?.endsAt;
  }

  String? get _imageError =>
      _picked == null && widget.existing == null ? 'Add a photo.' : null;

  String? get _linkError {
    final v = _link.text.trim();
    if (v.isEmpty || v.startsWith('/')) return null;
    final uri = Uri.tryParse(v);
    if (uri != null && (uri.isScheme('https') || uri.isScheme('http'))) {
      return null;
    }
    return 'Use an in-app path like /product/… or a link starting with https://';
  }

  String? get _windowError =>
      _startsAt != null && _endsAt != null && !_endsAt!.isAfter(_startsAt!)
      ? 'End must be after start.'
      : null;

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _subtitle, _cta, _link]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _subtitle.dispose();
    _cta.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: uploadImageMaxSide,
      maxHeight: uploadImageMaxSide,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (mounted) {
      setState(() {
        _picked = picked;
        _pickedBytes = bytes;
      });
    }
  }

  Future<void> _pickDateTime({required bool start}) async {
    final current = start ? _startsAt : _endsAt;
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 3)),
      helpText: start ? 'Banner starts on' : 'Banner ends on',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        current ??
            (start ? now : DateTime(now.year, now.month, now.day, 23, 59)),
      ),
      helpText: start ? 'Starts at' : 'Ends at',
    );
    if (!mounted) return;
    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? 0,
      time?.minute ?? 0,
    );
    setState(() {
      if (start) {
        _startsAt = picked;
      } else {
        _endsAt = picked;
      }
    });
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty || _saving) return true;
    return confirmDestructiveAction(
      context,
      title: 'Discard changes?',
      message: 'Your edits to this banner will be lost.',
      confirmLabel: 'Discard',
    );
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (_imageError != null || _linkError != null || _windowError != null) {
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final repo = ref.read(homeBannerRepositoryProvider);
    try {
      var imageUrl = widget.existing?.imageUrl;
      if (_picked != null && _pickedBytes != null) {
        imageUrl = await repo.uploadBannerImage(
          _pickedBytes!,
          _picked!.name.split('.').last,
        );
      }
      String? clean(TextEditingController c) =>
          c.text.trim().isEmpty ? null : c.text.trim();
      await repo.upsertBanner({
        'image_url': imageUrl,
        'title': clean(_title),
        'subtitle': clean(_subtitle),
        'cta_label': clean(_cta),
        'link_url': clean(_link),
        'active': _active,
        'starts_at': _startsAt?.toUtc().toIso8601String(),
        'ends_at': _endsAt?.toUtc().toIso8601String(),
        if (widget.existing == null) 'sort_order': 1 << 20,
      }, id: widget.existing?.id);
      ref.invalidate(adminHomeBannersProvider);
      ref.invalidate(liveHomeBannersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.existing == null ? 'Banner added' : 'Banner saved',
            ),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _saveError = friendlyErrorMessage(
            e,
            fallback: 'Could not save the banner. Please try again.',
            context: 'admin.banner_edit',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final ok = await confirmDestructiveAction(
      context,
      title: 'Delete this banner?',
      message: 'It disappears from the Shop tab immediately.',
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(homeBannerRepositoryProvider).deleteBanner(existing.id);
      ref.invalidate(adminHomeBannersProvider);
      ref.invalidate(liveHomeBannersProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = friendlyErrorMessage(
            e,
            fallback: 'Could not delete the banner. Please try again.',
            context: 'admin.banner_delete',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final preview = HomeBanner(
      id: widget.existing?.id ?? 'new',
      imageUrl: widget.existing?.imageUrl ?? '',
      title: _title.text.trim().isEmpty ? null : _title.text.trim(),
      subtitle: _subtitle.text.trim().isEmpty ? null : _subtitle.text.trim(),
      ctaLabel: _cta.text.trim().isEmpty ? null : _cta.text.trim(),
      linkUrl: _link.text.trim().isEmpty ? null : _link.text.trim(),
    );
    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.existing == null ? 'Add Banner' : 'Edit Banner'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              style: TextButton.styleFrom(foregroundColor: AppColors.white),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _SectionLabel('PREVIEW'),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: AspectRatio(
                aspectRatio: BannerCarousel.aspectRatio,
                child: BannerSlide(
                  banner: preview,
                  localImage: _pickedBytes,
                  onTap: _pickImage,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: Text(
                    _picked == null && widget.existing == null
                        ? 'Choose photo'
                        : 'Replace photo',
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    _submitted && _imageError != null
                        ? _imageError!
                        : 'Landscape photo, about 2:1. Resized to 1600 px.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: _submitted && _imageError != null
                          ? palette.error
                          : palette.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            _SectionLabel('TEXT (OPTIONAL)'),
            TextField(
              controller: _title,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Headline',
                hintText: 'e.g. New Kohaku arrivals',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _subtitle,
              maxLength: 140,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Subtitle',
                hintText: 'e.g. Fresh from the autumn harvest',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _cta,
              maxLength: 30,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Button label',
                hintText: 'e.g. Shop Koi',
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            _SectionLabel('TAP TARGET'),
            TextField(
              controller: _link,
              keyboardType: TextInputType.url,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Link (optional)',
                hintText: '/product/<id>  or  https://…',
                helperText: 'In-app: /product/<id>, /faq. Web: https://… opens outside the app.',
                helperMaxLines: 3,
                errorText: _submitted ? _linkError : null,
                errorMaxLines: 3,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            _SectionLabel('SCHEDULE (OPTIONAL)'),
            _DateTimeTile(
              label: 'Starts',
              value: _startsAt,
              emptyText: 'Immediately',
              onPick: () => _pickDateTime(start: true),
              onClear: () => setState(() => _startsAt = null),
            ),
            _DateTimeTile(
              label: 'Ends',
              value: _endsAt,
              emptyText: 'Never',
              onPick: () => _pickDateTime(start: false),
              onClear: () => setState(() => _endsAt = null),
            ),
            if (_submitted && _windowError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 16),
                child: Text(
                  _windowError!,
                  style: TextStyle(color: palette.error, fontSize: 12.5),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show in app'),
              subtitle: Text(
                _active
                    ? 'Visible to customers during the schedule above.'
                    : 'Hidden until you switch it on.',
              ),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            if (_saveError != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_saveError!, style: TextStyle(color: palette.error)),
            ],
            const SizedBox(height: AppSpacing.xl),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: Text(
                widget.existing == null ? 'Add Banner' : 'Save Changes',
              ),
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: _saving ? null : _delete,
                style: TextButton.styleFrom(foregroundColor: palette.error),
                child: const Text('Delete Banner'),
              ),
            ],
            SizedBox(height: MediaQuery.paddingOf(context).bottom + 24),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: AppPalette.of(context).textMuted),
    ),
  );
}

class _DateTimeTile extends StatelessWidget {
  final String label;
  final DateTime? value;
  final String emptyText;
  final VoidCallback onPick;
  final VoidCallback onClear;
  const _DateTimeTile({
    required this.label,
    required this.value,
    required this.emptyText,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onPick,
      leading: Icon(Icons.schedule_outlined, color: palette.textMuted),
      title: Text(label),
      subtitle: Text(
        value == null
            ? emptyText
            : DateFormat('EEE, d MMM yyyy · HH:mm').format(value!),
        style: TextStyle(color: value == null ? palette.textMuted : null),
      ),
      trailing: value == null
          ? const Icon(Icons.chevron_right)
          : IconButton(
              tooltip: 'Clear $label',
              icon: const Icon(Icons.close),
              onPressed: onClear,
            ),
    );
  }
}
