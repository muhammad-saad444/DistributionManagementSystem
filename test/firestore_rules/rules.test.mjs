// Tests for ../../firestore.rules against the local Firestore emulator (no real data).
// Run from this folder:  npm install  then  npm test   (needs Java 21+)
//
// Two companies (an-agency and xyz) prove that neither can reach the other's data, people or
// settings, and that only the super admin sees across companies.
import { after, before, beforeEach, describe, test } from 'node:test';
import { readFileSync } from 'node:fs';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  collection, deleteDoc, doc, getDoc, getDocs, query, setDoc, Timestamp, updateDoc, where, writeBatch,
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
const allModules = { crm: true, purchases: true, khata: true, dsr: true, loadsheet: true, hr: true };

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

// ------------------------------------------------------------------ HR
describe('HR keeps salaries private', () => {
  const A = 'companies/an-agency';
  beforeEach(async () => {
    await seed();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const d = ctx.firestore();
      await setDoc(doc(d, `${A}/employees/e1`), { name: 'Booker', basic: 40000, userUid: A_BOOKER });
      await setDoc(doc(d, `${A}/employees/e2`), { name: 'Driver', basic: 35000, userUid: '' });
      await setDoc(doc(d, `${A}/hr_links/${A_BOOKER}`), { employeeId: 'e1', active: true });
      await setDoc(doc(d, `${A}/payslips/2026-11_e1`), { userUid: A_BOOKER, net: 40000 });
      await setDoc(doc(d, `${A}/payslips/2026-11_e2`), { userUid: '', net: 35000 });
      await setDoc(doc(d, `${A}/attendance/e2_2026-11-05`), { employeeId: 'e2', userUid: '', status: 'present', markedBy: 'admin' });
      await setDoc(doc(d, `${A}/attendance/e1_2026-11-04`), { employeeId: 'e1', userUid: A_BOOKER, status: 'absent', markedBy: 'admin' });
      await setDoc(doc(d, `${A}/leave_requests/l1`), { employeeId: 'e1', userUid: A_BOOKER, status: 'pending' });
      await setDoc(doc(d, `${A}/leave_requests/l2`), { employeeId: 'e2', userUid: '', status: 'pending' });
    });
  });

  test('admins manage staff, salaries, advances and payroll', async () => {
    await assertSucceeds(getDocs(collection(db(A_ADMIN), `${A}/employees`)));
    await assertSucceeds(setDoc(doc(db(A_ADMIN), `${A}/advances/adv1`), { employeeId: 'e2', amount: 5000 }));
    await assertSucceeds(setDoc(doc(db(A_OWNER), `${A}/payroll/2026-11`), { status: 'draft', lines: [] }));
  });
  test('a booker cannot see salaries, other people or payroll', async () => {
    await assertFails(getDoc(doc(db(A_BOOKER), `${A}/employees/e1`)));
    await assertFails(getDocs(collection(db(A_BOOKER), `${A}/employees`)));
    await assertFails(getDoc(doc(db(A_BOOKER), `${A}/payroll/2026-11`)));
    await assertFails(getDocs(collection(db(A_BOOKER), `${A}/advances`)));
    await assertFails(getDoc(doc(db(A_BOOKER), `${A}/payslips/2026-11_e2`)));
  });
  test('a booker reads their own link and payslips', async () => {
    await assertSucceeds(getDoc(doc(db(A_BOOKER), `${A}/hr_links/${A_BOOKER}`)));
    await assertSucceeds(getDoc(doc(db(A_BOOKER), `${A}/payslips/2026-11_e1`)));
    await assertSucceeds(getDocs(query(collection(db(A_BOOKER), `${A}/payslips`), where('userUid', '==', A_BOOKER))));
    await assertFails(getDocs(collection(db(A_BOOKER), `${A}/payslips`)));
  });
  test('a booker checks in for themselves only, and cannot overwrite an admin mark', async () => {
    const b = db(A_BOOKER);
    await assertSucceeds(setDoc(doc(b, `${A}/attendance/e1_2026-11-05`),
      { employeeId: 'e1', userUid: A_BOOKER, status: 'late', markedBy: 'self' }));
    await assertSucceeds(updateDoc(doc(b, `${A}/attendance/e1_2026-11-05`), { checkOut: 1 }));
    await assertFails(setDoc(doc(b, `${A}/attendance/e1_2026-11-06`),
      { employeeId: 'e1', userUid: A_BOOKER, status: 'leave', markedBy: 'self' }));
    await assertFails(setDoc(doc(b, `${A}/attendance/e2_2026-11-06`),
      { employeeId: 'e2', userUid: '', status: 'present', markedBy: 'self' }));
    await assertFails(setDoc(doc(b, `${A}/attendance/e1_2026-11-04`),
      { employeeId: 'e1', userUid: A_BOOKER, status: 'present', markedBy: 'self' }));
    await assertFails(getDoc(doc(b, `${A}/attendance/e2_2026-11-05`)));
    await assertSucceeds(getDoc(doc(b, `${A}/attendance/e1_2026-12-01`))); // a day not marked yet
  });
  test('a booker applies for and cancels their own leave, but cannot approve it', async () => {
    const b = db(A_BOOKER);
    await assertSucceeds(setDoc(doc(b, `${A}/leave_requests/l3`), { employeeId: 'e1', userUid: A_BOOKER, status: 'pending' }));
    await assertFails(setDoc(doc(b, `${A}/leave_requests/l4`), { employeeId: 'e1', userUid: A_BOOKER, status: 'approved' }));
    await assertFails(updateDoc(doc(b, `${A}/leave_requests/l1`), { status: 'approved' }));
    await assertSucceeds(updateDoc(doc(b, `${A}/leave_requests/l1`), { status: 'cancelled' }));
    await assertFails(updateDoc(doc(b, `${A}/leave_requests/l2`), { status: 'cancelled' }));
    await assertSucceeds(updateDoc(doc(db(A_ADMIN), `${A}/leave_requests/l2`), { status: 'approved' }));
  });
  test('another company and companies without HR are kept out', async () => {
    await assertFails(getDocs(collection(db(X_OWNER), `${A}/employees`)));
    await env.withSecurityRulesDisabled((ctx) =>
      updateDoc(doc(ctx.firestore(), 'companies/an-agency'), { 'modules.hr': false }));
    await assertFails(getDocs(collection(db(A_ADMIN), `${A}/employees`)));
    await assertFails(getDoc(doc(db(A_BOOKER), `${A}/hr_links/${A_BOOKER}`)));
  });
  test('the original company: HR in the shared copy is also admin only', async () => {
    await seed({ legacy: true });
    await assertSucceeds(setDoc(doc(db(A_ADMIN), 'employees/e9'), { name: 'x', basic: 1 }));
    await assertFails(getDoc(doc(db(A_BOOKER), 'employees/e9')));
    await assertFails(getDoc(doc(db(X_OWNER), 'employees/e9')));
  });
});

