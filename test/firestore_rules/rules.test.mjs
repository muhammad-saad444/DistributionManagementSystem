// Tests for ../../firestore.rules against the local Firestore emulator (no real data).
// Run from this folder:  npm install  then  npm test   (needs Java 21+)
//
// Two companies (an-agency and xyz) prove that neither can reach the other's data, people or
// settings, and that only the super admin sees across companies.
import { after, before, beforeEach, describe, test } from 'node:test';
import { readFileSync } from 'node:fs';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  collection, deleteDoc, doc, getDoc, getDocs, query, setDoc, updateDoc, where, writeBatch,
} from 'firebase/firestore';

let env;
const SUPER = 'super1';
const A_OWNER = 'aOwner', A_ADMIN = 'aAdmin', A_BOOKER = 'aBooker', A_OFF = 'aOff';
const X_OWNER = 'xOwner', X_BOOKER = 'xBooker';
const PENDING = 'pending1';

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-rules',
    firestore: { rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8') },
  });
});
after(() => env.cleanup());
beforeEach(() => env.clearFirestore());

const db = (uid, email) => env.authenticatedContext(uid, { email: email ?? `${uid.toLowerCase()}@test.com` }).firestore();
const allModules = { crm: true, purchases: true, khata: true, dsr: true, loadsheet: true };

/// Two separated companies. [legacy]: an-agency's data still in the shared collections.
async function seed({ legacy = false, xModules = allModules } = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    await setDoc(doc(d, `platform_admins/${SUPER}`), { email: 'depotos@gmail.com' });
    await setDoc(doc(d, 'companies/an-agency'), { name: 'A.N Agency', status: 'active', ownerUid: A_OWNER, modules: allModules, legacyData: legacy });
    await setDoc(doc(d, 'companies/xyz'), { name: 'XYZ', status: 'active', modules: xModules, legacyData: false });
    const u = (companyId, role, status = 'active') => ({ companyId, role, status, name: '', email: '' });
    await setDoc(doc(d, `users/${A_OWNER}`), u('an-agency', 'owner'));
    await setDoc(doc(d, `users/${A_ADMIN}`), u('an-agency', 'admin'));
    await setDoc(doc(d, `users/${A_BOOKER}`), u('an-agency', 'booker'));
    await setDoc(doc(d, `users/${A_OFF}`), u('an-agency', 'booker', 'disabled'));
    await setDoc(doc(d, `users/${X_OWNER}`), u('xyz', 'owner'));
    await setDoc(doc(d, `users/${X_BOOKER}`), u('xyz', 'booker'));
    await setDoc(doc(d, `users/${PENDING}`), u(null, 'booker', 'pending'));
    await setDoc(doc(d, 'companies/an-agency/invoices/a1'), { total: 100 });
    await setDoc(doc(d, 'companies/xyz/invoices/x1'), { total: 200 });
    await setDoc(doc(d, 'companies/xyz/crm_visits/v1'), { note: 'x' });
    await setDoc(doc(d, 'companies/xyz/sessions/xBooker'), { uid: X_BOOKER });
    await setDoc(doc(d, 'invoices/old1'), { total: 1 }); // the shared (legacy) collection
  });
}

