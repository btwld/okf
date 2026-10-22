import 'dart:collection';

import 'package:path/path.dart' as p;

import 'bundle.dart';
import 'bundle_change_set.dart';
import 'concept_id.dart';
import 'document.dart';
import 'index_generator.dart';
import 'index_log.dart';
import 'iso_date.dart';
import 'link_path.dart';
import 'yaml_emitter.dart';

/// The bundle state and file texts an [OkfBundleChangeSet] would produce.
///
/// The overlay is the single interpretation of a change description: what the
/// bundle becomes, and which files carry that state. Prospective validation
/// reads [bundle] and the atomic apply writes [files], so a validated change
/// and a written change cannot diverge.
final class OkfBundleChangeOverlay {
  OkfBundleChangeOverlay._({required this.bundle, required this.files});

  /// Overlays [changes] onto [base] as of [date].
  ///
  /// Throws [OkfBundleChangeException] when a change cannot be described
  /// against [base] at all — a distinct outcome from a change that describes
  /// a bundle state the rules reject. A change whose concept the emitter
  /// cannot write as YAML, such as one with a frontmatter string that holds
  /// an unpaired surrogate, is such a change.
  factory OkfBundleChangeOverlay.of(
    OkfBundle base,
    OkfBundleChangeSet changes, {
    required DateTime date,
  }) {
    if (changes.changes.isEmpty) {
      return OkfBundleChangeOverlay._(
        bundle: base,
        files: const <String, String>{},
      );
    }

    final documents = LinkedHashMap<OkfConceptId, OkfDocument>.of(
      base.concepts,
    );
    final logs = Map<String, String>.of(base.logFiles);
    final files = <String, String>{};
    final logEntries = <OkfLogEntry>[];
    final affectedIndexes = <String>{};
    final day = formatIsoDate(date);

    for (final change in changes.changes) {
      final applied = _emitting(
        change,
        () => _applyChange(documents, change, day),
      );
      if (applied == null) {
        continue;
      }
      documents[applied.id] = applied.document;
      files[applied.id.documentPath] = applied.document.sourceText!;
      logEntries.add(applied.entry);
      if (applied.affectsIndex) {
        affectedIndexes.addAll(_indexAncestors(applied.id));
      }
    }

    final log = logEntries.isEmpty
        ? null
        : _rewrittenLog(logs[_rootLogPath], logEntries);
    if (log != null) {
      logs[_rootLogPath] = log;
      files[_rootLogPath] = log;
    }

    final conceptFiles = <String, OkfDocument>{
      for (final entry in documents.entries)
        entry.key.documentPath: entry.value,
    };
    final indexes = const OkfIndexGenerator().generate(
      OkfBundle.fromDocuments(
        conceptFiles,
        indexes: base.indexFiles,
        logs: logs,
        assets: base.assetPaths,
      ),
    );
    final candidateIndexes = Map<String, String>.of(base.indexFiles);
    for (final index in indexes.entries) {
      if (!affectedIndexes.contains(index.key)) {
        continue;
      }
      candidateIndexes[index.key] = index.value;
      if (base.indexFiles[index.key] != index.value) {
        files[index.key] = index.value;
      }
    }

    return OkfBundleChangeOverlay._(
      bundle: OkfBundle.fromDocuments(
        conceptFiles,
        indexes: candidateIndexes,
        logs: logs,
        assets: base.assetPaths,
      ),
      files: Map<String, String>.unmodifiable(files),
    );
  }

  /// The bundle the change set describes.
  final OkfBundle bundle;

  /// Desired file texts keyed by bundle-relative path.
  final Map<String, String> files;
}

