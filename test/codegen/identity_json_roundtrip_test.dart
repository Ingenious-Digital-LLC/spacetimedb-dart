// Regression coverage for Identity fields in generated fromJson factories.
//
// toJson serialises an Identity as `toHexString`, but the generated
// fromJson previously assigned `json['ownerIdentity']` (a String) straight
// to the Identity-typed constructor parameter. The offline cache therefore
// threw on every load after a relaunch, and callers that swallow the load
// error silently started with an empty cache.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:spacetimedb/src/codegen/models/database_schema.dart';
import 'package:spacetimedb/src/codegen/table_generator.dart';
import 'test_helpers.dart';

Map<String, dynamic> _loadFixture(String name) {
  final root = findSdkRoot();
  final file = File('$root/test/fixtures/$name');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  group('TableGenerator Identity JSON', () {
    late String generated;

    setUpAll(() {
      final schema = DatabaseSchema.fromJson(
        'asteria-flutter-spike',
        _loadFixture('asteria_describe_2.8.3.json'),
      );
      final table = schema.tables.singleWhere((t) => t.name == 'birth_profile');
      generated = TableGenerator(schema, table).generate();
    });

    test('toJson writes the identity as hex', () {
      expect(generated, contains("'ownerIdentity': ownerIdentity.toHexString,"));
    });

    test('fromJson restores the identity from hex, not as a raw String', () {
      expect(
        generated,
        contains("ownerIdentity: Identity.fromHex(json['ownerIdentity'] as String),"),
      );
      expect(generated, isNot(contains("ownerIdentity: json['ownerIdentity'],")));
    });
  });
}
