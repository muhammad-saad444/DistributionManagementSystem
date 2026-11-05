// HR: staff records, attendance, leave, advances, payroll, booker scorecards and final settlement.
//
// Collections (all in the company's data, all behind the "hr" module):
//   employees        admin only: one per staff member (salary, bank, statutory switches…)
//   hr_links/{uid}   admin writes; a booker reads their own: which employee their login is
//   attendance       {employeeId}_{yyyy-MM-dd}: admins mark anyone, bookers check in/out themselves
//   leave_requests   bookers apply for themselves, admins decide
//   advances         admin only: money given ahead of salary, repaid from payroll
//   payroll/{yyyy-MM} admin only: one salary sheet per month
//   payslips         {yyyy-MM}_{employeeId}: admin writes when a month is finalised; a booker reads their own
//   settings/hr      leave types, working days, late rule, tax slabs, EOBI and social security
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../account/account.dart';

final _db = FirebaseFirestore.instance;

num _asNum(Object? v) => v is num ? v : num.tryParse('${v ?? ''}'.trim()) ?? 0;
DateTime? _asDate(Object? v) => v is Timestamp ? v.toDate() : (v is DateTime ? v : null);
String _s(Map m, String k) => (m[k] ?? '').toString().trim();
String _who() => FirebaseAuth.instance.currentUser?.email ?? '';

final _dayKey = DateFormat('yyyy-MM-dd');
final _monthKey = DateFormat('yyyy-MM');
String dayKey(DateTime d) => _dayKey.format(d);
String monthKey(DateTime d) => _monthKey.format(d);
DateTime monthStart(String key) => DateTime.parse('$key-01');
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Money rounded to whole rupees (payroll is paid in rupees).
num rupees(num v) => v.round();

// =============================================================================
// Settings
// =============================================================================

class LeaveType {
  final String name;
  final num daysPerYear;
  final bool paid;
  const LeaveType(this.name, this.daysPerYear, {this.paid = true});

  Map<String, dynamic> toMap() => {'name': name, 'days': daysPerYear, 'paid': paid};
  factory LeaveType.fromMap(Map m) => LeaveType(_s(m, 'name'), _asNum(m['days']), paid: m['paid'] != false);
}

class TaxSlab {
  final num from; // annual income above this…
  final num fixed; // …pays this…
  final num rate; // …plus this % of the amount above [from]
  const TaxSlab(this.from, this.fixed, this.rate);

  Map<String, dynamic> toMap() => {'from': from, 'fixed': fixed, 'rate': rate};
  factory TaxSlab.fromMap(Map m) => TaxSlab(_asNum(m['from']), _asNum(m['fixed']), _asNum(m['rate']));
}

/// Salaried slabs from the Finance Act 2026-27 (FY from 1 July 2026). Every budget changes them,
/// so they're editable in HR settings.
const defaultTaxSlabs = [
  TaxSlab(600000, 0, 1),
  TaxSlab(1200000, 6000, 11),
  TaxSlab(2200000, 116000, 20),
  TaxSlab(3200000, 316000, 25),
  TaxSlab(4100000, 541000, 29),
  TaxSlab(5600000, 976000, 32),
  TaxSlab(7000000, 1424000, 35),
];

const defaultLeaveTypes = [
  LeaveType('Casual', 10),
  LeaveType('Sick', 8),
  LeaveType('Annual', 14),
  LeaveType('Unpaid', 0, paid: false),
];

class HrSettings {
  final List<LeaveType> leaveTypes;
  final Set<int> weeklyOff; // DateTime.monday … DateTime.sunday
  final String lateAfter; // "HH:mm": checking in after this is late
  final int latesPerDay; // this many lates cost one day's pay (0 = never)
  final List<TaxSlab> taxSlabs;
  final num minimumWage; // EOBI is worked out on this, not the salary
  final num eobiEmployeePct;
  final num eobiEmployerPct;
  final num socialSecurityPct; // employer only (PESSI / SESSI)
  final num socialSecurityCeiling; // wages above this aren't covered (0 = no ceiling)
  final bool encashLeave; // final settlement pays unused annual leave

  const HrSettings({
    this.leaveTypes = defaultLeaveTypes,
    this.weeklyOff = const {DateTime.sunday},
    this.lateAfter = '09:30',
    this.latesPerDay = 3,
    this.taxSlabs = defaultTaxSlabs,
    this.minimumWage = 40000,
    this.eobiEmployeePct = 1,
    this.eobiEmployerPct = 5,
    this.socialSecurityPct = 6,
    this.socialSecurityCeiling = 0,
    this.encashLeave = true,
  });

  factory HrSettings.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const HrSettings();
    const d = HrSettings();
    final leave = m['leaveTypes'];
    final slabs = m['taxSlabs'];
    final off = m['weeklyOff'];
    return HrSettings(
      leaveTypes: leave is List && leave.isNotEmpty
          ? [for (final l in leave) if (l is Map) LeaveType.fromMap(l)]
          : d.leaveTypes,
      weeklyOff: off is List ? {for (final x in off) _asNum(x).toInt()} : d.weeklyOff,
      lateAfter: _s(m, 'lateAfter').isEmpty ? d.lateAfter : _s(m, 'lateAfter'),
      latesPerDay: m['latesPerDay'] == null ? d.latesPerDay : _asNum(m['latesPerDay']).toInt(),
      taxSlabs: slabs is List && slabs.isNotEmpty
          ? ([for (final s in slabs) if (s is Map) TaxSlab.fromMap(s)]..sort((a, b) => a.from.compareTo(b.from)))
          : d.taxSlabs,
      minimumWage: m['minimumWage'] == null ? d.minimumWage : _asNum(m['minimumWage']),
      eobiEmployeePct: m['eobiEmployeePct'] == null ? d.eobiEmployeePct : _asNum(m['eobiEmployeePct']),
      eobiEmployerPct: m['eobiEmployerPct'] == null ? d.eobiEmployerPct : _asNum(m['eobiEmployerPct']),
      socialSecurityPct: m['socialSecurityPct'] == null ? d.socialSecurityPct : _asNum(m['socialSecurityPct']),
      socialSecurityCeiling: _asNum(m['socialSecurityCeiling']),
      encashLeave: m['encashLeave'] != false,
    );
  }

  Map<String, dynamic> toMap() => {
        'leaveTypes': leaveTypes.map((l) => l.toMap()).toList(),
        'weeklyOff': weeklyOff.toList()..sort(),
        'lateAfter': lateAfter,
        'latesPerDay': latesPerDay,
        'taxSlabs': taxSlabs.map((s) => s.toMap()).toList(),
        'minimumWage': minimumWage,
        'eobiEmployeePct': eobiEmployeePct,
        'eobiEmployerPct': eobiEmployerPct,
        'socialSecurityPct': socialSecurityPct,
        'socialSecurityCeiling': socialSecurityCeiling,
        'encashLeave': encashLeave,
      };

  LeaveType? leaveType(String name) => leaveTypes.where((l) => l.name == name).firstOrNull;

  /// Days of the month that are working days.
  List<DateTime> workingDays(String month) {
    final start = monthStart(month);
    final days = DateTime(start.year, start.month + 1, 0).day;
    return [
      for (var i = 1; i <= days; i++)
        if (!weeklyOff.contains(DateTime(start.year, start.month, i).weekday)) DateTime(start.year, start.month, i),
    ];
  }

  /// Yearly income tax on an annual taxable income.
  num annualTax(num income) {
    final slab = taxSlabs.lastWhere((s) => income > s.from, orElse: () => const TaxSlab(-1, 0, 0));
    if (slab.from < 0) return 0;
    return slab.fixed + (income - slab.from) * slab.rate / 100;
  }

  num get eobiEmployee => minimumWage * eobiEmployeePct / 100;
  num get eobiEmployer => minimumWage * eobiEmployerPct / 100;

  bool isLate(DateTime checkIn) {
    final parts = lateAfter.split(':');
    final h = int.tryParse(parts.first) ?? 9;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return checkIn.hour * 60 + checkIn.minute > h * 60 + m;
  }
}

