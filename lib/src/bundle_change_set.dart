import 'concept_id.dart';
import 'document.dart';
import 'yaml_data.dart';

/// A prospective mutation included in an [OkfBundleChangeSet].
sealed class OkfBundleChange {
  /// Shared by every change kind; the sealed hierarchy is closed here.
  const OkfBundleChange();
}

/// A request to create a concept from a complete document.
final class OkfCreateConceptChange extends OkfBundleChange {
  /// Creates a concept-change description, snapshotting [document].
  ///
  /// The parts are snapshotted rather than re-serialized so the description
  /// stays faithful to what the caller supplied: frontmatter values keep
  /// their runtime types and key order, and the body is retained verbatim.
  /// Canonicalization belongs to serialization, not to describing a change.
  /// Values YAML cannot represent are rejected here with [ArgumentError],
  /// matching [OkfUpdateConceptChange].
  OkfCreateConceptChange({required this.id, required OkfDocument document})
    : _frontmatter = snapshotYamlMap(document.frontmatter),
      _body = document.body,
      _hasFrontmatter = document.hasFrontmatter;

  /// The ID for the new concept.
  final OkfConceptId id;

  final Map<String, Object?> _frontmatter;
  final String _body;
  final bool _hasFrontmatter;

  /// A detached copy of the prospective concept document.
  ///
  /// Each access returns a new document over the frozen snapshot, so
  /// mutations made while inspecting one copy cannot change this
  /// description. Nested frontmatter collections are unmodifiable.
  OkfDocument get document => OkfDocument(
    frontmatter: _frontmatter,
    body: _body,
    hasFrontmatter: _hasFrontmatter,
  );
}

/// A request to update the managed portions of an existing concept.
final class OkfUpdateConceptChange extends OkfBundleChange {
  /// Creates an update-change description.
  OkfUpdateConceptChange({
    required this.id,
    Map<String, Object?> frontmatterChanges = const <String, Object?>{},
    this.body,
  }) : frontmatterChanges = snapshotYamlMap(frontmatterChanges);

  /// The concept to update.
  final OkfConceptId id;

  /// Frontmatter values to overlay while retaining unmanaged fields.
  ///
  /// Held as a deep, unmodifiable copy of the requested values.
  final Map<String, Object?> frontmatterChanges;

  /// Replacement Markdown body, or `null` to retain the existing body.
  final String? body;
}

/// A request to add a typed relationship between concepts.
final class OkfLinkConceptsChange extends OkfBundleChange {
  /// Creates a link-change description.
  ///
  /// Surrounding whitespace is removed from [relationship], whose resulting
  /// value must not be empty.
  OkfLinkConceptsChange({
    required this.source,
    required this.target,
    required String relationship,
  }) : relationship = relationship.trim() {
    if (this.relationship.isEmpty) {
      throw ArgumentError.value(
        relationship,
        'relationship',
        'must not be empty',
      );
    }
  }

  /// The concept that owns the relationship.
  final OkfConceptId source;

  /// The concept referenced by the relationship.
  final OkfConceptId target;

  /// The producer-defined relationship type.
  final String relationship;
}

/// A request to deprecate an existing concept.
final class OkfDeprecateConceptChange extends OkfBundleChange {
  /// Creates a deprecation-change description.
  const OkfDeprecateConceptChange({required this.id, this.note});

  /// The concept to deprecate.
  final OkfConceptId id;

  /// Optional context recorded with the lifecycle change.
  final String? note;
}

/// An ordered group of changes validated and applied as one operation.
final class OkfBundleChangeSet {
  /// Creates a change set in application order.
  OkfBundleChangeSet(Iterable<OkfBundleChange> changes)
    : changes = List<OkfBundleChange>.unmodifiable(changes);

  /// The changes in application order.
  final List<OkfBundleChange> changes;
}

/// A change that cannot be described against the bundle it targets.
///
/// This is the tool-error tier of the write path: creating a concept that
/// already exists, or touching one that does not, describes no bundle state
/// at all, so there is no report to refuse with. So is a reserved-file
/// projection that names a path other than an `index.md` or `log.md` file. A
/// change that describes a state the Spec rejects is an
/// [OkfPreparationRefused] instead.
final class OkfBundleChangeException implements Exception {
  /// Creates a change-description exception.
  const OkfBundleChangeException(this.message);

  /// A human-readable explanation.
  final String message;

  @override
  String toString() => 'OkfBundleChangeException: $message';
}
