import 'package:flutter/material.dart';
import 'dart:async';

class Lock {
  Completer<void>? _completer;

  Future<T> synchronized<T>(Future<T> Function() computation) async {
    if (_completer != null) {
      await _completer!.future;
    }
    _completer = Completer<void>();
    try {
      final result = await computation();
      _completer?.complete();
      _completer = null;
      return result;
    } catch (e) {
      _completer?.complete();
      _completer = null;
      rethrow;
    }
  }
}

class NavigationService {
  static final NavigationService _instance = NavigationService._internal();
  factory NavigationService() => _instance;
  NavigationService._internal();

  final _navigatorLock = Lock();
  bool _isNavigating = false;
  bool _isDisposed = false;

  GlobalKey<NavigatorState>? _rootNavigatorKey;
  void attachRootNavigatorKey(GlobalKey<NavigatorState> key) {
    _rootNavigatorKey = key;
  }

  void dispose() {
    if (_isDisposed) return;
    // Mark disposed and release any pending locks without awaiting
    _isDisposed = true;
    _isNavigating = false;
    _navigatorLock._completer?.complete();
    _navigatorLock._completer = null;
    _rootNavigatorKey = null;
  }

  void refreshRoutes() {
    if (_isDisposed) return;
    _isNavigating = false;
    _navigatorLock._completer?.complete();
    _navigatorLock._completer = null;
  }

  Future<T?> showDialogSafely<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
    bool useRootNavigator = true,
  }) async {
    if (!context.mounted || _isDisposed) return null;

    return await _navigatorLock.synchronized(() async {
      if (!context.mounted || _isDisposed) return null;
      _isNavigating = true;
      try {
        return await showDialog<T>(
          context: context,
          barrierDismissible: barrierDismissible,
          useRootNavigator: useRootNavigator,
          builder: builder,
        );
      } finally {
        if (!_isDisposed) {
          _isNavigating = false;
        }
      }
    });
  }

  // Updated: Do not acquire the navigation lock here to avoid deadlocks when a dialog is open.
  Future<void> popDialog(BuildContext context, {bool useRootNavigator = true}) async {
    if (_isDisposed) return;
    // Prefer the attached root navigator if requested
    NavigatorState? nav;
    if (useRootNavigator && _rootNavigatorKey?.currentState != null) {
      nav = _rootNavigatorKey!.currentState;
    } else if (context.mounted) {
      nav = Navigator.of(context, rootNavigator: useRootNavigator);
    }

    if (nav == null) return;

    try {
      // Try to pop immediately if possible
      if (nav.canPop()) {
        nav.pop();
        // Allow the pop to process
        await Future.delayed(Duration.zero);
      } else {
        // Fallback: schedule maybePop on the next frame
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_isDisposed) return;
          try {
            nav!.maybePop();
          } catch (_) {
            // Ignore if navigator is gone
          }
        });
      }
    } catch (_) {
      // Swallow exceptions to keep UI resilient
    }
  }
}