// ------------------------------------------------------------------ orders
describe('purchase and sales orders', () => {
  const A = 'companies/an-agency';
  beforeEach(async () => {
    await seed({ xModules: { ...allModules, purchases: false } });
    await env.withSecurityRulesDisabled(async (ctx) => {
      const d = ctx.firestore();
      await setDoc(doc(d, `${A}/sales_orders/s1`), { userId: A_BOOKER, status: 'pending', customer: 'Shop' });
      await setDoc(doc(d, `${A}/sales_orders/s2`), { userId: 'someoneElse', status: 'pending', customer: 'Shop 2' });
    });
  });

  test('purchase orders follow the Purchases module', async () => {
    await assertSucceeds(setDoc(doc(db(A_ADMIN), `${A}/purchase_orders/p1`), { number: 'PO-0001', status: 'open' }));
    await assertFails(setDoc(doc(db(X_OWNER), 'companies/xyz/purchase_orders/p1'), { number: 'PO-0001' }));
    await assertFails(getDoc(doc(db(X_OWNER), `${A}/purchase_orders/p1`)));
  });
  test('a booker places their own pending order and can cancel it', async () => {
    const b = db(A_BOOKER);
    await assertSucceeds(setDoc(doc(b, `${A}/sales_orders/s3`), { userId: A_BOOKER, status: 'pending' }));
    await assertFails(setDoc(doc(b, `${A}/sales_orders/s4`), { userId: A_BOOKER, status: 'invoiced' }));
    await assertFails(setDoc(doc(b, `${A}/sales_orders/s5`), { userId: 'someoneElse', status: 'pending' }));
    await assertSucceeds(updateDoc(doc(b, `${A}/sales_orders/s1`), { status: 'cancelled' }));
    await assertFails(updateDoc(doc(b, `${A}/sales_orders/s2`), { status: 'cancelled' }));
  });
  test('only admins approve or reject orders', async () => {
    await assertFails(updateDoc(doc(db(A_BOOKER), `${A}/sales_orders/s1`), { status: 'invoiced' }));
    await assertSucceeds(updateDoc(doc(db(A_ADMIN), `${A}/sales_orders/s1`), { status: 'invoiced', invoiceId: 'i1' }));
    await assertSucceeds(updateDoc(doc(db(A_OWNER), `${A}/sales_orders/s2`), { status: 'rejected' }));
  });
  test('another company cannot see the orders', async () => {
    await assertFails(getDoc(doc(db(X_OWNER), `${A}/sales_orders/s1`)));
    await assertFails(getDocs(collection(db(X_BOOKER), `${A}/sales_orders`)));
  });
});