DocumentReference<Map<String, dynamic>> get _settingsRef => companyCol('settings').doc('hr');

Future<HrSettings> loadHrSettings() async => HrSettings.fromMap((await _settingsRef.get()).data());
Future<void> saveHrSettings(HrSettings s) => _settingsRef.set(s.toMap());

// =============================================================================
// Employees
// =============================================================================

const designations = ['Booker', 'Salesman', 'Driver', 'Delivery', 'Warehouse', 'Accounts', 'Office', 'Manager', 'Other'];
const employeeStatuses = ['active', 'resigned', 'terminated'];

class Allowance {
  final String name;
  final num amount;
  const Allowance(this.name, this.amount);
  Map<String, dynamic> toMap() => {'name': name, 'amount': amount};
  factory Allowance.fromMap(Map m) => Allowance(_s(m, 'name'), _asNum(m['amount']));
}

class Employee {
  final String id;
  final String code;
  final String name;
  final String fatherName;
  final String cnic;
  final String phone;
  final String address;
  final String emergencyName;
  final String emergencyPhone;
  final DateTime? joinDate;
  final DateTime? dob;
  final String designation;
  final String department;
  final String salaryType; // monthly | daily
  final num basic; // a month, or a day for daily wagers
  final List<Allowance> allowances;
  final String bankName;
  final String accountTitle;
  final String iban;
  final String userUid; // their app login, for bookers (empty for staff without the app)
  final String userName;
  // Statutory, switched per person.
  final bool eobi;
  final String eobiNo;
  final bool incomeTax;
  final bool socialSecurity;
  // Commission and target (bookers / salesmen).
  final num commissionPct; // % of the month's sales
  final num monthlyTarget; // sales target
  final num targetBonus; // paid when the target is reached
  final String status; // active | resigned | terminated
  final DateTime? leftDate;
  final String notes;
  final Map<String, dynamic>? settlement; // saved final settlement

  const Employee({
    this.id = '',
    this.code = '',
    required this.name,
    this.fatherName = '',
    this.cnic = '',
    this.phone = '',
    this.address = '',
    this.emergencyName = '',
    this.emergencyPhone = '',
    this.joinDate,
    this.dob,
    this.designation = 'Other',
    this.department = '',
    this.salaryType = 'monthly',
    this.basic = 0,
    this.allowances = const [],
    this.bankName = '',
    this.accountTitle = '',
    this.iban = '',
    this.userUid = '',
    this.userName = '',
    this.eobi = false,
    this.eobiNo = '',
    this.incomeTax = false,
    this.socialSecurity = false,
    this.commissionPct = 0,
    this.monthlyTarget = 0,
    this.targetBonus = 0,
    this.status = 'active',
    this.leftDate,
    this.notes = '',
    this.settlement,
  });

  bool get isActive => status == 'active';
  bool get isDaily => salaryType == 'daily';
  num get allowanceTotal => allowances.fold<num>(0, (s, a) => s + a.amount);
  /// A full month's fixed pay (daily wagers: their rate × working days is worked out per month).
  num get monthlyGross => basic + allowanceTotal;
  bool get hasApp => userUid.isNotEmpty;

  factory Employee.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) => Employee.fromMap(doc.id, doc.data() ?? const {});

  factory Employee.fromMap(String id, Map<String, dynamic> m) {
    final allow = m['allowances'];
    return Employee(
      id: id,
      code: _s(m, 'code'),
      name: _s(m, 'name'),
      fatherName: _s(m, 'fatherName'),
      cnic: _s(m, 'cnic'),
      phone: _s(m, 'phone'),
      address: _s(m, 'address'),
      emergencyName: _s(m, 'emergencyName'),
      emergencyPhone: _s(m, 'emergencyPhone'),
      joinDate: _asDate(m['joinDate']),
      dob: _asDate(m['dob']),
      designation: _s(m, 'designation').isEmpty ? 'Other' : _s(m, 'designation'),
      department: _s(m, 'department'),
      salaryType: m['salaryType'] == 'daily' ? 'daily' : 'monthly',
      basic: _asNum(m['basic']),
      allowances: allow is List ? [for (final a in allow) if (a is Map) Allowance.fromMap(a)] : const [],
      bankName: _s(m, 'bankName'),
      accountTitle: _s(m, 'accountTitle'),
      iban: _s(m, 'iban'),
      userUid: _s(m, 'userUid'),
      userName: _s(m, 'userName'),
      eobi: m['eobi'] == true,
      eobiNo: _s(m, 'eobiNo'),
      incomeTax: m['incomeTax'] == true,
      socialSecurity: m['socialSecurity'] == true,
      commissionPct: _asNum(m['commissionPct']),
      monthlyTarget: _asNum(m['monthlyTarget']),
      targetBonus: _asNum(m['targetBonus']),
      status: employeeStatuses.contains(m['status']) ? m['status'] as String : 'active',
      leftDate: _asDate(m['leftDate']),
      notes: _s(m, 'notes'),
      settlement: m['settlement'] is Map ? Map<String, dynamic>.from(m['settlement'] as Map) : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'code': code,
        'name': name,
        'fatherName': fatherName,
        'cnic': cnic,
        'phone': phone,
        'address': address,
        'emergencyName': emergencyName,
        'emergencyPhone': emergencyPhone,
        'joinDate': joinDate == null ? null : Timestamp.fromDate(joinDate!),
        'dob': dob == null ? null : Timestamp.fromDate(dob!),
        'designation': designation,
        'department': department,
        'salaryType': salaryType,
        'basic': basic,
        'allowances': allowances.map((a) => a.toMap()).toList(),
        'bankName': bankName,
        'accountTitle': accountTitle,
        'iban': iban,
        'userUid': userUid,
        'userName': userName,
        'eobi': eobi,
        'eobiNo': eobiNo,
        'incomeTax': incomeTax,
        'socialSecurity': socialSecurity,
        'commissionPct': commissionPct,
        'monthlyTarget': monthlyTarget,
        'targetBonus': targetBonus,
        'status': status,
        'leftDate': leftDate == null ? null : Timestamp.fromDate(leftDate!),
        'notes': notes,
      };
}

