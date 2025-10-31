import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SettingsProviderState { idle, loading, error }

class SettingsProvider with ChangeNotifier {
  String _schoolName = 'SOE RKU';
  String _academicYear = '2024-25';
  bool _showPercentageInList = true;
  int _minimumAttendancePercentage = 75;
  String _defaultDepartment = 'CE';
  String _defaultDivision = 'A';
  int _defaultSemester = 1;
  bool _enableBackupReminders = true;
  int _autoBackupDays = 7;
  String _dateFormat = 'dd/MM/yyyy';
  String _timeFormat = '24h';
  bool _enableDataValidation = true;
  bool _enableConfirmationDialogs = true;

  SettingsProviderState _state = SettingsProviderState.idle;
  String? _errorMessage;
  bool _disposed = false;

  // Getters
  String get schoolName => _schoolName;
  String get academicYear => _academicYear;
  bool get showPercentageInList => _showPercentageInList;
  int get minimumAttendancePercentage => _minimumAttendancePercentage;
  String get defaultDepartment => _defaultDepartment;
  String get defaultDivision => _defaultDivision;
  int get defaultSemester => _defaultSemester;
  bool get enableBackupReminders => _enableBackupReminders;
  int get autoBackupDays => _autoBackupDays;
  String get dateFormat => _dateFormat;
  String get timeFormat => _timeFormat;
  bool get enableDataValidation => _enableDataValidation;
  bool get enableConfirmationDialogs => _enableConfirmationDialogs;

  SettingsProviderState get state => _state;
  bool get isLoading => _state == SettingsProviderState.loading;
  bool get hasError => _state == SettingsProviderState.error;
  String? get errorMessage => _errorMessage;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _safeNotifyListeners() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _setState(SettingsProviderState newState, {String? error}) {
    _state = newState;
    _errorMessage = error;
    _safeNotifyListeners();
  }

  // Load settings from SharedPreferences
  Future<void> loadSettings() async {
    if (_state == SettingsProviderState.loading) return;

    _setState(SettingsProviderState.loading);

    try {
      final prefs = await SharedPreferences.getInstance();

      _schoolName = prefs.getString('school_name') ?? 'SOE RKU';
      _academicYear = prefs.getString('academic_year') ?? _generateCurrentAcademicYear();
      _showPercentageInList = prefs.getBool('show_percentage_in_list') ?? true;
      _minimumAttendancePercentage = prefs.getInt('minimum_attendance_percentage') ?? 75;
      _defaultDepartment = prefs.getString('default_department') ?? 'CE';
      _defaultDivision = prefs.getString('default_division') ?? 'A';
      _defaultSemester = prefs.getInt('default_semester') ?? 1;
      _enableBackupReminders = prefs.getBool('enable_backup_reminders') ?? true;
      _autoBackupDays = prefs.getInt('auto_backup_days') ?? 7;
      _dateFormat = prefs.getString('date_format') ?? 'dd/MM/yyyy';
      _timeFormat = prefs.getString('time_format') ?? '24h';
      _enableDataValidation = prefs.getBool('enable_data_validation') ?? true;
      _enableConfirmationDialogs = prefs.getBool('enable_confirmation_dialogs') ?? true;

      _setState(SettingsProviderState.idle);
    } catch (e) {
      print('Error loading settings: $e');
      _setState(SettingsProviderState.error, error: 'Failed to load settings: ${e.toString()}');
    }
  }

  // Save settings to SharedPreferences
  Future<bool> saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString('school_name', _schoolName);
      await prefs.setString('academic_year', _academicYear);
      await prefs.setBool('show_percentage_in_list', _showPercentageInList);
      await prefs.setInt('minimum_attendance_percentage', _minimumAttendancePercentage);
      await prefs.setString('default_department', _defaultDepartment);
      await prefs.setString('default_division', _defaultDivision);
      await prefs.setInt('default_semester', _defaultSemester);
      await prefs.setBool('enable_backup_reminders', _enableBackupReminders);
      await prefs.setInt('auto_backup_days', _autoBackupDays);
      await prefs.setString('date_format', _dateFormat);
      await prefs.setString('time_format', _timeFormat);
      await prefs.setBool('enable_data_validation', _enableDataValidation);
      await prefs.setBool('enable_confirmation_dialogs', _enableConfirmationDialogs);

