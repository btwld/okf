import 'dart:collection';

import 'package:yaml/yaml.dart';

import 'document.dart';
import 'yaml_data.dart';
import 'yaml_emitter.dart';

/// Returns [source] rewritten so that it parses to [frontmatter] and, unless
/// [body] is null, to [body].
///
/// [OkfDocument.rewriteSource] documents the contract; this is its
/// implementation, which `okf.dart` does not export. [source] is null for a
/// document that was not parsed from text, which is written in canonical
/// form; [hasFrontmatter] says whether that document has a frontmatter
/// block.
String rewriteOkfDocumentSource(
  String? source,
  Map<String, Object?> frontmatter, {
  required String? body,
  required String currentBody,
  required bool hasFrontmatter,
  required OkfYamlEmitter emitter,
}) {
  final target = _normalizedMapping(frontmatter);
  if (source == null) {
    final writesFrontmatter = hasFrontmatter || target.isNotEmpty;
    final text = OkfDocument(
      frontmatter: target,
      body: body ?? currentBody,
      hasFrontmatter: writesFrontmatter,
    ).serialize(emitter: emitter);
    if (_readsBack(
      text,
      target,
      _canonicalBody(body ?? currentBody),
      hasFrontmatter: writesFrontmatter,
    )) {
      return text;
    }
    throw writesFrontmatter ? _unwritable(frontmatter) : _unwritableBody(text);
  }

  final original = OkfDocument.parse(source);
  final layout = _SourceLayout(source);
  final replacement = body == null ? null : _canonicalBody(body);
  final newBody =
      replacement == null || replacement == _canonicalBody(original.body)
      ? null
      : replacement;
  final expectedBody = newBody ?? original.body;

  if (!original.hasFrontmatter) {
    if (target.isEmpty) {
      final text = newBody == null ? source : layout.withLineEndings(newBody);
      if (_readsBack(text, target, expectedBody, hasFrontmatter: false)) {
        return text;
      }
      throw _unwritableBody(text);
    }
    // There is no block to edit, so one is written in front of the text. A
    // byte order mark that begins the kept text stays in front of it all.
    final mark = newBody == null && source.startsWith(_byteOrderMark)
        ? _byteOrderMark
        : '';
    final rest = newBody == null
        ? source.substring(mark.length)
        : layout.withLineEndings(newBody);
    final eol = layout.eol;
    final text =
        '$mark---$eol${layout.withLineEndings(emitter.emit(target))}$eol'
        '---$eol$eol$rest';
    if (_readsBack(text, target, expectedBody.substring(mark.length))) {
      return text;
    }
    throw _unwritable(frontmatter);
  }

  if (newBody == null && _sameYaml(original.frontmatter, target)) {
    return source;
  }

  final root = layout.yamlRoot();
  if (root == null || root is YamlMap && _editableRoot(root, layout)) {
    for (final nested in const <bool>[true, false]) {
      final String edited;
      try {
        edited = _InPlaceEdit(
          layout,
          emitter,
          nested: nested,
        ).apply(root as YamlMap?, original.frontmatter, target, newBody);
      } on _NotInPlace {
        continue;
      }
      if (_readsBack(edited, target, expectedBody)) {
        return edited;
      }
    }
  }

  final canonical = layout.withYaml(emitter.emit(target), newBody);
  if (_readsBack(canonical, target, expectedBody)) {
    return canonical;
  }
  throw _unwritable(frontmatter);
}

const String _byteOrderMark = '\uFEFF';

OkfYamlEncodeException _unwritable(Map<String, Object?> frontmatter) =>
    OkfYamlEncodeException(
      'The frontmatter cannot be written so that it reads back as the '
      'requested values.',
      frontmatter,
    );

/// The text of a document without frontmatter did not read back: its first
/// line reads as the `---` that opens a frontmatter block.
OkfYamlEncodeException _unwritableBody(String text) => OkfYamlEncodeException(
  'A body whose first line is a --- delimiter cannot be written without a '
  'frontmatter block, because it would read back as one.',
  text,
);

