import 'dart:collection';

import 'package:ack/ack.dart';
import 'package:yaml/yaml.dart';

import 'metadata.dart';
import 'yaml_data.dart';
import 'yaml_emitter.dart';

part 'document.g.dart';

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
@Schemable()
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
  /// Update, link and deprecate changes edit this text in place rather than
  /// write the document anew. Mutating [frontmatter] afterwards does not
  /// change it. A parsed document holds this text besides its [body], so a
  /// loaded bundle keeps each concept's text about twice.
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
  /// are null.
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
