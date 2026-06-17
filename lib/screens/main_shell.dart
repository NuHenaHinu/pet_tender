import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../providers/auth_provider.dart';

// ── Tab screens — create each file and uncomment its import ──────────────────
import 'home/home_screen.dart';
import 'search/search_screen.dart';
import 'jobs/my_posted_jobs_screen.dart';
import 'jobs/my_applications_screen.dart';
import 'breed/breed_explorer_screen.dart';
import 'profile/profile_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  /// Jump to a specific tab from anywhere in the app:
  /// ```dart
  /// MainShell.of(context)?.jumpTo(MainShell.tabBreeds);
  /// ```
  static _MainShellState? of(BuildContext context) =>
      context.findAncestorStateOfType<_MainShellState>();

  static const int tabHome    = 0;
  static const int tabSearch  = 1;
  static const int tabAction  = 2; // Post Job (owner) or My Applications (sitter)
  static const int tabBreeds  = 3;
  static const int tabProfile = 4;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  void jumpTo(int index) => setState(() => _currentIndex = index);

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth   = context.watch<AuthProvider>();
    final role   = auth.user?.role;
    final isOwner = role == UserRole.owner || role == UserRole.both;

    // IndexedStack keeps all tab states alive — no reload when switching tabs.
    // Each screen is instantiated once and stays in the widget tree.
    final screens = [
      const HomeScreen(),
      const SearchScreen(),
      switch (role) {
        UserRole.owner  => const MyPostedJobsScreen(),
        UserRole.both   => const _BothRoleScreen(),
        _               => const _SitterScreen(),
      },
      const BreedExplorerScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      // IndexedStack instead of PageView — preserves scroll position per tab
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),

      bottomNavigationBar: NavigationBar(
        selectedIndex:           _currentIndex,
        onDestinationSelected:   (i) => setState(() => _currentIndex = i),
        animationDuration:       const Duration(milliseconds: 300),
        labelBehavior:           NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [

          // ── Home ───────────────────────────────────────────────────────────
          const NavigationDestination(
            icon:         Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label:        'Home',
          ),

          // ── Search ─────────────────────────────────────────────────────────
          const NavigationDestination(
            icon:  Icon(Icons.search_rounded),
            label: 'Search',
          ),

          // ── My Jobs / Applied / Activity — visually distinct centre button ──
          _ActionDestination(role: role),

          // ── Breeds ─────────────────────────────────────────────────────────
          const NavigationDestination(
            icon:         Icon(Icons.pets_outlined),
            selectedIcon: Icon(Icons.pets),
            label:        'Breeds',
          ),

          // ── Profile — badge when there are pending applications ────────────
          _ProfileDestination(isOwner: isOwner),
        ],
      ),
    );
  }
}

// =============================================================================
// Private widgets for the two special destinations
// =============================================================================

/// Centre tab — filled rounded square icon to stand out from the others.
class _ActionDestination extends StatelessWidget {
  const _ActionDestination({required this.role});
  final UserRole? role;

  @override
  Widget build(BuildContext context) {
    final color      = Theme.of(context).colorScheme.primary;
    final isSelected = MainShell.of(context)?._currentIndex == MainShell.tabAction;

    Widget icon(IconData data) => Container(
      width:  42,
      height: 42,
      decoration: BoxDecoration(
        color:        isSelected ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(data, size: 22, color: isSelected ? Colors.white : color),
    );

    final (IconData desel, IconData sel, String label) = switch (role) {
      UserRole.owner  => (Icons.work_outline_rounded,  Icons.work_rounded,        'My Jobs'),
      UserRole.both   => (Icons.layers_outlined,        Icons.layers_rounded,      'Activity'),
      _               => (Icons.assignment_outlined,    Icons.assignment_rounded,  'Applied'),
    };

    return NavigationDestination(
      icon:         icon(desel),
      selectedIcon: icon(sel),
      label:        label,
    );
  }
}

/// Profile tab — shows a red dot badge when there are unread status changes.
class _ProfileDestination extends StatelessWidget {
  const _ProfileDestination({required this.isOwner});
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    // Owners get notified of new applicants; sitters get notified of decisions.
    // JobProvider can expose a `pendingCount` in a future iteration.
    // For now, badge is always hidden — wire up when you build notifications.
    const hasBadge = false;

    return NavigationDestination(
      icon: Badge(
        isLabelVisible: hasBadge,
        child:          const Icon(Icons.person_outline_rounded),
      ),
      selectedIcon: Badge(
        isLabelVisible: hasBadge,
        child:          const Icon(Icons.person_rounded),
      ),
      label: 'Profile',
    );
  }
}

// =============================================================================
// Sitter-only screen
// =============================================================================

class _SitterScreen extends StatelessWidget {
  const _SitterScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Applications')),
      body: const MyApplicationsView(),
    );
  }
}

// =============================================================================
// Combined screen for UserRole.both — tabs between My Jobs and Applied
// =============================================================================

class _BothRoleScreen extends StatefulWidget {
  const _BothRoleScreen();

  @override
  State<_BothRoleScreen> createState() => _BothRoleScreenState();
}

class _BothRoleScreenState extends State<_BothRoleScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _jobsKey = GlobalKey<MyPostedJobsViewState>();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Activity'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.work_outline_rounded), text: 'My Jobs'),
            Tab(icon: Icon(Icons.assignment_outlined),  text: 'Applied'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          MyPostedJobsView(key: _jobsKey),
          const MyApplicationsView(),
        ],
      ),
      floatingActionButton: _tab.index == 0
          ? FloatingActionButton(
              heroTag: 'post_job_fab',
              onPressed: () async {
                await Navigator.pushNamed(context, '/post-job');
                _jobsKey.currentState?.refresh();
              },
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}