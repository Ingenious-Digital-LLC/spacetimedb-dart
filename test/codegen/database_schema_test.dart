// Regression coverage for the SpacetimeDB 2.8+ `sections` describe shape.
//
// Before this fix, DatabaseSchema.fromJson only understood a flat legacy
// shape (`tables`/`reducers`/`types`/`typespace` keys directly on the root
// object). SpacetimeDB 2.8.3's `spacetime describe --json` instead emits
// `{"sections": [{"Typespace": ...}, {"Types": [...]}, {"Tables": [...]},
// {"Reducers": [...]}, {"Procedures": [...]}, {"ExplicitNames": {...}}]}`.
// None of the legacy parser's `is List` checks matched that shape, so it
// silently returned an empty schema (0 tables, 0 reducers, 0 types, 0
// views) instead of erroring — the generator then reported success with
// nothing generated. See the fixture file's header comment for provenance.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:spacetimedb/src/codegen/models/database_schema.dart';
import 'test_helpers.dart';

Map<String, dynamic> _loadFixture(String name) {
  final root = findSdkRoot();
  final file = File('$root/test/fixtures/$name');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  group('DatabaseSchema.fromJson — SpacetimeDB 2.8+ sections shape', () {
    late Map<String, dynamic> json;

    setUpAll(() {
      json = _loadFixture('asteria_describe_2.8.3.json');
    });

    test('parses the real Asteria module describe output without error',
        () {
      final schema = DatabaseSchema.fromJson('asteria-flutter-spike', json);

      expect(schema.tables, hasLength(1));
      expect(schema.reducers, hasLength(2));
    });

    test('reads correct table name from `source_name`', () {
      final schema = DatabaseSchema.fromJson('asteria-flutter-spike', json);
      expect(schema.tables.single.name, 'birth_profile');
    });

    test('reads correct reducer names from `source_name`', () {
      final schema = DatabaseSchema.fromJson('asteria-flutter-spike', json);
      final names = schema.reducers.map((r) => r.name).toSet();
      expect(
        names,
        equals({'save_birth_profile', 'save_birth_profile_with_house_method'}),
      );
    });

    test('reducer params still parse per-field names and types', () {
      final schema = DatabaseSchema.fromJson('asteria-flutter-spike', json);
      final saveWithMethod = schema.reducers
          .firstWhere((r) => r.name == 'save_birth_profile_with_house_method');
      final paramNames =
          saveWithMethod.params.elements.map((e) => e.name).toList();
      expect(
        paramNames,
        equals([
          'local_date',
          'place_label',
          'latitude_e6',
          'longitude_e6',
          'timezone',
          'time_confidence',
          'local_minute_of_day',
          'uncertainty_minutes',
          'fold',
          'house_method_id',
          'commit_token',
        ]),
      );
    });

    test('typespace parses non-empty', () {
      final schema = DatabaseSchema.fromJson('asteria-flutter-spike', json);
      expect(schema.typeSpace.types, isNotEmpty);
    });

    test('types parse with correct names from `source_name`', () {
      final schema = DatabaseSchema.fromJson('asteria-flutter-spike', json);
      expect(schema.types, isNotEmpty);
      expect(schema.types.every((t) => t.name.isNotEmpty), isTrue,
          reason: 'every parsed type should have a non-empty name');
    });

    // This module declares no views, and no "Views" section appears in its
    // describe output at all — a real absence, not a parse failure.
    // See the `asteria_module_views_describe.json` group below for real
    // views coverage.
    test('views parse as empty when the module declares none', () {
      final schema = DatabaseSchema.fromJson('asteria-flutter-spike', json);
      expect(schema.views, isEmpty);
    });

    test('an unrecognized top-level shape throws, never returns an empty schema',
        () {
      expect(
        () => DatabaseSchema.fromJson('whatever', {'unexpected_key': 123}),
        throwsFormatException,
      );
    });

    test(
        'a sections array with none of the expected tags throws, never returns an empty schema',
        () {
      expect(
        () => DatabaseSchema.fromJson('whatever', {
          'sections': [
            {'SomethingElseEntirely': []}
          ]
        }),
        throwsFormatException,
      );
    });
  });

  group('DatabaseSchema.fromJson — SpacetimeDB 2.8+ Views section', () {
    // asteria_module_views_describe.json is real describe output from a
    // module that declares two public views. See its README: the "Views"
    // section holds bare ViewSchema-shaped objects, NOT wrapped in
    // `{"View": {...}}` the way legacy `misc_exports` wraps them. An
    // earlier "best-effort" version of this parser assumed the wrapped
    // shape by analogy and would have silently produced an empty views
    // list against this exact fixture — these tests guard against that
    // regressing.
    late Map<String, dynamic> json;

    setUpAll(() {
      json = _loadFixture('asteria_module_views_describe.json');
    });

    test('parses both public views from the real Views section', () {
      final schema = DatabaseSchema.fromJson('asteria-local', json);

      expect(schema.views, hasLength(2));
      expect(
        schema.views.map((v) => v.name).toSet(),
        equals({'my_birth_profiles', 'my_natal_charts'}),
      );
    });

    test('views read `is_public` correctly', () {
      final schema = DatabaseSchema.fromJson('asteria-local', json);
      expect(schema.views.every((v) => v.isPublic), isTrue,
          reason: 'both views in this fixture are declared public');
    });

    test('tables and reducers still parse alongside views', () {
      final schema = DatabaseSchema.fromJson('asteria-local', json);

      expect(
        schema.tables.map((t) => t.name).toSet(),
        equals({'birth_profile', 'natal_chart_result'}),
      );
      expect(
        schema.reducers.map((r) => r.name).toSet(),
        equals({
          'compute_natal_chart',
          'delete_birth_profile',
          'save_birth_profile',
          'save_birth_profile_with_house_method',
        }),
      );
    });
  });

  group('DatabaseSchema.fromJson — legacy flat shape still works', () {
    test('parses tables/reducers/types/typespace directly on the root', () {
      final json = {
        'typespace': {
          'types': [],
        },
        'types': [],
        'tables': [
          {'name': 'notes', 'product_type_ref': 0, 'primary_key': [0]},
        ],
        'reducers': [
          {
            'name': 'create_note',
            'params': {'elements': []},
          },
        ],
        'misc_exports': [],
      };

      final schema = DatabaseSchema.fromJson('legacy-db', json);

      expect(schema.tables, hasLength(1));
      expect(schema.tables.single.name, 'notes');
      expect(schema.reducers, hasLength(1));
      expect(schema.reducers.single.name, 'create_note');
      expect(schema.views, isEmpty);
    });

    test('parses views from misc_exports on the legacy shape', () {
      // Round-trip through jsonEncode/jsonDecode so nested map literals get
      // real Map<String, dynamic> typing, matching how this JSON actually
      // arrives in production (via jsonDecode of `spacetime describe`'s
      // stdout) rather than Dart's local literal-inference quirks.
      final json = jsonDecode(jsonEncode({
        'typespace': {'types': []},
        'types': [],
        'tables': [],
        'reducers': [],
        'misc_exports': [
          {
            'View': {
              'name': 'my_view',
              'index': 0,
              'is_public': true,
              'is_anonymous': false,
              'params': {'elements': []},
              'return_type': {},
            },
          },
        ],
      })) as Map<String, dynamic>;

      final schema = DatabaseSchema.fromJson('legacy-db', json);

      expect(schema.views, hasLength(1));
      expect(schema.views.single.name, 'my_view');
    });
  });
}
