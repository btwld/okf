import 'package:ack/ack.dart';

import 'document.dart';
import 'iso_date.dart';
import 'link_path.dart';

part 'index_log.g.dart';

/// One entry in an OKF `index.md` document.
@Schemable()
final class OkfIndexEntry with _$OkfIndexEntryAck {
  /// Creates an index entry.
  const OkfIndexEntry({
    required this.type,
    required this.title,
    required this.link,
    required this.description,
  });

  /// The section heading in which the entry appears.
  final String type;

  /// The display label for the entry.
  final String title;

  /// A URL relative to the containing index.
  final String link;

  /// A short summary, empty when none is available.
  final String description;
}

/// One dated entry in an OKF `log.md` document.
@Schemable()
final class OkfLogEntry with _$OkfLogEntryAck {
  /// Creates a log entry.
  const OkfLogEntry({
    required this.date,
    required this.action,
    required this.description,
  });

  /// The date heading text as written, `YYYY-MM-DD` when well-formed.
  ///
  /// Held as text so a malformed heading stays representable for the rules
  /// that report it.
  final String date;

  /// The producer-defined action label.
  final String action;

  /// The Markdown description following the action label.
  final String description;
}

/// A structural problem in an OKF `index.md` document.
///
/// Each value is a fact about the document's shape. Naming, severity, and
/// message wording belong to the rules that consume it.
enum OkfIndexIssue {
  /// A list entry appeared before any level-one section heading.
  entryBeforeSection,

  /// A level-one section declared no entries.
  emptySection,

  /// A line was neither a section heading nor a linked list entry.
  unrecognizedLine,

  /// The document declared no level-one section.
  missingSection,

  /// A plain link destination carried raw whitespace, parentheses, or angle
  /// brackets, which CommonMark parsers do not read as a link.
  nonPortableLink,
}

/// A structural problem in an OKF `log.md` document.
///
/// Each value is a fact about the document's shape. Naming, severity, and
/// message wording belong to the rules that consume it.
enum OkfLogIssue {
  /// The document did not begin with a level-one title.
  missingTitle,

  /// A list entry appeared before any date heading.
  entryBeforeDate,

  /// A date heading did not carry a valid ISO 8601 date.
  invalidDate,

  /// A date heading declared no entries.
  emptyDate,

  /// A date heading was newer than the one preceding it.
  notNewestFirst,

  /// A line was neither a title, a date heading, nor a list entry.
  unrecognizedLine,

  /// The document declared no date heading.
  missingDate,
}

/// Parsed index data that may describe malformed, non-writable input.
final class OkfIndexParseResult {
  OkfIndexParseResult._({
    required List<OkfIndexEntry> entries,
    required List<OkfIndexIssue> issues,
    required this.okfVersion,
    required bool preservesFrontmatter,
  }) : entries = List<OkfIndexEntry>.unmodifiable(entries),
       issues = List<OkfIndexIssue>.unmodifiable(issues),
       _preservesFrontmatter = preservesFrontmatter;

  /// Recognized entries in document order.
  final List<OkfIndexEntry> entries;

  /// Structural problems found in document order.
  final List<OkfIndexIssue> issues;

  /// The declared OKF version, or `null` when none was declared.
  final String? okfVersion;

  final bool _preservesFrontmatter;

  /// Builds a canonical writable document when doing so cannot hide damage.
  OkfIndexDocument toDocument() {
    if (issues.isNotEmpty || !_preservesFrontmatter) {
      throw StateError('A malformed index cannot become a writable document');
    }
    return OkfIndexDocument(entries: entries, okfVersion: okfVersion);
  }
}

/// Parsed log data that may describe malformed, non-writable input.
final class OkfLogParseResult {
  OkfLogParseResult._({
    required this.title,
    required List<OkfLogEntry> entries,
    required List<OkfLogIssue> issues,
    required bool preservesFrontmatter,
  }) : entries = List<OkfLogEntry>.unmodifiable(entries),
       issues = List<OkfLogIssue>.unmodifiable(issues),
       _preservesFrontmatter = preservesFrontmatter;

