import 'package:okf/okf.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('OkfYamlEmitter.scalar', () {
    const emitter = OkfYamlEmitter();

    test('writes safe strings plain and quotes the rest as JSON', () {
      const expected = <String, String>{
        'Revenue': 'Revenue',
        'finance-team': 'finance-team',
        'agent:okf/v2 @ 50%': 'agent:okf/v2 @ 50%',
        'https://example.com/a.md': 'https://example.com/a.md',
        '_private': '_private',
        '': '""',
        '2026-08-18': '"2026-08-18"',
        'True': '"True"',
        'off': '"off"',
        'a: b': '"a: b"',
        'ends:': '"ends:"',
        '#tag': '"#tag"',
        ' padded': '" padded"',
        'it\'s': '"it\'s"',
        'two\nlines': r'"two\nlines"',
        'Größe': '"Größe"',
      };

      for (final MapEntry(key: value, value: text) in expected.entries) {
        expect(emitter.scalar(value), text, reason: value);
        expect(loadYaml('key: ${emitter.scalar(value)}'), <String, Object?>{
          'key': value,
        }, reason: value);
      }
    });

    test('writes other scalars by type', () {
      expect(emitter.scalar(null), 'null');
      expect(emitter.scalar(true), 'true');
      expect(emitter.scalar(42), '42');
      expect(emitter.scalar(1.5), '1.5');
      expect(emitter.scalar(double.nan), '.nan');
      expect(emitter.scalar(double.negativeInfinity), '-.inf');
      expect(
        emitter.scalar(DateTime.utc(2026, 8, 18, 12)),
        '"2026-08-18T12:00:00.000Z"',
      );
    });

    test('is how emit writes a scalar value', () {
      for (final value in <Object?>['Revenue', 'a: b', 7, null, false]) {
        expect(
          emitter.emit(<String, Object?>{'key': value}),
          'key: ${emitter.scalar(value)}',
        );
      }
    });

    test('rejects collections', () {
      expect(
        () => emitter.scalar(const <Object?>['a']),
        throwsA(isA<OkfYamlEncodeException>()),
      );
      expect(
        () => emitter.scalar(const <String, Object?>{}),
        throwsA(isA<OkfYamlEncodeException>()),
      );
    });
  });
}
