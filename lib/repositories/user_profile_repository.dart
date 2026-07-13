import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_profile.dart';

class UsernameValidationException implements Exception {
  final String message;

  const UsernameValidationException(this.message);

  @override
  String toString() => message;
}

class UsernameTakenException implements Exception {
  const UsernameTakenException();

  String get message => 'Username is already taken.';

  @override
  String toString() => message;
}

class UserProfileRepository {
  UserProfileRepository({
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  static final UserProfileRepository instance = UserProfileRepository();

  static final RegExp _usernameRegex = RegExp(r'^[A-Za-z0-9_]{3,20}$');

  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> get _usernames =>
      _firestore.collection('usernames');

  Future<UserProfile?> ensureUserProfile({User? user}) async {
    final currentUser = user ?? _firebaseAuth.currentUser;
    if (currentUser == null) {
      return null;
    }

    final ref = _users.doc(currentUser.uid);
    final snapshot = await ref.get();
    if (!snapshot.exists) {
      await ref.set({
        'uid': currentUser.uid,
        'username': null,
        'usernameLower': null,
        'displayName': _nonEmptyOrNull(currentUser.displayName),
        'photoUrl': _nonEmptyOrNull(currentUser.photoURL),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final created = await ref.get();
      return _profileFromSnapshot(created);
    }

    final updates = <String, dynamic>{
      if (snapshot.data()?['uid'] != currentUser.uid) 'uid': currentUser.uid,
    };
    final displayName = _nonEmptyOrNull(currentUser.displayName);
    final photoUrl = _nonEmptyOrNull(currentUser.photoURL);
    if (displayName != null && snapshot.data()?['displayName'] == null) {
      updates['displayName'] = displayName;
    }
    if (photoUrl != null && snapshot.data()?['photoUrl'] == null) {
      updates['photoUrl'] = photoUrl;
    }
    if (updates.isNotEmpty) {
      updates['updatedAt'] = FieldValue.serverTimestamp();
      await ref.set(updates, SetOptions(merge: true));
      final updated = await ref.get();
      return _profileFromSnapshot(updated);
    }

    return _profileFromSnapshot(snapshot);
  }

  Future<UserProfile?> getCurrentUserProfile() async {
    final uid = _firebaseAuth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      return null;
    }
    final snapshot = await _users.doc(uid).get();
    if (!snapshot.exists) {
      return null;
    }
    return _profileFromSnapshot(snapshot);
  }

  Stream<UserProfile?> streamCurrentUserProfile() {
    final uid = _firebaseAuth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      return Stream<UserProfile?>.value(null);
    }
    return _users.doc(uid).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return null;
      }
      return _profileFromSnapshot(snapshot);
    });
  }

  Future<UserProfile> claimUsername(String username) async {
    final trimmed = username.trim();
    final validationMessage = validateUsername(trimmed);
    if (validationMessage != null) {
      throw UsernameValidationException(validationMessage);
    }

    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw const UsernameValidationException('Sign in to choose a username.');
    }

    final usernameLower = trimmed.toLowerCase();
    final userRef = _users.doc(user.uid);
    final usernameRef = _usernames.doc(usernameLower);

    await _firestore.runTransaction((transaction) async {
      final profileSnapshot = await transaction.get(userRef);
      final usernameSnapshot = await transaction.get(usernameRef);

      if (usernameSnapshot.exists &&
          usernameSnapshot.data()?['uid'] != user.uid) {
        throw const UsernameTakenException();
      }

      final profileData = profileSnapshot.data();
      final oldUsernameLower =
          _nonEmptyOrNull(profileData?['usernameLower'])?.toLowerCase();
      DocumentSnapshot<Map<String, dynamic>>? oldUsernameSnapshot;
      DocumentReference<Map<String, dynamic>>? oldUsernameRef;
      if (oldUsernameLower != null && oldUsernameLower != usernameLower) {
        oldUsernameRef = _usernames.doc(oldUsernameLower);
        oldUsernameSnapshot = await transaction.get(oldUsernameRef);
      }

      if (!usernameSnapshot.exists) {
        transaction.set(usernameRef, {
          'uid': user.uid,
          'username': trimmed,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else if (usernameSnapshot.data()?['username'] != trimmed) {
        transaction.set(usernameRef, {
          'uid': user.uid,
          'username': trimmed,
          'createdAt': usernameSnapshot.data()?['createdAt'] ??
              FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (oldUsernameRef != null &&
          oldUsernameSnapshot != null &&
          oldUsernameSnapshot.exists &&
          oldUsernameSnapshot.data()?['uid'] == user.uid) {
        transaction.delete(oldUsernameRef);
      }

      final displayName = _nonEmptyOrNull(user.displayName);
      final photoUrl = _nonEmptyOrNull(user.photoURL);
      transaction.set(userRef, {
        'uid': user.uid,
        'username': trimmed,
        'usernameLower': usernameLower,
        if (displayName != null) 'displayName': displayName,
        if (photoUrl != null) 'photoUrl': photoUrl,
        if (!profileSnapshot.exists) 'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    final updated = await userRef.get();
    return _profileFromSnapshot(updated)!;
  }

  Future<void> updateDisplayName(String displayName) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      return;
    }
    await _users.doc(user.uid).set({
      'uid': user.uid,
      'displayName': _nonEmptyOrNull(displayName),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static String? validateUsername(String value) {
    if (value.trim().isEmpty) {
      return 'Enter a username.';
    }
    if (value.length < 3) {
      return 'Username must be at least 3 characters.';
    }
    if (value.length > 20) {
      return 'Username must be 20 characters or fewer.';
    }
    if (value.contains(' ')) {
      return 'Username cannot contain spaces.';
    }
    if (!_usernameRegex.hasMatch(value)) {
      return 'Use letters, numbers, and underscores only.';
    }
    return null;
  }

  UserProfile? _profileFromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null) {
      return null;
    }
    return UserProfile.fromJson({
      ...data,
      'uid': data['uid'] ?? snapshot.id,
    });
  }

  String? _nonEmptyOrNull(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }
}
