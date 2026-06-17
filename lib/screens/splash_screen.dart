import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lottie/lottie.dart';

/// First screen shown while [AuthGate] validates a saved session token.
/// Does NOT navigate — provider state changes drive routing automatically.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 180,
              width:  180,
              // Falls back to a paw icon if the Lottie asset isn't bundled.
              child: Lottie.asset(
                'assets/lottie/splash.json',
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Icon(
                  Icons.pets_rounded,
                  size:  96,
                  color: scheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'PeTender',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color:      scheme.primary,
                  ),
            ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.2),
            const SizedBox(height: 28),
            SizedBox(
              height: 26,
              width:  26,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color:       scheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
