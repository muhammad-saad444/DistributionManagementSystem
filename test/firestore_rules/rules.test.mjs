// Tests for ../../firestore.rules against the local Firestore emulator (no real data).
// Run from this folder:  npm install  then  npm test
import { after, before, beforeEach, describe, test } from 'node:test';
import { readFileSync } from 'node:fs';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, writeBatch, collection, query, where, getDocs } from 'firebase/firestore';

let env;
const OWNER = 'owner1', ADMIN = 'admin1', BOOKER = 'booker1', OFF = 'off1', NEW = 'new1', OTHER_ADMIN = 'other1';

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-rules',
    firestore: { rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8') },
  });
});
after(() => env.cleanup());
beforeEach(() => env.clearFirestore());

const db = (uid, email) => env.authenticatedContext(uid, email ? { email } : {}).firestore();

/// A set-up world: the original company, an owner, admin, booker, switched-off booker,
/// someone waiting for approval, and an admin of another company.
async function seed() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    await setDoc(doc(d, 'companies/an-agency'), { name: 'A.N Agency', status: 'active', ownerUid: OWNER, modules: {} });
    await setDoc(doc(d, 'companies/other-co'), { name: 'Other', status: 'active', ownerUid: OTHER_ADMIN, modules: {} });
    const u = (companyId, role, status) => ({ companyId, role, status, name: '', email: '' });
    await setDoc(doc(d, `users/${OWNER}`), u('an-agency', 'owner', 'active'));
    await setDoc(doc(d, `users/${ADMIN}`), u('an-agency', 'admin', 'active'));
    await setDoc(doc(d, `users/${BOOKER}`), u('an-agency', 'booker', 'active'));
    await setDoc(doc(d, `users/${OFF}`), u('an-agency', 'booker', 'disabled'));
    await setDoc(doc(d, `users/${NEW}`), u(null, 'booker', 'pending'));
    await setDoc(doc(d, `users/${OTHER_ADMIN}`), u('other-co', 'owner', 'active'));
    await setDoc(doc(d, 'invoices/inv1'), { total: 100 });
  });
}

describe('before setup (company not created yet)', () => {
  test('anyone signed in still reads business data, as before', async () => {
    await env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), 'invoices/inv1'), { total: 1 }));
    await assertSucceeds(getDoc(doc(db('someone'), 'invoices/inv1')));
  });
  test('signed-out people read nothing', async () => {
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'invoices/inv1')));
  });
  test('the app can see the company is missing', async () => {
    await assertSucceeds(getDoc(doc(db('someone'), 'companies/an-agency')));
  });
  test('the original admin creates the company and becomes owner', async () => {
    const d = db(OWNER, 'admin@gmail.com');
    const b = writeBatch(d);
    b.set(doc(d, 'companies/an-agency'), { name: 'A.N Agency', status: 'active', ownerUid: OWNER, modules: {} });
    b.set(doc(d, `users/${OWNER}`), { companyId: 'an-agency', role: 'owner', status: 'active', name: 'admin', email: '' });
    await assertSucceeds(b.commit());
  });
  test('any other login cannot create the company', async () => {
    const d = db('intruder', 'x@gmail.com');
    const b = writeBatch(d);
    b.set(doc(d, 'companies/an-agency'), { name: 'A.N Agency', status: 'active', ownerUid: 'intruder', modules: {} });
    b.set(doc(d, 'users/intruder'), { companyId: 'an-agency', role: 'owner', status: 'active' });
    await assertFails(b.commit());
  });
  test('nobody can make themselves owner without creating the company', async () => {
    await assertFails(setDoc(doc(db('intruder', 'admin@gmail.com'), 'users/intruder'),
      { companyId: 'an-agency', role: 'owner', status: 'active' }));
  });
});