// ------------------------------------------------------------------ expenses
describe('expenses', () => {
  beforeEach(() => seed());
  const A = 'companies/an-agency';

  test('admins record and read their company expenses', async () => {
    await assertSucceeds(setDoc(doc(db(A_ADMIN), `${A}/expenses/e1`), { category: 'Fuel', amount: 2000 }));
    await assertSucceeds(getDoc(doc(db(A_OWNER), `${A}/expenses/e1`)));
    await assertSucceeds(getDocs(collection(db(A_OWNER), `${A}/expenses`)));
    await assertSucceeds(deleteDoc(doc(db(A_OWNER), `${A}/expenses/e1`)));
  });

  test('bookers cannot see or add expenses', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), `${A}/expenses/e1`), { amount: 1 }));
    await assertFails(getDoc(doc(db(A_BOOKER), `${A}/expenses/e1`)));
    await assertFails(getDocs(collection(db(A_BOOKER), `${A}/expenses`)));
    await assertFails(setDoc(doc(db(A_BOOKER), `${A}/expenses/e2`), { amount: 5 }));
  });

  test("another company's admin cannot reach them", async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), `${A}/expenses/e1`), { amount: 1 }));
    await assertFails(getDoc(doc(db(X_OWNER), `${A}/expenses/e1`)));
    await assertFails(setDoc(doc(db(X_OWNER), `${A}/expenses/e2`), { amount: 5 }));
  });
});

// ------------------------------------------------------------------ cash book entries
describe('cash book entries', () => {
  beforeEach(() => seed());
  const A = 'companies/an-agency';

  test('admins add and read opening balances and transfers', async () => {
    await assertSucceeds(setDoc(doc(db(A_ADMIN), `${A}/cash_entries/c1`), { type: 'opening', account: 'cash', amount: 5000 }));
    await assertSucceeds(getDocs(collection(db(A_OWNER), `${A}/cash_entries`)));
  });

  test('bookers and other companies cannot', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), `${A}/cash_entries/c1`), { amount: 1 }));
    await assertFails(getDoc(doc(db(A_BOOKER), `${A}/cash_entries/c1`)));
    await assertFails(setDoc(doc(db(A_BOOKER), `${A}/cash_entries/c2`), { amount: 5 }));
    await assertFails(getDoc(doc(db(X_OWNER), `${A}/cash_entries/c1`)));
  });
});

// ------------------------------------------------------------------ market returns
describe('returns', () => {
  beforeEach(() => seed());

  test('only the office records returns', async () => {
    await assertSucceeds(setDoc(doc(db(A_ADMIN), 'companies/an-agency/returns/r1'), { invoiceId: 'a1', refund: 100 }));
    await assertSucceeds(getDocs(collection(db(A_OWNER), 'companies/an-agency/returns')));
    await assertFails(setDoc(doc(db(A_BOOKER), 'companies/an-agency/returns/r2'), { invoiceId: 'a1', refund: 100 }));
    await assertFails(getDocs(collection(db(A_BOOKER), 'companies/an-agency/returns')));
    await assertFails(setDoc(doc(db(X_OWNER), 'companies/an-agency/returns/r3'), { refund: 1 }));
  });
});