  /// The parsed level-one title, empty when none was recognized.
  final String title;

  /// Recognized entries in document order.
  final List<OkfLogEntry> entries;

  /// Structural problems found in document order.
  final List<OkfLogIssue> issues;

  final bool _preservesFrontmatter;

  /// Builds a canonical writable document when doing so cannot hide damage.
  OkfLogDocument toDocument() {
    if (issues.isNotEmpty || !_preservesFrontmatter) {
      throw StateError('A malformed log cannot become a writable document');
    }
    return OkfLogDocument(title: title, entries: entries);
  }
}

/// The parsed content of an OKF `index.md` document.
///
/// This type owns the `index.md` entry format: producers emit through
/// [serialize] and consumers read through [parse], so no other module needs
/// to know how an entry is spelled.
final class OkfIndexDocument {
  /// Creates an index document from entry data.
  ///
  /// [okfVersion] is declared as root-index frontmatter; a blank or absent
  /// value emits a body-only index. Entry text is normalized to one line;
  /// entry order is preserved.
  OkfIndexDocument({
    required Iterable<OkfIndexEntry> entries,
    String? okfVersion,
  }) : entries = List<OkfIndexEntry>.unmodifiable(
         _canonicalWritableIndexEntries(entries),
       ),
       okfVersion = _declaredVersion(okfVersion);

  /// Parses a complete index file, frontmatter included.
  ///
  /// Throws [OkfDocumentException] when the frontmatter block is malformed.
  static OkfIndexParseResult parse(String source, {String? sourcePath}) {
    final document = OkfDocument.parse(source, sourcePath: sourcePath);
    final declared = document.frontmatter['okf_version'];
    final scan = _scanIndexBody(document.body);
    return OkfIndexParseResult._(
      entries: scan.entries,
      issues: scan.issues,
      okfVersion: declared is String ? declared : null,
      preservesFrontmatter:
          !document.hasFrontmatter ||
          document.frontmatter.length == 1 &&
              declared is String &&
              declared.trim().isNotEmpty,
    );
  }

  /// Parses an index body already separated from its frontmatter.
  ///
  /// Entries outside a section are reported through [issues] and dropped:
  /// they carry no section to be emitted under.
  static OkfIndexParseResult parseBody(String body) {
    final scan = _scanIndexBody(body);
    return OkfIndexParseResult._(
      entries: scan.entries,
      issues: scan.issues,
      okfVersion: null,
      preservesFrontmatter: true,
    );
  }

  /// The entries in document order.
  final List<OkfIndexEntry> entries;

  /// The declared OKF version, or `null` when the document declares none.
  final String? okfVersion;

  /// Emits the document.
  ///
  /// Contiguous entries of one type share a section, and entry text is
  /// normalized to a single line. No Spec rule constrains section order, so
  /// the caller's entry order is preserved.
  String serialize() {
    final body = _emitIndexBody(entries);
    final version = okfVersion;
    if (version == null) {
      return body;
    }
    return OkfDocument(
      frontmatter: <String, Object?>{'okf_version': version},
      body: body,
    ).serialize();
  }
}

/// The parsed content of an OKF `log.md` document.
///
/// This type owns the `log.md` entry format: producers emit through
/// [serialize] and consumers read through [parse], so no other module needs
/// to know how an entry is spelled.
final class OkfLogDocument {
  /// Creates a log document from entry data.
  ///
  /// Text is normalized to one line and entries are stored newest first.
  OkfLogDocument({
    required String title,
    required Iterable<OkfLogEntry> entries,
  }) : title = _canonicalWritableLogTitle(title),
       entries = List<OkfLogEntry>.unmodifiable(
         _canonicalWritableLogEntries(entries),
       );

