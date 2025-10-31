# Attendance Management Flutter App  

<p align="center">
  <img src="LOGO.svg" alt="App Logo" width="120"/>
</p>

<p align="center">
  <a href="https://github.com/YashVinchhi/attendence_flutter/releases/latest/download/app-release.apk">
    <img src="https://img.shields.io/badge/Download-APK-blue?logo=android" alt="Download APK"/>
  </a>
  <br>
  <b>Download the latest APK and try the app!</b>
</p>

---

## 📱 Overview
A comprehensive attendance management system built with Flutter for educational institutions. Faculty can mark, view, and report student attendance efficiently, supporting features like per-lecture tracking, absentee/present reports, and statistics.

## ✨ Features
- ✅ Mark attendance for individual students or in bulk (present/absent)
- 📅 Track attendance by date, lecture, and class
- 📊 Generate formatted absentee and attendance reports
- 📈 View per-day and date-range attendance statistics
- 💾 SQLite local database for offline support (local cache + sync-friendly design)
- 🔐 Firebase Authentication integration: users created with Firebase Auth now get a corresponding Firestore `users/{uid}` profile (written by client) so auth and profile stay in sync.
- ♻️ Resilient profile writes: when Firestore writes fail (network/permission), profile payloads are persisted locally as `pending_profile_{uid}` and retried automatically in background when connectivity returns.
- ⏱ Connectivity-aware background retry: app periodically checks connectivity and retries pending profile writes automatically.
- 🛠 Manage roles UI: HOD can manage Class Coordinators (CCs) and HOD/CC can manage Class Representatives (CRs) via dedicated screens. These screens show live Firestore data and any pending local entries (marked as "(pending)").
- 📱 Sign-up UX: Create-account screen is scrollable to avoid RenderFlex overflow on small screens or when the keyboard is visible.
- ⚠️ Security: client writes intentionally avoid admin-only fields (`is_active`, `permissions`, etc.). Privileged role changes are expected to be performed by HOD/Admin or a trusted backend (Cloud Function) in production.

## How the new auth/profile flow works (brief)
1. User signs up using Firebase Authentication.
2. The app writes a Firestore document at `users/{uid}` using the Auth UID as document ID. The client only writes non-privileged fields: `uid`, `email`, `name`, `department`, `division`, `year`, `role`, `created_at` (server timestamp).
3. If the Firestore write fails, the app saves the profile JSON into SharedPreferences under `pending_profile_{uid}` and retries automatically later via a connectivity-aware background loop.
4. The Home debug UI includes tools to inspect and retry pending profiles manually.

## Manage CCs / CRs screens
- Manage CCs: HOD users can view all `role == 'CC'`, search users by email, assign CC, and revoke CC.
- Manage CRs: HOD and CC users can view/assign/revoke `role == 'CR'` for students.
- Both screens merge locally pending profiles into the displayed lists and mark them as `(pending)` so the UI reflects eventual state.

## 🗂️ Folder Structure

```
lib/
  models/         # Data models (Student, AttendanceRecord, etc.)
  providers/      # State management (AttendanceProvider, etc.)
  services/       # Database and utility services
  screens/        # UI screens
  widgets/        # Reusable widgets
assets/           # Sample data, images, fonts
build/            # Build outputs (APK, etc.)
test/             # Unit and widget tests
```

---

## 🚀 Installation & Setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/YashVinchhi/attendence_flutter.git
   cd attendence_flutter
   ```
2. **Install dependencies**
   ```bash
   flutter pub get
   ```
3. **Run the app**
   ```bash
   flutter run
   ```

---

## 📦 APK Download

- Download the latest release APK: [Download APK](https://github.com/YashVinchhi/attendence_flutter/releases/latest/download/app-release.apk)
- To update the APK:
  1. Build your APK: `flutter build apk --release`
  2. Upload `build/app/outputs/apk/release/app-release.apk` to your GitHub Release page.
  3. Update the download link above if needed.

---

## 🛠️ Requirements
- Flutter SDK (>=3.0.0 recommended)
- Android emulator or device

---

## 📝 Usage
- Mark attendance for students by date and lecture
- Generate daily absentee/present reports
- View attendance statistics for any date range or class

---

## 🖼️ Screenshots
<p align="center">
  <img src="assets/sample_data/screenshot1.png" alt="Main Screen" width="250"/>
  <img src="assets/sample_data/screenshot2.png" alt="Attendance Marking" width="250"/>
</p>

---

## ❓ FAQ
**Q: Is my data stored online?**  
A: No, all data is stored locally on your device using SQLite.

**Q: Can I export attendance reports?**  
A: Yes, you can generate and export formatted reports from the app.

---

## 🧰 Troubleshooting
- If you encounter issues running the app, ensure your Flutter SDK is up to date.
- For database errors, try clearing app data or reinstalling.
- Check [GitHub Issues](https://github.com/YashVinchhi/attendence_flutter/issues) for known problems.

---

## 🤝 Contributing
Pull requests are welcome! For major changes, please open an issue first to discuss what you would like to change.

---

## 📄 License
This project is licensed under the MIT License.

---

## 🙏 Credits
- Developed by Yash VInchhi (https://github.com/YashVinchhi)
- Special thanks to contributors and open-source Flutter community

---

## 📝 Changelog
See [Releases](https://github.com/YashVinchhi/attendence_flutter/releases) for version history and updates.

---

## 💬 Support
For any queries or support, contact [yashhvinchhi@gmail.com].

---

## CI / Releases
- This repository includes a GitHub Actions workflow that builds both an APK and an AAB on pushes to `main`. The workflow creates a GitHub Release and uploads the built artifacts as assets so team members can download the APK directly from:

```
https://github.com/YashVinchhi/attendence_flutter/releases/latest/download/app-release.apk
```

and the AAB via:

```
https://github.com/YashVinchhi/attendence_flutter/releases/latest/download/app-release.aab
```

If you prefer not to publish to Play Store, the workflow can be used to distribute builds internally via Releases.

## Developer notes & clean-up guidance
The repo contains some platform-specific and local files that should not be tracked by GitHub (build outputs, local IDE configs, generated files). Below is a helper `CLEAN_REMOTE.md` with exact git commands you can run locally to remove these from the remote history while keeping them on your PC. This keeps the repo lightweight while preserving your local environment.
