# CrashAid 🚨

An AI-powered crash detection and emergency response app built with Flutter and Firebase. Automatically detects vehicle crashes, sends SOS alerts to emergency contacts, shares live GPS location, and provides AI-guided first aid — all running in the background even when the app is closed.

---

## Features

| Feature | Description |
|---|---|
| 🔴 **Auto Crash Detection** | Accelerometer-based detection with 10-second cancel window |
| 📍 **Live GPS Tracking** | Real-time location shared with emergency contacts |
| 🤖 **AI First Aid** | Gemini-powered guidance with offline fallback |
| 📱 **Multi-channel SOS** | SMS, WhatsApp, email, or all three simultaneously |
| 🎙️ **Voice Trigger** | "Help", "SOS", "emergency", "bachao" keywords |
| 🗺️ **Offline Hospital Map** | 27,000+ locations pre-loaded in SQLite (no internet needed) |
| 🔐 **Secure Contacts** | AES-encrypted emergency contacts via FlutterSecureStorage |
| 🌐 **Admin Dashboard** | Web-based incident management with role-based access |
| 🌍 **Multi-language** | Full i18n support with locale persistence |
| 🔋 **Background Service** | Flutter Foreground Task keeps detection alive when app is closed |

---

## Tech Stack

### Framework & Language
- **Flutter 3.0+** / **Dart 3.0+**

### State Management
- **Flutter Riverpod** — locale, SOS state, crash detection, alert channel providers

### Backend & Cloud
- **Firebase Auth** — Email, Google Sign-in, Phone OTP
- **Firebase Realtime Database** — Live tracking breadcrumbs
- **Cloud Firestore** — SOS sessions, admin dashboard data
- **Firebase Hosting** — Web admin panel + live tracking viewer

### Local Storage
- **sqflite** — Emergency contacts mirror, OSM places database
- **flutter_secure_storage** — AES-encrypted contacts (Keychain on iOS)
- **shared_preferences** — App settings, locale, alert channel preference

### Sensors & Location
- **sensors_plus** — Accelerometer data for crash detection
- **geolocator** — GPS location
- **flutter_map** + **latlong2** — OpenStreetMap integration

### Other
- **flutter_foreground_task** — Background crash monitoring service
- **permission_handler** — Runtime permissions
- **url_launcher** — Phone calls, WhatsApp, SMS URI
- **http** — Gemini AI API calls

---

## Project Structure

```
lib/
├── main.dart                          # App entry point, Firebase init, locale
├── providers.dart                     # All Riverpod providers
├── firebase_options.dart              # Firebase configuration
│
├── auth/                              # Authentication
│   ├── auth_service.dart             # Email / Google / Phone auth logic
│   ├── splash_screen.dart            # Boot screen, auth state routing
│   ├── login_screen.dart             # Email + Google login
│   ├── phone_login_screen.dart       # Phone number entry
│   └── otp_screen.dart               # OTP verification
│
├── screens/                           # Main app screens
│   ├── home_screen.dart              # Dashboard, SOS button, crash toggle
│   ├── ai_first_aid_screen.dart      # Gemini AI first aid chat
│   ├── contacts_screen.dart          # Emergency contacts (encrypted)
│   ├── profile_screen.dart           # User profile + medical info
│   ├── vehicle_screen.dart           # Vehicle details
│   ├── medical_screen.dart           # Medical history / blood group / allergies
│   ├── safety_screen.dart            # Crash detection sensitivity settings
│   ├── live_tracking_map_screen.dart # Real-time GPS map
│   ├── hospital_map_screen.dart      # Nearby hospitals (offline SQLite)
│   ├── directions_map_screen.dart    # Navigation to destination
│   └── offline_first_aid_data.dart  # Offline first aid content
│
├── services/                          # Business logic
│   ├── crash_foreground_service.dart # Background crash detection (foreground task)
│   ├── live_tracking_service.dart    # Firebase RTDB location updates
│   ├── sos_firestore_service.dart    # SOS session management (Firestore)
│   ├── contacts_db.dart              # Encrypted contacts + SQLite mirror
│   ├── osm_db.dart                   # OpenStreetMap SQLite queries
│   ├── crash_math.dart               # Crash detection algorithm & thresholds
│   └── web_speech.dart               # Voice trigger (Web Speech API + Android native)
│
├── widgets/                           # Reusable components
│   ├── crash_banner.dart             # Crash detection status banner
│   ├── sos_section.dart              # SOS button section
│   └── voice_button.dart             # Voice trigger toggle button
│
├── admin/                             # Admin panel (web)
│   ├── admin_guard.dart              # Route protection by role
│   ├── admin_login_screen.dart       # Admin authentication
│   ├── admin_roles.dart              # Role definitions
│   ├── roles_service.dart            # Role management
│   ├── analytics_snapshot_service.dart
│   ├── screens/                      # Admin-specific screens
│   └── widgets/                      # Admin UI components
│
└── l10n/
    └── app_localizations.dart        # i18n strings (all supported languages)

android/                   # Android native code, AndroidManifest, SMS plugin
ios/                       # iOS native code
web/                       # Web admin + /track live tracking viewer
assets/
└── places.db              # Pre-loaded SQLite: 27,000 hospitals, police, services
test/
└── home_screen_test.dart  # 14 widget tests (SOS flow, contacts, crash chip)
```