  /// Parses a complete log file.
  ///
  /// Throws [OkfDocumentException] when a frontmatter block is present but
  /// malformed. Logs carry no frontmatter; a well-formed block is dropped and
  /// left for the rules to report.
  static OkfLogParseResult parse(String source, {String? sourcePath}) {
    final document = OkfDocument.parse(source, sourcePath: sourcePath);
    final scan = _scanLogBody(document.body);
    return OkfLogParseResult._(
      title: scan.title,
      entries: scan.entries,
      issues: scan.issues,
      preservesFrontmatter: !document.hasFrontmatter,
    );
  }

  /// Parses a log body already separated from any frontmatter.
  ///
  /// Entries before any date heading are reported through `issues` and
  /// dropped. Entries under a malformed date retain its text for reporting.
  static OkfLogParseResult parseBody(String body) {
    final scan = _scanLogBody(body);
    return OkfLogParseResult._(
      title: scan.title,
      entries: scan.entries,
      issues: scan.issues,
      preservesFrontmatter: true,
    );
  }

  /// The level-one document title, empty when the log declares none.
  final String title;

  /// The entries in document order.
  final List<OkfLogEntry> entries;

  /// Emits the document.
  ///
  /// Contiguous entries with one date share a heading, and stored order is
  /// preserved. Writable documents store dates newest first.
  String serialize() => _emitLogBody(title, entries);
}

({List<OkfIndexEntry> entries, List<OkfIndexIssue> issues}) _scanIndexBody(
  String body,
) {
  final entries = <OkfIndexEntry>[];
  final issues = <OkfIndexIssue>[];
  String? type;
  var sectionHasEntry = false;

  for (final rawLine in body.split(_lineBreak)) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }

    final heading = _levelOneHeading.firstMatch(line);
    if (heading != null) {
      if (type != null && !sectionHasEntry) {
        issues.add(OkfIndexIssue.emptySection);
      }
      type = _unescapeHeading(heading.group(1)!).trim();
      sectionHasEntry = false;
      continue;
    }

    final entry = _indexEntry.firstMatch(line);
    if (entry == null) {
      issues.add(OkfIndexIssue.unrecognizedLine);
      continue;
    }
    final angle = entry.namedGroup('angle');
    final plain = entry.namedGroup('plain');
    final link = angle != null ? _encodeAngleDestination(angle) : plain!;
    if (angle == null && okfLinkDestinationUnsafe.hasMatch(plain!)) {
      issues.add(OkfIndexIssue.nonPortableLink);
    }
    if (type == null) {
      issues.add(OkfIndexIssue.entryBeforeSection);
    } else {
      entries.add(
        OkfIndexEntry(
          type: type,
          title: _unescapeLinkLabel(entry.namedGroup('label')!),
          link: link,
          description: entry.namedGroup('description')?.trim() ?? '',
        ),
      );
    }
    sectionHasEntry = true;
  }

  if (type == null) {
    issues.add(OkfIndexIssue.missingSection);
  } else if (!sectionHasEntry) {
    issues.add(OkfIndexIssue.emptySection);
  }

  return (entries: entries, issues: issues);
}

({String title, List<OkfLogEntry> entries, List<OkfLogIssue> issues})
_scanLogBody(String body) {
  final entries = <OkfLogEntry>[];
  final issues = <OkfLogIssue>[];
  var title = '';
  var sawTitle = false;
  var sawDate = false;
  var dateHasEntry = false;
  String? date;
  DateTime? previousDate;

  for (final rawLine in body.split(_lineBreak)) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }

    if (!sawTitle) {
      sawTitle = true;
      final heading = _levelOneHeading.firstMatch(line);
      if (heading == null) {
        issues.add(OkfLogIssue.missingTitle);
      } else {
        title = _unescapeHeading(heading.group(1)!).trim();
      }
      continue;
    }

    final heading = _logDate.firstMatch(line);
    if (heading != null) {
      if (sawDate && !dateHasEntry) {
        issues.add(OkfLogIssue.emptyDate);
      }
      final parsed = parseIsoDate(heading.group(1));
      if (parsed == null) {
        issues.add(OkfLogIssue.invalidDate);
        date = heading.group(1);
      } else {
        if (previousDate != null && parsed.isAfter(previousDate)) {
          issues.add(OkfLogIssue.notNewestFirst);
        }
        previousDate = parsed;
        date = heading.group(1);
      }
      sawDate = true;
      dateHasEntry = false;
      continue;
    }

    final entry = _logEntry.firstMatch(line);
    if (entry == null) {
      issues.add(OkfLogIssue.unrecognizedLine);
      continue;
    }
    if (!sawDate) {
      issues.add(OkfLogIssue.entryBeforeDate);
    } else if (date != null) {
      entries.add(
        OkfLogEntry(
          date: date,
          action: entry.group(1)?.trim() ?? '',
          description: entry.group(2)!.trim(),
        ),
      );
    }
    dateHasEntry = true;
  }

  if (!sawTitle) {
    issues.add(OkfLogIssue.missingTitle);
  }
  if (!sawDate) {
    issues.add(OkfLogIssue.missingDate);
  } else if (!dateHasEntry) {
    issues.add(OkfLogIssue.emptyDate);
  }

  return (title: title, entries: entries, issues: issues);
}

