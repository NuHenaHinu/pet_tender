import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../backendless_client.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../main_shell.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  _ProfileStats _stats = const _ProfileStats();
  double? _rating; // fresh from the Users row; falls back to auth.user
  int? _ratingCount;
  bool _loading = true;
  bool _ready = false; // first load finished (success or fail)
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStats());
  }

  // ── Stats ───────────────────────────────────────────────────────────────────

  /// One count that never throws — a single failed query shouldn't blank the
  /// whole profile.
  Future<int> _count(String table, String where) async {
    try {
      return await BackendlessClient.instance.count(table, where: where);
    } catch (_) {
      return 0;
    }
  }

  Future<void> _loadStats() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final id = user.id;
    final isSitter = user.role == UserRole.sitter || user.role == UserRole.both;
    final isOwner = user.role == UserRole.owner || user.role == UserRole.both;

    try {
      final prefs = await SharedPreferences.getInstance();
      final bookmarks = (prefs.getStringList('bookmarks') ?? []).length;

      // Fresh rating from the user's own row — auth.user is only as current as
      // the last login, but an owner may have rated the sitter since then.
      double? freshRating;
      int? freshCount;
      try {
        final me = await BackendlessClient.instance.findById('Users', id);
        freshRating = (me['rating'] as num?)?.toDouble();
        freshCount = (me['ratingCount'] as num?)?.toInt();
      } catch (_) {}

      final results = await Future.wait<int>([
        isSitter
            ? _count('Applications', "sitterId='$id'")
            : Future<int>.value(0),
        isSitter
            ? _count('Applications', "sitterId='$id' and status='completed'")
            : Future<int>.value(0),
        isSitter
            ? _count('Applications',
                "sitterId='$id' and status in ('accepted','pendingConfirmation')")
            : Future<int>.value(0),
        isOwner ? _count('Jobs', "ownerId='$id'") : Future<int>.value(0),
        isOwner
            ? _count('Jobs', "ownerId='$id' and status='closed'")
            : Future<int>.value(0),
        isOwner
            ? _count('Jobs',
                "ownerId='$id' and status in ('open','filled','completing')")
            : Future<int>.value(0),
      ]);

      if (!mounted) return;
      setState(() {
        _stats = _ProfileStats(
          applied: results[0],
          ordersDone: results[1],
          activeAsSitter: results[2],
          jobsPosted: results[3],
          jobsCompleted: results[4],
          activeAsOwner: results[5],
          bookmarks: bookmarks,
        );
        _rating = freshRating;
        _ratingCount = freshCount;
        _loading = false;
        _ready = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Couldn\'t load some stats.';
        _loading = false;
        _ready = true;
      });
    }
  }

  void _goToActivity() => MainShell.of(context)?.jumpTo(MainShell.tabAction);

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: user == null
          ? const Center(child: Text('You are not signed in.'))
          : Column(
              children: [
                if (_loading) const LinearProgressIndicator(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadStats,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      children: _content(user),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  List<Widget> _content(User user) {
    final isSitter = user.role == UserRole.sitter || user.role == UserRole.both;
    final isOwner = user.role == UserRole.owner || user.role == UserRole.both;

    return [
      _Header(user: user, ordersDone: _stats.ordersDone),

      if (_error != null) ...[
        const SizedBox(height: 12),
        _InlineError(message: _error!, onRetry: _loadStats),
      ],

      // ── Rating (sitters earn reviews) ──
      if (isSitter) ...[
        const SizedBox(height: 20),
        _RatingCard(
          rating: _rating ?? user.rating,
          ratingCount: _ratingCount ?? user.ratingCount,
        ),
      ],

      // ── Sitter activity ──
      if (isSitter) ...[
        const SizedBox(height: 20),
        _SectionLabel('Sitter activity'),
        _StatRow(children: [
          _StatTile(
            icon: Icons.verified_rounded,
            color: Colors.green,
            value: _v(_stats.ordersDone),
            label: 'Orders done',
            onTap: _goToActivity,
          ),
          _StatTile(
            icon: Icons.play_circle_outline_rounded,
            value: _v(_stats.activeAsSitter),
            label: 'Active',
            onTap: _goToActivity,
          ),
          _StatTile(
            icon: Icons.assignment_outlined,
            value: _v(_stats.applied),
            label: 'Applied',
            onTap: _goToActivity,
          ),
        ]),
      ],

      // ── Owner activity ──
      if (isOwner) ...[
        const SizedBox(height: 20),
        _SectionLabel('Owner activity'),
        _StatRow(children: [
          _StatTile(
            icon: Icons.work_outline_rounded,
            color: Theme.of(context).colorScheme.secondary,
            value: _v(_stats.jobsPosted),
            label: 'Jobs posted',
            onTap: _goToActivity,
          ),
          _StatTile(
            icon: Icons.play_circle_outline_rounded,
            value: _v(_stats.activeAsOwner),
            label: 'Active',
            onTap: _goToActivity,
          ),
          _StatTile(
            icon: Icons.task_alt_rounded,
            color: Colors.green,
            value: _v(_stats.jobsCompleted),
            label: 'Completed',
            onTap: _goToActivity,
          ),
        ]),
      ],

      // ── Saved ──
      const SizedBox(height: 20),
      _SectionLabel('Saved'),
      _StatRow(children: [
        _StatTile(
          icon: Icons.bookmark_outline_rounded,
          value: _v(_stats.bookmarks),
          label: 'Bookmarked jobs',
        ),
      ]),

      // ── About / contact ──
      const SizedBox(height: 20),
      _SectionLabel('About'),
      _AboutCard(user: user),

      // ── Edit ──
      const SizedBox(height: 24),
      OutlinedButton.icon(
        onPressed: () => Navigator.pushNamed(context, '/edit-profile'),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Edit profile'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
        ),
      ),
    ]
        .animate(interval: const Duration(milliseconds: 30))
        .fadeIn(duration: const Duration(milliseconds: 250))
        .slideY(begin: 0.08);
  }

  /// Stat value as text — shows an em dash until the first load completes.
  String _v(int n) => _ready ? '$n' : '—';
}

// =============================================================================
// Header — avatar, name, role chip, joined date
// =============================================================================

class _Header extends StatelessWidget {
  const _Header({required this.user, required this.ordersDone});
  final User user;
  final int ordersDone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final photo = user.profilePhotoUrl;
    final hasPhoto = photo != null && photo.isNotEmpty;

    return Column(
      children: [
        CircleAvatar(
          radius: 44,
          backgroundColor: scheme.primaryContainer,
          backgroundImage: hasPhoto ? CachedNetworkImageProvider(photo) : null,
          child: hasPhoto
              ? null
              : Text(
                  _initials(user.name),
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w600,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
        ),
        const SizedBox(height: 12),
        Text(user.name, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        _RoleChip(role: user.role),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_outlined, size: 14, color: scheme.outline),
            const SizedBox(width: 4),
            Text(
              'Joined ${DateFormat('MMM y').format(user.createdAt)}',
              style: TextStyle(color: scheme.outline, fontSize: 13),
            ),
          ],
        ),
      ],
    );
  }

  static String _initials(String name) {
    final t = name.trim();
    if (t.isEmpty) return '?';
    final parts = t.split(RegExp(r'\s+'));
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last =
        parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
    final res = (first + last).toUpperCase();
    return res.isEmpty ? '?' : res;
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color color, IconData icon) = switch (role) {
      UserRole.owner => (scheme.secondary, Icons.home_work_outlined),
      UserRole.sitter => (scheme.primary, Icons.pets_outlined),
      UserRole.both => (scheme.tertiary, Icons.workspace_premium_outlined),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            role.displayName,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Rating card — driven by user.rating, with an honest empty state
// =============================================================================

class _RatingCard extends StatelessWidget {
  const _RatingCard({required this.rating, required this.ratingCount});
  final double rating;
  final int ratingCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasRating = rating > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary.withValues(alpha: 0.10),
            scheme.secondary.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
      ),
      child: hasRating
          ? Row(
              children: [
                Text(
                  rating.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Stars(rating: rating),
                    const SizedBox(height: 6),
                    Text(
                      'Based on $ratingCount '
                      '${ratingCount == 1 ? 'review' : 'reviews'}',
                      style: TextStyle(fontSize: 12, color: scheme.outline),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Icon(Icons.star_outline_rounded,
                    size: 40, color: scheme.outline),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No ratings yet',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Complete jobs — owners rate you when they confirm, '
                        'and your score shows here.',
                        style: TextStyle(fontSize: 12, color: scheme.outline),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.rating});
  final double rating;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 1; i <= 5; i++)
          Icon(
            rating >= i
                ? Icons.star_rounded
                : (rating >= i - 0.5
                    ? Icons.star_half_rounded
                    : Icons.star_outline_rounded),
            size: 20,
            color: Colors.amber.shade600,
          ),
      ],
    );
  }
}

