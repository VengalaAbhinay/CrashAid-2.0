import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import 'offline_first_aid_data.dart';
import 'package:flutter/foundation.dart';

class AIFirstAidScreen extends StatefulWidget {
  /// Optional message sent automatically when the screen opens.
  /// Used by crash detection to pre-fill "I was just in a crash…".
  final String? initialMessage;

  const AIFirstAidScreen({super.key, this.initialMessage});

  @override
  State<AIFirstAidScreen> createState() => _AIFirstAidScreenState();
}

class _AIFirstAidScreenState extends State<AIFirstAidScreen>
    with TickerProviderStateMixin {
  // ── API key from .env ──────────────────────────────────────────────────────
  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  // ── State ──────────────────────────────────────────────────────────────────
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = false;
  bool _isOnline = true; // updated before every send

  // Cancellable timer used by _checkConnectivity – cancelled in dispose()
  Timer? _connectivityTimer;

  // ── Animation ──────────────────────────────────────────────────────────────
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // ── Quick-question buttons (12 topics) ────────────────────────────────────
  List<Map<String, String>> _quickQuestions(AppLocalizations loc) => [
        {'emoji': '🩸', 'label': loc.bleedingHeavily},
        {'emoji': '❤️', 'label': loc.heartAttack},
        {'emoji': '🔥', 'label': loc.burnInjury},
        {'emoji': '🦴', 'label': loc.brokenBone},
        {'emoji': '😵', 'label': loc.unconsciousPerson},
        {'emoji': '🐍', 'label': loc.snakeBite},
        {'emoji': '🧠', 'label': loc.strokeEmergency},
        {'emoji': '⚡', 'label': loc.seizureFit},
        {'emoji': '💉', 'label': loc.allergicReaction},
        {'emoji': '🤕', 'label': loc.headInjury},
        {'emoji': '🌡️', 'label': loc.heatStroke},
        {'emoji': '🫁', 'label': loc.choking},
      ];

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Auto-send crash context message if provided (e.g. from crash detection)
    if (widget.initialMessage != null && widget.initialMessage!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) sendMessage(widget.initialMessage);
      });
    }
  }

  @override
  void dispose() {
    // Cancel any pending connectivity timer so it doesn't fire after disposal.
    _connectivityTimer?.cancel();
    _connectivityTimer = null;
    _pulseController.dispose();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<bool> _checkConnectivity() async {
    if (kIsWeb) return _apiKey.isNotEmpty;
    _connectivityTimer?.cancel();
    final completer = Completer<bool>();
    _connectivityTimer = Timer(const Duration(seconds: 5), () {
      if (!completer.isCompleted) completer.complete(false);
    });
    InternetAddress.lookup('google.com').then((result) {
      _connectivityTimer?.cancel();
      _connectivityTimer = null;
      if (!completer.isCompleted) {
        completer.complete(result.isNotEmpty && result[0].rawAddress.isNotEmpty);
      }
    }).catchError((_) {
      _connectivityTimer?.cancel();
      _connectivityTimer = null;
      if (!completer.isCompleted) completer.complete(false);
    });
    return completer.future;
  }
  Future<void> _call112() async {
    final Uri uri = Uri(scheme: 'tel', path: '112');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  // ── Core send logic ────────────────────────────────────────────────────────
Future<void> sendMessage([String? quickText]) async {
  final String text = quickText ?? _controller.text.trim();
  if (text.isEmpty) return;

  String langCode = 'en';
  try {
    langCode = AppLocalizations.of(context).aiSystemPromptLanguage;
  } catch (_) {
    langCode = 'en';
  }

  setState(() {
    _messages.add({'role': 'user', 'text': text});
    _isLoading = true;
  });

  if (quickText == null) _controller.clear();
  _scrollToBottom();

  if (!mounted) return;

  if (kIsWeb) {
    if (_apiKey.isNotEmpty) {
      await _sendOnline(text, langCode);
    } else {
      await _sendOffline(text, langCode);
    }
    return;
  }

  _isOnline = await _checkConnectivity();
  if (!mounted) return;

  if (_isOnline && _apiKey.isNotEmpty) {
    await _sendOnline(text, langCode);
  } else {
    await _sendOffline(text, langCode);
  }
}
  // ── ONLINE path: Gemini 2.5 Flash ─────────────────────────────────────────

  Future<void> _sendOnline(String text, String langCode) async {
    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_apiKey',
      );

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {
                      'text': '''
You are an expert emergency medical assistant and paramedic with 20 years of experience.
Respond in the language: $langCode.
If the language is Kannada, respond entirely in Kannada script (ಕನ್ನಡ).

When someone describes an emergency, respond like a calm, professional doctor giving clear life-saving guidance.

Your response should:
- Start with the most critical action first
- Give numbered step-by-step instructions
- Be specific
- Include what NOT to do
- End with when to call 108/112
- Use simple language
- Be concise (under 200 words)

Do NOT say "I am an AI".

Emergency: $text
'''
                    }
                  ]
                }
              ]
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reply =
            data['candidates'][0]['content']['parts'][0]['text'] as String? ??
                'No response.';
        _setReply(reply);
      } else {
        debugPrint('Gemini API error: status=${response.statusCode}');
        await _sendOffline(text, langCode);
      }
    } catch (e) {
      debugPrint('Gemini API exception: $e');
      await _sendOffline(text, langCode);
    }
  }

  // ── OFFLINE path: local knowledge base ────────────────────────────────────
  void _setReply(String text, {bool fromOffline = false}) {
    if (!mounted) return;
    setState(() {
      _messages.add({
        'role': 'assistant',
        'text': text,
        'offline': fromOffline ? 'true' : 'false',
      });
      _isLoading = false;
    });
    _scrollToBottom();
  }

  String _langNameToCode(String langCode) {
    const map = <String, String>{
      'en': 'en', 'english': 'en',
      'hi': 'hi', 'hindi': 'hi',
      'ta': 'ta', 'tamil': 'ta',
      'te': 'te', 'telugu': 'te',
      'kn': 'kn', 'kannada': 'kn',
      'ml': 'ml', 'malayalam': 'ml',
      'mr': 'mr', 'marathi': 'mr',
      'bn': 'bn', 'bengali': 'bn',
      'gu': 'gu', 'gujarati': 'gu',
      'pa': 'pa', 'punjabi': 'pa',
    };
    return map[langCode.toLowerCase()] ?? 'en';
  }

