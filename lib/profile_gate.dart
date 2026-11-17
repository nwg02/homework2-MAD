
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'board_screen.dart';

import 'auth_service.dart';
import 'user_service.dart';

class ProfileGate extends StatefulWidget {
  final User user;
  final AuthService authService;

  const ProfileGate({
    super.key,
    required this.user,
    required this.authService,
  });

  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  final UserService _users = UserService();

  late final Stream<DocumentSnapshot<Map<String, dynamic>>>
      _profileStream;

  @override
  void initState() {
    super.initState();
    _profileStream = _users.watchUser(widget.user.uid);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _profileStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Profile Error')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Could not load your Firestore profile.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Check your Firestore security rules.',
                  ),
                  TextButton(
                    onPressed: widget.authService.signOut,
                    child: const Text('Sign Out'),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final document = snapshot.data;
        final data = document?.data();

        if (document != null && document.exists) {
          if (_users.hasCompleteProfile(data, widget.user.uid)) {
            return BoardScreen(
              authService: widget.authService,
              authorName: '${data!['firstName']} ${data['lastName']}',
            );
          }

          return const Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Your profile is incomplete. '
                  'Please check the Firestore document.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        return CompleteProfileScreen(
          user: widget.user,
          authService: widget.authService,
          userService: _users,
        );
      },
    );
  }
}

class CompleteProfileScreen extends StatefulWidget {
  final User user;
  final AuthService authService;
  final UserService userService;

  const CompleteProfileScreen({
    super.key,
    required this.user,
    required this.authService,
    required this.userService,
  });

  @override
  State<CompleteProfileScreen> createState() =>
      _CompleteProfileScreenState();
}

class _CompleteProfileScreenState
    extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (_saving || !_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.userService.saveUserRecord(
        user: widget.user,
        firstName: _firstName.text,
        lastName: _lastName.text,
      );

      // ProfileGate's Firestore stream will update automatically.
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.code == 'permission-denied'
              ? 'Profile write denied. Check Firestore rules.'
              : 'Could not save profile. Check your connection.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not complete your profile.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';

    if (name.isEmpty) {
      return 'This field is required';
    }

    if (name.length > 60) {
      return 'Maximum 60 characters';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Registration'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: _saving
                ? null
                : () => widget.authService.signOut(),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.person_add_alt_1,
                    size: 75,
                    color: Color(0xFF304FFE),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Complete Your Profile',
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Enter your name to finish registration.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30),
                  TextFormField(
                    controller: _firstName,
                    decoration: const InputDecoration(
                      labelText: 'First Name',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateName,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _lastName,
                    decoration: const InputDecoration(
                      labelText: 'Last Name',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateName,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Account Role: Member',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _saveProfile,
                      child: _saving
                          ? const CircularProgressIndicator()
                          : const Text('Complete Registration'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Temporary success screen until message CRUD is implemented.
class ProfileReadyScreen extends StatelessWidget {
  final User user;
  final String firstName;
  final AuthService authService;

  const ProfileReadyScreen({
    super.key,
    required this.user,
    required this.firstName,
    required this.authService,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Message Board'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: authService.signOut,
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.verified_user,
              color: Colors.green,
              size: 80,
            ),
            const SizedBox(height: 20),
            Text(
              'Welcome, $firstName!',
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text('Firestore User Profile Saved!'),
            const SizedBox(height: 12),
            const Text('Next Phase: Message Board CRUD'),
          ],
        ),
      ),
    );
  }
}