---

## Getting Started

### Prerequisites

- Flutter SDK 3.0+
- Android Studio (for Android builds)
- Firebase project with Auth, Firestore, Realtime Database, and Hosting enabled
- Gemini API key (for AI first aid feature)

### Setup

**1. Install dependencies**
```bash
flutter pub get
```

**2. Configure Firebase**
- Download `google-services.json` from Firebase Console → place in `android/app/`
- Download `GoogleService-Info.plist` → place in `ios/Runner/`
- Update `web/config.js` with your Firebase web config

**3. Set Gemini API key**

Pass it at build time via `--dart-define` (never hardcode it):
```bash
flutter run --dart-define=GEMINI_API_KEY=your_key_here
```

**4. Deploy Firebase Database Rules**
```bash
firebase deploy --only database
```

The rules in `database.rules.json` restrict live tracking writes to the authenticated user's own session.

### Running the App

```bash
# Android debug
flutter run

# Release APK
flutter build apk --release

# Web (admin dashboard)
flutter build web --release
firebase deploy --only hosting
```

### Running Tests

```bash
flutter test test/home_screen_test.dart
```

---

## Crash Detection Algorithm

**File:** `lib/services/crash_math.dart`

| Parameter | Value | Description |
|---|---|---|
| Impact threshold | 25.0 m/s² | Minimum acceleration to count as a hit |
| Required hits | 2 consecutive | Prevents single-jolt false positives |
| Speed gate | 5 km/h minimum | Ignores stationary drops |
| Low-pass filter α | 0.8 | Gravity estimation smoothing |
| Reset window | 20 seconds | Prevents repeated triggers |

**Flow:**
1. Foreground service reads accelerometer continuously in background
2. Low-pass filter separates gravity from linear acceleration
3. When magnitude > 25 m/s² for 2 consecutive readings at speed > 5 km/h → crash detected
4. Main app receives crash event via `MethodChannel`
5. 10-second countdown shown — user can cancel
6. If not cancelled: SOS sent, live tracking starts, AI first aid opens

To adjust sensitivity, edit the constants in `crash_math.dart`:
```dart
static const double _impactThreshold = 25.0; // Lower = more sensitive
static const double _alpha = 0.8;             // Higher = smoother
static const int _requiredHits = 2;           // More = fewer false positives
static const double _minSpeedMs = 5.0 / 3.6; // Speed gate in m/s
```

---

## SOS Flow

```
User taps SOS (or crash detected)
        ↓
Confirm dialog (3 sec) → Cancel available
        ↓
10-second countdown → Cancel available
        ↓
Get GPS location + start live tracking (Firebase RTDB)
        ↓
Read emergency contacts (FlutterSecureStorage → SQLite fallback)
        ↓
Send alerts via selected channel:
  • SMS  → Native Android SMS plugin (MethodChannel)
  • WhatsApp → wa.me deep link per contact
  • Email → mailto: URI
  • All three simultaneously
        ↓
Open AI First Aid screen (Gemini API, offline fallback if no internet)
        ↓
Post-SOS: "I'm Safe" button sends safe message + stops tracking
```

---

## Voice Trigger

Listens for: `help`, `help me`, `SOS`, `emergency`, `bachao`

- **Android**: Native speech recognition via `MethodChannel` (`com.crashaid/voice`)
- **Web**: Browser Web Speech API (no dependencies)

