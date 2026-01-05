import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

/// Service für Google Calendar Integration (nur lesen)
class GoogleCalendarService {
  static final GoogleCalendarService _instance = GoogleCalendarService._internal();
  factory GoogleCalendarService() => _instance;
  GoogleCalendarService._internal();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      calendar.CalendarApi.calendarReadonlyScope,
    ],
  );

  GoogleSignInAccount? _currentUser;
  calendar.CalendarApi? _calendarApi;

  bool get isSignedIn => _currentUser != null;
  String? get userEmail => _currentUser?.email;

  /// Meldet den Benutzer bei Google an
  Future<bool> signIn() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      if (_currentUser != null) {
        await _initCalendarApi();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Google Sign-In error: $e');
      return false;
    }
  }

  /// Meldet den Benutzer ab
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
    _calendarApi = null;
  }

  /// Prüft ob der Benutzer bereits angemeldet ist
  Future<bool> checkSignIn() async {
    try {
      _currentUser = await _googleSignIn.signInSilently();
      if (_currentUser != null) {
        await _initCalendarApi();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Silent sign-in error: $e');
      return false;
    }
  }

  /// Initialisiert die Calendar API
  Future<void> _initCalendarApi() async {
    final httpClient = await _googleSignIn.authenticatedClient();
    if (httpClient != null) {
      _calendarApi = calendar.CalendarApi(httpClient);
    }
  }

  /// Gibt alle Kalender des Benutzers zurück
  Future<List<CalendarInfo>> getCalendars() async {
    if (_calendarApi == null) return [];

    try {
      final calendarList = await _calendarApi!.calendarList.list();
      return calendarList.items
              ?.map((c) => CalendarInfo(
                    id: c.id ?? '',
                    summary: c.summary ?? 'Unbenannt',
                    primary: c.primary ?? false,
                  ))
              .toList() ??
          [];
    } catch (e) {
      debugPrint('Error fetching calendars: $e');
      return [];
    }
  }

  /// Gibt Events für einen bestimmten Zeitraum zurück
  Future<List<CalendarEvent>> getEvents({
    required String calendarId,
    required DateTime start,
    required DateTime end,
  }) async {
    if (_calendarApi == null) return [];

    try {
      final events = await _calendarApi!.events.list(
        calendarId,
        timeMin: start.toUtc(),
        timeMax: end.toUtc(),
        singleEvents: true,
        orderBy: 'startTime',
      );

      return events.items
              ?.where((e) => e.start?.dateTime != null || e.start?.date != null)
              .map((e) {
                // All-day events haben nur date (als DateTime), keine dateTime
                final startDate = e.start?.dateTime?.toLocal() ?? e.start?.date;
                final endDate = e.end?.dateTime?.toLocal() ?? e.end?.date;

                if (startDate == null || endDate == null) return null;

                return CalendarEvent(
                  id: e.id ?? '',
                  summary: e.summary ?? 'Kein Titel',
                  description: e.description,
                  start: startDate,
                  end: endDate,
                  isAllDay: e.start?.date != null && e.start?.dateTime == null,
                  location: e.location,
                );
              })
              .whereType<CalendarEvent>()
              .toList() ??
          [];
    } catch (e) {
      debugPrint('Error fetching events: $e');
      return [];
    }
  }

  /// Gibt Events für den heutigen Tag zurück
  Future<List<CalendarEvent>> getTodayEvents(String calendarId) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    return getEvents(calendarId: calendarId, start: start, end: end);
  }

  /// Gibt Events für eine Woche zurück
  Future<List<CalendarEvent>> getWeekEvents(String calendarId, DateTime weekStart) async {
    final end = weekStart.add(const Duration(days: 7));
    return getEvents(calendarId: calendarId, start: weekStart, end: end);
  }
}

/// Kalender-Info (vereinfachte Darstellung)
class CalendarInfo {
  final String id;
  final String summary;
  final bool primary;

  CalendarInfo({
    required this.id,
    required this.summary,
    required this.primary,
  });
}

/// Kalender-Event (vereinfachte Darstellung)
class CalendarEvent {
  final String id;
  final String summary;
  final String? description;
  final DateTime start;
  final DateTime end;
  final bool isAllDay;
  final String? location;

  CalendarEvent({
    required this.id,
    required this.summary,
    this.description,
    required this.start,
    required this.end,
    this.isAllDay = false,
    this.location,
  });

  Duration get duration => end.difference(start);
}