/// Runs [emit] for [change], turning a concept the emitter cannot write as
/// YAML into the change's tool error.
T _emitting<T>(OkfBundleChange change, T Function() emit) {
  try {
    return emit();
  } on OkfYamlEncodeException catch (error) {
    final id = switch (change) {
      OkfCreateConceptChange(:final id) ||
      OkfUpdateConceptChange(:final id) ||
      OkfDeprecateConceptChange(:final id) => id,
      OkfLinkConceptsChange(:final source) => source,
    };
    throw OkfBundleChangeException(
      'Concept ${id.value} cannot be written. ${error.message}',
    );
  }
}

/// Interprets one change against [documents], or returns `null` when the
/// bundle already describes it.
///
/// The returned document is parsed from the text the change writes, which is
/// its [OkfDocument.sourceText]. A new concept is written in canonical form;
/// a change to an existing one edits its text in place through
/// [OkfDocument.rewriteSource].
({OkfConceptId id, OkfDocument document, OkfLogEntry entry, bool affectsIndex})?
_applyChange(
  Map<OkfConceptId, OkfDocument> documents,
  OkfBundleChange change,
  String day,
) {
  switch (change) {
    case OkfCreateConceptChange(id: final id, document: final document):
      _rejectReservedPath(id);
      if (documents.containsKey(id)) {
        throw OkfBundleChangeException('Concept ${id.value} already exists.');
      }
      return (
        id: id,
        document: OkfDocument.parse(
          document.serialize(),
          sourcePath: id.documentPath,
        ),
        entry: OkfLogEntry(
          date: day,
          action: 'Created',
          description: _conceptLink(id, document),
        ),
        affectsIndex: true,
      );

    case OkfUpdateConceptChange(id: final id):
      final current = _requireDocument(documents, id);
      final updated = _edited(
        id,
        current,
        change.frontmatterChanges,
        body: change.body,
      );
      if (updated == null) {
        return null;
      }
      return (
        id: id,
        document: updated,
        entry: OkfLogEntry(
          date: day,
          action: 'Updated',
          description: _conceptLink(id, updated),
        ),
        affectsIndex: _indexProjection(current) != _indexProjection(updated),
      );

    case OkfLinkConceptsChange(
      source: final source,
      target: final target,
      relationship: final relationship,
    ):
      _rejectReservedPath(target);
      final current = _requireDocument(documents, source);
      final targetDocument = documents[target];

      final declared = current.frontmatter['sources'] ?? const <Object?>[];
      if (declared is! List<Object?>) {
        throw OkfBundleChangeException(
          'Concept ${source.value} declares sources that are not a list.',
        );
      }
      final link = <String, Object?>{
        'resource': _relativeResource(source, target),
        'relationship': relationship,
      };
      if (declared.any((entry) => _sameLink(entry, link))) {
        return null;
      }

      final linked = _edited(source, current, <String, Object?>{
        'sources': <Object?>[...declared, link],
      });
      if (linked == null) {
        return null;
      }
      return (
        id: source,
        document: linked,
        entry: OkfLogEntry(
          date: day,
          action: 'Linked',
          description:
              '${_conceptLink(source, current)} $relationship '
              '${_conceptLink(target, targetDocument)}',
        ),
        affectsIndex: false,
      );

    case OkfDeprecateConceptChange(id: final id, note: final note):
      final current = _requireDocument(documents, id);
      if (current.frontmatter['status'] == _deprecated) {
        return null;
      }
      final deprecated = _edited(id, current, const <String, Object?>{
        'status': _deprecated,
      });
      if (deprecated == null) {
        return null;
      }
      final link = _conceptLink(id, current);
      final trimmedNote = note?.trim() ?? '';
      return (
        id: id,
        document: deprecated,
        entry: OkfLogEntry(
          date: day,
          action: 'Deprecated',
          description: trimmedNote.isEmpty ? link : '$link — $trimmedNote',
        ),
        affectsIndex: false,
      );
  }
}

({String type, String title, String description}) _indexProjection(
  OkfDocument document,
) => (
  type: _indexValue(document.frontmatter['type'], fallback: 'Other'),
  title: _indexValue(document.frontmatter['title']),
  description: _indexValue(document.frontmatter['description'], fallback: ''),
);

