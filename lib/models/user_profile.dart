class UserProfile {
  final String uid;
  final String? username;
  final String? usernameLower;
  final String? displayName;
  final String? photoUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const UserProfile({
    required this.uid,
    this.username,
    this.usernameLower,
    this.displayName,
    this.photoUrl,
    this.createdAt,
    this.updatedAt,
  });

  bool get hasUsername => (username ?? '').trim().isNotEmpty;

  String get welcomeName {
    final publicName = username?.trim();
    if (publicName != null && publicName.isNotEmpty) {
      return publicName;
    }
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return 'there';
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      uid: json['uid']?.toString() ?? '',
      username: _nonEmptyString(json['username']),
      usernameLower: _nonEmptyString(json['usernameLower']),
      displayName: _nonEmptyString(json['displayName']),
      photoUrl: _nonEmptyString(json['photoUrl']),
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
    );
  }
}

String? _nonEmptyString(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  final dynamic maybeTimestamp = value;
  try {
    final dynamic date = maybeTimestamp.toDate();
    if (date is DateTime) {
      return date;
    }
  } catch (_) {}
  return DateTime.tryParse(value.toString());
}
