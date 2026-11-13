// The company's details printed on invoices, and its sales tax settings. Kept on the company
// record (companies/{id}.profile), which every member can read and only an admin can change.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../account/account.dart';
import '../audit/audit.dart';
import 'invoice_tax.dart';

class CompanyProfile {
  final String legalName; // as registered; the app's company name if empty
  final String address;
  final String phone;
  final String email;
  final String ntn;
  final String strn; // sales tax registration number
  final String invoiceNote; // printed at the bottom of every invoice (terms, bank details...)
  final bool taxEnabled;
  final double taxRate;
  final bool taxInclusive; // prices already include the tax

  const CompanyProfile({
    this.legalName = '',
    this.address = '',
    this.phone = '',
    this.email = '',
    this.ntn = '',
    this.strn = '',
    this.invoiceNote = '',
    this.taxEnabled = false,
    this.taxRate = 18,
    this.taxInclusive = true,
  });

  factory CompanyProfile.fromMap(Map? m) {
    String s(String k) => (m?[k] ?? '').toString().trim();
    return CompanyProfile(
      legalName: s('legalName'),
      address: s('address'),
      phone: s('phone'),
      email: s('email'),
      ntn: s('ntn'),
      strn: s('strn'),
      invoiceNote: s('invoiceNote'),
      taxEnabled: m?['taxEnabled'] == true,
      taxRate: (num.tryParse(s('taxRate')) ?? 18).toDouble(),
      taxInclusive: m?['taxInclusive'] != false,
    );
  }

  Map<String, dynamic> toMap() => {
        'legalName': legalName.trim(),
        'address': address.trim(),
        'phone': phone.trim(),
        'email': email.trim(),
        'ntn': ntn.trim(),
        'strn': strn.trim(),
        'invoiceNote': invoiceNote.trim(),
        'taxEnabled': taxEnabled,
        'taxRate': taxRate,
        'taxInclusive': taxInclusive,
      };

  String get name => legalName.isNotEmpty ? legalName : Account.companyName;

  /// Tax fields a new invoice is saved with: its lines [items] and total after discount [net].
  /// Empty when sales tax is off.
  Map<String, dynamic> taxFieldsFor(List items, double net) =>
      taxEnabled ? computeTax(items, net, rate: taxRate, inclusive: taxInclusive).fields : const {};
}

CompanyProfile? _cached;
String? _cachedFor;

/// The company's profile (read once, then from memory; [fresh] reads it again).
Future<CompanyProfile> loadCompanyProfile({bool fresh = false}) async {
  final id = Account.companyId;
  if (!fresh && _cached != null && _cachedFor == id) return _cached!;
  if (id == null) return const CompanyProfile();
  try {
    final d = await FirebaseFirestore.instance.collection('companies').doc(id).get();
    _cached = CompanyProfile.fromMap(d.data()?['profile'] as Map?);
    _cachedFor = id;
  } catch (e) {
    debugPrint('Company profile: $e');
    _cached ??= const CompanyProfile();
  }
  return _cached!;
}

/// Saves the profile (admins only) and notes what changed in the audit log.
Future<void> saveCompanyProfile(CompanyProfile p) async {
  final before = await loadCompanyProfile(fresh: true);
  await FirebaseFirestore.instance.collection('companies').doc(Account.companyId).update({'profile': p.toMap()});
  _cached = p;
  _cachedFor = Account.companyId;
  final diff = fieldChanges(before.toMap(), p.toMap(), const {
    'legalName': 'Name on invoices',
    'address': 'Address',
    'phone': 'Phone',
    'email': 'Email',
    'ntn': 'NTN',
    'strn': 'STRN',
    'invoiceNote': 'Invoice note',
    'taxEnabled': 'Sales tax on',
    'taxRate': 'Tax rate %',
    'taxInclusive': 'Prices include tax',
  });
  if (diff.isNotEmpty) {
    await logAudit(area: AuditArea.books, action: AuditAction.edit, refId: 'profile', title: 'Company details and tax', changes: diff);
  }
}
