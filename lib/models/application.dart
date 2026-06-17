import 'enums.dart';
import 'job.dart';
 
class Application {
  final String id;
  final String jobId;

  /// objectId of the user who owns the job this application is for.
  /// Lets an owner fetch every application across all their jobs in one query
  /// (`where: "jobOwnerId='<id>'"`). Deliberately NOT named `ownerId`: that is
  /// Backendless's system field for the row creator (the sitter), and
  /// overwriting it would reassign row ownership away from the sitter.
  final String jobOwnerId;

  final Job? job;
 
  final String sitterId;
  final String sitterName;
  final String? sitterPhotoUrl;
 
  final String? message;
 
  final ApplicationStatus status;
  final DateTime appliedAt;
  final DateTime? updatedAt;
 
  const Application({
    required this.id,
    required this.jobId,
    this.jobOwnerId = '',
    this.job,
    required this.sitterId,
    required this.sitterName,
    this.sitterPhotoUrl,
    this.message,
    this.status = ApplicationStatus.pending,
    required this.appliedAt,
    this.updatedAt,
  });
 
  // Deserialization
 
  factory Application.fromJson(Map<String, dynamic> json) {
    return Application(
      id:             json['objectId']      as String?  ?? '',
      jobId:          json['jobId']         as String?  ?? '',
      jobOwnerId:     json['jobOwnerId']    as String?  ?? '',
      job:            json['job'] != null
                        ? Job.fromJson(json['job'] as Map<String, dynamic>)
                        : null,
      sitterId:       json['sitterId']      as String?  ?? '',
      sitterName:     json['sitterName']    as String?  ?? '',
      sitterPhotoUrl: json['sitterPhotoUrl'] as String?,
      message:        json['message']       as String?,
      status:         ApplicationStatus.values.firstWhere(
                        (s) => s.name == (json['status'] as String?),
                        orElse: () => ApplicationStatus.pending,
                      ),
      appliedAt:  _fromTimestamp(json['created']),
      updatedAt:  json['updated'] != null
                    ? _fromTimestamp(json['updated'])
                    : null,
    );
  }
 
  // Serialization
 
  Map<String, dynamic> toJson() => {
        'jobId':      jobId,
        'jobOwnerId': jobOwnerId,
        'sitterId':   sitterId,
        'sitterName': sitterName,
        if (sitterPhotoUrl != null) 'sitterPhotoUrl': sitterPhotoUrl,
        if (message        != null) 'message':        message,
        'status':     status.name,
      };
 
  // copyWith
 
  Application copyWith({
    String?            id,
    String?            jobId,
    String?            jobOwnerId,
    Job?               job,
    String?            sitterId,
    String?            sitterName,
    String?            sitterPhotoUrl,
    String?            message,
    ApplicationStatus? status,
    DateTime?          appliedAt,
    DateTime?          updatedAt,
  }) =>
      Application(
        id:             id             ?? this.id,
        jobId:          jobId          ?? this.jobId,
        jobOwnerId:     jobOwnerId     ?? this.jobOwnerId,
        job:            job            ?? this.job,
        sitterId:       sitterId       ?? this.sitterId,
        sitterName:     sitterName     ?? this.sitterName,
        sitterPhotoUrl: sitterPhotoUrl ?? this.sitterPhotoUrl,
        message:        message        ?? this.message,
        status:         status         ?? this.status,
        appliedAt:      appliedAt      ?? this.appliedAt,
        updatedAt:      updatedAt      ?? this.updatedAt,
      );
 
  // Equality 
 
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Application &&
          runtimeType == other.runtimeType &&
          id == other.id;
 
  @override
  int get hashCode => id.hashCode;
 
  @override
  String toString() =>
      'Application(id: $id, jobId: $jobId, status: ${status.name})';
}
 
//Private helper 
 
DateTime _fromTimestamp(dynamic value) {
  if (value is int)    return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.parse(value);
  return DateTime.now();
}
