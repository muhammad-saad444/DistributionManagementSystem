// Staff: the list, adding/editing someone, and one person's page (attendance, leave balances,
// advances, final settlement).
import 'package:flutter/material.dart';
import 'package:an_agency/ui/app_theme.dart';

import '../account/account.dart';
import '../crm/crm_ui.dart';
import '../print_preview.dart';
import 'hr_data.dart';
import 'hr_pdf.dart';
import 'hr_ui.dart';

class StaffTab extends StatefulWidget {
  const StaffTab({super.key});

  @override
  State<StaffTab> createState() => _StaffTabState();
}

class _StaffTabState extends State<StaffTab> {
  List<Employee>? _staff;
  Object? _error;
  String _search = '';
  bool _showLeft = false;
  List<AppUser> _unlinked = const []; // app logins with no staff record yet

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final s = await loadEmployees();
      List<AppUser> unlinked = const [];
      try {
        unlinked = await loginsWithoutStaffRecord(s);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _staff = s;
          _unlinked = unlinked;
        });
      }
    } catch (e) {
      debugPrint('HR staff: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  Widget _importBanner(List<Employee> staff) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(color: CrmTokens.amberBg, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          const Icon(Icons.person_search_outlined, color: CrmTokens.navy),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${_unlinked.length} app login${_unlinked.length == 1 ? '' : 's'} '
              '(${_unlinked.take(3).map((u) => u.name.isEmpty ? u.email : u.name).join(', ')}'
              '${_unlinked.length > 3 ? '…' : ''}) ${_unlinked.length == 1 ? 'has' : 'have'} no staff record yet.',
              style: CrmTokens.body(),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.navy, elevation: 0),
            onPressed: () => _import(staff),
            child: Text('Import', style: CrmTokens.body(color: Colors.white, w: FontWeight.w600)),
          ),
        ]),
      );

  Future<void> _import(List<Employee> staff) async {
    final picked = {for (final u in _unlinked) if (u.role == Role.booker) u.uid};
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text('Add app logins as staff', style: CrmTokens.display(size: 17)),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Each gets a staff record linked to their login. Add their salary, CNIC and bank afterwards.',
                  style: CrmTokens.body(size: 12.5, color: CrmTokens.muted)),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final u in _unlinked)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: picked.contains(u.uid),
                      activeColor: CrmTokens.navy,
                      onChanged: (v) => set(() => v == true ? picked.add(u.uid) : picked.remove(u.uid)),
                      title: Text(u.name.isEmpty ? u.email : u.name, style: CrmTokens.body(w: FontWeight.w600)),
                      subtitle: Text('${u.email}  ·  ${u.role.name}', style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
                    ),
                ]),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Cancel', style: CrmTokens.body())),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.navy, elevation: 0),
              onPressed: picked.isEmpty ? null : () => Navigator.pop(d, true),
              child: Text('Add ${picked.length}', style: CrmTokens.body(color: Colors.white, w: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final n = await importLogins(_unlinked.where((u) => picked.contains(u.uid)).toList(), staff);
      if (mounted) crmSnack(context, 'Added $n. Open each to fill in salary and details.');
    } catch (e) {
      debugPrint('Import logins failed: $e');
      if (mounted) crmSnack(context, "Couldn't add. Check your connection.", error: true);
    }
    _load();
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final staff = _staff;
    if (staff == null) return hrLoading(_error, _load, what: 'staff');
    final q = _search.trim().toLowerCase();
    final active = staff.where((e) => e.isActive).toList();
    final shown = staff
        .where((e) => _showLeft || e.isActive)
        .where((e) =>
            q.isEmpty ||
            e.name.toLowerCase().contains(q) ||
            e.code.toLowerCase().contains(q) ||
            e.designation.toLowerCase().contains(q) ||
            e.phone.contains(q))
        .toList();
    final payroll = active.fold<num>(0, (s, e) => s + (e.isDaily ? e.basic * 26 : e.monthlyGross));
    return Scaffold(
      backgroundColor: CrmTokens.bg,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: CrmTokens.amber,
        foregroundColor: CrmTokens.navyDark,
        onPressed: () => _open(EmployeeFormScreen(existing: staff)),
        icon: const Icon(Icons.person_add_alt_1),
        label: Text('Add staff', style: CrmTokens.body(color: CrmTokens.navyDark, w: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        color: CrmTokens.navy,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
          children: [
            Row(children: [
              Expanded(child: CrmStat(label: 'Active staff', value: '${active.length}')),
              const SizedBox(width: 8),
              Expanded(child: CrmStat(label: 'Monthly salaries (fixed)', value: crmRs(payroll))),
            ]),
            const SizedBox(height: 12),
            if (_unlinked.isNotEmpty) _importBanner(staff),
            TextField(
              onChanged: (v) => setState(() => _search = v),
              style: CrmTokens.body(),
              decoration: crmInput('Search name, code, designation, phone', icon: Icons.search),
            ),
            Row(children: [
              Checkbox(
                  value: _showLeft,
                  activeColor: CrmTokens.navy,
                  onChanged: (v) => setState(() => _showLeft = v ?? false)),
              Text('Show people who have left', style: CrmTokens.body(color: CrmTokens.muted)),
            ]),
            if (staff.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 30),
                child: CrmEmpty(
                    icon: Icons.badge_outlined,
                    text: 'No staff yet. Add your bookers, drivers and office staff to track attendance and pay salaries.'),
              )
            else
              for (final e in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: CrmCard(
                    onTap: () => _open(EmployeeDetailScreen(employeeId: e.id)),
                    child: Row(children: [
                      CircleAvatar(
                        backgroundColor: e.isActive ? CrmTokens.blueBg : CrmTokens.bg,
                        child: Text(e.name.isEmpty ? '?' : e.name[0].toUpperCase(),
                            style: CrmTokens.body(w: FontWeight.w700, color: CrmTokens.navy)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Flexible(child: Text(e.name, style: CrmTokens.display(size: 15), overflow: TextOverflow.ellipsis)),
                            if (e.hasApp) ...[
                              const SizedBox(width: 6),
                              const CrmPill('App', icon: Icons.phone_android, color: CrmTokens.blue, background: CrmTokens.blueBg),
                            ],
                          ]),
                          const SizedBox(height: 2),
                          Text(
                            [e.code, e.designation, if (e.department.isNotEmpty) e.department, e.phone]
                                .where((s) => s.isNotEmpty)
                                .join('  ·  '),
                            style: CrmTokens.body(size: 12, color: CrmTokens.muted),
                          ),
                        ]),
                      ),
                      if (!e.isActive)
                        CrmPill(e.status == 'terminated' ? 'Terminated' : 'Resigned',
                            color: CrmTokens.muted, background: CrmTokens.bg)
                      else
                        Text(e.isDaily ? '${crmRs(e.basic)}/day' : crmRs(e.monthlyGross),
                            style: CrmTokens.body(w: FontWeight.w700)),
                    ]),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Add / edit
// -----------------------------------------------------------------------------

class EmployeeFormScreen extends StatefulWidget {
  final Employee? employee;
  final List<Employee> existing; // for the next code and to hide logins already linked
  const EmployeeFormScreen({super.key, this.employee, this.existing = const []});

  @override
  State<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends State<EmployeeFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _code = TextEditingController();
  final _name = TextEditingController();
  final _father = TextEditingController();
  final _cnic = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _emName = TextEditingController();
  final _emPhone = TextEditingController();
  final _department = TextEditingController();
  final _basic = TextEditingController();
  final _bank = TextEditingController();
  final _title = TextEditingController();
  final _iban = TextEditingController();
  final _eobiNo = TextEditingController();
  final _commission = TextEditingController();
  final _target = TextEditingController();
  final _targetBonus = TextEditingController();
  final _notes = TextEditingController();
  final List<(TextEditingController, TextEditingController)> _allowances = [];
  DateTime? _join = DateTime.now();
  DateTime? _dob;
  String _designation = 'Booker';
  String _salaryType = 'monthly';
  bool _eobi = false, _tax = false, _ss = false;
  String _userUid = '';
  List<AppUser> _logins = const [];
  bool _saving = false;

  bool get _editing => widget.employee != null;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    String n(num v) => v == 0 ? '' : hrPlain(v);
    if (e != null) {
      _code.text = e.code;
      _name.text = e.name;
      _father.text = e.fatherName;
      _cnic.text = e.cnic;
      _phone.text = e.phone;
      _address.text = e.address;
      _emName.text = e.emergencyName;
      _emPhone.text = e.emergencyPhone;
      _department.text = e.department;
      _basic.text = n(e.basic);
      _bank.text = e.bankName;
      _title.text = e.accountTitle;
      _iban.text = e.iban;
      _eobiNo.text = e.eobiNo;
      _commission.text = n(e.commissionPct);
      _target.text = n(e.monthlyTarget);
      _targetBonus.text = n(e.targetBonus);
      _notes.text = e.notes;
      _join = e.joinDate;
      _dob = e.dob;
      _designation = designations.contains(e.designation) ? e.designation : 'Other';
      _salaryType = e.salaryType;
      _eobi = e.eobi;
      _tax = e.incomeTax;
      _ss = e.socialSecurity;
      _userUid = e.userUid;
      for (final a in e.allowances) {
        _allowances.add((TextEditingController(text: a.name), TextEditingController(text: hrPlain(a.amount))));
      }
    } else {
      _code.text = nextEmployeeCode(widget.existing);
    }
    _loadLogins();
  }

  Future<void> _loadLogins() async {
    try {
      final users = await loadCompanyUsers(fresh: true);
      final taken = {for (final e in widget.existing) if (e.id != widget.employee?.id && e.hasApp) e.userUid};
      if (mounted) setState(() => _logins = users.where((u) => !taken.contains(u.uid)).toList());
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in [_code, _name, _father, _cnic, _phone, _address, _emName, _emPhone, _department, _basic, _bank, _title,
      _iban, _eobiNo, _commission, _target, _targetBonus, _notes]) {
      c.dispose();
    }
    for (final a in _allowances) {
      a.$1.dispose();
      a.$2.dispose();
    }
    super.dispose();
  }

  num _n(TextEditingController c) => num.tryParse(c.text.trim()) ?? 0;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final login = _logins.where((u) => u.uid == _userUid).firstOrNull;
    final old = widget.employee;
    final e = Employee(
      id: old?.id ?? '',
      code: _code.text.trim(),
      name: _name.text.trim(),
      fatherName: _father.text.trim(),
      cnic: _cnic.text.trim(),
      phone: _phone.text.trim(),
      address: _address.text.trim(),
      emergencyName: _emName.text.trim(),
      emergencyPhone: _emPhone.text.trim(),
      joinDate: _join,
      dob: _dob,
      designation: _designation,
      department: _department.text.trim(),
      salaryType: _salaryType,
      basic: _n(_basic),
      allowances: [
        for (final a in _allowances)
          if (a.$1.text.trim().isNotEmpty && _n(a.$2) > 0) Allowance(a.$1.text.trim(), _n(a.$2)),
      ],
      bankName: _bank.text.trim(),
      accountTitle: _title.text.trim(),
      iban: _iban.text.trim(),
      userUid: _userUid,
      userName: login?.name.isNotEmpty == true ? login!.name : (login?.email ?? old?.userName ?? ''),
      eobi: _eobi,
      eobiNo: _eobiNo.text.trim(),
      incomeTax: _tax,
      socialSecurity: _ss,
      commissionPct: _n(_commission),
      monthlyTarget: _n(_target),
      targetBonus: _n(_targetBonus),
      status: old?.status ?? 'active',
      leftDate: old?.leftDate,
      notes: _notes.text.trim(),
    );
    setState(() => _saving = true);
    try {
      final dup = await findDuplicateEmployee(e);
      if (dup != null) {
        if (!mounted) return;
        setState(() => _saving = false);
        return crmSnack(
            context,
            dup.userUid == e.userUid && e.userUid.isNotEmpty
                ? 'That app login is already linked to ${dup.name}.'
                : '${dup.name} already has this CNIC.',
            error: true);
      }
      await saveEmployee(e, before: old);
      if (!mounted) return;
      crmSnack(context, _editing ? 'Saved' : '${e.name} added');
      Navigator.pop(context, true);
    } catch (err) {
      debugPrint('Saving employee failed: $err');
      if (!mounted) return;
      setState(() => _saving = false);
      crmSnack(context, "Couldn't save. Check your connection and try again.", error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = hrPair;
    return Scaffold(
      backgroundColor: CrmTokens.bg,
      appBar: AppBar(
        title: Text(_editing ? 'Edit staff member' : 'Add staff member',
            style: CrmTokens.display(size: 18, color: AppColors.text, w: FontWeight.w600)),
      ),
      body: Form(
        key: _form,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 40),
              children: [
                const CrmSectionTitle('Person'),
                CrmCard(
                  child: Column(children: [
                    p(context, HrField(_code, 'Employee code', icon: Icons.tag),
                        HrField(_name, 'Full name *', icon: Icons.person_outline,
                            validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the name' : null)),
                    const SizedBox(height: 12),
                    p(context, HrField(_father, 'Father / husband name', icon: Icons.family_restroom),
                        HrField(_cnic, 'CNIC', icon: Icons.badge_outlined, hint: '35202-1234567-1', validator: (v) {
                      final d = (v ?? '').replaceAll(RegExp(r'\D'), '');
                      return d.isNotEmpty && d.length != 13 ? 'CNIC has 13 digits' : null;
                    })),
                    const SizedBox(height: 12),
                    p(context, HrField(_phone, 'Phone', icon: Icons.phone_outlined),
                        HrDateField('Date of birth', _dob, (d) => setState(() => _dob = d), last: DateTime.now())),
                    const SizedBox(height: 12),
                    HrField(_address, 'Address', icon: Icons.home_outlined, lines: 2),
                    const SizedBox(height: 12),
                    p(context, HrField(_emName, 'Emergency contact name', icon: Icons.contact_emergency_outlined),
                        HrField(_emPhone, 'Emergency contact phone', icon: Icons.phone_in_talk_outlined)),
                  ]),
                ),
                const CrmSectionTitle('Job'),
                CrmCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    p(
                      context,
                      DropdownButtonFormField<String>(
                        initialValue: _designation,
                        isExpanded: true,
                        decoration: crmInput('Designation', icon: Icons.work_outline),
                        items: [for (final d in designations) DropdownMenuItem(value: d, child: Text(d, style: CrmTokens.body()))],
                        onChanged: (v) => setState(() => _designation = v ?? 'Other'),
                      ),
                      HrField(_department, 'Department', icon: Icons.apartment_outlined, hint: 'e.g. Sales, Warehouse'),
                    ),
                    const SizedBox(height: 12),
                    p(context, HrDateField('Joining date', _join, (d) => setState(() => _join = d), clearable: false),
                        DropdownButtonFormField<String>(
                          initialValue: _logins.any((u) => u.uid == _userUid) || _userUid.isEmpty ? _userUid : '',
                          isExpanded: true,
                          decoration: crmInput('App login', icon: Icons.phone_android),
                          items: [
                            DropdownMenuItem(value: '', child: Text('No app login', style: CrmTokens.body(color: CrmTokens.muted))),
                            for (final u in _logins)
                              DropdownMenuItem(
                                value: u.uid,
                                child: Text('${u.name.isEmpty ? u.email : u.name}  (${u.role.name})',
                                    style: CrmTokens.body(), overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (v) => setState(() => _userUid = v ?? ''),
                        )),
                    const SizedBox(height: 6),
                    Text(
                      'Link a booker\'s login so they can check in from the app, apply for leave, see their payslips, '
                      'and so their sales count for commission.',
                      style: CrmTokens.body(size: 11.5, color: CrmTokens.muted),
                    ),
                  ]),
                ),
                const CrmSectionTitle('Salary'),
                CrmCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 'monthly', label: Text('Monthly salary')),
                          ButtonSegment(value: 'daily', label: Text('Daily wage')),
                        ],
                        selected: {_salaryType},
                        onSelectionChanged: (v) => setState(() => _salaryType = v.first),
                      ),
                    ),
                    const SizedBox(height: 12),
                    HrField(_basic, _salaryType == 'daily' ? 'Wage per day (Rs.) *' : 'Basic salary per month (Rs.) *',
                        icon: Icons.payments_outlined, number: true, onChanged: (_) => setState(() {}), validator: (v) {
                      final n = num.tryParse((v ?? '').trim());
                      return n == null || n < 0 ? 'Enter the salary (0 if commission only)' : null;
                    }),
                    const SizedBox(height: 12),
                    Text('Monthly allowances', style: CrmTokens.body(w: FontWeight.w600)),
                    const SizedBox(height: 6),
                    for (var i = 0; i < _allowances.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(children: [
                          Expanded(flex: 3, child: HrField(_allowances[i].$1, 'Allowance', hint: 'Fuel, mobile, house rent…')),
                          const SizedBox(width: 8),
                          Expanded(
                              flex: 2,
                              child: HrField(_allowances[i].$2, 'Rs. a month', number: true, onChanged: (_) => setState(() {}))),
                          IconButton(
                            icon: const Icon(Icons.close, color: CrmTokens.muted),
                            onPressed: () => setState(() => _allowances.removeAt(i)),
                          ),
                        ]),
                      ),
                    TextButton.icon(
                      onPressed: () => setState(() => _allowances.add((TextEditingController(), TextEditingController()))),
                      icon: const Icon(Icons.add, color: CrmTokens.navy),
                      label: Text('Add allowance', style: CrmTokens.body(color: CrmTokens.navy, w: FontWeight.w600)),
                    ),
                    if (_salaryType == 'monthly' && _n(_basic) > 0)
                      Text(
                        'Gross a month: ${crmRs(_n(_basic) + _allowances.fold<num>(0, (s, a) => s + _n(a.$2)))}',
                        style: CrmTokens.body(w: FontWeight.w700, color: CrmTokens.navy),
                      ),
                  ]),
                ),
                if (_designation == 'Booker' || _designation == 'Salesman' || _n(_commission) > 0) ...[
                  const CrmSectionTitle('Commission and target'),
                  CrmCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      p(context, HrField(_commission, 'Commission (% of sales)', icon: Icons.percent, number: true),
                          HrField(_target, 'Monthly sales target (Rs.)', icon: Icons.flag_outlined, number: true)),
                      const SizedBox(height: 12),
                      HrField(_targetBonus, 'Bonus when target is reached (Rs.)', icon: Icons.emoji_events_outlined, number: true),
                      const SizedBox(height: 6),
                      Text('Worked out from the invoices this person books in the app (needs their app login).',
                          style: CrmTokens.body(size: 11.5, color: CrmTokens.muted)),
                    ]),
                  ),
                ],
                const CrmSectionTitle('Bank'),
                CrmCard(
                  child: Column(children: [
                    p(context, HrField(_bank, 'Bank name', icon: Icons.account_balance_outlined),
                        HrField(_title, 'Account title', icon: Icons.person_pin_outlined)),
                    const SizedBox(height: 12),
                    HrField(_iban, 'IBAN / account no.', icon: Icons.numbers),
                  ]),
                ),
                const CrmSectionTitle('Government deductions'),
                CrmCard(
                  child: Column(children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _eobi,
                      onChanged: (v) => setState(() => _eobi = v),
                      title: Text('EOBI', style: CrmTokens.body(w: FontWeight.w600)),
                      subtitle: Text('Employee 1% and employer 5% of the minimum wage (rates in HR settings)',
                          style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
                    ),
                    if (_eobi) HrField(_eobiNo, 'EOBI registration no.', icon: Icons.numbers),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _tax,
                      onChanged: (v) => setState(() => _tax = v),
                      title: Text('Income tax on salary', style: CrmTokens.body(w: FontWeight.w600)),
                      subtitle: Text('Deducted each month from the FBR salaried slabs in HR settings',
                          style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _ss,
                      onChanged: (v) => setState(() => _ss = v),
                      title: Text('Social security (PESSI / SESSI)', style: CrmTokens.body(w: FontWeight.w600)),
                      subtitle: Text('Paid by the company; shown as employer cost',
                          style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                CrmCard(child: HrField(_notes, 'Notes (optional)', icon: Icons.notes_outlined, lines: 2)),
                const SizedBox(height: 18),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: CrmTokens.amber,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: CrmTokens.navyDark))
                        : const Icon(Icons.check, color: CrmTokens.navyDark),
                    label: Text(_editing ? 'Save changes' : 'Add staff member',
                        style: CrmTokens.body(size: 14, color: CrmTokens.navyDark, w: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// One person
// -----------------------------------------------------------------------------

class EmployeeDetailScreen extends StatefulWidget {
  final String employeeId;
  const EmployeeDetailScreen({super.key, required this.employeeId});

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen> {
  Employee? _e;
  List<Employee> _all = const [];
  HrSettings _settings = const HrSettings();
  AttendanceSummary? _month;
  List<Advance> _advances = const [];
  Map<String, num> _leaveUsed = const {};
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final month = monthKey(DateTime.now());
      final results = await Future.wait<Object>([
        loadEmployees(),
        loadHrSettings(),
        loadMonthAttendance(month),
        loadAdvances(),
        loadLeaveRequests(),
      ]);
      final all = results[0] as List<Employee>;
      final e = all.where((x) => x.id == widget.employeeId).firstOrNull;
      if (!mounted) return;
      if (e == null) {
        Navigator.pop(context);
        return;
      }
      final settings = results[1] as HrSettings;
      setState(() {
        _all = all;
        _e = e;
        _settings = settings;
        _month = summarise(e, month, (results[2] as Map<String, Map<String, Attendance>>)[e.id] ?? const {}, settings);
        _advances = (results[3] as List<Advance>).where((a) => a.employeeId == e.id).toList();
        _leaveUsed = leaveUsed(results[4] as List<LeaveRequest>, e.id, DateTime.now().year);
      });
    } catch (err) {
      debugPrint('HR employee: $err');
      if (mounted) setState(() => _error = err);
    }
  }

  Future<void> _giveAdvance(Employee e) async {
    final amount = TextEditingController();
    final inst = TextEditingController();
    final note = TextEditingController();
    var date = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text('Give advance to ${e.name}', style: CrmTokens.display(size: 17)),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              HrField(amount, 'Amount (Rs.)', number: true, icon: Icons.payments_outlined),
              const SizedBox(height: 10),
              HrField(inst, 'Take back each month (Rs.)', number: true, icon: Icons.event_repeat,
                  hint: 'Empty = all from the next salary'),
              const SizedBox(height: 10),
              HrDateField('Date', date, (v) => set(() => date = v ?? date), clearable: false, last: DateTime.now()),
              const SizedBox(height: 10),
              HrField(note, 'Note (optional)'),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Cancel', style: CrmTokens.body())),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.navy, elevation: 0),
              onPressed: () => Navigator.pop(d, true),
              child: Text('Save', style: CrmTokens.body(color: Colors.white, w: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
    final a = num.tryParse(amount.text.trim()) ?? 0;
    if (ok != true || a <= 0) return;
    try {
      await addAdvance(e, a, num.tryParse(inst.text.trim()) ?? 0, date, note.text.trim());
      if (mounted) crmSnack(context, 'Advance recorded. It comes back from the next salaries.');
      _load();
    } catch (_) {
      if (mounted) crmSnack(context, "Couldn't save. Check your connection.", error: true);
    }
  }

  Future<void> _leave(Employee e) async {
    final saved = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => SettlementScreen(employee: e)));
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final e = _e;
    return Scaffold(
      backgroundColor: CrmTokens.bg,
      appBar: AppBar(
        title: Text(e?.name ?? 'Staff member', style: CrmTokens.display(size: 18, color: AppColors.text, w: FontWeight.w600)),
        actions: [
          if (e != null)
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined, color: AppColors.text),
              onPressed: () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => EmployeeFormScreen(employee: e, existing: _all)));
                _load();
              },
            ),
        ],
      ),
      body: e == null ? hrLoading(_error, _load, what: 'this person') : _body(e),
    );
  }

  Widget _body(Employee e) {
    final m = _month!;
    final owed = _advances.fold<num>(0, (s, a) => s + a.remaining);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
          children: [
            CrmCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(e.name, style: CrmTokens.display(size: 18))),
                  if (!e.isActive)
                    CrmPill(e.status == 'terminated' ? 'Terminated' : 'Resigned', color: CrmTokens.red, background: CrmTokens.redBg)
                  else
                    const CrmPill('Active', color: CrmTokens.green, background: CrmTokens.greenBg),
                ]),
                const SizedBox(height: 4),
                Text([e.code, e.designation, e.department].where((s) => s.isNotEmpty).join('  ·  '),
                    style: CrmTokens.body(color: CrmTokens.muted)),
                const Divider(height: 22),
                HrInfoRow('Phone', e.phone),
                HrInfoRow('CNIC', e.cnic),
                if (e.fatherName.isNotEmpty) HrInfoRow('Father / husband', e.fatherName),
                HrInfoRow('Joined', e.joinDate == null ? '' : crmDay.format(e.joinDate!)),
                if (e.leftDate != null) HrInfoRow('Left', crmDay.format(e.leftDate!)),
                HrInfoRow('App login', e.hasApp ? (e.userName.isEmpty ? 'Linked' : e.userName) : 'None'),
                if (e.emergencyName.isNotEmpty) HrInfoRow('Emergency contact', '${e.emergencyName}  ${e.emergencyPhone}'),
                if (e.address.isNotEmpty) HrInfoRow('Address', e.address),
              ]),
            ),
            const CrmSectionTitle('Pay'),
            CrmCard(
              child: Column(children: [
                HrInfoRow(e.isDaily ? 'Wage per day' : 'Basic salary', crmRs(e.basic)),
                for (final a in e.allowances) HrInfoRow(a.name, crmRs(a.amount)),
                if (!e.isDaily) HrInfoRow('Gross a month', crmRs(e.monthlyGross), bold: true),
                if (e.commissionPct > 0) HrInfoRow('Commission', '${hrPlain(e.commissionPct)}% of sales'),
                if (e.monthlyTarget > 0)
                  HrInfoRow('Target', '${crmRs(e.monthlyTarget)}  →  bonus ${crmRs(e.targetBonus)}'),
                HrInfoRow('Bank', [e.bankName, e.accountTitle, e.iban].where((s) => s.isNotEmpty).join('  ·  ')),
                HrInfoRow('Deductions',
                    [if (e.eobi) 'EOBI', if (e.incomeTax) 'Income tax', if (e.socialSecurity) 'Social security'].join(', ')),
              ]),
            ),
            CrmSectionTitle('This month (${hrMonthLabel.format(DateTime.now())})'),
            Row(children: [
              Expanded(child: CrmStat(label: 'At work', value: hrPlain(m.daysAtWork + m.unmarked))),
              const SizedBox(width: 8),
              Expanded(child: CrmStat(label: 'Late', value: hrPlain(m.late))),
              const SizedBox(width: 8),
              Expanded(child: CrmStat(label: 'Absent', value: hrPlain(m.absent), color: m.absent > 0 ? CrmTokens.red : null)),
              const SizedBox(width: 8),
              Expanded(child: CrmStat(label: 'Leave', value: hrPlain(m.paidLeave + m.unpaidLeave))),
            ]),
            CrmSectionTitle('Leave this year'),
            CrmCard(
              child: Column(children: [
                for (final t in _settings.leaveTypes)
                  if (t.daysPerYear > 0 || (_leaveUsed[t.name] ?? 0) > 0)
                    HrInfoRow(
                      t.name,
                      t.daysPerYear > 0
                          ? '${hrPlain(_leaveUsed[t.name] ?? 0)} used of ${hrPlain(t.daysPerYear)}  ·  '
                              '${hrPlain(t.daysPerYear - (_leaveUsed[t.name] ?? 0))} left'
                          : '${hrPlain(_leaveUsed[t.name] ?? 0)} used',
                    ),
              ]),
            ),
            CrmSectionTitle('Advances and loans',
                trailing: e.isActive
                    ? TextButton.icon(
                        onPressed: () => _giveAdvance(e),
                        icon: const Icon(Icons.add, size: 18, color: CrmTokens.navy),
                        label: Text('Give advance', style: CrmTokens.body(color: CrmTokens.navy, w: FontWeight.w600)),
                      )
                    : null),
            if (_advances.isEmpty)
              Text('No advances.', style: CrmTokens.body(color: CrmTokens.muted))
            else ...[
              for (final a in _advances)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: CrmCard(
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${crmRs(a.amount)} on ${crmDay.format(a.date)}', style: CrmTokens.body(w: FontWeight.w600)),
                          Text(
                            '${crmRs(a.installment)} a month  ·  ${crmRs(a.repaid)} repaid'
                            '${a.note.isNotEmpty ? '  ·  ${a.note}' : ''}',
                            style: CrmTokens.body(size: 12, color: CrmTokens.muted),
                          ),
                        ]),
                      ),
                      a.remaining > 0
                          ? Text('${crmRs(a.remaining)} left', style: CrmTokens.body(w: FontWeight.w700, color: CrmTokens.red))
                          : const CrmPill('Repaid', color: CrmTokens.green, background: CrmTokens.greenBg),
                      if (a.repaid == 0)
                        IconButton(
                          tooltip: 'Delete (nothing repaid yet)',
                          icon: const Icon(Icons.delete_outline, color: CrmTokens.muted, size: 20),
                          onPressed: () async {
                            if (!await hrConfirm(context, 'Delete advance?', 'Only if it was entered by mistake.', 'Delete',
                                danger: true)) {
                              return;
                            }
                            await deleteAdvance(a.id);
                            _load();
                          },
                        ),
                    ]),
                  ),
                ),
              if (owed > 0) HrInfoRow('Outstanding', crmRs(owed), bold: true, color: CrmTokens.red),
            ],
            const SizedBox(height: 20),
            if (e.isActive)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: CrmTokens.red,
                  side: const BorderSide(color: CrmTokens.red),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => _leave(e),
                icon: const Icon(Icons.logout),
                label: Text('Resignation / termination and final settlement',
                    style: CrmTokens.body(color: CrmTokens.red, w: FontWeight.w600)),
              )
            else if (e.settlement != null)
              CrmCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Final settlement', style: CrmTokens.display(size: 15)),
                  const SizedBox(height: 6),
                  HrInfoRow('Net', crmRs((e.settlement!['net'] as num?) ?? 0), bold: true),
                  if ((e.settlement!['note'] ?? '').toString().isNotEmpty) HrInfoRow('Note', e.settlement!['note'].toString()),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Final settlement
