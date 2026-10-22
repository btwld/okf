import 'dart:collection';

import 'package:path/path.dart' as p;

import 'bundle.dart';
import 'index_log.dart';
import 'link_path.dart';
import 'version.dart';

/// Supplies a deterministic description for a directory index.
typedef OkfDirectoryDescriptionSynthesizer =
    String Function(String directory, List<OkfIndexEntry> entries);

/// Generates deterministic, progressively disclosed `index.md` files.
///
/// For the same bundle and [synthesizeDescription], the output bytes stay the
/// same across every release sharing one [okfIndexGeneratorRevision]. A change
/// to them bumps that revision and ships only in a minor release.
final class OkfIndexGenerator {
  /// Creates an index generator.
  const OkfIndexGenerator({this.synthesizeDescription});

  /// Optional directory-summary callback.
  ///
  /// No network-backed synthesis is built into this package. When omitted,
  /// a deterministic summary is generated from the entry titles.
  final OkfDirectoryDescriptionSynthesizer? synthesizeDescription;

  /// Generates indexes, keyed by their bundle-relative path.
  ///
  /// Map iteration order is deepest directory first so callers can write the
  /// returned files in the same order they were derived. Existing root
  /// `okf_version` frontmatter is retained unless [declareVersion] is given.
  Map<String, String> generate(OkfBundle bundle, {String? declareVersion}) {
    final directories = _directoriesToIndex(bundle);
    final knownDirectories = directories.toSet();
    final descriptions = <String, String>{};
    final generated = <String, String>{};

    for (final directory in directories) {
      final entries = _entriesForDirectory(
        bundle,
        directory,
        descriptions,
        knownDirectories,
      );
      if (entries.isEmpty) {
        continue;
      }

      final isRoot = directory.isEmpty;
      final indexPath = isRoot ? 'index.md' : '$directory/index.md';
      generated[indexPath] = OkfIndexDocument(
        entries: entries,
        okfVersion: isRoot
            ? declareVersion ??
                  _existingRootVersion(bundle.indexFiles[indexPath])
            : null,
      ).serialize();

      if (directory.isNotEmpty) {
        descriptions[directory] = _describeDirectory(directory, entries);
      }
    }

    return UnmodifiableMapView(generated);
  }

  List<String> _directoriesToIndex(OkfBundle bundle) {
    final directories = <String>{};

    void addWithAncestors(String directory) {
      var current = directory;
      while (true) {
        directories.add(current);
        if (current.isEmpty) {
          return;
        }
        final parent = p.posix.dirname(current);
        current = parent == '.' ? '' : parent;
      }
    }

    for (final id in bundle.concepts.keys) {
      addWithAncestors(id.directory);
    }
    for (final indexPath in bundle.indexFiles.keys) {
      final directory = p.posix.dirname(indexPath);
      addWithAncestors(directory == '.' ? '' : directory);
    }

    final result = directories.toList()
      ..sort((left, right) {
        final depthComparison = _depth(right).compareTo(_depth(left));
        return depthComparison != 0 ? depthComparison : left.compareTo(right);
      });
    return result;
  }

  List<OkfIndexEntry> _entriesForDirectory(
    OkfBundle bundle,
    String directory,
    Map<String, String> descriptions,
    Set<String> knownDirectories,
  ) {
    final entries = <OkfIndexEntry>[];

    for (final entry in bundle.concepts.entries) {
      if (entry.key.directory != directory) {
        continue;
      }
      final document = entry.value;
      entries.add(
        OkfIndexEntry(
          type: _nonEmptyString(document.frontmatter['type']) ?? 'Other',
          title:
              _nonEmptyString(document.frontmatter['title']) ??
              entry.key.basename,
          link: encodeOkfLinkSegment('${entry.key.basename}.md'),
          description:
              _nonEmptyString(document.frontmatter['description']) ?? '',
        ),
      );
    }

    final childDirectories = knownDirectories.where((candidate) {
      if (candidate.isEmpty || candidate == directory) {
        return false;
      }
      final parent = p.posix.dirname(candidate);
      return (parent == '.' ? '' : parent) == directory;
    }).toSet();
    for (final child in childDirectories) {
      final basename = p.posix.basename(child);
      entries.add(
        OkfIndexEntry(
          type: 'Subdirectories',
          title: basename,
          link: '${encodeOkfLinkSegment(basename)}/index.md',
          description: descriptions[child] ?? '',
        ),
      );
    }

    entries.sort((left, right) {
      final typeComparison = _compareText(left.type, right.type);
      if (typeComparison != 0) {
        return typeComparison;
      }
      final titleComparison = _compareText(left.title, right.title);
      if (titleComparison != 0) {
        return titleComparison;
      }
      return left.link.compareTo(right.link);
    });
    return entries;
  }

  String _describeDirectory(String directory, List<OkfIndexEntry> entries) {
    if (entries.length == 1 && entries.single.description.trim().isNotEmpty) {
      return entries.single.description;
    }
    String? custom;
    try {
      custom = synthesizeDescription?.call(
        directory,
        List<OkfIndexEntry>.unmodifiable(entries),
      );
    } on Exception {
      // A synthesizer is optional enrichment. Index generation remains
      // deterministic and available when it fails.
      custom = null;
    }
    if (custom != null && custom.trim().isNotEmpty) {
      return custom;
    }

    final titles = entries.map((entry) => entry.title).join(', ');
    return 'Contains ${entries.length} entries: $titles.';
  }
}

String? _existingRootVersion(String? source) {
  if (source == null) {
    return null;
  }
  try {
    return _nonEmptyString(
      OkfIndexDocument.parse(source, sourcePath: 'index.md').okfVersion,
    );
  } on FormatException {
    return null;
  }
}

int _depth(String directory) =>
    directory.isEmpty ? 0 : directory.split('/').length;

int _compareText(String left, String right) {
  final insensitive = left.toLowerCase().compareTo(right.toLowerCase());
  return insensitive != 0 ? insensitive : left.compareTo(right);
}

String? _nonEmptyString(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return value.trim();
}
