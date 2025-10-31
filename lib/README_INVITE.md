Invite flow (local testing)

1. Start Firebase emulators (functions + firestore + auth) in the `functions/` folder:

   In cmd.exe run:

   ```cmd
   cd functions && npm install
   npm run serve
   ```

   This uses the local `firebase-tools` (via `npx`) if you don't have the Firebase CLI installed globally. If you prefer the global CLI, run `firebase init emulators` once at the project root to generate emulator configuration and then `firebase emulators:start --only functions,firestore,auth`.

2. From the app, sign in as a test user (email must match invitedEmail when accepting).

3. Create an invite (dev-only token shown in response):
   - Open the in-app route: /create-invite
   - Fill invited email, role and allowed classes and press Create Invite
   - Copy the returned token from the UI

4. Accept the invite:
   - Open the in-app route: /accept-invite?token=<PASTE_TOKEN>
   - Or paste the token into the Accept Invite screen and press Accept Invite

Notes:
- The functions scaffold returns the plain token in the createInvite response for convenience in development only. In production you MUST email the token and store only a hash in Firestore.
- The functions enforce simple role checks (only CC/HOD/ADMIN can create invites). Ensure your test user in `users/{uid}` has an appropriate `role` field.
