import 'dart:io';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../auth/presentation/auth_providers.dart';
import '../delivery/easyparcel_providers.dart';
import '../delivery/easyparcel_repository.dart';
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
  final _lowStockThresholdCtrl = TextEditingController();
  final _bannerLinkCtrl = TextEditingController();
  final _shopPostcodeCtrl = TextEditingController();
  final _shopCityCtrl = TextEditingController();
  final _shopStateCtrl = TextEditingController();
  final _defaultWeightCtrl = TextEditingController();
  bool _gstIncluded = true;
  bool _showPriceDefault = true;
  bool _loading = true;
  bool _saving = false;
  bool _signingOut = false;
  XFile? _pickedBannerImage;
  String? _existingBannerImageUrl;
  bool _bannerActive = false;
  final _easyParcelRepo = EasyParcelRepository();
  bool _checkingEasyParcel = true;
  EasyParcelStatus? _easyParcelStatus;

  Future<void> _checkEasyParcelStatus() async {
    setState(() => _checkingEasyParcel = true);
    try {
      final status = await _easyParcelRepo.connectionStatus();
      if (mounted) setState(() => _easyParcelStatus = status);
      // So the Delivery tab's "Ship with EasyParcel" option appears
      // immediately once connected, instead of waiting for its own
      // provider to happen to re-run.
      ref.invalidate(easyParcelConnectedProvider);
    } catch (_) {
      // Non-fatal — Settings should still render if the check itself fails.
    } finally {
      if (mounted) setState(() => _checkingEasyParcel = false);
    }
  }

  /// Opens EasyParcel's OAuth consent screen in the external browser — the
  /// admin logs into their EasyParcel account there and approves, then
  /// easyparcel-oauth-callback (a Supabase Edge Function, not this app)
  /// exchanges the code and stores the tokens server-side. There's no way
  /// for the app to know the moment that finishes, so "Refresh status"
  /// (calling _checkEasyParcelStatus again) is how the admin confirms it.
  Future<void> _connectEasyParcel() async {
    final state = List.generate(24, (_) => Random.secure().nextInt(16).toRadixString(16)).join();
    final uri = Uri.https('api.easyparcel.com', '/oauth/login', {
      'client_id': 'f0e209dd-f3db-4f6f-a74b-c5aa743af87e',
      'redirect_uri':
          'https://gexgcwdkbeythrnqmihe.supabase.co/functions/v1/easyparcel-oauth-callback',
      'state': state,
    });
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _pickBannerImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked != null) setState(() => _pickedBannerImage = picked);
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await confirmLogout(context);
    if (!confirmed) return;

    setState(() => _signingOut = true);
    try {
      await ref.read(authRepositoryProvider).signOut();
    } catch (e) {
      if (!mounted) return;
      setState(() => _signingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not log out: $e')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    _checkEasyParcelStatus();
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
    _lowStockThresholdCtrl.text = s['low_stock_threshold']?.toString() ?? '5';
    _existingBannerImageUrl = s['promo_banner_image_url']?.toString();
    _bannerLinkCtrl.text = s['promo_banner_link_url']?.toString() ?? '';
    _bannerActive = s['promo_banner_active'] as bool? ?? false;
    _shopPostcodeCtrl.text = s['shop_postcode']?.toString() ?? '';
    _shopCityCtrl.text = s['shop_city']?.toString() ?? '';
    _shopStateCtrl.text = s['shop_state']?.toString() ?? '';
    _defaultWeightCtrl.text = s['default_parcel_weight_kg']?.toString() ?? '1';
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      var bannerImageUrl = _existingBannerImageUrl;
      final picked = _pickedBannerImage;
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        final ext = picked.name.split('.').last;
        bannerImageUrl = await _repo.uploadBannerImage(bytes, ext);
        // Record the upload immediately, before the settings write below
        // can fail — otherwise a network error on updateSettings() would
        // leave _pickedBannerImage still set, and retrying Save would
        // upload the same picked file a second time under a new path,
        // orphaning the first upload in storage.
        _existingBannerImageUrl = bannerImageUrl;
        _pickedBannerImage = null;
      }
      await _repo.updateSettings({
        'shop_name': _shopNameCtrl.text.trim(),
        'shop_phone': _phoneCtrl.text.trim(),
        'shop_address': _addressCtrl.text.trim(),
        'gst_percent': int.tryParse(_gstCtrl.text.trim()) ?? 9,
        'gst_included_in_price': _gstIncluded,
        'show_price_default': _showPriceDefault,
        'delivery_lead_days_min': int.tryParse(_deliveryMinCtrl.text.trim()) ?? 2,
        'delivery_lead_days_max': int.tryParse(_deliveryMaxCtrl.text.trim()) ?? 5,
        'low_stock_threshold':
            int.tryParse(_lowStockThresholdCtrl.text.trim()) ?? 5,
        'promo_banner_image_url': bannerImageUrl,
        'promo_banner_link_url': _bannerLinkCtrl.text.trim().isEmpty
            ? null
            : _bannerLinkCtrl.text.trim(),
        'promo_banner_active': _bannerActive,
        'shop_postcode': _shopPostcodeCtrl.text.trim(),
        'shop_city': _shopCityCtrl.text.trim(),
        'shop_state': _shopStateCtrl.text.trim(),
        'default_parcel_weight_kg':
            double.tryParse(_defaultWeightCtrl.text.trim()) ?? 1.0,
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(content: Text('Settings saved')));
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
          const _SectionLabel('EASYPARCEL INTEGRATION'),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Connect once to auto-book couriers and auto-track shipments '
            'from the Delivery tab, instead of typing tracking numbers in '
            'by hand.',
            style: TextStyle(fontSize: 12, color: AppColors.grey),
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.offWhite,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                Icon(
                  _easyParcelStatus?.connected == true
                      ? Icons.check_circle
                      : Icons.link_off,
                  color: _easyParcelStatus?.connected == true
                      ? AppColors.success
                      : AppColors.grey,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _checkingEasyParcel
                        ? 'Checking connection…'
                        : _easyParcelStatus?.connected == true
                            ? 'Connected'
                                '${_easyParcelStatus?.connectedAt != null ? ' since ${DateFormat.yMMMd().format(_easyParcelStatus!.connectedAt!)}' : ''}'
                            : 'Not connected',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                  ),
                ),
                TextButton(
                  onPressed: _checkingEasyParcel ? null : _checkEasyParcelStatus,
                  child: const Text('Refresh'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: _connectEasyParcel,
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(
              _easyParcelStatus?.connected == true
                  ? 'Reconnect EasyParcel'
                  : 'Connect EasyParcel',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'SENDER ADDRESS (used for shipping rate quotes)',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 0.6,
              color: AppColors.grey,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _shopPostcodeCtrl,
                  decoration: const InputDecoration(labelText: 'Postcode'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextField(
                  controller: _shopCityCtrl,
                  decoration: const InputDecoration(labelText: 'City'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _shopStateCtrl,
            decoration: const InputDecoration(labelText: 'State (if applicable)'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _defaultWeightCtrl,
            decoration: const InputDecoration(
              labelText: 'Default parcel weight (kg)',
              hintText: 'Used for every order — per-item weight isn\'t tracked yet',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: AppSpacing.xl),
          const _SectionLabel('INVENTORY'),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _lowStockThresholdCtrl,
            decoration: const InputDecoration(labelText: 'Low stock alert quantity'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Products at or below this quantity appear in the dashboard\'s '
            'Low Stock list',
            style: TextStyle(fontSize: 12, color: AppColors.grey),
          ),
          const SizedBox(height: AppSpacing.xl),
          const _SectionLabel('PROMOTION BANNER'),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Shown as a popup once per device per day when a customer '
            'opens the app.',
            style: TextStyle(fontSize: 12, color: AppColors.grey),
          ),
          const SizedBox(height: AppSpacing.sm),
          GestureDetector(
            onTap: _pickBannerImage,
            child: Container(
              height: 140,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.offWhite,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.lightGrey),
              ),
              clipBehavior: Clip.antiAlias,
              child: _pickedBannerImage != null
                  ? Image.file(File(_pickedBannerImage!.path), fit: BoxFit.cover)
                  : (_existingBannerImageUrl != null &&
                          _existingBannerImageUrl!.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: _existingBannerImageUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => const Icon(
                            Icons.image_not_supported_outlined,
                            color: AppColors.greySoft,
                          ),
                        )
                      : const Center(
                          child: Icon(
                            Icons.add_photo_alternate_outlined,
                            color: AppColors.grey,
                            size: 32,
                          ),
                        ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _bannerLinkCtrl,
            decoration: const InputDecoration(
              labelText: 'Link URL (optional)',
              hintText: 'Opened when a customer taps the banner',
            ),
            keyboardType: TextInputType.url,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show banner when app opens'),
            value: _bannerActive,
            onChanged: (v) => setState(() => _bannerActive = v),
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
            leading: _signingOut
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.error),
                  )
                : const Icon(Icons.logout, color: AppColors.error),
            title: const Text('Log Out', style: TextStyle(color: AppColors.error)),
            enabled: !_signingOut,
            onTap: _confirmSignOut,
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
