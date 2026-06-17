import 'dart:convert';

import 'enums.dart';
 
// JobLocation
class JobLocation {
  final String address;
  final double latitude;
  final double longitude;
 
  const JobLocation({
    required this.address,
    required this.latitude,
    required this.longitude,
  });
 
  factory JobLocation.fromJson(Map<String, dynamic> json) => JobLocation(
        address:   json['address']   as String?  ?? '',
        latitude:  (json['latitude']  as num?)?.toDouble() ?? 0.0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      );
 
  Map<String, dynamic> toJson() => {
        'address':   address,
        'latitude':  latitude,
        'longitude': longitude,
      };
 
  @override
  String toString() => 'JobLocation($address)';
}
 
// Job
class Job {
  final String id;
  final String title;
  final String description;
  final String ownerId;
  final String ownerName;
  final String? ownerPhotoUrl;
  final PetType petType;
  final String? breedName;
  final String? photoUrl;
 
  final double payRate;
  final String currency;
 
  final DateTime startDate;
  final DateTime? endDate;
  final int? durationHours;
 
  final JobLocation location;
  final JobStatus status;
  final DateTime createdAt;
 
  const Job({
    required this.id,
    required this.title,
    required this.description,
    required this.ownerId,
    required this.ownerName,
    this.ownerPhotoUrl,
    required this.petType,
    this.breedName,
    this.photoUrl,
    required this.payRate,
    this.currency = 'TWD',
    required this.startDate,
    this.endDate,
    this.durationHours,
    required this.location,
    this.status = JobStatus.open,
    required this.createdAt,
  });
 
  // Deserialization
 
  factory Job.fromJson(Map<String, dynamic> json) {
    return Job(
      id: json['objectId'] as String?  ?? '',
      title: json['title'] as String?  ?? '',
      description: json['description'] as String?  ?? '',
      ownerId: json['ownerId'] as String?  ?? '',
      ownerName: json['ownerName'] as String?  ?? '',
      ownerPhotoUrl: json['ownerPhotoUrl'] as String?,
      petType: PetType.values.firstWhere(
                (t) => t.name == (json['petType'] as String?),
                orElse: () => PetType.dog,
              ),
      breedName: json['breedName'] as String?,
      photoUrl: json['photoUrl'] as String?,
      payRate: (json['payRate'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String?  ?? 'TWD',
      startDate: _fromTimestamp(json['startDate']),
      endDate: json['endDate'] != null ? _fromTimestamp(json['endDate']) : null,
      durationHours: (json['durationHours'] as num?)?.toInt(),
      location: _parseLocation(json['location']),
      status: JobStatus.values.firstWhere(
                (s) => s.name == (json['status'] as String?),
                orElse: () => JobStatus.open,
              ),
      createdAt: _fromTimestamp(json['created']),
    );
  }
 
  // Serialization
  Map<String, dynamic> toJson() => {
        'title':       title,
        'description': description,
        'ownerId':     ownerId,
        'ownerName':   ownerName,
        if (ownerPhotoUrl != null) 'ownerPhotoUrl': ownerPhotoUrl,
        'petType':     petType.name,
        if (breedName != null) 'breedName': breedName,
        if (photoUrl != null) 'photoUrl': photoUrl,
        'payRate':     payRate,
        'currency':    currency,
        // Send UTC (with 'Z') so Backendless stores the correct instant.
        // Offset-less local strings get read as UTC by the server, which
        // shifted every job's time by the local offset (8h in Taiwan).
        'startDate':   startDate.toUtc().toIso8601String(),
        if (endDate != null) 'endDate': endDate!.toUtc().toIso8601String(),
        if (durationHours != null) 'durationHours': durationHours,
        'location':    location.toJson(),
        'status':      status.name,
      };
 
  // copyWith 
  Job copyWith({
    String?      id,
    String?      title,
    String?      description,
    String?      ownerId,
    String?      ownerName,
    String?      ownerPhotoUrl,
    PetType?     petType,
    String?      breedName,
    String?      photoUrl,
    double?      payRate,
    String?      currency,
    DateTime?    startDate,
    DateTime?    endDate,
    int?         durationHours,
    JobLocation? location,
    JobStatus?   status,
    DateTime?    createdAt,
  }) =>
      Job(
        id:            id            ?? this.id,
        title:         title         ?? this.title,
        description:   description   ?? this.description,
        ownerId:       ownerId       ?? this.ownerId,
        ownerName:     ownerName     ?? this.ownerName,
        ownerPhotoUrl: ownerPhotoUrl ?? this.ownerPhotoUrl,
        petType:       petType       ?? this.petType,
        breedName:     breedName     ?? this.breedName,
        photoUrl:      photoUrl      ?? this.photoUrl,
        payRate:       payRate       ?? this.payRate,
        currency:      currency      ?? this.currency,
        startDate:     startDate     ?? this.startDate,
        endDate:       endDate       ?? this.endDate,
        durationHours: durationHours ?? this.durationHours,
        location:      location      ?? this.location,
        status:        status        ?? this.status,
        createdAt:     createdAt     ?? this.createdAt,
      );
 
  // Equality 
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Job && runtimeType == other.runtimeType && id == other.id;
 
  @override
  int get hashCode => id.hashCode;
 
  @override
  String toString() => 'Job(id: $id, title: $title, status: ${status.name})';
}
 
// Private helpers

// Handles location stored as a Map (normal) or as a JSON string (Backendless
// may stringify nested objects if the column type is String in the schema).
JobLocation _parseLocation(dynamic raw) {
  if (raw is Map<String, dynamic>) return JobLocation.fromJson(raw);
  if (raw is String && raw.isNotEmpty) {
    try {
      return JobLocation.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
  }
  return const JobLocation(address: '', latitude: 0, longitude: 0);
}

DateTime _fromTimestamp(dynamic value) {
  if (value is int)    return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.parse(value);
  return DateTime.now();
}
