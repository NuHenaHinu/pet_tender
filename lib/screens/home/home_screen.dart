import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../main.dart';
import '../../models/models.dart';
import '../../providers/job_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<JobProvider>().fetchJobs(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<JobProvider>();
    final jobs = prov.filteredJobs;

    return Scaffold(
      appBar: AppBar(title: const Text('PeTender 🐾')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (prov.isLoading) const LinearProgressIndicator(),

          // Pet type filter chips
          const _FilterChips(),

          Expanded(child: _buildBody(prov, jobs)),
        ],
      ),
    );
  }

  Widget _buildBody(JobProvider prov, List<Job> jobs) {
    // Requirement: error state
    if (prov.error != null && jobs.isEmpty) {
      return _ErrorState(
        onRetry: () => context.read<JobProvider>().fetchJobs(),
      );
    }

    // Requirement: empty state
    if (jobs.isEmpty && !prov.isLoading) {
      return const _EmptyState();
    }

    // Requirement: pull-to-refresh
    return RefreshIndicator(
      onRefresh: context.read<JobProvider>().fetchJobs,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: jobs.length,
        itemBuilder: (ctx, i) {
          final j = jobs[i];
          // Requirement: animation — staggered fade + slide per card
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _JobCard(job: j)
                .animate()
                .fadeIn(delay: Duration(milliseconds: i * 60))
                .slideY(
                  begin: 0.15,
                  duration: const Duration(milliseconds: 300),
                ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// Filter chips — All / Dog / Cat / Other
// =============================================================================

class _FilterChips extends StatelessWidget {
  const _FilterChips();

  @override
  Widget build(BuildContext context) {
    final prov   = context.watch<JobProvider>();
    final active = prov.filterType;

    const filters = <PetType?>[null, PetType.dog, PetType.cat, PetType.other];
    const labels  = <String>['All', '🐶 Dog', '🐱 Cat', '🐰 Other'];

    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection:  Axis.horizontal,
        padding:          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount:        filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => FilterChip(
          label:      Text(labels[i]),
          selected:   active == filters[i],
          onSelected: (_) =>
              context.read<JobProvider>().setFilter(filters[i]),
        ),
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date   = DateFormat('MMM d, y').format(job.startDate);

    return Card(
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: () => Navigator.pushNamed(
          context,
          AppRoutes.jobDetail,
          arguments: job,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pet photo — height 140, cover fit
            SizedBox(
              height: 140,
              width:  double.infinity,
              child:  job.photoUrl != null
                  ? CachedNetworkImage(
                      imageUrl:    job.photoUrl!,
                      fit:         BoxFit.cover,
                      placeholder: (_, _) => _PhotoPlaceholder(job.petType),
                      errorWidget: (_, _, _) =>
                          _PhotoPlaceholder(job.petType),
                    )
                  : _PhotoPlaceholder(job.petType),
            ),

            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row + breed chip
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          job.title,
                          style:    Theme.of(context).textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (job.breedName != null) ...[
                        const SizedBox(width: 8),
                        Chip(
                          label:               Text(job.breedName!),
                          labelStyle:          const TextStyle(fontSize: 11),
                          padding:             EdgeInsets.zero,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 6),

                  // Pay + date
                  Row(
                    children: [
                      Icon(Icons.payments_outlined,
                          size: 14, color: scheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        '${job.currency} ${job.payRate.toStringAsFixed(0)}/hr',
                        style: TextStyle(
                          fontSize:   12,
                          color:      scheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.calendar_today_outlined,
                          size: 13, color: scheme.outline),
                      const SizedBox(width: 4),
                      Text(
                        date,
                        style: TextStyle(fontSize: 12, color: scheme.outline),
                      ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  // Location
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 13, color: scheme.outline),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          job.location.address,
                          style:    TextStyle(
                              fontSize: 12, color: scheme.outline),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Photo placeholder — shown when photoUrl is null or image load fails
// =============================================================================

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder(this.petType);
  final PetType petType;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Text(petType.emoji, style: const TextStyle(fontSize: 48)),
      ),
    );
  }
}

// =============================================================================
// Error state
// =============================================================================

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final msg = context.watch<JobProvider>().error
        ?? 'Could not load jobs. Check your connection.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded,
                size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              msg,
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 20),
            FilledButton.tonal(
              onPressed: onRetry,
              child:     const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Empty state
// =============================================================================

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🐾', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(
              'No jobs found',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different filter or check back later.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}