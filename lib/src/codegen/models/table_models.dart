/// Table schema models for SpacetimeDB
library;

class TableSchema {
  final String name;
  final int productTypeRef;
  final List<int> primaryKey;
  final List<IndexSchema> indexes;
  final List<ConstraintSchema> constraints;
  final List<dynamic> sequences;
  final Map<String, dynamic> schedule;
  final Map<String, dynamic> tableType;
  final Map<String, dynamic> tableAccess;

  TableSchema({
    required this.name,
    required this.productTypeRef,
    required this.primaryKey,
    required this.indexes,
    required this.constraints,
    required this.sequences,
    required this.schedule,
    required this.tableType,
    required this.tableAccess,
  });

  factory TableSchema.fromJson(Map<String, dynamic> json) {
    final primaryKeyJson = json['primary_key'];
    final indexesJson = json['indexes'];
    final constraintsJson = json['constraints'];
    final sequencesJson = json['sequences'];

    return TableSchema(
      // SpacetimeDB 2.8+ describe output names this field `source_name`;
      // older output used `name`. Accept either.
      name: json['source_name'] ?? json['name'] ?? '',
      productTypeRef: json['product_type_ref'] ?? 0,
      primaryKey: primaryKeyJson is List
          ? primaryKeyJson.whereType<int>().toList()
          : [],
      indexes: indexesJson is List
          ? indexesJson.map((i) => IndexSchema.fromJson(i)).toList()
          : [],
      constraints: constraintsJson is List
          ? constraintsJson.map((c) => ConstraintSchema.fromJson(c)).toList()
          : [],
      sequences: sequencesJson is List ? List.from(sequencesJson) : [],
      schedule: json['schedule'] ?? {},
      tableType: json['table_type'] ?? {},
      tableAccess: json['table_access'] ?? {},
    );
  }
}

/// IndexSchema - table index definition
class IndexSchema {
  final String? name;
  final String? accessorName;
  final Map<String, dynamic> algorithm;

  IndexSchema({this.name, this.accessorName, required this.algorithm});

  factory IndexSchema.fromJson(Map<String, dynamic> json) {
    // SpacetimeDB 2.8+ describe output names this field `source_name`;
    // older output used `name`. Both wrap the value as an Option
    // (`{"some": "..."}` or absent/null for None) — guard against a
    // missing/null wrapper rather than throwing.
    final nameJson = json['source_name'] ?? json['name'];
    final accessorJson = json['accessor_name'];
    final indexName =
        (nameJson is Map<String, dynamic> ? nameJson['some'] : null) ?? "";
    final accessor =
        (accessorJson is Map<String, dynamic> ? accessorJson['some'] : null) ??
            "";

    return IndexSchema(
      name: indexName,
      accessorName: accessor,
      algorithm: json['algorithm'] ?? {},
    );
  }
}

/// ConstraintSchema - table constraint definition
class ConstraintSchema {
  final String? name;
  final Map<String, dynamic> data;

  ConstraintSchema({this.name, required this.data});

  factory ConstraintSchema.fromJson(Map<String, dynamic> json) {
    // SpacetimeDB 2.8+ describe output names this field `source_name`;
    // older output used `name`. Accept either, guarding against a
    // missing/null Option wrapper.
    final nameJson = json['source_name'] ?? json['name'];
    final constraintName =
        (nameJson is Map<String, dynamic> ? nameJson['some'] : null) ?? "";

    return ConstraintSchema(
      name: constraintName,
      data: json['data'] ?? {},
    );
  }
}
