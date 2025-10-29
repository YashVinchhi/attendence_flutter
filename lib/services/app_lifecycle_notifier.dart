import 'package:flutter/material.dart';

/// A ChangeNotifier that listens to app lifecycle changes and notifies
/// listeners (e.g., to refresh GoRouter) when the app resumes or when
/// refresh() is called explicitly.
class AppLifecycleNotifier extends ChangeNotifier with WidgetsBindingObserver {
  AppLifecycleNotifier() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      notifyListeners();
    }
  }

  /// Manually trigger a refresh (useful after significant state changes).
  void refresh() => notifyListeners();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