// ------------------------------------------------------------------ targets
describe('targets', () => {
  beforeEach(() => seed());
  const A = 'companies/an-agency';

  test('the office sets targets and sees them all', async () => {
    await assertSucceeds(setDoc(doc(db(A_ADMIN), `${A}/targets/2026-11__${A_BOOKER}`), { month: '2026-11', userId: A_BOOKER, sales: 1000 }));
    await assertSucceeds(getDocs(query(collection(db(A_OWNER), `${A}/targets`), where('month', '==', '2026-11'))));
  });

  test("a booker reads their own target, not someone else's, and can't change it", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const d = ctx.firestore(); // one connection: settings can only be set once
      await setDoc(doc(d, `${A}/targets/2026-11__${A_BOOKER}`), { month: '2026-11', userId: A_BOOKER, sales: 1000 });
      await setDoc(doc(d, `${A}/targets/2026-11__other`), { month: '2026-11', userId: 'other', sales: 5 });
    });
    const b = db(A_BOOKER);
    await assertSucceeds(getDoc(doc(b, `${A}/targets/2026-11__${A_BOOKER}`)));
    await assertSucceeds(getDoc(doc(b, `${A}/targets/2026-12__${A_BOOKER}`))); // none set yet
    await assertFails(getDoc(doc(b, `${A}/targets/2026-11__other`)));
    await assertFails(setDoc(doc(b, `${A}/targets/2026-11__${A_BOOKER}`), { month: '2026-11', userId: A_BOOKER, sales: 1 }));
    await assertFails(getDoc(doc(db(X_OWNER), `${A}/targets/2026-11__${A_BOOKER}`)));
  });
});

// ------------------------------------------------------------------ delivery trips
describe('delivery trips', () => {
  beforeEach(() => seed());
  const A = 'companies/an-agency';

  test('the office makes and reads trips; bookers and other companies cannot', async () => {
    await assertSucceeds(setDoc(doc(db(A_ADMIN), `${A}/dispatches/t1`), { number: '1', invoiceIds: ['a1'], status: 'loading' }));
    await assertSucceeds(getDocs(collection(db(A_OWNER), `${A}/dispatches`)));
    await assertFails(getDocs(collection(db(A_BOOKER), `${A}/dispatches`)));
    await assertFails(setDoc(doc(db(A_BOOKER), `${A}/dispatches/t2`), { number: '2' }));
    await assertFails(getDoc(doc(db(X_OWNER), `${A}/dispatches/t1`)));
  });
});

