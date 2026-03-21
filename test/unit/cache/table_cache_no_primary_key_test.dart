import 'dart:typed_data';

import 'package:spacetimedb/spacetimedb.dart';
import 'package:spacetimedb/src/cache/table_cache.dart';
import 'package:spacetimedb/src/events/event_context.dart';
import 'package:spacetimedb/src/messages/shared_types.dart';
import 'package:test/test.dart';

class NoPrimaryKeyRow {
  final int id;
  final String label;

  NoPrimaryKeyRow({
    required this.id,
    required this.label,
  });

  void encodeBsatn(BsatnEncoder encoder) {
    encoder.writeU32(id);
    encoder.writeString(label);
  }

  static NoPrimaryKeyRow decodeBsatn(BsatnDecoder decoder) {
    return NoPrimaryKeyRow(
      id: decoder.readU32(),
      label: decoder.readString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
      };

  static NoPrimaryKeyRow fromJson(Map<String, dynamic> json) {
    return NoPrimaryKeyRow(
      id: (json['id'] as int?) ?? 0,
      label: (json['label'] as String?) ?? '',
    );
  }
}

class NoPrimaryKeyRowDecoder extends RowDecoder<NoPrimaryKeyRow> {
  @override
  NoPrimaryKeyRow decode(BsatnDecoder decoder) {
    return NoPrimaryKeyRow.decodeBsatn(decoder);
  }

  @override
  dynamic getPrimaryKey(NoPrimaryKeyRow row) => null;

  @override
  Map<String, dynamic>? toJson(NoPrimaryKeyRow row) => row.toJson();

  @override
  NoPrimaryKeyRow? fromJson(Map<String, dynamic> json) {
    return NoPrimaryKeyRow.fromJson(json);
  }

  @override
  bool get supportsJsonSerialization => true;
}

BsatnRowList createRowList(List<NoPrimaryKeyRow> rows) {
  if (rows.isEmpty) return BsatnRowList.empty();

  final encodedRows = rows.map((row) {
    final encoder = BsatnEncoder();
    row.encodeBsatn(encoder);
    return encoder.toBytes();
  }).toList();

  final offsets = <int>[];
  var currentOffset = 0;

  for (final row in encodedRows) {
    offsets.add(currentOffset);
    currentOffset += row.length;
  }

  final combinedData = Uint8List(currentOffset);
  var writeOffset = 0;
  for (final row in encodedRows) {
    combinedData.setRange(writeOffset, writeOffset + row.length, row);
    writeOffset += row.length;
  }

  return BsatnRowList(
    sizeHint: RowSizeHint.rowOffsets(offsets),
    rowsData: combinedData,
  );
}

void main() {
  group('TableCache no primary key rows', () {
    late TableCache<NoPrimaryKeyRow> cache;

    setUp(() {
      cache = TableCache<NoPrimaryKeyRow>(
        tableId: 1,
        tableName: 'no_pk_view',
        decoder: NoPrimaryKeyRowDecoder(),
      );
    });

    tearDown(() => cache.dispose());

    test('transaction delete removes matching row by value when no PK exists',
        () {
      final subscribeContext = EventContext(
        myConnectionId: null,
        event: SubscribeAppliedEvent(),
      );
      final reducerContext = EventContext.optimistic(requestId: 'req-1');
      final row = NoPrimaryKeyRow(id: 42, label: 'live-match');

      cache.applyInitialData(createRowList([row]), subscribeContext);
      expect(cache.count(), equals(1));

      cache.applyTransactionUpdate(
        createRowList([row]),
        BsatnRowList.empty(),
        reducerContext,
      );

      expect(cache.count(), equals(0));
      expect(cache.iter(), isEmpty);
    });
  });
}
