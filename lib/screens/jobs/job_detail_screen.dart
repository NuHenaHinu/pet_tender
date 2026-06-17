import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../backendless_client.dart';
import '../../main.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';

class JobDetailScreen extends StatefulWidget {
  final Job? job;

  const JobDetailScreen({super.key, this.job});

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  // Mutable copy of the job so status updates reflect immediately in UI.
  late Job _job;
  Job get _j => _job;

  bool _isBookmarked   = false;
  bool _isApplying     = false;

  // Sitter-only state — whether this sitter has already applied to this job.
  // Starts as "checking" so the Apply button shows a spinner until verified.
  bool _checkingApplication = true;
  Application? _myApplication;

  // Owner-only state
  List<Application> _applications = [];
  bool _loadingApps = false;
  bool _accepting   = false;

  @override
  void initState() {
    super.initState();
    _job = widget.job!;
    _loadBookmark();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final userId = context.read<AuthProvider>().user?.id;
      if (userId == _job.ownerId) {
        _fetchApplications();
      } else {
        _checkExistingApplication();
      }
    });
  }

  // ── Bookmark ──────────────────────────────────────────────────────────────

  Future<void> _loadBookmark() async {
    if (widget.job == null) return;
    final prefs     = await SharedPreferences.getInstance();
    final bookmarks = prefs.getStringList('bookmarks') ?? [];
    if (mounted) setState(() => _isBookmarked = bookmarks.contains(_j.id));
  }

  Future<void> _toggleBookmark() async {
    final prefs     = await SharedPreferences.getInstance();
    final bookmarks = prefs.getStringList('bookmarks') ?? [];
    _isBookmarked ? bookmarks.remove(_j.id) : bookmarks.add(_j.id);
    await prefs.setStringList('bookmarks', bookmarks);
    setState(() => _isBookmarked = !_isBookmarked);
  }

  // ── Apply (sitter) ────────────────────────────────────────────────────────

  /// Looks up whether the signed-in sitter has already applied to this job so
  /// the Apply button can be disabled — preventing duplicate application rows.
  Future<void> _checkExistingApplication() async {
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null || userId.isEmpty) {
      if (mounted) setState(() => _checkingApplication = false);
      return;
    }
    try {
      final raw = await BackendlessClient.instance.find(
        'Applications',
        where:    "sitterId='$userId' and jobId='${_job.id}'",
        sortBy:   'created DESC',
        pageSize: 1,
      );
      if (!mounted) return;
      setState(() {
        _myApplication =
            raw.isNotEmpty ? Application.fromJson(raw.first) : null;
        _checkingApplication = false;
      });
    } catch (_) {
      // Couldn't verify — don't hard-block; let the attempt proceed.
      if (mounted) setState(() => _checkingApplication = false);
    }
  }

  Future<void> _handleApply() async {
    if (_myApplication != null) return; // already applied — guard double taps
    final auth = context.read<AuthProvider>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   const Text('Apply for this job?'),
        content: Text('Send your application to ${_j.ownerName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:     const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:     const Text('Apply Now'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isApplying = true);
    try {
      final created = await BackendlessClient.instance.create(
        'Applications',
        Application(
          id:             '',
          jobId:          _j.id,
          jobOwnerId:     _j.ownerId,
          sitterId:       auth.user!.id,
          sitterName:     auth.user!.name,
          sitterPhotoUrl: auth.user?.profilePhotoUrl,
          status:         ApplicationStatus.pending,
          appliedAt:      DateTime.now(),
        ).toJson(),
      );
      if (!mounted) return;
      // Reflect immediately so the Apply button disables — no duplicate rows.
      setState(() => _myApplication = Application.fromJson(created));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Application sent! 🐾')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to apply. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  // ── Fetch applicants (owner) ──────────────────────────────────────────────

  Future<void> _fetchApplications() async {
    setState(() => _loadingApps = true);
    try {
      final raw = await BackendlessClient.instance.find(
        'Applications',
        where: "jobId='${_job.id}'",
        sortBy: 'created DESC',
      );
      if (mounted) {
        setState(() {
          _applications = raw.map((a) => Application.fromJson(a)).toList();
          _loadingApps  = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingApps = false);
    }
  }

  // ── Confirm completion (owner) ───────────────────────────────────────────

  Future<void> _confirmCompletion() async {
    // The sitter awaiting confirmation is the one we'll mark done and rate.
    final pendingApp = _applications
        .where((a) => a.status == ApplicationStatus.pendingConfirmation)
        .firstOrNull;

    // Combined confirm + star rating. Returns 1–5, or null if cancelled.
    final stars = await showDialog<int>(
      context: context,
      builder: (ctx) => _CompletionRatingDialog(
        sitterName: pendingApp?.sitterName ?? 'the sitter',
      ),
    );
    if (stars == null || !mounted) return;

    setState(() => _accepting = true);
    try {
      await BackendlessClient.instance.update(
        'Jobs', _job.id, {'status': 'closed'},
      );
      if (pendingApp != null) {
        await BackendlessClient.instance.update(
          'Applications', pendingApp.id, {'status': 'completed'},
        );
      }

      // Best-effort rating write — completion must not fail just because the
      // Users-table update was denied by permissions.
      String? ratingError;
      if (pendingApp != null && pendingApp.sitterId.isNotEmpty) {
        try {
          await _applyRating(pendingApp.sitterId, stars);
        } catch (_) {
          ratingError =
              'Job completed, but the rating couldn\'t be saved (check Users '
              'table permissions).';
        }
      }

      if (!mounted) return;
      setState(() {
        _job = _job.copyWith(status: JobStatus.closed);
        _applications = _applications.map((a) {
          if (a.status == ApplicationStatus.pendingConfirmation) {
            return a.copyWith(status: ApplicationStatus.completed);
          }
          return a;
        }).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ratingError ?? 'Job completed! Thanks for rating $stars★. 🐾',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to confirm: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  /// Folds a new star rating into the sitter's running average on their Users
  /// row: `newAvg = (oldAvg * oldCount + stars) / (oldCount + 1)`.
  Future<void> _applyRating(String sitterId, int stars) async {
    final row = await BackendlessClient.instance.findById('Users', sitterId);
    final oldRating = (row['rating'] as num?)?.toDouble() ?? 0.0;
    final oldCount = (row['ratingCount'] as num?)?.toInt() ?? 0;
    final newCount = oldCount + 1;
    final newRating = (oldRating * oldCount + stars) / newCount;
    await BackendlessClient.instance.update('Users', sitterId, {
      'rating': double.parse(newRating.toStringAsFixed(2)),
      'ratingCount': newCount,
    });
  }

  // ── Accept applicant (owner) ──────────────────────────────────────────────

  Future<void> _acceptApplicant(Application app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   const Text('Accept this sitter?'),
        content: Text(
          'Accept ${app.sitterName}? All other pending applications will be rejected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:     const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:     const Text('Accept'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _accepting = true);
    try {
      // Accept chosen applicant
      await BackendlessClient.instance.update(
        'Applications', app.id, {'status': 'accepted'},
      );
      // Mark job as in-progress
      await BackendlessClient.instance.update(
        'Jobs', _job.id, {'status': 'filled'},
      );
      // Reject remaining pending applications (fire and forget — non-critical)
      for (final other in _applications) {
        if (other.id != app.id && other.status == ApplicationStatus.pending) {
          BackendlessClient.instance
              .update('Applications', other.id, {'status': 'rejected'})
              .ignore();
        }
      }

      // Best-effort: schedule a local reminder 24h before the job starts.
      // Must not fail the accept flow if the platform rejects scheduling.
      try {
        await scheduleJobReminder(
          jobId:    _job.id.hashCode,
          jobTitle: _job.title,
          jobStart: _job.startDate,
        );
      } catch (_) {/* notifications unavailable — non-critical */}

      if (!mounted) return;
      setState(() {
        _job = _job.copyWith(status: JobStatus.filled);
        _applications = _applications.map((a) {
          if (a.id == app.id) return a.copyWith(status: ApplicationStatus.accepted);
          if (a.status == ApplicationStatus.pending) return a.copyWith(status: ApplicationStatus.rejected);
          return a;
        }).toList();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${app.sitterName} has been accepted!')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to accept: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.job == null) {
      return const Scaffold(body: Center(child: Text('Job not found')));
    }

    final auth    = context.watch<AuthProvider>();
    final scheme  = Theme.of(context).colorScheme;
    final isOwner = auth.user?.id == _j.ownerId;
    final date    = DateFormat('MMM d, y').format(_j.startDate);

    return Scaffold(
      bottomNavigationBar: _buildBottomBar(isOwner, scheme),
      body: CustomScrollView(
        slivers: [

          // ── SliverAppBar — Hero pet photo ──────────────────────────────
          SliverAppBar(
            expandedHeight: 240,
            pinned:         true,
            actions: [
              IconButton(
                tooltip:  _isBookmarked ? 'Remove bookmark' : 'Bookmark',
                icon:     Icon(
                  _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                ),
                onPressed: _toggleBookmark,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Hero(
                tag:   'job-${_j.id}',
                child: _j.photoUrl != null
                    ? CachedNetworkImage(
                        imageUrl:    _j.photoUrl!,
                        fit:         BoxFit.cover,
                        placeholder: (_, _) => _PhotoBg(_j.petType),
                        errorWidget: (_, _, _) => _PhotoBg(_j.petType),
                      )
                    : _PhotoBg(_j.petType),
              ),
            ),
          ),

          // ── Body ──────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // Status chip (only if not open)
                  if (!_j.status.isActive) ...[
                    _StatusChip(
                      label: _j.status.displayName,
                      bg: switch (_j.status) {
                        JobStatus.filled     => scheme.secondary.withValues(alpha: 0.12),
                        JobStatus.completing => Colors.orange.shade50,
                        _                   => Colors.green.shade50,
                      },
                      fg: switch (_j.status) {
                        JobStatus.filled     => scheme.secondary,
                        JobStatus.completing => Colors.orange.shade800,
                        _                   => Colors.green.shade700,
                      },
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Title
                  Text(
                    _j.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),

                  const SizedBox(height: 12),

                  // Pet type + breed chips
                  Wrap(
                    spacing: 8,
                    children: [
                      Chip(
                        avatar: Text(_j.petType.emoji),
                        label:  Text(_j.petType.displayName),
                      ),
                      if (_j.breedName != null)
                        Chip(label: Text(_j.breedName!)),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Pay + date
                  Row(
                    children: [
                      Icon(Icons.payments_outlined,
                          size: 16, color: scheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        '${_j.currency} ${_j.payRate.toStringAsFixed(0)} / hr',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color:      scheme.primary,
                          fontSize:   15,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Icon(Icons.calendar_today_outlined,
                          size: 15, color: scheme.outline),
                      const SizedBox(width: 6),
                      Text(date, style: TextStyle(color: scheme.outline)),
                    ],
                  ),

                  const Divider(height: 32),

                  // Description
                  Text('About the job',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(_j.description, style: const TextStyle(height: 1.6)),

                  const Divider(height: 32),

                  // Owner row
                  Text('Posted by',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundImage: _j.ownerPhotoUrl != null
                            ? CachedNetworkImageProvider(_j.ownerPhotoUrl!)
                            : null,
                        child: _j.ownerPhotoUrl == null
                            ? Text(_j.ownerName.isNotEmpty
                                  ? _j.ownerName[0].toUpperCase()
                                  : '?')
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _j.ownerName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize:   15,
                        ),
                      ),
                    ],
                  ),

                  const Divider(height: 32),

                  // Location + Google Map
                  Text('Location',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 15, color: scheme.outline),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _j.location.address,
                          style: TextStyle(color: scheme.outline),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 150,
                      child: GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: LatLng(
                            _j.location.latitude,
                            _j.location.longitude,
                          ),
                          zoom: 15,
                        ),
                        markers: {
                          Marker(
                            markerId: const MarkerId('job-location'),
                            position: LatLng(
                              _j.location.latitude,
                              _j.location.longitude,
                            ),
                          ),
                        },
                        zoomControlsEnabled:     false,
                        scrollGesturesEnabled:   false,
                        rotateGesturesEnabled:   false,
                        tiltGesturesEnabled:     false,
                        myLocationButtonEnabled: false,
                        zoomGesturesEnabled:     false,
                      ),
                    ),
                  ),

                  // ── Applicants section (owner only) ──────────────────
                  if (isOwner) ...[
                    const Divider(height: 40),
                    _buildApplicantsSection(scheme),
                  ],

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom bar ────────────────────────────────────────────────────────────

  Widget? _buildBottomBar(bool isOwner, ColorScheme scheme) {
    if (isOwner) return null;

    // Still verifying whether this sitter has already applied.
    if (_checkingApplication) {
      return _bottomBarShell(
        const FilledButton(
          onPressed: null,
          child: SizedBox(
            height: 20,
            width:  20,
            child:  CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    // Already applied — show the application's status instead of Apply.
    if (_myApplication != null) {
      final label = switch (_myApplication!.status) {
        ApplicationStatus.pending             => 'Application Sent',
        ApplicationStatus.accepted            => 'Application Accepted ✓',
        ApplicationStatus.rejected            => 'Application Not Selected',
        ApplicationStatus.withdrawn           => 'Application Withdrawn',
        ApplicationStatus.pendingConfirmation => 'Awaiting Owner Confirmation',
        ApplicationStatus.completed           => 'Job Completed',
      };
      return _bottomBarShell(
        FilledButton.tonal(onPressed: null, child: Text(label)),
      );
    }

    final label = switch (_j.status) {
      JobStatus.open       => 'Apply Now',
      JobStatus.filled     => 'Position Filled',
      JobStatus.completing => 'Awaiting Owner Confirmation',
      JobStatus.closed     => 'Job Completed',
    };
    final canApply = _j.status == JobStatus.open;

    return _bottomBarShell(
      FilledButton(
        onPressed: (canApply && !_isApplying) ? _handleApply : null,
        child: _isApplying
            ? const SizedBox(
                height: 20,
                width:  20,
                child:  CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white,
                ),
              )
            : Text(label),
      ),
    );
  }

  // Shared SafeArea + padding wrapper for the bottom action button.
  Widget _bottomBarShell(Widget child) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: child,
        ),
      );

  // ── Applicants section ────────────────────────────────────────────────────

  Widget _buildApplicantsSection(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // ── Completion confirmation banner ────────────────────────────────
        if (_job.status == JobStatus.completing) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:        Colors.orange.shade50,
              borderRadius: BorderRadius.circular(14),
              border:       Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.notifications_active_outlined,
                        color: Colors.orange.shade700),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Sitter marked this job as done',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color:      Colors.orange.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Please confirm if the job was completed satisfactorily.',
                  style: TextStyle(fontSize: 13, color: Colors.orange.shade700),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _accepting ? null : _confirmCompletion,
                    icon:  const Icon(Icons.verified_outlined),
                    label: const Text('Confirm Completion'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        Row(
          children: [
            Expanded(
              child: Text(
                'Applicants'
                '${_applications.isNotEmpty ? " (${_applications.length})" : ""}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (!_loadingApps)
              IconButton(
                tooltip:  'Refresh',
                icon:     const Icon(Icons.refresh_rounded),
                onPressed: _fetchApplications,
              ),
          ],
        ),

        if (_accepting || _loadingApps) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ],

        const SizedBox(height: 12),

        if (!_loadingApps && _applications.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Icon(Icons.inbox_outlined, size: 48, color: scheme.outline),
                  const SizedBox(height: 8),
                  Text('No applications yet',
                      style: TextStyle(color: scheme.outline)),
                ],
              ),
            ),
          )
        else
          ...(_applications.map(
            (app) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ApplicantCard(
                app:       app,
                jobStatus: _job.status,
                onAccept:  (_job.status == JobStatus.open &&
                                app.status == ApplicationStatus.pending &&
                                !_accepting)
                            ? () => _acceptApplicant(app)
                            : null,
              ),
            ),
          )),
      ],
    );
  }
}

// =============================================================================
// Applicant card (owner view) — expandable sitter bio
// =============================================================================

class _ApplicantCard extends StatefulWidget {
  const _ApplicantCard({
    required this.app,
    required this.jobStatus,
    required this.onAccept,
  });

  final Application   app;
  final JobStatus     jobStatus;
  final VoidCallback? onAccept;

  @override
  State<_ApplicantCard> createState() => _ApplicantCardState();
}

class _ApplicantCardState extends State<_ApplicantCard> {
  bool  _expanded       = false;
  bool  _loadingProfile = false;
  User? _profile;

  Future<void> _loadProfile() async {
    if (_profile != null || _loadingProfile) return;
    setState(() => _loadingProfile = true);
    try {
      final data = await BackendlessClient.instance.findById(
        'Users', widget.app.sitterId,
      );
      if (mounted) {
        setState(() {
          _profile        = User.fromJson(data);
          _loadingProfile = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
    if (_expanded) _loadProfile();
  }

  @override
  Widget build(BuildContext context) {
    final scheme     = Theme.of(context).colorScheme;
    final app        = widget.app;
    final isAccepted = app.status == ApplicationStatus.accepted;
    final isRejected = app.status == ApplicationStatus.rejected;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Header: avatar + name + date + status chip ───────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundImage: app.sitterPhotoUrl != null
                      ? CachedNetworkImageProvider(app.sitterPhotoUrl!)
                      : null,
                  child: app.sitterPhotoUrl == null
                      ? Text(
                          app.sitterName.isNotEmpty
                              ? app.sitterName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(fontSize: 18),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        app.sitterName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize:   15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Applied ${DateFormat("MMM d, y").format(app.appliedAt)}',
                        style: TextStyle(fontSize: 12, color: scheme.outline),
                      ),
                    ],
                  ),
                ),
                if (isAccepted)
                  _StatusChip(
                    label: 'Accepted',
                    bg:    Colors.green.shade50,
                    fg:    Colors.green.shade800,
                  )
                else if (isRejected)
                  _StatusChip(
                    label: 'Rejected',
                    bg:    scheme.errorContainer,
                    fg:    scheme.onErrorContainer,
                  )
                else if (app.status == ApplicationStatus.withdrawn)
                  _StatusChip(
                    label: 'Withdrawn',
                    bg:    scheme.surfaceContainerLow,
                    fg:    scheme.outline,
                  ),
              ],
            ),

            // ── Application message ───────────────────────────────────────
            if (app.message != null && app.message!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:        scheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(10),
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
                        style: const TextStyle(fontSize: 13, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── About this sitter (expandable) ────────────────────────────
            const SizedBox(height: 10),
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _toggleExpanded,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Row(
                    children: [
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'About this sitter',
                        style: TextStyle(
                          fontSize:   13,
                          fontWeight: FontWeight.w600,
                          color:      scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve:    Curves.easeInOut,
              child:    _expanded
                  ? _buildProfileDetail(scheme)
                  : const SizedBox.shrink(),
            ),

            // ── Accept button ─────────────────────────────────────────────
            if (widget.onAccept != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: widget.onAccept,
                  child: const Text('Accept this sitter'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProfileDetail(ColorScheme scheme) {
    if (_loadingProfile) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_profile == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Could not load profile.',
          style: TextStyle(color: scheme.outline, fontSize: 13),
        ),
      );
    }

    final u = _profile!;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Rating stars
          Row(
            children: [
              ..._buildStars(u.rating),
              const SizedBox(width: 6),
              Text(
                u.rating > 0
                    ? u.rating.toStringAsFixed(1)
                    : 'No rating yet',
                style: TextStyle(
                  fontSize:   13,
                  fontWeight: FontWeight.w600,
                  color: u.rating > 0
                      ? Colors.amber.shade700
                      : scheme.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Member since + role
          Wrap(
            spacing:   16,
            runSpacing: 4,
            children: [
              _InfoRow(
                icon:  Icons.calendar_today_outlined,
                label: 'Member since ${DateFormat("MMM y").format(u.createdAt)}',
                scheme: scheme,
              ),
              _InfoRow(
                icon:  Icons.badge_outlined,
                label: u.role.displayName,
                scheme: scheme,
              ),
            ],
          ),

          // Bio
          const SizedBox(height: 10),
          u.bio != null && u.bio!.isNotEmpty
              ? Text(
                  u.bio!,
                  style: const TextStyle(fontSize: 13, height: 1.55),
                )
              : Text(
                  'No bio provided.',
                  style: TextStyle(fontSize: 13, color: scheme.outline),
                ),

          // Phone
          if (u.phoneNumber != null && u.phoneNumber!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _InfoRow(
              icon:  Icons.phone_outlined,
              label: u.phoneNumber!,
              scheme: scheme,
            ),
          ],

          const SizedBox(height: 4),
        ],
      ),
    );
  }

  List<Widget> _buildStars(double rating) {
    return List.generate(5, (i) {
      final full = i + 1;
      final IconData icon;
      if (rating >= full) {
        icon = Icons.star_rounded;
      } else if (rating >= full - 0.5) {
        icon = Icons.star_half_rounded;
      } else {
        icon = Icons.star_outline_rounded;
      }
      return Icon(icon, size: 16, color: Colors.amber.shade600);
    });
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.scheme});
  final IconData     icon;
  final String       label;
  final ColorScheme  scheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: scheme.outline),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurface)),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.bg, required this.fg});

  final String label;
  final Color  bg;
  final Color  fg;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: bg,
      labelStyle: TextStyle(color: fg, fontWeight: FontWeight.w600),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

// ── Photo placeholder ─────────────────────────────────────────────────────────

class _PhotoBg extends StatelessWidget {
  const _PhotoBg(this.petType);
  final PetType petType;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Text(petType.emoji, style: const TextStyle(fontSize: 64)),
      ),
    );
  }
}

// =============================================================================
// Confirm-completion dialog with a 1–5 star rating (owner rates the sitter)
// =============================================================================

class _CompletionRatingDialog extends StatefulWidget {
  const _CompletionRatingDialog({required this.sitterName});
  final String sitterName;

  @override
  State<_CompletionRatingDialog> createState() =>
      _CompletionRatingDialogState();
}

class _CompletionRatingDialogState extends State<_CompletionRatingDialog> {
  int _stars = 0;

  static const _labels = ['Tap to rate', 'Poor', 'Fair', 'Good', 'Great', 'Excellent'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Confirm & rate'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Confirm that ${widget.sitterName} finished the job, '
            'and rate your experience.',
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int i = 1; i <= 5; i++)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 34,
                  onPressed: () => setState(() => _stars = i),
                  icon: Icon(
                    i <= _stars
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: Colors.amber.shade600,
                  ),
                ),
            ],
          ),
          Text(
            _labels[_stars],
            style: TextStyle(color: scheme.outline, fontSize: 13),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _stars == 0 ? null : () => Navigator.pop(context, _stars),
          child: const Text('Complete'),
        ),
      ],
    );
  }
}
