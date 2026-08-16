# CrashAid 🚨

An AI-powered crash detection and emergency response app built with Flutter and Firebase. Automatically detects vehicle crashes, sends SOS alerts to emergency contacts, shares live GPS location, routes ambulances to the best hospital in real time, and provides AI-guided first aid — all running in the background even when the app is closed.

---

## Features

| Feature | Description |
|---|---|
| 🔴 **Auto Crash Detection** | Accelerometer-based detection with 10-second cancel window |
| 📍 **Live GPS Tracking** | Real-time location shared with emergency contacts |
| 🚑 **Intelligent Ambulance Routing** | Scores nearby hospitals on real driving ETA + distance + suitability (not just nearest), draws a live OSRM route, favours the fastest road while steering around hazard clusters, and automatically reroutes if conditions change |
| 🕳️ **Crowd-sourced Hazard Reporting** | Auto-GPS pothole/road-hazard reports with photo evidence, severity levels, and crowd confirmation — feeds directly into ambulance route scoring |
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
- **Firebase Realtime Database** — Live tracking breadcrumbs (patient, ambulance, and general session GPS)
- **Cloud Firestore** — SOS sessions, hazard reports, admin dashboard data
- **Firebase Storage** — Pothole and missing-person photo evidence
- **Firebase Hosting** — Web admin panel + live tracking viewer

### Routing & Mapping
- **OSRM** (public mirrors, with automatic fallback) — real driving routes, distance, and ETA for ambulance routing
- **Overpass API** (public OpenStreetMap mirrors, with automatic fallback) — nearby hospital discovery
- **flutter_map** + **latlong2** — OpenStreetMap tile rendering for all in-app maps

### Local Storage
- **sqflite** — Emergency contacts mirror, OSM places database
- **flutter_secure_storage** — AES-encrypted contacts (Keychain on iOS)
- **shared_preferences** — App settings, locale, alert channel preference

### Sensors & Location
- **sensors_plus** — Accelerometer data for crash detection
- **geolocator** — GPS location, live streams for ambulance/patient tracking
- **image_picker** — Camera/gallery capture for hazard photo evidence

