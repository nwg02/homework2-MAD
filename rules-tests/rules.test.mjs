
import { test, before, beforeEach, after } from 'node:test';
import { readFileSync } from 'node:fs';

import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';

import {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  serverTimestamp,
} from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'message-board-hw2',
    firestore: {
      host: '127.0.0.1',
      port: 8080,
      rules: readFileSync(
        new URL('../firestore.rules', import.meta.url),
        'utf8',
      ),
    },
  });
});

beforeEach(async () => {
  await env.clearFirestore();

  // Seed local test data without applying rules.
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    await setDoc(doc(db, 'users/alice'), {
      uid: 'alice',
      firstName: 'Alice',
      lastName: 'Tester',
      role: 'member',
      registrationDateTime: new Date(),
    });

    await setDoc(doc(db, 'users/bob'), {
      uid: 'bob',
      firstName: 'Bob',
      lastName: 'Tester',
      role: 'member',
      registrationDateTime: new Date(),
    });

    await setDoc(doc(db, 'messages/alice-message'), {
      text: 'Hello from Alice',
      authorUid: 'alice',
      authorName: 'Alice Tester',
      createdAt: new Date(),
      editedAt: null,
    });

    await setDoc(doc(db, 'messages/bob-message'), {
      text: 'Hello from Bob',
      authorUid: 'bob',
      authorName: 'Bob Tester',
      createdAt: new Date(),
      editedAt: null,
    });
  });
});

after(async () => {
  if (env) {
    await env.cleanup();
  }
});

// TEST 1: Signed-out users cannot read messages.
test('Signed-out message read DENIED', async () => {
  const guest = env.unauthenticatedContext().firestore();

  await assertFails(
    getDoc(doc(guest, 'messages/alice-message')),
  );
});

// TEST 2: Bob cannot edit Alice's message.
test('Cross-user update DENIED', async () => {
  const bob = env.authenticatedContext('bob').firestore();

  await assertFails(
    updateDoc(doc(bob, 'messages/alice-message'), {
      text: 'Unauthorized edit',
      editedAt: serverTimestamp(),
    }),
  );
});

// TEST 3: Bob cannot delete Alice's message.
test('Cross-user delete DENIED', async () => {
  const bob = env.authenticatedContext('bob').firestore();

  await assertFails(
    deleteDoc(doc(bob, 'messages/alice-message')),
  );
});

// TEST 4: Bob cannot impersonate Alice.
test('Forged author UID DENIED', async () => {
  const bob = env.authenticatedContext('bob').firestore();

  await assertFails(
    setDoc(doc(bob, 'messages/forged-message'), {
      text: 'Forged message',
      authorUid: 'alice',
      authorName: 'Alice Tester',
      createdAt: serverTimestamp(),
      editedAt: null,
    }),
  );
});

// TEST 5: A signed-in user can read public board messages.
test('Signed-in message read ALLOWED', async () => {
  const alice = env.authenticatedContext('alice').firestore();

  await assertSucceeds(
    getDoc(doc(alice, 'messages/bob-message')),
  );
});

// TEST 6: Alice can perform all four CRUD operations.
test('Correct-author CRUD ALLOWED', async () => {
  const alice = env.authenticatedContext('alice').firestore();
  const message = doc(alice, 'messages/allowed-message');

  await assertSucceeds(
    setDoc(message, {
      text: 'New message',
      authorUid: 'alice',
      authorName: 'Alice Tester',
      createdAt: serverTimestamp(),
      editedAt: null,
    }),
  );

  await assertSucceeds(getDoc(message));

  await assertSucceeds(
    updateDoc(message, {
      text: 'Updated message',
      editedAt: serverTimestamp(),
    }),
  );

  await assertSucceeds(deleteDoc(message));
});

// TEST 7: Users cannot read another user's private profile.
test('Cross-user profile read DENIED', async () => {
  const bob = env.authenticatedContext('bob').firestore();

  await assertFails(
    getDoc(doc(bob, 'users/alice')),
  );
});