describe('after setup', () => {
  beforeEach(seed);

  test('active members read business data', async () => {
    await assertSucceeds(getDoc(doc(db(BOOKER), 'invoices/inv1')));
  });
  test('switched-off people are kept out of business data', async () => {
    await assertFails(getDoc(doc(db(OFF), 'invoices/inv1')));
  });
  test('people waiting for approval are kept out', async () => {
    await assertFails(getDoc(doc(db(NEW), 'invoices/inv1')));
  });
  test('a login with no users record is kept out', async () => {
    await assertFails(getDoc(doc(db('stranger'), 'invoices/inv1')));
  });
  test('anyone can still write their own login session', async () => {
    await assertSucceeds(setDoc(doc(db(NEW), `sessions/${NEW}`), { uid: NEW }));
    await assertFails(setDoc(doc(db(NEW), `sessions/${BOOKER}`), { uid: NEW }));
  });

  test('someone new can ask to join as a pending booker', async () => {
    await assertSucceeds(setDoc(doc(db('fresh'), 'users/fresh'), { companyId: null, role: 'booker', status: 'pending' }));
  });
  test('someone new cannot join a company or pick a role themselves', async () => {
    await assertFails(setDoc(doc(db('fresh'), 'users/fresh'), { companyId: 'an-agency', role: 'booker', status: 'active' }));
    await assertFails(setDoc(doc(db('fresh'), 'users/fresh'), { companyId: null, role: 'admin', status: 'pending' }));
  });

  test('a booker cannot make themselves admin', async () => {
    await assertFails(updateDoc(doc(db(BOOKER), `users/${BOOKER}`), { role: 'admin' }));
  });
  test('a booker cannot move to another company', async () => {
    await assertFails(updateDoc(doc(db(BOOKER), `users/${BOOKER}`), { companyId: 'other-co' }));
  });
  test('a switched-off booker cannot switch themselves back on', async () => {
    await assertFails(updateDoc(doc(db(OFF), `users/${OFF}`), { status: 'active' }));
  });
  test('people may change their own name', async () => {
    await assertSucceeds(updateDoc(doc(db(BOOKER), `users/${BOOKER}`), { name: 'Ali' }));
  });
  test('a booker cannot read other people', async () => {
    await assertFails(getDoc(doc(db(BOOKER), `users/${ADMIN}`)));
    await assertFails(getDocs(query(collection(db(BOOKER), 'users'), where('companyId', '==', 'an-agency'))));
  });

  test("an admin lists their company's people", async () => {
    await assertSucceeds(getDocs(query(collection(db(ADMIN), 'users'), where('companyId', '==', 'an-agency'))));
  });
  test("an admin cannot list another company's people", async () => {
    await assertFails(getDocs(query(collection(db(ADMIN), 'users'), where('companyId', '==', 'other-co'))));
  });
  test('an admin sees requests waiting for approval', async () => {
    await assertSucceeds(getDocs(query(collection(db(ADMIN), 'users'),
      where('status', '==', 'pending'), where('companyId', '==', null))));
  });
  test('an admin approves a request into their own company', async () => {
    await assertSucceeds(updateDoc(doc(db(ADMIN), `users/${NEW}`), { companyId: 'an-agency', role: 'booker', status: 'active' }));
  });
  test('during setup the owner adds people who logged in before', async () => {
    await assertSucceeds(setDoc(doc(db(OWNER), 'users/oldbooker'),
      { companyId: 'an-agency', role: 'booker', status: 'active', name: 'Ali', email: '' }, { merge: true }));
  });
  test('an admin cannot add someone as owner or into another company', async () => {
    await assertFails(setDoc(doc(db(OWNER), 'users/x1'), { companyId: 'an-agency', role: 'owner', status: 'active' }));
    await assertFails(setDoc(doc(db(OWNER), 'users/x2'), { companyId: 'other-co', role: 'booker', status: 'active' }));
  });
  test('an admin cannot approve someone as owner', async () => {
    await assertFails(updateDoc(doc(db(ADMIN), `users/${NEW}`), { companyId: 'an-agency', role: 'owner', status: 'active' }));
  });
  test('an admin cannot approve someone into another company', async () => {
    await assertFails(updateDoc(doc(db(ADMIN), `users/${NEW}`), { companyId: 'other-co', role: 'booker', status: 'active' }));
  });
  test('an admin changes a booker to admin and switches people off', async () => {
    await assertSucceeds(updateDoc(doc(db(ADMIN), `users/${BOOKER}`), { role: 'admin' }));
    await assertSucceeds(updateDoc(doc(db(OWNER), `users/${BOOKER}`), { status: 'disabled' }));
  });
  test('an admin cannot change the owner or themselves', async () => {
    await assertFails(updateDoc(doc(db(ADMIN), `users/${OWNER}`), { role: 'booker' }));
    await assertFails(updateDoc(doc(db(ADMIN), `users/${ADMIN}`), { role: 'owner' }));
  });
  test("another company's admin cannot touch this company's people", async () => {
    await assertFails(updateDoc(doc(db(OTHER_ADMIN), `users/${BOOKER}`), { status: 'disabled' }));
    await assertFails(getDoc(doc(db(OTHER_ADMIN), `users/${BOOKER}`)));
  });

  test('members read their own company, not others', async () => {
    await assertSucceeds(getDoc(doc(db(BOOKER), 'companies/an-agency')));
    await assertFails(getDoc(doc(db(BOOKER), 'companies/other-co')));
  });
  test('an admin cannot change their plan, modules or status', async () => {
    await assertSucceeds(updateDoc(doc(db(ADMIN), 'companies/an-agency'), { name: 'A.N Agency Pvt' }));
    await assertFails(updateDoc(doc(db(ADMIN), 'companies/an-agency'), { modules: { crm: true } }));
    await assertFails(updateDoc(doc(db(OWNER), 'companies/an-agency'), { status: 'active', limits: {} }));
  });
  test('the company cannot be created again', async () => {
    await assertFails(setDoc(doc(db(OWNER, 'admin@gmail.com'), 'companies/an-agency'),
      { name: 'x', status: 'active', ownerUid: OWNER }));
  });
});
