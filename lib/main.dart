import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'backendless_client.dart';
import 'models/models.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/job_provider.dart';

import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/main_shell.dart';
import 'screens/jobs/job_detail_screen.dart';
import 'screens/jobs/post_job_screen.dart';
import 'screens/jobs/my_posted_jobs_screen.dart';
import 'screens/jobs/my_applications_screen.dart';
import 'screens/breed/breed_detail_screen.dart';
import 'screens/profile/edit_profile_screen.dart';
import 'screens/profile/settings_screen.dart';

// ── Credentials — move to flutter_dotenv before publishing ───────────────────
String get _backendlessAppId => dotenv.env['BACKENDLESS_APP_ID'] ?? '';
String get _backendlessApiKey => dotenv.env['BACKENDLESS_API_KEY'] ?? '';

// Global — accessed by scheduleJobReminder() from any screen
final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // 1. Backendless REST client (no SDK — avoids http version conflicts)
  BackendlessClient.init(appId: _backendlessAppId, apiKey: _backendlessApiKey);

  // 2. Timezone data — required for zonedSchedule notifications
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Taipei')); // UTC+8

  // 3. Local notifications
  await _initNotifications();

  // 4. Restore persisted preferences before first frame
  final prefs = await SharedPreferences.getInstance();
  final isDarkMode = prefs.getBool('dark_mode') ?? false;
  final savedToken = prefs.getString('user_token');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider(savedToken: savedToken),
        ),
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(isDarkMode: isDarkMode),
        ),
        ChangeNotifierProvider(create: (_) => JobProvider()),
      ],
      child: const PeTenderApp(),
    ),
  );
}

// =============================================================================
// App root
// =============================================================================

class PeTenderApp extends StatelessWidget {
  const PeTenderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (_, theme, _) => MaterialApp(
        title: 'PeTender',
        debugShowCheckedModeBanner: false,
        themeMode: theme.themeMode,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        home: const AuthGate(),
        routes: {
          AppRoutes.login: (_) => const LoginScreen(),
          AppRoutes.register: (_) => const RegisterScreen(),
          AppRoutes.home: (_) => const MainShell(),
          AppRoutes.postJob: (_) => const PostJobScreen(),
          AppRoutes.myJobs: (_) => const MyPostedJobsScreen(),
          AppRoutes.myApplications: (_) => const MyApplicationsScreen(),
          AppRoutes.editProfile: (_) => const EditProfileScreen(),
          AppRoutes.settings: (_) => const SettingsScreen(),
        },
        // Screens that receive a model object as argument
        onGenerateRoute: (settings) => switch (settings.name) {
          AppRoutes.jobDetail => MaterialPageRoute(
            builder: (_) => JobDetailScreen(job: settings.arguments as Job?),
            settings: settings,
          ),
          AppRoutes.breedDetail => MaterialPageRoute(
            builder: (_) =>
                BreedDetailScreen(breed: settings.arguments as Breed?),
            settings: settings,
          ),
          _ => null,
        },
      ),
    );
  }
}

// =============================================================================
// Auth gate — single source of truth for which screen shows first
// =============================================================================

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (_, auth, _) {
        if (auth.isLoading) {
          return const SplashScreen(); // validating saved token
        }
        if (auth.isLoggedIn) return const MainShell(); // token valid → home
        return const LoginScreen(); // no token → login
      },
    );
  }
}

// =============================================================================
// Route constants — never use raw strings for navigation
// =============================================================================

abstract final class AppRoutes {
  static const login = '/login';
  static const register = '/register';
  static const home = '/home';
  static const jobDetail = '/job-detail';
  static const postJob = '/post-job';
  static const myJobs = '/my-jobs';
  static const myApplications = '/my-applications';
  static const breedDetail = '/breed-detail';
  static const editProfile = '/edit-profile';
  static const settings = '/settings';
}

// =============================================================================
// Theme
// =============================================================================

ThemeData _buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF1D9E75), // teal
    secondary: const Color(0xFF378ADD), // accent blue
    brightness: brightness,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,

    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: true,
    ),

    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),

    navigationBarTheme: NavigationBarThemeData(
      indicatorColor: scheme.primary.withValues(alpha: 0.12),
    ),
  );
}

// =============================================================================
// Notification init
// =============================================================================

Future<void> _initNotifications() async {
  await notificationsPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    ),
    onDidReceiveNotificationResponse: (r) {
      // r.payload == 'job_<objectId>' — use to navigate on tap
      debugPrint('Notification tapped: ${r.payload}');
    },
  );

  await notificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.requestNotificationsPermission();
}

// =============================================================================
// Public helper — schedule a reminder 24h before a job starts
// Call this when AuthProvider.acceptApplication() succeeds.
// =============================================================================

Future<void> scheduleJobReminder({
  required int jobId, // unique int — use objectId.hashCode
  required String jobTitle,
  required DateTime jobStart,
}) async {
  final fire = jobStart.subtract(const Duration(hours: 24));
  if (fire.isBefore(DateTime.now())) return; // already past

  await notificationsPlugin.zonedSchedule(
    jobId,
    'Upcoming job 🐾',
    '$jobTitle starts tomorrow!',
    tz.TZDateTime.from(fire, tz.local),
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'job_reminders',
        'Job Reminders',
        channelDescription: 'Reminders 24 h before a job starts',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    ),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
    payload: 'job_$jobId',
  );
}
