import 'dart:collection';

import 'package:yaml/yaml.dart';

import 'document.dart';
import 'yaml_data.dart';
import 'yaml_emitter.dart';

/// Edits a parsed document's text in place, keeping every byte a change does
/// not touch.
///
/// The change set's overlay edits existing concepts through it. `okf.dart`
/// does not export this library: the rewriter's layout rules are not a public
/// contract, and hosts read the text a change writes from its candidate.
extension OkfDocumentSourceRewrite on OkfDocument {
  /// Returns [OkfDocument.sourceText] edited so that it parses to
  /// [frontmatter] and, unless [body] is null, to [body], keeping the exact
  /// bytes of everything the edit does not change.
  ///
  /// [frontmatter] is the complete resulting mapping and defaults to this
  /// document's frontmatter; a key it lacks is removed. This document is
  /// not changed. Values compare as YAML data: mappings without regard to
  /// key order, an integer never equals a double, and a [DateTime] is the
  /// string of its `toIso8601String()`, which is how it is written.
  ///
  /// The frontmatter is edited in place:
  ///
  /// * A key whose value is unchanged keeps its bytes: its position, flow or
  ///   block style, quoting, comments and the blank lines around it.
  /// * A changed one-line scalar is replaced by its span. Whatever else
  ///   shares the line, such as a trailing comment, stays.
  /// * A changed literal (`|`) or folded (`>`) block scalar whose new value
  ///   is a string with a line break is written as a literal block at the
  ///   old block's indentation, keeping any comment on its header line: `|-`
  ///   for a string without a final line break, `|` for one, and `|+` for
  ///   more. A string without a line break is written as any other changed
  ///   value, and so is one that a literal block does not hold as written:
  ///   one whose first line is empty or starts with whitespace, that has a
  ///   line reading as a `---` delimiter, or that holds a C0 control
  ///   character other than tab and line feed, DEL, a C1 control character,
  ///   U+2028, U+2029, U+FEFF, U+FFFE, U+FFFF or an unpaired surrogate.
  /// * A changed flow collection stays a flow collection. A flow mapping
  ///   that keeps every key, or a flow sequence that does not get shorter,
  ///   has each changed value or item replaced by its span by these rules,
  ///   and each new entry, or each item past its old length, inserted
  ///   directly after the last one, after `, `; the rest of its text,
  ///   spacing and line breaks included, stays. Otherwise the whole
  ///   collection is replaced by its span with one line such as `[a, b]` or
  ///   `{key: value}`, which writes its unchanged entries in [okfYamlScalar]
  ///   spellings too. That also happens when a value to replace is omitted
  ///   (`{key}`) or spans lines, and when entries are added after a last
  ///   value that is omitted or is a plain scalar over several lines.
  /// * A changed block mapping is edited entry by entry, by these same rules.
  ///   A changed block sequence whose old items are a prefix of its new ones
  ///   gets the new items after its last item, in that item's style
  ///   (`- key: value`, or `-` on a line of its own); one whose length is
  ///   unchanged has each changed item edited by these rules.
  /// * Any other changed value is written after its key, replacing the old
  ///   value through the end of its last line, comments included: a scalar
  ///   or an empty collection as `key: <scalar>`, `key: []` or `key: {}`,
  ///   and a collection in the block style [OkfYamlEmitter.emit] uses.
  /// * A removed key removes only its own lines, from its key's line to its
  ///   value's last. Comment and blank lines around it stay.
  /// * A new key goes on the lines directly after the last entry of its
  ///   mapping, before any comment or blank lines that end the mapping, at
  ///   the indentation of the mapping's keys and in the order [frontmatter]
  ///   lists the new keys. In a frontmatter block with no entries it goes
  ///   directly before the closing `---`.
  ///
  /// Other than in those literal blocks, scalars and keys are written as
  /// [okfYamlScalar] writes them. New lines end with the line break of the
  /// document's first line, so a CRLF document stays CRLF, and the delimiter
  /// lines are kept.
  ///
  /// A canonical block stays canonical. When the frontmatter block holds
  /// exactly the lines [OkfYamlEmitter.emit] writes for its values, whatever
  /// their line breaks, as `okf format` leaves it, the block of a result
  /// that reads back is written the same way from the values it holds. That
  /// keeps every unchanged line and the order of nested keys, moves each new
  /// top-level key from after the last entry to its place in
  /// [OkfYamlEmitter.preferredTopLevelKeys], and writes a filled empty
  /// collection, which the rules above keep in flow style, in block style.
  /// So an edit never makes `okf format --check` fail on a file it passed.
  ///
  /// A [body] equal to this document's body once line endings are
  /// normalized and a final newline is added keeps the current bytes; any
  /// other is written in that canonical form, after one blank line, with the
  /// document's line break. So when the resulting frontmatter equals the
  /// current one the frontmatter block is byte-identical, and so is the whole
  /// text when the body is unchanged too.
  ///
  /// A byte order mark that begins the text stays there. With a frontmatter
  /// block it comes before the opening `---`. A document without one holds
  /// the mark in its body, as [OkfDocument.parse] reads it: it stays with
  /// that body, goes before the `---` of a block this call adds (the body
  /// then reads back without it), and goes with the body that [body]
  /// replaces.
  ///
  /// Every result is parsed again and must read back as [frontmatter] and
  /// the expected body. The edit is made in up to three ways, and the first
  /// whose result reads back is returned:
  ///
  /// 1. In place, by all the rules above.
  /// 2. In place at the top level only: each changed top-level value is
  ///    replaced whole, by its span when it is a one-line scalar or a flow
  ///    collection and otherwise after its key as for any other changed
  ///    value, with every scalar written as [okfYamlScalar] writes it.
  /// 3. Re-emitted: [OkfYamlEmitter.emit] writes the whole mapping between
  ///    the existing delimiter lines, in the emitter's canonical order
  ///    ([OkfYamlEmitter.preferredTopLevelKeys] first), so keys such as
  ///    `tags` move and comments inside the block are dropped.
  ///
  /// Step 1 gives up without a result, and step 2 runs, when it would remove
  /// the first key of a `- key: value` item, whose line holds the item's
  /// `-`; when a changed block sequence has a tag or anchor before its first
  /// `-`, where its span begins; or when two of its edits would overlap.
  /// Step 2 gives up for overlapping edits too. Step 3 runs without the
  /// others when the frontmatter is not a block mapping (for example a
  /// one-line `{type: Metric}`), uses a YAML alias, has a collection as a
  /// key at any depth, or has a key in a block mapping with anything but
  /// indentation and `-` indicators before it on its line, that is, an
  /// explicit `?` key. (A tag or anchor written before a key, as in
  /// `- !tag key: value`, starts that key's span, so it does not count.)
  ///
  /// Throws [OkfYamlEncodeException] when a value cannot be written as
  /// YAML, when even step 3 does not read back, or when a document without
  /// a frontmatter block would get a body whose first line reads as a `---`
  /// delimiter, which would read back as the start of one.
  ///
  /// A document without a frontmatter block gets one in front of its text
  /// when [frontmatter] is not empty. A document without
  /// [OkfDocument.sourceText] is written as [OkfDocument.serialize] writes
  /// it, and checked the same way.
  String rewriteSource({
    Map<String, Object?>? frontmatter,
    String? body,
    OkfYamlEmitter emitter = const OkfYamlEmitter(),
  }) => _rewriteSource(
    sourceText,
    frontmatter ?? this.frontmatter,
    body: body,
    currentBody: this.body,
    hasFrontmatter: hasFrontmatter,
    emitter: emitter,
  );
}

