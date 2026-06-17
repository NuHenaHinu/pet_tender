import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pet_tender/models/models.dart';
import 'package:pet_tender/providers/auth_provider.dart';
import 'package:pet_tender/screens/profile/profile_screen.dart';

/// AuthProvider stub with a fixed user (no network/login needed).
class _FakeAuth extends AuthProvider {
  _FakeAuth(this._u);
  final User _u;
  @override
  User? get user => _u;
}

/// Regression guard: ProfileScreen must lay out without throwing. It previously
/// crashed blank because a stat Row used CrossAxisAlignment.stretch inside a
/// vertically-unbounded ListView (RenderFlex assertion). Backendless isn't
/// initialised here, so the stat fetch fails fast and is swallowed — we're only
/// asserting the screen builds.
void main() {
  testWidgets('ProfileScreen lays out without throwing', (tester) async {
    SharedPreferences.setMockInitialValues({});

    for (final role in UserRole.values) {
      final user = User(
        id: 'id-${role.name}',
        name: 'Test ${role.name}',
        email: 'test@example.com',
        role: role,
        createdAt: DateTime(2026, 1, 1),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AuthProvider>.value(
            value: _FakeAuth(user),
            child: const ProfileScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(tester.takeException(), isNull, reason: 'role=$role');
      expect(find.text('Test ${role.name}'), findsOneWidget, reason: 'role=$role');
    }
  });
}
