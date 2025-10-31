"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendPendingEmails = exports.acceptInvite = exports.revokeInvite = exports.listInvites = exports.createInvite = void 0;
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const crypto_1 = require("crypto");
admin.initializeApp();
const db = admin.firestore();
const SENDGRID_API_KEY = process.env.SENDGRID_API_KEY || '';
const SEND_FROM = process.env.SEND_FROM || `no-reply@${(process.env.APP_DOMAIN || 'example.app')}`;
function genTokenPair() {
    const buf = (0, crypto_1.randomBytes)(32);
    const token = buf.toString('base64url');
    const hash = (0, crypto_1.createHash)('sha256').update(token).digest('hex');
    return { token, hash };
}
async function userHasAnyRole(uid, roles) {
    const doc = await db.doc(`users/${uid}`).get();
    if (!doc.exists)
        return false;
    const data = doc.data();
    return roles.includes(data?.role);
}
function classesWithinScope(inviterAllowed, requested) {
    if (!Array.isArray(inviterAllowed))
        return false;
    if (!Array.isArray(requested))
        return false;
    const allowedSet = new Set(inviterAllowed.map((s) => String(s).trim()));
    for (const r of requested) {
        if (!allowedSet.has(String(r).trim()))
            return false;
    }
    return true;
}
exports.createInvite = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
    }
    const inviterUid = context.auth.uid;
    const invitedEmail = String((data && data.invitedEmail) || '').toLowerCase();
    const role = String((data && data.role) || '');
    const allowedClasses = Array.isArray(data?.allowedClasses) ? data.allowedClasses : [];
    const expiresInDays = Number(data?.expiresInDays) || 7;
    if (!invitedEmail || !role) {
        throw new functions.https.HttpsError('invalid-argument', 'invitedEmail and role are required');
    }
    const allowedInviterRoles = ['CC', 'HOD', 'ADMIN'];
    const inviterDoc = await db.doc(`users/${inviterUid}`).get();
    const inviter = inviterDoc.exists ? inviterDoc.data() : null;
    const inviterRole = inviter?.role || 'UNKNOWN';
    if (!allowedInviterRoles.includes(inviterRole)) {
        throw new functions.https.HttpsError('permission-denied', 'Insufficient permissions to create invites');
    }
    if (inviterRole === 'CC') {
        const inviterAllowed = inviter?.allowed_classes || inviter?.allowedClasses || [];
        if (!Array.isArray(inviterAllowed) || inviterAllowed.length === 0) {
            throw new functions.https.HttpsError('permission-denied', 'Inviter has no allowed classes configured');
        }
        if (!classesWithinScope(inviterAllowed, allowedClasses)) {
            throw new functions.https.HttpsError('permission-denied', 'Requested allowedClasses exceed inviter scope');
        }
    }
    const { token, hash } = genTokenPair();
    const now = admin.firestore.FieldValue.serverTimestamp();
    const expiresAt = admin.firestore.Timestamp.fromDate(new Date(Date.now() + expiresInDays * 24 * 60 * 60 * 1000));
    const docRef = await db.collection('invites').add({
        tokenHash: hash,
        invitedEmail,
        role,
        allowedClasses,
        expiresAt,
        used: false,
        createdBy: inviterUid,
        createdAt: now,
    });
    const appUrl = process.env.APP_URL || 'https://example.app';
    const inviteLink = `${appUrl}/accept-invite?token=${encodeURIComponent(token)}`;
    const dynamicDomain = process.env.DYNAMIC_LINK_DOMAIN;
    const dynamicLink = dynamicDomain ? `https://${dynamicDomain}/?link=${encodeURIComponent(inviteLink)}` : null;
    const bodyLines = [
        `Hello,`,
        `\nYou have been invited to join the Attendance app as ${role}.`,
        `Click the link to accept:`,
        ``,
        `${inviteLink}`,
    ];
    if (dynamicLink) {
        bodyLines.push('', 'If clicking from mobile, try this link:', '', `${dynamicLink}`);
    }
    bodyLines.push('', `This link expires in ${expiresInDays} days.`);
    const body = bodyLines.join('\n');
    await db.collection('email_outbox').add({
        to: invitedEmail,
        subject: `You're invited to join the Attendance app as ${role}`,
        body,
        metadata: { inviteId: docRef.id, role, allowedClasses, dynamicLink },
        createdAt: now,
        sent: false,
    });
    return {
        inviteId: docRef.id,
        token,
        message: 'Invite created (token returned for development). In production an email would be sent.'
    };
});
exports.listInvites = functions.https.onCall(async (data, context) => {
    if (!context.auth)
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
    const uid = context.auth.uid;
    const allowedAdminRoles = ['HOD', 'ADMIN'];
    const isAdmin = await userHasAnyRole(uid, allowedAdminRoles);
    let query = db.collection('invites').orderBy('createdAt', 'desc').limit(100);
    if (!isAdmin) {
        query = query.where('createdBy', '==', uid);
    }
    const snap = await query.get();
    const results = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    return { invites: results };
});
exports.revokeInvite = functions.https.onCall(async (data, context) => {
    if (!context.auth)
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
    const uid = context.auth.uid;
    const inviteId = String((data && data.inviteId) || '');
    if (!inviteId)
        throw new functions.https.HttpsError('invalid-argument', 'inviteId required');
    const docRef = db.collection('invites').doc(inviteId);
    const doc = await docRef.get();
    if (!doc.exists)
        throw new functions.https.HttpsError('not-found', 'Invite not found');
    const invite = doc.data();
    const isCreator = invite.createdBy === uid;
    const isAdmin = await userHasAnyRole(uid, ['HOD', 'ADMIN']);
    if (!isCreator && !isAdmin) {
        throw new functions.https.HttpsError('permission-denied', 'Not allowed to revoke this invite');
    }
    await docRef.update({ used: true, revoked: true, revokedBy: uid, revokedAt: admin.firestore.FieldValue.serverTimestamp() });
    await db.collection('audit_logs').add({
        actor_uid: uid,
        action: 'revoke_invite',
        target: inviteId,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        details: { revokedBy: uid },
    });
    return { success: true };
});
exports.acceptInvite = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
    }
    const token = String((data && data.token) || '');
    const uid = context.auth.uid;
    const email = String((context.auth.token && (context.auth.token.email || ''))).toLowerCase();
    if (!token) {
        throw new functions.https.HttpsError('invalid-argument', 'token is required');
    }
    const hash = (0, crypto_1.createHash)('sha256').update(token).digest('hex');
    const invites = await db.collection('invites').where('tokenHash', '==', hash).limit(1).get();
    if (invites.empty) {
        throw new functions.https.HttpsError('not-found', 'Invite not found');
    }
    const inviteDoc = invites.docs[0];
    const invite = inviteDoc.data();
    if (invite.used === true) {
        throw new functions.https.HttpsError('failed-precondition', 'Invite already used');
    }
    const nowTs = admin.firestore.Timestamp.now();
    if (invite.expiresAt && invite.expiresAt.toMillis && invite.expiresAt.toMillis() < nowTs.toMillis()) {
        throw new functions.https.HttpsError('deadline-exceeded', 'Invite expired');
    }
    const invitedEmail = String(invite.invitedEmail || '').toLowerCase();
    if (invitedEmail && invitedEmail !== email) {
        throw new functions.https.HttpsError('permission-denied', 'Signed-in email does not match invited email');
    }
    const userDocRef = db.doc(`users/${uid}`);
    await userDocRef.set({
        uid,
        email,
        role: invite.role || 'CR',
        allowed_classes: invite.allowedClasses || [],
        is_active: true,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    await inviteDoc.ref.update({ used: true, usedBy: uid, usedAt: admin.firestore.FieldValue.serverTimestamp() });
    await db.collection('audit_logs').add({
        actor_uid: uid,
        action: 'accept_invite',
        target: inviteDoc.id,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        details: { invitedEmail },
    });
    return { success: true, message: 'Invite accepted and user created/updated' };
});
exports.sendPendingEmails = functions.https.onCall(async (data, context) => {
    if (!context.auth)
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
    const uid = context.auth.uid;
    const allowed = await userHasAnyRole(uid, ['HOD', 'ADMIN']);
    if (!allowed)
        throw new functions.https.HttpsError('permission-denied', 'Insufficient permissions');
    const limit = Number(data?.limit) || 50;
    const snap = await db.collection('email_outbox').where('sent', '==', false).orderBy('createdAt').limit(limit).get();
    if (snap.empty)
        return { processed: 0 };
    let processed = 0;
    const results = [];
    for (const doc of snap.docs) {
        const item = doc.data();
        const to = item.to;
        const subject = item.subject || 'Notification';
        const body = item.body || '';
        try {
            if (SENDGRID_API_KEY) {
                try {
                    const sgMail = require('@sendgrid/mail');
                    if (typeof sgMail.setApiKey === 'function')
                        sgMail.setApiKey(SENDGRID_API_KEY);
                    await sgMail.send({
                        to,
                        from: SEND_FROM,
                        subject,
                        text: body,
                    });
                    await doc.ref.update({ sent: true, sentAt: admin.firestore.FieldValue.serverTimestamp(), provider: 'sendgrid' });
                    results.push({ id: doc.id, status: 'sent' });
                }
                catch (requireErr) {
                    console.error('SendGrid module not available or failed to send:', requireErr);
                    await doc.ref.update({ last_error: 'SendGrid module missing or send failed: ' + String(requireErr?.message || requireErr), attemptedAt: admin.firestore.FieldValue.serverTimestamp() });
                    results.push({ id: doc.id, status: 'error', error: String(requireErr?.message || requireErr) });
                }
            }
            else {
                console.log('Email (not sent, no SENDGRID_API_KEY):', { id: doc.id, to, subject, body });
                await doc.ref.update({ logged: true, loggedAt: admin.firestore.FieldValue.serverTimestamp() });
                results.push({ id: doc.id, status: 'logged' });
            }
            processed++;
        }
        catch (err) {
            console.error('Failed to send email for', doc.id, err);
            await doc.ref.update({ last_error: String(err?.message || err), attemptedAt: admin.firestore.FieldValue.serverTimestamp() });
            results.push({ id: doc.id, status: 'error', error: String(err?.message || err) });
        }
    }
    return { processed, results };
});
//# sourceMappingURL=index.js.map