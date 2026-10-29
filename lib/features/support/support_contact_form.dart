import 'dart:math';

import 'package:flutter/material.dart';

import '../../shared/models/support_contact.dart';

class SupportContactForm extends StatefulWidget {
  final SupportContact? contact;
  final ValueChanged<SupportContact> onSaved;
  const SupportContactForm({super.key, this.contact, required this.onSaved});
  @override
  State<SupportContactForm> createState() => _SupportContactFormState();
}

class _SupportContactFormState extends State<SupportContactForm> {
  late final _fields = [
    TextEditingController(text: widget.contact?.name),
    TextEditingController(text: widget.contact?.category),
    TextEditingController(text: widget.contact?.whatsapp),
    TextEditingController(text: widget.contact?.phone),
    TextEditingController(text: widget.contact?.email),
  ];
  String? _error;
  @override
  void dispose() {
    for (final controller in _fields) {
      controller.dispose();
    }
    super.dispose();
  }

  // Accept the usual "+65 8888-9999" spellings; storage stays +6588889999.
  static String _number(String text) => text.replaceAll(RegExp(r'[ ()-]'), '');

  void _save() {
    try {
      final contact = SupportContact.fromMap({
        'id':
            widget.contact?.id ??
            'contact-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
        'name': _fields[0].text,
        'category': _fields[1].text,
        'whatsapp': _number(_fields[2].text),
        'phone': _number(_fields[3].text),
        'email': _fields[4].text,
      });
      widget.onSaved(contact);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.contact == null ? 'Add support contact' : 'Edit support contact',
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'These details are public to customers. Add at least one channel. Use international phone numbers, e.g. +65 8888 9999.',
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < _fields.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextField(
              controller: _fields[i],
              keyboardType: i == 4
                  ? TextInputType.emailAddress
                  : (i >= 2 ? TextInputType.phone : TextInputType.text),
              maxLength: [80, 120, 20, 20, 254][i],
              decoration: InputDecoration(
                labelText: [
                  'Staff name',
                  'Support type / responsibility',
                  'WhatsApp (optional)',
                  'Phone (optional)',
                  'Email (optional)',
                ][i],
              ),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
          child: const Text('Save contact'),
        ),
      ],
    ),
  );
}
