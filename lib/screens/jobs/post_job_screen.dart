import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../backendless_client.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/job_provider.dart';
import '../main_shell.dart';

class PostJobScreen extends StatefulWidget {
  const PostJobScreen({super.key});

  @override
  State<PostJobScreen> createState() => _PostJobScreenState();
}

class _PostJobScreenState extends State<PostJobScreen> {
  final _formKey      = GlobalKey<FormState>();
  final _titleCtrl    = TextEditingController();
  final _descCtrl     = TextEditingController();
  final _payCtrl      = TextEditingController();
  final _durationCtrl = TextEditingController();

  PetType      _petType      = PetType.dog;
  String?      _breedName;
  XFile?       _photo;
  DateTime?    _startDate;
  TimeOfDay?   _startTime;
  JobLocation? _location;
  bool         _isSubmitting = false;

  final _dio = Dio();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _payCtrl.dispose();
    _durationCtrl.dispose();
    _dio.close();
    super.dispose();
  }

  // ── Photo ─────────────────────────────────────────────────────────────────

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1200,
    );
    if (picked != null) setState(() => _photo = picked);
  }

  Future<String?> _uploadPhoto(XFile file) async {
    try {
      final ext      = file.path.split('.').last.toLowerCase();
      final filename = 'job_${DateTime.now().millisecondsSinceEpoch}.$ext';
      return await BackendlessClient.instance.uploadFile(
        path:     'jobs',
        filename: filename,
        filePath: file.path,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Reset ─────────────────────────────────────────────────────────────────

  void _resetForm() {
    _formKey.currentState?.reset();
    _titleCtrl.clear();
    _descCtrl.clear();
    _payCtrl.clear();
    _durationCtrl.clear();
    setState(() {
      _petType   = PetType.dog;
      _breedName = null;
      _photo     = null;
      _startDate = null;
      _startTime = null;
      _location  = null;
    });
  }

  // ── Date / time ───────────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context:     context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate:   DateTime.now(),
      lastDate:    DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context:     context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) setState(() => _startTime = picked);
  }

  // ── Breed autocomplete ────────────────────────────────────────────────────

  Future<Iterable<String>> _breedOptions(TextEditingValue value) async {
    if (value.text.length < 2) return const [];
    try {
      final isDog  = _petType == PetType.dog;
      final url    = isDog
          ? 'https://api.thedogapi.com/v1/breeds/search'
          : 'https://api.thecatapi.com/v1/breeds/search';
      final apiKey = dotenv.env[isDog ? 'DOG_API_KEY' : 'CAT_API_KEY'] ?? '';
      final res = await _dio.get<List<dynamic>>(
        url,
        queryParameters: {'q': value.text},
        options: Options(headers: {'x-api-key': apiKey}),
      );
      return (res.data ?? []).map((b) => b['name'] as String);
    } catch (_) {
      return const [];
    }
  }

  // ── Location picker ───────────────────────────────────────────────────────

  Future<void> _openLocationPicker() async {
    final result = await Navigator.push<JobLocation>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _LocationPickerScreen(initial: _location),
      ),
    );
    if (result != null) setState(() => _location = result);
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a start date.')),
      );
      return;
    }
    if (_location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set a job location.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final auth  = context.read<AuthProvider>();
      final time  = _startTime ?? const TimeOfDay(hour: 9, minute: 0);
      final start = DateTime(
        _startDate!.year, _startDate!.month, _startDate!.day,
        time.hour, time.minute,
      );
      final duration = int.tryParse(_durationCtrl.text.trim());

      String? photoUrl;
      if (_photo != null) photoUrl = await _uploadPhoto(_photo!);

      final job = Job(
        id:            '',
        title:         _titleCtrl.text.trim(),
        description:   _descCtrl.text.trim(),
        ownerId:       auth.user!.id,
        ownerName:     auth.user!.name,
        ownerPhotoUrl: auth.user?.profilePhotoUrl,
        petType:       _petType,
        breedName:     (_breedName?.isNotEmpty ?? false) ? _breedName : null,
        photoUrl:      photoUrl,
        payRate:       double.parse(_payCtrl.text.trim()),
        currency:      'TWD',
        startDate:     start,
        durationHours: duration,
        location:      _location!,
        status:        JobStatus.open,
        createdAt:     DateTime.now(),
      );

      await BackendlessClient.instance.create('Jobs', job.toJson());

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title:   const Text('Job Posted! 🐾'),
          content: const Text('Your listing is now live.'),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _resetForm();
                context.read<JobProvider>().fetchJobs();
                MainShell.of(context)?.jumpTo(MainShell.tabHome);
              },
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to post job: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Post a Job')),
      body: Column(
        children: [
          if (_isSubmitting) const LinearProgressIndicator(),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildPhotoPicker(scheme),
                  const SizedBox(height: 24),
                  _sectionHeader('Job Details'),
                  const SizedBox(height: 12),
                  _buildTitleField(),
                  const SizedBox(height: 12),
                  _buildDescField(),
                  const SizedBox(height: 24),
                  _sectionHeader('Pet'),
                  const SizedBox(height: 12),
                  _buildPetTypeDropdown(),
                  if (_petType != PetType.other) ...[
                    const SizedBox(height: 12),
                    _buildBreedAutocomplete(scheme),
                  ],
                  const SizedBox(height: 24),
                  _sectionHeader('Pay Rate'),
                  const SizedBox(height: 12),
                  _buildPayField(),
                  const SizedBox(height: 24),
                  _sectionHeader('Schedule'),
                  const SizedBox(height: 12),
                  _buildDateTile(scheme),
                  const SizedBox(height: 8),
                  _buildTimeTile(scheme),
                  const SizedBox(height: 8),
                  _buildDurationField(),
                  const SizedBox(height: 24),
                  _sectionHeader('Location'),
                  const SizedBox(height: 12),
                  _buildLocationTile(scheme),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _isSubmitting ? null : _submit,
                    child: const Text('Post Job'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section widgets ───────────────────────────────────────────────────────

  Widget _sectionHeader(String title) => Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color:      Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      );

  Widget _buildPhotoPicker(ColorScheme scheme) => GestureDetector(
        onTap: _pickPhoto,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: _photo != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(File(_photo!.path), fit: BoxFit.cover),
                      Positioned(
                        bottom: 8, right: 8,
                        child: FloatingActionButton.small(
                          heroTag:   'photo_edit',
                          onPressed: _pickPhoto,
                          child:     const Icon(Icons.edit),
                        ),
                      ),
                    ],
                  )
                : ColoredBox(
                    color: scheme.surfaceContainerLow,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined,
                            size: 48, color: scheme.outline),
                        const SizedBox(height: 8),
                        Text('Add a photo (optional)',
                            style: TextStyle(color: scheme.outline)),
                      ],
                    ),
                  ),
          ),
        ),
      );

  Widget _buildTitleField() => TextFormField(
        controller:          _titleCtrl,
        textCapitalization:  TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Job title',
          hintText:  'e.g. Dog walker needed for weekend',
        ),
        validator: (v) =>
            v == null || v.trim().isEmpty ? 'Title is required' : null,
      );

  Widget _buildDescField() => TextFormField(
        controller:         _descCtrl,
        maxLines:           4,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText:          'Description',
          hintText:           'Describe the job and any special requirements',
          alignLabelWithHint: true,
        ),
        validator: (v) =>
            v == null || v.trim().isEmpty ? 'Description is required' : null,
      );

  Widget _buildPetTypeDropdown() => DropdownButtonFormField<PetType>(
        initialValue:      _petType,
        decoration: const InputDecoration(labelText: 'Pet type'),
        items: PetType.values
            .map((t) => DropdownMenuItem(
                  value: t,
                  child: Text('${t.emoji}  ${t.displayName}'),
                ))
            .toList(),
        onChanged: (v) {
          if (v != null) setState(() { _petType = v; _breedName = null; });
        },
      );

  Widget _buildBreedAutocomplete(ColorScheme scheme) => Autocomplete<String>(
        key:            ValueKey(_petType),
        optionsBuilder: _breedOptions,
        onSelected:     (name) => setState(() => _breedName = name),
        fieldViewBuilder: (ctx, ctrl, focusNode, _) => TextFormField(
          controller:  ctrl,
          focusNode:   focusNode,
          decoration: const InputDecoration(
            labelText: 'Breed (optional)',
            hintText:  'Start typing to search…',
          ),
          onChanged: (v) => _breedName = v.isEmpty ? null : v,
        ),
        optionsViewBuilder: (ctx, onSelected, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation:    4,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap:  true,
                padding:     EdgeInsets.zero,
                itemCount:   options.length,
                itemBuilder: (_, i) {
                  final name = options.elementAt(i);
                  return ListTile(
                    title: Text(name),
                    onTap:  () => onSelected(name),
                  );
                },
              ),
            ),
          ),
        ),
      );

  Widget _buildPayField() => TextFormField(
        controller:      _payCtrl,
        keyboardType:    const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
        ],
        decoration: const InputDecoration(
          labelText:  'Pay rate',
          prefixText: 'TWD ',
          suffixText: '/ hr',
        ),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'Pay rate is required';
          if (double.tryParse(v.trim()) == null) return 'Enter a valid number';
          return null;
        },
      );

  Widget _buildDateTile(ColorScheme scheme) {
    final label = _startDate != null
        ? DateFormat('MMM d, y').format(_startDate!)
        : null;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      shape:       RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tileColor:   scheme.surfaceContainerLowest,
      leading:     Icon(Icons.calendar_today_outlined, color: scheme.primary),
      title:       const Text('Start date'),
      subtitle:    label != null ? Text(label) : null,
      trailing: _startDate == null
          ? Text('Required', style: TextStyle(color: scheme.error, fontSize: 12))
          : null,
      onTap: _pickDate,
    );
  }

  Widget _buildTimeTile(ColorScheme scheme) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        shape:     RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: scheme.surfaceContainerLowest,
        leading:   Icon(Icons.access_time_outlined, color: scheme.primary),
        title:     const Text('Start time'),
        subtitle:  Text(_startTime != null
            ? _startTime!.format(context)
            : '9:00 AM (default)'),
        onTap: _pickTime,
      );

  Widget _buildDurationField() => TextFormField(
        controller:      _durationCtrl,
        keyboardType:    TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          labelText:  'Duration (optional)',
          suffixText: 'hours',
          hintText:   'e.g. 3',
        ),
      );

  Widget _buildLocationTile(ColorScheme scheme) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        shape:     RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: scheme.surfaceContainerLowest,
        leading:   Icon(
          Icons.location_on_outlined,
          color: _location != null ? scheme.primary : scheme.outline,
        ),
        title: Text(
          _location?.address ?? 'Tap to set location',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _location != null ? null : scheme.outline,
          ),
        ),
        trailing: _location == null
            ? Text('Required',
                style: TextStyle(color: scheme.error, fontSize: 12))
            : const Icon(Icons.chevron_right),
        onTap: _openLocationPicker,
      );
}