String _indexValue(Object? value, {String? fallback}) =>
    value is String && value.trim().isNotEmpty ? value.trim() : fallback ?? '';

/// Overlays [changes] onto a document's frontmatter, dropping fields changed
/// to `null` and retaining every field the change does not name, and returns
/// the edited document, or `null` when its text would not change.
///
/// The text is edited in place, so every byte the change does not touch is
/// kept; see [OkfDocument.rewriteSource].
OkfDocument? _edited(
  OkfConceptId id,
  OkfDocument document,
  Map<String, Object?> changes, {
  String? body,
}) {
  final frontmatter = LinkedHashMap<String, Object?>.of(document.frontmatter);
  for (final field in changes.entries) {
    if (field.value == null) {
      frontmatter.remove(field.key);
    } else {
      frontmatter[field.key] = field.value;
    }
  }
  final text = document.rewriteSource(frontmatter: frontmatter, body: body);
  if (text == (document.sourceText ?? document.serialize())) {
    return null;
  }
  return OkfDocument.parse(text, sourcePath: id.documentPath);
}

/// Emits the root log with [entries] prepended, or `null` when the existing
/// log cannot be re-emitted without losing content.
///
/// An unparseable log stays untouched so a change set never silently drops
/// authored history: the rules that read it report the same problem, and the
/// resulting state is refused.
String? _rewrittenLog(String? source, List<OkfLogEntry> entries) {
  if (source == null) {
    return OkfLogDocument(
      title: _defaultLogTitle,
      entries: entries,
    ).serialize();
  }

  final OkfDocument document;
  try {
    document = OkfDocument.parse(source, sourcePath: _rootLogPath);
  } on OkfDocumentException {
    return null;
  }
  if (document.hasFrontmatter) {
    return null;
  }

  final log = OkfLogDocument.parseBody(document.body);
  if (log.issues.isNotEmpty) {
    return null;
  }
  return OkfLogDocument(
    title: log.title,
    entries: <OkfLogEntry>[...entries, ...log.entries],
  ).serialize();
}

OkfDocument _requireDocument(
  Map<OkfConceptId, OkfDocument> documents,
  OkfConceptId id,
) {
  final document = documents[id];
  if (document == null) {
    throw OkfBundleChangeException('Concept ${id.value} does not exist.');
  }
  return document;
}

void _rejectReservedPath(OkfConceptId id) {
  try {
    OkfConceptId.fromDocumentPath(id.documentPath);
  } on FormatException {
    throw OkfBundleChangeException(
      'Concept ${id.value} would occupy the reserved path '
      '${id.documentPath}.',
    );
  }
}

bool _sameLink(Object? entry, Map<String, Object?> link) =>
    entry is Map<Object?, Object?> &&
    entry['resource'] == link['resource'] &&
    entry['relationship'] == link['relationship'];

String _conceptLink(OkfConceptId id, OkfDocument? document) {
  final String title;
  if (document == null) {
    title = id.value;
  } else {
    title = document.title ?? id.basename;
  }
  return '[${escapeOkfConceptLinkLabel(title)}]('
      '${encodeOkfLinkPath(id.documentPath)})';
}

Iterable<String> _indexAncestors(OkfConceptId id) sync* {
  var directory = id.directory;
  while (true) {
    yield directory.isEmpty ? 'index.md' : '$directory/index.md';
    if (directory.isEmpty) {
      break;
    }
    final parent = p.posix.dirname(directory);
    directory = parent == '.' ? '' : parent;
  }
}

String _relativeResource(OkfConceptId source, OkfConceptId target) {
  final directory = source.directory;
  return encodeOkfLinkPath(
    p.posix.relative(
      target.documentPath,
      from: directory.isEmpty ? '.' : directory,
    ),
  );
}

const String _rootLogPath = 'log.md';
const String _defaultLogTitle = 'Log';
const String _deprecated = 'deprecated';