### Other
- **flutter_foreground_task** — Background crash monitoring service
- **permission_handler** — Runtime permissions
- **url_launcher** — Phone calls, WhatsApp, SMS URI, external navigation handoff
- **http** — Gemini AI, OSRM, and Overpass API calls

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
│   ├── ambulance_routing_screen.dart # Emergency Mode: live route to best hospital
│   ├── pothole_map_screen.dart       # Report & view crowd-sourced hazards
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
│   ├── ambulance_routing_service.dart# Hospital scoring, OSRM routing, hazard-aware selection
│   ├── pothole_service.dart          # Hazard report CRUD, photo upload, crowd confirmation
│   ├── live_tracking_service.dart    # Firebase RTDB location updates
│   ├── sos_firestore_service.dart    # SOS session management (Firestore)
│   ├── contacts_db.dart              # Encrypted contacts + SQLite mirror
│   ├── osm_db.dart                   # OpenStreetMap SQLite queries
│   ├── crash_math.dart               # Crash detection algorithm & thresholds
│   └── web_speech.dart               # Voice trigger (Web Speech API + Android native)
│
├── widgets/                           # Reusable components
│   ├── crash_banner.dart             # Crash detection status banner
│   ├── sos_dialog.dart               # Post-SOS options (incl. Start Ambulance Routing)
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
firestore.rules            # Cloud Firestore security rules
database.rules.json        # Realtime Database security rules
storage.rules               # Firebase Storage security rules (photo evidence)
test/
└── home_screen_test.dart  # 14 widget tests (SOS flow, contacts, crash chip)
```

---

## Getting Started

### Prerequisites

- Flutter SDK 3.0+
- Android Studio (for Android builds)
- Firebase project with Auth, Firestore, Realtime Database, Storage, and Hosting enabled
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

**4. Deploy Firebase security rules**
```bash
firebase deploy --only firestore:rules,storage:rules,database
```

> ⚠️ **Firestore rules do not auto-renew.** A freshly-created Firestore database starts in "test mode," which only allows read/write for 30 days before locking the entire database — including SOS, hazard reports, and the admin dashboard. Make sure `firestore.rules` (checked into this repo) is deployed and doesn't contain a `request.time < timestamp.date(...)` expiry clause before shipping to real users.

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
6. If not cancelled: SOS sent, live tracking starts, AI first aid opens, and the person can launch Ambulance Routing directly from the post-SOS dialog

To adjust sensitivity, edit the constants in `crash_math.dart`:
```dart
static const double _impactThreshold = 25.0; // Lower = more sensitive
static const double _alpha = 0.8;             // Higher = smoother
static const int _requiredHits = 2;           // More = fewer false positives
static const double _minSpeedMs = 5.0 / 3.6; // Speed gate in m/s
```

---

## Intelligent Ambulance Routing

**Files:** `lib/services/ambulance_routing_service.dart`, `lib/screens/ambulance_routing_screen.dart`

Reachable from the home screen tile or the post-SOS "Start Ambulance Routing" button. Runs entirely on free public infrastructure (OSRM + Overpass, each with automatic mirror fallback) — no paid routing API required.

| Stage | What happens |
|---|---|
| 1. Emergency Mode | Activates the moment the screen opens; live GPS streaming starts immediately |
| 2. Live GPS | A `Geolocator` stream drives the on-screen marker and mirrors position to Firebase RTDB via `LiveTrackingService` so it's watchable remotely |
| 3. Hospital selection | The 5 nearest hospitals (via Overpass) are scored on **real driving ETA (50%) + distance (35%) − suitability bonus (up to 25%** for an emergency department / trauma capability) — lowest cost wins, not simply the nearest |
| 4. Route calculation | OSRM returns a real driving route (geometry, distance, duration) to the selected hospital |
| 5. Traffic-aware routing | OSRM route alternatives are penalised by nearby hazard reports (8s / 25s / 60s per Low / Medium / High severity pothole within 80m) and the lowest *effective* duration wins — steering away from hazard clusters when a viable alternative exists |
| 6. Dynamic rerouting | Recalculates every 30 seconds, immediately on >90m deviation from the planned route, and whenever a new hazard is reported near the active route |

Every hazard report made through the Pothole Map feeds directly into stage 5 — this is the link between the two features.

---

## Crowd-sourced Hazard Reporting

**Files:** `lib/services/pothole_service.dart`, `lib/screens/pothole_map_screen.dart`

| Requirement | Implementation |
|---|---|
| Automatic location | GPS is captured fresh via `Geolocator` at the moment of submission — never a cached position |
| Photo evidence | Camera or gallery photo, uploaded to Firebase Storage at `potholes/{reportId}/photo.jpg` |
| Severity | Small / Medium / Large-Critical, shown as colour-coded markers (🟢 / 🟠 / 🔴) with a map legend |
| Report type | Pothole, Road damage, Dangerous road, Other hazard |
| Live map | Markers update in real time via a Firestore `snapshots()` stream; a bad/legacy document is skipped and logged rather than blanking the whole map |
| Crowd confirmation | "I found this pothole too" — a Firestore transaction increments `confirmCount` and adds the user to `confirmedBy`, capped at one confirmation per user |

> Internally, severity is stored as `Low` / `Medium` / `High` (not the display labels) because `AmbulanceRoutingService`'s hazard-penalty lookup keys off those exact values — only the UI label is remapped to Small/Medium/Large-Critical.

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
Post-SOS options:
  • Start Ambulance Routing → best hospital, live route, ETA
  • "I'm Safe" → sends safe message + stops tracking
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

> Ambulance Routing and Hazard Reporting require a live connection (OSRM + Overpass + Firestore) and will show a "temporarily unavailable" banner with a Retry button if all mirrors fail — they do not have an offline mode.

---

## Admin Dashboard

Web-only at `/admin`. Requires a document at Firestore `admin_users/{uid}`.

**Roles:**

| Role | Permissions |
|---|---|
| Super Admin | Full access, manage other admins |
| Emergency Operator | View incidents, verify, dispatch, update status |
| Hospital Coordinator | View incoming ambulance routing sessions, hospital-side status |
| Police Coordinator | View incidents, coordinate road/traffic response |

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

### Firestore — `potholes/{reportId}`
```
lat, lng, severity ('Low'|'Medium'|'High'), type, note, photoUrl,
reportedBy, reportedAt, confirmCount, confirmedBy: [uid, ...]
```

### Firestore — `admin_users/{uid}`
```
role ('super_admin' | 'emergency_operator' | 'hospital_coordinator' | 'police_coordinator')
```

### Realtime Database — `live_tracking/{sessionId}`
```
username, started_at, expires_at, active,
lat, lng, accuracy, speed, updated_at,
path: [{lat, lng, ts}], path_truncated
```

### Realtime Database Security Rules (`database.rules.json`)
```json
{
  "rules": {
    "live_tracking": {
      "$sessionId": {
        ".read": true,
        ".write": "auth != null && $sessionId.beginsWith(auth.uid + '_')"
      }
    },
    "safe_route_sessions": {
      "$code": {
        ".read": "auth != null",
        ".write": "auth != null && (data.exists() || newData.child('parent_uid').val() === auth.uid)"
      }
    }
  }
}
```
Write is restricted to the authenticated user's own session. Read is open on `live_tracking` so emergency contacts can view the live tracking link without logging in.

### Cloud Firestore Security Rules (`firestore.rules`)
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    function isSignedIn() { return request.auth != null; }
    function isAdmin() {
      return isSignedIn() &&
        exists(/databases/$(database)/documents/admin_users/$(request.auth.uid));
    }
    function isSuperAdmin() {
      return isSignedIn() &&
        get(/databases/$(database)/documents/admin_users/$(request.auth.uid)).data.role == 'super_admin';
    }

    match /users/{uid} {
      allow read, write: if isSignedIn() && (request.auth.uid == uid || isAdmin());
      match /emergency_contacts/{contactId} {
        allow read, write: if isSignedIn() && (request.auth.uid == uid || isAdmin());
      }
    }

    match /sos_sessions/{sessionId} {
      allow read: if isSignedIn() && (resource.data.uid == request.auth.uid || isAdmin());
      allow create: if isSignedIn() && request.resource.data.uid == request.auth.uid;
      allow update: if isSignedIn() && (resource.data.uid == request.auth.uid || isAdmin());
      allow delete: if isSuperAdmin();
    }

    match /missing_persons/{reportId} {
      allow read: if isSignedIn();
      allow create: if isSignedIn() && request.resource.data.reportedBy == request.auth.uid;
      allow update: if isSignedIn() && (resource.data.reportedBy == request.auth.uid || isAdmin());
      allow delete: if isAdmin();
    }

    match /potholes/{reportId} {
      allow read: if isSignedIn();
      allow create: if isSignedIn() && request.resource.data.reportedBy == request.auth.uid;
      allow update: if isSignedIn() &&
        request.resource.data.diff(resource.data).affectedKeys().hasOnly(['confirmCount', 'confirmedBy']);
      allow delete: if isAdmin();
    }

    match /admin_users/{adminId} {
      allow read: if isSignedIn();
      allow write: if isSuperAdmin();
    }

    match /analytics_history/{snapshotId} {
      allow read, write: if isAdmin();
    }
  }
}
```

