import 'dart:collection';
import 'dart:convert';

import 'utf8_text.dart';
import 'yaml_data.dart';

/// Preferred top-level frontmatter order used by OKF producer tooling.
///
/// Unknown keys are emitted after these keys in their original insertion
/// order. Ordering is presentational only and consumers must not depend on it.
const List<String> okfPreferredFrontmatterKeyOrder = <String>[
  'type',
  'resource',
  'title',
  'description',
  'tags',
  'status',
  'generated',
  'verified',
  'stale_after',
  'sources',
  'usage_window',
  'runtime',
  'parameters',
  'computation',
  'executor',
  'attester',
];

/// A value could not be represented by the deterministic YAML emitter.
final class OkfYamlEncodeException implements FormatException {
  /// Creates an encoding exception.
  const OkfYamlEncodeException(this.message, [this.source]);

  @override
  final String message;

  @override
  final Object? source;

  @override
  int? get offset => null;

  @override
  String toString() => 'OkfYamlEncodeException: $message';
}

/// Returns the text [OkfYamlEmitter] writes for the scalar [value].
///
/// The package's frontmatter rewriter writes this text for every scalar value
/// or key a concept edit changes or adds, except a string with a line break
/// that replaces a literal or folded block scalar, which it keeps a literal
/// block when it can. [OkfYamlEmitter.emit] writes a scalar value as
/// `key: <scalar>` and spells a mapping key the same way. `okf.dart` hides
/// this function: the spelling is not a public contract, and hosts read the
/// text a change writes rather than predict it.
///
/// A string is written plain, without quotes, when all of these hold:
///
/// * it starts with an ASCII letter or `_`;
/// * every other character is an ASCII letter, a digit, a space, or one of
///   `_ . / : @ + % -`;
/// * it has no leading or trailing whitespace, contains no `: ` and does
///   not end with `:`;
/// * ignoring case, it is none of `null`, `true`, `false`, `yes`, `no`,
///   `on`, `off`, `y`, `n`, `.nan` and `.inf`.
///
/// Any other string, including the empty string, is written as its JSON
/// string literal (`jsonEncode`), which YAML reads as the same double-quoted
/// string. So `Revenue` and `finance-team` stay plain, while `2026-08-18`,
/// `true`, `a: b` and `#tag` are written as `"2026-08-18"`, `"true"`,
/// `"a: b"` and `"#tag"`. A multi-line string is written on one line, with
/// `\n` escapes.
///
/// `null` is written as `null`, booleans as `true` and `false`, integers and
/// doubles by their `toString()` (with `.nan`, `.inf` and `-.inf` for the
/// non-finite doubles), and a [DateTime] as the JSON string literal of its
/// `toIso8601String()`, so it reads back as a string.
///
/// Throws [OkfYamlEncodeException] for a collection, any other value that is
/// not a scalar, and a string that holds an unpaired surrogate, which no YAML
/// text holds.
String okfYamlScalar(Object? value) {
  if (value is Map || value is Iterable && value is! String) {
    throw OkfYamlEncodeException(
      'Only scalar values have a scalar form; found ${value.runtimeType}.',
      value,
    );
  }
  return const OkfYamlEmitter()._scalar(value);
}

/// A small deterministic YAML emitter for values returned by `package:yaml`.
///
/// It intentionally does not try to preserve comments, anchors, aliases,
/// quoting style, or whitespace. It emits ordinary mappings, sequences, and
/// scalars in a canonical form that can be read by general YAML parsers.
/// A string that holds an unpaired surrogate has no such form, because YAML
/// text cannot hold one, so the emitter refuses it.
final class OkfYamlEmitter {
  /// Creates an emitter.
  const OkfYamlEmitter({
    this.preferredTopLevelKeys = okfPreferredFrontmatterKeyOrder,
  });

  /// Keys moved to the front of the root mapping, in this order.
  final List<String> preferredTopLevelKeys;

  /// Emits [frontmatter] without a trailing newline.
  ///
  /// Throws [OkfYamlEncodeException] for a value it cannot represent: an
  /// unsupported type, a cyclic collection, a non-scalar mapping key, more
  /// nodes than the supported limit, or a string that holds an unpaired
  /// surrogate, whether a key or a value.
  String emit(Map<String, Object?> frontmatter) {
    final output = StringBuffer();
    final state = _YamlEmissionState();
    _writeMapping(
      output,
      _orderedRootEntries(frontmatter),
      indentation: 0,
      state: state,
    );
    final result = output.toString();
    return result.endsWith('\n')
        ? result.substring(0, result.length - 1)
        : result;
  }

  Iterable<MapEntry<Object?, Object?>> _orderedRootEntries(
    Map<String, Object?> frontmatter,
  ) sync* {
    final emitted = <String>{};
    for (final key in preferredTopLevelKeys) {
      if (frontmatter.containsKey(key)) {
        emitted.add(key);
        yield MapEntry<Object?, Object?>(key, frontmatter[key]);
      }
    }
    for (final entry in frontmatter.entries) {
      if (emitted.add(entry.key)) {
        yield MapEntry<Object?, Object?>(entry.key, entry.value);
      }
    }
  }

