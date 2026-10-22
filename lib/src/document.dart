import 'dart:collection';

import 'package:ack/ack.dart';
import 'package:ack_annotations/ack_annotations.dart';
import 'package:yaml/yaml.dart';

import 'frontmatter_rewriter.dart';
import 'metadata.dart';
import 'yaml_data.dart';
import 'yaml_emitter.dart';

part 'document.ack.dart';
part 'document.ack.g.dart';

/// A failure to split or parse an OKF concept document.
final class OkfDocumentException implements FormatException {
  /// Creates a document parse exception.
  const OkfDocumentException(
    this.message, {
    this.sourcePath,
    this.line,
    this.column,
  });

  @override
  final String message;

  /// Optional source name supplied to [OkfDocument.parse].
  final String? sourcePath;

  /// One-based source line, when known.
  final int? line;

  /// One-based source column, when known.
  final int? column;

  @override
  Object? get source => sourcePath;

  @override
  int? get offset => null;

  @override
  String toString() {
    final location = StringBuffer();
    if (sourcePath != null) {
      location.write(sourcePath);
    }
    if (line != null) {
      if (location.isNotEmpty) {
        location.write(':');
      }
      location.write(line);
      if (column != null) {
        location
          ..write(':')
          ..write(column);
      }
    }
    return location.isEmpty
        ? 'OkfDocumentException: $message'
        : 'OkfDocumentException ($location): $message';
  }
}

/// One entry from a legacy v0.1 `# Citations` section.
///
/// OKF v0.2 §13.1 permits this fallback; current provenance uses `sources`.
@AckModel()
final class OkfLegacyCitation with _$OkfLegacyCitationAck {
  /// Creates a parsed legacy citation.
  const OkfLegacyCitation({
    required this.number,
    required this.title,
    required this.target,
    required this.raw,
  });

  /// Explicit citation number, or its one-based order in an unnumbered list.
  final int number;

  /// Markdown link label.
  final String title;

  /// Markdown link destination.
  final String target;

  /// Original citation line, without surrounding whitespace.
  final String raw;
}

/// An Open Knowledge Format document: YAML frontmatter and a Markdown body.
final class OkfDocument {
  /// Creates a document.
  ///
  /// The top-level [frontmatter] map is copied so later structural mutations
  /// of the caller's map do not change this document. Nested semantic values
  /// are retained as supplied. The document has no source text, so its
  /// [sourceText] and [bodyStartLine] are null.
  OkfDocument({
    Map<String, Object?> frontmatter = const <String, Object?>{},
    String body = '',
    bool hasFrontmatter = true,
  }) : this._(
         frontmatter: frontmatter,
         body: body,
         hasFrontmatter: hasFrontmatter,
       );

  OkfDocument._({
    required Map<String, Object?> frontmatter,
    required this.body,
    required this.hasFrontmatter,
    this.sourceText,
    this.bodyStartLine,
  }) : frontmatter = LinkedHashMap<String, Object?>.of(frontmatter);

