import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../backendless_client.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../main_shell.dart';

class MyApplicationsView extends StatefulWidget {
  const MyApplicationsView({super.key});

  @override
  State<MyApplicationsView> createState() => MyApplicationsViewState();
}

class MyApplicationsViewState extends State<MyApplicationsView> {
  List<Application> _apps = [];
  bool _isLoading = true;
  String? _error;

  // Status filter — null means "All".
  ApplicationStatus? _filter;

  List<Application> get _visibleApps => _filter == null
      ? _apps
      : _apps.where((a) => a.status == _filter).toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchApps());
  }

  Future<void> _fetchApps() async {
    final userId = context.read<AuthProvider>().user?.id;

    // No logged-in user — clear the spinner instead of leaving the body blank
    // forever. (initState seeds _isLoading = true, so an early return without
    // this would strand the screen on a permanent loading bar.)
    if (userId == null || userId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'You need to be logged in to view your applications.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // Step 1 — fetch applications
      final raw = await BackendlessClient.instance.find(
        'Applications',
        where: "sitterId='$userId'",
        sortBy: 'created DESC',
      );
      final apps = raw.map((a) => Application.fromJson(a)).toList();

      // Step 2 — batch-fetch all referenced jobs in one query. A failure here
      // must NOT blank the whole screen: the applications still render without
      // their job details, and a single malformed job can't abort the rest.
      final jobIds = apps
          .map((a) => a.jobId)
          .where((id) => id.isNotEmpty)
          .toSet();

      final jobMap = <String, Job>{};
      if (jobIds.isNotEmpty) {
        try {
          final idList = jobIds.map((id) => "'$id'").join(',');
          final jobsRaw = await BackendlessClient.instance.find(
            'Jobs',
            where: 'objectId in ($idList)',
            pageSize: jobIds.length,
          );
          for (final j in jobsRaw) {
            try {
              final job = Job.fromJson(j);
              jobMap[job.id] = job;
            } catch (_) {
              // Skip a single unparseable job — keep the rest.
            }
          }
        } catch (_) {
          // Job lookup failed entirely — fall through with an empty jobMap so
          // the applications themselves still show (with a fallback title).
        }
      }

      if (!mounted) return;
      setState(() {
        _apps = apps
            .map((a) => a.copyWith(job: jobMap[a.jobId]))
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _markDone(Application app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   const Text('Mark job as finished?'),
        content: const Text(
          'Let the owner know you have completed this job. '
          'They will review and confirm before the job closes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Yes, I'm done!"),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      // Move job to awaiting-confirmation state — owner must still confirm.
      await BackendlessClient.instance.update(
        'Jobs', app.jobId, {'status': 'completing'},
      );
      await BackendlessClient.instance.update(
        'Applications', app.id, {'status': 'pendingConfirmation'},
      );
      setState(() {
        final idx = _apps.indexWhere((a) => a.id == app.id);
        if (idx != -1) {
          _apps[idx] = app.copyWith(status: ApplicationStatus.pendingConfirmation);
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Done sent! Waiting for the owner to confirm.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e')),
        );
      }
    }
  }

  Future<void> _cancelAccepted(Application app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel accepted job?'),
        content: const Text(
          'The position will be released and the owner can accept someone else. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep job'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel job'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await BackendlessClient.instance.update(
        'Applications', app.id, {'status': 'withdrawn'},
      );
      await BackendlessClient.instance.update(
        'Jobs', app.jobId, {'status': 'open'},
      );
      setState(() {
        final idx = _apps.indexWhere((a) => a.id == app.id);
        if (idx != -1) {
          _apps[idx] = app.copyWith(status: ApplicationStatus.withdrawn);
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Job cancelled — the position is now open again.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel: $e')),
        );
      }
    }
  }

  Future<void> _withdraw(Application app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw application?'),
        content: const Text("You won't be able to reapply after withdrawing."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await BackendlessClient.instance.update(
        'Applications',
        app.id,
        {'status': 'withdrawn'},
      );
      setState(() {
        final idx = _apps.indexWhere((a) => a.id == app.id);
        if (idx != -1) {
          _apps[idx] = app.copyWith(status: ApplicationStatus.withdrawn);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to withdraw: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ── Error (and nothing cached to show) — pull-to-refresh recoverable ──
    if (_error != null && _apps.isEmpty) {
      return _StateMessage(
        onRefresh: _fetchApps,
        icon: Icons.cloud_off_rounded,
        title: 'Could not load applications',
        message: _error,
        action: FilledButton.tonal(
          onPressed: _fetchApps,
          child: const Text('Retry'),
        ),
      );
    }

    // ── First load — top progress bar over a surface you can still pull ──
    if (_isLoading && _apps.isEmpty) {
      return Column(
        children: [
          const LinearProgressIndicator(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _fetchApps,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 160),
                  Center(child: Text('Loading your applications…')),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // ── Loaded, but the sitter has no applications at all ──
    if (_apps.isEmpty) {
      return _StateMessage(
        onRefresh: _fetchApps,
        emoji: '📝',
        title: 'No applications yet',
        message: 'Browse available jobs and apply',
        action: FilledButton.tonal(
          onPressed: () => MainShell.of(context)?.jumpTo(MainShell.tabHome),
          child: const Text('Browse jobs'),
        ),
      );
    }

    // ── Loaded with data ──
    final visible = _visibleApps;
    return Column(
      children: [
        if (_isLoading) const LinearProgressIndicator(),
        _StatusFilterBar(
          apps: _apps,
          selected: _filter,
          onSelected: (s) => setState(() => _filter = s),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetchApps,
            child: visible.isEmpty
                // Filter excludes everything — still scrollable so the
                // RefreshIndicator works, and the filter bar above recovers it.
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      Center(child: Text('No applications with this status.')),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) => _AppCard(
                      app:              visible[i],
                      onWithdraw:       _withdraw,
                      onMarkDone:       _markDone,
                      onCancelAccepted: _cancelAccepted,
                    )
                        .animate()
                        .fadeIn(delay: Duration(milliseconds: i * 40))
                        .slideY(begin: 0.15),
                  ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Status filter bar — only shown when more than one status is present
// =============================================================================

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({
    required this.apps,
    required this.selected,
    required this.onSelected,
  });
  final List<Application> apps;
  final ApplicationStatus? selected;
  final ValueChanged<ApplicationStatus?> onSelected;

  @override
  Widget build(BuildContext context) {
    final present = (<ApplicationStatus>{for (final a in apps) a.status}.toList())
      ..sort((a, b) => a.index.compareTo(b.index));

    // A single status — nothing useful to filter by.
    if (present.length < 2) return const SizedBox.shrink();

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          ChoiceChip(
            label: Text('All (${apps.length})'),
            selected: selected == null,
            onSelected: (_) => onSelected(null),
          ),
          for (final s in present) ...[
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text(
                '${s.displayName} '
                '(${apps.where((a) => a.status == s).length})',
              ),
              selected: selected == s,
              onSelected: (_) => onSelected(s),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// Reusable centred state message — optionally pull-to-refresh recoverable
// =============================================================================

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.title,
    this.message,
    this.icon,
    this.emoji,
    this.action,
    this.onRefresh,
  });
  final String title;
  final String? message;
  final IconData? icon;
  final String? emoji;
  final Widget? action;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final content = Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (emoji != null)
              Text(emoji!, style: const TextStyle(fontSize: 64)),
            if (icon != null) Icon(icon, size: 56, color: scheme.outline),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (message != null && message!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.outline),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );

    if (onRefresh == null) return content;

    // Wrap in an always-scrollable view so pull-to-refresh works even when the
    // message is short — this is the recovery path out of an empty/error state.
    return RefreshIndicator(
      onRefresh: onRefresh!,
      child: LayoutBuilder(
        builder: (ctx, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: content,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Standalone screen
// =============================================================================

class MyApplicationsScreen extends StatelessWidget {
  const MyApplicationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Applications')),
      body: const MyApplicationsView(),
    );
  }
}

// =============================================================================
// Application card
// =============================================================================

class _AppCard extends StatelessWidget {
  const _AppCard({
    required this.app,
    required this.onWithdraw,
    required this.onMarkDone,
    required this.onCancelAccepted,
  });
  final Application app;
  final Future<void> Function(Application) onWithdraw;
  final Future<void> Function(Application) onMarkDone;
  final Future<void> Function(Application) onCancelAccepted;

  ({Color bg, Color fg, IconData icon}) _statusStyle(ColorScheme s) =>
      switch (app.status) {
        ApplicationStatus.pending =>
          (bg: Colors.amber.shade50,     fg: Colors.amber.shade800,  icon: Icons.hourglass_top_rounded),
        ApplicationStatus.accepted =>
          (bg: Colors.green.shade50,     fg: Colors.green.shade800,  icon: Icons.check_circle_outline_rounded),
        ApplicationStatus.rejected =>
          (bg: s.errorContainer,         fg: s.onErrorContainer,     icon: Icons.cancel_outlined),
        ApplicationStatus.withdrawn =>
          (bg: s.surfaceContainerLow,    fg: s.outline,              icon: Icons.undo_rounded),
        ApplicationStatus.pendingConfirmation =>
          (bg: Colors.orange.shade50,    fg: Colors.orange.shade800, icon: Icons.pending_outlined),
        ApplicationStatus.completed =>
          (bg: Colors.blue.shade50,      fg: Colors.blue.shade800,   icon: Icons.verified_outlined),
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = _statusStyle(scheme);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: style.fg.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Status row ─────────────────────────────────────────────────
            Row(
              children: [
                Icon(style.icon, size: 16, color: style.fg),
                const SizedBox(width: 6),
                Text(
                  app.status.displayName,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: style.fg),
                ),
                const Spacer(),
                Text(
                  DateFormat('MMM d, y').format(app.appliedAt),
                  style: TextStyle(fontSize: 11, color: scheme.outline),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Job title + meta (tappable → job detail) ──────────────────
            GestureDetector(
              onTap: app.job != null
                  ? () => Navigator.pushNamed(
                        context, '/job-detail',
                        arguments: app.job,
                      )
                  : null,
              behavior: HitTestBehavior.opaque,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.job?.title ?? 'Job application',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (app.job != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                '${app.job!.petType.emoji} ${app.job!.petType.displayName}',
                                style: TextStyle(
                                    fontSize: 12, color: scheme.outline),
                              ),
                              const SizedBox(width: 12),
                              Icon(Icons.location_on_outlined,
                                  size: 13, color: scheme.outline),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  app.job!.location.address,
                                  style: TextStyle(
                                      fontSize: 12, color: scheme.outline),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.calendar_today_outlined,
                                  size: 13, color: scheme.outline),
                              const SizedBox(width: 3),
                              Text(
                                DateFormat('MMM d, y')
                                    .format(app.job!.startDate),
                                style: TextStyle(
                                    fontSize: 12, color: scheme.outline),
                              ),
                              const Spacer(),
                              Text(
                                'TWD ${app.job!.payRate.toStringAsFixed(0)} / hr',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (app.job != null) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded,
                        size: 18, color: scheme.outline),
                  ],
                ],
              ),
            ),

            // ── Message quote ──────────────────────────────────────────────
            if (app.message != null && app.message!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.format_quote_rounded,
                        size: 14, color: scheme.outline),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        app.message!,
                        style:
                            TextStyle(fontSize: 12, color: scheme.onSurface),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Withdraw button (pending only) ─────────────────────────────
            if (app.status == ApplicationStatus.pending) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => onWithdraw(app),
                  icon: const Icon(Icons.undo_rounded, size: 16),
                  label: const Text('Withdraw'),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.error,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],

            // ── Accepted: Mark Done + Cancel row ──────────────────────────
            // OverflowBar lays the two buttons in a row, then stacks them
            // vertically if the card is too narrow — instead of overflowing.
            if (app.status == ApplicationStatus.accepted) ...[
              const SizedBox(height: 12),
              OverflowBar(
                alignment: MainAxisAlignment.spaceBetween,
                overflowAlignment: OverflowBarAlignment.end,
                spacing: 8,
                overflowSpacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () => onCancelAccepted(app),
                    icon:  const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('Cancel job'),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => onMarkDone(app),
                    icon:  const Icon(Icons.check_circle_outline_rounded, size: 18),
                    label: const Text('Mark as Done'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],

            // ── Awaiting owner confirmation ────────────────────────────────
            if (app.status == ApplicationStatus.pendingConfirmation) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.orange.shade700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Waiting for owner to confirm…',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
