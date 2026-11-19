import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/appearance_tile.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/discard_changes_guard.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/providers/settings_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../admin_shell.dart' show adminTabIndexProvider, kAdminHomeBannersTab;
import '../delivery/easyparcel_providers.dart';
import '../delivery/easyparcel_repository.dart';
import 'settings_repository.dart';
import '../../support/support_directory_settings.dart';
import '../../../shared/utils/error_message.dart';
import '../../../shared/widgets/section_label.dart';

class AdminSettingsScreen extends ConsumerStatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  ConsumerState<AdminSettingsScreen> createState() =>
      _AdminSettingsScreenState();
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
  final _shopPostcodeCtrl = TextEditingController();
  final _shopCityCtrl = TextEditingController();
  final _shopStateCtrl = TextEditingController();
  final _parcelLengthCtrl = TextEditingController();
  final _parcelWidthCtrl = TextEditingController();
  final _parcelHeightCtrl = TextEditingController();
  int? _loadedGst;
  bool _loadedGstIncluded = true;
  String? _baseline;
  bool _gstIncluded = true;
  bool _showPriceDefault = true;
  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;
  bool _signingOut = false;
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
    final String state;
    try {
      state = await EasyParcelRepository().startOAuth();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyErrorMessage(
                e,
                fallback: 'Could not start EasyParcel connection.',
                context: 'admin.settings',
              ),
            ),
          ),
        );
      }
      return;
    }
    final uri = Uri.https('api.easyparcel.com', '/oauth/login', {
      'client_id': 'f0e209dd-f3db-4f6f-a74b-c5aa743af87e',
      'redirect_uri': 'https://gexgcwdkbeythrnqmihe.supabase.co/functions/v1/easyparcel-oauth-callback',
      'state': state,
    });
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              e,
              fallback: 'Could not log out. Please try again.',
              context: 'admin.settings',
            ),
          ),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    _checkEasyParcelStatus();
  }

  @override
  void dispose() {
    for (final c in [
      _shopNameCtrl,
      _phoneCtrl,
      _addressCtrl,
      _gstCtrl,
      _deliveryMinCtrl,
      _deliveryMaxCtrl,
      _lowStockThresholdCtrl,
      _shopPostcodeCtrl,
      _shopCityCtrl,
      _shopStateCtrl,
      _parcelLengthCtrl,
      _parcelWidthCtrl,
      _parcelHeightCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
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
      _shopPostcodeCtrl.text = s['shop_postcode']?.toString() ?? '';
      _shopCityCtrl.text = s['shop_city']?.toString() ?? '';
      _shopStateCtrl.text = s['shop_state']?.toString() ?? '';
      _parcelLengthCtrl.text = s['default_parcel_length_cm']?.toString() ?? '';
      _parcelWidthCtrl.text = s['default_parcel_width_cm']?.toString() ?? '';
      _parcelHeightCtrl.text = s['default_parcel_height_cm']?.toString() ?? '';
      _loadedGst = int.tryParse(_gstCtrl.text);
      _loadedGstIncluded = _gstIncluded;
      _baseline = _fingerprint();
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Human-readable problems with the fields that every checkout total,
  /// invoice and shipping quote depends on; null when all is well.
  String? _validationError() {
    final gst = int.tryParse(_gstCtrl.text.trim());
    if (gst == null || gst < 0 || gst > 100) {
      return 'GST % must be a whole number from 0 to 100.';
    }
    final minDays = int.tryParse(_deliveryMinCtrl.text.trim());
    final maxDays = int.tryParse(_deliveryMaxCtrl.text.trim());
    if (minDays == null || maxDays == null || minDays < 0 || maxDays < 0) {
      return 'Delivery min and max days must be whole numbers.';
    }
    if (minDays > maxDays) return 'Delivery min days cannot exceed max days.';
    final low = int.tryParse(_lowStockThresholdCtrl.text.trim());
    if (low == null || low < 0) {
      return 'Low-stock threshold must be a whole number.';
    }
    final postcode = _shopPostcodeCtrl.text.trim();
    if (postcode.isNotEmpty && !RegExp(r'^\d{6}\$').hasMatch(postcode)) {
      return 'Shop postcode must be 6 digits (Singapore).';
    }
    final dimensions = [_parcelLengthCtrl, _parcelWidthCtrl, _parcelHeightCtrl];
    final entered = dimensions.any((c) => c.text.trim().isNotEmpty);
    final valid = dimensions.every((c) {
      final n = double.tryParse(c.text.trim());
      return n != null && n.isFinite && n > 0;
    });
    if (entered && !valid) {
      return 'Enter all three positive dimensions, or leave all dimensions blank.';
    }
    return null;
  }

  /// Everything the form holds, for the unsaved-changes guard.
  String _fingerprint() => [
    _shopNameCtrl.text,
    _phoneCtrl.text,
    _addressCtrl.text,
    _gstCtrl.text,
    _gstIncluded,
    _showPriceDefault,
    _deliveryMinCtrl.text,
    _deliveryMaxCtrl.text,
    _lowStockThresholdCtrl.text,
    _shopPostcodeCtrl.text,
    _shopCityCtrl.text,
    _shopStateCtrl.text,
    _parcelLengthCtrl.text,
    _parcelWidthCtrl.text,
    _parcelHeightCtrl.text,
  ].join('\u0001');

  Future<void> _save() async {
    final problem = _validationError();
    if (problem != null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    // GST changes every price shown and charged from the next checkout.
    final gstNow = int.parse(_gstCtrl.text.trim());
    if (_loadedGst != null &&
        (gstNow != _loadedGst || _gstIncluded != _loadedGstIncluded)) {
      final ok = await confirmAction(
        context,
        title: 'Change GST for the whole shop?',
        message:
            'New GST settings apply to every price, checkout total and '
            'invoice from now on. Existing orders are not changed.',
        confirmLabel: 'Change GST',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      // The retired promo popup's promo_banner_* columns are deliberately
      // absent: an upsert leaves columns it does not name untouched, so the
      // stored image, link and switch stay exactly as they were.
      await _repo.updateSettings({
        'shop_name': _shopNameCtrl.text.trim(),
        'shop_phone': _phoneCtrl.text.trim(),
        'shop_address': _addressCtrl.text.trim(),
        'gst_percent': int.tryParse(_gstCtrl.text.trim()) ?? 9,
        'gst_included_in_price': _gstIncluded,
        'show_price_default': _showPriceDefault,
        'delivery_lead_days_min':
            int.tryParse(_deliveryMinCtrl.text.trim()) ?? 2,
        'delivery_lead_days_max':
            int.tryParse(_deliveryMaxCtrl.text.trim()) ?? 5,
        'low_stock_threshold':
            int.tryParse(_lowStockThresholdCtrl.text.trim()) ?? 5,
        'shop_postcode': _shopPostcodeCtrl.text.trim(),
        'shop_city': _shopCityCtrl.text.trim(),
        'shop_state': _shopStateCtrl.text.trim(),
        'default_parcel_length_cm': double.tryParse(
          _parcelLengthCtrl.text.trim(),
        ),
        'default_parcel_width_cm': double.tryParse(
          _parcelWidthCtrl.text.trim(),
        ),
        'default_parcel_height_cm': double.tryParse(
          _parcelHeightCtrl.text.trim(),
        ),
      });
      ref.invalidate(shopSettingsProvider);
      if (mounted) {
        _loadedGst = gstNow;
        _loadedGstIncluded = _gstIncluded;
        _baseline = _fingerprint();
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(content: Text('Settings saved')));
      }
    } catch (e) {
      // Settings that silently fail to save are worse than an error: the
      // owner walks away believing GST or delivery days changed.
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                friendlyErrorMessage(
                  e,
                  fallback: 'Could not save settings. Please try again.',
                  context: 'admin.settings_save',
                ),
              ),
            ),
          );
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
    if (_loadFailed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ErrorState(onRetry: _load),
      );
    }
    return DiscardChangesGuard(
      dirty: _baseline != null && _fingerprint() != _baseline,
      busy: _saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            const _SectionLabel('THIS DEVICE'),
            const AppearanceTile(),
            Text(
              'Appearance is saved on this device and does not change shop settings.',
              style: TextStyle(
                color: AppPalette.of(context).textMuted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const _SectionLabel('SHOP INFO'),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _shopNameCtrl,
              decoration: const InputDecoration(labelText: 'Shop name'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _addressCtrl,
              decoration: const InputDecoration(labelText: 'Address'),
              maxLines: 2,
            ),
            const SizedBox(height: AppSpacing.xl),
            const SupportDirectorySettingsTile(),
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
            Text(
              'Shown on shop cards as an estimated delivery date range',
              style: TextStyle(
                fontSize: 12,
                color: AppPalette.of(context).textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const _SectionLabel('EASYPARCEL INTEGRATION'),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Connect once to auto-book couriers and auto-track shipments '
              'from the Delivery tab, instead of typing tracking numbers in '
              'by hand.',
              style: TextStyle(
                fontSize: 12,
                color: AppPalette.of(context).textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppPalette.of(context).surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        _easyParcelStatus?.connected == true
                            ? Icons.check_circle
                            : Icons.link_off,
                        color: _easyParcelStatus?.connected == true
                            ? AppPalette.of(context).success
                            : AppPalette.of(context).textMuted,
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
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _checkingEasyParcel
                          ? null
                          : _checkEasyParcelStatus,
                      child: const Text('Refresh'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'For real pickups, select your live Singapore account when reconnecting. '
              'Connected only confirms authorization; a sandbox account does not arrange real pickups.',
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
            Text(
              'SENDER ADDRESS (used for shipping rate quotes)',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: 0.6,
                color: AppPalette.of(context).textMuted,
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
              decoration: const InputDecoration(
                labelText: 'State (if applicable)',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const SizedBox(height: AppSpacing.xl),
            const _SectionLabel('SHIPPING POLICY'),
            const SizedBox(height: AppSpacing.sm),
            const Text('All available couriers · Currency: SGD (S\$)'),
            const Text(
              'Courier delivery: buyer 50%, shop 50%. The shop covers any rounding cent.',
            ),
            const Text(
              'Live fish and mixed shop-delivery orders: the shop covers delivery in full.',
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Packed parcel dimensions (optional)',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const Text(
              'Shipping weight comes from each product option × quantity. Leave dimensions blank for weight-based quotes; enter the actual packed dimensions before booking. Only configure these if they apply to every courier parcel.',
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final entry in [
              (_parcelLengthCtrl, 'Length (cm)'),
              (_parcelWidthCtrl, 'Width (cm)'),
              (_parcelHeightCtrl, 'Height (cm)'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: entry.$1,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(labelText: entry.$2),
                ),
              ),
            const SizedBox(height: AppSpacing.xl),
            const _SectionLabel('INVENTORY'),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _lowStockThresholdCtrl,
              decoration: const InputDecoration(
                labelText: 'Low stock alert quantity',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Products at or below this quantity appear in the dashboard\'s '
              'Low Stock list',
              style: TextStyle(
                fontSize: 12,
                color: AppPalette.of(context).textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const _SectionLabel('PROMOTIONS'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.view_carousel_outlined),
              title: const Text('Promotions now live in Home Banners'),
              subtitle: const Text(
                'The once-a-day popup is retired. Add promotion slides to '
                'the carousel on the shop home page.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  ref.read(adminTabIndexProvider.notifier).state =
                      kAdminHomeBannersTab,
            ),
            const SizedBox(height: AppSpacing.xl),
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
                  : const Text('Save Settings'),
            ),
            const SizedBox(height: AppSpacing.xl),
            const Divider(),
            ListTile(
              leading: _signingOut
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppPalette.of(context).error,
                      ),
                    )
                  : Icon(Icons.logout, color: AppPalette.of(context).error),
              title: Text(
                'Log Out',
                style: TextStyle(color: AppPalette.of(context).error),
              ),
              enabled: !_signingOut,
              onTap: _confirmSignOut,
            ),
          ],
        ),
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
    return SectionLabel(text);
  }
}
