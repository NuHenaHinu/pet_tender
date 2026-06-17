import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../backendless_client.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';

// =============================================================================
// Embeddable view — no Scaffold, used standalone and inside _BothRoleScreen
// =============================================================================

class MyPostedJobsView extends StatefulWidget {
  const MyPostedJobsView({super.key});

  @override
  State<MyPostedJobsView> createState() => MyPostedJobsViewState();
}

class MyPostedJobsViewState extends State<MyPostedJobsView> {
  List<Job> _jobs = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchMyJobs());
  }

  // Called externally by the standalone screen's FAB after posting a new job.
  Future<void> refresh() => _fetchMyJobs();

  Future<void> _fetchMyJobs() async {
    final userId = context.read<AuthProvider>().user?.id;
    // Not signed in — clear the spinner instead of stranding the screen on a
    // permanent loading bar (_isLoading is seeded true in initState).
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final raw = await BackendlessClient.instance.find(
        'Jobs',
        where: "ownerId='$userId'",
        sortBy: 'created DESC',
      );
      setState(() {
        _jobs = raw.map((j) => Job.fromJson(j)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteJob(Job job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete job?'),
        content: Text('Remove "${job.title}" permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
              minimumSize: Size.zero,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await BackendlessClient.instance.delete('Jobs', job.id);
      setState(() => _jobs.removeWhere((j) => j.id == job.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${job.title}" deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Column(
        children: [
          LinearProgressIndicator(),
          Expanded(child: SizedBox()),
        ],
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 64, color: scheme.outline),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.outline),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: _fetchMyJobs, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_jobs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📋', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text('No jobs posted yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Tap + to post your first job',
                style: TextStyle(color: scheme.outline)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchMyJobs,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        itemCount: _jobs.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final job = _jobs[i];
          return Dismissible(
            key: ValueKey(job.id),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) async {
              await _deleteJob(job);
              return false;
            },
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
            ),
            child: _JobCard(job: job),
          )
              .animate()
              .fadeIn(delay: Duration(milliseconds: i * 40))
              .slideY(begin: 0.15);
        },
      ),
    );
  }
}

// =============================================================================
// Standalone screen — wraps MyPostedJobsView with Scaffold + AppBar + FAB
// =============================================================================

class MyPostedJobsScreen extends StatefulWidget {
  const MyPostedJobsScreen({super.key});

  @override
  State<MyPostedJobsScreen> createState() => _MyPostedJobsScreenState();
}

class _MyPostedJobsScreenState extends State<MyPostedJobsScreen> {
  final _viewKey = GlobalKey<MyPostedJobsViewState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Jobs')),
      body: MyPostedJobsView(key: _viewKey),
      floatingActionButton: FloatingActionButton(
        heroTag: 'post_job_fab',
        onPressed: () async {
          await Navigator.pushNamed(context, '/post-job');
          _viewKey.currentState?.refresh();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

// =============================================================================
// Job card
// =============================================================================

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job});
  final Job job;

  Color _statusColor(ColorScheme s) => switch (job.status) {
        JobStatus.open       => Colors.green.shade600,
        JobStatus.filled     => s.secondary,
        JobStatus.completing => Colors.orange.shade600,
        JobStatus.closed     => s.outline,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = _statusColor(scheme);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.pushNamed(context, '/job-detail', arguments: job),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      job.title,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(job.status.displayName,
                        style: const TextStyle(fontSize: 11)),
                    backgroundColor: statusColor.withValues(alpha: 0.12),
                    labelStyle: TextStyle(
                        color: statusColor, fontWeight: FontWeight.w600),
                    side: BorderSide.none,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${job.petType.emoji} ${job.petType.displayName}'
                '${job.breedName != null ? " · ${job.breedName}" : ""}',
                style: TextStyle(fontSize: 13, color: scheme.outline),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 14, color: scheme.outline),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      job.location.address,
                      style: TextStyle(fontSize: 13, color: scheme.outline),
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
                      size: 14, color: scheme.outline),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('MMM d, y').format(job.startDate),
                    style: TextStyle(fontSize: 13, color: scheme.outline),
                  ),
                  const Spacer(),
                  Text(
                    'TWD ${job.payRate.toStringAsFixed(0)} / hr',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