  /// Parses an OKF document.
  ///
  /// If the first line is not a `---` delimiter, all input is treated as the
  /// Markdown body and [hasFrontmatter] is false. This is syntactically
  /// consumable but a concept validator can still report that frontmatter and
  /// `type` are required.
  ///
  /// The parsed document keeps [source] as [sourceText] and records where
  /// its body begins in it as [bodyStartLine].
  factory OkfDocument.parse(String source, {String? sourcePath}) {
    final normalized = _normalizeLineEndings(source);
    final lines = normalized.split('\n');
    if (lines.isEmpty || lines.first.trim() != '---') {
      return OkfDocument._(
        frontmatter: const <String, Object?>{},
        body: normalized,
        hasFrontmatter: false,
        sourceText: source,
        bodyStartLine: 1,
      );
    }

    int? closingLine;
    for (var index = 1; index < lines.length; index++) {
      if (lines[index].trim() == '---') {
        closingLine = index;
        break;
      }
    }
    if (closingLine == null) {
      throw OkfDocumentException(
        'Unterminated YAML frontmatter block',
        sourcePath: sourcePath,
        line: lines.length,
        column: 1,
      );
    }

    final yamlSource = lines.sublist(1, closingLine).join('\n');
    Object? parsed;
    try {
      parsed = yamlSource.trim().isEmpty ? null : loadYaml(yamlSource);
    } on YamlException catch (error) {
      final start = error.span?.start;
      throw OkfDocumentException(
        'Invalid YAML in frontmatter: ${error.message}',
        sourcePath: sourcePath,
        // Account for the opening delimiter and convert zero-based positions.
        line: start == null ? null : start.line + 2,
        column: start == null ? null : start.column + 1,
      );
    }

    if (parsed != null && parsed is! Map) {
      throw OkfDocumentException(
        'Frontmatter must be a YAML mapping',
        sourcePath: sourcePath,
        line: 2,
        column: 1,
      );
    }

    final frontmatter = <String, Object?>{};
    if (parsed is Map) {
      late final Object? converted;
      try {
        converted = _YamlConversionState().convert(parsed);
      } on _YamlStructureException catch (error) {
        throw OkfDocumentException(
          error.message,
          sourcePath: sourcePath,
          line: 2,
          column: 1,
        );
      }
      for (final entry in (converted! as Map<Object?, Object?>).entries) {
        if (entry.key is! String) {
          throw OkfDocumentException(
            'Frontmatter keys must be strings',
            sourcePath: sourcePath,
            line: 2,
            column: 1,
          );
        }
        frontmatter[entry.key as String] = entry.value;
      }
    }

    var body = lines.sublist(closingLine + 1).join('\n');
    // `closingLine` is zero-based, so the line after it is `closingLine + 2`.
    var bodyStartLine = closingLine + 2;
    // A single empty line conventionally separates frontmatter from Markdown.
    if (body.startsWith('\n')) {
      body = body.substring(1);
      bodyStartLine++;
    }
    return OkfDocument._(
      frontmatter: frontmatter,
      body: body,
      hasFrontmatter: true,
      sourceText: source,
      bodyStartLine: bodyStartLine,
    );
  }

  /// Ordered, open YAML metadata. Unknown keys are retained.
  final Map<String, Object?> frontmatter;

  /// Markdown following the frontmatter block.
  final String body;

  /// Whether parsing found a frontmatter block.
  final bool hasFrontmatter;

  /// The exact text this document was parsed from, or null for a document
  /// built with the constructor or [copyWith].
  ///
  /// It is what [rewriteSource] edits. Mutating [frontmatter] afterwards does
  /// not change it. A parsed document holds this text besides its [body], so
  /// a loaded bundle keeps each concept's text about twice.
  final String? sourceText;

  /// The one-based line of the parsed source on which [body] begins, or null
  /// for a document that was not parsed from text.
  ///
  /// Line `n` of [body], counting from 1 and splitting at `\n`, is line
  /// `bodyStartLine + n - 1` of the source, so a host can cite body text by
  /// source line without searching the source for it. Lines are counted as
  /// [OkfDocument.parse] reads them: LF, CRLF and a lone CR each end a line,
  /// and a byte order mark adds none.
  ///
  /// A final line break ends the body's last line rather than starting
  /// another, so the empty element that splitting leaves after it is not a
  /// line: a body of `k` lines ends on line `bodyStartLine + k - 1`, which is
  /// the source's last line.
  ///
  /// Without frontmatter the body is the whole source and begins on line 1.
  /// Otherwise it begins on the line after the closing `---` delimiter, or on
  /// the line after that when parsing drops the blank separator line. An
  /// empty body after frontmatter therefore begins one line past the
  /// source's last line.
  ///
  /// Documents from the constructor or [copyWith] have no source, so this is
  /// null for them.
  final int? bodyStartLine;

  /// Typed, non-destructive access to known OKF metadata.
  OkfMetadata get metadata => OkfMetadata.fromFrontmatter(frontmatter);

