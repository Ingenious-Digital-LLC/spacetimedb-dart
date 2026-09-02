import 'dart:typed_data';

import 'package:spacetimedb/spacetimedb.dart';
import 'package:test/test.dart';

void main() {
  group('Identity.fromHex', () {
    test('round-trips toHexString', () {
      final bytes = Uint8List.fromList(List.generate(32, (i) => (i * 7 + 3) & 0xff));
      final identity = Identity(bytes);
      final restored = Identity.fromHex(identity.toHexString);
      expect(restored, equals(identity));
      expect(restored.bytes, equals(bytes));
    });

    test('accepts upper-case digits and surrounding whitespace', () {
      final hex = '${'0A' * 31}ff';
      final identity = Identity.fromHex(' ${hex.toUpperCase()} ');
      expect(identity.bytes.first, 0x0a);
      expect(identity.bytes.last, 0xff);
    });

    test('rejects wrong lengths and non-hex input', () {
      expect(() => Identity.fromHex(''), throwsFormatException);
      expect(() => Identity.fromHex('ab' * 31), throwsFormatException);
      expect(() => Identity.fromHex('zz' * 32), throwsFormatException);
    });
  });
}
