import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../l10n/app_localizations.dart';
import '../services/contacts_db.dart';

class _Contact {
  String name;
  String number;
  _Contact({required this.name, required this.number});
  String toPrefsString() => '$name|$number';
  factory _Contact.fromPrefsString(String s) {
    final idx = s.indexOf('|');
    if (idx == -1) return _Contact(name: '', number: s);
    return _Contact(name: s.substring(0, idx), number: s.substring(idx + 1));
  }
}

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});
  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<_Contact> _contacts = [];

  // flutter_secure_storage — AES encrypted on Android, Keychain on iOS
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? 'guest';
  String get _key => '${_uid}_emergency_contacts';

  @override
  void initState() { super.initState(); _loadContacts(); }

  Future<void> _loadContacts() async {
    // Read encrypted value — returns null if key doesn't exist yet
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) {
      setState(() => _contacts = []);
      return;
    }
    // Stored as newline-separated "name|number" entries
    final entries = raw.split('\n').where((e) => e.isNotEmpty).toList();
    setState(() => _contacts = entries.map(_Contact.fromPrefsString).toList());
  }

  Future<void> _saveContacts() async {
    // Primary: join with newline and write as a single encrypted string
    final value = _contacts.map((c) => c.toPrefsString()).join('\n');
    await _storage.write(key: _key, value: value);

    // Mirror: write to sqflite so the background crash-detection isolate
    // can read contact numbers without needing flutter_secure_storage.
    final dbContacts = _contacts
        .map((c) => {'name': c.name, 'number': c.number})
        .toList();
    await ContactsDb.instance.replaceAll(_uid, dbContacts);
  }


  // ── Phone validation ──────────────────────────────────────────────────────
  bool _isValidPhone(String input) {
    final cleaned = input.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    // Only digits and optional leading + allowed
    if (!RegExp(r'^\+?\d+$').hasMatch(cleaned)) return false;
    final digits = cleaned.replaceAll('+', '');
    // Not all same digit (e.g. 9999999999)
    if (RegExp(r'^(\d)\1+$').hasMatch(digits)) return false;

    if (cleaned.startsWith('+')) {
      // International number: 7–15 digits
      if (digits.length < 7 || digits.length > 15) return false;
    } else {
      // Indian number: exactly 10 digits, must start with 6/7/8/9
      if (digits.length != 10) return false;
      if (!RegExp(r'^[6-9]').hasMatch(digits)) return false;
    }
    return true;
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white54),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red)),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 2)),
  );

  void _addContact() {
    final loc = AppLocalizations.of(context);
    String name = '', number = '';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(loc.addEmergencyContact,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration(loc.namePlaceholderLong),
            onChanged: (v) => name = v,
          ),
          const SizedBox(height: 12),
          TextField(
            keyboardType: TextInputType.phone,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration(loc.phoneNumberPlaceholder),
            onChanged: (v) => number = v,
          ),
        ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.cancel, style: const TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () async {
              final trimmed = number.trim();
              if (trimmed.isEmpty) return;

              if (!_isValidPhone(trimmed)) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Enter a valid phone number (e.g. +91 9876543210)'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
                return;
              }
              if (_contacts.length >= 5) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Maximum 5 emergency contacts allowed'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
                return;
              }
              Navigator.pop(context);
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: const Color(0xFF1A1A2E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: const Row(children: [
                    Icon(Icons.person_add_rounded, color: Colors.green, size: 22),
                    SizedBox(width: 10),
                    Text('Save Contact?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ]),
                  content: RichText(
                    text: TextSpan(
                      style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                      children: [
                        const TextSpan(text: 'Add '),
                        TextSpan(text: name.trim().isNotEmpty ? name.trim() : trimmed,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        const TextSpan(text: ' ('),
                        TextSpan(text: trimmed, style: const TextStyle(color: Colors.white70)),
                        const TextSpan(text: ') as an emergency contact?'),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                setState(() => _contacts.add(_Contact(name: name.trim(), number: trimmed)));
                await _saveContacts();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${name.trim().isNotEmpty ? name.trim() : trimmed} added successfully'),
                        backgroundColor: Colors.green, duration: const Duration(seconds: 2)),
                  );
                }
              }
            },
            child: Text(loc.add, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _editContact(int index) {
    final loc = AppLocalizations.of(context);
    final c = _contacts[index];
    final nameCtrl   = TextEditingController(text: c.name);
    final numberCtrl = TextEditingController(text: c.number);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(loc.editContact,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration(loc.namePlaceholderLong)),
          const SizedBox(height: 12),
          TextField(controller: numberCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration(loc.phoneNumberPlaceholder)),
        ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.cancel, style: const TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () async {
              final trimmed = numberCtrl.text.trim();
              if (trimmed.isEmpty) return;

              if (!_isValidPhone(trimmed)) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Enter a valid phone number (e.g. +91 9876543210)'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
                return;
              }
              Navigator.pop(context);
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: const Color(0xFF1A1A2E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: const Row(children: [
                    Icon(Icons.edit_rounded, color: Colors.orange, size: 22),
                    SizedBox(width: 10),
                    Text('Save Changes?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ]),
                  content: RichText(
                    text: TextSpan(
                      style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                      children: [
                        const TextSpan(text: 'Update contact to '),
                        TextSpan(text: nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : trimmed,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        const TextSpan(text: ' ('),
                        TextSpan(text: trimmed, style: const TextStyle(color: Colors.white70)),
                        const TextSpan(text: ')?'),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                setState(() => _contacts[index] =
                    _Contact(name: nameCtrl.text.trim(), number: trimmed));
                await _saveContacts();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Contact updated successfully'),
                        backgroundColor: Colors.orange, duration: Duration(seconds: 2)),
                  );
                }
              }
            },
            child: Text(loc.save, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _deleteContact(int index) async {
    final contact = _contacts[index];
    final displayName = contact.name.isNotEmpty ? contact.name : contact.number;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.delete_rounded, color: Colors.red, size: 22),
          SizedBox(width: 10),
          Text('Delete Contact?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
            children: [
              const TextSpan(text: 'Remove '),
              TextSpan(text: displayName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const TextSpan(text: ' from your emergency contacts?\n\n'),
              const TextSpan(text: 'They will no longer receive SOS alerts.',
                  style: TextStyle(color: Colors.red, fontSize: 13)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() => _contacts.removeAt(index));
      await _saveContacts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$displayName removed from emergency contacts'),
              backgroundColor: Colors.red, duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  Future<void> _callNumber(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(loc.emergencyContactsTitle,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _contacts.isEmpty
          ? Center(child: Text(loc.noContactsAdded,
              style: const TextStyle(color: Colors.white54, fontSize: 16)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _contacts.length,
              itemBuilder: (context, i) {
                final contact = _contacts[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
                    boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.08),
                        blurRadius: 10, spreadRadius: 1)],
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.person, color: Colors.red, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (contact.name.isNotEmpty)
                          Text(contact.name, style: const TextStyle(color: Colors.white,
                              fontSize: 15, fontWeight: FontWeight.bold)),
                        Text(contact.number,
                            style: TextStyle(
                              color: contact.name.isNotEmpty ? Colors.white60 : Colors.white,
                              fontSize: contact.name.isNotEmpty ? 13 : 16,
                              fontWeight: contact.name.isNotEmpty
                                  ? FontWeight.normal : FontWeight.w600,
                            )),
                      ],
                    )),
                    IconButton(icon: const Icon(Icons.edit, color: Colors.orange, size: 20),
                        onPressed: () => _editContact(i), tooltip: loc.editContact),
                    IconButton(icon: const Icon(Icons.call, color: Colors.green),
                        onPressed: () => _callNumber(contact.number), tooltip: loc.call),
                    IconButton(icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteContact(i), tooltip: loc.delete),
                  ]),
                );
              }),
      floatingActionButton: FloatingActionButton(
        onPressed: _addContact,
        backgroundColor: Colors.red,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}