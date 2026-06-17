import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../main.dart';
import '../../models/models.dart';
import '../../providers/job_provider.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final TextEditingController _searchCtrl;

  // Local filters applied on top of JobProvider's pet-type filter
  RangeValues _payRange        = const RangeValues(0, 5000);
  DateTime?   _startDateFilter;
  bool        _filtersActive   = false;

  @override
  void initState() {
    super.initState();
    final query = context.read<JobProvider>().searchQuery;
    _searchCtrl = TextEditingController(text: query)
      // Place cursor at end so the existing text isn't clobbered
      ..selection = TextSelection.collapsed(offset: query.length);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  List<Job> _applyLocalFilters(List<Job> jobs) {
    if (!_filtersActive) return jobs;
    return jobs.where((j) {
      final payOk  = j.payRate >= _payRange.start && j.payRate <= _payRange.end;
      final dateOk = _startDateFilter == null ||
          !j.startDate.isBefore(_startDateFilter!);
      return payOk && dateOk;
    }).toList();
  }

  bool get _hasLocalFilters =>
      _payRange != const RangeValues(0, 5000) || _startDateFilter != null;

  void _clearAll(JobProvider prov) {
    prov.clearFilters();
    _searchCtrl.clear();
    setState(() {
      _payRange        = const RangeValues(0, 5000);
      _startDateFilter = null;
      _filtersActive   = false;
    });
  }

  // ── Filter bottom sheet ────────────────────────────────────────────────────

  Future<void> _showFilters(BuildContext context, JobProvider prov) async {
    // Local copies so we can cancel
    var tempPetType   = prov.filterType;
    var tempPayRange  = _payRange;
    var tempStartDate = _startDateFilter;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final scheme = Theme.of(ctx).colorScheme;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20, 20, 20,
              20 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle + title
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color:        scheme.outline.withAlpha(80),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Filters',
                    style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 20),

                // Pet type
                Text('Pet Type',
                    style: Theme.of(ctx).textTheme.labelLarge),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    FilterChip(
                      label:    const Text('All'),
                      selected: tempPetType == null,
                      onSelected: (_) =>
                          setSheetState(() => tempPetType = null),
                    ),
                    ...PetType.values.map((t) => FilterChip(
                          label:    Text('${t.emoji} ${t.displayName}'),
                          selected: tempPetType == t,
                          onSelected: (_) =>
                              setSheetState(() => tempPetType = t),
                        )),
                  ],
                ),
                const SizedBox(height: 20),

                // Pay rate range
                Text('Pay Rate (TWD/hr)',
                    style: Theme.of(ctx).textTheme.labelLarge),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${tempPayRange.start.round()}',
                      style: TextStyle(
                          fontSize: 12, color: scheme.outline),
                    ),
                    Text(
                      tempPayRange.end >= 5000
                          ? '5000+'
                          : '${tempPayRange.end.round()}',
                      style: TextStyle(
                          fontSize: 12, color: scheme.outline),
                    ),
                  ],
                ),
                RangeSlider(
                  values:    tempPayRange,
                  min:       0,
                  max:       5000,
                  divisions: 50,
                  labels:    RangeLabels(
                    '${tempPayRange.start.round()}',
                    tempPayRange.end >= 5000
                        ? '5000+'
                        : '${tempPayRange.end.round()}',
                  ),
                  onChanged: (v) =>
                      setSheetState(() => tempPayRange = v),
                ),
                const SizedBox(height: 12),

                // Start date
                Text('Earliest Start Date',
                    style: Theme.of(ctx).textTheme.labelLarge),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today_outlined,
                            size: 16),
                        label: Text(
                          tempStartDate != null
                              ? DateFormat('MMM d, y').format(tempStartDate!)
                              : 'Any date',
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate:
                                tempStartDate ?? DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now()
                                .add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setSheetState(() => tempStartDate = picked);
                          }
                        },
                      ),
                    ),
                    if (tempStartDate != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () =>
                            setSheetState(() => tempStartDate = null),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 24),

                // Apply / Reset
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setSheetState(() {
                            tempPetType   = null;
                            tempPayRange  =
                                const RangeValues(0, 5000);
                            tempStartDate = null;
                          });
                        },
                        child: const Text('Reset'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () {
                          prov.setFilter(tempPetType);
                          setState(() {
                            _payRange        = tempPayRange;
                            _startDateFilter = tempStartDate;
                            _filtersActive   = _hasLocalFilters ||
                                tempPetType != null;
                          });
                          Navigator.pop(ctx);
                        },
                        child: const Text('Apply'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final prov    = context.watch<JobProvider>();
    final results = _applyLocalFilters(prov.filteredJobs);
    final scheme  = Theme.of(context).colorScheme;

    final hasActiveFilters =
        prov.filterType != null || _hasLocalFilters;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
        actions: [
          if (hasActiveFilters)
            TextButton(
              onPressed: () => _clearAll(prov),
              child: const Text('Clear'),
            ),
          IconButton(
            icon: Badge(
              isLabelVisible: hasActiveFilters,
              child: const Icon(Icons.tune_rounded),
            ),
            tooltip: 'Filters',
            onPressed: () => _showFilters(context, prov),
          ),
        ],
      ),
      body: Column(
        children: [
          if (prov.isLoading) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller:  _searchCtrl,
              autofocus:   false,
              decoration:  InputDecoration(
                hintText:    'Search jobs, breeds, locations…',
                prefixIcon:  const Icon(Icons.search),
                suffixIcon:  _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon:      const Icon(Icons.close),
                        onPressed: () {
                          _searchCtrl.clear();
                          prov.setSearch('');
                        },
                      )
                    : null,
                filled:      true,
                fillColor:   scheme.surfaceContainerLowest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide:   BorderSide.none,
                ),
              ),
              onChanged: (v) {
                prov.setSearch(v);
                setState(() {}); // refresh suffix icon
              },
            ),
          ),
          const SizedBox(height: 8),

          // Active filter chips row
          if (hasActiveFilters)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  if (prov.filterType != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Chip(
                        label: Text(
                            '${prov.filterType!.emoji} ${prov.filterType!.displayName}'),
                        onDeleted: () => prov.setFilter(null),
                      ),
                    ),
                  if (_payRange != const RangeValues(0, 5000))
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Chip(
                        label: Text(
                            'TWD ${_payRange.start.round()}–${_payRange.end >= 5000 ? "5000+" : _payRange.end.round()}/hr'),
                        onDeleted: () => setState(
                            () => _payRange = const RangeValues(0, 5000)),
                      ),
                    ),
                  if (_startDateFilter != null)
                    Chip(
                      label: Text(
                          'From ${DateFormat('MMM d').format(_startDateFilter!)}'),
                      onDeleted: () =>
                          setState(() => _startDateFilter = null),
                    ),
                ],
              ),
            ),

          const SizedBox(height: 4),

          Expanded(
            child: results.isEmpty && !prov.isLoading
                ? _EmptyState(
                    hasQuery: _searchCtrl.text.isNotEmpty ||
                        hasActiveFilters,
                  )
                : RefreshIndicator(
                    onRefresh: prov.fetchJobs,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: results.length,
                      itemBuilder: (ctx, i) => _JobCard(job: results[i])
                          .animate()
                          .fadeIn(
                              delay:
                                  Duration(milliseconds: i * 40))
                          .slideY(
                              begin: 0.06,
                              duration:
                                  const Duration(milliseconds: 250)),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Job card — identical style to HomeScreen
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
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () =>
            Navigator.pushNamed(context, AppRoutes.jobDetail, arguments: job),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 130,
              width:  double.infinity,
              child:  job.photoUrl != null
                  ? CachedNetworkImage(
                      imageUrl:    job.photoUrl!,
                      fit:         BoxFit.cover,
                      placeholder: (_, _) =>
                          _PhotoPlaceholder(job.petType),
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
                          label:    Text(job.breedName!),
                          labelStyle: const TextStyle(fontSize: 11),
                          padding:  EdgeInsets.zero,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
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
                      Text(date,
                          style: TextStyle(
                              fontSize: 12, color: scheme.outline)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 13, color: scheme.outline),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          job.location.address,
                          style: TextStyle(
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
// Photo placeholder
// =============================================================================

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder(this.petType);
  final PetType petType;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: Text(petType.emoji, style: const TextStyle(fontSize: 48)),
        ),
      );
}

// =============================================================================
// Empty state
// =============================================================================

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasQuery});
  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(hasQuery ? '🔍' : '💼',
                style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(
              hasQuery ? 'No jobs found' : 'Start searching',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              hasQuery
                  ? 'Try a different keyword or adjust your filters.'
                  : 'Type a job title, breed, or location above.',
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
