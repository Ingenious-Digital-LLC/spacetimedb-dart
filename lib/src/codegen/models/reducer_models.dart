/// Reducer schema models for SpacetimeDB
library;

import 'type_models.dart';

class ReducerSchema {
  final String name;
  final ProductType params;
  final Map<String, dynamic> lifecycle;

  ReducerSchema({
    required this.name,
    required this.params,
    required this.lifecycle,
  });

  factory ReducerSchema.fromJson(Map<String, dynamic> json) {
    return ReducerSchema(
      // SpacetimeDB 2.8+ describe output names this field `source_name`;
      // older output used `name`. Accept either.
      name: json['source_name'] ?? json['name'] ?? '',
      params: ProductType.fromJson(json['params'] ?? {}),
      lifecycle: json['lifecycle'] ?? {},
    );
  }
}
