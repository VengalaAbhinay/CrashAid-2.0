import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MissingPersonScreen
///
/// Allows users to file a missing person report with:
/// - Photo upload (camera or gallery)
/// - Personal details (name, age, gender, description)
/// - Last known location (auto-fetched or manual)
/// - Reporter contact info
///
/// Reports are stored in Firestore under 'missing_persons' collection
/// and visible on the Admin dashboard.
class MissingPersonScreen extends StatefulWidget {
  const MissingPersonScreen({super.key});

  @override
  State<MissingPersonScreen> createState() => _MissingPersonScreenState();
}

class _MissingPersonScreenState extends State<MissingPersonScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();

  String _gender = 'Female';
  String _relation = 'Parent';
  XFile? _photo;
  bool _submitting = false;
  bool _locationLoading = false;
  double? _lat, _lng;

  static const _bg = Color(0xFF0A0A0F);
  static const _card = Color(0xFF13131A);
  static const _purple = Color(0xFF7B5CFA);
  static const _border = Color(0xFF2A2A3A);

  @override
  void initState() {
    super.initState();
    _prefillReporter();
  }

  Future<void> _prefillReporter() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('phone') ?? '';
    if (phone.isNotEmpty) _contactCtrl.text = phone;
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
        source: source, maxWidth: 800, imageQuality: 80);
    if (file != null) setState(() => _photo = file);
  }

  Future<void> _fetchLocation() async {
    setState(() => _locationLoading = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        _showSnack('Location permission denied');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      _lat = pos.latitude;
      _lng = pos.longitude;
      _locationCtrl.text =
          'Lat: ${pos.latitude.toStringAsFixed(5)}, Lng: ${pos.longitude.toStringAsFixed(5)}';
    } catch (e) {
      _showSnack('Could not fetch location');
    } finally {
      setState(() => _locationLoading = false);
    }
  }

  Future<String?> _uploadPhoto(String docId) async {
    if (_photo == null) return null;
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('missing_persons/$docId/photo.jpg');
      await ref.putFile(File(_photo!.path));
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('Photo upload failed: $e');
      return null;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    HapticFeedback.mediumImpact();

    try {
      final user = FirebaseAuth.instance.currentUser;
      final prefs = await SharedPreferences.getInstance();
      final reporterName = prefs.getString('name') ?? user?.displayName ?? 'Anonymous';

      // Create Firestore document first to get the ID
      final docRef =
          FirebaseFirestore.instance.collection('missing_persons').doc();

      // Upload photo if selected
      final photoUrl = await _uploadPhoto(docRef.id);

      await docRef.set({
        'id': docRef.id,
        'name': _nameCtrl.text.trim(),
        'age': int.tryParse(_ageCtrl.text) ?? 0,
        'gender': _gender,
        'description': _descCtrl.text.trim(),
        'lastSeenLocation': _locationCtrl.text.trim(),
        'lastSeenLat': _lat,
        'lastSeenLng': _lng,
        'photoUrl': photoUrl,
        'reporterContact': _contactCtrl.text.trim(),
        'reporterName': reporterName,
        'reporterRelation': _relation,
        'reportedBy': user?.uid ?? 'anonymous',
        'status': 'Active', // Active | Found | Closed
        'reportedAt': FieldValue.serverTimestamp(),
        'resolvedAt': null,
      });

      if (mounted) {
        _showSuccessDialog(docRef.id);
      }
    } catch (e) {
      _showSnack('Submission failed. Please try again.');
      debugPrint('Missing person submit error: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: _purple));
  }

  void _showSuccessDialog(String caseId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Column(children: [
          Icon(Icons.check_circle_rounded, color: Color(0xFF4ADE80), size: 56),
          SizedBox(height: 12),
          Text('Report Filed',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Your missing person report has been submitted to the police dashboard.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _purple.withOpacity(0.4)),
              ),
              child: Column(
                children: [
                  const Text('Case ID',
                      style: TextStyle(color: Colors.white54, fontSize: 11)),
                  const SizedBox(height: 4),
                  Text(caseId.substring(0, 12).toUpperCase(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          fontSize: 15)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _purple,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                Navigator.of(context).pop(); // close dialog
                Navigator.of(context).pop(); // go back
              },
              child: const Text('Done',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('🔍 Missing Person Report',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Alert banner
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3B3B).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFFFF3B3B).withOpacity(0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: Color(0xFFFF3B3B), size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Report will be instantly shared with Prakasam Police. Provide as much detail as possible.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Photo upload
              _sectionLabel('Photo of Missing Person'),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: _showPhotoOptions,
                child: Container(
                  height: 140,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: _photo != null
                            ? _purple
                            : _border,
                        width: 2),
                  ),
                  child: _photo != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.file(File(_photo!.path),
                              fit: BoxFit.cover, width: double.infinity))
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo_rounded,
                                color: Colors.white38, size: 36),
                            SizedBox(height: 8),
                            Text('Tap to upload photo',
                                style: TextStyle(
                                    color: Colors.white38, fontSize: 13)),
                            Text('(Camera or Gallery)',
                                style: TextStyle(
                                    color: Colors.white24, fontSize: 11)),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 24),

              // Personal Details
              _sectionLabel('Missing Person Details'),
              const SizedBox(height: 12),
              _field(_nameCtrl, 'Full Name *', Icons.person_outline,
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Name is required' : null),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  flex: 2,
                  child: _field(_ageCtrl, 'Age *', Icons.cake_outlined,
                      keyboardType: TextInputType.number,
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Required' : null),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: _dropdownField(
                    label: 'Gender',
                    value: _gender,
                    items: ['Female', 'Male', 'Child (Girl)', 'Child (Boy)', 'Other'],
                    onChanged: (v) => setState(() => _gender = v!),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              _field(_descCtrl, 'Physical Description *', Icons.description_outlined,
                  maxLines: 3,
                  hint: 'Height, skin tone, clothing last seen wearing...',
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Description is required' : null),
              const SizedBox(height: 24),

              // Last seen location
              _sectionLabel('Last Known Location'),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: _field(
                      _locationCtrl, 'Location / Area *', Icons.location_on_outlined,
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Location required' : null),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _fetchLocation,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _purple.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _purple.withOpacity(0.4)),
                    ),
                    child: _locationLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.my_location_rounded,
                            color: Colors.white, size: 22),
                  ),
                ),
              ]),
              const SizedBox(height: 24),

              // Reporter info
              _sectionLabel('Your Information'),
              const SizedBox(height: 12),
              _dropdownField(
                label: 'Relation to Missing Person',
                value: _relation,
                items: ['Parent', 'Sibling', 'Spouse', 'Relative', 'Neighbor', 'Other'],
                onChanged: (v) => setState(() => _relation = v!),
              ),
              const SizedBox(height: 12),
              _field(_contactCtrl, 'Your Contact Number *', Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Contact number required' : null),
              const SizedBox(height: 32),

              // Submit button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF3B3B),
                    disabledBackgroundColor:
                        const Color(0xFFFF3B3B).withOpacity(0.4),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _submitting
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white)),
                            SizedBox(width: 12),
                            Text('Submitting to Police...',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                          ],
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.send_rounded,
                                color: Colors.white, size: 20),
                            SizedBox(width: 10),
                            Text('SUBMIT REPORT TO POLICE',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5)),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Upload Photo',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _photoOption(Icons.camera_alt_rounded, 'Camera', () {
                    Navigator.pop(context);
                    _pickPhoto(ImageSource.camera);
                  }),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _photoOption(
                      Icons.photo_library_rounded, 'Gallery', () {
                    Navigator.pop(context);
                    _pickPhoto(ImageSource.gallery);
                  }),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _photoOption(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: _purple.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _purple.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: _purple, size: 32),
            const SizedBox(height: 8),
            Text(label,
                style: const TextStyle(
                    color: Colors.white70, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
            color: Color(0xFF7B5CFA),
            fontWeight: FontWeight.bold,
            fontSize: 13,
            letterSpacing: 0.5),
      );

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    int maxLines = 1,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
        labelStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        filled: true,
        fillColor: _card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _purple, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFFFF3B3B), width: 1.5),
        ),
      ),
    );
  }

  Widget _dropdownField({
    required String label,
    required String value,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      onChanged: onChanged,
      dropdownColor: _card,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: _card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _purple, width: 1.5),
        ),
      ),
      items: items
          .map((e) => DropdownMenuItem(
              value: e,
              child: Text(e, style: const TextStyle(color: Colors.white))))
          .toList(),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }
}