      return true;
    } catch (e) {
      print('Error saving settings: $e');
      _setState(SettingsProviderState.error, error: 'Failed to save settings: ${e.toString()}');
      return false;
    }
  }

  // Individual update methods
  Future<void> updateSchoolName(String name) async {
    if (name.trim().isEmpty) {
      _setState(SettingsProviderState.error, error: 'School name cannot be empty');
      return;
    }

    _schoolName = name.trim();
    await saveSettings();
    _safeNotifyListeners();
  }

  Future<void> updateAcademicYear(String year) async {
    if (!_isValidAcademicYear(year)) {
      _setState(SettingsProviderState.error, error: 'Invalid academic year format. Use YYYY-YY format (e.g., 2024-25)');
      return;
    }

    _academicYear = year;
    await saveSettings();
    _safeNotifyListeners();
  }

  Future<void> togglePercentageDisplay() async {
    _showPercentageInList = !_showPercentageInList;
    await saveSettings();
    _safeNotifyListeners();
  }

  Future<void> updateMinimumAttendance(int percentage) async {
    if (percentage < 0 || percentage > 100) {
      _setState(SettingsProviderState.error, error: 'Minimum attendance must be between 0 and 100');
      return;
    }

    _minimumAttendancePercentage = percentage;
    await saveSettings();
    _safeNotifyListeners();
  }

  Future<void> updateDefaultDepartment(String department) async {
    if (department.trim().isEmpty) {
      _setState(SettingsProviderState.error, error: 'Department cannot be empty');
      return;
    }

    _defaultDepartment = department.trim().toUpperCase();
    await saveSettings();
    _safeNotifyListeners();
  }

  Future<void> updateDefaultDivision(String division) async {
    if (division.trim().isEmpty) {
      _setState(SettingsProviderState.error, error: 'Division cannot be empty');
      return;
    }

    _defaultDivision = division.trim().toUpperCase();
    await saveSettings();
    _safeNotifyListeners();
  }

  Future<void> updateDefaultSemester(int semester) async {
    if (semester < 1 || semester > 8) {
      _setState(SettingsProviderState.error, error: 'Semester must be between 1 and 8');
      return;
    }

    _defaultSemester = semester;
    await saveSettings();
    _safeNotifyListeners();
  }

  Future<void> updateDateFormat(String format) async {
    final validFormats = ['dd/MM/yyyy', 'MM/dd/yyyy', 'yyyy-MM-dd', 'dd-MM-yyyy'];
    if (!validFormats.contains(format)) {
      _setState(SettingsProviderState.error, error: 'Invalid date format');
      return;
    }

    _dateFormat = format;
    await saveSettings();
    _safeNotifyListeners();
  }

  Future<void> updateTimeFormat(String format) async {
    if (!['12h', '24h'].contains(format)) {
      _setState(SettingsProviderState.error, error: 'Invalid time format');
      return;
    }

    _timeFormat = format;
    await saveSettings();
    _safeNotifyListeners();
  }

  Future<void> toggleBackupReminders() async {
    _enableBackupReminders = !_enableBackupReminders;
    await saveSettings();
    _safeNotifyListeners();
  }

  Future<void> updateAutoBackupDays(int days) async {
    if (days < 1 || days > 30) {
      _setState(SettingsProviderState.error, error: 'Auto backup days must be between 1 and 30');
      return;
    }

    _autoBackupDays = days;
    await saveSettings();
    _safeNotifyListeners();
  }

  Future<void> toggleDataValidation() async {
    _enableDataValidation = !_enableDataValidation;
    await saveSettings();
    _safeNotifyListeners();
  }

  Future<void> toggleConfirmationDialogs() async {
    _enableConfirmationDialogs = !_enableConfirmationDialogs;
    await saveSettings();
    _safeNotifyListeners();
  }

  // Reset settings to defaults
  Future<void> resetToDefaults() async {
    _schoolName = 'SOE RKU';
    _academicYear = _generateCurrentAcademicYear();
    _showPercentageInList = true;
    _minimumAttendancePercentage = 75;
    _defaultDepartment = 'CE';
    _defaultDivision = 'A';
    _defaultSemester = 1;
    _enableBackupReminders = true;
    _autoBackupDays = 7;
    _dateFormat = 'dd/MM/yyyy';
    _timeFormat = '24h';
    _enableDataValidation = true;
    _enableConfirmationDialogs = true;

    await saveSettings();
    _safeNotifyListeners();
  }

  // Export settings
  Map<String, dynamic> exportSettings() {
    return {
      'school_name': _schoolName,
      'academic_year': _academicYear,
      'show_percentage_in_list': _showPercentageInList,
      'minimum_attendance_percentage': _minimumAttendancePercentage,
      'default_department': _defaultDepartment,
      'default_division': _defaultDivision,
      'default_semester': _defaultSemester,
      'enable_backup_reminders': _enableBackupReminders,
      'auto_backup_days': _autoBackupDays,
      'date_format': _dateFormat,
      'time_format': _timeFormat,
      'enable_data_validation': _enableDataValidation,
      'enable_confirmation_dialogs': _enableConfirmationDialogs,
      'exported_at': DateTime.now().toIso8601String(),
    };
  }

  // Import settings
  Future<bool> importSettings(Map<String, dynamic> settings) async {
    try {
      _schoolName = settings['school_name'] ?? _schoolName;
      _academicYear = settings['academic_year'] ?? _academicYear;
      _showPercentageInList = settings['show_percentage_in_list'] ?? _showPercentageInList;
      _minimumAttendancePercentage = settings['minimum_attendance_percentage'] ?? _minimumAttendancePercentage;
      _defaultDepartment = settings['default_department'] ?? _defaultDepartment;
      _defaultDivision = settings['default_division'] ?? _defaultDivision;
      _defaultSemester = settings['default_semester'] ?? _defaultSemester;
      _enableBackupReminders = settings['enable_backup_reminders'] ?? _enableBackupReminders;
      _autoBackupDays = settings['auto_backup_days'] ?? _autoBackupDays;
      _dateFormat = settings['date_format'] ?? _dateFormat;
      _timeFormat = settings['time_format'] ?? _timeFormat;
      _enableDataValidation = settings['enable_data_validation'] ?? _enableDataValidation;
      _enableConfirmationDialogs = settings['enable_confirmation_dialogs'] ?? _enableConfirmationDialogs;

      await saveSettings();
      _safeNotifyListeners();
      return true;
    } catch (e) {
      _setState(SettingsProviderState.error, error: 'Failed to import settings: ${e.toString()}');
      return false;
    }
  }

  // Helper methods
  String _generateCurrentAcademicYear() {
    final now = DateTime.now();
    final year = now.year;
    final month = now.month;

    // Academic year typically starts in June/July
    if (month >= 6) {
      return '$year-${(year + 1).toString().substring(2)}';
    } else {
      return '${year - 1}-${year.toString().substring(2)}';
    }
  }

  bool _isValidAcademicYear(String year) {
    final regex = RegExp(r'^\d{4}-\d{2}$');
    if (!regex.hasMatch(year)) return false;

    final parts = year.split('-');
    final startYear = int.tryParse(parts[0]);
    final endYear = int.tryParse('20${parts[1]}');

    if (startYear == null || endYear == null) return false;
    return endYear == startYear + 1;
  }

  // Get formatted date string
  String formatDate(DateTime date) {
    switch (_dateFormat) {
      case 'MM/dd/yyyy':
        return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
      case 'yyyy-MM-dd':
        return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      case 'dd-MM-yyyy':
        return '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';
      default: // 'dd/MM/yyyy'
        return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    }
  }

  void clearError() {
    if (_state == SettingsProviderState.error) {
      _setState(SettingsProviderState.idle);
    }
  }

  // Academic year management
  List<String> getAvailableAcademicYears() {
    final currentYear = DateTime.now().year;
    final years = <String>[];

    for (int i = -2; i <= 2; i++) {
      final year = currentYear + i;
      years.add('$year-${(year + 1).toString().substring(2)}');
    }

    return years;
  }

  bool isCurrentAcademicYear(String year) {
    return year == _generateCurrentAcademicYear();
  }
}
