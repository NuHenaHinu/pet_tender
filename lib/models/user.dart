import 'enums.dart';
 
class User {
  final String id;
  final String name;
  final String email;
  final UserRole role;
  final String? profilePhotoUrl;
  final String? bio;
  final String? phoneNumber;
  final double rating;
  final int ratingCount;
  final DateTime createdAt;
 
  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.profilePhotoUrl,
    this.bio,
    this.phoneNumber,
    this.rating = 0.0,
    this.ratingCount = 0,
    required this.createdAt,
  });
 
  // Deserialization
 
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['objectId'] as String?  ?? '',
      name: json['name'] as String?  ?? '',
      email: json['email'] as String?  ?? '',
      role: UserRole.values.firstWhere(
              (r) => r.name == (json['role'] as String?),
              orElse: () => UserRole.sitter,
            ),
      profilePhotoUrl: json['profilePhotoUrl'] as String?,
      bio: json['bio'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 0,
      createdAt: _fromTimestamp(json['created']),
    );
  }
 
  // Serialization (omit server-managed fields)
 
  Map<String, dynamic> toJson() => {
        'name':  name,
        'email': email,
        'role':  role.name,
        if (profilePhotoUrl != null) 'profilePhotoUrl': profilePhotoUrl,
        if (bio             != null) 'bio':             bio,
        if (phoneNumber     != null) 'phoneNumber':     phoneNumber,
        'rating': rating,
        'ratingCount': ratingCount,
      };
 
  // copyWith 
 
  User copyWith({
    String?   id,
    String?   name,
    String?   email,
    UserRole? role,
    String?   profilePhotoUrl,
    String?   bio,
    String?   phoneNumber,
    double?   rating,
    int?      ratingCount,
    DateTime? createdAt,
  }) =>
      User(
        id:              id              ?? this.id,
        name:            name            ?? this.name,
        email:           email           ?? this.email,
        role:            role            ?? this.role,
        profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
        bio:             bio             ?? this.bio,
        phoneNumber:     phoneNumber     ?? this.phoneNumber,
        rating:          rating          ?? this.rating,
        ratingCount:     ratingCount     ?? this.ratingCount,
        createdAt:       createdAt       ?? this.createdAt,
      );
 
  // Equality 
 
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is User &&
          runtimeType == other.runtimeType &&
          id == other.id;
 
  @override
  int get hashCode => id.hashCode;
 
  @override
  String toString() => 'User(id: $id, name: $name, role: ${role.name})';
}
 
//  Private helper 
/// Parses a Backendless timestamp (int ms) or ISO-8601 string safely.
DateTime _fromTimestamp(dynamic value) {
  if (value is int)    return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.parse(value);
  return DateTime.now();
}