/// Returns [source] rewritten so that it parses to [frontmatter] and, unless
/// [body] is null, to [body].
///
/// [OkfDocumentSourceRewrite.rewriteSource] documents the contract. [source]
/// is null for a document that was not parsed from text, which is written in
/// canonical form; [hasFrontmatter] says whether that document has a
/// frontmatter block.
String _rewriteSource(
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

  // Canonical in, canonical out: an edit of a block `okf format` would leave
  // alone must not make `okf format --check` fail.
  final keepsCanonical = _isCanonicalBlock(
    layout,
    original.frontmatter,
    emitter,
  );

  // [text] when it reads back, in canonical form when the source block was
  // canonical; otherwise null.
  String? accepted(String text) {
    if (!_readsBack(text, target, expectedBody)) {
      return null;
    }
    if (!keepsCanonical) {
      return text;
    }
    final canonical = _canonicalized(text, emitter);
    return _readsBack(canonical, target, expectedBody) ? canonical : null;
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
      if (accepted(edited) case final text?) {
        return text;
      }
    }
  }

  if (accepted(layout.withYaml(emitter.emit(target), newBody))
      case final text?) {
    return text;
  }
  throw _unwritable(frontmatter);
}

/// Whether the frontmatter block of [layout] holds exactly the lines
/// [emitter] writes for [frontmatter], whatever their line breaks.
bool _isCanonicalBlock(
  _SourceLayout layout,
  Map<String, Object?> frontmatter,
  OkfYamlEmitter emitter,
) {
  final String yaml;
  try {
    yaml = emitter.emit(frontmatter);
  } on OkfYamlEncodeException {
    return false;
  }
  final lines = yaml.isEmpty ? const <String>[] : yaml.split('\n');
  if (lines.length != layout.yamlLineCount) {
    return false;
  }
  for (var line = 0; line < lines.length; line++) {
    if (layout.yamlLine(line) != lines[line]) {
      return false;
    }
  }
  return true;
}