// =============================================================================
// Location Picker Screen
// =============================================================================

class _LocationPickerScreen extends StatefulWidget {
  const _LocationPickerScreen({this.initial});
  final JobLocation? initial;

  @override
  State<_LocationPickerScreen> createState() =>
      _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<_LocationPickerScreen> {
  static const _taipei = LatLng(25.0330, 121.5654);

  late LatLng          _markerPos;
  final _addressCtrl = TextEditingController();
  GoogleMapController?  _mapCtrl;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _markerPos        = LatLng(widget.initial!.latitude, widget.initial!.longitude);
      _addressCtrl.text = widget.initial!.address;
    } else {
      _markerPos = _taipei;
    }
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _mapCtrl?.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_addressCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an address.')),
      );
      return;
    }
    Navigator.pop(
      context,
      JobLocation(
        address:   _addressCtrl.text.trim(),
        latitude:  _markerPos.latitude,
        longitude: _markerPos.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Location'),
        actions: [
          TextButton(
            onPressed: _confirm,
            child:     const Text('Confirm'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _markerPos,
                zoom:   14,
              ),
              onMapCreated: (ctrl) => _mapCtrl = ctrl,
              onTap: (pos) => setState(() => _markerPos = pos),
              markers: {
                Marker(
                  markerId:  const MarkerId('pick'),
                  position:  _markerPos,
                  draggable: true,
                  onDragEnd: (pos) => setState(() => _markerPos = pos),
                ),
              },
              myLocationButtonEnabled: false,
              zoomControlsEnabled:     true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller:         _addressCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText:  'Address',
                    hintText:   'Type the full address',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Drag the pin or tap the map to set the exact spot.',
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