  void _writeNode(
    StringBuffer output,
    Object? value, {
    required int indentation,
    required _YamlEmissionState state,
  }) {
    if (value is Map) {
      state.enter(value);
      try {
        _writeMapping(
          output,
          value.entries,
          indentation: indentation,
          state: state,
        );
      } finally {
        state.exit(value);
      }
      return;
    }
    if (value is Iterable && value is! String) {
      state.enter(value);
      try {
        _writeSequence(output, value, indentation: indentation, state: state);
      } finally {
        state.exit(value);
      }
      return;
    }
    output
      ..write(' ' * indentation)
      ..writeln(_scalar(value));
  }

  void _writeMapping(
    StringBuffer output,
    Iterable<MapEntry<Object?, Object?>> entries, {
    required int indentation,
    required _YamlEmissionState state,
  }) {
    for (final entry in entries) {
      state.countNode();
      output
        ..write(' ' * indentation)
        ..write(_key(entry.key))
        ..write(':');

      final value = entry.value;
      if (_isEmptyCollection(value) || _isScalar(value)) {
        output
          ..write(' ')
          ..writeln(_collectionOrScalar(value));
      } else {
        output.writeln();
        _writeNode(output, value, indentation: indentation + 2, state: state);
      }
    }
  }

  void _writeSequence(
    StringBuffer output,
    Iterable<Object?> values, {
    required int indentation,
    required _YamlEmissionState state,
  }) {
    for (final value in values) {
      state.countNode();
      output
        ..write(' ' * indentation)
        ..write('-');
      if (_isEmptyCollection(value) || _isScalar(value)) {
        output
          ..write(' ')
          ..writeln(_collectionOrScalar(value));
      } else {
        output.writeln();
        _writeNode(output, value, indentation: indentation + 2, state: state);
      }
    }
  }

  bool _isScalar(Object? value) =>
      value == null ||
      value is String ||
      value is num ||
      value is bool ||
      value is DateTime;

  bool _isEmptyCollection(Object? value) =>
      value is Map && value.isEmpty ||
      value is Iterable && value is! String && value.isEmpty;

  String _collectionOrScalar(Object? value) {
    if (value is Map && value.isEmpty) {
      return '{}';
    }
    if (value is Iterable && value is! String && value.isEmpty) {
      return '[]';
    }
    return _scalar(value);
  }

  String _key(Object? value) {
    if (value is String) {
      return _string(value);
    }
    if (value is Map || value is Iterable) {
      throw OkfYamlEncodeException(
        'YAML mapping keys must be scalar values.',
        value,
      );
    }
    return _scalar(value);
  }

  String _scalar(Object? value) {
    if (value == null) {
      return 'null';
    }
    if (value is bool) {
      return value ? 'true' : 'false';
    }
    if (value is int) {
      return value.toString();
    }
    if (value is double) {
      if (value.isNaN) {
        return '.nan';
      }
      if (value == double.infinity) {
        return '.inf';
      }
      if (value == double.negativeInfinity) {
        return '-.inf';
      }
      return value.toString();
    }
    if (value is num) {
      return value.toString();
    }
    if (value is DateTime) {
      return jsonEncode(value.toIso8601String());
    }
    if (value is String) {
      return _string(value);
    }
    throw OkfYamlEncodeException(
      'Unsupported YAML value of type ${value.runtimeType}.',
      value,
    );
  }

  String _string(String value) {
    // jsonEncode would write the surrogate as a `\ud800` escape, which YAML
    // parsers reject, so the emitted text would not read back.
    if (hasUnpairedSurrogate(value)) {
      throw OkfYamlEncodeException(
        'A string holds an unpaired surrogate, which YAML cannot represent.',
        value,
      );
    }
    if (_canUsePlainScalar(value)) {
      return value;
    }
    return jsonEncode(value);
  }

  bool _canUsePlainScalar(String value) {
    if (value.trim() != value || value.contains(': ') || value.endsWith(':')) {
      return false;
    }
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9 _./:@+%-]*$').hasMatch(value)) {
      return false;
    }
    final lowered = value.toLowerCase();
    return !const <String>{
      'null',
      'true',
      'false',
      'yes',
      'no',
      'on',
      'off',
      'y',
      'n',
      '.nan',
      '.inf',
    }.contains(lowered);
  }
}

final class _YamlEmissionState {
  final HashSet<Object> _active = HashSet<Object>.identity();
  var _nodes = 0;

  void countNode() {
    _nodes++;
    if (_nodes > maximumYamlNodes) {
      throw const OkfYamlEncodeException(
        'YAML output exceeds the supported node limit.',
      );
    }
  }

  void enter(Object value) {
    if (!_active.add(value)) {
      throw OkfYamlEncodeException(
        'Cyclic Dart collections cannot be emitted as YAML.',
        value,
      );
    }
  }

  void exit(Object value) {
    _active.remove(value);
  }
}
