import '../../orders/utils/print_document.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/models/order.dart';
import '../../../shared/models/order_parcel.dart';
import '../../../shared/utils/price_format.dart';
import '../../../shared/widgets/parcel_tracking_list.dart';
import 'easyparcel_providers.dart';

class ParcelFulfillmentPanel extends ConsumerStatefulWidget {
  final Order order;
  final bool disabled;
  final VoidCallback onChanged;
  const ParcelFulfillmentPanel({
    super.key,
    required this.order,
    required this.onChanged,
    this.disabled = false,
  });
  @override
  ConsumerState<ParcelFulfillmentPanel> createState() =>
      _ParcelFulfillmentPanelState();
}

class _ParcelFulfillmentPanelState
    extends ConsumerState<ParcelFulfillmentPanel> {
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _quote;
  List<OrderParcel>? _local;
  List<OrderParcel> get _parcels => _local ?? widget.order.parcels;
  bool get _editable => _parcels.every((p) => p.state == 'draft');
  @override
  void didUpdateWidget(covariant ParcelFulfillmentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order != widget.order) {
      _local = null;
      _quote = null;
    }
  }

  void _accept(Map<String, dynamic> result) {
    final rows = result['parcels'];
    if (rows is List) {
      _local =
          rows
              .whereType<Map>()
              .map((p) => OrderParcel.fromMap(p.cast<String, dynamic>()))
              .toList()
            ..sort((a, b) => a.number.compareTo(b.number));
    }
  }

  Future<void> _action(
    String action, {
    Map<String, dynamic> data = const {},
  }) async {
    if (_busy || widget.disabled) return;
    setState(() {
      _busy = true;
      _error = null;
      if (action != 'book') _quote = null;
    });
    try {
      final result = await ref
          .read(easyParcelRepositoryProvider)
          .parcelAction(action, widget.order.id, data: data);
      if (!mounted) return;
      setState(() {
        _accept(result);
        _quote = action == 'quote' ? result : null;
      });
      if (action != 'quote') widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _quote = null;
        _error = error is StateError
            ? error.message.toString()
            : 'Could not update parcels. Refresh before trying again.';
      });
      // A timeout can follow a successful booking. Always read saved truth;
      // never restore a stale enabled booking action.
      if (action == 'book') {
        try {
          final result = await ref
              .read(easyParcelRepositoryProvider)
              .parcelAction('list', widget.order.id);
          if (mounted) setState(() => _accept(result));
        } catch (_) {
          if (mounted) {
            setState(
              () => _local = _parcels
                  .map(
                    (p) => OrderParcel(
                      id: p.id,
                      number: p.number,
                      state: 'needs_attention',
                      items: p.items,
                    ),
                  )
                  .toList(),
            );
          }
        }
        widget.onChanged();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    if (_busy || widget.disabled) return;
    setState(() => _busy = true);
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ParcelPlanEditor(order: widget.order, parcels: _parcels),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result != null) {
        _accept(result);
        _quote = null;
        _error = null;
      }
    });
    if (result != null) widget.onChanged();
  }

  Future<void> _book() async {
    final quote = _quote;
    final cents = quote?['total_cents'];
    final signature = quote?['quote_signature'];
    if (cents is! num || signature is! String || signature.isEmpty || _busy) {
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Book these parcels?'),
        content: Text(
          'Courier total: ${formatPrice(cents.toDouble() / 100)}\n'
          'Customer already paid: ${formatPrice(((quote?['buyer_shipping_cents'] as num?)?.toDouble() ?? 0) / 100)}\n'
          'Shop covers: ${formatPrice(((quote?['seller_shipping_cents'] as num?)?.toDouble() ?? 0) / 100)}\n\n'
          'This can create real courier bookings. The customer will not be charged again. If EasyParcel needs payment, complete it there.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve booking'),
          ),
        ],
      ),
    );
    if (approved == true && mounted) {
      await _action(
        'book',
        data: {
          'approved_total_cents': cents.toInt(),
          'approved_quote_signature': signature,
        },
      );
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri?.scheme != 'https') return;
    try {
      if (await launchUrl(uri!, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the page. Try your browser.'),
        ),
      );
    }
  }

  Future<void> _printLabel(String url) async {
    try {
      await previewShippingLabel(
        context,
        url: url,
        orderNumber: widget.order.displayNumber,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not load the shipping label. Pull down and try again.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final parcels = _parcels;
    final disabled = _busy || widget.disabled;
    if (parcels.isEmpty) {
      return OutlinedButton.icon(
        onPressed: disabled ? null : _edit,
        icon: const Icon(Icons.inventory_2_outlined, size: 18),
        label: const Text('Split into parcels'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ParcelTrackingList(
          parcels: parcels,
          showMeasurements: true,
          onPrint: disabled ? null : (p) => _printLabel(p.awbUrl!),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_quote != null) ...[
          const Divider(),
          Text(
            'Courier total: ${formatPrice(((_quote!['total_cents'] as num?)?.toDouble() ?? 0) / 100)}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            'Customer paid: ${formatPrice(((_quote!['buyer_shipping_cents'] as num?)?.toDouble() ?? 0) / 100)} · no extra charge',
          ),
          Text(
            'Shop covers: ${formatPrice(((_quote!['seller_shipping_cents'] as num?)?.toDouble() ?? 0) / 100)}',
          ),
          if (((_quote!['additional_seller_cents'] as num?)?.toInt() ?? 0) > 0)
            Text(
              'Extra shop cost: ${formatPrice((_quote!['additional_seller_cents'] as num).toDouble() / 100)}',
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: disabled ? null : _book,
            child: const Text('Review & book parcels'),
          ),
        ] else if (_editable)
          FilledButton(
            onPressed: disabled ? null : () => _action('quote'),
            child: const Text('Get parcel quotes'),
          ),
        if (_editable)
          TextButton(
            onPressed: disabled ? null : _edit,
            child: const Text('Edit parcels'),
          )
        else ...[
          if (parcels.any((p) => p.needsAttention || !p.canPrintLabel))
            TextButton.icon(
              onPressed: disabled
                  ? null
                  : () => _open('https://app.easyparcel.com/shipment/list'),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Check EasyParcel'),
            ),
        ],
        if (_busy) const LinearProgressIndicator(),
      ],
    );
  }
}

class _BoxDraft {
  final Map<String, TextEditingController> quantities = {};
  final kg = TextEditingController(),
      length = TextEditingController(),
      width = TextEditingController(),
      height = TextEditingController();
  _BoxDraft(List<Map<String, dynamic>> lines, {OrderParcel? parcel}) {
    for (final line in lines) {
      final id = line['order_item_id'] as String;
      final entries = parcel?.items.where((i) => i['order_item_id'] == id);
      quantities[id] = TextEditingController(
        text: '${entries?.isNotEmpty == true ? entries!.first['quantity'] : 0}',
      );
    }
    if (parcel != null) {
      kg.text = '${parcel.weightKg}';
      length.text = '${parcel.lengthCm}';
      width.text = '${parcel.widthCm}';
      height.text = '${parcel.heightCm}';
    }
  }
  int qty(String id) => int.tryParse(quantities[id]!.text) ?? 0;
  void defaults(List<Map<String, dynamic>> lines) {
    var total = 0.0, units = 0;
    var known = true;
    Map? single;
    for (final line in lines) {
      final count = qty(line['order_item_id'] as String);
      if (count <= 0) continue;
      final weight = line['weight_kg'];
      if (weight is! num || weight <= 0) {
        known = false;
      } else {
        total += weight * count;
      }
      units += count;
      single = line;
    }
    kg.text = known && total > 0
        ? total.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '')
        : '';
    final dims = units == 1 && single != null
        ? single['packed_dimensions']
        : null;
    length.text = dims is Map ? '${dims['length_cm'] ?? ''}' : '';
    width.text = dims is Map ? '${dims['width_cm'] ?? ''}' : '';
    height.text = dims is Map ? '${dims['height_cm'] ?? ''}' : '';
  }

  void dispose() {
    for (final c in [...quantities.values, kg, length, width, height]) {
      c.dispose();
    }
  }
}

class _ParcelPlanEditor extends ConsumerStatefulWidget {
  final Order order;
  final List<OrderParcel> parcels;
  const _ParcelPlanEditor({required this.order, required this.parcels});
  @override
  ConsumerState<_ParcelPlanEditor> createState() => _ParcelPlanEditorState();
}

class _ParcelPlanEditorState extends ConsumerState<_ParcelPlanEditor> {
  final _form = GlobalKey<FormState>();
  List<Map<String, dynamic>> _lines = [];
  final List<_BoxDraft> _boxes = [];
  bool _loading = true, _saving = false;
  String? _error;
  late DateTime _date;
  @override
  void initState() {
    super.initState();
    final sg = DateTime.now().toUtc().add(const Duration(hours: 8));
    _date = DateTime(sg.year, sg.month, sg.day + 1);
    final savedDate = widget.parcels.isEmpty
        ? null
        : DateTime.tryParse(widget.parcels.first.collectionDate);
    if (savedDate != null && !savedDate.isBefore(_date)) {
      _date = DateTime(savedDate.year, savedDate.month, savedDate.day);
    }
    _load();
  }

  @override
  void dispose() {
    for (final b in _boxes) {
      b.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await ref
          .read(easyParcelRepositoryProvider)
          .parcelAction('list', widget.order.id);
      if (!mounted) return;
      final rows = result['items'];
      if (rows is! List || rows.isEmpty) {
        throw StateError('Order items unavailable. Refresh the order.');
      }
      _lines = rows
          .whereType<Map>()
          .map((r) => r.cast<String, dynamic>())
          .toList();
      for (final b in _boxes) {
        b.dispose();
      }
      _boxes.clear();
      if (widget.parcels.isNotEmpty) {
        for (final p in widget.parcels) {
          _boxes.add(_BoxDraft(_lines, parcel: p));
        }
      } else {
        _boxes.addAll([_BoxDraft(_lines), _BoxDraft(_lines)]);
        var first = true;
        for (final line in _lines) {
          final id = line['order_item_id'] as String;
          final quantity = (line['quantity'] as num).toInt();
          _boxes[0].quantities[id]!.text = first ? '1' : '0';
          _boxes[1].quantities[id]!.text = '${quantity - (first ? 1 : 0)}';
          first = false;
        }
        for (final b in _boxes) {
          b.defaults(_lines);
        }
      }
      setState(() => _error = null);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError
              ? error.message.toString()
              : 'Could not load packing details. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _positive(String? text) {
    final n = double.tryParse(text?.trim() ?? '');
    return n == null || !n.isFinite || n <= 0
        ? 'Enter a positive number.'
        : null;
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    for (final line in _lines) {
      final id = line['order_item_id'] as String;
      if (_boxes.fold<int>(0, (sum, b) => sum + b.qty(id)) !=
          (line['quantity'] as num).toInt()) {
        setState(
          () => _error =
              'Allocate exactly ${line['quantity']} × ${line['product_name']} across the parcels.',
        );
        return;
      }
    }
    if (_boxes.any(
      (b) => b.quantities.values.every((c) => (int.tryParse(c.text) ?? 0) == 0),
    )) {
      setState(() => _error = 'Each parcel needs at least one item.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(easyParcelRepositoryProvider)
          .parcelAction(
            'save_plan',
            widget.order.id,
            data: {
              'parcels': [
                for (final b in _boxes)
                  {
                    'items': [
                      for (final e in b.quantities.entries)
                        if (b.qty(e.key) > 0)
                          {'order_item_id': e.key, 'quantity': b.qty(e.key)},
                    ],
                    'weight_kg': double.parse(b.kg.text),
                    'length_cm': double.parse(b.length.text),
                    'width_cm': double.parse(b.width.text),
                    'height_cm': double.parse(b.height.text),
                    'collection_date': DateFormat('yyyy-MM-dd').format(_date),
                  },
              ],
            },
          );
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError
              ? error.message.toString()
              : 'Could not save parcels. Refresh and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _measure(TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: c,
      decoration: InputDecoration(labelText: label),
      enabled: !_saving,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: _positive,
    ),
  );
  Widget _dimensions(_BoxDraft box) => LayoutBuilder(
    builder: (context, constraints) {
      final fields = [
        _measure(box.length, 'Length (cm)'),
        _measure(box.width, 'Width (cm)'),
        _measure(box.height, 'Height (cm)'),
      ];
      if (constraints.maxWidth < 340 ||
          MediaQuery.textScalerOf(context).scale(14) > 18) {
        return Column(children: fields);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < fields.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: fields[i]),
          ],
        ],
      );
    },
  );
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .9,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _lines.isEmpty
            ? Column(
                children: [
                  const Text('Packing details unavailable'),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              )
            : Form(
                key: _form,
                child: ListView(
                  children: [
                    const Text(
                      'Pack into parcels',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Match each parcel to a real packed box. Customer shipping stays unchanged.',
                    ),
                    for (var index = 0; index < _boxes.length; index++) ...[
                      const SizedBox(height: 20),
                      const Divider(),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Parcel ${index + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (_boxes.length > 2)
                            IconButton(
                              onPressed: _saving
                                  ? null
                                  : () => setState(
                                      () => _boxes.removeAt(index).dispose(),
                                    ),
                              tooltip: 'Remove parcel ${index + 1}',
                              icon: const Icon(Icons.close),
                            ),
                        ],
                      ),
                      for (final line in _lines)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextFormField(
                            controller:
                                _boxes[index].quantities[line['order_item_id']],
                            enabled: !_saving,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText:
                                  '${line['product_name']}${line['option_label'] == null ? '' : ' · ${line['option_label']}'}',
                              helperText:
                                  'Quantity in this parcel · ${line['quantity']} ordered',
                            ),
                            validator: (value) {
                              final n = int.tryParse(value?.trim() ?? '');
                              return n == null ||
                                      n < 0 ||
                                      n > (line['quantity'] as num)
                                  ? 'Enter a quantity from 0 to ${line['quantity']}.'
                                  : null;
                            },
                            onChanged: (_) =>
                                setState(() => _boxes[index].defaults(_lines)),
                          ),
                        ),
                      _measure(_boxes[index].kg, 'Packed kg'),
                      _dimensions(_boxes[index]),
                    ],
                    if (_boxes.length < 20)
                      OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () =>
                                  setState(() => _boxes.add(_BoxDraft(_lines))),
                        icon: const Icon(Icons.add),
                        label: const Text('Add parcel'),
                      ),
                    TextButton.icon(
                      onPressed: _saving
                          ? null
                          : () async {
                              final sg = DateTime.now().toUtc().add(
                                const Duration(hours: 8),
                              );
                              final first = DateTime(
                                sg.year,
                                sg.month,
                                sg.day + 1,
                              );
                              final date = await showDatePicker(
                                context: context,
                                initialDate: _date.isBefore(first)
                                    ? first
                                    : _date,
                                firstDate: first,
                                lastDate: first.add(const Duration(days: 90)),
                              );
                              if (date != null && mounted) {
                                setState(() => _date = date);
                              }
                            },
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                      label: Text(
                        'Pickup: ${DateFormat.yMMMd().format(_date)}',
                      ),
                    ),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Saving…' : 'Save parcel plan'),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    ),
  );
}
