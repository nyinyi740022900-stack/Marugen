import '../utils/price_format.dart';

import 'package:flutter/material.dart';

import '../models/order_parcel.dart';

/// Customer-safe parcel progress. Owner-only costs and controls stay elsewhere.
class ParcelTrackingList extends StatelessWidget {
  final List<OrderParcel> parcels;
  final void Function(OrderParcel)? onPrint;
  final bool showMeasurements;
  const ParcelTrackingList({
    super.key,
    required this.parcels,
    this.onPrint,
    this.showMeasurements = false,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final parcel in parcels) ...[
        const Divider(),
        Text(
          'Parcel ${parcel.number} of ${parcels.length}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(parcel.statusLabel),
        if (parcel.carrierName != null) Text(parcel.carrierName!),
        if (parcel.trackingNumber?.isNotEmpty == true && !parcel.isSample)
          SelectableText('Tracking: ${parcel.trackingNumber}'),
        if (showMeasurements && parcel.quotedTotalCents != null)
          Text('Delivery: ${formatPrice(parcel.quotedTotalCents! / 100)}'),
        if (showMeasurements)
          Text(
            '${parcel.weightKg} kg · ${parcel.lengthCm} × ${parcel.widthCm} × ${parcel.heightCm} cm',
          ),
        if (onPrint != null && parcel.canPrintLabel)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => onPrint!(parcel),
              icon: const Icon(Icons.description_outlined, size: 18),
              label: const Text('Print label'),
            ),
          ),
      ],
    ],
  );
}
