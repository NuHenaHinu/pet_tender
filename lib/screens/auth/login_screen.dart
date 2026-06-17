import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleEmailLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    try {
      await auth.login(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      // On success, the AuthGate in main.dart will show the home screen.
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.home,
          (route) => false,
      );
    }
    } catch (e) {
      final msg = auth.error ?? 'Could not sign in. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleLogin() async {
    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    try {
      final signedIn = await auth.loginWithGoogle(selectRole: _pickRole);
      if (signedIn && mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.home,
          (route) => false,
      );
    }
    } catch (e) {
      final msg = auth.error ?? 'Google sign-in failed.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Asks a first-time social user which role they want. Returns the chosen
  /// [UserRole], or null if they dismissed the sheet (sign-in is then aborted).
  Future<UserRole?> _pickRole() {
    final scheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<UserRole>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        const subtitles = {
          UserRole.owner: 'Post jobs and hire sitters for your pets',
          UserRole.sitter: 'Find and apply for pet care jobs',
          UserRole.both: 'Post jobs and apply for them',
        };
        const icons = {
          UserRole.owner: Icons.pets,
          UserRole.sitter: Icons.volunteer_activism,
          UserRole.both: Icons.swap_horiz,
        };
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Choose your role',
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'How will you use PeTender? You can change this later in your profile.',
                      style: Theme.of(sheetContext)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: scheme.outline),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              for (final role in UserRole.values)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    foregroundColor: scheme.onPrimaryContainer,
                    child: Icon(icons[role]),
                  ),
                  title: Text(role.displayName),
                  subtitle: Text(subtitles[role]!),
                  onTap: () => Navigator.of(sheetContext).pop(role),
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                Text('Welcome back', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text('Sign in to continue', style: theme.textTheme.bodyMedium),
                const SizedBox(height: 24),

                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Please enter your email.';
                    }
                    if (!v.contains('@')) return 'Please enter a valid email.';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'Please enter your password.';
                    }
                    if (v.length < 6) {
                      return 'Password must be at least 6 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                FilledButton(
                  onPressed: _isLoading ? null : _handleEmailLogin,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Sign in'),
                ),

                const SizedBox(height: 12),
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () => Navigator.pushNamed(context, '/register'),
                  child: const Text('Don\'t have an account? Register'),
                ),

                const SizedBox(height: 24),
                Row(
                  children: const [
                    Expanded(child: Divider()),
                    SizedBox(width: 8),
                    Text('or'),
                    SizedBox(width: 8),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 16),

                // Social sign-in
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _handleGoogleLogin,
                  icon: Image.asset(
                    'assets/icons/google.png',
                    height: 20,
                    width: 20,
                    errorBuilder: (_, _, _) => const Icon(Icons.login),
                  ),
                  label: const Text('Sign in with Google'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
