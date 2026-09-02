
import 'type_models.dart';

class ViewSchema {
  final String name;
  final int index;
  final bool isPublic;
  final bool isAnonymous;
  final ProductType params;
  final Map<String, dynamic> returnType;

  ViewSchema({
    required this.name,
    required this.index,
    required this.isPublic,
    required this.isAnonymous,
    required this.params,
    required this.returnType,
  });

  factory ViewSchema.fromJson(Map<String, dynamic> json) {
    return ViewSchema(
      // Best-effort: no real SpacetimeDB 2.8+ "sections" describe output
      // with a view has been observed yet (see
      // test/fixtures/asteria_describe_2.8.3.json's tracking note), so this
      // mirrors the source_name/name fallback used elsewhere pending a real
      // fixture.
      name: json['source_name'] ?? json['name'] ?? '',
      index: json['index'] ?? 0,
      isPublic: json['is_public'] ?? false,
      isAnonymous: json['is_anonymous'] ?? false,
      params: ProductType.fromJson(json['params'] ?? {}),
      returnType: json['return_type'] ?? {},
    );
  }
}