// ------------------------------------------------------------------ data separation
describe('each company only reaches its own data', () => {
  beforeEach(() => seed());

  test('a booker reads and writes their own company', async () => {
    await assertSucceeds(getDoc(doc(db(A_BOOKER), 'companies/an-agency/invoices/a1')));
    await assertSucceeds(setDoc(doc(db(A_BOOKER), 'companies/an-agency/invoices/a2'), { total: 5 }));
  });
  test("a booker cannot read another company's data", async () => {
    await assertFails(getDoc(doc(db(A_BOOKER), 'companies/xyz/invoices/x1')));
    await assertFails(getDocs(collection(db(A_BOOKER), 'companies/xyz/invoices')));
  });
  test("a company admin cannot read or write another company's data", async () => {
    await assertFails(getDoc(doc(db(A_OWNER), 'companies/xyz/invoices/x1')));
    await assertFails(setDoc(doc(db(A_OWNER), 'companies/xyz/invoices/hack'), { total: 1 }));
    await assertFails(deleteDoc(doc(db(A_OWNER), 'companies/xyz/invoices/x1')));
  });
  test("a company cannot see another company's people or logins", async () => {
    await assertFails(getDocs(query(collection(db(A_OWNER), 'users'), where('companyId', '==', 'xyz'))));
    await assertFails(getDoc(doc(db(A_OWNER), `users/${X_BOOKER}`)));
    await assertFails(getDocs(collection(db(A_OWNER), 'companies/xyz/sessions')));
  });
  test("a company cannot read another company's settings", async () => {
    await assertFails(getDoc(doc(db(A_OWNER), 'companies/xyz')));
  });
  test('switched-off people and people with no company reach nothing', async () => {
    await assertFails(getDoc(doc(db(A_OFF), 'companies/an-agency/invoices/a1')));
    await assertFails(getDoc(doc(db(PENDING), 'companies/an-agency/invoices/a1')));
    await assertFails(getDoc(doc(db('stranger'), 'companies/an-agency/invoices/a1')));
  });
  test('after the move, the old shared copy is only for the super admin', async () => {
    await assertFails(getDoc(doc(db(A_BOOKER), 'invoices/old1')));
    await assertFails(getDoc(doc(db(X_OWNER), 'invoices/old1')));
    await assertSucceeds(getDoc(doc(db(SUPER), 'invoices/old1')));
  });
  test('a suspended company is locked out of its data', async () => {
    await env.withSecurityRulesDisabled((c) => updateDoc(doc(c.firestore(), 'companies/xyz'), { status: 'suspended' }));
    await assertFails(getDoc(doc(db(X_BOOKER), 'companies/xyz/invoices/x1')));
  });
  test('people write only their own login copy', async () => {
    await assertSucceeds(setDoc(doc(db(X_BOOKER), 'companies/xyz/sessions/xBooker'), { uid: X_BOOKER }));
    await assertFails(setDoc(doc(db(X_BOOKER), 'companies/xyz/sessions/xOwner'), { uid: X_BOOKER }));
  });
});

describe('modules', () => {
  beforeEach(() => seed({ xModules: { crm: false, purchases: false, khata: true, dsr: true, loadsheet: true } }));

  test("a company without CRM can't read or write CRM data", async () => {
    await assertFails(getDoc(doc(db(X_BOOKER), 'companies/xyz/crm_visits/v1')));
    await assertFails(setDoc(doc(db(X_OWNER), 'companies/xyz/crm_visits/v2'), { note: 'y' }));
  });
  test("a company without Purchases can't record purchases", async () => {
    await assertFails(setDoc(doc(db(X_OWNER), 'companies/xyz/purchases/p1'), { total: 1 }));
  });
  test('modules it has still work', async () => {
    await assertSucceeds(setDoc(doc(db(X_OWNER), 'companies/xyz/khata_entries/k1'), { amount: 1 }));
    await assertSucceeds(getDoc(doc(db(X_BOOKER), 'companies/xyz/invoices/x1')));
  });
  test('a company admin cannot switch modules on for themselves', async () => {
    await assertFails(updateDoc(doc(db(X_OWNER), 'companies/xyz'), { 'modules.crm': true }));
    await assertFails(updateDoc(doc(db(X_OWNER), 'companies/xyz'), { 'limits.maxBookers': 999 }));
    await assertFails(updateDoc(doc(db(X_OWNER), 'companies/xyz'), { legacyData: true }));
    await env.withSecurityRulesDisabled((c) => updateDoc(doc(c.firestore(), 'companies/xyz'), { status: 'suspended' }));
    await assertFails(updateDoc(doc(db(X_OWNER), 'companies/xyz'), { status: 'active' })); // can't un-suspend itself
    await assertSucceeds(updateDoc(doc(db(X_OWNER), 'companies/xyz'), { name: 'XYZ Traders' }));
  });
});