### Storage Security Rules (`storage.rules`)
```
match /potholes/{reportId}/{fileName} {
  allow read: if request.auth != null;
  allow write: if request.auth != null
               && request.resource.size < 5 * 1024 * 1024
               && request.resource.contentType.matches('image/.*');
}
```

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
| Admin login not working | Verify user has a document in Firestore `admin_users` collection |
| SQLite error on startup | Run `flutter clean && flutter pub get` |
| `[cloud_firestore/permission-denied]` on any screen | Your `firestore.rules` has likely expired (test-mode rules auto-expire after 30 days) — redeploy the rules in this repo |
| Ambulance Routing shows "temporarily unavailable" | The free OSRM/Overpass mirrors are rate-limited or briefly down — tap Retry; avoid hot-restarting the screen repeatedly during testing, as each restart burns another request against the same free quota |
| Pothole photo upload fails (`object-not-found`) | `storage.rules` isn't deployed/doesn't cover the `potholes/` path — redeploy `storage.rules` |
| Pothole markers not appearing after a successful submit | Check `flutter logs` for `🟠 PotholeService: skipping malformed report <id>` — delete that document in Firestore Console; this happens if a test document was added manually with the wrong field types |
| `flutter build apk` fails with "Access is denied" on Windows | Kill stray `dart.exe`/`java.exe` processes in Task Manager, run the terminal as Administrator, then `flutter clean` before rebuilding |

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
- Cloud Firestore access is role- and ownership-scoped per collection (see rules above) — every collection requires sign-in, and cross-user writes are blocked except for admins
- Pothole confirmations are restricted at the rules level to only touch `confirmCount`/`confirmedBy`, so a client can't rewrite another user's report
- Medical profiles in Firestore with user-level access control
- Admin routes protected by a Firestore `admin_users` role document, checked both client-side and in security rules
- All location, routing, and photo data transmitted over HTTPS

# website url: https://crashaid-a1d3c.web.app

---

## License

Proprietary. All rights reserved.