/// Whether [text] parses to [frontmatter] and [body], with a frontmatter
/// block exactly when [hasFrontmatter] is true.
bool _readsBack(
  String text,
  Map<String, Object?> frontmatter,
  String body, {
  bool hasFrontmatter = true,
}) {
  try {
    final document = OkfDocument.parse(text);
    return document.hasFrontmatter == hasFrontmatter &&
        document.body == body &&
        _sameYaml(document.frontmatter, frontmatter);
  } on FormatException {
    return false;
  }
}

/// A block mapping whose entries can be located by span: one without
/// aliases, explicit `?` keys or keys that are collections.
///
/// An alias reads back the node it names, so its span is the anchored
/// node's; editing either place in the text would change the other value.
/// An explicit key's omitted value has its span on the next token, so its
/// entry's extent cannot be told from its spans.
bool _editableRoot(YamlMap root, _SourceLayout layout) {
  if (root.style != CollectionStyle.BLOCK) {
    return false;
  }
  final seen = HashSet<YamlNode>.identity();
  bool editable(YamlNode node) {
    if (!seen.add(node)) {
      return false;
    }
    if (node is YamlMap) {
      for (final MapEntry(:key, :value) in node.nodes.entries) {
        final keyNode = key as YamlNode;
        if (keyNode is! YamlScalar ||
            node.style == CollectionStyle.BLOCK &&
                layout
                    .yamlLine(keyNode.span.start.line)
                    .substring(0, keyNode.span.start.column)
                    .contains(RegExp('[^ -]'))) {
          return false;
        }
        if (!editable(keyNode) || !editable(value)) {
          return false;
        }
      }
    } else if (node is YamlList) {
      for (final item in node.nodes) {
        if (!editable(item)) {
          return false;
        }
      }
    }
    return true;
  }

  return editable(root);
}

/// The YAML data model a value is written as: dates become the strings the
/// emitter writes for them, and every other iterable a list.
Map<String, Object?> _normalizedMapping(Map<String, Object?> frontmatter) {
  final active = HashSet<Object>.identity();

  Object? normalized(Object? value, int depth) {
    if (depth > maximumYamlDepth) {
      throw OkfYamlEncodeException(
        'YAML data exceeds the supported nesting depth.',
        value,
      );
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is Map || value is Iterable && value is! String) {
      if (!active.add(value!)) {
        throw OkfYamlEncodeException(
          'Cyclic Dart collections cannot be emitted as YAML.',
          value,
        );
      }
      try {
        if (value is Map) {
          return <Object?, Object?>{
            for (final entry in value.entries)
              normalized(entry.key, depth + 1): normalized(
                entry.value,
                depth + 1,
              ),
          };
        }
        return <Object?>[
          for (final item in value as Iterable) normalized(item, depth + 1),
        ];
      } finally {
        active.remove(value);
      }
    }
    return value;
  }

  return <String, Object?>{
    for (final entry in frontmatter.entries)
      entry.key: normalized(entry.value, 1),
  };
}

