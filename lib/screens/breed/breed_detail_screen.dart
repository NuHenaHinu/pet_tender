import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../dog_image_service.dart';
import '../../models/models.dart';

class BreedDetailScreen extends StatefulWidget {
  final Breed? breed;

  const BreedDetailScreen({super.key, this.breed});

  @override
  State<BreedDetailScreen> createState() => _BreedDetailScreenState();
}

class _BreedDetailScreenState extends State<BreedDetailScreen> {
  final _dio      = Dio();
  final _pageCtrl = PageController();

  List<String> _galleryUrls    = [];
  bool         _loadingGallery = false;
  int          _currentPage    = 0;
  bool         _statsAnimated  = false;

  @override
  void initState() {
    super.initState();
    if (widget.breed != null) {
      _fetchGallery();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _statsAnimated = true);
      });
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _dio.close();
    super.dispose();
  }

  // ── Gallery fetch ──────────────────────────────────────────────────────────

  Future<void> _fetchGallery() async {
    final breed = widget.breed!;
    setState(() => _loadingGallery = true);
    try {
      List<String> urls;

      if (breed.type == BreedType.dog) {
        // thedogapi ignores breed_ids (returns random dogs), so use dog.ceo,
        // which is keyed by breed name. Empty if the breed has no match.
        urls = await DogCeoImages.instance.galleryFor(breed.name, count: 6);
      } else {
        // The Cat API supports breed_ids filtering and embeds a hero image.
        final res = await _dio.get<List<dynamic>>(
          'https://api.thecatapi.com/v1/images/search',
          queryParameters: {'breed_ids': breed.id, 'limit': 6},
          options: Options(
              headers: {'x-api-key': dotenv.env['CAT_API_KEY'] ?? ''}),
        );
        urls = (res.data ?? [])
            .map((j) => (j as Map<String, dynamic>)['url'] as String?)
            .whereType<String>()
            .toList();
        final heroUrl = breed.image?.url;
        if (heroUrl != null && heroUrl.isNotEmpty) {
          urls.remove(heroUrl);
          urls.insert(0, heroUrl);
        }
      }

      if (mounted) setState(() => _galleryUrls = urls);
    } catch (_) {
      final heroUrl = breed.image?.url;
      if (mounted) {
        setState(() => _galleryUrls = [
              if (heroUrl != null && heroUrl.isNotEmpty) heroUrl,
            ]);
      }
    } finally {
      if (mounted) setState(() => _loadingGallery = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.breed == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Breed not found.')),
      );
    }

    final breed  = widget.breed!;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(breed, scheme),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + type chip
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          breed.name,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Chip(
                        label: Text(
                            breed.type == BreedType.dog ? '🐶 Dog' : '🐱 Cat'),
                        backgroundColor: scheme.secondaryContainer,
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ).animate().fadeIn().slideY(begin: 0.2),

                  const SizedBox(height: 20),

                  // Info tiles
                  _InfoGrid(breed: breed, scheme: scheme)
                      .animate()
                      .fadeIn(delay: 80.ms),

                  const SizedBox(height: 24),

                  // Temperament chips
                  if (breed.temperamentList.isNotEmpty) ...[
                    _sectionTitle(context, 'Temperament'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: breed.temperamentList
                          .map((t) => Chip(
                                label: Text(t,
                                    style: const TextStyle(fontSize: 12)),
                                backgroundColor: scheme.surfaceContainerLow,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ))
                          .toList(),
                    ).animate().fadeIn(delay: 120.ms),
                    const SizedBox(height: 24),
                  ],

                  // Cat-only trait bars
                  if (breed.type == BreedType.cat) ...[
                    _sectionTitle(context, 'Traits'),
                    const SizedBox(height: 14),
                    _TraitBar(label: 'Energy',         value: breed.traitNormalised(breed.energyLevel),    animate: _statsAnimated, delay: 0),
                    _TraitBar(label: 'Affection',      value: breed.traitNormalised(breed.affectionLevel), animate: _statsAnimated, delay: 60),
                    _TraitBar(label: 'Child Friendly', value: breed.traitNormalised(breed.childFriendly),  animate: _statsAnimated, delay: 120),
                    _TraitBar(label: 'Dog Friendly',   value: breed.traitNormalised(breed.dogFriendly),    animate: _statsAnimated, delay: 180),
                    _TraitBar(label: 'Intelligence',   value: breed.traitNormalised(breed.intelligence),   animate: _statsAnimated, delay: 240),
                    _TraitBar(label: 'Social Needs',   value: breed.traitNormalised(breed.socialNeeds),    animate: _statsAnimated, delay: 300),
                    _TraitBar(label: 'Grooming',       value: breed.traitNormalised(breed.groomingLevel),  animate: _statsAnimated, delay: 360),
                    const SizedBox(height: 24),
                  ],

                  // About / description (cat-only)
                  if (breed.description != null &&
                      breed.description!.isNotEmpty) ...[
                    _sectionTitle(context, 'About'),
                    const SizedBox(height: 10),
                    Text(
                      breed.description!,
                      style: TextStyle(
                          color: scheme.outline, height: 1.6),
                    ).animate().fadeIn(delay: 200.ms),
                    const SizedBox(height: 24),
                  ],

                  // Bred for (dog-only)
                  if (breed.bredFor != null &&
                      breed.bredFor!.isNotEmpty) ...[
                    _sectionTitle(context, 'Bred For'),
                    const SizedBox(height: 8),
                    Text(
                      breed.bredFor!,
                      style: TextStyle(
                          color: scheme.outline, height: 1.5),
                    ).animate().fadeIn(delay: 200.ms),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── SliverAppBar ───────────────────────────────────────────────────────────

  SliverAppBar _buildSliverAppBar(Breed breed, ColorScheme scheme) {
    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      title: Text(breed.name),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Hero image / gallery PageView
            Hero(
              tag: 'breed-${breed.id}',
              child: _galleryUrls.isEmpty
                  ? _imagePlaceholder(breed, scheme)
                  : PageView.builder(
                      controller: _pageCtrl,
                      itemCount:  _galleryUrls.length,
                      onPageChanged: (i) =>
                          setState(() => _currentPage = i),
                      itemBuilder: (_, i) => CachedNetworkImage(
                        imageUrl:    _galleryUrls[i],
                        fit:         BoxFit.cover,
                        placeholder: (_, _) =>
                            _imagePlaceholder(breed, scheme),
                        errorWidget: (_, _, _) =>
                            _imagePlaceholder(breed, scheme),
                      ),
                    ),
            ),

            // Page indicator dots
            if (_galleryUrls.length > 1)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _galleryUrls.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width:  _currentPage == i ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _currentPage == i
                            ? Colors.white
                            : Colors.white.withAlpha(128),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),

            // Gallery fetch progress
            if (_loadingGallery)
              const Positioned(
                bottom: 0, left: 0, right: 0,
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _imagePlaceholder(Breed breed, ColorScheme scheme) => ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Center(
          child: Text(
            breed.type == BreedType.dog ? '🐶' : '🐱',
            style: const TextStyle(fontSize: 64),
          ),
        ),
      );

  Text _sectionTitle(BuildContext context, String title) => Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w600),
      );
}

