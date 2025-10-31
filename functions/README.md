# Cloud Functions for Attendance App

This folder contains two callable Cloud Functions used by the Attendance Flutter app:

- `approveCr` - Approve a CR request and create/update a `users/{uid}` document with CR role and default permissions.
- `deactivateStudent` - Soft-deactivate a student by setting `students/{studentId}.active = false` and writing an audit log.

Prerequisites
- Firebase CLI installed and logged in (`npm install -g firebase-tools`)
- Node 18+ installed

Quick start
1. Install dependencies

```bash
cd functions
npm install
```

2. Emulate locally (recommended during development)

```bash
firebase emulators:start --only firestore,functions,auth
```

3. Deploy to Firebase (production)

```bash
cd functions
firebase deploy --only functions
```

Notes
- These functions check a `permissions` array on the caller's `users/{uid}` document. Ensure your user documents include the required permission tokens (e.g., `approve_cr`, `deactivate_student`). Roles `HOD` and `ADMIN` are treated as super-privileged by the functions.
- All admin actions are recorded in `audit_logs` collection for accountability.