Enable via the microphone toggle on the home screen. When a keyword is detected, the 10-second SOS countdown starts immediately.

---

## Offline Capabilities

| Data | Storage | Size |
|---|---|---|
| Hospitals, police, services | `assets/places.db` (SQLite) | ~27,000 locations |
| Emergency contacts | FlutterSecureStorage + SQLite mirror | — |
| First aid guidance | `offline_first_aid_data.dart` | Built-in |
| App settings / locale | SharedPreferences | — |

**Offline fallback chain for map queries:**
1. SQLite (`assets/places.db`) — always available, fastest
2. Nominatim (free reverse geocoding)
3. Overpass API (multiple mirrors)
4. Last cached result

---

## Admin Dashboard

Web-only at `/admin`. Requires Firestore admin role claim.

**Roles:**

| Role | Permissions |
|---|---|
| Super Admin | Full access, manage other admins |
| Admin | View incidents, verify, dispatch, update status |
| Responder | View assigned incidents, update status |

**Features:**
- Live SOS feed with auto-refresh
- Incident history with date/status/text filters
- Status pipeline: `Pending → Verified → Ambulance Sent → Police Notified → Resolved`
- User management and role assignment
- Real-time analytics (active incidents, response times, user count)
- Interactive map per incident with live tracking link

---

## Firebase Data Structure

### Firestore — `sos_sessions/{sessionId}`
```
uid, userName, phone, bloodGroup, medicalCondition, allergy,
lat, lng, address, status, createdAt, endedAt, userProfile
```

### Realtime Database — `live_tracking/{sessionId}`
```
username, started_at, expires_at, active,
lat, lng, accuracy, speed, updated_at,
path: [{lat, lng, ts}], path_truncated
```

### Security Rules (`database.rules.json`)
```json
{
  "rules": {
    "live_tracking": {
      "$sessionId": {
        ".read": true,
        ".write": "auth != null && $sessionId.beginsWith(auth.uid + '_')"
      }
    }
  }
}
```
Write is restricted to the authenticated user's own session. Read is open so emergency contacts can view the live tracking link without logging in.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Background service stops | Ensure "Disable battery optimizations" permission granted for the app |
| SMS not sending | Check `SEND_SMS` permission in Android settings |
| False crash detections | Raise `_impactThreshold` in `crash_math.dart` |
| Maps not loading | Check `geolocator` and `flutter_map` packages, verify location permission |
| Live tracking stops | App needs "Always Allow" location permission, not just "While Using" |
| OTP not received | Check Firebase phone auth configuration and SMS quota |
| Google Sign-in fails | Verify SHA-1 fingerprint in Firebase Console matches your build |
| AI first aid not responding | Check `GEMINI_API_KEY` was passed via `--dart-define` |
| Admin login not working | Verify user has admin role set in Firestore `admin_users` collection |
| SQLite error on startup | Run `flutter clean && flutter pub get` |

---

## Platform Notes

### Android
- Foreground service keeps crash detection alive with a persistent notification
- Native SMS via `MethodChannel` (`com.crashaid/sms`)
- AES-encrypted SharedPreferences via FlutterSecureStorage

### iOS
- Background location tracking via CoreLocation
- Keychain storage for encrypted contacts
- No foreground service equivalent — crash detection requires app to be in foreground

### Web
- Admin dashboard at `/#/admin`
- Live tracking viewer at `/track?id={sessionId}`
- Voice trigger via Web Speech API (Chrome/Edge)
- No crash detection (no accelerometer access in browsers)

---

## Testing

14 widget tests covering:
- HomeScreen renders (SOS button, quick-call buttons)
- Emergency contact parsing (empty, with contacts, fallback key, blank number stripping)
- SOS confirmation dialog (open, cancel)
- Countdown dialog (appears, cancel dismisses, starts at 10, decrements)
- Crash detection chip (ON state, toggle dialog)

```bash
flutter test test/home_screen_test.dart
```

---

## Security

- Emergency contacts encrypted with AES (Android) / Keychain (iOS) via `flutter_secure_storage`
- Gemini API key injected at build time via `--dart-define`, never in source
- Firebase Realtime Database write access restricted to auth session owner
- Medical profiles in Firestore with user-level access control
- Admin routes protected by Firestore custom role claims
- All location data transmitted over HTTPS

# website url :https://crashaid-a1d3c.web.app

---

## License

Proprietary. All rights reserved.