Future<void> _sendOffline(String text, String langCode) async {
  await Future.delayed(const Duration(milliseconds: 400));
  if (!mounted) return;

  final code = _langNameToCode(langCode);

  // Try matching with original text first
  String answer = OfflineFirstAidData.find(query: text, langCode: code);

  // If no specific match found, try with English keywords mapped from quick buttons
  final genericAnswer = OfflineFirstAidData.find(query: '', langCode: code);
  if (answer == genericAnswer || answer.isEmpty) {
    final englishQuery = _mapToEnglishKeyword(text);
    if (englishQuery.isNotEmpty) {
      answer = OfflineFirstAidData.find(query: englishQuery, langCode: code);
    }
  }

  _setReply(answer, fromOffline: true);
}

String _mapToEnglishKeyword(String localizedText) {
  const Map<String, String> map = {
    // Kannada
    'ರಕ್ತಸ್ರಾವ': 'bleeding',
    'ಹೃದಯಾಘಾತ': 'heart attack',
    'ಸುಟ್ಟ': 'burn',
    'ಮೂಳೆ ಮುರಿತ': 'fracture',
    'ಪ್ರಜ್ಞೆ': 'unconscious',
    'ಹಾವು': 'snake',
    'ಪಾರ್ಶ್ವವಾಯು': 'stroke',
    'ಅಪಸ್ಮಾರ': 'seizure',
    'ಅಲರ್ಜಿ': 'allergy',
    'ತಲೆ ಗಾಯ': 'head injury',
    'ಶಾಖಾಘಾತ': 'heat stroke',
    'ಗಂಟಲು': 'choking',
    // Hindi
    'खून': 'bleeding',
    'दिल': 'heart attack',
    'जला': 'burn',
    'हड्डी': 'fracture',
    'बेहोश': 'unconscious',
    'सांप': 'snake',
    'स्ट्रोक': 'stroke',
    'दौरा': 'seizure',
    'एलर्जी': 'allergy',
    'गर्मी': 'heat stroke',
    'दम': 'choking',
    // Telugu
    'రక్తం': 'bleeding',
    'గుండె': 'heart attack',
    'కాలిన': 'burn',
    'ఎముక': 'fracture',
    'స్పృహ': 'unconscious',
    'పాము': 'snake',
    'స్ట్రోక్': 'stroke',
    'మూర్ఛ': 'seizure',
    'అలెర్జీ': 'allergy',
    'హీట్': 'heat stroke',
    'గొంతు': 'choking',
  };

  for (final entry in map.entries) {
    if (localizedText.contains(entry.key)) {
      return entry.value;
    }
  }
  return '';
}
  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFF0A0A0F),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _messages.isEmpty
                  ? _buildWelcomeScreen()
                  : _buildMessageList(),
            ),
            if (_isLoading) _buildTypingIndicator(),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final bool online = _isOnline && _apiKey.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A0A0A), Color(0xFF2D0F0F)],
        ),
        border: Border(
          bottom: BorderSide(color: Color(0xFFFF3B3B), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // ── Back button ───────────────────────────────────────────────────
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.arrow_back_ios_new,
                  color: Colors.white, size: 16),
            ),
          ),

          const SizedBox(width: 8),

          // ── Pulsing icon ──────────────────────────────────────────────────
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFF6B6B), Color(0xFFFF3B3B)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.health_and_safety,
                  color: Colors.white, size: 20),
            ),
          ),

          const SizedBox(width: 10),

          // ── Title + status ────────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'AI First Aid',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 3,
                      backgroundColor:
                          online ? const Color(0xFF00FF88) : const Color(0xFFFF9500),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        online ? 'Emergency Assistant • Online' : 'Emergency Assistant • Offline AI',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: online
                              ? const Color(0xFF00FF88)
                              : const Color(0xFFFF9500),
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 6),

          // ── Call 112 button ───────────────────────────────────────────────
          GestureDetector(
            onTap: _call112,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFF3B3B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.call, color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text('112',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Welcome / quick questions ──────────────────────────────────────────────

  Widget _buildWelcomeScreen() {
    final loc = AppLocalizations.of(context);
    final questions = _quickQuestions(loc);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          children: [
            const SizedBox(height: 10),

            // ── Icon ───────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF3B3B).withValues(alpha: 0.1),
              ),
              child: const Icon(Icons.medical_services_rounded,
                  color: Color(0xFFFF6B6B), size: 44),
            ),

            const SizedBox(height: 14),

            Text(
              loc.aiFirstAidBannerTitle,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 6),

            Text(
              loc.aiFirstAidBannerSubtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFF888888), fontSize: 13, height: 1.5),
            ),

            const SizedBox(height: 24),

            // ── Section label ──────────────────────────────────────────────
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Quick Options',
                style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),

            const SizedBox(height: 10),

            // ── 2-column grid of 12 quick buttons ─────────────────────────
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 2.8,
              children: questions.map((q) {
                return GestureDetector(
                  onTap: () => sendMessage(q['label']),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFFF3B3B).withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(q['emoji']!, style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            q['label']!,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // ── Disclaimer ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFF3B3B).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFFFF3B3B).withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Color(0xFFFF6B6B), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      loc.aiDisclaimer,
                      style: const TextStyle(
                          color: Color(0xFF888888), fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Message list ───────────────────────────────────────────────────────────

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final isUser = msg['role'] == 'user';
        final wasOffline = msg['offline'] == 'true';
        return _buildMessageBubble(msg['text'] ?? '', isUser, wasOffline);
      },
    );
  }

  // ── Message bubble ─────────────────────────────────────────────────────────

  Widget _buildMessageBubble(String text, bool isUser, bool wasOffline) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── AI avatar ─────────────────────────────────────────────────────
          if (!isUser) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFF6B6B), Color(0xFFFF3B3B)]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.health_and_safety,
                  color: Colors.white, size: 16),
            ),
            const SizedBox(width: 8),
          ],

          // ── Bubble ────────────────────────────────────────────────────────
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isUser
                        ? const Color(0xFFFF3B3B)
                        : const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    text,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14, height: 1.6),
                  ),
                ),
                // ── Offline badge ─────────────────────────────────────────
                if (!isUser && wasOffline) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off,
                          size: 10, color: Color(0xFFFF9500)),
                      const SizedBox(width: 3),
                      const Text(
                        'Offline AI',
                        style: TextStyle(
                            color: Color(0xFFFF9500), fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // ── User avatar ───────────────────────────────────────────────────
          if (isUser) ...[
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A3E),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.person, color: Colors.white54, size: 16),
            ),
          ],
        ],
      ),
    );
  }

  // ── Typing indicator ───────────────────────────────────────────────────────

  Widget _buildTypingIndicator() {
    return const Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: CircularProgressIndicator(color: Color(0xFFFF3B3B)),
    );
  }

  // ── Input bar ──────────────────────────────────────────────────────────────

  Widget _buildInputBar() {
    final loc = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1A),
        border: Border(
          top: BorderSide(color: const Color(0xFFFF3B3B).withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          // ── Text field ────────────────────────────────────────────────────
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: const Color(0xFFFF3B3B).withValues(alpha: 0.2)),
              ),
              child: TextField(
                controller: _controller,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => sendMessage(),
                decoration: InputDecoration(
                  hintText: loc.typeSymptomOrInjury,
                  hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3), fontSize: 14),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // ── Send button ───────────────────────────────────────────────────
          GestureDetector(
            onTap: _isLoading ? null : () => sendMessage(),
            child: Container(
              padding: const EdgeInsets.all(13),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [Color(0xFFFF6B6B), Color(0xFFFF3B3B)]),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isLoading ? Icons.hourglass_top : Icons.send_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}