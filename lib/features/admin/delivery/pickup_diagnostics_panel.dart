import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/models/order.dart';
import '../../../shared/utils/price_format.dart';
import 'easyparcel_providers.dart';

/// Owner-only read-only check. Operational detail stays behind one disclosure.
class PickupDiagnosticsPanel extends ConsumerStatefulWidget {
  final Order order;
  final bool disabled;
  const PickupDiagnosticsPanel({
    super.key,
    required this.order,
    this.disabled = false,
  });
  @override
  ConsumerState<PickupDiagnosticsPanel> createState() =>
      _PickupDiagnosticsPanelState();
}

class _PickupDiagnosticsPanelState
    extends ConsumerState<PickupDiagnosticsPanel> {
  Map<String, dynamic>? _result;
  bool _loading = false;
  bool _failed = false;

  Future<void> _check() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
      _result = null;
    });
    try {
      final result = await ref
          .read(easyParcelRepositoryProvider)
          .pickupDiagnostics(widget.order.id);
      if (mounted) setState(() => _result = result);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openParcels() async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse('https://app.easyparcel.com/shipment/list'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // The owner can use the website directly if no browser is available.
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Open app.easyparcel.com → All Parcels.')),
      );
    }
  }

  Widget _checkButton() => OutlinedButton.icon(
    onPressed: _loading || widget.disabled ? null : _check,
    icon: _loading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.manage_search, size: 18),
    label: Text(_loading ? 'Checking pickup…' : 'Check delivery details'),
  );

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final result = _result;
    final sample = order.hasSampleTracking;
    final wallet = result?['wallet'];
    final checked = DateTime.tryParse(result?['checked_at']?.toString() ?? '');
    final title = sample
        ? 'Live booking required'
        : result?['title'] as String? ??
              (order.needsBookingAttention
                  ? 'Booking needs checking'
                  : order.fulfillmentStatusLabel);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        if (sample) ...[
          const SizedBox(height: 6),
          const Text(
            'Sample shipment. Check EasyParcel before booking live delivery.',
          ),
        ],
        if (result?['collection_date'] != null) ...[
          const SizedBox(height: 6),
          Text('Pickup: ${result!['collection_date']} (Singapore)'),
        ],
        if (_failed) ...[
          const SizedBox(height: 6),
          const Text('Could not check pickup. Try again or open EasyParcel.'),
        ],
        const SizedBox(height: 8),
        if (sample)
          FilledButton.icon(
            onPressed: widget.disabled ? null : _openParcels,
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Open EasyParcel'),
          ),

        Material(
          type: MaterialType.transparency,
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: const Text('Delivery details'),
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (result?['message'] is String)
                    Text(result!['message'] as String),
                  if (result?['action'] is String) ...[
                    const SizedBox(height: 8),
                    Text(result!['action'] as String),
                  ],
                  if (result != null) ...[
                    const SizedBox(height: 8),
                    if (wallet is Map && wallet['balance'] is num)
                      Text(
                        'EasyParcel wallet: ${formatPrice((wallet['balance'] as num).toDouble())}',
                      )
                    else
                      const Text('SGD wallet balance unavailable.'),
                    if (wallet is Map && wallet['free_credit'] is num)
                      Text(
                        'Free credit: ${formatPrice((wallet['free_credit'] as num).toDouble())}',
                      ),
                    const Text(
                      'Wallet balance does not confirm shipment payment.',
                    ),
                    if (checked != null)
                      Text(
                        'Checked ${DateFormat.yMMMd().add_jm().format(checked.toLocal())}',
                      ),
                  ],
                  if (order.qxpressTrackingNo?.isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    SelectableText('Tracking: ${order.qxpressTrackingNo}'),
                  ],
                  if (!sample && order.trackingStatus != null)
                    Text(order.trackingStatus!),
                  if (!sample &&
                      order.trackingStatusDetail?.isNotEmpty == true &&
                      !order.trackingStatusDetail!.startsWith('booking_issue:'))
                    Text(order.trackingStatusDetail!),
                  _checkButton(),
                  if (!sample)
                    TextButton.icon(
                      onPressed: widget.disabled ? null : _openParcels,
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Open EasyParcel'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