// =============================================================================
// Stat tiles
// =============================================================================

class _StatRow extends StatelessWidget {
  const _StatRow({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final row = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) row.add(const SizedBox(width: 12));
      row.add(children[i]);
    }
    // IntrinsicHeight gives the Row a bounded cross-axis (height) so the tiles
    // can stretch to equal height. Without it, CrossAxisAlignment.stretch in a
    // vertically-unbounded ListView throws a RenderFlex layout assertion and
    // the whole profile renders blank.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: row,
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    this.color,
    this.onTap,
  });
  final IconData icon;
  final String value;
  final String label;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = color ?? scheme.primary;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Icon(icon, color: tint, size: 24),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// About / contact card
// =============================================================================

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.user});
  final User user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bio = user.bio;
    final phone = user.phoneNumber;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          if (bio != null && bio.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(bio, style: const TextStyle(height: 1.4)),
              ),
            ),
          _InfoRow(icon: Icons.email_outlined, text: user.email),
          if (phone != null && phone.isNotEmpty)
            _InfoRow(icon: Icons.phone_outlined, text: phone),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: scheme.outline),
      title: Text(text, style: const TextStyle(fontSize: 14)),
    );
  }
}

// =============================================================================
// Inline error chip with retry
// =============================================================================

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded,
              size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                  fontSize: 13, color: scheme.onErrorContainer),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

// =============================================================================
// Section label
// =============================================================================

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Stats holder
// =============================================================================

class _ProfileStats {
  const _ProfileStats({
    this.applied = 0,
    this.ordersDone = 0,
    this.activeAsSitter = 0,
    this.jobsPosted = 0,
    this.jobsCompleted = 0,
    this.activeAsOwner = 0,
    this.bookmarks = 0,
  });

  final int applied;
  final int ordersDone;
  final int activeAsSitter;
  final int jobsPosted;
  final int jobsCompleted;
  final int activeAsOwner;
  final int bookmarks;
}