  /// Required OKF concept type, when represented by a scalar.
  String? get type => metadata.type;

  /// Optional human-readable display name.
  String? get title => metadata.title;

  /// Optional one-line summary.
  String? get description => metadata.description;

  /// Optional URI for the underlying asset.
  String? get resource => metadata.resource;

  /// Cross-cutting category tags.
  List<String> get tags => metadata.tags;

  /// Trust tier derived from the normalized verification events.
  OkfTrustTier get trustTier => metadata.trustTier;

  /// Lifecycle status, defaulting to stable.
  OkfLifecycleStatus get status => metadata.status;

  /// Whether the document is stale on [today].
  bool isStale([DateTime? now]) => metadata.isStale(now);

  /// Returns a copy with selected document parts replaced.
  ///
  /// The copy has no source text, so its [sourceText] and [bodyStartLine]
  /// are null. Use [rewriteSource] to change a parsed document's text
  /// without rewriting the parts that stay the same.
  OkfDocument copyWith({
    Map<String, Object?>? frontmatter,
    String? body,
    bool? hasFrontmatter,
  }) => OkfDocument(
    frontmatter: frontmatter ?? this.frontmatter,
    body: body ?? this.body,
    hasFrontmatter: hasFrontmatter ?? this.hasFrontmatter,
  );

  /// Serializes the document in canonical form.
  ///
  /// Body-only input remains body-only. For frontmatter documents this method
  /// applies the preferred OKF key order, normalizes line endings, separates
  /// frontmatter and body with one blank line, and ensures a final newline for
  /// non-empty bodies.
  String serialize({OkfYamlEmitter emitter = const OkfYamlEmitter()}) {
    final canonicalBody = _canonicalBody(body);
    if (!hasFrontmatter) {
      return canonicalBody;
    }

    final yaml = emitter.emit(frontmatter);
    final output = StringBuffer('---\n');
    if (yaml.isNotEmpty) {
      output
        ..write(yaml)
        ..write('\n');
    }
    output.write('---\n\n');
    output.write(canonicalBody);
    return output.toString();
  }

  /// Alias for [serialize].
  String toMarkdown({OkfYamlEmitter emitter = const OkfYamlEmitter()}) =>
      serialize(emitter: emitter);

  /// Returns [sourceText] edited so that it parses to [frontmatter] and,
  /// unless [body] is null, to [body], keeping the exact bytes of everything
  /// the edit does not change.
  ///
  /// [frontmatter] is the complete resulting mapping and defaults to this
  /// document's [frontmatter]; a key it lacks is removed. This document is
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
  ///   spacing and line breaks included, stays. Otherwise the
  ///   whole collection is replaced by its span with one line such as
  ///   `[a, b]` or `{key: value}`, which writes its unchanged entries in
  ///   [OkfYamlEmitter.scalar] spellings too. That also happens when a value
  ///   to replace is omitted (`{key}`) or spans lines, and when entries are
  ///   added after a last value that is omitted or is a plain scalar over
  ///   several lines.
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
  /// [OkfYamlEmitter.scalar] writes them. New lines end with the line break
  /// of the document's first line, so a CRLF document stays CRLF, and the
  /// delimiter lines are kept.
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
  /// the mark in its [body], as [OkfDocument.parse] reads it: it stays with
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
  ///    value, with every scalar written as [OkfYamlEmitter.scalar] writes
  ///    it.
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
  /// when [frontmatter] is not empty. A document without [sourceText] is
  /// written as [serialize] writes it, and checked the same way.
  String rewriteSource({
    Map<String, Object?>? frontmatter,
    String? body,
    OkfYamlEmitter emitter = const OkfYamlEmitter(),
  }) => rewriteOkfDocumentSource(
    sourceText,
    frontmatter ?? this.frontmatter,
    body: body,
    currentBody: this.body,
    hasFrontmatter: hasFrontmatter,
    emitter: emitter,
  );