/// YAML data equality: mappings compare without regard to key order, an
/// integer never equals a double, and NaN equals NaN.
bool _sameYaml(Object? left, Object? right) {
  if (left is Map && right is Map) {
    if (left.length != right.length) {
      return false;
    }
    for (final MapEntry(:key, :value) in left.entries) {
      final match = _matchingKey(right, key);
      if (!right.containsKey(match) || !_sameYaml(value, right[match])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (!_sameYaml(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }
  if (left is num && right is num) {
    if (left.isNaN && right.isNaN) {
      return true;
    }
    return left == right && (left is int) == (right is int);
  }
  return left == right;
}

/// The key of [map] that equals [key] as YAML data, or [key] itself when
/// none does.
///
/// A collection key equals another only by content, which Dart's map lookup
/// does not compare.
Object? _matchingKey(Map<Object?, Object?> map, Object? key) {
  if (map.containsKey(key) || key is! Map && key is! List) {
    return key;
  }
  for (final candidate in map.keys) {
    if (_sameYaml(key, candidate)) {
      return candidate;
    }
  }
  return key;
}

String _canonicalBody(String body) {
  final normalized = body.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  return normalized.isEmpty || normalized.endsWith('\n')
      ? normalized
      : '$normalized\n';
}

/// An in-place edit could not be made; the caller tries a coarser one.
final class _NotInPlace implements Exception {
  const _NotInPlace();
}

/// The lines of a document's text and where its frontmatter block lies.
///
/// Lines end at LF, CRLF or a lone CR, as [OkfDocument.parse] reads them,
/// and keep their own line breaks. Line 0 of the frontmatter's YAML is line
/// 1 of the text.
final class _SourceLayout {
  _SourceLayout(this.source) {
    var start = 0;
    for (var index = 0; index < source.length; index++) {
      final unit = source.codeUnitAt(index);
      if (unit != 0x0A && unit != 0x0D) {
        continue;
      }
      final crlf =
          unit == 0x0D &&
          index + 1 < source.length &&
          source.codeUnitAt(index + 1) == 0x0A;
      _starts.add(start);
      _ends.add(index);
      start = index + (crlf ? 2 : 1);
      if (crlf) {
        index++;
      }
    }
    _starts.add(start);
    _ends.add(source.length);
    eol = _starts.length > 1 ? source.substring(_ends[0], _starts[1]) : '\n';
    if (_line(0).trim() == '---') {
      for (var line = 1; line < _starts.length; line++) {
        if (_line(line).trim() == '---') {
          _closing = line;
          break;
        }
      }
    }
  }

  final String source;
  final List<int> _starts = <int>[];
  final List<int> _ends = <int>[];
  int? _closing;

  /// The line break the text's first line ends with, or LF for one line.
  late final String eol;

  String _line(int line) => source.substring(_starts[line], _ends[line]);

  int get _closingLine => _closing!;

  /// The number of lines between the frontmatter delimiters.
  int get yamlLineCount => _closingLine - 1;

  /// A line of the frontmatter's YAML, without its line break.
  String yamlLine(int line) => _line(line + 1);

  /// The offset at which a YAML line begins; the closing delimiter's line
  /// for [yamlLineCount].
  int lineStart(int line) => _starts[line + 1];

  /// The offset at which a YAML line's line break begins.
  int lineEnd(int line) => _ends[line + 1];

  /// The offset of a position in the frontmatter's YAML.
  int offset(_Position position) => lineStart(position.line) + position.column;

  /// The frontmatter's YAML node, or null when it holds no value.
  YamlNode? yamlRoot() {
    final text = <String>[
      for (var line = 0; line < yamlLineCount; line++) yamlLine(line),
    ].join('\n');
    if (text.trim().isEmpty) {
      return null;
    }
    final root = loadYamlNode(text);
    return root is YamlScalar && root.value == null ? null : root;
  }

  /// [text], whose lines end in LF, with this text's line breaks.
  String withLineEndings(String text) => text.replaceAll('\n', eol);

  /// The text with its frontmatter's YAML replaced by [yaml], and its body by
  /// [body] unless that is null.
  String withYaml(String yaml, String? body) => apply(<_Edit>[
    _Edit(
      lineStart(0),
      lineStart(yamlLineCount),
      yaml.isEmpty ? '' : '${withLineEndings(yaml)}$eol',
    ),
    ?bodyEdit(body),
  ]);

  /// Replaces everything after the closing delimiter with one blank line and
  /// [body], or nothing when [body] is null.
  _Edit? bodyEdit(String? body) {
    if (body == null) {
      return null;
    }
    final closing = _closingLine;
    final hasBreak = _starts.length > closing + 1;
    return _Edit(
      hasBreak ? _starts[closing + 1] : _ends[closing],
      source.length,
      '${hasBreak ? '' : eol}$eol${withLineEndings(body)}',
    );
  }

  /// Applies [edits], which must not overlap, to the text.
  ///
  /// Edits that start at the same offset apply insertions first, then in the
  /// order they were made.
  String apply(List<_Edit> edits) {
    final ordered =
        <(int, _Edit)>[
          for (var index = 0; index < edits.length; index++)
            (index, edits[index]),
        ]..sort((left, right) {
          final byStart = left.$2.start.compareTo(right.$2.start);
          if (byStart != 0) {
            return byStart;
          }
          final byKind = (left.$2.isInsertion ? 0 : 1).compareTo(
            right.$2.isInsertion ? 0 : 1,
          );
          return byKind != 0 ? byKind : left.$1.compareTo(right.$1);
        });
    final output = StringBuffer();
    var position = 0;
    for (final (_, edit) in ordered) {
      if (edit.start < position) {
        throw const _NotInPlace();
      }
      output
        ..write(source.substring(position, edit.start))
        ..write(edit.text);
      position = edit.end;
    }
    output.write(source.substring(position));
    return output.toString();
  }
}

/// A zero-based line and column in the frontmatter's YAML.
typedef _Position = ({int line, int column});

_Position _startOf(YamlNode node) =>
    (line: node.span.start.line, column: node.span.start.column);

_Position _endOf(YamlNode node) =>
    (line: node.span.end.line, column: node.span.end.column);

final class _Edit {
  const _Edit(this.start, this.end, this.text);

  final int start;
  final int end;
  final String text;

  bool get isInsertion => start == end;
}

/// One attempt at editing the frontmatter in place.
///
/// With [nested] it edits inside block mappings and block sequences;
/// without it, it replaces the whole value of each changed top-level key.
final class _InPlaceEdit {
  _InPlaceEdit(this.layout, this.emitter, {required this.nested});

  final _SourceLayout layout;
  final OkfYamlEmitter emitter;
  final bool nested;
  final List<_Edit> _edits = <_Edit>[];

  String get _eol => layout.eol;

  String apply(
    YamlMap? root,
    Map<String, Object?> before,
    Map<String, Object?> after,
    String? body,
  ) {
    if (root == null) {
      _insertLines(layout.yamlLineCount, <String>[
        for (final entry in after.entries)
          ..._entryLines(entry.key, entry.value, 0),
      ]);
    } else {
      _mapping(root, before, after);
    }
    final bodyEdit = layout.bodyEdit(body);
    if (bodyEdit != null) {
      _edits.add(bodyEdit);
    }
    return layout.apply(_edits);
  }

  void _mapping(
    YamlMap node,
    Map<Object?, Object?> before,
    Map<Object?, Object?> after,
  ) {
    final entries = <(YamlNode, YamlNode)>[
      for (final entry in node.nodes.entries)
        (entry.key as YamlNode, entry.value),
    ];
    final column = entries.first.$1.span.start.column;
    for (final (keyNode, valueNode) in entries) {
      final key = keyNode.value;
      if (!after.containsKey(key)) {
        _remove(keyNode, valueNode);
        continue;
      }
      final old = before[key];
      final value = after[key];
      if (!_sameYaml(old, value)) {
        _replaceValue(keyNode, valueNode, old, value, column);
      }
    }
    _insertLines(_end(entries.last.$2).line + 1, <String>[
      for (final entry in after.entries)
        if (!before.containsKey(entry.key))
          ..._entryLines(entry.key, entry.value, column),
    ]);
  }

  /// Removes an entry's own lines: from its key's line to its value's last.
  void _remove(YamlNode key, YamlNode value) {
    final line = key.span.start.line;
    if (layout
        .yamlLine(line)
        .substring(0, key.span.start.column)
        .trim()
        .isNotEmpty) {
      // The line also holds the `-` of the sequence item this mapping is.
      throw const _NotInPlace();
    }
    _edits.add(
      _Edit(layout.lineStart(line), layout.lineStart(_end(value).line + 1), ''),
    );
  }

  void _replaceValue(
    YamlNode key,
    YamlNode value,
    Object? old,
    Object? replacement,
    int column,
  ) {
    if (_editInside(value, old, replacement) ||
        _replaceInline(value, replacement)) {
      return;
    }
    // Re-emit the value after the key, through the end of its last line.
    final inline = _inline(replacement);
    _edits.add(
      _Edit(
        layout.offset(_endOf(key)),
        layout.lineEnd(_end(value).line),
        inline != null
            ? ': $inline'
            : ':$_eol${_blockLines(replacement, column + 2).join(_eol)}',
      ),
    );
  }

  /// Edits a block collection's own entries or items, keeping the rest.
  bool _editInside(YamlNode node, Object? old, Object? replacement) {
    if (!nested) {
      return false;
    }
    if (node is YamlMap &&
        node.style == CollectionStyle.BLOCK &&
        old is Map &&
        replacement is Map &&
        replacement.isNotEmpty) {
      _mapping(node, old, replacement);
      return true;
    }
    if (node is YamlList &&
        node.style == CollectionStyle.BLOCK &&
        old is List &&
        replacement is List &&
        replacement.isNotEmpty) {
      return _sequence(node, old, replacement);
    }
    return false;
  }

  /// Replaces a one-line scalar or a flow collection by its span, keeping
  /// whatever shares its lines, such as a trailing comment.
  ///
  /// An omitted value is not replaced this way: its empty span lies on the
  /// `:` or `-` indicator before it.
  bool _replaceInline(YamlNode node, Object? replacement) {
    final String? text;
    if (node.span.length == 0) {
      text = null;
    } else if (node is YamlScalar) {
      text =
          node.style != ScalarStyle.LITERAL &&
              node.style != ScalarStyle.FOLDED &&
              node.span.start.line == node.span.end.line
          ? _inline(replacement)
          : null;
    } else if (node is YamlList && node.style == CollectionStyle.FLOW ||
        node is YamlMap && node.style == CollectionStyle.FLOW) {
      text = _flow(replacement);
    } else {
      text = null;
    }
    if (text == null) {
      return false;
    }
    _edits.add(
      _Edit(layout.offset(_startOf(node)), layout.offset(_endOf(node)), text),
    );
    return true;
  }

  bool _sequence(YamlList node, List<Object?> old, List<Object?> replacement) {
    final dash = node.span.start.column;
    if (!layout.yamlLine(node.span.start.line).startsWith('-', dash)) {
      throw const _NotInPlace();
    }
    final items = node.nodes;
    if (replacement.length > old.length &&
        _sameYaml(old, replacement.sublist(0, old.length))) {
      final compact = _isCompact(items.last);
      _insertLines(_end(items.last).line + 1, <String>[
        for (final item in replacement.skip(old.length))
          ..._itemLines(item, dash, compact: compact),
      ]);
      return true;
    }
    if (replacement.length != old.length) {
      return false;
    }
    for (var index = 0; index < items.length; index++) {
      if (!_sameYaml(old[index], replacement[index])) {
        _replaceItem(items[index], old[index], replacement[index], dash);
      }
    }
    return true;
  }

  void _replaceItem(YamlNode item, Object? old, Object? replacement, int dash) {
    if (_editInside(item, old, replacement) ||
        _replaceInline(item, replacement)) {
      return;
    }
    // An omitted item has an empty span on its `-`, so it is written after
    // the dash.
    final empty = item.span.length == 0;
    final column = empty ? dash + 2 : item.span.start.column;
    final inline = _inline(replacement);
    final String text;
    if (inline != null) {
      text = inline;
    } else {
      final lines = _blockLines(replacement, column);
      text = <String>[
        lines.first.substring(column),
        ...lines.skip(1),
      ].join(_eol);
    }
    _edits.add(
      _Edit(
        layout.offset(_startOf(item)) + (empty ? 1 : 0),
        layout.lineEnd(_end(item).line),
        empty ? ' $text' : text,
      ),
    );
  }

  /// Whether a sequence item starts on its `-` line, as in `- key: value`.
  bool _isCompact(YamlNode item) {
    if (item is! YamlMap && item is! YamlList) {
      return true;
    }
    final line = layout.yamlLine(item.span.start.line);
    return line.substring(0, item.span.start.column).trim() == '-';
  }

  void _insertLines(int line, List<String> lines) {
    if (lines.isEmpty) {
      return;
    }
    final offset = layout.lineStart(line);
    _edits.add(_Edit(offset, offset, '${lines.join(_eol)}$_eol'));
  }

  List<String> _entryLines(Object? key, Object? value, int column) {
    final indentation = ' ' * column;
    final inline = _inline(value);
    if (inline != null) {
      return <String>['$indentation${emitter.scalar(key)}: $inline'];
    }
    return <String>[
      '$indentation${emitter.scalar(key)}:',
      ..._blockLines(value, column + 2),
    ];
  }

  List<String> _itemLines(Object? value, int dash, {required bool compact}) {
    final indentation = ' ' * dash;
    final inline = _inline(value);
    if (inline != null) {
      return <String>['$indentation- $inline'];
    }
    final lines = _blockLines(value, dash + 2);
    if (!compact) {
      return <String>['$indentation-', ...lines];
    }
    return <String>[
      '$indentation- ${lines.first.substring(dash + 2)}',
      ...lines.skip(1),
    ];
  }

  /// The lines [OkfYamlEmitter.emit] writes for the non-empty collection
  /// [value] when it is nested at [indentation].
  ///
  /// `emit` writes a collection value on the lines after its key, two spaces
  /// in, and starts every such line with at least that indentation, since it
  /// writes each scalar on one line.
  List<String> _blockLines(Object? value, int indentation) {
    final lines = emitter
        .emit(<String, Object?>{'value': value})
        .split('\n')
        .skip(1);
    return <String>[
      for (final line in lines)
        indentation >= 2
            ? '${' ' * (indentation - 2)}$line'
            : line.substring(2 - indentation),
    ];
  }

  /// The one-line form of a scalar or an empty collection, or null.
  String? _inline(Object? value) {
    if (value is Map) {
      return value.isEmpty ? '{}' : null;
    }
    if (value is List) {
      return value.isEmpty ? '[]' : null;
    }
    return emitter.scalar(value);
  }

  /// The flow form of a collection of one-line values, or null.
  String? _flow(Object? value) {
    if (value is List) {
      final items = <String>[];
      for (final item in value) {
        final text = _inline(item);
        if (text == null) {
          return null;
        }
        items.add(text);
      }
      return '[${items.join(', ')}]';
    }
    if (value is Map) {
      final entries = <String>[];
      for (final entry in value.entries) {
        final text = _inline(entry.value);
        if (text == null) {
          return null;
        }
        entries.add('${emitter.scalar(entry.key)}: $text');
      }
      return '{${entries.join(', ')}}';
    }
    return null;
  }

  /// Where a node's own text ends: its last child's end for a block
  /// collection, and past the trailing blank lines a keeping (`+`) block
  /// scalar reads as content.
  ///
  /// The YAML's last line has no line break of its own, so a blank last line
  /// adds nothing to such a scalar and is not part of it.
  _Position _end(YamlNode node) {
    if (node is YamlMap &&
        node.style == CollectionStyle.BLOCK &&
        node.nodes.isNotEmpty) {
      return _end(node.nodes.values.last);
    }
    if (node is YamlList &&
        node.style == CollectionStyle.BLOCK &&
        node.nodes.isNotEmpty) {
      return _end(node.nodes.last);
    }
    var end = _endOf(node);
    if (node is YamlScalar &&
        (node.style == ScalarStyle.LITERAL ||
            node.style == ScalarStyle.FOLDED) &&
        node.span.text.split('\n').first.split('#').first.contains('+')) {
      while (end.line + 2 < layout.yamlLineCount &&
          layout.yamlLine(end.line + 1).trim().isEmpty) {
        end = (line: end.line + 1, column: 0);
      }
    }
    return end;
  }
}
