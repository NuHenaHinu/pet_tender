import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../dog_image_service.dart';
import '../../main.dart';
import '../../models/models.dart';

class BreedExplorerScreen extends StatefulWidget {
  const BreedExplorerScreen({super.key});

  @override
  State<BreedExplorerScreen> createState() => _BreedExplorerScreenState();
}

class _BreedExplorerScreenState extends State<BreedExplorerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _searchCtrl = TextEditingController();
  final _dio        = Dio();

  List<Breed> _dogs = [];
  List<Breed> _cats = [];
  bool        _loadingDogs = false;
  bool        _loadingCats = false;
  String?     _dogError;
  String?     _catError;
  String      _query = '';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(_onTabChanged);
    _fetchDogs();
  }

  @override
  void dispose() {
    _tabCtrl.removeListener(_onTabChanged);
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    _dio.close();
    super.dispose();
  }

  void _onTabChanged() {
    // Lazy-load cats the first time the tab is opened
    if (!_tabCtrl.indexIsChanging &&
        _tabCtrl.index == 1 &&
        _cats.isEmpty &&
        _catError == null &&
        !_loadingCats) {
      _fetchCats();
    }
  }

  // ── API calls ─────────────────────────────────────────────────────────────

  Future<void> _fetchDogs() async {
    setState(() { _loadingDogs = true; _dogError = null; });
    try {
      final res = await _dio.get<List<dynamic>>(
        'https://api.thedogapi.com/v1/breeds',
        options: Options(headers: {
          'x-api-key': dotenv.env['DOG_API_KEY'] ?? '',
        }),
      );
      if (!mounted) return;
      setState(() {
        _dogs = (res.data ?? [])
            .map((j) => Breed.fromDogJson(j as Map<String, dynamic>))
            .toList();
      });
    } catch (e) {
      debugPrint('Error fetching dog breeds: $e');
      if (mounted) setState(() => _dogError = 'Could not load dog breeds.');
    } finally {
      if (mounted) setState(() => _loadingDogs = false);
    }
  }

  Future<void> _fetchCats() async {
    setState(() { _loadingCats = true; _catError = null; });
    try {
      final res = await _dio.get<List<dynamic>>(
        'https://api.thecatapi.com/v1/breeds',
        options: Options(headers: {
          'x-api-key': dotenv.env['CAT_API_KEY'] ?? '',
        }),
      );
      if (!mounted) return;
      setState(() {
        _cats = (res.data ?? [])
            .map((j) => Breed.fromCatJson(j as Map<String, dynamic>))
            .toList();
      });
    } catch (e) {
      debugPrint('Error fetching cat breeds: $e');
      if (mounted) setState(() => _catError = 'Could not load cat breeds.');
    } finally {
      if (mounted) setState(() => _loadingCats = false);
    }
  }

  // ── Filtered lists ────────────────────────────────────────────────────────

  List<Breed> get _filteredDogs => _query.isEmpty
      ? _dogs
      : _dogs.where((b) => b.name.toLowerCase().contains(_query)).toList();

  List<Breed> get _filteredCats => _query.isEmpty
      ? _cats
      : _cats.where((b) => b.name.toLowerCase().contains(_query)).toList();

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isLoading = _tabCtrl.index == 0 ? _loadingDogs : _loadingCats;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Breed Explorer'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104), // search (52) + tabbar (52)
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) =>
                      setState(() => _query = v.toLowerCase().trim()),
                  decoration: InputDecoration(
                    hintText:   'Search breeds…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon:      const Icon(Icons.close),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                  ),
                ),
              ),
              TabBar(
                controller: _tabCtrl,
                tabs: const [
                  Tab(text: '🐶  Dogs'),
                  Tab(text: '🐱  Cats'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          if (isLoading) const LinearProgressIndicator(),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _BreedGrid(
                  breeds:    _filteredDogs,
                  isLoading: _loadingDogs,
                  error:     _dogError,
                  onRefresh: _fetchDogs,
                ),
                _BreedGrid(
                  breeds:    _filteredCats,
                  isLoading: _loadingCats,
                  error:     _catError,
                  onRefresh: _fetchCats,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Breed grid — shared by both tabs
// =============================================================================

class _BreedGrid extends StatelessWidget {
  const _BreedGrid({
    required this.breeds,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
  });

  final List<Breed>  breeds;
  final bool         isLoading;
  final String?      error;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (error != null && breeds.isEmpty) {
      return _ErrorState(message: error!, onRetry: onRefresh);
    }
    if (!isLoading && breeds.isEmpty) {
      return const _EmptyState();
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount:   2,
          crossAxisSpacing: 12,
          mainAxisSpacing:  12,
          childAspectRatio: 0.78,
        ),
        itemCount:   breeds.length,
        itemBuilder: (ctx, i) => _BreedCard(breed: breeds[i])
            .animate()
            .fadeIn(delay: Duration(milliseconds: i * 30))
            .slideY(begin: 0.1, duration: const Duration(milliseconds: 260)),
      ),
    );
  }
}

// =============================================================================
// Breed card
// =============================================================================

class _BreedCard extends StatelessWidget {
  const _BreedCard({required this.breed});
  final Breed breed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: () => Navigator.pushNamed(
          context,
          AppRoutes.breedDetail,
          arguments: breed,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Hero(
                tag:   'breed-${breed.id}',
                child: _buildImage(scheme),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    breed.name,
                    style:    Theme.of(context).textTheme.labelLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    breed.breedGroup ?? breed.origin ?? breed.lifeSpan,
                    style: TextStyle(fontSize: 11, color: scheme.outline),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(ColorScheme scheme) {
    // Cats: the Cat API embeds a direct image URL on the breed.
    if (breed.type == BreedType.cat) {
      return _network(breed.image?.url, scheme);
    }
    // Dogs: thedogapi has no usable per-breed image, so resolve via dog.ceo
    // (cached, so this only fetches once per breed).
    return FutureBuilder<String?>(
      future:  DogCeoImages.instance.imageFor(breed.name),
      builder: (_, snap) => _network(snap.data, scheme),
    );
  }

  Widget _network(String? url, ColorScheme scheme) {
    if (url == null || url.isEmpty) return _placeholder(scheme);
    return CachedNetworkImage(
      imageUrl:    url,
      fit:         BoxFit.cover,
      width:       double.infinity,
      placeholder: (_, _) => _placeholder(scheme),
      errorWidget: (_, _, _) => _placeholder(scheme),
    );
  }

  Widget _placeholder(ColorScheme scheme) => ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Center(
          child: Text(
            breed.type == BreedType.dog ? '🐶' : '🐱',
            style: const TextStyle(fontSize: 40),
          ),
        ),
      );
}

// =============================================================================
// Error state
// =============================================================================

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String   message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
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
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 20),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔍', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          Text('No breeds found',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Try a different search term.',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