// ------------------------------------------------------------------ closed books and the audit log
describe('closed books', () => {
  const A = 'companies/an-agency';
  const ts = (y, m, d) => Timestamp.fromDate(new Date(y, m - 1, d));
  beforeEach(async () => {
    await seed();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const d = ctx.firestore(); // one connection: settings can only be set once
      await updateDoc(doc(d, A), { booksClosedUntil: Timestamp.fromDate(new Date(2026, 9, 31, 23, 59, 59)) }); // 31 Oct
      await setDoc(doc(d, `${A}/invoices/oct`), { total: 100, salesDateTs: ts(2026, 10, 20) });
      await setDoc(doc(d, `${A}/invoices/nov`), { total: 100, salesDateTs: ts(2026, 11, 5) });
      await setDoc(doc(d, `${A}/khata_entries/oct`), { amount: 50, date: ts(2026, 10, 20) });
      await setDoc(doc(d, `${A}/expenses/oct`), { amount: 50, date: ts(2026, 10, 20) });
    });
  });

  test('nothing dated in the closed books can be changed, added or deleted', async () => {
    const a = db(A_ADMIN);
    await assertFails(updateDoc(doc(a, `${A}/invoices/oct`), { total: 1 }));
    await assertFails(deleteDoc(doc(a, `${A}/invoices/oct`)));
    await assertFails(setDoc(doc(db(A_BOOKER), `${A}/invoices/back`), { total: 5, salesDateTs: ts(2026, 10, 31) }));
    await assertFails(deleteDoc(doc(a, `${A}/khata_entries/oct`)));
    await assertFails(setDoc(doc(a, `${A}/khata_entries/k2`), { amount: 5, date: ts(2026, 10, 1) }));
    await assertFails(updateDoc(doc(a, `${A}/expenses/oct`), { amount: 1 }));
  });

  test('an open invoice cannot be moved into the closed books', async () => {
    await assertFails(updateDoc(doc(db(A_ADMIN), `${A}/invoices/nov`), { salesDateTs: ts(2026, 10, 30) }));
  });

  test('after the closing day everything works as before', async () => {
    const a = db(A_ADMIN);
    await assertSucceeds(updateDoc(doc(a, `${A}/invoices/nov`), { total: 90 }));
    await assertSucceeds(setDoc(doc(db(A_BOOKER), `${A}/invoices/n2`), { total: 5, salesDateTs: ts(2026, 11, 1) }));
    await assertSucceeds(setDoc(doc(a, `${A}/khata_entries/k3`), { amount: 5, date: ts(2026, 11, 1) }));
    await assertSucceeds(setDoc(doc(a, `${A}/expenses/e2`), { amount: 5, date: ts(2026, 11, 1) }));
    await assertSucceeds(deleteDoc(doc(a, `${A}/invoices/a1`))); // no date: not held back
  });

  test('only an admin closes or reopens the books', async () => {
    await assertFails(updateDoc(doc(db(A_BOOKER), A), { booksClosedUntil: null }));
    await assertFails(updateDoc(doc(db(X_OWNER), A), { booksClosedUntil: null }));
    await assertSucceeds(updateDoc(doc(db(A_ADMIN), A), { booksClosedUntil: ts(2026, 9, 30) }));
    await assertSucceeds(updateDoc(doc(db(A_ADMIN), `${A}/invoices/oct`), { total: 1 })); // October open again
  });

  test('the super admin can still correct a closed record', async () => {
    await assertSucceeds(updateDoc(doc(db(SUPER), `${A}/invoices/oct`), { total: 1 }));
  });
});

describe('audit log', () => {
  const A = 'companies/an-agency';
  beforeEach(() => seed());

  test('anyone in the company adds to it as themselves; only admins read it', async () => {
    await assertSucceeds(setDoc(doc(db(A_BOOKER), `${A}/audit_log/l1`), { by: A_BOOKER, action: 'delete' }));
    await assertFails(setDoc(doc(db(A_BOOKER), `${A}/audit_log/l2`), { by: A_ADMIN, action: 'delete' }));
    await assertFails(getDocs(collection(db(A_BOOKER), `${A}/audit_log`)));
    await assertSucceeds(getDocs(collection(db(A_ADMIN), `${A}/audit_log`)));
    await assertFails(setDoc(doc(db(X_OWNER), `${A}/audit_log/l3`), { by: X_OWNER }));
  });

  test('nobody changes or deletes it, not even the owner', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `${A}/audit_log/l1`), { by: A_BOOKER, action: 'delete' });
    });
    await assertFails(updateDoc(doc(db(A_OWNER), `${A}/audit_log/l1`), { action: 'edit' }));
    await assertFails(deleteDoc(doc(db(A_OWNER), `${A}/audit_log/l1`)));
  });
});

describe('company details and sales tax', () => {
  const A = 'companies/an-agency';
  beforeEach(() => seed());

  test('an admin saves them; a booker reads but cannot change them; another company cannot', async () => {
    const profile = { legalName: 'A.N Agency (Pvt) Ltd', ntn: '1234567-8', taxEnabled: true, taxRate: 18, taxInclusive: true };
    await assertSucceeds(updateDoc(doc(db(A_ADMIN), A), { profile }));
    await assertSucceeds(getDoc(doc(db(A_BOOKER), A)));
    await assertFails(updateDoc(doc(db(A_BOOKER), A), { profile: { ...profile, taxEnabled: false } }));
    await assertFails(updateDoc(doc(db(X_OWNER), A), { profile }));
    await assertFails(updateDoc(doc(db(A_ADMIN), A), { profile, modules: {} })); // modules stay the super admin's
  });
});

