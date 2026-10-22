import 'dart:io';

import 'package:okf/okf.dart';
import 'package:okf/src/yaml_emitter.dart' show okfYamlScalar;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('okfYamlScalar', () {
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
        expect(okfYamlScalar(value), text, reason: value);
        expect(loadYaml('key: ${okfYamlScalar(value)}'), <String, Object?>{
          'key': value,
        }, reason: value);
      }
    });

    test('writes other scalars by type', () {
      expect(okfYamlScalar(null), 'null');
      expect(okfYamlScalar(true), 'true');
      expect(okfYamlScalar(42), '42');
      expect(okfYamlScalar(1.5), '1.5');
      expect(okfYamlScalar(double.nan), '.nan');
      expect(okfYamlScalar(double.negativeInfinity), '-.inf');
      expect(
        okfYamlScalar(DateTime.utc(2026, 8, 18, 12)),
        '"2026-08-18T12:00:00.000Z"',
      );
    });

    test('is how emit writes a scalar value', () {
      for (final value in <Object?>['Revenue', 'a: b', 7, null, false]) {
        expect(
          emitter.emit(<String, Object?>{'key': value}),
          'key: ${okfYamlScalar(value)}',
        );
      }
    });

    test('rejects collections', () {
      expect(
        () => okfYamlScalar(const <Object?>['a']),
        throwsA(isA<OkfYamlEncodeException>()),
      );
      expect(
        () => okfYamlScalar(const <String, Object?>{}),
        throwsA(isA<OkfYamlEncodeException>()),
      );
    });

    test('stays out of the public library', () {
      // Its spelling is not a contract: hosts read the text a change writes
      // instead of predicting it (ADR-0010).
      expect(
        File('lib/okf.dart').readAsStringSync(),
        contains("export 'src/yaml_emitter.dart' hide okfYamlScalar;"),
      );
    });
  });
}
