import 'models/type_models.dart';

class TypeMapper {
  // Type mappings
  static const _dartTypeMap = {
    'U8': 'int',
    'U16': 'int',
    'U32': 'int',
    'U64': 'Int64',
    'I8': 'int',
    'I16': 'int',
    'I32': 'int',
    'I64': 'Int64',
    'F32': 'double',
    'F64': 'double',
    'Bool': 'bool',
    'String': 'String',
    'Timestamp': 'Int64',
  };

  static const _encoderMethodMap = {
    'U8': 'writeU8',
    'U16': 'writeU16',
    'U32': 'writeU32',
    'U64': 'writeU64',
    'I8': 'writeI8',
    'I16': 'writeI16',
    'I32': 'writeI32',
    'I64': 'writeI64',
    'F32': 'writeF32',
    'F64': 'writeF64',
    'Bool': 'writeBool',
    'String': 'writeString',
    'Timestamp': 'writeU64',
  };

  static const _decoderMethodMap = {
    'U8': 'readU8',
    'U16': 'readU16',
    'U32': 'readU32',
    'U64': 'readU64',
    'I8': 'readI8',
    'I16': 'readI16',
    'I32': 'readI32',
    'I64': 'readI64',
    'F32': 'readF32',
    'F64': 'readF64',
    'Bool': 'readBool',
    'String': 'readString',
    'Timestamp': 'readU64',
  };

  /// Map algebraic type to Dart type string
  /// Pass typeSpace and typeDefs to resolve Ref types
  static String toDartType(
    Map<String, dynamic> algebraicType, {
    TypeSpace? typeSpace,
    List<TypeDef>? typeDefs,
  }) {
    final optionInnerType = getOptionInnerType(
      algebraicType,
      typeSpace: typeSpace,
      typeDefs: typeDefs,
    );
    if (optionInnerType != null) {
      final innerDartType = toDartType(
        optionInnerType,
        typeSpace: typeSpace,
        typeDefs: typeDefs,
      );
      return '$innerDartType?';
    }

    if (isIdentityType(
      algebraicType,
      typeSpace: typeSpace,
      typeDefs: typeDefs,
    )) {
      return 'Identity';
    }

    if (isScheduleAtType(algebraicType, typeSpace: typeSpace)) {
      return 'dynamic';
    }

    // 1. Handle Timestamp (Product with __timestamp_micros_since_unix_epoch__)
    if (algebraicType.containsKey('Product')) {
      final product = algebraicType['Product'];
      if (product is Map && product.containsKey('elements')) {
        final elements = product['elements'] as List;
        if (elements.length == 1) {
          final element = elements[0];
          if (element['name'] != null &&
              element['name']['some'] ==
                  '__timestamp_micros_since_unix_epoch__') {
            return 'Int64';
          }
        }
      }
    }

    if (algebraicType.containsKey('Ref')) {
      final typeIndex = algebraicType['Ref'] as int;

      if (typeSpace != null && typeDefs != null) {
        final typeDef = typeDefs.firstWhere(
          (td) => td.typeRef == typeIndex,
          orElse: () =>
              TypeDef(scope: [], name: '', typeRef: -1, customOrdering: false),
        );

        if (typeDef.name.isNotEmpty) {
          return _toPascalCase(typeDef.name);
        }
      }

      return 'dynamic';
    }

    // 2. Handle Array types (recursive)
    if (algebraicType.containsKey('Array')) {
      final elementType = algebraicType['Array'];
      final dartInnerType = toDartType(
        elementType,
        typeSpace: typeSpace,
        typeDefs: typeDefs,
      );
      return 'List<$dartInnerType>';
    }

    // 3. Handle primitive types
    for (final key in _dartTypeMap.keys) {
      if (algebraicType.containsKey(key)) {
        return _dartTypeMap[key]!;
      }
    }

    return 'dynamic';
  }

