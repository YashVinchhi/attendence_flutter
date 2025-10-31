// This script creates users in your *running* Firebase AUTHENTICATION emulator.

// 1. Import the admin SDK
// Make sure to run `npm install firebase-admin` in your terminal first.
const admin = require('firebase-admin');

// 2. Define the auth users to be created
const authUsersToSeed = [
    {
        uid: 'uid-yash-cr',
        email: 'yash@example.com',
        password: 'root123'
    },
    {
        uid: 'uid-parita-cc',
        email: 'parita@example.com',
        password: 'class123'
    },
    {
        uid: 'uid-chetan-hod',
        email: 'chetan@example.com',
        password: 'dept123'
    },
    {
        uid: 'uid-vinchhi-admin',
        email: 'vinchhi@example.com',
        password: 'tree123'
    }
];

// 3. Initialize the Firebase Admin App
// Use your project ID to match the emulator
try {
    admin.initializeApp({
        projectId: 'attendance-b9f1a',
    });
} catch (e) {
    // This handles the "app already initialized" error
    if (e.code !== 'app/duplicate-app') {
        console.error('Firebase admin initialization error:', e);
    }
}

// 4. Get a reference to the Auth service
const auth = admin.auth();

// 5. !! IMPORTANT !! Set the emulator host
// This environment variable tells the SDK to use the auth emulator.
// This assumes your auth emulator is running on the default port (9099).
process.env.FIREBASE_AUTH_EMULATOR_HOST = 'localhost:9099';

// 6. Asynchronous function to create all auth users
async function seedAuth() {
    console.log('Starting to seed auth emulator...');
    
    const creationPromises = [];

    for (const user of authUsersToSeed) {
        console.log(`Creating auth user: ${user.email} (UID: ${user.uid})`);
        
        const userPayload = {
            uid: user.uid,
            email: user.email,
            password: user.password,
            emailVerified: true // Let's assume they are verified for demo purposes
        };
        
        // Create the user in Firebase Auth
        creationPromises.push(auth.createUser(userPayload).catch(error => {
            // Handle case where user already exists
            if (error.code === 'auth/uid-already-exists' || error.code === 'auth/email-already-exists') {
                console.warn(`Warning: Auth user ${user.email} already exists. Skipping creation.`);
                return null; // Return null to indicate a handled "error"
            }
            // Re-throw other errors
            throw error;
        }));
    }

    // Wait for all create operations to complete
    try {
        await Promise.all(creationPromises);
        console.log('---------------------------------');
        console.log('✅ Auth emulator seeding complete.');
        console.log(`(Users who didn't already exist have been created).`);
        
        // We must manually exit the script
        process.exit(0);

    } catch (error) {
        console.error('Error creating auth users:', error);
        process.exit(1);
    }
}

// 7. Run the seed function
seedAuth();


