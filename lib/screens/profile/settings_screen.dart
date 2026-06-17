import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/theme_provider.dart';
import '../../providers/auth_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _appVersion = '0.1.0';

  bool   _notificationsEnabled = false;
  String _language             = 'English';
  bool   _loadingPrefs         = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? false;
      _language             = prefs.getString('language') ?? 'English';
      _loadingPrefs         = false;
    });
  }

  // ── Notifications ───────────────────────────────────────────────────────────

  Future<void> _toggleNotifications(bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    final prefs     = await SharedPreferences.getInstance();

    // Turning on requires the OS permission. If denied, fall back to off and
    // offer a shortcut to the system settings.
    if (value) {
      final status = await Permission.notification.request();
      if (!status.isGranted) {
        await prefs.setBool('notifications_enabled', false);
        if (!mounted) return;
        setState(() => _notificationsEnabled = false);
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Notification permission was denied.'),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => openAppSettings(),
            ),
          ),
        );
        return;
      }
    }

    await prefs.setBool('notifications_enabled', value);
    if (mounted) setState(() => _notificationsEnabled = value);
  }

  // ── Language ────────────────────────────────────────────────────────────────

  Future<void> _pickLanguage() async {
    const options = ['English', '中文 (繁體)'];
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Language',
                    style: Theme.of(ctx).textTheme.titleLarge),
              ),
            ),
            for (final opt in options)
              ListTile(
                title:   Text(opt),
                trailing: _language == opt
                    ? Icon(Icons.check_rounded,
                        color: Theme.of(ctx).colorScheme.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, opt),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (selected == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', selected);
    if (mounted) setState(() => _language = selected);
  }

  // ── Clear cache ─────────────────────────────────────────────────────────────

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   const Text('Clear cache?'),
        content: const Text(
          'This removes downloaded images and temporary files. '
          'They will be re-downloaded when needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:     const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:     const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await DefaultCacheManager().emptyCache();
      // Also drop Flutter's in-memory image cache so freed images don't linger.
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      messenger.showSnackBar(const SnackBar(content: Text('Cache cleared')));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not clear the cache.')),
      );
    }
  }

  // ── Logout ──────────────────────────────────────────────────────────────────

  Future<void> _logout() async {
    final auth      = context.read<AuthProvider>();
    final navigator = Navigator.of(context);
    await auth.logout();
    // Login cleared the AuthGate root via pushNamedAndRemoveUntil, so it's no
    // longer in the tree to route us back. Explicitly reset to the login screen.
    navigator.pushNamedAndRemoveUntil('/login', (route) => false);
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme  = context.watch<ThemeProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _sectionLabel('Appearance'),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title:     const Text('Dark mode'),
            value:     theme.isDarkMode,
            onChanged: (_) => context.read<ThemeProvider>().toggle(),
          ),

          const Divider(height: 1),
          _sectionLabel('Notifications'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title:     const Text('Push notifications'),
            subtitle:  const Text('Job reminders and status updates'),
            value:     _notificationsEnabled,
            onChanged: _loadingPrefs ? null : _toggleNotifications,
          ),

          const Divider(height: 1),
          _sectionLabel('General'),
          ListTile(
            leading:  const Icon(Icons.language_outlined),
            title:    const Text('Language'),
            subtitle: Text(_language),
            trailing: const Icon(Icons.chevron_right),
            onTap:    _pickLanguage,
          ),
          ListTile(
            leading:  const Icon(Icons.cleaning_services_outlined),
            title:    const Text('Clear cache'),
            subtitle: const Text('Free up space used by cached images'),
            onTap:    _clearCache,
          ),
          const ListTile(
            leading:  Icon(Icons.info_outline),
            title:    Text('App version'),
            subtitle: Text('PeTender · v$_appVersion'),
          ),

          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: _logout,
              icon:      const Icon(Icons.logout_rounded),
              label:     const Text('Log out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.error,
                side:            BorderSide(color: scheme.error),
                minimumSize:     const Size.fromHeight(48),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize:      12,
              fontWeight:    FontWeight.w700,
              letterSpacing: 0.5,
              color:         Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );
}
