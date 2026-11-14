// What each admin may open.
import 'package:an_agency/account/account.dart';
import 'package:flutter_test/flutter_test.dart';

AppUser _u(Role role, [Set<String>? sections]) =>
    AppUser(uid: 'u', companyId: 'c', role: role, status: UserStatus.active, name: '', email: '', sections: sections);

void main() {
  test('no list means everything, as before', () {
    expect(_u(Role.admin).can('accounts'), isTrue);
    expect(sectionsFrom(null), isNull);
  });

  test('a list limits an admin', () {
    final u = _u(Role.admin, sectionsFrom(['sales', 'stock']));
    expect(u.can('sales'), isTrue);
    expect(u.can('accounts'), isFalse);
    expect(_u(Role.admin, {}).can('sales'), isFalse); // dashboard only
  });

  test('the owner always opens everything', () {
    expect(_u(Role.owner, {'sales'}).can('accounts'), isTrue);
  });

  test('every section has a name the owner sees', () {
    expect(appSections.keys, ['sales', 'accounts', 'stock', 'customers', 'team']);
  });
}
