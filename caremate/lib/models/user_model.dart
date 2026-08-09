class UserModel {
  const UserModel({
    required this.id,
    required this.name,
    required this.role,
    this.avatarPath,
    this.profilePhotoUrl,
    this.avatarKey,
  });

  final String id;
  final String name;
  final String role;

  /// Legacy bundled asset fallback kept for older preview fixtures.
  final String? avatarPath;

  /// Signed profile-photo URL returned by the care relationship API.
  final String? profilePhotoUrl;

  /// Shared LifeMate avatar key used when no real profile photo is available.
  final String? avatarKey;
}