String _emitIndexBody(List<OkfIndexEntry> entries) {
  final sections = <String>[];
  for (final section in _groupRuns(entries, (entry) => entry.type)) {
    final lines = <String>['# ${_escapeHeading(section.key)}', ''];
    for (final entry in section.value) {
      final description = _singleLine(entry.description);
      final suffix = description.isEmpty ? '' : ' - $description';
      lines.add('* [${_escapeLinkLabel(entry.title)}](${entry.link})$suffix');
    }
    sections.add(lines.join('\n'));
  }
  return _joinSections(sections);
}

String _emitLogBody(String title, List<OkfLogEntry> entries) {
  final sections = <String>[];
  final heading = _singleLine(title);
  if (heading.isNotEmpty) {
    sections.add('# ${_escapeHeading(heading)}');
  }
  for (final section in _groupRuns(entries, (entry) => entry.date)) {
    final lines = <String>['## ${section.key}', ''];
    for (final entry in section.value) {
      final action = _singleLine(entry.action);
      final prefix = action.isEmpty ? '' : '**$action**: ';
      lines.add('* $prefix${_singleLine(entry.description)}');
    }
    sections.add(lines.join('\n'));
  }
  return _joinSections(sections);
}

Map<String, List<T>> _groupBy<T>(List<T> values, String Function(T) key) {
  final grouped = <String, List<T>>{};
  for (final value in values) {
    grouped.putIfAbsent(key(value), () => <T>[]).add(value);
  }
  return grouped;
}

Iterable<MapEntry<String, List<T>>> _groupRuns<T>(
  List<T> values,
  String Function(T) keyOf,
) sync* {
  String? key;
  var run = <T>[];
  for (final value in values) {
    final nextKey = keyOf(value);
    if (key != null && nextKey != key) {
      yield MapEntry<String, List<T>>(key, run);
      run = <T>[];
    }
    key = nextKey;
    run.add(value);
  }
  if (key != null) {
    yield MapEntry<String, List<T>>(key, run);
  }
}

String _joinSections(List<String> sections) =>
    sections.isEmpty ? '' : '${sections.join('\n\n')}\n';

String? _declaredVersion(String? value) =>
    value == null || value.trim().isEmpty ? null : value;

String _singleLine(String value) =>
    value.trim().replaceAll(_whitespaceRun, ' ');

String _escapeHeading(String value) =>
    _singleLine(value).replaceAll('#', r'\#');

String _unescapeHeading(String value) => value.replaceAll(r'\#', '#');

/// Converts an angle-bracket destination to the canonical encoded spelling.
///
/// Only the characters a plain destination cannot carry are encoded;
/// existing percent escapes keep their CommonMark URL meaning.
String _encodeAngleDestination(String value) => value.replaceAllMapped(
  okfLinkDestinationUnsafe,
  (match) =>
      _destinationEscapes[match.group(0)] ??
      Uri.encodeComponent(match.group(0)!),
);

