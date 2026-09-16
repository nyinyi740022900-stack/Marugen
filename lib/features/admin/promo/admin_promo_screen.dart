import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/promo_code.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../promo/presentation/promo_providers.dart';

/// Admin CRUD for `promo_codes` — mirrors [AdminKnowledgeScreen]'s
/// list + bottom-sheet-form pattern.
class AdminPromoScreen extends ConsumerWidget {
  const AdminPromoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promosAsync = ref.watch(adminPromoCodesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Promo Codes')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.red,
        onPressed: () => _showForm(context, ref),
        child: const Icon(Icons.add, color: AppColors.white),
      ),
      body: promosAsync.when(
        data: (promos) {
          if (promos.isEmpty) {
            return const EmptyState(
              icon: Icons.local_offer_outlined,
              title: 'No promo codes yet',
              subtitle: 'Tap + to create a discount code for checkout.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: promos.length,
            itemBuilder: (context, i) {
              final p = promos[i];
              final expired = p.isExpired;
              final label = p.discountType == DiscountType.percent
                  ? '${p.discountValue.toStringAsFixed(0)}% off'
                  : 'S\$${p.discountValue.toStringAsFixed(2)} off';
              return Card(
                child: ListTile(
                  title: Text(p.code, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    [
                      label,
                      if (p.expiresAt != null)
                        'Expires ${DateFormat.yMMMd().format(p.expiresAt!)}',
                      if (!p.active) 'Inactive',
                      if (expired) 'Expired',
                    ].join(' · '),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        p.isUsable ? Icons.check_circle_outline : Icons.block,
                        size: 18,
                        color: p.isUsable ? AppColors.success : AppColors.greySoft,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: AppColors.error),
                        onPressed: () async {
                          await ref.read(promoRepositoryProvider).delete(p.id);
                          ref.invalidate(adminPromoCodesProvider);
                        },
                      ),
                    ],
                  ),
                  onTap: () => _showForm(context, ref, existing: p),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  void _showForm(BuildContext context, WidgetRef ref, {PromoCode? existing}) {
    final codeCtrl = TextEditingController(text: existing?.code);
    final valueCtrl =
        TextEditingController(text: existing?.discountValue.toStringAsFixed(2));
    DiscountType type = existing?.discountType ?? DiscountType.percent;
    bool active = existing?.active ?? true;
    DateTime? expiresAt = existing?.expiresAt;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.xl,
            right: AppSpacing.xl,
            top: AppSpacing.xl,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.xl,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(existing == null ? 'Add Promo Code' : 'Edit Promo Code',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Code', hintText: 'e.g. WELCOME10'),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<DiscountType>(
                  initialValue: type,
                  items: const [
                    DropdownMenuItem(value: DiscountType.percent, child: Text('Percent off')),
                    DropdownMenuItem(value: DiscountType.fixed, child: Text('Fixed amount off')),
                  ],
                  onChanged: (v) => setSheetState(() => type = v ?? DiscountType.percent),
                  decoration: const InputDecoration(labelText: 'Discount type'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: valueCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: type == DiscountType.percent ? 'Percent (%)' : 'Amount (S\$)',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Expiry date'),
                  subtitle: Text(expiresAt == null
                      ? 'No expiry'
                      : DateFormat.yMMMd().format(expiresAt!)),
                  trailing: Wrap(
                    children: [
                      if (expiresAt != null)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setSheetState(() => expiresAt = null),
                        ),
                      IconButton(
                        icon: const Icon(Icons.calendar_today_outlined, size: 18),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: expiresAt ?? DateTime.now(),
                            firstDate: DateTime.now().subtract(const Duration(days: 365)),
                            lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                          );
                          if (picked != null) setSheetState(() => expiresAt = picked);
                        },
                      ),
                    ],
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: active,
                  onChanged: (v) => setSheetState(() => active = v),
                ),
                const SizedBox(height: AppSpacing.lg),
                ElevatedButton(
                  onPressed: () async {
                    final code = codeCtrl.text.trim().toUpperCase();
                    final value = double.tryParse(valueCtrl.text.trim()) ?? 0;
                    if (code.isEmpty || value <= 0) return;
                    await ref.read(promoRepositoryProvider).upsert({
                      'code': code,
                      'discount_type': type.name,
                      'discount_value': value,
                      'active': active,
                      'expires_at': expiresAt?.toIso8601String(),
                    }, id: existing?.id);
                    ref.invalidate(adminPromoCodesProvider);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