Future<List<Employee>> loadEmployees() async {
  final snap = await companyCol('employees').get();
  return snap.docs.map(Employee.fromDoc).where((e) => e.name.isNotEmpty).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

/// Another employee with the same CNIC or app login, or null.
Future<Employee?> findDuplicateEmployee(Employee e) async {
  final all = await loadEmployees();
  String digits(String s) => s.replaceAll(RegExp(r'\D'), '');
  return all.where((x) => x.id != e.id).where((x) {
    if (e.cnic.isNotEmpty && digits(x.cnic) == digits(e.cnic)) return true;
    return e.userUid.isNotEmpty && x.userUid == e.userUid;
  }).firstOrNull;
}

/// Saves an employee and keeps the link from their app login up to date. Returns the id.
Future<String> saveEmployee(Employee e, {Employee? before}) async {
  final batch = _db.batch();
  final ref = e.id.isEmpty ? companyCol('employees').doc() : companyCol('employees').doc(e.id);
  batch.set(
      ref,
      {
        ...e.toMap(),
        if (e.id.isEmpty) 'createdAt': FieldValue.serverTimestamp(),
        if (e.id.isEmpty) 'createdBy': _who(),
      },
      SetOptions(merge: true));
  final oldUid = before?.userUid ?? '';
  if (oldUid.isNotEmpty && oldUid != e.userUid) batch.delete(companyCol('hr_links').doc(oldUid));
  if (e.userUid.isNotEmpty) {
    batch.set(companyCol('hr_links').doc(e.userUid), {
      'employeeId': ref.id,
      'name': e.name,
      'active': e.isActive,
    });
  }
  await batch.commit();
  return ref.id;
}

/// The next free employee code: EMP-001, EMP-002…
String nextEmployeeCode(List<Employee> all) {
  var max = 0;
  for (final e in all) {
    final n = int.tryParse(e.code.replaceAll(RegExp(r'\D'), '')) ?? 0;
    if (n > max) max = n;
  }
  return 'EMP-${(max + 1).toString().padLeft(3, '0')}';
}

/// Which employee the signed-in login is (bookers), or null if HR hasn't linked them.
Future<({String employeeId, String name})?> myEmployeeLink() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  final m = (await companyCol('hr_links').doc(uid).get()).data();
  if (m == null || m['active'] == false) return null;
  return (employeeId: _s(m, 'employeeId'), name: _s(m, 'name'));
}

// =============================================================================
// Attendance
// =============================================================================

const attendanceStatuses = ['present', 'late', 'half', 'absent', 'leave', 'off'];

String attendanceLabel(String s) => switch (s) {
      'present' => 'Present',
      'late' => 'Late',
      'half' => 'Half day',
      'absent' => 'Absent',
      'leave' => 'Leave',
      'off' => 'Off',
      _ => s,
    };

String attendanceLetter(String s) => switch (s) {
      'present' => 'P',
      'late' => 'L',
      'half' => 'H',
      'absent' => 'A',
      'leave' => 'LV',
      'off' => 'O',
      _ => '',
    };

class Attendance {
  final String id;
  final String employeeId;
  final String userUid;
  final String date; // yyyy-MM-dd
  final String status;
  final String leaveType; // for status "leave"
  final bool paidLeave;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final num? inLat, inLng, outLat, outLng;
  final String markedBy; // self | admin
  final String note;

  const Attendance({
    this.id = '',
    required this.employeeId,
    this.userUid = '',
    required this.date,
    required this.status,
    this.leaveType = '',
    this.paidLeave = true,
    this.checkIn,
    this.checkOut,
    this.inLat,
    this.inLng,
    this.outLat,
    this.outLng,
    this.markedBy = 'admin',
    this.note = '',
  });

  static String docId(String employeeId, String date) => '${employeeId}_$date';

  factory Attendance.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    num? n(String k) => m[k] is num ? m[k] as num : null;
    return Attendance(
      id: doc.id,
      employeeId: _s(m, 'employeeId'),
      userUid: _s(m, 'userUid'),
      date: _s(m, 'date'),
      status: attendanceStatuses.contains(m['status']) ? m['status'] as String : 'present',
      leaveType: _s(m, 'leaveType'),
      paidLeave: m['paidLeave'] != false,
      checkIn: _asDate(m['checkIn']),
      checkOut: _asDate(m['checkOut']),
      inLat: n('inLat'),
      inLng: n('inLng'),
      outLat: n('outLat'),
      outLng: n('outLng'),
      markedBy: _s(m, 'markedBy'),
      note: _s(m, 'note'),
    );
  }
}

/// Attendance for one month, by employee id, then by day key.
Future<Map<String, Map<String, Attendance>>> loadMonthAttendance(String month) async {
  final start = monthStart(month);
  final end = DateTime(start.year, start.month + 1, 0);
  final snap = await companyCol('attendance')
      .where('date', isGreaterThanOrEqualTo: dayKey(start))
      .where('date', isLessThanOrEqualTo: dayKey(end))
      .get();
  final out = <String, Map<String, Attendance>>{};
  for (final d in snap.docs) {
    final a = Attendance.fromDoc(d);
    out.putIfAbsent(a.employeeId, () => {})[a.date] = a;
  }
  return out;
}