/// `Uri.encodeComponent` leaves parentheses unescaped, so the destination
/// characters it cannot be trusted with carry their escapes here.
const Map<String, String> _destinationEscapes = <String, String>{
  ' ': '%20',
  '\t': '%09',
  '(': '%28',
  ')': '%29',
  '<': '%3C',
  '>': '%3E',
};

String _escapeLinkLabel(String value) => _singleLine(
  value,
).replaceAll(r'\', r'\\').replaceAll('[', r'\[').replaceAll(']', r'\]');

String _unescapeLinkLabel(String value) =>
    value.replaceAllMapped(_escapedCharacter, (match) => match.group(1)!);

List<OkfIndexEntry> _canonicalWritableIndexEntries(
  Iterable<OkfIndexEntry> entries,
) {
  final source = entries.toList(growable: false);
  if (source.isEmpty) {
    throw ArgumentError.value(entries, 'entries', 'Must not be empty');
  }
  final result = <OkfIndexEntry>[];
  for (final entry in source) {
    final type = _singleLine(entry.type);
    final title = _singleLine(entry.title);
    if (type.isEmpty) {
      throw ArgumentError.value(entry, 'entries', 'Type must not be blank');
    }
    if (title.isEmpty) {
      throw ArgumentError.value(entry, 'entries', 'Title must not be blank');
    }
    if (entry.link.isEmpty || okfLinkDestinationUnsafe.hasMatch(entry.link)) {
      throw ArgumentError.value(
        entry,
        'entries',
        'Link must percent-encode whitespace, parentheses, and angle '
            'brackets',
      );
    }
    result.add(
      entry.copyWith(
        type: type,
        title: title,
        description: _singleLine(entry.description),
      ),
    );
  }
  return result;
}

String _canonicalWritableLogTitle(String title) {
  final normalized = _singleLine(title);
  if (normalized.isEmpty) {
    throw ArgumentError.value(title, 'title', 'Must not be blank');
  }
  return normalized;
}

List<OkfLogEntry> _canonicalWritableLogEntries(Iterable<OkfLogEntry> entries) {
  final source = entries.toList(growable: false);
  if (source.isEmpty) {
    throw ArgumentError.value(entries, 'entries', 'Must not be empty');
  }
  final canonical = <OkfLogEntry>[];
  for (final entry in source) {
    final action = _singleLine(entry.action);
    final description = _singleLine(entry.description);
    if (parseIsoDate(entry.date) == null) {
      throw ArgumentError.value(
        entry,
        'entries',
        'Date must use canonical YYYY-MM-DD form',
      );
    }
    if (action.contains('**:')) {
      throw ArgumentError.value(entry, 'entries', 'Action cannot contain **:');
    }
    if (description.isEmpty ||
        (action.isEmpty && _actionPrefix.hasMatch(description))) {
      throw ArgumentError.value(
        entry,
        'entries',
        'Description is blank or ambiguous with an action label',
      );
    }
    canonical.add(entry.copyWith(action: action, description: description));
  }
  final byDate = _groupBy(canonical, (entry) => entry.date);
  final newestFirst = byDate.keys.toList()
    ..sort((left, right) => right.compareTo(left));
  return <OkfLogEntry>[for (final date in newestFirst) ...byDate[date]!];
}

final RegExp _lineBreak = RegExp(r'\r?\n');
final RegExp _whitespaceRun = RegExp(r'\s+');
final RegExp _escapedCharacter = RegExp(r'\\(.)');
final RegExp _levelOneHeading = RegExp(r'^# ([^#].*)$');
final RegExp _indexEntry = RegExp(
  r'^[*-] \[(?<label>(?:\\.|[^\]])+)\]'
  r'\((?:<(?<angle>[^<>]+)>|(?<plain>[^)]+))\)'
  r'(?:\s+-\s+(?<description>.+))?$',
);
final RegExp _logDate = RegExp(r'^## (\d{4}-\d{2}-\d{2})$');
final RegExp _logEntry = RegExp(r'^[*-] (?:\*\*(.+?)\*\*:\s+)?(.+)$');
final RegExp _actionPrefix = RegExp(r'^\*\*.+?\*\*:\s+.+$');