  /// Entries from a legacy v0.1 top-level `# Citations` section.
  List<OkfLegacyCitation> get legacyCitations {
    final citations = <OkfLegacyCitation>[];
    var inCitations = false;
    for (final line in _normalizeLineEndings(body).split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('# ')) {
        inCitations = trimmed == '# Citations';
        continue;
      }
      if (!inCitations || trimmed.isEmpty) {
        continue;
      }

      final numbered = RegExp(
        r'^\[(\d+)\]\s+\[([^\]]+)\]\((.+)\)\s*$',
      ).firstMatch(trimmed);
      if (numbered != null) {
        citations.add(
          OkfLegacyCitation(
            number: int.parse(numbered.group(1)!),
            title: numbered.group(2)!,
            target: numbered.group(3)!,
            raw: trimmed,
          ),
        );
        continue;
      }

      final bullet = RegExp(
        r'^(?:[-*+]\s+|\d+[.)]\s+)(.+)$',
      ).firstMatch(trimmed);
      if (bullet == null) {
        continue;
      }
      final content = bullet.group(1)!.trim();
      final link = RegExp(r'^\[([^\]]+)\]\((.+)\)$').firstMatch(content);
      final title = link?.group(1) ?? content;
      final target = link?.group(2) ?? content;
      citations.add(
        OkfLegacyCitation(
          number: citations.length + 1,
          title: title,
          target: target,
          raw: trimmed,
        ),
      );
    }
    return List<OkfLegacyCitation>.unmodifiable(citations);
  }

  /// Alias for [legacyCitations].
  List<OkfLegacyCitation> get citations => legacyCitations;

  /// Whether a legacy v0.1 citation entry is present.
  bool get hasLegacyCitations => legacyCitations.isNotEmpty;

  @override
  String toString() => serialize();
}

/// Backward-friendly short name for document parsing failures.
typedef OkfDocumentError = OkfDocumentException;

final class _YamlConversionState {
  final HashMap<Object, Object?> _converted =
      HashMap<Object, Object?>.identity();
  final HashSet<Object> _active = HashSet<Object>.identity();
  var _nodes = 0;

  Object? convert(Object? value, [int depth = 0]) {
    _nodes++;
    if (_nodes > maximumYamlNodes) {
      throw const _YamlStructureException(
        'YAML frontmatter exceeds the supported node limit.',
      );
    }
    if (depth > maximumYamlDepth) {
      throw const _YamlStructureException(
        'YAML frontmatter exceeds the supported nesting depth.',
      );
    }

    if (value is Map) {
      if (_active.contains(value)) {
        throw const _YamlStructureException(
          'Cyclic YAML aliases are not supported.',
        );
      }
      final cached = _converted[value];
      if (cached != null) {
        return cached;
      }
      _active.add(value);
      final result = <Object?, Object?>{};
      _converted[value] = result;
      try {
        for (final entry in value.entries) {
          result[convert(entry.key, depth + 1)] = convert(
            entry.value,
            depth + 1,
          );
        }
      } finally {
        _active.remove(value);
      }
      return result;
    }
    if (value is Iterable && value is! String) {
      if (_active.contains(value)) {
        throw const _YamlStructureException(
          'Cyclic YAML aliases are not supported.',
        );
      }
      final cached = _converted[value];
      if (cached != null) {
        return cached;
      }
      _active.add(value);
      final result = <Object?>[];
      _converted[value] = result;
      try {
        for (final item in value) {
          result.add(convert(item, depth + 1));
        }
      } finally {
        _active.remove(value);
      }
      return result;
    }
    return value;
  }
}

final class _YamlStructureException implements Exception {
  const _YamlStructureException(this.message);

  final String message;
}

String _normalizeLineEndings(String value) =>
    value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

String _canonicalBody(String value) {
  final normalized = _normalizeLineEndings(value);
  if (normalized.isEmpty || normalized.endsWith('\n')) {
    return normalized;
  }
  return '$normalized\n';
}
