import 'package:dio/dio.dart';

/// Drop-in replacement for backendless_sdk using the Backendless REST API.
///
/// Usage — call [BackendlessClient.init] once in main.dart:
/// ```dart
/// BackendlessClient.init(
///   appId:  'YOUR_APP_ID',
///   apiKey: 'YOUR_REST_API_KEY',   // Backendless Console → Manage → API Keys → REST
/// );
/// ```
/// Then use [BackendlessClient.instance] anywhere in the app.
class BackendlessClient {
  BackendlessClient._();

  static BackendlessClient? _instance;
  static BackendlessClient get instance {
    assert(_instance != null, 'Call BackendlessClient.init() first.');
    return _instance!;
  }

  late final Dio _dio;

  // Saved after login — sent as header on every authenticated request
  String? _userToken;
  String? get userToken => _userToken;
  bool get isLoggedIn => _userToken != null;

  // ── Initialisation ─────────────────────────────────────────────────────────

  static void init({required String appId, required String apiKey}) {
    _instance = BackendlessClient._();
    _instance!._dio = Dio(
      BaseOptions(
        baseUrl: 'https://api.backendless.com/$appId/$apiKey',
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    // Attach user token to every request once logged in
    _instance!._dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _instance!._userToken;
          if (token != null) options.headers['user-token'] = token;
          handler.next(options);
        },
        onError: (error, handler) {
          // Backendless wraps errors in { "code": ..., "message": ... }, but
          // gateway/timeout failures can return a String/HTML body — subscript
          // that and we'd throw a TypeError, surfacing a generic error instead
          // of the real one. Only read 'message' when the body is a Map.
          String? msg;
          final data = error.response?.data;
          if (data is Map && data['message'] != null) {
            msg = data['message'].toString();
          }
          handler.next(
            DioException(
              requestOptions: error.requestOptions,
              response:       error.response,
              type:           error.type,
              error:          error.error,
              message:        msg ?? error.message,
            ),
          );
        },
      ),
    );
  }

  // ── Auth ───────────────────────────────────────────────────────────────────

  /// Register a new user. Returns the created user map.
  /// Throws [DioException] on failure (e.g. duplicate email).
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String name,
    required String role,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/users/register',
      data: {
        'email':    email,
        'password': password,
        'name':     name,
        'role':     role,
      },
    );
    return res.data!;
  }

  /// Login with email + password. Saves the user token automatically.
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/users/login',
      data: {'login': email, 'password': password},
    );
    _userToken = res.data!['user-token'] as String?;
    return res.data!;
  }

  /// Logout and clear the saved token.
  Future<void> logout() async {
    await _dio.get('/users/logout');
    _userToken = null;
  }

  /// Restore a saved token (e.g. from SharedPreferences) and validate it.
  Future<Map<String, dynamic>> restoreSession(String token) async {
    _userToken = token;
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/users/isvalidusertoken/$token',
      );
      if (res.data!['result'] != true) {
        _userToken = null;
        throw Exception('Session expired');
      }
      // Fetch full user object
      final user = await _dio.get<Map<String, dynamic>>('/users/me');
      return user.data!;
    } on DioException {
      _userToken = null;
      rethrow;
    }
  }

  // ── Data — generic CRUD ────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> find(
    String table, {
    String?  where,
    int      pageSize = 20,
    int      offset   = 0,
    String?  sortBy,
    String?  related,    // comma-separated relation properties to load
  }) async {
    final res = await _dio.get<List<dynamic>>(
      '/data/$table',
      queryParameters: {
        'where':    ?where,
        'sortBy':   ?sortBy,
        'loadRelations': ?related,
        'pageSize': pageSize,
        'offset':   offset,
      },
    );
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  /// Fetch a single record by [objectId].
  Future<Map<String, dynamic>> findById(String table, String objectId) async {
    final res = await _dio.get<Map<String, dynamic>>('/data/$table/$objectId');
    return res.data!;
  }

  /// Create a new record in [table]. Returns the saved object (with objectId).
  Future<Map<String, dynamic>> create(
    String table,
    Map<String, dynamic> data,
  ) async {
    final res = await _dio.post<Map<String, dynamic>>('/data/$table', data: data);
    return res.data!;
  }

  /// Update an existing record. Returns the updated object.
  Future<Map<String, dynamic>> update(
    String table,
    String objectId,
    Map<String, dynamic> data,
  ) async {
    final res = await _dio.put<Map<String, dynamic>>(
      '/data/$table/$objectId',
      data: data,
    );
    return res.data!;
  }

  /// Delete a record by [objectId].
  Future<void> delete(String table, String objectId) async {
    await _dio.delete('/data/$table/$objectId');
  }

  // ── Convenience: count records ─────────────────────────────────────────────

  Future<int> count(String table, {String? where}) async {
    final res = await _dio.get<int>(
      '/data/$table/count',
      queryParameters: {'where': ?where},
    );
    return res.data ?? 0;
  }

  // ── File upload ────────────────────────────────────────────────────────────

  /// Upload a local file to Backendless Files. Returns the public file URL.
  Future<String> uploadFile({
    required String path,
    required String filename,
    required String filePath,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: filename),
    });
    final res = await _dio.post<Map<String, dynamic>>(
      '/files/$path/$filename',
      data: formData,
    );
    return res.data!['fileURL'] as String;
  }
}