# 🐾 PeTender

> A pet care job board app built with Flutter — connect pet owners with trusted sitters.

PeTender is a Flutter university final project that lets pet **owners** post pet-sitting jobs and **sitters** browse, apply, and manage their applications. It also includes a dog/cat **breed explorer** powered by The Dog API and The Cat API.

---

## ✨ Features

- **Authentication** — register, login via Email, Google, or LINE, and logout
- **Job board** — browse open jobs with filter chips, pull-to-refresh, shimmer loading, and staggered animations
- **Job details** — collapsing app bar, hero images, apply dialog, bookmarking, and an embedded Google Map
- **Post a job** — form with breed autocomplete, date/time pickers, map location picker, and photo upload
- **My jobs & applications** — manage posted jobs (swipe-to-delete) and track application status
- **Breed explorer** — searchable grid of dog & cat breeds with detail pages, image galleries, and trait stat bars
- **Profile & settings** — edit profile, dark mode, notifications, language, and cache management
- **Local notifications** — schedule job reminders (timezone-aware, `Asia/Taipei`)

---

## 🛠️ Tech Stack

| Area | Choice |
|---|---|
| Framework | Flutter 3.x · Material 3 |
| Language | Dart 3.3+ |
| State management | [`provider`](https://pub.dev/packages/provider) |
| Backend | Backendless (custom REST client via `dio`) |
| Networking | [`dio`](https://pub.dev/packages/dio) |
| Maps & location | `google_maps_flutter`, `geolocator` |
| Auth | `google_sign_in`, `flutter_line_sdk` |
| External data | The Dog API · The Cat API |

**Target locale:** Taiwan (UTC+8, TWD currency) · **Min Android SDK:** 23 · **Min iOS:** 14.0

---

## 🏗️ Architecture

```
lib/
├── main.dart                 # App entry, init, routes, theme, AuthGate
├── backendless_client.dart   # Backendless REST client (dio) — auth + CRUD
├── models/                   # User, Job, Application, Breed + enums
├── providers/                # AuthProvider, ThemeProvider, JobProvider
└── screens/
    ├── main_shell.dart       # Bottom nav (IndexedStack, 5 tabs)
    ├── auth/                 # login, register
    ├── home/                 # job feed
    ├── search/               # job search
    ├── jobs/                 # detail, post, my jobs, my applications
    ├── breed/                # breed explorer + detail
    └── profile/              # profile, edit, settings
```

- **State** — `context.watch<P>()` in `build()`, `context.read<P>()` in callbacks
- **Navigation** — named routes in `AppRoutes`; model arguments passed via `onGenerateRoute`
- **Backend** — `BackendlessClient.instance` singleton handles auth tokens and CRUD against the `Jobs` and `Applications` tables

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK 3.x (Dart 3.3+)
- An Android/iOS device or emulator
- API keys for Backendless, Google Maps, and LINE

### Setup

1. **Clone & install dependencies**
   ```bash
   git clone <repo-url>
   cd pet_tender
   flutter pub get
   ```

2. **Configure environment variables** — copy the example file and fill in your keys:
   ```bash
   cp .env.example .env
   ```
   ```env
   BACKENDLESS_APP_ID=
   BACKENDLESS_API_KEY=        # REST key (Backendless Console → Manage → API Keys → REST)
   LINE_CHANNEL_ID=
   GOOGLE_MAPS_API_KEY=
   DOG_API_KEY=                # optional — The Dog API
   CAT_API_KEY=                # optional — The Cat API
   ```
   > `.env` is gitignored. Never commit your real keys.

3. **Run the app**
   ```bash
   flutter run
   ```

### Android build notes
`android/app/build.gradle` must include (required by `flutter_local_notifications`):
```gradle
compileOptions {
    coreLibraryDesugaringEnabled true
    sourceCompatibility JavaVersion.VERSION_1_8
    targetCompatibility JavaVersion.VERSION_1_8
}
dependencies {
    coreLibraryDesugaring 'com.android.tools.desugar_jdk_libs:2.1.4'
}
defaultConfig {
    minSdkVersion 23
}
```

---

## 🌐 External APIs

| API | Base URL | Auth |
|---|---|---|
| Backendless | `https://api.backendless.com/{APP_ID}/{API_KEY}` | `user-token` header after login |
| The Dog API | `https://api.thedogapi.com/v1` | `x-api-key` header (optional) |
| The Cat API | `https://api.thecatapi.com/v1` | `x-api-key` header (optional) |
| Google Maps | Platform SDK | API key in `AndroidManifest` / `AppDelegate` |

---

## ⚠️ Notes

- This project uses a **custom `dio`-based REST client** instead of `backendless_sdk` — the SDK pins `http ^0.13.x`, which conflicts with `lottie`, `cached_network_image`, and others. Do not add `backendless_sdk` or `http` directly.
- `lottie` is pinned to `^2.7.0` and `cached_network_image` to `^3.3.1` for the same `http` compatibility reason.
- Backendless timestamps are **Unix ms integers**, not ISO strings.

---

## 📄 License

This project was created for educational purposes as a university final project.