/// [text] with its frontmatter block written as [emitter] writes the values
/// it holds, which keeps every line that already is.
///
/// For an edit of a canonical block, this moves a new top-level key from
/// after the last entry to its place in the preferred key order and writes a
/// filled empty collection, which an edit keeps in flow style, in block
/// style. Unchanged entries, and the order of nested keys, stay as they are.
String _canonicalized(String text, OkfYamlEmitter emitter) {
  final layout = _SourceLayout(text);
  final frontmatter = OkfDocument.parse(text).frontmatter;
  return _isCanonicalBlock(layout, frontmatter, emitter)
      ? text
      : layout.withYaml(emitter.emit(frontmatter), null);
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
/// aliases or keys that are collections, in which each key of a block
/// mapping has nothing but indentation and `-` indicators before it on its
/// line.
///
/// An alias reads back the node it names, so its span is the anchored
/// node's; editing either place in the text would change the other value.
/// An explicit `?` key's omitted value has its span on the next token, so
/// its entry's extent cannot be told from its spans; the `?` before a key is
/// what the indentation check finds. A tag or anchor written before a key,
/// as in `- !tag key: value`, passes it: `package:yaml` starts that key's
/// span at the tag, and keys are never rewritten in place.
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

final RegExp _lineBreak = RegExp('[\r\n]');

/// The `|` or `>` that starts a block scalar's header, with its chomping and
/// indentation indicators. A tag or anchor before it does not match.
final RegExp _blockScalarIndicators = RegExp('^[|>][-+0-9]*');

/// The chomping indicator and lines of a literal block without an
/// indentation indicator that reads back as [value], or null when there is
/// none.
///
/// The value needs a line break, a first line that starts with something
/// other than whitespace, no line that reads as a `---` delimiter (it would
/// close the frontmatter block), and only characters a YAML block scalar
/// holds as they are: no control character but tab and line feed, no
/// U+2028, U+2029 or U+FEFF, and no unpaired surrogate. Its final line
/// breaks choose the indicator: none is `-`, one is the default, and more
/// are `+`, with a line for each one after the first.
({String chomping, List<String> lines})? _literalBlock(String value) {
  if (!value.contains('\n') || value.startsWith(RegExp(r'\s'))) {
    return null;
  }
  for (final rune in value.runes) {
    if (rune < 0x20 && rune != 0x09 && rune != 0x0A ||
        rune >= 0x7F && rune <= 0x9F ||
        rune == 0x2028 ||
        rune == 0x2029 ||
        rune == 0xFEFF ||
        rune >= 0xD800 && rune <= 0xDFFF ||
        rune == 0xFFFE ||
        rune == 0xFFFF) {
      return null;
    }
  }
  final lines = value.split('\n');
  if (lines.any((line) => line.trim() == '---')) {
    return null;
  }
  var breaks = 0;
  while (breaks < lines.length - 1 &&
      lines[lines.length - 1 - breaks].isEmpty) {
    breaks++;
  }
  return (
    chomping: switch (breaks) {
      0 => '-',
      1 => '',
      _ => '+',
    },
    lines: breaks == 0 ? lines : lines.sublist(0, lines.length - 1),
  );
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
/// With [nested] it edits inside block and flow collections and keeps a
/// changed block scalar a literal block; without it, it replaces the whole
/// value of each changed top-level key and writes every scalar as
/// [okfYamlScalar] does.
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
        _replaceInline(value, replacement) ||
        _replaceBlockScalar(value, replacement)) {
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

  /// Edits a collection's own entries or items, keeping the rest: a block
  /// collection line by line, a flow collection by spans.
  bool _editInside(YamlNode node, Object? old, Object? replacement) {
    if (!nested) {
      return false;
    }
    if (node is YamlMap &&
        old is Map &&
        replacement is Map &&
        replacement.isNotEmpty) {
      if (node.style == CollectionStyle.BLOCK) {
        _mapping(node, old, replacement);
        return true;
      }
      return _flowMapping(node, old, replacement);
    }
    if (node is YamlList &&
        old is List &&
        replacement is List &&
        replacement.isNotEmpty) {
      return node.style == CollectionStyle.BLOCK
          ? _sequence(node, old, replacement)
          : _flowSequence(node, old, replacement);
    }
    return false;
  }

  /// Replaces a one-line scalar or a flow collection by its span, keeping
  /// whatever shares its lines, such as a trailing comment.
  ///
  /// A flow collection, and with [inFlow] any node inside one, takes the
  /// flow form of a collection; a scalar outside a flow collection takes
  /// only a scalar or an empty collection.
  bool _replaceInline(
    YamlNode node,
    Object? replacement, {
    bool inFlow = false,
  }) {
    final end = _textEnd(node);
    if (end == null) {
      return false;
    }
    final start = layout.offset(_startOf(node));
    final String? text;
    if (node is YamlScalar) {
      text =
          node.style == ScalarStyle.LITERAL ||
              node.style == ScalarStyle.FOLDED ||
              layout.source.substring(start, end).contains(_lineBreak)
          ? null
          : inFlow
          ? _flow(replacement)
          : _inline(replacement);
    } else if (node is YamlList && node.style == CollectionStyle.FLOW ||
        node is YamlMap && node.style == CollectionStyle.FLOW) {
      text = _flow(replacement);
    } else {
      text = null;
    }
    if (text == null) {
      return false;
    }
    _edits.add(_Edit(start, end, text));
    return true;
  }

  /// The offset at which a node's own text ends, or null when it cannot be
  /// told from its span.
  ///
  /// An omitted value has an empty span on the `:` or `-` indicator before
  /// it. A plain scalar's span inside a flow collection runs on over the
  /// whitespace and line breaks before the next `,` or bracket, which are not
  /// its text; for a plain scalar whose own text spans lines, where that
  /// text ends is not told apart from them.
  int? _textEnd(YamlNode node) {
    if (node.span.length == 0) {
      return null;
    }
    if (node is YamlScalar && node.style == ScalarStyle.PLAIN) {
      final text = node.span.text.trimRight();
      return text.contains('\n')
          ? null
          : layout.offset(_startOf(node)) + text.length;
    }
    return layout.offset(_endOf(node));
  }

  /// Edits a flow mapping by spans: each changed value where it stands, and
  /// each new entry after the last one as `, key: value`.
  ///
  /// Records nothing and returns false when an entry is removed, or when a
  /// changed value or the last one cannot be located by its span; the caller
  /// then replaces the whole mapping.
  bool _flowMapping(
    YamlMap node,
    Map<Object?, Object?> old,
    Map<Object?, Object?> replacement,
  ) {
    final entries = node.nodes.entries.toList();
    if (entries.isEmpty ||
        old.keys.any((key) => !replacement.containsKey(key))) {
      return false;
    }
    final mark = _edits.length;
    for (final MapEntry(:key, :value) in entries) {
      final name = (key as YamlNode).value;
      if (!_sameYaml(old[name], replacement[name]) &&
          !_replaceFlowItem(value, old[name], replacement[name])) {
        _edits.length = mark;
        return false;
      }
    }
    final added = <String>[
      for (final MapEntry(:key, :value) in replacement.entries)
        if (!old.containsKey(key)) '${okfYamlScalar(key)}: ${_flow(value)}',
    ];
    if (!_appendFlow(entries.last.value, added)) {
      _edits.length = mark;
      return false;
    }
    return true;
  }

  /// Edits a flow sequence by spans: each changed item where it stands, and
  /// each item added at its end after the last one as `, item`.
  ///
  /// Records nothing and returns false when the sequence gets shorter, or
  /// when a changed item or the last one cannot be located by its span.
  bool _flowSequence(
    YamlList node,
    List<Object?> old,
    List<Object?> replacement,
  ) {
    final items = node.nodes;
    if (items.isEmpty || replacement.length < old.length) {
      return false;
    }
    final mark = _edits.length;
    for (var index = 0; index < items.length; index++) {
      if (!_sameYaml(old[index], replacement[index]) &&
          !_replaceFlowItem(items[index], old[index], replacement[index])) {
        _edits.length = mark;
        return false;
      }
    }
    final added = <String>[
      for (final item in replacement.skip(old.length)) _flow(item),
    ];
    if (!_appendFlow(items.last, added)) {
      _edits.length = mark;
      return false;
    }
    return true;
  }

  bool _replaceFlowItem(YamlNode node, Object? old, Object? replacement) =>
      _editInside(node, old, replacement) ||
      _replaceInline(node, replacement, inFlow: true);

  /// Inserts [texts] directly after [last], the last entry's value or the
  /// last item of a flow collection, each after `, `.
  bool _appendFlow(YamlNode last, List<String> texts) {
    if (texts.isEmpty) {
      return true;
    }
    final end = _textEnd(last);
    if (end == null) {
      return false;
    }
    _edits.add(
      _Edit(end, end, <String>[for (final text in texts) ', $text'].join()),
    );
    return true;
  }

  /// Writes a changed literal or folded block scalar as a literal block at
  /// its indentation, keeping its header line's comment, when the new value
  /// is a string with a line break that such a block holds exactly.
  ///
  /// Only the in-place attempt does this; the attempt that replaces whole
  /// top-level values writes the string as [okfYamlScalar] does.
  bool _replaceBlockScalar(YamlNode node, Object? replacement) {
    if (!nested ||
        node is! YamlScalar ||
        node.style != ScalarStyle.LITERAL && node.style != ScalarStyle.FOLDED ||
        replacement is! String) {
      return false;
    }
    final block = _literalBlock(replacement);
    final start = _startOf(node);
    final header = layout.yamlLine(start.line).substring(start.column);
    final indicators = _blockScalarIndicators.firstMatch(header);
    final indentation = _contentIndentation(node);
    if (block == null ||
        indicators == null ||
        indentation == null ||
        indentation == 0) {
      return false;
    }
    final (:chomping, :lines) = block;
    _edits.add(
      _Edit(
        layout.offset(start),
        layout.lineEnd(_end(node).line),
        <String>[
          '|$chomping${header.substring(indicators.end)}',
          for (final line in lines)
            line.isEmpty ? '' : '${' ' * indentation}$line',
        ].join(_eol),
      ),
    );
    return true;
  }

  /// The fewest spaces before a line of a block scalar's text, or null when
  /// it has no line with anything but spaces.
  int? _contentIndentation(YamlScalar node) {
    int? indentation;
    for (
      var line = node.span.start.line + 1;
      line <= node.span.end.line;
      line++
    ) {
      final text = layout.yamlLine(line);
      var spaces = 0;
      while (spaces < text.length && text.codeUnitAt(spaces) == 0x20) {
        spaces++;
      }
      if (spaces < text.length &&
          (indentation == null || spaces < indentation)) {
        indentation = spaces;
      }
    }
    return indentation;
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
        _replaceInline(item, replacement) ||
        _replaceBlockScalar(item, replacement)) {
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
      return <String>['$indentation${okfYamlScalar(key)}: $inline'];
    }
    return <String>[
      '$indentation${okfYamlScalar(key)}:',
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
    return okfYamlScalar(value);
  }

  /// The one-line form of any value: a collection in flow style, as
  /// `[a, b]` or `{key: value}`, and a scalar as [_inline] writes it.
  String _flow(Object? value) {
    if (value is List && value.isNotEmpty) {
      return '[${<String>[for (final item in value) _flow(item)].join(', ')}]';
    }
    if (value is Map && value.isNotEmpty) {
      final entries = <String>[
        for (final entry in value.entries)
          '${okfYamlScalar(entry.key)}: ${_flow(entry.value)}',
      ];
      return '{${entries.join(', ')}}';
    }
    return _inline(value)!;
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
