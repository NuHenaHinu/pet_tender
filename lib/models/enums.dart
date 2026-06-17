/// All enums for the PeTender pet care job board app.
/// Extensions provide display-ready strings and helpers used across the UI.
library;

// User

enum UserRole { owner, sitter, both }

extension UserRoleX on UserRole {
  String get displayName => switch (this) {
        UserRole.owner  => 'Pet Owner',
        UserRole.sitter => 'Pet Sitter',
        UserRole.both   => 'Owner & Sitter',
      };
}

// Job

enum PetType { dog, cat, other }

extension PetTypeX on PetType {
  String get displayName => switch (this) {
        PetType.dog    => 'Dog',
        PetType.cat    => 'Cat',
        PetType.other  => 'Other',
      };

  String get emoji => switch (this) {
        PetType.dog    => '🐶',
        PetType.cat    => '🐱',
        PetType.other  => '🐾',
      };
}

enum JobStatus { open, filled, completing, closed }

extension JobStatusX on JobStatus {
  String get displayName => switch (this) {
        JobStatus.open       => 'Open',
        JobStatus.filled     => 'In Progress',
        JobStatus.completing => 'Awaiting Confirmation',
        JobStatus.closed     => 'Completed',
      };

  bool get isActive => this == JobStatus.open;
}

// Application

enum ApplicationStatus {
  pending,
  accepted,
  rejected,
  withdrawn,
  pendingConfirmation,
  completed,
}

extension ApplicationStatusX on ApplicationStatus {
  String get displayName => switch (this) {
        ApplicationStatus.pending             => 'Pending',
        ApplicationStatus.accepted            => 'Accepted',
        ApplicationStatus.rejected            => 'Rejected',
        ApplicationStatus.withdrawn           => 'Withdrawn',
        ApplicationStatus.pendingConfirmation => 'Awaiting Confirmation',
        ApplicationStatus.completed           => 'Completed',
      };

  bool get isTerminal =>
      this == ApplicationStatus.rejected  ||
      this == ApplicationStatus.withdrawn ||
      this == ApplicationStatus.completed;
}

// Breed

enum BreedType { dog, cat }

extension BreedTypeX on BreedType {
  String get displayName => switch (this) {
        BreedType.dog => 'Dog',
        BreedType.cat => 'Cat',
      };
}
