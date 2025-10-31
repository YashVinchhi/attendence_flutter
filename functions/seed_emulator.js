// Simple seeder for Firebase emulators: creates Auth users and Firestore user docs
// Usage (Windows cmd.exe):
//   cd functions
//   node seed_emulator.js
// The script targets the emulators by setting FIRESTORE_EMULATOR_HOST and
// FIREBASE_AUTH_EMULATOR_HOST if they are not already set.

const admin = require('firebase-admin');

// Default emulator hosts/ports (match firebase.json)
process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || 'localhost:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || 'localhost:9099';

// Initialize admin with the same projectId as firebase.json
admin.initializeApp({ projectId: 'attendance-b9f1a' });
const auth = admin.auth();
const db = admin.firestore();

// Test accounts to seed
const users = [
  {
    uid: 'yash_cr',
    email: 'yash@example.com',
    password: 'root123',
    name: 'Yash (CR)',
    role: 'CR',
    allowed_classes: ['2CEIT-B'],
  },
  {
    uid: 'parita_cc',
    email: 'parita@example.com',
    password: 'class123',
    name: 'Parita (CC)',
    role: 'CC',
    allowed_classes: ['2CEIT-B', '2CEIT-A'],
  },
  {
    uid: 'chetan_hod',
    email: 'chetan@example.com',
    password: 'dept123',
    name: 'Chetan (HOD)',
    role: 'HOD',
    allowed_classes: [],
  },
  {
    uid: 'vinchhi_admin',
    email: 'vinchhi@example.com',
    password: 'tree123',
    name: 'Vinchhi (Admin)',
    role: 'ADMIN',
    allowed_classes: [],
  },
];

async function ensureAuthUser(u) {
  try {
    const existing = await auth.getUserByEmail(u.email);
    console.log(`Auth user exists: ${u.email} (uid=${existing.uid})`);
    return existing.uid;
  } catch (getErr) {
    // create
    try {
      const created = await auth.createUser({
        uid: u.uid,
        email: u.email,
        password: u.password,
        displayName: u.name,
      });
      console.log(`Created auth user: ${u.email} (uid=${created.uid})`);
      return created.uid;
    } catch (createErr) {
      console.error(`Failed to create auth user ${u.email}:`, createErr);
      throw createErr;
    }
  }
}

async function ensureFirestoreUser(uid, u) {
  const docRef = db.doc(`users/${uid}`);
  const doc = {
    uid,
    email: u.email,
    name: u.name,
    role: u.role,
    allowed_classes: u.allowed_classes,
    is_active: true,
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  };
  await docRef.set(doc, { merge: true });
  console.log(`Seeded users/${uid} in Firestore emulator`);
}

async function seedAll() {
  console.log('Seeding emulator: FIRESTORE_EMULATOR_HOST=', process.env.FIRESTORE_EMULATOR_HOST, 'AUTH_EMULATOR=', process.env.FIREBASE_AUTH_EMULATOR_HOST);
  for (const u of users) {
    try {
      const uid = await ensureAuthUser(u);
      await ensureFirestoreUser(uid, u);
    } catch (err) {
      console.error('Error seeding user', u.email, err);
    }
  }
  console.log('Seeding complete.');
  process.exit(0);
}

seedAll();

