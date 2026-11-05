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
    await assertSucceeds(setDoc(doc(db(A_OWNER), 'companies/an-agency/quotations/q1'), { lines: [] }));
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
    await assertFails(setDoc(doc(db(X_OWNER), 'companies/xyz/quotations/q1'), { lines: [] }));
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
  test('nobody can make themselves super admin', async () => {
    await assertFails(setDoc(doc(db(A_OWNER), `platform_admins/${A_OWNER}`), { email: 'x' }));
    await assertFails(setDoc(doc(db('someone', 'depotos@gmail.com'), 'platform_admins/someone'), { email: 'depotos@gmail.com' }));
  });
  test('company admins cannot list companies', async () => {
    await assertFails(getDocs(collection(db(A_OWNER), 'companies')));
  });
});

// ------------------------------------------------------------------ creating accounts
describe('creating accounts', () => {
  beforeEach(() => seed());

  test("a company admin creates a booker or admin in their own company", async () => {
    await assertSucceeds(setDoc(doc(db(X_OWNER), 'users/newBooker'), { companyId: 'xyz', role: 'booker', status: 'active', name: 'Ali', email: 'ali@x.com' }));
    await assertSucceeds(setDoc(doc(db(X_OWNER), 'users/newAdmin'), { companyId: 'xyz', role: 'admin', status: 'active', name: 'Sara', email: 's@x.com' }));
  });
  test('a company admin cannot create accounts in another company, or owners', async () => {
    await assertFails(setDoc(doc(db(X_OWNER), 'users/spy'), { companyId: 'an-agency', role: 'booker', status: 'active' }));
    await assertFails(setDoc(doc(db(X_OWNER), 'users/boss'), { companyId: 'xyz', role: 'owner', status: 'active' }));
  });
  test('a booker cannot create accounts', async () => {
    await assertFails(setDoc(doc(db(X_BOOKER), 'users/friend'), { companyId: 'xyz', role: 'booker', status: 'active' }));
  });
  test('nobody can give themselves an account', async () => {
    await assertFails(setDoc(doc(db('fresh'), 'users/fresh'), { companyId: null, role: 'booker', status: 'pending' }));
    await assertFails(setDoc(doc(db('fresh'), 'users/fresh'), { companyId: 'xyz', role: 'booker', status: 'active' }));
  });
  test("the super admin creates a company's owner", async () => {
    const d = db(SUPER);
    const b = writeBatch(d);
    b.set(doc(d, 'users/newOwner'), { companyId: 'xyz', role: 'owner', status: 'active', name: 'Boss', email: 'b@x.com' });
    b.update(doc(d, 'companies/xyz'), { ownerUid: 'newOwner' });
    await assertSucceeds(b.commit());
  });
  test('a company admin cannot hand the company to someone else', async () => {
    await assertFails(updateDoc(doc(db(X_OWNER), 'companies/xyz'), { ownerUid: X_BOOKER }));
  });
  test('invitations are no longer readable or writable by anyone in the app', async () => {
    await assertFails(setDoc(doc(db(SUPER), 'invites/a@b.com'), { companyId: 'xyz', role: 'booker' }));
    await assertFails(getDoc(doc(db(X_OWNER), 'invites/a@b.com')));
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

// ------------------------------------------------------------------ warehouses
describe('warehouses', () => {
  beforeEach(() => seed());

  test("an admin adds a warehouse and assigns a booker's warehouse", async () => {
    await assertSucceeds(setDoc(doc(db(X_OWNER), 'companies/xyz/warehouses/w2'), { name: 'Godown 2', active: true }));
    await assertSucceeds(updateDoc(doc(db(X_OWNER), `users/${X_BOOKER}`), { warehouseId: 'w2' }));
  });
  test('a booker cannot change their own warehouse', async () => {
    await assertFails(updateDoc(doc(db(X_BOOKER), `users/${X_BOOKER}`), { warehouseId: 'w2' }));
  });
  test("a company cannot see or change another company's warehouses", async () => {
    await assertFails(getDocs(collection(db(A_OWNER), 'companies/xyz/warehouses')));
    await assertFails(setDoc(doc(db(A_OWNER), 'companies/xyz/warehouses/w9'), { name: 'x' }));
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
    await assertSucceeds(setDoc(doc(db(A_OWNER), 'quotations/q1'), { lines: [] }));
    await assertFails(setDoc(doc(db(X_OWNER), 'quotations/q2'), { lines: [] }));
  });
  test('the super admin can copy it into the company', async () => {
    await seed({ legacy: true });
    await assertSucceeds(getDocs(collection(db(SUPER), 'invoices')));
    await assertSucceeds(setDoc(doc(db(SUPER), 'companies/an-agency/invoices/old1'), { total: 1 }));
    await assertSucceeds(updateDoc(doc(db(SUPER), 'companies/an-agency'), { legacyData: false }));
  });
});
