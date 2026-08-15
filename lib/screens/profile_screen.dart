import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:crashaid/l10n/app_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProfileScreen extends StatefulWidget {
  final String? email;
  const ProfileScreen({super.key, this.email});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController      = TextEditingController();
  final _ageController       = TextEditingController();
  final _phoneController     = TextEditingController();
  final _allergyController   = TextEditingController();
  final _conditionController = TextEditingController();

  String? _selectedBlood;
  String? _selectedGender;
  bool _isEditing = false;
  bool _isLoading = true;
  File? _profileImage;
  final _picker = ImagePicker();

  static const _bloodGroups = ['A+','A-','B+','B-','AB+','AB-','O+','O-'];

  // Stored keys (language-neutral) — display is localized via _localizedGenderLabel()
  static const _genderKeys = ['Male', 'Female', 'Other', 'Prefer not to say'];

  List<String> _genderLabels(AppLocalizations loc) => [
    loc.get('genderMale'),
    loc.get('genderFemale'),
    loc.get('genderOther'),
    loc.get('genderPreferNot'),
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _phoneController.dispose();
    _allergyController.dispose();
    _conditionController.dispose();
    super.dispose();
  }

  // ── Load ───────────────────────────────────────────────────
  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final imgPath = prefs.getString('profile_image');
    setState(() {
      _nameController.text      = prefs.getString('name')      ?? '';
      _ageController.text       = prefs.getString('age')       ?? '';
      _phoneController.text     = prefs.getString('phone')     ?? '';
      _selectedBlood            = prefs.getString('blood');
      _selectedGender           = prefs.getString('gender');
      _allergyController.text   = prefs.getString('allergy')   ?? '';
      _conditionController.text = prefs.getString('condition') ?? '';
      if (imgPath != null && File(imgPath).existsSync()) {
        _profileImage = File(imgPath);
      }
      _isLoading = false;
    });
  }

  // ── Save ───────────────────────────────────────────────────
  Future<void> _saveProfile() async {
    final loc = AppLocalizations.of(context);
    if (_nameController.text.trim().isEmpty) {
      _snack(loc.get('profileEnterName'), Colors.orange);
      return;
    }
    if (_ageController.text.trim().isEmpty) {
      _snack(loc.get('profileEnterAge'), Colors.orange);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('name',      _nameController.text.trim());
    await prefs.setString('age',       _ageController.text.trim());
    await prefs.setString('phone',     _phoneController.text.trim());
    await prefs.setString('blood',     _selectedBlood  ?? '');
    await prefs.setString('gender',    _selectedGender ?? '');
    await prefs.setString('allergy',   _allergyController.text.trim());
    await prefs.setString('condition', _conditionController.text.trim());
    if (_profileImage != null) {
      await prefs.setString('profile_image', _profileImage!.path);
    }
    setState(() => _isEditing = false);
    _snack(loc.profileSaved, Colors.green);
  }

  // ── Delete all profile data ────────────────────────────────
  Future<void> _deleteProfile() async {
    final loc = AppLocalizations.of(context);
    Navigator.of(context).pop();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('name');
    await prefs.remove('age');
    await prefs.remove('phone');
    await prefs.remove('blood');
    await prefs.remove('gender');
    await prefs.remove('allergy');
    await prefs.remove('condition');
    await prefs.remove('profile_image');

    setState(() {
      _nameController.clear();
      _ageController.clear();
      _phoneController.clear();
      _selectedBlood  = null;
      _selectedGender = null;
      _allergyController.clear();
      _conditionController.clear();
      _profileImage   = null;
      _isEditing      = false;
    });

    _snack(loc.get('profileDeleted'), Colors.red);
  }

  // ── Delete confirmation dialog ─────────────────────────────
  void _showDeleteDialog() {
    final loc = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
            const SizedBox(width: 10),
            Text(loc.get('deleteProfileTitle'),
                style: const TextStyle(color: Colors.white, fontSize: 17)),
          ],
        ),
        content: Text(
          loc.get('deleteProfileMsg'),
          style: const TextStyle(color: Colors.white60, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(loc.cancel,
                style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _deleteProfile,
            child: Text(loc.delete,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Image picker bottom sheet ──────────────────────────────
  void _showImageSheet() {
    final loc = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C28),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(loc.get('profilePhoto'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _imageOption(
                      icon: Icons.camera_alt_rounded,
                      label: loc.get('camera'),
                      color: Colors.redAccent,
                      onTap: () {
                        Navigator.pop(context);
                        _pickImage(ImageSource.camera);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _imageOption(
                      icon: Icons.photo_library_rounded,
                      label: loc.get('gallery'),
                      color: Colors.white70,
                      onTap: () {
                        Navigator.pop(context);
                        _pickImage(ImageSource.gallery);
                      },
                    ),
                  ),
                  if (_profileImage != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: _imageOption(
                        icon: Icons.delete_outline_rounded,
                        label: loc.get('removePhoto'),
                        color: Colors.orange,
                        onTap: () {
                          Navigator.pop(context);
                          _removePhoto();
                        },
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imageOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final loc = AppLocalizations.of(context);
    try {
      final picked = await _picker.pickImage(
          source: source, imageQuality: 80, maxWidth: 512, maxHeight: 512);
      if (picked != null) {
        setState(() => _profileImage = File(picked.path));
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('profile_image', picked.path);
      }
    } catch (e) {
      _snack('${loc.get("couldNotPickImage")}: $e', Colors.red);
    }
  }

  Future<void> _removePhoto() async {
    final loc = AppLocalizations.of(context);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('profile_image');
    setState(() => _profileImage = null);
    _snack(loc.get('photoRemoved'), Colors.orange);
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  String get _currentUserEmail {
    try {
      return FirebaseAuth.instance.currentUser?.email ?? '';
    } catch (_) {
      return '';
    }
  }

  String get _initials {
    final parts = _nameController.text.trim()
        .split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts.last[0]).toUpperCase();
  }

  double get _completion {
    int n = 0;
    if (_nameController.text.trim().isNotEmpty) n++;
    if (_ageController.text.trim().isNotEmpty) n++;
    if (_phoneController.text.trim().isNotEmpty) n++;
    if (_selectedBlood  != null && _selectedBlood!.isNotEmpty)  n++;
    if (_selectedGender != null && _selectedGender!.isNotEmpty) n++;
    if (_allergyController.text.trim().isNotEmpty)   n++;
    if (_conditionController.text.trim().isNotEmpty) n++;
    return n / 7;
  }

  // ── Text field ─────────────────────────────────────────────
  Widget _field({
    required String label,
    required TextEditingController controller,
    TextInputType keyboard = TextInputType.text,
    List<TextInputFormatter>? formatters,
    int maxLines = 1,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        enabled: _isEditing,
        keyboardType: keyboard,
        inputFormatters: formatters,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
          prefixIcon: icon != null
              ? Icon(icon, color: Colors.white38, size: 18)
              : null,
          filled: true,
          fillColor: _isEditing
              ? const Color(0xFF1C1C28)
              : const Color(0xFF13131A),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF2E2E3E)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF1A1A24)),
          ),
        ),
      ),
    );
  }

  // ── Generic dropdown (blood group) ────────────────────────
  Widget _dropdown({
    required String label,
    required String? value,
    required List<String> items,
    required void Function(String?) onChanged,
    IconData? icon,
  }) {
    final loc = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        value: value,
        dropdownColor: const Color(0xFF1C1C28),
        style: const TextStyle(color: Colors.white, fontSize: 15),
        iconEnabledColor: Colors.white54,
        iconDisabledColor: const Color(0xFF3E3E4E),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
          prefixIcon: icon != null
              ? Icon(icon, color: Colors.white38, size: 18)
              : null,
          filled: true,
          fillColor: _isEditing
              ? const Color(0xFF1C1C28)
              : const Color(0xFF13131A),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF2E2E3E)),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF1A1A24)),
          ),
        ),
        hint: Text(loc.get('select'),
            style: const TextStyle(color: Colors.white30)),
        selectedItemBuilder: (context) => items
            .map((b) => Text(b,
                style: const TextStyle(color: Colors.white, fontSize: 15)))
            .toList(),
        items: items
            .map((b) => DropdownMenuItem(value: b, child: Text(b)))
            .toList(),
        onChanged: _isEditing ? onChanged : null,
      ),
    );
  }

  // ── Gender dropdown — shows localized label, stores English key ──
  Widget _genderDropdown(AppLocalizations loc) {
    final labels = _genderLabels(loc);

    // Map the saved English key → localized display string
    String? displayValue;
    if (_selectedGender != null && _selectedGender!.isNotEmpty) {
      final idx = _genderKeys.indexOf(_selectedGender!);
      if (idx >= 0) displayValue = labels[idx];
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        value: displayValue,
        dropdownColor: const Color(0xFF1C1C28),
        style: const TextStyle(color: Colors.white, fontSize: 15),
        iconEnabledColor: Colors.white54,
        iconDisabledColor: const Color(0xFF3E3E4E),
        decoration: InputDecoration(
          labelText: loc.get('gender'),
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
          prefixIcon: const Icon(Icons.wc_rounded, color: Colors.white38, size: 18),
          filled: true,
          fillColor: _isEditing
              ? const Color(0xFF1C1C28)
              : const Color(0xFF13131A),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF2E2E3E)),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF1A1A24)),
          ),
        ),
        hint: Text(loc.get('select'),
            style: const TextStyle(color: Colors.white30)),
        selectedItemBuilder: (context) => labels
            .map((l) => Text(l,
                style: const TextStyle(color: Colors.white, fontSize: 15)))
            .toList(),
        items: labels
            .map((l) => DropdownMenuItem(value: l, child: Text(l)))
            .toList(),
        onChanged: _isEditing
            ? (localizedLabel) {
                if (localizedLabel == null) return;
                final idx = labels.indexOf(localizedLabel);
                setState(() =>
                    _selectedGender = idx >= 0 ? _genderKeys[idx] : localizedLabel);
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final pct = (_completion * 100).round();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.redAccent))
            : Column(
                children: [

                  // ── Header row ─────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
                    child: Row(
                      children: [
                        // ← Back
                        IconButton(
                          icon: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: Colors.white,
                              size: 20),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        // Title
                        Expanded(
                          child: Text(
                            loc.medicalProfile,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        // 🗑 Delete button
                        GestureDetector(
                          onTap: _showDeleteDialog,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: Colors.red.withValues(alpha: 0.35),
                                  width: 1),
                            ),
                            child: const Icon(Icons.delete_outline_rounded,
                                color: Colors.redAccent, size: 18),
                          ),
                        ),
                        // ✏ Edit / ✕ Cancel
                        GestureDetector(
                          onTap: () {
                            if (_isEditing) _loadProfile();
                            setState(() => _isEditing = !_isEditing);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: _isEditing
                                  ? Colors.redAccent.withValues(alpha: 0.15)
                                  : Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _isEditing
                                    ? Colors.redAccent
                                    : Colors.white38,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _isEditing
                                      ? Icons.close_rounded
                                      : Icons.edit_rounded,
                                  color: _isEditing
                                      ? Colors.redAccent
                                      : Colors.white,
                                  size: 15,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _isEditing ? loc.cancel : loc.get('edit'),
                                  style: TextStyle(
                                    color: _isEditing
                                        ? Colors.redAccent
                                        : Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Scrollable body ────────────────────────────
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [

                          Center(
                            child: Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.bottomRight,
                              children: [
                                Container(
                                  width: 92,
                                  height: 92,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.redAccent.withValues(alpha: 0.15),
                                    border: Border.all(
                                        color: Colors.redAccent.withValues(alpha: 0.5),
                                        width: 2),
                                  ),
                                  alignment: Alignment.center,
                                  child: _profileImage != null
                                      ? ClipOval(
                                          child: Image.file(
                                            _profileImage!,
                                            fit: BoxFit.cover,
                                            width: 92,
                                            height: 92,
                                          ),
                                        )
                                      : Text(
                                          _initials,
                                          style: const TextStyle(
                                            fontSize: 30,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                ),
                                if (_isEditing)
                                  Positioned(
                                    bottom: -4,
                                    right: -4,
                                    child: GestureDetector(
                                      onTap: _showImageSheet,
                                      child: Container(
                                        padding: const EdgeInsets.all(7),
                                        decoration: BoxDecoration(
                                          color: Colors.redAccent,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: const Color(0xFF0A0A0F),
                                              width: 2),
                                        ),
                                        child: const Icon(
                                            Icons.camera_alt_rounded,
                                            size: 15,
                                            color: Colors.white),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 12),

                          // ── Logged-in email ────────────────────
                          Center(
                            child: Text(
                              widget.email ?? _currentUserEmail,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(loc.get('profileCompletion'),
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 12)),
                              Text('$pct%',
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: _completion,
                              minHeight: 5,
                              backgroundColor: Colors.white10,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  Colors.redAccent),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // ── Personal Info ──────────────────────
                          Text(loc.get('personalInfo'),
                              style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 10,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 10),

                          _field(
                            label: loc.fullName,
                            controller: _nameController,
                            icon: Icons.person_outline_rounded,
                          ),
                          _field(
                            label: loc.age,
                            controller: _ageController,
                            keyboard: TextInputType.number,
                            formatters: [FilteringTextInputFormatter.digitsOnly],
                            icon: Icons.cake_outlined,
                          ),
                          _field(
                            label: loc.phoneNumber,
                            controller: _phoneController,
                            keyboard: TextInputType.phone,
                            formatters: [FilteringTextInputFormatter.digitsOnly],
                            icon: Icons.phone_outlined,
                          ),
                          _genderDropdown(loc),

                          const SizedBox(height: 4),

                          // ── Medical Info ───────────────────────
                          Text(loc.get('medicalInfo'),
                              style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 10,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 10),

                          _dropdown(
                            label: loc.bloodGroup,
                            value: _selectedBlood,
                            items: _bloodGroups,
                            icon: Icons.water_drop_outlined,
                            onChanged: (v) =>
                                setState(() => _selectedBlood = v),
                          ),
                          _field(
                            label: loc.allergies,
                            controller: _allergyController,
                            maxLines: 2,
                            icon: Icons.warning_amber_outlined,
                          ),
                          _field(
                            label: loc.medicalConditions,
                            controller: _conditionController,
                            maxLines: 2,
                            icon: Icons.medical_information_outlined,
                          ),

                          const SizedBox(height: 16),

                          // Save button — only in edit mode
                          if (_isEditing)
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(14)),
                                  elevation: 0,
                                ),
                                icon: const Icon(Icons.save_rounded,
                                    color: Colors.white, size: 18),
                                label: Text(
                                  loc.saveProfile,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600),
                                ),
                                onPressed: _saveProfile,
                              ),
                            ),

                          // Delete button — always visible at bottom
                          if (!_isEditing) ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                      color: Colors.redAccent, width: 1),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(14)),
                                ),
                                icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Colors.redAccent,
                                    size: 18),
                                label: Text(
                                  loc.get('deleteProfile'),
                                  style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600),
                                ),
                                onPressed: _showDeleteDialog,
                              ),
                            ),
                          ],

                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}