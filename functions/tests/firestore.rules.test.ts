import * as fs from 'fs';
import * as firebase from '@firebase/rules-unit-testing';
import * as admin from 'firebase-admin';

const projectId = 'demo-firestore-tests';

// Load rules file
const rules = fs.readFileSync('../../firestore.rules', 'utf8');

describe('Firestore security rules', () => {
  let testEnv: firebase.RulesTestEnvironment;

  beforeAll(async () => {
    testEnv = await firebase.initializeTestEnvironment({ projectId, firestore: { rules } });
  });

  afterAll(async () => {
    await testEnv.cleanup();
  });

  test('unauthenticated user cannot read another user profile', async () => {
    const unauth = testEnv.unauthenticatedContext();
    const db = unauth.firestore();
    const ref = db.collection('users').doc('user123');
    await firebase.assertFails(ref.get());
  });

  test('authenticated user can read own profile', async () => {
    const auth = testEnv.authenticatedContext('user123', { role: 'CC' });
    const db = auth.firestore();
    const ref = db.collection('users').doc('user123');
    await firebase.assertSucceeds(ref.set({ name: 'Me' }));
    await firebase.assertSucceeds(ref.get());
  });
});

