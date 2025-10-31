import 'package:cloud_functions/cloud_functions.dart';

/// AdminService: wrapper around callable Cloud Functions.
///
/// NOTE: To avoid requiring Artifact Registry / Blaze during development,
/// function calls are disabled by default. Re-enable in dev by passing these
/// dart-define flags when running the app:
///   --dart-define=ENV=dev --dart-define=EMULATOR_HOST=10.0.2.2 --dart-define=ENABLE_FUNCTIONS=true
///
/// To deploy functions to production, upgrade your Firebase project to Blaze
/// and deploy the functions (then set ENABLE_FUNCTIONS=true in production
/// build if you want the client to call them directly).
class AdminService {
  AdminService._() {
    _initEmulatorIfNeeded();
  }
  static final AdminService instance = AdminService._();

  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // Compile-time flags
  static const String _env = String.fromEnvironment('ENV', defaultValue: 'prod');
  static const String _emulatorHost = String.fromEnvironment('EMULATOR_HOST', defaultValue: '');
  static final bool _functionsEnabled = (String.fromEnvironment('ENABLE_FUNCTIONS', defaultValue: 'false').toLowerCase() == 'true');

  // Initialize emulator wiring only if explicitly enabled (ENABLE_FUNCTIONS=true)
  static void _initEmulatorIfNeeded() {
    if (!_functionsEnabled) return; // emulator disabled unless explicit opt-in
    if (_env == 'dev' && _emulatorHost.isNotEmpty) {
      try {
        // Default functions emulator port is 5001
        FirebaseFunctions.instance.useFunctionsEmulator(_emulatorHost, 5001);
      } catch (_) {
        // ignore errors during initialization; emulator not required for prod
      }
    }
  }

  String get _disabledMessage => 'Server functions are currently disabled. To enable locally run with --dart-define=ENV=dev --dart-define=EMULATOR_HOST=10.0.2.2 --dart-define=ENABLE_FUNCTIONS=true, or upgrade the Firebase project to Blaze and deploy functions.';

  Future<Map<String, dynamic>> approveCr(String requestId, {String? targetUid}) async {
    if (!_functionsEnabled) {
      return {'success': false, 'error': _disabledMessage};
    }
    try {
      final callable = _functions.httpsCallable('approveCr');
      final res = await callable.call({'requestId': requestId, 'targetUid': targetUid});
      return Map<String, dynamic>.from(res.data as Map);
    } on FirebaseFunctionsException catch (e) {
      return {'success': false, 'error': e.message ?? e.code};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> deactivateStudent(String studentId) async {
    if (!_functionsEnabled) {
      return {'success': false, 'error': _disabledMessage};
    }
    try {
      final callable = _functions.httpsCallable('deactivateStudent');
      final res = await callable.call({'studentId': studentId});
      return Map<String, dynamic>.from(res.data as Map);
    } on FirebaseFunctionsException catch (e) {
      return {'success': false, 'error': e.message ?? e.code};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}
