import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { v4 as uuidv4 } from 'uuid';

admin.initializeApp();
const db = admin.firestore();

// Create an invite: stores token (hashed) and metadata in Firestore and returns a one-time token.
export const createInvite = functions.https.onCall(async (data, context) => {
  // Only authenticated users may create invites in production - require custom claim 'CC' or 'ADMIN'
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Only authenticated users can create invites');
  }

  const callerClaims = context.auth.token || {};
  if (!['CC','ADMIN','HOD'].includes(callerClaims.role)) {
    throw new functions.https.HttpsError('permission-denied', 'Insufficient permissions to create invite');
  }

  const invitedEmail: string = (data.invitedEmail || '').toLowerCase();
  const role: string = data.role || 'CC';
  const allowedClasses = data.allowedClasses || [];
  const expiresInDays = data.expiresInDays || 7;

  if (!invitedEmail) throw new functions.https.HttpsError('invalid-argument', 'invitedEmail required');

  const token = uuidv4();
  const doc = {
    token, // store token directly for simplicity; in production consider hashing
    invitedEmail,
    role,
    allowedClasses,
    expiresAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + expiresInDays * 24 * 60 * 60 * 1000)),
    used: false,
    createdBy: context.auth.uid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  const inviteRef = await db.collection('invites').add(doc as any);

  return { inviteId: inviteRef.id, token };
});

// Accept an invite: supply token and current auth user; function sets user's custom claims and marks invite used.
export const acceptInvite = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Must be signed in to accept invite');
  }

  const token: string = data.token || '';
  if (!token) throw new functions.https.HttpsError('invalid-argument', 'token required');

  const invites = await db.collection('invites').where('token', '==', token).where('used', '==', false).limit(1).get();
  if (invites.empty) throw new functions.https.HttpsError('not-found', 'Invalid or used invite token');

  const invite = invites.docs[0];
  const inviteData = invite.data();
  const expiresAt = (inviteData.expiresAt as admin.firestore.Timestamp).toDate();
  if (expiresAt < new Date()) throw new functions.https.HttpsError('deadline-exceeded', 'Invite expired');

  const role = inviteData.role || 'CC';
  const allowedClasses = inviteData.allowedClasses || [];

  // Set custom claims for the user
  await admin.auth().setCustomUserClaims(context.auth.uid, { role, allowedClasses });

  // Mark invite used
  await invite.ref.update({ used: true, usedBy: context.auth.uid, usedAt: admin.firestore.FieldValue.serverTimestamp() });

  return { success: true, role };
});

// Revoke a user's refresh tokens (admin-only). Caller must be authenticated and have ADMIN role.
export const revokeUserSession = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Must be signed in');
  }

  const callerClaims = context.auth.token || {};
  if (callerClaims.role !== 'ADMIN') {
    throw new functions.https.HttpsError('permission-denied', 'Only admins can revoke sessions');
  }

  const targetUid: string = data.uid;
  if (!targetUid) throw new functions.https.HttpsError('invalid-argument', 'uid required');

  try {
    await admin.auth().revokeRefreshTokens(targetUid);
    // Optionally record the revocation time
    await db.collection('revocations').add({ uid: targetUid, revokedAt: admin.firestore.FieldValue.serverTimestamp(), revokedBy: context.auth.uid });
    return { success: true };
  } catch (err) {
    throw new functions.https.HttpsError('internal', 'Failed to revoke session');
  }
});
