// The generated client must gate token persistence on
// SpacetimeDbConnection.shouldAdoptIdentityToken; see
// test/unit/connection/identity_token_adoption_test.dart for why.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:spacetimedb/src/codegen/client_generator.dart';
import 'package:spacetimedb/src/codegen/models/database_schema.dart';
import 'test_helpers.dart';

void main() {
  test('generated client only persists identity tokens it should adopt', () {
    final root = findSdkRoot();
    final json = jsonDecode(
      File('$root/test/fixtures/asteria_describe_2.8.3.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final schema = DatabaseSchema.fromJson('asteria-flutter-spike', json);
    final code = ClientGenerator(schema).generate();

    expect(code, contains('subscriptionManager.onIdentityToken.listen((msg) async {'));
    expect(code, contains('if (!connection.shouldAdoptIdentityToken(msg.token)) return;'));
    final listener = code.indexOf('onIdentityToken.listen');
    final guard = code.indexOf('shouldAdoptIdentityToken');
    final save = code.indexOf('storage.saveToken(msg.token)');
    expect(listener, lessThan(guard));
    expect(guard, lessThan(save), reason: 'the guard must run before saveToken');
  });
}