  static String getEncoderMethod(Map<String, dynamic> algebraicType) {
    // Handle Timestamp
    if (algebraicType.containsKey('Product')) {
      final product = algebraicType['Product'];
      if (product is Map && product.containsKey('elements')) {
        final elements = product['elements'] as List;
        if (elements.length == 1) {
          final element = elements[0];
          if (element['name'] != null &&
              element['name']['some'] ==
                  '__timestamp_micros_since_unix_epoch__') {
            return 'writeI64';
          }
        }
      }
    }

    for (final key in _encoderMethodMap.keys) {
      if (algebraicType.containsKey(key)) {
        return _encoderMethodMap[key]!;
      }
    }

    throw UnsupportedError('No encoder method for type: $algebraicType');
  }

  static String getDecoderMethod(Map<String, dynamic> algebraicType) {
    // Handle Timestamp
    if (algebraicType.containsKey('Product')) {
      final product = algebraicType['Product'];
      if (product is Map && product.containsKey('elements')) {
        final elements = product['elements'] as List;
        if (elements.length == 1) {
          final element = elements[0];
          if (element['name'] != null &&
              element['name']['some'] ==
                  '__timestamp_micros_since_unix_epoch__') {
            return 'readI64';
          }
        }
      }
    }

    for (final key in _decoderMethodMap.keys) {
      if (algebraicType.containsKey(key)) {
        return _decoderMethodMap[key]!;
      }
    }

    throw UnsupportedError('No decoder method for type: $algebraicType');
  }

  /// Get the full encode expression for a type, handling Array types
  /// (recursively, via writeArray with a callback) and Ref types (nested
  /// struct/enum values). For a Ref, which generated class method to call
  /// depends on which generator produced the referenced type: see
  /// [_refEncodeMethodName].
  ///
  /// Examples: 'encoder.writeU64(value)',
  /// 'encoder.writeArray<Int64>(value, (item) => encoder.writeU64(item))',
  /// 'value.encodeBsatn(encoder)'.
  static String getEncodeExpression(
    String valueName,
    Map<String, dynamic> algebraicType, {
    TypeSpace? typeSpace,
    List<TypeDef>? typeDefs,
  }) {
    if (isIdentityType(algebraicType, typeSpace: typeSpace, typeDefs: typeDefs)) {
      return 'encoder.writeBytes($valueName.bytes)';
    }

    if (algebraicType.containsKey('Array')) {
      final elementType =
          (algebraicType['Array'] as Map).cast<String, dynamic>();
      // Note: U8 arrays deliberately go through the generic per-element
      // writeArray loop below, not encoder.writeBytes(). writeBytes takes
      // no length argument on the encode side but BsatnDecoder.readBytes
      // requires an explicit length, which nothing here has read off the
      // wire — a mismatched pair would compile but decode wrong. The
      // per-element loop is self-delimiting (each array is length-prefixed
      // by writeArray/readArray) and matches toDartType's declared
      // `List<int>` for this shape. It's also byte-identical on the wire
      // to a direct writeBytes/readBytes pair: writeArray writes a u32
      // length then calls writeU8 per element (one byte, no per-element
      // framing), which is exactly `u32 length + raw bytes` — the same
      // layout BSATN's writeBytes/readBytes would produce. No overhead,
      // no wire-format change.
      final innerDartType = toDartType(
        elementType,
        typeSpace: typeSpace,
        typeDefs: typeDefs,
      );
      final innerExpr = getEncodeExpression(
        'item',
        elementType,
        typeSpace: typeSpace,
        typeDefs: typeDefs,
      );
      return 'encoder.writeArray<$innerDartType>($valueName, (item) => $innerExpr)';
    }

    if (isRefType(algebraicType)) {
      final method = _refEncodeMethodName(algebraicType, typeSpace);
      return '$valueName.$method(encoder)';
    }

    final method = getEncoderMethod(algebraicType);
    return 'encoder.$method($valueName)';
  }

