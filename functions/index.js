const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

// Utility: check if caller has permission token in users/{uid}.permissions array
async function callerHasPermission(callerUid, permission) {
  if (!callerUid) return false;
  try {
    const doc = await db.collection('users').doc(callerUid).get();
    if (!doc.exists) return false;
    const data = doc.data() || {};
    const perms = data.permissions || [];
    const role = (data.role || '').toString().toUpperCase();
    // HOD and ADMIN treated as super-privileged
    if (role === 'HOD' || role === 'ADMIN') return true;
    return perms.includes(permission);
  } catch (e) {
    console.error('callerHasPermission error', e);
    return false;
  }
}

// Approve a CR request. Expects { requestId: string, targetUid?: string }
exports.approveCr = functions.https.onCall(async (data, context) => {
  const callerUid = context.auth?.uid;
  if (!callerUid) throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  const ok = await callerHasPermission(callerUid, 'approve_cr');
  if (!ok) throw new functions.https.HttpsError('permission-denied', 'Caller lacks approve_cr permission');

  const requestId = data.requestId;
  if (!requestId) throw new functions.https.HttpsError('invalid-argument', 'requestId is required');

  const reqRef = db.collection('cr_requests').doc(requestId);
  const reqSnap = await reqRef.get();
  if (!reqSnap.exists) throw new functions.https.HttpsError('not-found', 'CR request not found');
  const req = reqSnap.data();
  if (!req) throw new functions.https.HttpsError('not-found', 'CR request missing data');
  if (req.status === 'approved') return { success: true, message: 'Already approved' };

  // Determine target user UID. If targetUid provided, use that, else try to find user by email
  let targetUid = data.targetUid;
  if (!targetUid) {
    // try to find user by invited_email or email in users collection
    const email = (req.invited_email || req.email || '').toString().toLowerCase();
    if (email) {
      const q = await db.collection('users').where('email', '==', email).limit(1).get();
      if (!q.empty) targetUid = q.docs[0].id;
    }
  }

  // If still no targetUid, create a new user doc (without auth user) and set a placeholder uid
  if (!targetUid) {
    const newDoc = db.collection('users').doc();
    targetUid = newDoc.id;
  }

  // Write user doc: add role=CR and allowed_classes from request, add default permissions
  const allowedClasses = req.allowed_classes || [];
  const userRef = db.collection('users').doc(targetUid);
  const userData = {
    role: 'CR',
    allowed_classes: allowedClasses,
    permissions: [ 'take_attendance', 'view_reports' ],
    is_active: 1,
    name: req.name || req.invited_name || '',
    email: req.invited_email || req.email || '',
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  };

  const batch = db.batch();
  batch.set(userRef, userData, { merge: true });
  batch.update(reqRef, { status: 'approved', reviewed_by: callerUid, reviewed_at: admin.firestore.FieldValue.serverTimestamp() });

  // Audit log
  const auditRef = db.collection('audit_logs').doc();
  batch.set(auditRef, {
    actorUid: callerUid,
    action: 'approve_cr',
    targetId: targetUid,
    details: { requestId },
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });

  await batch.commit();

  return { success: true, targetUid };
});

// Deactivate a student document (soft delete). Expects { studentId: string }
exports.deactivateStudent = functions.https.onCall(async (data, context) => {
  const callerUid = context.auth?.uid;
  if (!callerUid) throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  const ok = await callerHasPermission(callerUid, 'deactivate_student');
  if (!ok) throw new functions.https.HttpsError('permission-denied', 'Caller lacks deactivate_student permission');

  const studentId = data.studentId;
  if (!studentId) throw new functions.https.HttpsError('invalid-argument', 'studentId is required');

  const studentRef = db.collection('students').doc(studentId);
  const snap = await studentRef.get();
  if (!snap.exists) throw new functions.https.HttpsError('not-found', 'Student not found');

  await studentRef.update({ active: false, updated_at: admin.firestore.FieldValue.serverTimestamp() });

  // Audit log
  await db.collection('audit_logs').add({
    actorUid: callerUid,
    action: 'deactivate_student',
    targetId: studentId,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { success: true };
});

// Create Firestore user profile when a new Firebase Auth user is created.
exports.createUserProfileOnAuth = functions.auth.user().onCreate(async (user) => {
  const uid = user.uid;
  const email = (user.email || '').toString().toLowerCase();
  const displayName = user.displayName || '';

  const profileRef = db.collection('users').doc(uid);
  const profileData = {
    uid: uid,
    email: email,
    name: displayName,
    department: '',
    division: '',
    year: 0,
    role: 'STUDENT',
    is_active: 1,
    isActive: true,
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  };

  try {
    // Use merge:true to preserve any existing fields (e.g., invites or pre-created docs)
    await profileRef.set(profileData, { merge: true });
    console.log(`createUserProfileOnAuth: created profile for uid=${uid}`);
    return { success: true };
  } catch (err) {
    console.error(`createUserProfileOnAuth: failed to write profile for uid=${uid}`, err);
    // Rethrow to let Functions retry based on platform behavior
    throw err;
  }
});

