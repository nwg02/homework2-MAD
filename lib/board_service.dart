
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BoardService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Generate a unique document ID before sending.
  String newMessageId() {
    return _db.collection('messages').doc().id;
  }

  // READ: Live message stream.
  Stream<QuerySnapshot<Map<String, dynamic>>> messageBoard() {
    return _db
        .collection('messages')
        .orderBy('createdAt')
        .snapshots();
  }

  // CREATE: Transaction prevents duplicate writes for the same ID.
  // Returns true if created, false if already present.
  Future<bool> postMessage({
    required String messageId,
    required String authorName,
    required String text,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('You must be signed in.');
    }

    final message = text.trim();

    if (message.isEmpty || message.length > 500) {
      throw ArgumentError('Message must be 1-500 characters.');
    }

    final ref = _db.collection('messages').doc(messageId);

    return _db.runTransaction<bool>((transaction) async {
      final existing = await transaction.get(ref);

      // If the document already exists, do not write it again.
      if (existing.exists) {
        final data = existing.data();

        if (data?['authorUid'] != user.uid ||
            data?['authorName'] != authorName ||
            data?['text'] != message) {
          throw StateError(
            'This message ID belongs to a different message.',
          );
        }

        return false;
      }

      transaction.set(ref, {
        'text': message,
        'authorUid': user.uid,
        'authorName': authorName,
        'createdAt': FieldValue.serverTimestamp(),
        'editedAt': null,
      });

      return true;
    });
  }

  // UPDATE: Edit an existing message.
  Future<void> editMessage({
    required String messageId,
    required String newText,
  }) async {
    if (_auth.currentUser == null) {
      throw StateError('You must be signed in.');
    }

    final message = newText.trim();

    if (message.isEmpty || message.length > 500) {
      throw ArgumentError('Message must be 1-500 characters.');
    }

    await _db.collection('messages').doc(messageId).update({
      'text': message,
      'editedAt': FieldValue.serverTimestamp(),
    });
  }

  // DELETE: Remove one message.
  Future<void> deleteMessage({
    required String messageId,
  }) async {
    if (_auth.currentUser == null) {
      throw StateError('You must be signed in.');
    }

    await _db.collection('messages').doc(messageId).delete();
  }
}
