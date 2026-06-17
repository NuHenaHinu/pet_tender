import 'package:dio/dio.dart';

/// Resolves breed-correct dog images from the free Dog CEO API (dog.ceo).
///
/// Why this exists: the `api.thedogapi.com` deployment this project uses returns
/// breed records with no `image`/`reference_image_id`, and its `/images/search`
/// ignores `breed_ids` (it returns random-breed dogs). So dog images can't come
/// from thedogapi at all. Dog CEO is keyed by breed *name*, so we map each
/// thedogapi breed name to a dog.ceo slug. Unmatched breeds return null/empty so
/// the UI shows a placeholder rather than a wrong-breed photo.
///
/// Results are cached per breed name; the breed list is fetched once.
class DogCeoImages {
  DogCeoImages._();
  static final DogCeoImages instance = DogCeoImages._();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  Future<Map<String, List<String>>>? _breedListFuture;
  final Map<String, String?> _singleCache = {};
  final Map<String, List<String>> _galleryCache = {};

  /// Names the heuristic can't resolve. dog.ceo spells Saint Bernard as
  /// "stbernard", which neither the words nor sub-breed rules would find.
  /// (German Shepherd resolves correctly via the sub-breed rule: german/shepherd.)
  /// Every slug here must be a real dog.ceo slug, or the request 404s.
  static const Map<String, String> _overrides = {
    'saint bernard': 'stbernard',
    'st. bernard': 'stbernard',
  };

  Future<Map<String, List<String>>> _breedList() {
    return _breedListFuture ??= _dio
        .get<Map<String, dynamic>>('https://dog.ceo/api/breeds/list/all')
        .then((res) {
      final msg = res.data?['message'] as Map<String, dynamic>? ?? const {};
      return msg.map((k, v) => MapEntry(k, (v as List).cast<String>()));
    });
  }

  /// Maps a thedogapi breed name to a dog.ceo slug, or null if no good match.
  /// Prefers exact sub-breed matches ("Afghan Hound" → hound/afghan) before
  /// falling back to a single matching word ("Siberian Husky" → husky).
  String? _slug(String name, Map<String, List<String>> breeds) {
    final lower = name.toLowerCase().trim();
    final override = _overrides[lower];
    if (override != null) return override;

    final words = lower
        .split(RegExp(r'\s+'))
        .where((w) => w != 'dog' && w.isNotEmpty)
        .toList();
    if (words.isEmpty) return null;

    // Sub-breed: one word is a group, another is its sub-breed.
    for (final group in words) {
      final subs = breeds[group];
      if (subs != null) {
        for (final sub in words) {
          if (sub != group && subs.contains(sub)) return '$group/$sub';
        }
      }
    }
    // Whole name as one word ("Border Collie" is "collie/border" above; this
    // catches e.g. one-word breeds and "germanshepherd").
    final joined = words.join();
    if (breeds.containsKey(joined)) return joined;
    // A single word that is itself a breed — prefer the qualifier first
    // ("Labrador Retriever" → labrador), then the type ("Siberian Husky" → husky).
    if (breeds.containsKey(words.first)) return words.first;
    if (breeds.containsKey(words.last)) return words.last;
    for (final w in words) {
      if (breeds.containsKey(w)) return w;
    }
    return null;
  }

  /// One representative image for [breedName], or null if unmatched.
  Future<String?> imageFor(String breedName) async {
    if (_singleCache.containsKey(breedName)) return _singleCache[breedName];
    try {
      final breeds = await _breedList();
      final slug = _slug(breedName, breeds);
      if (slug == null) return _singleCache[breedName] = null;
      final res = await _dio.get<Map<String, dynamic>>(
          'https://dog.ceo/api/breed/$slug/images/random');
      return _singleCache[breedName] = res.data?['message'] as String?;
    } catch (_) {
      return _singleCache[breedName] = null;
    }
  }

  /// Up to [count] images for [breedName] (gallery). Empty if unmatched. The
  /// cached single image (if any) is placed first so a Hero transition lines up.
  Future<List<String>> galleryFor(String breedName, {int count = 6}) async {
    final cached = _galleryCache[breedName];
    if (cached != null) return cached;
    try {
      final breeds = await _breedList();
      final slug = _slug(breedName, breeds);
      if (slug == null) return _galleryCache[breedName] = const [];
      final res = await _dio.get<Map<String, dynamic>>(
          'https://dog.ceo/api/breed/$slug/images/random/$count');
      final urls = ((res.data?['message'] as List?) ?? const [])
          .cast<String>()
          .toList();
      final single = _singleCache[breedName];
      if (single != null && single.isNotEmpty) {
        urls.remove(single);
        urls.insert(0, single);
      }
      return _galleryCache[breedName] = urls;
    } catch (_) {
      return _galleryCache[breedName] = const [];
    }
  }
}
