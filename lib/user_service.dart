
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Watch the signed-in user's Firestore profile.
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchUser(
    String uid,
  ) {
    return _db.collection('users').doc(uid).snapshots();
  }

  // Verify that all five required fields exist.
  bool hasCompleteProfile(
    Map<String, dynamic>? data,
    String uid,
  ) {
    if (data == null) return false;

    return data['uid'] == uid &&
        data['firstName'] is String &&
        (data['firstName'] as String).trim().isNotEmpty &&
        data['lastName'] is String &&
        (data['lastName'] as String).trim().isNotEmpty &&
        data['role'] == 'member' &&
        data['registrationDateTime'] is Timestamp;
  }

  // Create a user document once, using the Auth UID.
  Future<void> saveUserRecord({
    required User user,
    required String firstName,
    required String lastName,
  }) async {
    final ref = _db.collection('users').doc(user.uid);

    final existing = await ref.get();

    if (existing.exists) {
      if (!hasCompleteProfile(existing.data(), user.uid)) {
        throw StateError('Existing profile is incomplete.');
      }
      return;
    }

    await ref.set({
      'uid': user.uid,
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'role': 'member',
      'registrationDateTime': FieldValue.serverTimestamp(),
    });
  }
}
