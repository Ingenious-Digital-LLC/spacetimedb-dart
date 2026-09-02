/// Main database schema model for SpacetimeDB
library;

import 'type_models.dart';
import 'table_models.dart';
import 'reducer_models.dart';
import 'view_models.dart';

class DatabaseSchema {
  final String databaseName;
  final TypeSpace typeSpace;
  final List<TableSchema> tables;
  final List<ReducerSchema> reducers;
  final List<TypeDef> types;
  final List<ViewSchema> views;

  DatabaseSchema({
    required this.databaseName,
    required this.typeSpace,
    required this.tables,
    required this.reducers,
    required this.types,
    required this.views,
  });

  /// Parses the JSON produced by `spacetime describe --json`.
  ///
  /// SpacetimeDB has shipped two incompatible shapes for this output:
  ///
  /// - Legacy (pre-2.8-ish): a flat object with `tables`, `reducers`,
  ///   `types`, `typespace`, and `misc_exports` keys directly on the root.
  /// - SpacetimeDB 2.8+: `{"sections": [{"Typespace": ...}, {"Types": [...]},
  ///   {"Tables": [...]}, {"Reducers": [...]}, {"Procedures": [...]},
  ///   {"ExplicitNames": {...}}, ...]}` — each section is a single-key
  ///   object tagging its variant.
  ///
  /// Both are accepted. A shape that matches neither throws a
  /// [FormatException] naming what was found, rather than silently
  /// returning an empty schema (the bug this fixes: the legacy parser's
  /// `is List` checks all failed against 2.8+ output and produced 0
  /// tables/reducers/types/views with no error at all).
  factory DatabaseSchema.fromJson(String dbName, Map<String, dynamic> json) {
    final sectionsJson = json['sections'];
    if (sectionsJson is List) {
      return _fromSections(dbName, sectionsJson);
    }

    final hasLegacyKeys = json.containsKey('tables') ||
        json.containsKey('reducers') ||
        json.containsKey('types') ||
        json.containsKey('typespace');
    if (hasLegacyKeys) {
      return _fromLegacyFlat(dbName, json);
    }

    throw FormatException(
      'Unrecognized SpacetimeDB describe schema: expected a top-level '
      '"sections" array (SpacetimeDB 2.8+) or one of '
      '"tables"/"reducers"/"types"/"typespace" (legacy). Got top-level '
      'keys: ${json.keys.toList()}',
    );
  }

  static DatabaseSchema _fromLegacyFlat(
      String dbName, Map<String, dynamic> json) {
    final tablesJson = json['tables'];
    final reducersJson = json['reducers'];
    final typesJson = json['types'];
    final miscExportsJson = json['misc_exports'];

    return DatabaseSchema(
      databaseName: dbName,
      typeSpace: TypeSpace.fromJson(json['typespace'] ?? {}),
      tables: tablesJson is List
          ? tablesJson.map((t) => TableSchema.fromJson(t)).toList()
          : [],
      reducers: reducersJson is List
          ? reducersJson.map((r) => ReducerSchema.fromJson(r)).toList()
          : [],
      types: typesJson is List
          ? typesJson.map((t) => TypeDef.fromJson(t)).toList()
          : [],
      views: _viewsFromMiscExports(miscExportsJson),
    );
  }

  static DatabaseSchema _fromSections(
      String dbName, List<dynamic> sectionsJson) {
    Map<String, dynamic>? typespaceJson;
    List<dynamic>? typesJson;
    List<dynamic>? tablesJson;
    List<dynamic>? reducersJson;
    // Views are not yet observed in a real SpacetimeDB 2.8+ "sections"
    // describe output from any module we've generated against (our fixture
    // module has none). We accept either a "MiscExports" section (matching
    // the legacy `misc_exports` key, PascalCase per the section-tag
    // convention) or a "Views" section, parsed the same way the legacy
    // shape parses `misc_exports`. This is best-effort until a fixture with
    // real views is available — see test/fixtures for the tracking note.
    List<dynamic>? miscExportsJson;
    final foundTags = <String>[];

    for (final section in sectionsJson) {
      if (section is! Map<String, dynamic> || section.isEmpty) continue;
      final tag = section.keys.first;
      foundTags.add(tag);
      final value = section[tag];
      switch (tag) {
        case 'Typespace':
          if (value is Map<String, dynamic>) typespaceJson = value;
          break;
        case 'Types':
          if (value is List) typesJson = value;
          break;
        case 'Tables':
          if (value is List) tablesJson = value;
          break;
        case 'Reducers':
          if (value is List) reducersJson = value;
          break;
        case 'MiscExports':
        case 'Views':
          if (value is List) miscExportsJson = value;
          break;
        // 'Procedures' and 'ExplicitNames' sections exist in SpacetimeDB
        // 2.8+ describe output but this SDK does not model or generate
        // code for procedures; they are intentionally not parsed here.
      }
    }

    if (typespaceJson == null &&
        typesJson == null &&
        tablesJson == null &&
        reducersJson == null) {
      throw FormatException(
        'SpacetimeDB describe "sections" array did not contain any of the '
        'expected Typespace/Types/Tables/Reducers sections. Found section '
        'tags: $foundTags',
      );
    }

    return DatabaseSchema(
      databaseName: dbName,
      typeSpace: TypeSpace.fromJson(typespaceJson ?? {}),
      tables: (tablesJson ?? [])
          .map((t) => TableSchema.fromJson(t))
          .toList(),
      reducers: (reducersJson ?? [])
          .map((r) => ReducerSchema.fromJson(r))
          .toList(),
      types: (typesJson ?? []).map((t) => TypeDef.fromJson(t)).toList(),
      views: _viewsFromMiscExports(miscExportsJson),
    );
  }

  static List<ViewSchema> _viewsFromMiscExports(dynamic miscExportsJson) {
    if (miscExportsJson is! List) return [];
    final views = <ViewSchema>[];
    for (final item in miscExportsJson) {
      if (item is Map<String, dynamic> && item.containsKey('View')) {
        views.add(ViewSchema.fromJson(item['View']));
      }
    }
    return views;
  }
}
