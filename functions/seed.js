// Simple seeder for the Firestore emulator
// Usage (cmd.exe):
//   set UID=Dq4ZiCVBZU1Ia2v2nXcgrfxugzcJ && set EMAIL=test-inviter@example.com && node seed.js

const admin = require('firebase-admin');

// Ensure we target the Firestore emulator if not already set
process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || 'localhost:8080';

// Initialize with projectId matching firebase.json
admin.initializeApp({ projectId: 'attendance-b9f1a' });
const db = admin.firestore();

const uid = process.env.UID || 'Dq4ZiCVBZU1Ia2v2nXcgrfxugzcJ';
const email = process.env.EMAIL || 'test-inviter@example.com';

const doc = {
  uid,
  email,
  role: process.env.ROLE || 'CC',
  allowed_classes: process.env.CLASSES ? process.env.CLASSES.split(',') : ['2CEIT-B'],
  is_active: true,
  created_at: admin.firestore.FieldValue.serverTimestamp(),
};

async function seed() {
  try {
    await db.doc(`users/${uid}`).set(doc, { merge: true });
    console.log(`Seeded users/${uid} in Firestore emulator`);
    console.log(JSON.stringify(doc, null, 2));
    process.exit(0);
  } catch (err) {
    console.error('Failed to seed Firestore emulator:', err);
    process.exit(1);
  }
}

seed();