// ------------------------------------------------------------------ super admin
describe('super admin', () => {
  beforeEach(() => seed());

  test('sees every company and its data', async () => {
    await assertSucceeds(getDocs(collection(db(SUPER), 'companies')));
    await assertSucceeds(getDoc(doc(db(SUPER), 'companies/xyz/invoices/x1')));
    await assertSucceeds(getDoc(doc(db(SUPER), 'companies/an-agency/invoices/a1')));
    await assertSucceeds(getDocs(query(collection(db(SUPER), 'users'), where('companyId', '==', 'xyz'))));
  });
  test('creates companies, sets modules and limits, suspends', async () => {
    await assertSucceeds(setDoc(doc(db(SUPER), 'companies/new-co'), { name: 'New', status: 'active', modules: {}, legacyData: false }));
    await assertSucceeds(updateDoc(doc(db(SUPER), 'companies/xyz'), { 'modules.crm': false, 'limits.maxBookers': 3, status: 'suspended' }));
  });
  test('invites a company owner', async () => {
    await assertSucceeds(setDoc(doc(db(SUPER), 'invites/boss@new.com'), { companyId: 'xyz', role: 'owner' }));
  });
  test('nobody can make themselves super admin', async () => {
    await assertFails(setDoc(doc(db(A_OWNER), `platform_admins/${A_OWNER}`), { email: 'x' }));
    await assertFails(setDoc(doc(db('someone', 'depotos@gmail.com'), 'platform_admins/someone'), { email: 'depotos@gmail.com' }));
  });
  test('company admins cannot list companies', async () => {
    await assertFails(getDocs(collection(db(A_OWNER), 'companies')));
  });
  test('people without a company are visible to the super admin only', async () => {
    await assertSucceeds(getDocs(query(collection(db(SUPER), 'users'), where('status', '==', 'pending'), where('companyId', '==', null))));
    await assertFails(getDocs(query(collection(db(A_OWNER), 'users'), where('status', '==', 'pending'), where('companyId', '==', null))));
  });
});

// ------------------------------------------------------------------ invitations
describe('invitations', () => {
  beforeEach(() => seed());

  test('a company admin invites into their own company as admin or booker', async () => {
    await assertSucceeds(setDoc(doc(db(X_OWNER), 'invites/new@x.com'), { companyId: 'xyz', role: 'booker' }));
  });
  test('a company admin cannot invite into another company, or as owner', async () => {
    await assertFails(setDoc(doc(db(X_OWNER), 'invites/new@x.com'), { companyId: 'an-agency', role: 'booker' }));
    await assertFails(setDoc(doc(db(X_OWNER), 'invites/new@x.com'), { companyId: 'xyz', role: 'owner' }));
  });
  test('a booker cannot invite anyone', async () => {
    await assertFails(setDoc(doc(db(X_BOOKER), 'invites/new@x.com'), { companyId: 'xyz', role: 'booker' }));
  });
  test("a company cannot see another company's invitations", async () => {
    await env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), 'invites/hire@a.com'), { companyId: 'an-agency', role: 'booker' }));
    await assertFails(getDoc(doc(db(X_OWNER), 'invites/hire@a.com')));
    await assertFails(getDocs(query(collection(db(X_OWNER), 'invites'), where('companyId', '==', 'an-agency'))));
    await assertSucceeds(getDocs(query(collection(db(A_OWNER), 'invites'), where('companyId', '==', 'an-agency'))));
  });
  test('the invited person joins with exactly the invited company and role', async () => {
    await env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), 'invites/new@x.com'), { companyId: 'xyz', role: 'booker' }));
    const d = db('newbie', 'new@x.com');
    const b = writeBatch(d);
    b.set(doc(d, 'users/newbie'), { companyId: 'xyz', role: 'booker', status: 'active', name: 'N', email: 'new@x.com' });
    b.delete(doc(d, 'invites/new@x.com'));
    await assertSucceeds(b.commit());
  });
  test('the invited person cannot upgrade their role or pick another company', async () => {
    await env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), 'invites/new@x.com'), { companyId: 'xyz', role: 'booker' }));
    await assertFails(setDoc(doc(db('newbie', 'new@x.com'), 'users/newbie'), { companyId: 'xyz', role: 'admin', status: 'active' }));
    await assertFails(setDoc(doc(db('newbie', 'new@x.com'), 'users/newbie'), { companyId: 'an-agency', role: 'booker', status: 'active' }));
  });
  test("someone else cannot use another person's invitation", async () => {
    await env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), 'invites/new@x.com'), { companyId: 'xyz', role: 'booker' }));
    await assertFails(setDoc(doc(db('thief', 'thief@x.com'), 'users/thief'), { companyId: 'xyz', role: 'booker', status: 'active' }));
  });
  test('a pending sign-up joins when invited', async () => {
    await env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), 'invites/pending1@test.com'), { companyId: 'xyz', role: 'booker' }));
    await assertSucceeds(setDoc(doc(db(PENDING), `users/${PENDING}`), { companyId: 'xyz', role: 'booker', status: 'active', name: '', email: '' }));
  });
  test('without an invitation, a new sign-up can only wait with no company', async () => {
    await assertSucceeds(setDoc(doc(db('fresh'), 'users/fresh'), { companyId: null, role: 'booker', status: 'pending' }));
    await assertFails(setDoc(doc(db('fresh2'), 'users/fresh2'), { companyId: 'xyz', role: 'booker', status: 'active' }));
  });
});

