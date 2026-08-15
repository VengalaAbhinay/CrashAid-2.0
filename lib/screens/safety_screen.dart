import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import 'contacts_screen.dart';
import 'medical_screen.dart';

class SafetyScreen extends StatelessWidget {
  const SafetyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(loc.safetyTitle,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(children: [
          _topBanner(loc),
          _safetyCard(context, loc.policeStations, loc.policeStationsSub,
              Icons.local_police_rounded, const Color(0xFF3B6FFF), const Color(0xFF0A0F2D),
              onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => NearbyPlacesScreen(
                      label: loc.policeStations,
                      osmKey: "amenity", osmValue: "police",
                      accentColor: const Color(0xFF3B6FFF))))),
          _safetyCard(context, loc.womenSafety, loc.womenSafetySub,
              Icons.shield_rounded, const Color(0xFFFF3B9A), const Color(0xFF2D0A1A),
              onTap: () => _callNumber("1091")),
          _safetyCard(context, loc.emergencyContacts, loc.emergencyContactsSub,
              Icons.contacts_rounded, const Color(0xFF00C851), const Color(0xFF0A2D16),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ContactsScreen()))),
          _safetyCard(context, loc.helplineNumbers, loc.helplineNumbersSub,
              Icons.phone_in_talk_rounded, const Color(0xFFFF8C3B), const Color(0xFF2D1A0A),
              onTap: () => _showHelplineDialog(context, loc)),
          const SizedBox(height: 30),
        ]),
      ),
    );
  }

  Widget _topBanner(AppLocalizations loc) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF0A0F2D), Color(0xFF05050F)]),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF3B6FFF).withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(color: const Color(0xFF3B6FFF).withValues(alpha: 0.15),
            blurRadius: 20, spreadRadius: 2)],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: const Color(0xFF3B6FFF).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.shield_rounded, color: Color(0xFF3B6FFF), size: 40),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(loc.safetyBannerTitle,
              style: const TextStyle(color: Colors.white, fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(loc.safetyBannerSubtitle,
              style: const TextStyle(color: Color(0xFF888888), fontSize: 12, height: 1.4)),
        ])),
      ]),
    );
  }

  Widget _safetyCard(BuildContext context, String title, String subtitle,
      IconData icon, Color color, Color bg, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.25)),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 10, spreadRadius: 1)],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.white,
                fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 3),
            Text(subtitle, style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
          ])),
          Icon(Icons.arrow_forward_ios, color: color, size: 16),
        ]),
      ),
    );
  }

  Future<void> _callNumber(String number) async {
    final Uri uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _showHelplineDialog(BuildContext context, AppLocalizations loc) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF3B6FFF).withValues(alpha: 0.3))),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(loc.helplineNumbers,
                      style: const TextStyle(color: Colors.white, fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  _helplineTile(context, loc.helplinePolice,          "100",  const Color(0xFF3B6FFF)),
                  _helplineTile(context, loc.helplineAmbulance,        "108",  const Color(0xFFFF3B3B)),
                  _helplineTile(context, loc.helplineFire,             "101",  const Color(0xFFFF8C3B)),
                  _helplineTile(context, loc.helplineWomen,            "1091", const Color(0xFFFF3B9A)),
                  _helplineTile(context, loc.helplineNationalEmergency,"112",  const Color(0xFFFF3B3B)),
                  _helplineTile(context, loc.helplineDisasterMgmt,     "1078", const Color(0xFFFF8C3B)),
                  _helplineTile(context, loc.helplineChildHelpline,    "1098", const Color(0xFF00C851)),
                ]),
          ),
        ),
      ),
    );
  }

  Widget _helplineTile(BuildContext context, String title, String number, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Colors.white,
              fontSize: 14, fontWeight: FontWeight.w600)),
          Text(number, style: TextStyle(color: color,
              fontSize: 13, fontWeight: FontWeight.bold)),
        ])),
        GestureDetector(
          onTap: () => _callNumber(number),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.call, color: color, size: 18),
          ),
        ),
      ]),
    );
  }
}