  /// Get the full decode expression for a type. See [getEncodeExpression].
  /// Examples: 'decoder.readU64()',
  /// 'decoder.readArray<Int64>(() => decoder.readU64())',
  /// 'PlanetaryPositionWire.decodeBsatn(decoder)'.
  static String getDecodeExpression(
    Map<String, dynamic> algebraicType, {
    TypeSpace? typeSpace,
    List<TypeDef>? typeDefs,
  }) {
    if (isIdentityType(algebraicType, typeSpace: typeSpace, typeDefs: typeDefs)) {
      return 'Identity(decoder.readBytes(32))';
    }

    if (algebraicType.containsKey('Array')) {
      final elementType =
          (algebraicType['Array'] as Map).cast<String, dynamic>();
      // See the matching note in getEncodeExpression: U8 arrays use the
      // generic per-element readArray loop, not decoder.readBytes(), which
      // requires a length nothing here has read off the wire.
      final innerDartType = toDartType(
        elementType,
        typeSpace: typeSpace,
        typeDefs: typeDefs,
      );
      final innerExpr = getDecodeExpression(
        elementType,
        typeSpace: typeSpace,
        typeDefs: typeDefs,
      );
      return 'decoder.readArray<$innerDartType>(() => $innerExpr)';
    }

    if (isRefType(algebraicType)) {
      final typeName = toDartType(
        algebraicType,
        typeSpace: typeSpace,
        typeDefs: typeDefs,
      );
      final method = _refDecodeMethodName(algebraicType, typeSpace);
      return '$typeName.$method(decoder)';
    }

    final method = getDecoderMethod(algebraicType);
    return 'decoder.$method()';
  }

  /// Whether a Ref type resolves to a Sum (enum) type in the typespace.
  ///
  /// Every named type this SDK's generator gives its own file to is
  /// produced by exactly one of two generators, and they use different
  /// instance-method names:
  ///  - Sum (enum) types -> SumTypeGenerator -> plain `encode`/`decode`.
  ///  - Product (struct) types -> TableGenerator, whether backed by a real
  ///    table, a view's return type, or any other named struct -> always
  ///    `encodeBsatn`/`decodeBsatn`, never `encode`/`decode`.
  /// A Ref field's encode/decode call must match whichever of those two
  /// the referenced type actually got, or the generated code simply won't
  /// compile (the method it calls doesn't exist on the target class).
  static bool _refIsSumType(
    Map<String, dynamic> algebraicType,
    TypeSpace? typeSpace,
  ) {
    if (typeSpace == null || !algebraicType.containsKey('Ref')) return false;
    final typeIndex = algebraicType['Ref'] as int;
    if (typeIndex < 0 || typeIndex >= typeSpace.types.length) return false;
    return typeSpace.types[typeIndex].isSum;
  }

  static String _refEncodeMethodName(
    Map<String, dynamic> algebraicType,
    TypeSpace? typeSpace,
  ) {
    return _refIsSumType(algebraicType, typeSpace) ? 'encode' : 'encodeBsatn';
  }

  static String _refDecodeMethodName(
    Map<String, dynamic> algebraicType,
    TypeSpace? typeSpace,
  ) {
    return _refIsSumType(algebraicType, typeSpace) ? 'decode' : 'decodeBsatn';
  }

  static bool isIdentityType(
    Map<String, dynamic> algebraicType, {
    TypeSpace? typeSpace,
    List<TypeDef>? typeDefs,
  }) {
    if (_isIdentityProduct(algebraicType)) {
      return true;
    }

    if (algebraicType.containsKey('Ref') &&
        typeSpace != null &&
        typeDefs != null) {
      final typeIndex = algebraicType['Ref'] as int;
      final typeDef = typeDefs.firstWhere(
        (td) => td.typeRef == typeIndex,
        orElse: () =>
            TypeDef(scope: [], name: '', typeRef: -1, customOrdering: false),
      );

      if (typeDef.name.toLowerCase() == 'identity') {
        return true;
      }

      final resolved = _resolveRefType(algebraicType, typeSpace);
      if (resolved != null && _isIdentityProduct(resolved)) {
        return true;
      }
    }

    return false;
  }

