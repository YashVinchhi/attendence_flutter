// This script uses the Firebase Admin SDK to populate your *running* Firestore emulator.
// NOTE: This file is unchanged. It works with the new seed_auth_emulator.js

// 1. Import the admin SDK
// Make sure to run `npm install firebase-admin` in your terminal first.
const admin = require('firebase-admin');

// 2. Define the user data to be added
const usersToSeed = [
    {
        uid: 'uid-yash-cr',
        email: 'yash@example.com',
        displayName: 'Yash (CR)',
        role: 'CR',
        is_active: true,
        allowed_classes: ['2CEIT-B'] // A Class Rep (CR) for one class
    },
    {
        uid: 'uid-parita-cc',
        email: 'parita@example.com',
        displayName: 'Parita (CC)',
        role: 'CC',
        is_active: true,
        allowed_classes: ['2CEIT-A', '2CEIT-B'] // A Class Coordinator (CC) for two classes
    },
    {
        uid: 'uid-chetan-hod',
        email: 'chetan@example.com',
        displayName: 'Chetan (HOD)',
        role: 'HOD',
        is_active: true,
        allowed_classes: ['2CEIT-A', '2CEIT-B', '3MECH-A', '3MECH-B'] // Head of Dept. over multiple years/branches
    },
    {
        uid: 'uid-vinchhi-admin',
        email: 'vinchhi@example.com',
        displayName: 'Vinchhi (Admin)',
        role: 'ADMIN',
        is_active: true,
        allowed_classes: [] // Admin role access is checked by role, not class list
    }
];

// 3. Initialize the Firebase Admin App
// Use your project ID to match the emulator
try {
    admin.initializeApp({
        projectId: 'attendance-b9f1a',
    });
} catch (e) {
    // This handles the "app already initialized" error if you run the script multiple times
    if (e.code !== 'app/duplicate-app') {
        console.error('Firebase admin initialization error:', e);
    }
}


// 4. Get a reference to the Firestore database
const db = admin.firestore();

// 5. !! IMPORTANT !! Point the SDK to the running emulator
// This assumes your Firestore emulator is running on the default port (8080).
db.settings({
    host: 'localhost:8080',
    ssl: false
});

// 6. Asynchronous function to add all users
async function seedDatabase() {
    console.log('Starting to seed database...');
    
    const writePromises = [];

    for (const user of usersToSeed) {
        console.log(`Adding user: ${user.displayName} (Role: ${user.role})`);
        
        // Get a reference to the document using the user's UID
        const docRef = db.collection('users').doc(user.uid);
        
        // Use set() to create or overwrite the document
        // We remove 'uid' from the object since it's the document ID, not a field
        const { uid, ...userData } = user; 
        writePromises.push(docRef.set(userData).catch(error => {
            console.error(`Error writing doc ${user.uid}:`, error);
        }));
    }

    // Wait for all write operations to complete
    try {
        await Promise.all(writePromises);
        console.log('---------------------------------');
        console.log('✅ Database seeded successfully!');
        console.log(`${usersToSeed.length} user documents created/updated.`);
        
        // We must manually exit the script, as the Firebase connection stays open
        process.exit(0);

    } catch (error) {
        console.error('Error writing documents to emulator:', error);
        process.exit(1);
    }
}

// 7. Run the seed function
seedDatabase();


