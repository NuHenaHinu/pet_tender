import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../backendless_client.dart';
import '../models/models.dart';

/// Supplied by the UI to let a first-time social user pick their [UserRole].
/// Return the chosen role, or null if the user dismissed the picker.
typedef RoleSelector = Future<UserRole?> Function();

class AuthProvider extends ChangeNotifier {
  User? _user;
  bool _isLoading;
  String? _error;

  User? get user => _user;
  bool get isLoggedIn => _user != null;
  bool get isLoading => _isLoading;
  String? get error => _error;

  final _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);

  AuthProvider({String? savedToken}) : _isLoading = savedToken != null {
    if (savedToken != null) _restoreSession(savedToken);
  }

  // ── Token restore on app launch ───────────────────────────────────────────

  Future<void> _restoreSession(String token) async {
    try {
      final json = await BackendlessClient.instance.restoreSession(token);
      _user = User.fromJson(json);
    } catch (_) {
      // Token expired — clear it so the user isn't stuck on splash
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_token');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── Email / password ──────────────────────────────────────────────────────

  Future<void> login({required String email, required String password}) async {
    _setError(null);
    try {
      final json = await BackendlessClient.instance.login(
        email: email,
        password: password,
      );
      await _saveSession(json);
    } catch (e) {
      _setError(_friendlyError(e));
      rethrow; // let the UI show showSnackBar
    }
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
    required UserRole role,
  }) async {
    _setError(null);
    try {
      await BackendlessClient.instance.register(
        name: name,
        email: email,
        password: password,
        role: role.name,
      );
      // Auto-login after register
      await login(email: email, password: password);
    } catch (e) {
      _setError(_friendlyError(e));
      rethrow;
    }
  }

  // ── Google Sign-In ────────────────────────────────────────────────────────

  /// [selectRole] is invoked only when this is a brand-new account, to let the
  /// user pick their role. Returning users keep the role they already have.
  /// Returns `true` once signed in, `false` if the user backed out (cancelled
  /// the Google chooser or dismissed the role picker) — no error in that case.
  Future<bool> loginWithGoogle({RoleSelector? selectRole}) async {
    _setError(null);
    try {
      // Clear any stale/cached session so the account chooser always appears
      // and a previously-invalid token can't be silently reused.
      await _googleSignIn.signOut();

      final account = await _googleSignIn.signIn();
      if (account == null) return false; // user cancelled

      // Derive a stable, deterministic password from the immutable Google ID.
      return await _continueWithSocial(
        email: account.email,
        password: 'google_${account.id}',
        name: account.displayName ?? account.email,
        selectRole: selectRole,
      );
    } catch (e) {
      _setError(_friendlyError(e));
      rethrow;
    }
  }

  /// Shared social-login path: try to log the derived identity in, and only if
  /// that identity doesn't exist yet, register it then log in. Talks to the
  /// client directly (not the public [login]/[register]) so the expected
  /// first-time login miss doesn't flash a spurious error to the UI.
  ///
  /// On a first-time account [selectRole] is awaited to choose the role; if it
  /// returns null the user dismissed the picker, so we abort and return false.
  /// Returns true once the session is saved.
  Future<bool> _continueWithSocial({
    required String email,
    required String password,
    required String name,
    RoleSelector? selectRole,
  }) async {
    Map<String, dynamic> json;
    try {
      json = await BackendlessClient.instance.login(
        email: email,
        password: password,
      );
    } catch (_) {
      // The identity likely doesn't exist yet — ask which role they want, then
      // create the account. If registration fails because it already exists,
      // ignore that and fall through to the retry login below (an existing
      // user keeps their stored role; the picked role only applies on create).
      final role = selectRole == null ? UserRole.sitter : await selectRole();
      if (role == null) return false; // user dismissed the role picker — abort

      try {
        await BackendlessClient.instance.register(
          name: name,
          email: email,
          password: password,
          role: role.name,
        );
      } catch (_) {/* already exists or transient — retry login */}
      json = await BackendlessClient.instance.login(
        email: email,
        password: password,
      );
    }
    await _saveSession(json);
    return true;
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    // Clear the local session and notify first so AuthGate routes to the login
    // screen immediately — don't make the user wait on the (possibly slow)
    // remote/provider sign-outs below.
    _user = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_token');

    // Best-effort remote/provider sign-out, in the background.
    unawaited(_signOutRemote());
  }

  Future<void> _signOutRemote() async {
    try {
      await BackendlessClient.instance.logout();
    } catch (_) {/* token already invalid / offline — ignore */}
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }

  // ── Profile ───────────────────────────────────────────────────────────────

  /// Persists the current user's editable profile fields to the Users table and
  /// refreshes the in-memory [user] so screens watching this provider update.
  ///
  /// Only writes columns that exist on the Backendless Users table —
  /// deliberately omits `rating`/`ratingCount` (no such columns; sending them
  /// makes the update fail). Pass `null` for [bio]/[phoneNumber] to clear them.
  Future<void> updateProfile({
    required String name,
    String? bio,
    String? phoneNumber,
    UserRole? role,
    String? profilePhotoUrl,
  }) async {
    final current = _user;
    if (current == null) throw Exception('You are not signed in.');

    final data = <String, dynamic>{
      'name':        name,
      'bio':         bio,
      'phoneNumber': phoneNumber,
      if (role != null)            'role':            role.name,
      'profilePhotoUrl': ?profilePhotoUrl,
    };

    await BackendlessClient.instance.update('Users', current.id, data);

    // Rebuild directly (not copyWith) so cleared bio/phone become null locally.
    _user = User(
      id:              current.id,
      name:            name,
      email:           current.email,
      role:            role ?? current.role,
      profilePhotoUrl: profilePhotoUrl ?? current.profilePhotoUrl,
      bio:             bio,
      phoneNumber:     phoneNumber,
      rating:          current.rating,
      ratingCount:     current.ratingCount,
      createdAt:       current.createdAt,
    );
    notifyListeners();
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<void> _saveSession(Map<String, dynamic> json) async {
    _user = User.fromJson(json);
    final token = json['user-token'] as String?;
    if (token != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_token', token);
    }
    notifyListeners();
  }

  void _setError(String? msg) {
    _error = msg;
    notifyListeners();
  }

  String _friendlyError(Object e) {
    // Log the raw cause so issues that map to the generic fallback below are
    // still diagnosable from the console.
    debugPrint('Auth error: $e');
    if (e is DioException) {
      debugPrint('Auth error response: ${e.response?.statusCode} ${e.response?.data}');
      final data = e.response?.data;
      if (data is Map && data['message'] != null) {
        final message = data['message'].toString().trim();
        if (message.isNotEmpty) return message;
      }
      final message = e.message?.trim();
      if (message != null && message.isNotEmpty) return message;
    }

    final msg = e.toString().toLowerCase();
    if (msg.contains('invalid login') || msg.contains('invalid password')) {
      return 'Incorrect email or password.';
    }
    if (msg.contains('already exists') || msg.contains('duplicate')) {
      return 'An account with this email already exists.';
    }
    if (msg.contains('socket') || msg.contains('connection')) {
      return 'No internet connection. Please try again.';
    }
    // Raw cause is already logged above for diagnosis; show users a generic,
    // non-leaky message.
    return 'Something went wrong. Please try again.';
  }
}
