# Attendance Management Flutter App  

<p align="center">
  <img src="LOGO.svg" alt="App Logo" width="120"/>
</p>

<p align="center">
  <a href="https://github.com/yourusername/attendance_flutter/releases/latest/download/app-release.apk">
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
- 💾 SQLite local database for offline support
- 🗂️ Organized codebase with providers, models, services, and screens

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
   git clone https://github.com/yourusername/attendance_flutter.git
   cd attendance_flutter
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

- Download the latest release APK: [Download APK](https://github.com/yvinchhi/attendence/releases/download/v1.0.0/app-release.apk)
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
- Check [GitHub Issues](https://github.com/yourusername/attendance_flutter/issues) for known problems.

---

## 🤝 Contributing
Pull requests are welcome! For major changes, please open an issue first to discuss what you would like to change.

---

## 📄 License
This project is licensed under the MIT License.

---

## 🙏 Credits
- Developed by Yash Vinchhi
- Special thanks to contributors and open-source Flutter community

---

## 📝 Changelog
See [Releases](https://github.com/yourusername/attendance_flutter/releases) for version history and updates.

---

## 💬 Support
For any queries or support, contact [your.email@example.com].