// =============================================================================
// Info tiles grid — origin, life span, weight, height, breed group
// =============================================================================

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.breed, required this.scheme});
  final Breed       breed;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[
      if (breed.origin != null && breed.origin!.isNotEmpty)
        ('Origin', breed.origin!),
      if (breed.lifeSpan.isNotEmpty)
        ('Life Span', breed.lifeSpan),
      if (breed.weight?.metric != null && breed.weight!.metric!.isNotEmpty)
        ('Weight', '${breed.weight!.metric} kg'),
      if (breed.height?.metric != null && breed.height!.metric!.isNotEmpty)
        ('Height', '${breed.height!.metric} cm'),
      if (breed.breedGroup != null && breed.breedGroup!.isNotEmpty)
        ('Group', breed.breedGroup!),
    ];

    if (items.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items
          .map((e) => _InfoTile(label: e.$1, value: e.$2, scheme: scheme))
          .toList(),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile(
      {required this.label, required this.value, required this.scheme});
  final String      label;
  final String      value;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color:        scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize:   11,
              color:      scheme.outline,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize:   13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Animated trait bar — cat-only
// =============================================================================

class _TraitBar extends StatelessWidget {
  const _TraitBar({
    required this.label,
    required this.value,
    required this.animate,
    required this.delay,
  });
  final String label;
  final double value;   // 0.0 – 1.0 (from breed.traitNormalised)
  final bool   animate;
  final int    delay;   // extra ms added to animation duration

  @override
  Widget build(BuildContext context) {
    final scheme    = Theme.of(context).colorScheme;
    final rawScore  = (value * 4 + 1).round().clamp(1, 5);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              Text(
                '$rawScore / 5',
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: animate ? value : 0),
            duration: Duration(milliseconds: 600 + delay),
            curve: Curves.easeOut,
            builder: (_, v, _) => LinearProgressIndicator(
              value:           v,
              borderRadius:    BorderRadius.circular(4),
              minHeight:       8,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}
