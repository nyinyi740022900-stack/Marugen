import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/auth_providers.dart';
import 'settings_repository.dart';

class AdminSettingsScreen extends ConsumerStatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  ConsumerState<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends ConsumerState<AdminSettingsScreen> {
  final _repo = SettingsRepository();
  final _shopNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _gstCtrl = TextEditingController();
  final _deliveryMinCtrl = TextEditingController();
  final _deliveryMaxCtrl = TextEditingController();
  bool _gstIncluded = true;
  bool _showPriceDefault = true;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await _repo.fetchSettings();
    _shopNameCtrl.text = s['shop_name']?.toString() ?? '';
    _phoneCtrl.text = s['shop_phone']?.toString() ?? '';
    _addressCtrl.text = s['shop_address']?.toString() ?? '';
    _gstCtrl.text = s['gst_percent']?.toString() ?? '9';
    _gstIncluded = s['gst_included_in_price'] as bool? ?? true;
    _showPriceDefault = s['show_price_default'] as bool? ?? true;
    _deliveryMinCtrl.text = s['delivery_lead_days_min']?.toString() ?? '2';
    _deliveryMaxCtrl.text = s['delivery_lead_days_max']?.toString() ?? '5';
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _repo.updateSettings({
        'shop_name': _shopNameCtrl.text.trim(),
        'shop_phone': _phoneCtrl.text.trim(),
        'shop_address': _addressCtrl.text.trim(),
        'gst_percent': int.tryParse(_gstCtrl.text.trim()) ?? 9,
        'gst_included_in_price': _gstIncluded,
        'show_price_default': _showPriceDefault,
        'delivery_lead_days_min': int.tryParse(_deliveryMinCtrl.text.trim()) ?? 2,
        'delivery_lead_days_max': int.tryParse(_deliveryMaxCtrl.text.trim()) ?? 5,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          const _SectionLabel('SHOP INFO'),
          const SizedBox(height: AppSpacing.sm),
          TextField(controller: _shopNameCtrl, decoration: const InputDecoration(labelText: 'Shop name')),
          const SizedBox(height: AppSpacing.md),
          TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Phone')),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _addressCtrl,
            decoration: const InputDecoration(labelText: 'Address'),
            maxLines: 2,
          ),
          const SizedBox(height: AppSpacing.xl),
          const _SectionLabel('PRICING'),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _gstCtrl,
            decoration: const InputDecoration(labelText: 'GST %'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: AppSpacing.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('GST included in displayed price'),
            value: _gstIncluded,
            onChanged: (v) => setState(() => _gstIncluded = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show prices by default on new products'),
            subtitle: const Text('Can still be overridden per product'),
            value: _showPriceDefault,
            onChanged: (v) => setState(() => _showPriceDefault = v),
          ),
          const SizedBox(height: AppSpacing.xl),
          const _SectionLabel('DELIVERY'),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _deliveryMinCtrl,
                  decoration: const InputDecoration(labelText: 'Min days'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextField(
                  controller: _deliveryMaxCtrl,
                  decoration: const InputDecoration(labelText: 'Max days'),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Shown on shop cards as an estimated delivery date range',
            style: TextStyle(fontSize: 12, color: AppColors.grey),
          ),
          const SizedBox(height: AppSpacing.xl),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white))
                : const Text('Save Settings'),
          ),
          const SizedBox(height: AppSpacing.xl),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.error),
            title: const Text('Log Out', style: TextStyle(color: AppColors.error)),
            onTap: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
    );
  }
}

/// Small "SECTION LABEL" caption matching the grey letter-spaced headers
/// used throughout the app (product detail, order detail, product form).
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
