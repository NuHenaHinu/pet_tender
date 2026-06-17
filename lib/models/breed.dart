import 'enums.dart';
 
// BreedWeight
class BreedMeasurement {
  final String? imperial;
  final String? metric;
 
  const BreedMeasurement({this.imperial, this.metric});
 
  factory BreedMeasurement.fromJson(Map<String, dynamic> json) =>
      BreedMeasurement(
        imperial: json['imperial'] as String?,
        metric:   json['metric']   as String?,
      );
 
  @override
  String toString() => metric ?? imperial ?? '';
}
 
// BreedImage
 
/// Image object embedded in a breed response from the Dog API or Cat API.
class BreedImage {
  final String id;
  final String url;
  final int? width;
  final int? height;
 
  const BreedImage({
    required this.id,
    required this.url,
    this.width,
    this.height,
  });
 
  factory BreedImage.fromJson(Map<String, dynamic> json) => BreedImage(
        id:     json['id']     as String?  ?? '',
        url:    json['url']    as String?  ?? '',
        width:  json['width']  as int?,
        height: json['height'] as int?,
      );
}
 
// Breed
 
/// Unified breed model for both The Dog API and The Cat API.
/// Use the named factory constructors:
/// - [Breed.fromDogJson] for responses from `https://api.thedogapi.com/v1/breeds`
/// - [Breed.fromCatJson] for responses from `https://api.thecatapi.com/v1/breeds`

class Breed {
  final String id;
  final String name;
  final BreedType type;
 
  // Common 
 
  final String? temperament;
  final String lifeSpan;
  final String? origin;
  final BreedMeasurement? weight;
  final BreedImage? image;
  final String? referenceImageId;
 
  // Dog-specific 
 
  /// What the breed was historically bred to do (Dog API only).
  final String? bredFor;
 
  /// AKC breed group, e.g. "Hound", "Toy" (Dog API only).
  final String? breedGroup;
 
  /// Shoulder height range (Dog API only).
  final BreedMeasurement? height;
 
  // Cat-specific (1–5 scale) 
 
  final String? description;
  final int? energyLevel;
  final int? affectionLevel;
  final int? childFriendly;
  final int? dogFriendly;
  final int? intelligence;
  final int? socialNeeds;
  final int? groomingLevel;
 
  const Breed({
    required this.id,
    required this.name,
    required this.type,
    this.temperament,
    required this.lifeSpan,
    this.origin,
    this.weight,
    this.image,
    this.referenceImageId,
    // dog
    this.bredFor,
    this.breedGroup,
    this.height,
    // cat
    this.description,
    this.energyLevel,
    this.affectionLevel,
    this.childFriendly,
    this.dogFriendly,
    this.intelligence,
    this.socialNeeds,
    this.groomingLevel,
  });
 
  // Named factory: Dog API
 
  /// Parses a single breed object from The Dog API.
  /// ```
  /// GET https://api.thedogapi.com/v1/breeds
  /// ```
  factory Breed.fromDogJson(Map<String, dynamic> json) {
    return Breed(
      id:               (json['id']).toString(),
      name:             json['name']              as String?  ?? '',
      type:             BreedType.dog,
      temperament:      json['temperament']        as String?,
      lifeSpan:         json['life_span']          as String?  ?? '',
      origin:           json['origin']             as String?,
      weight:           json['weight'] != null
                          ? BreedMeasurement.fromJson(json['weight'] as Map<String, dynamic>)
                          : null,
      height:           json['height'] != null
                          ? BreedMeasurement.fromJson(json['height'] as Map<String, dynamic>)
                          : null,
      referenceImageId: json['reference_image_id'] as String?,
      image:            _dogImage(json),
      bredFor:          json['bred_for']           as String?,
      breedGroup:       json['breed_group']        as String?,
    );
  }
 
  // Named factory: Cat API
  /// Parses a single breed object from The Cat API.
  /// ```
  /// GET https://api.thecatapi.com/v1/breeds
  /// ```
  factory Breed.fromCatJson(Map<String, dynamic> json) {
    return Breed(
      id:               json['id']                 as String?  ?? '',
      name:             json['name']               as String?  ?? '',
      type:             BreedType.cat,
      temperament:      json['temperament']         as String?,
      lifeSpan:         json['life_span']           as String?  ?? '',
      origin:           json['origin']              as String?,
      weight:           json['weight'] != null
                          ? BreedMeasurement.fromJson(json['weight'] as Map<String, dynamic>)
                          : null,
      image:            json['image'] != null
                          ? BreedImage.fromJson(json['image'] as Map<String, dynamic>)
                          : null,
      referenceImageId: json['reference_image_id']  as String?,
      description:      json['description']         as String?,
      energyLevel:      json['energy_level']        as int?,
      affectionLevel:   json['affection_level']     as int?,
      childFriendly:    json['child_friendly']      as int?,
      dogFriendly:      json['dog_friendly']        as int?,
      intelligence:     json['intelligence']        as int?,
      socialNeeds:      json['social_needs']        as int?,
      groomingLevel:    json['grooming']            as int?,
    );
  }
 
  // Computed helpers
 
  /// Splits the comma-separated [temperament] string into individual traits.
  /// Returns an empty list if [temperament] is null.
  List<String> get temperamentList =>
      temperament?.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList() ?? [];
 
  /// Returns a 0–1 normalised value for a cat trait (1–5 scale).
  /// Useful for driving AnimatedProgressIndicator in the Breed Detail screen.
  double traitNormalised(int? value) => value != null ? (value - 1) / 4.0 : 0.0;
 
  // Equality
 
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Breed &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          type == other.type;
 
  @override
  int get hashCode => Object.hash(id, type);
 
  @override
  String toString() => 'Breed(id: $id, name: $name, type: ${type.name})';
}

// Resolves a dog breed image from the embedded `image` object when present.
// NOTE: this thedogapi deployment returns no `image`/`reference_image_id`, so
// this is usually null and dog images are sourced from dog.ceo via
// DogCeoImages instead (see dog_image_service.dart). The old CDN-URL fallback
// built from `reference_image_id` was removed because that endpoint returns 403.
BreedImage? _dogImage(Map<String, dynamic> json) {
  final imgMap = json['image'] as Map<String, dynamic>?;
  if (imgMap != null) {
    final parsed = BreedImage.fromJson(imgMap);
    if (parsed.url.isNotEmpty) return parsed;
  }
  return null;
}