  static Map<String, dynamic>? getOptionInnerType(
    Map<String, dynamic> algebraicType, {
    TypeSpace? typeSpace,
    List<TypeDef>? typeDefs,
  }) {
    final resolvedType = _resolveAlgebraicType(algebraicType, typeSpace);
    if (!resolvedType.containsKey('Sum')) {
      return null;
    }

    final sum = resolvedType['Sum'];
    if (sum is! Map<String, dynamic>) {
      return null;
    }

    final variants = sum['variants'];
    if (variants is! List || variants.length != 2) {
      return null;
    }

    final firstVariant = variants[0];
    final secondVariant = variants[1];
    if (firstVariant is! Map<String, dynamic> ||
        secondVariant is! Map<String, dynamic>) {
      return null;
    }

    final firstTypeRaw =
        (firstVariant['algebraic_type'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
    final secondTypeRaw =
        (secondVariant['algebraic_type'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
    final firstType = _resolveAlgebraicType(firstTypeRaw, typeSpace);
    final secondType = _resolveAlgebraicType(secondTypeRaw, typeSpace);

    Map<String, dynamic> noneType;
    Map<String, dynamic> someType;
    // someTypeRaw is the Some variant's algebraic_type as written, before
    // Ref resolution. Most of the logic below needs the resolved
    // (structural) shape to detect identity/unit/single-field-wrapper
    // patterns, but the final fallback (a Ref to an ordinary multi-field
    // struct, e.g. Option<SomeStruct>) must return the *unresolved* Ref
    // so callers like getEncodeExpression/getDecodeExpression can still
    // see it's a Ref and pick the right encodeBsatn/decodeBsatn or
    // encode/decode call — resolving it here would silently strip that
    // and hand back a bare structural Product no generator method knows
    // how to encode.
    Map<String, dynamic> someTypeRaw;
    if (_isUnitLike(firstType) && !_isUnitLike(secondType)) {
      noneType = firstType;
      someType = secondType;
      someTypeRaw = secondTypeRaw;
    } else if (_isUnitLike(secondType) && !_isUnitLike(firstType)) {
      noneType = secondType;
      someType = firstType;
      someTypeRaw = firstTypeRaw;
    } else {
      return null;
    }

    if (!_isUnitLike(noneType)) {
      return null;
    }

    if (someType.containsKey('Product')) {
      if (_isIdentityProduct(someType)) {
        return someType;
      }

      final product = someType['Product'];
      if (product is Map<String, dynamic>) {
        final elements = product['elements'];
        if (elements is List && elements.length == 1) {
          final element = elements[0];
          if (element is Map<String, dynamic>) {
            final inner = element['algebraic_type'];
            if (inner is Map<String, dynamic>) {
              return inner;
            }
          }
        }
      }
    }

    if (_isUnitLike(someType)) {
      return null;
    }

    // If the Some variant is a Ref (to a struct, enum, or anything else),
    // return the unresolved Ref itself rather than its resolved structural
    // shape — see the comment above someTypeRaw's declaration.
    if (someTypeRaw.containsKey('Ref')) {
      return someTypeRaw;
    }

    return someType;
  }

  static bool isScheduleAtType(
    Map<String, dynamic> algebraicType, {
    TypeSpace? typeSpace,
  }) {
    final resolvedType = _resolveAlgebraicType(algebraicType, typeSpace);
    if (!resolvedType.containsKey('Sum')) {
      return false;
    }

    final sum = resolvedType['Sum'];
    if (sum is! Map<String, dynamic>) {
      return false;
    }

    final variants = sum['variants'];
    if (variants is! List || variants.length != 2) {
      return false;
    }

    for (final variant in variants) {
      if (variant is! Map<String, dynamic>) {
        return false;
      }

      final variantType = _resolveAlgebraicType(
        (variant['algebraic_type'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{},
        typeSpace,
      );

      if (!_isI64Payload(variantType)) {
        return false;
      }
    }

    return true;
  }

  /// Check if a type is a Ref (reference to another type)
  static bool isRefType(Map<String, dynamic> algebraicType) {
    return algebraicType.containsKey('Ref');
  }

  /// Get the type name for a Ref type
  static String? getRefTypeName(
    Map<String, dynamic> algebraicType,
    List<TypeDef> typeDefs,
  ) {
    if (!isRefType(algebraicType)) return null;

    final typeIndex = algebraicType['Ref'] as int;
    final typeDef = typeDefs.firstWhere(
      (td) => td.typeRef == typeIndex,
      orElse: () =>
          TypeDef(scope: [], name: '', typeRef: -1, customOrdering: false),
    );

    return typeDef.name.isNotEmpty ? typeDef.name : null;
  }

  static String _toPascalCase(String input) {
    if (input.isEmpty) return input;
    return input[0].toUpperCase() + input.substring(1);
  }

  static Map<String, dynamic> _resolveAlgebraicType(
    Map<String, dynamic> algebraicType,
    TypeSpace? typeSpace,
  ) {
    final resolvedRef = _resolveRefType(algebraicType, typeSpace);
    return resolvedRef ?? algebraicType;
  }

  static Map<String, dynamic>? _resolveRefType(
    Map<String, dynamic> algebraicType,
    TypeSpace? typeSpace,
  ) {
    if (typeSpace == null || !algebraicType.containsKey('Ref')) {
      return null;
    }

    final typeIndex = algebraicType['Ref'] as int;
    if (typeIndex < 0 || typeIndex >= typeSpace.types.length) {
      return null;
    }

    final resolved = typeSpace.types[typeIndex];
    if (resolved.product != null) {
      return <String, dynamic>{
        'Product': <String, dynamic>{
          'elements': resolved.product!.elements.map((element) {
            return <String, dynamic>{
              'name': <String, dynamic>{'some': element.name ?? ''},
              'algebraic_type': element.algebraicType,
            };
          }).toList(),
        },
      };
    }

    if (resolved.sum != null) {
      return <String, dynamic>{
        'Sum': <String, dynamic>{
          'variants': resolved.sum!.variants.map((variant) {
            return <String, dynamic>{
              'name': <String, dynamic>{'some': variant.name ?? ''},
              'algebraic_type': variant.algebraicTypeJson,
            };
          }).toList(),
        },
      };
    }

    return null;
  }

  static bool _isIdentityProduct(Map<String, dynamic> algebraicType) {
    if (!algebraicType.containsKey('Product')) {
      return false;
    }

    final product = algebraicType['Product'];
    if (product is! Map<String, dynamic>) {
      return false;
    }

    final elements = product['elements'];
    if (elements is! List || elements.length != 1) {
      return false;
    }

    final element = elements.first;
    if (element is! Map<String, dynamic>) {
      return false;
    }

    final nameObj = element['name'];
    if (nameObj is! Map<String, dynamic>) {
      return false;
    }

    final name = nameObj['some'];
    if (name == '__identity_bytes' || name == '__identity__') {
      return true;
    }

    final inner = element['algebraic_type'];
    return inner is Map<String, dynamic> && inner.containsKey('U256');
  }

  static bool _isUnitLike(Map<String, dynamic> algebraicType) {
    if (algebraicType.isEmpty) {
      return true;
    }

    if (!algebraicType.containsKey('Product')) {
      return false;
    }

    final product = algebraicType['Product'];
    if (product is! Map<String, dynamic>) {
      return false;
    }

    final elements = product['elements'];
    return elements is List && elements.isEmpty;
  }

  static bool _isI64Payload(Map<String, dynamic> algebraicType) {
    if (algebraicType.containsKey('I64') || algebraicType.containsKey('U64')) {
      return true;
    }

    if (_isTimestamp(algebraicType)) {
      return true;
    }

    if (algebraicType.containsKey('Product')) {
      final product = algebraicType['Product'];
      if (product is! Map<String, dynamic>) {
        return false;
      }

      final elements = product['elements'];
      if (elements is! List || elements.length != 1) {
        return false;
      }

      final first = elements.first;
      if (first is! Map<String, dynamic>) {
        return false;
      }

      final inner = first['algebraic_type'];
      if (inner is! Map<String, dynamic>) {
        return false;
      }

      return inner.containsKey('I64') ||
          inner.containsKey('U64') ||
          _isTimestamp(inner);
    }

    return false;
  }

  static bool _isTimestamp(Map<String, dynamic> algebraicType) {
    if (!algebraicType.containsKey('Product')) {
      return false;
    }

    final product = algebraicType['Product'];
    if (product is! Map<String, dynamic>) {
      return false;
    }

    final elements = product['elements'];
    if (elements is! List || elements.length != 1) {
      return false;
    }

    final element = elements.first;
    if (element is! Map<String, dynamic>) {
      return false;
    }

    final nameObj = element['name'];
    return nameObj is Map<String, dynamic> &&
        nameObj['some'] == '__timestamp_micros_since_unix_epoch__';
  }
}