// -----------------------------------------------------------------------------

class SettlementScreen extends StatefulWidget {
  final Employee employee;
  const SettlementScreen({super.key, required this.employee});

  @override
  State<SettlementScreen> createState() => _SettlementScreenState();
}

class _SettlementScreenState extends State<SettlementScreen> {
  DateTime _lastDay = DateTime.now();
  String _status = 'resigned';
  Settlement? _s;
  Object? _error;
  final _dues = TextEditingController();
  final _deductions = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _calc();
  }

  @override
  void dispose() {
    _dues.dispose();
    _deductions.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _calc() async {
    setState(() {
      _error = null;
      _s = null;
    });
    try {
      final s = await calculateSettlement(widget.employee, _lastDay);
      if (mounted) setState(() => _s = s);
    } catch (e) {
      debugPrint('Settlement: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  Settlement get _final => _s!.copyWith(
        otherDues: num.tryParse(_dues.text.trim()) ?? 0,
        otherDeductions: num.tryParse(_deductions.text.trim()) ?? 0,
        note: _note.text.trim(),
      );

  Future<void> _save() async {
    final e = widget.employee;
    if (!await hrConfirm(
        context,
        'Close ${e.name}\'s employment?',
        'They are marked ${_status == 'terminated' ? 'terminated' : 'resigned'} from ${crmDay.format(_lastDay)}, '
            'their app login stops counting for HR, and outstanding advances are cleared by this settlement.',
        'Save settlement',
        danger: true)) {
      return;
    }
    setState(() => _saving = true);
    try {
      final s = _final;
      await saveSettlement(e, _status, s);
      if (!mounted) return;
      await showPrintPreview(context,
          title: 'Final settlement',
          buildPdf: () => settlementPdf(e, _status, s),
          fileName: 'Settlement_${e.name.replaceAll(' ', '_')}.pdf');
      if (mounted) Navigator.pop(context, true);
    } catch (err) {
      debugPrint('Saving settlement failed: $err');
      if (!mounted) return;
      setState(() => _saving = false);
      crmSnack(context, "Couldn't save. Check your connection and try again.", error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.employee;
    final s = _s;
    return Scaffold(
      backgroundColor: CrmTokens.bg,
      appBar: AppBar(
        title: Text('Final settlement', style: CrmTokens.display(size: 18, color: AppColors.text, w: FontWeight.w600)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
            children: [
              Text(e.name, style: CrmTokens.display(size: 18)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'resigned', label: Text('Resigned')),
                    ButtonSegment(value: 'terminated', label: Text('Terminated')),
                  ],
                  selected: {_status},
                  onSelectionChanged: (v) => setState(() => _status = v.first),
                ),
              ),
              const SizedBox(height: 12),
              HrDateField('Last working day', _lastDay, (d) {
                if (d == null) return;
                setState(() => _lastDay = d);
                _calc();
              }, clearable: false, first: e.joinDate),
              const SizedBox(height: 14),
              if (s == null)
                SizedBox(height: 160, child: hrLoading(_error, _calc, what: 'the settlement'))
              else ...[
                CrmCard(
                  child: Column(children: [
                    HrInfoRow('Salary for ${hrMonthLabel.format(_lastDay)} (${s.daysWorkedLastMonth} working days)',
                        crmRs(s.salaryDue)),
                    if (s.salaryDue == 0)
                      Text('That month\'s salary sheet is already final, so it is paid there.',
                          style: CrmTokens.body(size: 11.5, color: CrmTokens.muted)),
                    HrInfoRow('Unused annual leave (${hrPlain(s.leaveDays)} days)', crmRs(s.leaveEncashment)),
                    HrInfoRow('Advances outstanding', s.advancesOutstanding > 0 ? '- ${crmRs(s.advancesOutstanding)}' : crmRs(0),
                        color: s.advancesOutstanding > 0 ? CrmTokens.red : null),
                  ]),
                ),
                const SizedBox(height: 12),
                hrPair(
                  context,
                  HrField(_dues, 'Other dues (Rs.)', number: true, hint: 'Gratuity, bonus owed…', onChanged: (_) => setState(() {})),
                  HrField(_deductions, 'Other deductions (Rs.)', number: true, hint: 'Damages, items not returned…',
                      onChanged: (_) => setState(() {})),
                ),
                const SizedBox(height: 12),
                HrField(_note, 'Note (optional)', lines: 2),
                const SizedBox(height: 12),
                CrmCard(
                  child: HrInfoRow(
                    _final.net >= 0 ? 'Payable to ${e.name}' : 'Recoverable from ${e.name}',
                    crmRs(_final.net.abs()),
                    bold: true,
                    color: _final.net >= 0 ? CrmTokens.green : CrmTokens.red,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.red, elevation: 0),
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: Text('Save settlement and print', style: CrmTokens.body(color: Colors.white, w: FontWeight.w700)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