/// Admin marks (or clears, with null) one person's day.
Future<void> markAttendance(Employee e, String date, String? status, {String note = ''}) async {
  final ref = companyCol('attendance').doc(Attendance.docId(e.id, date));
  if (status == null) return ref.delete();
  await ref.set({
    'employeeId': e.id,
    'userUid': e.userUid,
    'date': date,
    'status': status,
    'markedBy': 'admin',
    'markedByEmail': _who(),
    if (status != 'leave') 'leaveType': FieldValue.delete(),
    'note': note,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

/// Marks everyone without an entry for [date] as present (for staff without the app).
Future<int> markAllPresent(List<Employee> staff, String date, Map<String, Attendance> existing) async {
  final batch = _db.batch();
  var n = 0;
  for (final e in staff) {
    if (existing.containsKey(e.id)) continue;
    batch.set(companyCol('attendance').doc(Attendance.docId(e.id, date)), {
      'employeeId': e.id,
      'userUid': e.userUid,
      'date': date,
      'status': 'present',
      'markedBy': 'admin',
      'markedByEmail': _who(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    n++;
  }
  if (n > 0) await batch.commit();
  return n;
}

/// The signed-in booker's own day.
Future<Attendance?> loadMyDay(String employeeId, DateTime day) async {
  final d = await companyCol('attendance').doc(Attendance.docId(employeeId, dayKey(day))).get();
  return d.exists ? Attendance.fromDoc(d) : null;
}

/// The booker checks in (or out) from the app, with where they are if the phone allows it.
Future<void> selfCheck({
  required String employeeId,
  required bool checkIn,
  required HrSettings settings,
  num? lat,
  num? lng,
}) async {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  final now = DateTime.now();
  final ref = companyCol('attendance').doc(Attendance.docId(employeeId, dayKey(now)));
  await ref.set({
    'employeeId': employeeId,
    'userUid': uid,
    'date': dayKey(now),
    'markedBy': 'self',
    if (checkIn) ...{
      'status': settings.isLate(now) ? 'late' : 'present',
      'checkIn': Timestamp.fromDate(now),
      'inLat': lat,
      'inLng': lng,
    } else ...{
      'checkOut': Timestamp.fromDate(now),
      'outLat': lat,
      'outLng': lng,
    },
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

/// The signed-in booker's attendance for a month.
Future<List<Attendance>> loadMyAttendance(String month) async {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  final start = monthStart(month);
  final end = DateTime(start.year, start.month + 1, 0);
  final snap = await companyCol('attendance').where('userUid', isEqualTo: uid).get();
  return snap.docs
      .map(Attendance.fromDoc)
      .where((a) => a.date.compareTo(dayKey(start)) >= 0 && a.date.compareTo(dayKey(end)) <= 0)
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));
}

/// A month's attendance added up for one person.
class AttendanceSummary {
  final int workingDays;
  num present = 0, late = 0, half = 0, absent = 0, paidLeave = 0, unpaidLeave = 0, off = 0, unmarked = 0;
  AttendanceSummary(this.workingDays);

  /// Days that cost pay: absences, unpaid leave and half of each half day.
  num get unpaidDays => absent + unpaidLeave + half * 0.5;
  num get daysAtWork => present + late + half * 0.5;
}

/// Adds up a person's month. Days before they joined or after they left count as not employed;
/// unmarked working days count as present (staff without the app are marked by exception).
AttendanceSummary summarise(Employee e, String month, Map<String, Attendance> days, HrSettings settings) {
  final work = settings.workingDays(month);
  final employed = work.where((d) {
    if (e.joinDate != null && d.isBefore(dateOnly(e.joinDate!))) return false;
    if (e.leftDate != null && d.isAfter(dateOnly(e.leftDate!))) return false;
    return true;
  }).toList();
  final s = AttendanceSummary(employed.length);
  for (final d in employed) {
    final a = days[dayKey(d)];
    switch (a?.status) {
      case null:
        s.unmarked++;
      case 'present':
        s.present++;
      case 'late':
        s.late++;
      case 'half':
        s.half++;
      case 'absent':
        s.absent++;
      case 'leave':
        if (a!.paidLeave) {
          s.paidLeave++;
        } else {
          s.unpaidLeave++;
        }
      case 'off':
        s.off++;
    }
  }
  return s;
}

// =============================================================================
// Leave
// =============================================================================

class LeaveRequest {
  final String id;
  final String employeeId;
  final String employeeName;
  final String userUid;
  final String type;
  final DateTime from;
  final DateTime to;
  final num days; // working days in the range
  final String reason;
  final String status; // pending | approved | rejected | cancelled
  final String decidedBy;
  final String decisionNote;
  final DateTime? createdAt;

  const LeaveRequest({
    this.id = '',
    required this.employeeId,
    required this.employeeName,
    this.userUid = '',
    required this.type,
    required this.from,
    required this.to,
    required this.days,
    this.reason = '',
    this.status = 'pending',
    this.decidedBy = '',
    this.decisionNote = '',
    this.createdAt,
  });

  factory LeaveRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return LeaveRequest(
      id: doc.id,
      employeeId: _s(m, 'employeeId'),
      employeeName: _s(m, 'employeeName'),
      userUid: _s(m, 'userUid'),
      type: _s(m, 'type'),
      from: _asDate(m['from']) ?? DateTime.now(),
      to: _asDate(m['to']) ?? DateTime.now(),
      days: _asNum(m['days']),
      reason: _s(m, 'reason'),
      status: _s(m, 'status').isEmpty ? 'pending' : _s(m, 'status'),
      decidedBy: _s(m, 'decidedBy'),
      decisionNote: _s(m, 'decisionNote'),
      createdAt: _asDate(m['createdAt']),
    );
  }
}

/// Working days between two dates, both included.
List<DateTime> leaveDays(DateTime from, DateTime to, HrSettings settings) {
  final out = <DateTime>[];
  for (var d = dateOnly(from); !d.isAfter(dateOnly(to)); d = DateTime(d.year, d.month, d.day + 1)) {
    if (!settings.weeklyOff.contains(d.weekday)) out.add(d);
  }
  return out;
}

/// Applies for leave: a booker for themselves, or an admin on someone's behalf ([approve] true
/// records it as approved straight away).
Future<void> applyLeave({
  required String employeeId,
  required String employeeName,
  required String userUid,
  required String type,
  required DateTime from,
  required DateTime to,
  required String reason,
  required HrSettings settings,
  Employee? approveFor,
}) async {
  final ref = companyCol('leave_requests').doc();
  final days = leaveDays(from, to, settings).length;
  await ref.set({
    'employeeId': employeeId,
    'employeeName': employeeName,
    'userUid': userUid,
    'type': type,
    'from': Timestamp.fromDate(dateOnly(from)),
    'to': Timestamp.fromDate(dateOnly(to)),
    'days': days,
    'reason': reason,
    'status': 'pending',
    'createdAt': FieldValue.serverTimestamp(),
    'createdBy': _who(),
  });
  if (approveFor != null) {
    await decideLeave(
      LeaveRequest(
          id: ref.id,
          employeeId: employeeId,
          employeeName: employeeName,
          userUid: userUid,
          type: type,
          from: from,
          to: to,
          days: days),
      approveFor,
      approve: true,
      settings: settings,
    );
  }
}

Future<List<LeaveRequest>> loadLeaveRequests() async {
  final snap = await companyCol('leave_requests').orderBy('createdAt', descending: true).limit(300).get();
  return snap.docs.map(LeaveRequest.fromDoc).toList();
}

Future<List<LeaveRequest>> loadMyLeaveRequests() async {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  final snap = await companyCol('leave_requests').where('userUid', isEqualTo: uid).get();
  return snap.docs.map(LeaveRequest.fromDoc).toList()
    ..sort((a, b) => (b.createdAt ?? b.from).compareTo(a.createdAt ?? a.from));
}

/// Approves (marking each working day as leave) or rejects a request.
Future<void> decideLeave(LeaveRequest r, Employee e,
    {required bool approve, required HrSettings settings, String note = ''}) async {
  final batch = _db.batch();
  batch.update(companyCol('leave_requests').doc(r.id), {
    'status': approve ? 'approved' : 'rejected',
    'decidedBy': _who(),
    'decisionNote': note,
    'decidedAt': FieldValue.serverTimestamp(),
  });
  if (approve) {
    final paid = settings.leaveType(r.type)?.paid ?? true;
    for (final d in leaveDays(r.from, r.to, settings)) {
      batch.set(companyCol('attendance').doc(Attendance.docId(e.id, dayKey(d))), {
        'employeeId': e.id,
        'userUid': e.userUid,
        'date': dayKey(d),
        'status': 'leave',
        'leaveType': r.type,
        'paidLeave': paid,
        'leaveRequestId': r.id,
        'markedBy': 'admin',
        'markedByEmail': _who(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }
  await batch.commit();
}

/// Cancels an approved request: its leave days are cleared from attendance.
Future<void> cancelApprovedLeave(LeaveRequest r, Employee e, HrSettings settings) async {
  final batch = _db.batch();
  batch.update(companyCol('leave_requests').doc(r.id), {'status': 'cancelled', 'decidedBy': _who()});
  for (final d in leaveDays(r.from, r.to, settings)) {
    batch.delete(companyCol('attendance').doc(Attendance.docId(e.id, dayKey(d))));
  }
  await batch.commit();
}

Future<void> cancelMyLeave(LeaveRequest r) =>
    companyCol('leave_requests').doc(r.id).update({'status': 'cancelled'});

/// Leave days used this calendar year per type (approved requests only).
Map<String, num> leaveUsed(List<LeaveRequest> requests, String employeeId, int year) {
  final out = <String, num>{};
  for (final r in requests) {
    if (r.employeeId != employeeId || r.status != 'approved' || r.from.year != year) continue;
    out[r.type] = (out[r.type] ?? 0) + r.days;
  }
  return out;
}

// =============================================================================
// Advances
// =============================================================================

class Advance {
  final String id;
  final String employeeId;
  final String employeeName;
  final num amount;
  final num installment; // taken from each salary until repaid
  final num repaid;
  final DateTime date;
  final String note;

  const Advance({
    this.id = '',
    required this.employeeId,
    required this.employeeName,
    required this.amount,
    required this.installment,
    this.repaid = 0,
    required this.date,
    this.note = '',
  });

  num get remaining => (amount - repaid) < 0 ? 0 : amount - repaid;

  factory Advance.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return Advance(
      id: doc.id,
      employeeId: _s(m, 'employeeId'),
      employeeName: _s(m, 'employeeName'),
      amount: _asNum(m['amount']),
      installment: _asNum(m['installment']),
      repaid: _asNum(m['repaid']),
      date: _asDate(m['date']) ?? DateTime.now(),
      note: _s(m, 'note'),
    );
  }
}

Future<List<Advance>> loadAdvances() async {
  final snap = await companyCol('advances').orderBy('date', descending: true).get();
  return snap.docs.map(Advance.fromDoc).toList();
}

Future<void> addAdvance(Employee e, num amount, num installment, DateTime date, String note) =>
    companyCol('advances').add({
      'employeeId': e.id,
      'employeeName': e.name,
      'amount': amount,
      'installment': installment <= 0 ? amount : installment,
      'repaid': 0,
      'date': Timestamp.fromDate(date),
      'note': note,
      'by': _who(),
      'createdAt': FieldValue.serverTimestamp(),
    });

Future<void> deleteAdvance(String id) => companyCol('advances').doc(id).delete();

// =============================================================================
// Sales figures for commission and scorecards
// =============================================================================

class BookerMonth {
  num sales = 0;
  int invoices = 0;
  int shopsVisited = 0;
  int visits = 0;
  num recoveries = 0;
}

/// Each booker login's sales (invoice grand totals), visits and recoveries for a month.
Future<Map<String, BookerMonth>> loadBookerMonth(String month) async {
  final start = monthStart(month);
  final end = DateTime(start.year, start.month + 1);
  final results = await Future.wait([
    companyCol('invoices')
        .where('salesDateTs', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('salesDateTs', isLessThan: Timestamp.fromDate(end))
        .get(),
    if (Account.has('crm'))
      companyCol('crm_visits')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThan: Timestamp.fromDate(end))
          .get(),
    if (Account.has('khata'))
      companyCol('customer_recoveries')
          .where('dateStr', isGreaterThanOrEqualTo: dayKey(start))
          .where('dateStr', isLessThan: dayKey(end))
          .get(),
  ]);
  final out = <String, BookerMonth>{};
  BookerMonth of(String uid) => out.putIfAbsent(uid, BookerMonth.new);
  for (final d in results[0].docs) {
    final m = d.data();
    final uid = _s(m, 'userId');
    if (uid.isEmpty) continue;
    of(uid)
      ..sales += _asNum(m['grandTotal'] ?? m['total'])
      ..invoices += 1;
  }
  var i = 1;
  if (Account.has('crm')) {
    final shops = <String, Set<String>>{};
    for (final d in results[i].docs) {
      final m = d.data();
      final uid = _s(m, 'userId');
      if (uid.isEmpty) continue;
      of(uid).visits += 1;
      shops.putIfAbsent(uid, () => {}).add(_s(m, 'customerId').isEmpty ? _s(m, 'customerName') : _s(m, 'customerId'));
    }
    shops.forEach((uid, s) => of(uid).shopsVisited = s.length);
    i++;
  }
  if (Account.has('khata')) {
    for (final d in results[i].docs) {
      final m = d.data();
      final uid = _s(m, 'userId');
      if (uid.isEmpty) continue;
      of(uid).recoveries += _asNum(m['amountPaid']);
    }
  }
  return out;
}

// =============================================================================
// Payroll
// =============================================================================

/// One person's line on a month's salary sheet. The manual fields ([bonus], [otherDeduction],
/// [note]) are kept when the sheet is recalculated.
class PayLine {
  final String employeeId;
  final String name;
  final String code;
  final String designation;
  final String userUid;
  final String salaryType;
  final int workingDays;
  final num daysAtWork;
  final num paidLeave;
  final num unpaidDays;
  final num lates;
  final num basic;
  final num allowances;
  final num gross; // a full month's pay (daily: rate × working days)
  final num absenceDeduction;
  final num lateDeduction;
  final num sales;
  final num commission;
  final num targetBonus;
  final num bonus; // manual
  final num advanceDeduction;
  final Map<String, num> advanceSplit; // advance id → amount taken this month
  final num eobiEmployee;
  final num eobiEmployer;
  final num socialSecurityEmployer;
  final num tax;
  final num otherDeduction; // manual
  final String note;

  const PayLine({
    required this.employeeId,
    required this.name,
    this.code = '',
    this.designation = '',
    this.userUid = '',
    this.salaryType = 'monthly',
    this.workingDays = 0,
    this.daysAtWork = 0,
    this.paidLeave = 0,
    this.unpaidDays = 0,
    this.lates = 0,
    this.basic = 0,
    this.allowances = 0,
    this.gross = 0,
    this.absenceDeduction = 0,
    this.lateDeduction = 0,
    this.sales = 0,
    this.commission = 0,
    this.targetBonus = 0,
    this.bonus = 0,
    this.advanceDeduction = 0,
    this.advanceSplit = const {},
    this.eobiEmployee = 0,
    this.eobiEmployer = 0,
    this.socialSecurityEmployer = 0,
    this.tax = 0,
    this.otherDeduction = 0,
    this.note = '',
  });

  num get earned => gross - absenceDeduction - lateDeduction;
  num get totalEarnings => earned + commission + targetBonus + bonus;
  num get totalDeductions => advanceDeduction + eobiEmployee + tax + otherDeduction;
  num get net => rupees(totalEarnings - totalDeductions);
  num get employerCost => net + advanceDeduction + eobiEmployee + tax + eobiEmployer + socialSecurityEmployer;

  Map<String, dynamic> toMap() => {
        'employeeId': employeeId,
        'name': name,
        'code': code,
        'designation': designation,
        'userUid': userUid,
        'salaryType': salaryType,
        'workingDays': workingDays,
        'daysAtWork': daysAtWork,
        'paidLeave': paidLeave,
        'unpaidDays': unpaidDays,
        'lates': lates,
        'basic': basic,
        'allowances': allowances,
        'gross': gross,
        'absenceDeduction': absenceDeduction,
        'lateDeduction': lateDeduction,
        'sales': sales,
        'commission': commission,
        'targetBonus': targetBonus,
        'bonus': bonus,
        'advanceDeduction': advanceDeduction,
        'advanceSplit': advanceSplit,
        'eobiEmployee': eobiEmployee,
        'eobiEmployer': eobiEmployer,
        'socialSecurityEmployer': socialSecurityEmployer,
        'tax': tax,
        'otherDeduction': otherDeduction,
        'note': note,
        'net': net,
      };

  factory PayLine.fromMap(Map m) {
    final split = m['advanceSplit'];
    return PayLine(
      employeeId: _s(m, 'employeeId'),
      name: _s(m, 'name'),
      code: _s(m, 'code'),
      designation: _s(m, 'designation'),
      userUid: _s(m, 'userUid'),
      salaryType: _s(m, 'salaryType'),
      workingDays: _asNum(m['workingDays']).toInt(),
      daysAtWork: _asNum(m['daysAtWork']),
      paidLeave: _asNum(m['paidLeave']),
      unpaidDays: _asNum(m['unpaidDays']),
      lates: _asNum(m['lates']),
      basic: _asNum(m['basic']),
      allowances: _asNum(m['allowances']),
      gross: _asNum(m['gross']),
      absenceDeduction: _asNum(m['absenceDeduction']),
      lateDeduction: _asNum(m['lateDeduction']),
      sales: _asNum(m['sales']),
      commission: _asNum(m['commission']),
      targetBonus: _asNum(m['targetBonus']),
      bonus: _asNum(m['bonus']),
      advanceDeduction: _asNum(m['advanceDeduction']),
      advanceSplit: split is Map ? {for (final e in split.entries) e.key.toString(): _asNum(e.value)} : const {},
      eobiEmployee: _asNum(m['eobiEmployee']),
      eobiEmployer: _asNum(m['eobiEmployer']),
      socialSecurityEmployer: _asNum(m['socialSecurityEmployer']),
      tax: _asNum(m['tax']),
      otherDeduction: _asNum(m['otherDeduction']),
      note: _s(m, 'note'),
    );
  }

  PayLine withManual({num? bonus, num? otherDeduction, String? note}) => PayLine.fromMap({
        ...toMap(),
        'advanceSplit': advanceSplit,
        if (bonus != null) 'bonus': bonus,
        if (otherDeduction != null) 'otherDeduction': otherDeduction,
        if (note != null) 'note': note,
      });
}

class PayrollRun {
  final String month; // yyyy-MM
  final String status; // draft | final | paid
  final List<PayLine> lines;
  final DateTime? paidAt;
  final String paidMethod;

  const PayrollRun({required this.month, this.status = 'draft', this.lines = const [], this.paidAt, this.paidMethod = ''});

  bool get isDraft => status == 'draft';
  num get totalNet => lines.fold<num>(0, (s, l) => s + l.net);
  num get totalEmployerCost => lines.fold<num>(0, (s, l) => s + l.employerCost);

  factory PayrollRun.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    final lines = m['lines'];
    return PayrollRun(
      month: doc.id,
      status: _s(m, 'status').isEmpty ? 'draft' : _s(m, 'status'),
      lines: lines is List ? [for (final l in lines) if (l is Map) PayLine.fromMap(l)] : const [],
      paidAt: _asDate(m['paidAt']),
      paidMethod: _s(m, 'paidMethod'),
    );
  }
}

Future<List<PayrollRun>> loadPayrollRuns() async {
  final snap = await companyCol('payroll').get();
  return snap.docs.map(PayrollRun.fromDoc).toList()..sort((a, b) => b.month.compareTo(a.month));
}

Future<PayrollRun?> loadPayrollRun(String month) async {
  final d = await companyCol('payroll').doc(month).get();
  return d.exists ? PayrollRun.fromDoc(d) : null;
}

/// Works out one person's line for a month.
PayLine calculatePayLine({
  required Employee e,
  required String month,
  required HrSettings settings,
  required Map<String, Attendance> days,
  required BookerMonth? sales,
  required List<Advance> advances,
  PayLine? keep, // the previous calculation: its manual fields carry over
}) {
  final s = summarise(e, month, days, settings);
  final allWorkDays = settings.workingDays(month).length;
  final perDay = e.isDaily ? e.basic : (allWorkDays == 0 ? 0 : e.monthlyGross / allWorkDays);
  // A full month for monthly staff; for daily wagers, their rate × the days they were employed.
  final gross = e.isDaily ? e.basic * s.workingDays + e.allowanceTotal : e.monthlyGross;
  // Days not employed this month (joined late / left early) aren't paid for monthly staff.
  final notEmployed = e.isDaily ? 0 : allWorkDays - s.workingDays;
  final absence = rupees(perDay * (s.unpaidDays + notEmployed));
  final lateDays = settings.latesPerDay > 0 ? (s.late ~/ settings.latesPerDay) : 0;
  final late = rupees(perDay * lateDays);

  final salesTotal = sales?.sales ?? 0;
  final commission = rupees(salesTotal * e.commissionPct / 100);
  final targetBonus = e.monthlyTarget > 0 && salesTotal >= e.monthlyTarget ? e.targetBonus : 0;

  // Advances: oldest first, an installment each, never more than what's left.
  final split = <String, num>{};
  var advanceTotal = 0 as num;
  final mine = advances.where((a) => a.employeeId == e.id && a.remaining > 0).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  for (final a in mine) {
    if (!a.date.isBefore(DateTime(monthStart(month).year, monthStart(month).month + 1))) continue; // given later
    final take = a.installment < a.remaining ? a.installment : a.remaining;
    if (take <= 0) continue;
    split[a.id] = take;
    advanceTotal += take;
  }

  final bonus = keep?.bonus ?? 0;
  final earned = gross - absence - late;
  final taxable = earned + commission + targetBonus + bonus;
  final tax = e.incomeTax ? rupees(settings.annualTax(taxable * 12) / 12) : 0;
  final eobiEmp = e.eobi ? rupees(settings.eobiEmployee) : 0;
  final eobiEr = e.eobi ? rupees(settings.eobiEmployer) : 0;
  final ssBase = settings.socialSecurityCeiling > 0 && earned > settings.socialSecurityCeiling
      ? settings.socialSecurityCeiling
      : earned;
  final ss = e.socialSecurity ? rupees(ssBase * settings.socialSecurityPct / 100) : 0;

  return PayLine(
    employeeId: e.id,
    name: e.name,
    code: e.code,
    designation: e.designation,
    userUid: e.userUid,
    salaryType: e.salaryType,
    workingDays: s.workingDays,
    daysAtWork: s.daysAtWork + s.unmarked,
    paidLeave: s.paidLeave,
    unpaidDays: s.unpaidDays,
    lates: s.late,
    basic: e.isDaily ? e.basic * s.workingDays : e.basic,
    allowances: e.allowanceTotal,
    gross: gross,
    absenceDeduction: absence,
    lateDeduction: late,
    sales: salesTotal,
    commission: commission,
    targetBonus: targetBonus,
    bonus: bonus,
    advanceDeduction: advanceTotal,
    advanceSplit: split,
    eobiEmployee: eobiEmp,
    eobiEmployer: eobiEr,
    socialSecurityEmployer: ss,
    tax: tax,
    otherDeduction: keep?.otherDeduction ?? 0,
    note: keep?.note ?? '',
  );
}

/// Works out (or re-works out) a month's salary sheet for everyone employed in it. Only a draft
/// can be recalculated.
Future<PayrollRun> calculatePayroll(String month, {PayrollRun? previous}) async {
  final start = monthStart(month);
  final end = DateTime(start.year, start.month + 1, 0);
  final results = await Future.wait<Object>([
    loadHrSettings(),
    loadEmployees(),
    loadMonthAttendance(month),
    loadBookerMonth(month),
    loadAdvances(),
  ]);
  final settings = results[0] as HrSettings;
  final staff = (results[1] as List<Employee>).where((e) {
    if (e.joinDate != null && e.joinDate!.isAfter(end)) return false; // not joined yet
    if (!e.isActive && (e.leftDate == null || e.leftDate!.isBefore(start))) return false; // gone before
    return e.basic > 0 || e.commissionPct > 0;
  });
  final attendance = results[2] as Map<String, Map<String, Attendance>>;
  final sales = results[3] as Map<String, BookerMonth>;
  final advances = results[4] as List<Advance>;
  final keep = {for (final l in previous?.lines ?? const <PayLine>[]) l.employeeId: l};
  final lines = [
    for (final e in staff)
      calculatePayLine(
        e: e,
        month: month,
        settings: settings,
        days: attendance[e.id] ?? const {},
        sales: e.hasApp ? sales[e.userUid] : null,
        advances: advances,
        keep: keep[e.id],
      ),
  ];
  return PayrollRun(month: month, lines: lines);
}

Future<void> savePayrollDraft(PayrollRun run) => companyCol('payroll').doc(run.month).set({
      'status': 'draft',
      'lines': run.lines.map((l) => l.toMap()).toList(),
      'totalNet': run.totalNet,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _who(),
    });

/// Locks the month: payslips are issued and advance installments are recorded as repaid.
Future<void> finalisePayroll(PayrollRun run) async {
  final batch = _db.batch();
  batch.set(companyCol('payroll').doc(run.month), {
    'status': 'final',
    'lines': run.lines.map((l) => l.toMap()).toList(),
    'totalNet': run.totalNet,
    'totalEmployerCost': run.totalEmployerCost,
    'finalisedAt': FieldValue.serverTimestamp(),
    'finalisedBy': _who(),
  });
  for (final l in run.lines) {
    batch.set(companyCol('payslips').doc('${run.month}_${l.employeeId}'), {
      ...l.toMap(),
      'month': run.month,
      'companyName': Account.companyName,
      'issuedAt': FieldValue.serverTimestamp(),
    });
    l.advanceSplit.forEach((id, amount) {
      batch.update(companyCol('advances').doc(id), {'repaid': FieldValue.increment(amount)});
    });
  }
  await batch.commit();
}

/// Back to draft (e.g. a mistake): payslips are withdrawn and advance repayments undone.
Future<void> reopenPayroll(PayrollRun run) async {
  final batch = _db.batch();
  batch.update(companyCol('payroll').doc(run.month), {'status': 'draft', 'paidAt': null});
  for (final l in run.lines) {
    batch.delete(companyCol('payslips').doc('${run.month}_${l.employeeId}'));
    l.advanceSplit.forEach((id, amount) {
      batch.update(companyCol('advances').doc(id), {'repaid': FieldValue.increment(-amount)});
    });
  }
  await batch.commit();
}

Future<void> markPayrollPaid(String month, String method) => companyCol('payroll').doc(month).update({
      'status': 'paid',
      'paidAt': FieldValue.serverTimestamp(),
      'paidMethod': method,
      'paidBy': _who(),
    });

/// The signed-in booker's payslips, newest first.
Future<List<(String, PayLine)>> loadMyPayslips() async {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  final snap = await companyCol('payslips').where('userUid', isEqualTo: uid).get();
  return [for (final d in snap.docs) (_s(d.data(), 'month'), PayLine.fromMap(d.data()))]
    ..sort((a, b) => b.$1.compareTo(a.$1));
}

// =============================================================================
// Final settlement
// =============================================================================

class Settlement {
  final DateTime lastDay;
  final int daysWorkedLastMonth;
  final num salaryDue; // pay for the last month's days not yet on a finalised salary sheet
  final num leaveDays; // unused paid annual leave
  final num leaveEncashment;
  final num advancesOutstanding;
  final num otherDues; // manual: gratuity, bonus owed…
  final num otherDeductions; // manual: damages, unreturned items…
  final String note;

  const Settlement({
    required this.lastDay,
    required this.daysWorkedLastMonth,
    required this.salaryDue,
    required this.leaveDays,
    required this.leaveEncashment,
    required this.advancesOutstanding,
    this.otherDues = 0,
    this.otherDeductions = 0,
    this.note = '',
  });

  num get net => rupees(salaryDue + leaveEncashment + otherDues - advancesOutstanding - otherDeductions);

  Map<String, dynamic> toMap() => {
        'lastDay': Timestamp.fromDate(lastDay),
        'daysWorkedLastMonth': daysWorkedLastMonth,
        'salaryDue': salaryDue,
        'leaveDays': leaveDays,
        'leaveEncashment': leaveEncashment,
        'advancesOutstanding': advancesOutstanding,
        'otherDues': otherDues,
        'otherDeductions': otherDeductions,
        'note': note,
        'net': net,
      };

  Settlement copyWith({num? otherDues, num? otherDeductions, String? note}) => Settlement(
        lastDay: lastDay,
        daysWorkedLastMonth: daysWorkedLastMonth,
        salaryDue: salaryDue,
        leaveDays: leaveDays,
        leaveEncashment: leaveEncashment,
        advancesOutstanding: advancesOutstanding,
        otherDues: otherDues ?? this.otherDues,
        otherDeductions: otherDeductions ?? this.otherDeductions,
        note: note ?? this.note,
      );
}

/// Works out what's owed to (or by) someone leaving on [lastDay].
Future<Settlement> calculateSettlement(Employee e, DateTime lastDay) async {
  final month = monthKey(lastDay);
  final results = await Future.wait<Object?>([
    loadHrSettings(),
    loadMonthAttendance(month),
    loadAdvances(),
    loadLeaveRequests(),
    loadPayrollRun(month),
  ]);
  final settings = results[0] as HrSettings;
  final attendance = (results[1] as Map<String, Map<String, Attendance>>)[e.id] ?? const {};
  final advances = results[2] as List<Advance>;
  final leave = results[3] as List<LeaveRequest>;
  final run = results[4] as PayrollRun?;
  final leaving = Employee.fromMap(e.id, {...e.toMap(), 'leftDate': Timestamp.fromDate(lastDay)});

  // Last month's pay, unless that month's salary sheet is already final (then it's paid there).
  final alreadyOnSheet = run != null && !run.isDraft && run.lines.any((l) => l.employeeId == e.id);
  final line = calculatePayLine(
      e: leaving, month: month, settings: settings, days: attendance, sales: null, advances: const []);
  final salaryDue = alreadyOnSheet ? 0 : line.earned;

  // Unused annual leave for this year, paid at a day's rate.
  final annual = settings.leaveTypes.where((l) => l.paid && l.name.toLowerCase().contains('annual')).firstOrNull;
  num unused = 0;
  if (annual != null && settings.encashLeave) {
    final used = leaveUsed(leave, e.id, lastDay.year)[annual.name] ?? 0;
    // Pro-rata for the months worked this year.
    final fromMonth = e.joinDate != null && e.joinDate!.year == lastDay.year ? e.joinDate!.month : 1;
    final months = lastDay.month - fromMonth + 1;
    final earnedDays = annual.daysPerYear * months / 12;
    unused = (earnedDays - used) < 0 ? 0 : (earnedDays - used).floorToDouble();
  }
  final dayRate = e.isDaily ? e.basic : e.monthlyGross / (settings.workingDays(month).isEmpty ? 26 : settings.workingDays(month).length);

  final owed = advances.where((a) => a.employeeId == e.id).fold<num>(0, (s, a) => s + a.remaining);
  return Settlement(
    lastDay: lastDay,
    daysWorkedLastMonth: summarise(leaving, month, attendance, settings).workingDays,
    salaryDue: rupees(salaryDue),
    leaveDays: unused,
    leaveEncashment: rupees(unused * dayRate),
    advancesOutstanding: owed,
  );
}

/// Records someone leaving with their settlement; their app link is switched off.
Future<void> saveSettlement(Employee e, String status, Settlement s) async {
  final batch = _db.batch();
  batch.update(companyCol('employees').doc(e.id), {
    'status': status,
    'leftDate': Timestamp.fromDate(s.lastDay),
    'settlement': {...s.toMap(), 'savedAt': Timestamp.now(), 'by': _who()},
  });
  if (e.userUid.isNotEmpty) batch.set(companyCol('hr_links').doc(e.userUid), {'active': false}, SetOptions(merge: true));
  // Outstanding advances are cleared by the settlement.
  for (final a in await loadAdvances()) {
    if (a.employeeId == e.id && a.remaining > 0) {
      batch.update(companyCol('advances').doc(a.id), {'repaid': a.amount, 'settled': true});
    }
  }
  await batch.commit();
}