describe('cheques', () => {
  const A = 'companies/an-agency';
  beforeEach(() => seed());

  test('a booker records their own cheque as in hand and reads only their own', async () => {
    const b = db(A_BOOKER);
    await assertSucceeds(setDoc(doc(b, `${A}/cheques/c1`), { userId: A_BOOKER, customer: 'Shop', amount: 500, status: 'inHand' }));
    await assertFails(setDoc(doc(b, `${A}/cheques/c2`), { userId: A_BOOKER, amount: 500, status: 'cleared' }));
    await assertFails(setDoc(doc(b, `${A}/cheques/c3`), { userId: 'someoneElse', amount: 500, status: 'inHand' }));
    await assertSucceeds(getDocs(query(collection(b, `${A}/cheques`), where('userId', '==', A_BOOKER))));
    await assertFails(getDocs(collection(b, `${A}/cheques`)));
  });

  test('only the office deposits, clears or bounces them', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `${A}/cheques/c1`), { userId: A_BOOKER, amount: 500, status: 'inHand' });
    });
    await assertFails(updateDoc(doc(db(A_BOOKER), `${A}/cheques/c1`), { status: 'cleared' }));
    await assertFails(deleteDoc(doc(db(A_BOOKER), `${A}/cheques/c1`)));
    await assertSucceeds(updateDoc(doc(db(A_ADMIN), `${A}/cheques/c1`), { status: 'deposited' }));
    await assertFails(getDoc(doc(db(X_OWNER), `${A}/cheques/c1`)));
  });
});

describe('what each admin may open', () => {
  const A = 'companies/an-agency';
  const LIMITED = 'aSalesOnly';
  beforeEach(async () => {
    await seed();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const d = ctx.firestore(); // one connection: settings can only be set once
      await setDoc(doc(d, `users/${LIMITED}`), { companyId: 'an-agency', role: 'admin', status: 'active', name: '', email: '', sections: ['sales'] });
      await setDoc(doc(d, `${A}/expenses/e1`), { amount: 5, date: Timestamp.fromDate(new Date(2026, 10, 5)) });
      await setDoc(doc(d, `${A}/dispatches/t1`), { number: '1' });
      await setDoc(doc(d, `${A}/employees/emp1`), { name: 'x' });
    });
  });

  test('a sales-only admin reaches sales records but not money or staff', async () => {
    const s = db(LIMITED);
    await assertSucceeds(getDoc(doc(s, `${A}/dispatches/t1`)));
    await assertFails(getDoc(doc(s, `${A}/expenses/e1`)));
    await assertFails(getDocs(collection(s, `${A}/cash_entries`)));
    await assertFails(getDocs(collection(s, `${A}/audit_log`)));
    await assertFails(getDoc(doc(s, `${A}/employees/emp1`)));
    await assertFails(updateDoc(doc(s, A), { booksClosedUntil: null }));
    await assertSucceeds(updateDoc(doc(s, A), { name: 'A.N Agency' }));
  });

  test('a sales-only admin cannot manage users', async () => {
    await assertFails(updateDoc(doc(db(LIMITED), `users/${A_BOOKER}`), { status: 'disabled' }));
  });

  test('the owner or a full admin chooses what an admin may open; a limited admin cannot', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/other'), { companyId: 'an-agency', role: 'admin', status: 'active', name: '', email: '' });
    });
    await assertSucceeds(updateDoc(doc(db(A_ADMIN), 'users/other'), { sections: ['stock'] }));
    await assertFails(updateDoc(doc(db(LIMITED), 'users/other'), { sections: ['stock', 'team'] }));
    await assertFails(updateDoc(doc(db(LIMITED), `users/${LIMITED}`), { sections: ['sales', 'accounts'] }));
    await assertSucceeds(updateDoc(doc(db(A_OWNER), `users/${LIMITED}`), { sections: ['sales', 'accounts'] }));
    await assertSucceeds(getDoc(doc(db(LIMITED), `${A}/expenses/e1`)));
  });

  test('an admin without a list still reaches everything', async () => {
    await assertSucceeds(getDoc(doc(db(A_ADMIN), `${A}/expenses/e1`)));
    await assertSucceeds(getDoc(doc(db(A_ADMIN), `${A}/employees/emp1`)));
  });
});
