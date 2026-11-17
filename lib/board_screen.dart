
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'auth_service.dart';
import 'board_service.dart';

class BoardScreen extends StatefulWidget {
  final AuthService authService;
  final String authorName;

  const BoardScreen({
    super.key,
    required this.authService,
    required this.authorName,
  });

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  final BoardService _boardService = BoardService();
  final TextEditingController _messageController =
      TextEditingController();

  late final Stream<QuerySnapshot<Map<String, dynamic>>>
      _messageStream;

  bool _posting = false;

  // Duplicate submission protection.
  String? _pendingMessageId;
  String? _pendingMessageText;

  @override
  void initState() {
    super.initState();
    _messageStream = _boardService.messageBoard();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  // Display a message to the user.
  void _showFeedback(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // Translate errors into understandable messages.
  String _errorMessage(Object error) {
    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        return 'Permission denied by Firestore security rules.';
      }

      if (error.code == 'unavailable') {
        return 'Firestore is unavailable. Check your connection.';
      }
    }

    if (error is ArgumentError) {
      return 'Message must contain 1-500 characters.';
    }

    return 'Operation failed. Please try again.';
  }

  // CREATE: Post a message with duplicate protection.
  Future<void> _postMessage() async {
    if (_posting) return;

    final text = _messageController.text.trim();

    if (text.isEmpty || text.length > 500) {
      _showFeedback('Enter a message of 1-500 characters.');
      return;
    }

    // Generate an ID only for a new message.
    // Reuse the same ID when retrying the same text.
    if (_pendingMessageId == null ||
        _pendingMessageText != text) {
      _pendingMessageId = _boardService.newMessageId();
      _pendingMessageText = text;
    }

    final messageId = _pendingMessageId!;

    setState(() {
      _posting = true;
    });

    try {
      await _boardService.postMessage(
        messageId: messageId,
        authorName: widget.authorName,
        text: text,
      );

      _messageController.clear();

      // Clear the pending ID after successful completion.
      _pendingMessageId = null;
      _pendingMessageText = null;

      _showFeedback('Message sent successfully.');
    } catch (error) {
      _showFeedback(_errorMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _posting = false;
        });
      }
    }
  }

  // EXTRA SPICE #4: Test idempotent message creation.
  Future<void> _runIdempotencyTest() async {
    if (_posting) return;

    setState(() {
      _posting = true;
    });

    try {
      final messageId = _boardService.newMessageId();

      const testText = 'Idempotency Spice Test';

      // First submission should create the document.
      final first = await _boardService.postMessage(
        messageId: messageId,
        authorName: widget.authorName,
        text: testText,
      );

      // Second submission uses exactly the same ID.
      // It should not create another document.
      final second = await _boardService.postMessage(
        messageId: messageId,
        authorName: widget.authorName,
        text: testText,
      );

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Duplicate Write Test'),
            content: SelectableText(
              'Document ID:\n$messageId\n\n'
              'First submission: '
              '${first ? "CREATED" : "SKIPPED"}\n\n'
              'Second submission: '
              '${second ? "CREATED" : "SKIPPED"}\n\n'
              'Expected result:\n'
              'Exactly ONE Firestore document.\n\n'
              'Verify this document ID in the '
              'Firebase Console.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    } catch (error) {
      _showFeedback(_errorMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _posting = false;
        });
      }
    }
  }

  // UPDATE: Edit an existing message.
  Future<void> _editMessage(
    String messageId,
    String oldText,
  ) async {
    final formKey = GlobalKey<FormState>();
    String editedText = oldText;

    final newText = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit Message'),
          content: Form(
            key: formKey,
            child: TextFormField(
              initialValue: oldText,
              maxLength: 500,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Message',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                editedText = value;
              },
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Message cannot be empty';
                }

                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(
                    dialogContext,
                    editedText.trim(),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (!mounted || newText == null) return;

    try {
      await _boardService.editMessage(
        messageId: messageId,
        newText: newText,
      );

      _showFeedback('Message updated.');
    } catch (error) {
      _showFeedback(_errorMessage(error));
    }
  }

  // DELETE: Delete an existing message.
  Future<void> _deleteMessage(String messageId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Message'),
          content: const Text(
            'Are you sure you want to delete this message?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    try {
      await _boardService.deleteMessage(
        messageId: messageId,
      );

      _showFeedback('Message deleted.');
    } catch (error) {
      _showFeedback(_errorMessage(error));
    }
  }

  // Build one message card.
  Widget _buildMessage(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();

    final text = data['text'] as String? ?? '';
    final authorName =
        data['authorName'] as String? ?? 'Unknown';
    final authorUid = data['authorUid'] as String? ?? '';

    final currentUid =
        FirebaseAuth.instance.currentUser?.uid;

    final isOwner =
        currentUid != null && currentUid == authorUid;

    final createdAt = data['createdAt'];
    final editedAt = data['editedAt'];

    String timeLabel = 'Sending...';

    if (createdAt is Timestamp) {
      final dateTime = createdAt.toDate().toLocal();

      timeLabel =
          TimeOfDay.fromDateTime(dateTime).format(context);
    }

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  child: Icon(Icons.person),
                ),
                const SizedBox(width: 10),

                Expanded(
                  child: Text(
                    authorName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),

                Text(
                  timeLabel,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),

                // UI ownership controls.
                // Firestore rules enforce actual ownership.
                if (isOwner)
                  PopupMenuButton<String>(
                    tooltip: 'Message options',
                    onSelected: (choice) {
                      if (choice == 'edit') {
                        _editMessage(doc.id, text);
                      } else if (choice == 'delete') {
                        _deleteMessage(doc.id);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                  ),
              ],
            ),

            const SizedBox(height: 12),

            Text(
              text,
              style: const TextStyle(fontSize: 16),
            ),

            if (editedAt is Timestamp)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Edited',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // READ: Display live messages from Firestore.
  Widget _buildMessages() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _messageStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Could not load messages. Check Firestore rules.',
              textAlign: TextAlign.center,
            ),
          );
        }

        if (snapshot.connectionState ==
            ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final documents = snapshot.data?.docs ?? [];

        if (documents.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.forum_outlined,
                  size: 70,
                  color: Colors.grey,
                ),
                SizedBox(height: 16),
                Text(
                  'No messages yet!',
                  style: TextStyle(fontSize: 20),
                ),
                SizedBox(height: 8),
                Text('Be the first to post.'),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: documents.length,
          itemBuilder: (context, index) {
            return _buildMessage(documents[index]);
          },
        );
      },
    );
  }

  // Message composer.
  Widget _buildComposer() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 6,
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                maxLines: 3,
                minLines: 1,
                maxLength: 500,
                decoration: const InputDecoration(
                  hintText: 'Write a message...',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
            ),

            const SizedBox(width: 10),

            IconButton.filled(
              onPressed: _posting ? null : _postMessage,
              icon: _posting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }

  // Main screen.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Message Board'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,

        actions: [
          // Extra Spice #4 test button.
          // Only visible in debug builds.
          if (kDebugMode)
            IconButton(
              tooltip: 'Test Duplicate Protection',
              icon: const Icon(Icons.science_outlined),
              onPressed:
                  _posting ? null : _runIdempotencyTest,
            ),

          // Sign out.
          IconButton(
            tooltip: 'Sign Out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await widget.authService.signOut();
            },
          ),
        ],
      ),

      body: Column(
        children: [
          Expanded(
            child: _buildMessages(),
          ),
          _buildComposer(),
        ],
      ),
    );
  }
}