// ------------------------------------------------------------------ people within a company
describe('roles inside a company', () => {
  beforeEach(() => seed());

  test('a booker cannot make themselves admin or move company', async () => {
    await assertFails(updateDoc(doc(db(A_BOOKER), `users/${A_BOOKER}`), { role: 'admin' }));
    await assertFails(updateDoc(doc(db(A_BOOKER), `users/${A_BOOKER}`), { companyId: 'xyz' }));
    await assertSucceeds(updateDoc(doc(db(A_BOOKER), `users/${A_BOOKER}`), { name: 'Ali' }));
  });
  test('a switched-off booker cannot switch themselves back on', async () => {
    await assertFails(updateDoc(doc(db(A_OFF), `users/${A_OFF}`), { status: 'active' }));
  });
  test("an admin manages their company's people", async () => {
    await assertSucceeds(getDocs(query(collection(db(A_ADMIN), 'users'), where('companyId', '==', 'an-agency'))));
    await assertSucceeds(updateDoc(doc(db(A_ADMIN), `users/${A_BOOKER}`), { role: 'admin' }));
    await assertSucceeds(updateDoc(doc(db(A_OWNER), `users/${A_BOOKER}`), { status: 'disabled' }));
  });
  test('an admin cannot change the owner or themselves', async () => {
    await assertFails(updateDoc(doc(db(A_ADMIN), `users/${A_OWNER}`), { role: 'booker' }));
    await assertFails(updateDoc(doc(db(A_ADMIN), `users/${A_ADMIN}`), { role: 'owner' }));
  });
  test("an admin cannot take someone from another company", async () => {
    await assertFails(updateDoc(doc(db(A_OWNER), `users/${X_BOOKER}`), { companyId: 'an-agency' }));
    await assertFails(updateDoc(doc(db(A_OWNER), `users/${PENDING}`), { companyId: 'an-agency', role: 'booker', status: 'active' }));
  });
  test('bookers cannot read the people list', async () => {
    await assertFails(getDocs(query(collection(db(A_BOOKER), 'users'), where('companyId', '==', 'an-agency'))));
  });
});

// ------------------------------------------------------------------ the original company, before and during the move
describe('the original company before its data is moved', () => {
  test('before setup, anyone signed in uses the shared data as before', async () => {
    await env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), 'invoices/old1'), { total: 1 }));
    await assertSucceeds(getDoc(doc(db('someone'), 'invoices/old1')));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'invoices/old1')));
  });
  test('the original admin sets the company up and becomes owner', async () => {
    const d = db(A_OWNER, 'admin@gmail.com');
    const b = writeBatch(d);
    b.set(doc(d, 'companies/an-agency'), { name: 'A.N Agency', status: 'active', ownerUid: A_OWNER, modules: {}, legacyData: true });
    b.set(doc(d, `users/${A_OWNER}`), { companyId: 'an-agency', role: 'owner', status: 'active', name: 'admin', email: '' });
    await assertSucceeds(b.commit());
  });
  test('any other login cannot create that company', async () => {
    const d = db('intruder', 'x@gmail.com');
    const b = writeBatch(d);
    b.set(doc(d, 'companies/an-agency'), { name: 'A.N Agency', status: 'active', ownerUid: 'intruder', modules: {}, legacyData: true });
    b.set(doc(d, 'users/intruder'), { companyId: 'an-agency', role: 'owner', status: 'active' });
    await assertFails(b.commit());
  });
  test('after setup, until the move: its members use the shared data, other companies do not', async () => {
    await seed({ legacy: true });
    await assertSucceeds(getDoc(doc(db(A_BOOKER), 'invoices/old1')));
    await assertFails(getDoc(doc(db(X_BOOKER), 'invoices/old1')));
    await assertFails(getDoc(doc(db(A_OFF), 'invoices/old1')));
  });
  test('the super admin can copy it into the company', async () => {
    await seed({ legacy: true });
    await assertSucceeds(getDocs(collection(db(SUPER), 'invoices')));
    await assertSucceeds(setDoc(doc(db(SUPER), 'companies/an-agency/invoices/old1'), { total: 1 }));
    await assertSucceeds(updateDoc(doc(db(SUPER), 'companies/an-agency'), { legacyData: false }));
  });
});
