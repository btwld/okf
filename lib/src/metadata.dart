import 'dart:collection';
import 'iso_date.dart';

/// Frontmatter keys defined by OKF v0.2, including the v0.1 fallback key.
const Set<String> okfKnownFrontmatterKeys = <String>{
  'type',
  'title',
  'description',
  'resource',
  'tags',
  'sources',
  'usage_window',
  'generated',
  'verified',
  'status',
  'stale_after',
  'runtime',
  'parameters',
  'computation',
  'executor',
  'attester',
  'timestamp',
};

/// A trust tier derived from verification events.
enum OkfTrustTier {
  /// No usable verification event is present.
  unverified('unverified'),

  /// At least one non-human verification event is present.
  machineConfirmed('machine-confirmed'),

  /// At least one verifier uses the `human:` actor prefix.
  humanReviewed('human-reviewed');

  const OkfTrustTier(this.wireValue);

  /// The spelling used by the OKF specification.
  final String wireValue;
}

/// The lifecycle state of an OKF concept.
enum OkfLifecycleStatus {
  /// Not yet reviewed and potentially incomplete.
  draft('draft'),

  /// Ready for consumption. This is the default when `status` is absent.
  stable('stable'),

  /// Retained for links and history, but no longer current.
  deprecated('deprecated'),

  /// A producer-defined status that this version of the package does not know.
  unknown('unknown');

  const OkfLifecycleStatus(this.wireValue);

  factory OkfLifecycleStatus._parse(String? value) {
    switch (value?.trim().toLowerCase()) {
      case null:
      case '':
      case 'stable':
        return stable;
      case 'draft':
        return draft;
      case 'deprecated':
        return deprecated;
      default:
        return unknown;
    }
  }

  /// The stable lowercase representation.
  final String wireValue;
}

/// A date range framing one or more source usage counts.
final class OkfUsageWindow {
  OkfUsageWindow._(Map<String, Object?> raw)
    : raw = UnmodifiableMapView<String, Object?>(raw);

  /// Attempts to read a usage window from a YAML value.
  static OkfUsageWindow? tryParse(Object? value) {
    final map = _stringMap(value);
    return map == null ? null : OkfUsageWindow._(map);
  }

  /// The full mapping, including producer extensions.
  final Map<String, Object?> raw;

  /// Inclusive beginning of the window, when parseable.
  ///
  /// A date-only value is read as midnight UTC.
  DateTime? get from => _parseInstant(raw['from']);

  /// Inclusive end of the window, when parseable.
  ///
  /// A date-only value is read as midnight UTC.
  DateTime? get to => _parseInstant(raw['to']);

  /// The original scalar form of `from`.
  String? get rawFrom => _scalarString(raw['from']);

  /// The original scalar form of `to`.
  String? get rawTo => _scalarString(raw['to']);
}

/// A material from which an OKF concept was derived.
final class OkfSource {
  OkfSource._(Map<String, Object?> raw)
    : raw = UnmodifiableMapView<String, Object?>(raw);

  /// Attempts to read a source entry from a YAML value.
  static OkfSource? tryParse(Object? value) {
    final map = _stringMap(value);
    return map == null ? null : OkfSource._(map);
  }

  /// The full source mapping, including producer extensions.
  final Map<String, Object?> raw;

  /// Stable attribution key used by body footnotes.
  String? get id => _scalarString(raw['id']);

  /// The source URI, bundle path, or scope descriptor.
  String? get resource => _scalarString(raw['resource']);

  /// Human-readable source label.
  String? get title => _scalarString(raw['title']);

  /// The source's actor identity.
  String? get author => _scalarString(raw['author']);

  /// Coarse exercise count for this source.
  num? get usageCount => raw['usage_count'] is num
      ? raw['usage_count']! as num
      : num.tryParse(_scalarString(raw['usage_count']) ?? '');

  /// When the source itself last changed, when parseable.
  ///
  /// A date-only value is read as midnight UTC.
  DateTime? get lastModified => _parseInstant(raw['last_modified']);

  /// The original scalar form of `last_modified`.
  String? get rawLastModified => _scalarString(raw['last_modified']);

  /// A source-specific usage window, overriding the shared window.
  OkfUsageWindow? get usageWindow =>
      OkfUsageWindow.tryParse(raw['usage_window']);

  /// Returns the source-specific window, or [shared] when none is present.
  OkfUsageWindow? effectiveUsageWindow(OkfUsageWindow? shared) =>
      usageWindow ?? shared;
}

/// How the current content was generated.
final class OkfGeneration {
  OkfGeneration._(Map<String, Object?> raw)
    : raw = UnmodifiableMapView<String, Object?>(raw);

  /// Attempts to read a `generated` mapping.
  static OkfGeneration? tryParse(Object? value) {
    final map = _stringMap(value);
    return map == null ? null : OkfGeneration._(map);
  }

  /// The full mapping, including producer extensions.
  final Map<String, Object?> raw;

  /// Actor that produced the current content.
  String? get by => _scalarString(raw['by']);

  /// Original ISO 8601 spelling of the generation time.
  String? get at => _scalarString(raw['at']);

  /// Parsed generation instant, when valid.
  DateTime? get atDateTime => _parseDateTime(raw['at']);
}

/// An event that confirmed a concept against its source or resource.
final class OkfVerification {
  OkfVerification._(Map<String, Object?> raw)
    : raw = UnmodifiableMapView<String, Object?>(raw);

  /// Attempts to read a verification event mapping.
  static OkfVerification? tryParse(Object? value) {
    final map = _stringMap(value);
    return map == null ? null : OkfVerification._(map);
  }

  /// The full mapping, including producer extensions.
  final Map<String, Object?> raw;

  /// Actor that performed the verification.
  String? get by => _scalarString(raw['by']);

  /// Original ISO 8601 spelling of the verification time.
  String? get at => _scalarString(raw['at']);

  /// Parsed verification instant, when valid.
  DateTime? get atDateTime => _parseDateTime(raw['at']);

  /// Whether this event records a human reviewer.
  bool get isHuman {
    final actor = by?.trim();
    return actor != null &&
        actor.startsWith('human:') &&
        actor.length > 'human:'.length;
  }

  /// Whether this event contains the fields required by OKF v0.2.
  bool get isUsable {
    final actor = by?.trim();
    if (actor == null || actor.isEmpty || atDateTime == null) {
      return false;
    }
    return !actor.startsWith('human:') || isHuman;
  }
}

/// One declared, runtime-specific computation parameter.
final class OkfComputationParameter {
  OkfComputationParameter._(Map<String, Object?> raw)
    : raw = UnmodifiableMapView<String, Object?>(raw);

  /// Attempts to read a parameter mapping.
  static OkfComputationParameter? tryParse(Object? value) {
    final map = _stringMap(value);
    return map == null ? null : OkfComputationParameter._(map);
  }

  /// The full mapping, including producer extensions.
  final Map<String, Object?> raw;

  /// Parameter name.
  String? get name => _scalarString(raw['name']);

  /// Runtime-specific parameter type.
  String? get type => _scalarString(raw['type']);

  /// Whether the producer marked the parameter as required.
  ///
  /// `null` preserves the distinction between an omitted or malformed value
  /// and an explicit `false`.
  bool? get required =>
      raw['required'] is bool ? raw['required']! as bool : null;
}

/// Instructions for running an Attested Computation.
final class OkfExecutor {
  OkfExecutor._(Map<String, Object?> raw)
    : raw = UnmodifiableMapView<String, Object?>(raw);

  /// Attempts to read an executor mapping.
  static OkfExecutor? tryParse(Object? value) {
    final map = _stringMap(value);
    return map == null ? null : OkfExecutor._(map);
  }

  /// The full mapping, including producer extensions.
  final Map<String, Object?> raw;

  /// Path or URI naming the run instructions or code.
  String? get resource => _scalarString(raw['resource']);

  /// Fields a computation run must return.
  List<String> get receipt => _scalarList(raw['receipt']);
}

/// The deterministic check for an Attested Computation receipt.
final class OkfAttester {
  OkfAttester._(Map<String, Object?> raw)
    : raw = UnmodifiableMapView<String, Object?>(raw);

  /// Attempts to read an attester mapping.
  static OkfAttester? tryParse(Object? value) {
    final map = _stringMap(value);
    return map == null ? null : OkfAttester._(map);
  }

  /// The full mapping, including producer extensions.
  final Map<String, Object?> raw;

  /// Path or URI naming deterministic attester code.
  String? get resource => _scalarString(raw['resource']);
}

/// Typed view over an Attested Computation's top-level contract fields.
final class OkfComputationContract {
  const OkfComputationContract({
    required this.runtime,
    required this.parameters,
    required this.computation,
    required this.executor,
    required this.attester,
  });

  /// Runtime defining parameter binding and execution semantics.
  final String? runtime;

  /// Typed holes whose values an agent may supply.
  final List<OkfComputationParameter> parameters;

  /// Optional path to a computation file.
  final String? computation;

  /// Instructions for running the computation.
  final OkfExecutor? executor;

  /// Deterministic receipt checker.
  final OkfAttester? attester;
}

/// An order-preserving typed view over open OKF frontmatter.
///
/// Unknown keys remain available through [raw] and are never rejected.
final class OkfMetadata {
  /// Creates a typed view over [frontmatter].
  OkfMetadata.fromFrontmatter(Map<String, Object?> frontmatter)
    : raw = UnmodifiableMapView<String, Object?>(
        LinkedHashMap<String, Object?>.of(frontmatter),
      );

  /// The complete frontmatter mapping, including unknown extension fields.
  final Map<String, Object?> raw;

  /// Concept type. Scalar deviations are converted to their display form.
  String? get type => _scalarString(raw['type']);

  /// Optional display title.
  String? get title => _scalarString(raw['title']);

  /// Optional one-line summary.
  String? get description => _scalarString(raw['description']);

  /// Optional canonical URI for the described asset.
  String? get resource => _scalarString(raw['resource']);

  /// Cross-cutting category tags.
  List<String> get tags => _scalarList(raw['tags']);

  /// Materials from which this concept derives.
  List<OkfSource> get sources {
    final value = raw['sources'];
    if (value is! Iterable || value is String) {
      return const <OkfSource>[];
    }
    return List<OkfSource>.unmodifiable(
      value.map(OkfSource.tryParse).whereType<OkfSource>(),
    );
  }

  /// Shared date range framing source usage counts.
  OkfUsageWindow? get usageWindow =>
      OkfUsageWindow.tryParse(raw['usage_window']);

  /// How the current content was produced.
  OkfGeneration? get generated => OkfGeneration.tryParse(raw['generated']);

  /// Verification events normalized to a list.
  ///
  /// A bare mapping is treated as one event as required by OKF v0.2 §5.2.
  List<OkfVerification> get verified {
    final value = raw['verified'];
    if (value is Map) {
      final event = OkfVerification.tryParse(value);
      return event == null
          ? const <OkfVerification>[]
          : List<OkfVerification>.unmodifiable(<OkfVerification>[event]);
    }
    if (value is! Iterable || value is String) {
      return const <OkfVerification>[];
    }
    return List<OkfVerification>.unmodifiable(
      value.map(OkfVerification.tryParse).whereType<OkfVerification>(),
    );
  }

  /// Highest trust tier implied by [verified].
  OkfTrustTier get trustTier {
    final events = verified.where((event) => event.isUsable).toList();
    if (events.any((event) => event.isHuman)) {
      return OkfTrustTier.humanReviewed;
    }
    return events.isEmpty
        ? OkfTrustTier.unverified
        : OkfTrustTier.machineConfirmed;
  }

  /// Verification event with the latest parseable `at` value.
  OkfVerification? get latestVerification {
    OkfVerification? latest;
    DateTime? latestAt;
    for (final event in verified) {
      final at = event.atDateTime;
      if (at != null && (latestAt == null || at.isAfter(latestAt))) {
        latest = event;
        latestAt = at;
      }
    }
    return latest;
  }

  /// Original lifecycle status scalar.
  String? get rawStatus => _scalarString(raw['status']);

  /// Lifecycle status, defaulting to [OkfLifecycleStatus.stable].
  OkfLifecycleStatus get status => OkfLifecycleStatus._parse(rawStatus);

  /// Instant from which the concept is stale, when parseable.
  ///
  /// A date-only value, written before OKF revision 62432a0, is read as
  /// midnight UTC.
  DateTime? get staleAfter => _parseInstant(raw['stale_after']);

  /// Original `stale_after` scalar.
  String? get rawStaleAfter => _scalarString(raw['stale_after']);

  /// Whether this concept is stale at [now], which defaults to the current
  /// time.
  ///
  /// A concept is stale when `now >= stale_after`, compared as instants. An
  /// absent or malformed `stale_after` value is treated as not stale.
  bool isStale([DateTime? now]) {
    final boundary = staleAfter;
    if (boundary == null) {
      return false;
    }
    return !(now ?? DateTime.now()).isBefore(boundary);
  }

  /// Whether this concept is stale at the explicitly supplied instant.
  bool isStaleOn(DateTime now) => isStale(now);

  /// Legacy v0.1 `timestamp`, superseded by `generated.at`.
  String? get legacyTimestamp => _scalarString(raw['timestamp']);

  /// Current content-change instant, with the v0.1 fallback.
  ///
  /// The fallback is used only when `generated` is absent, matching §13.1.
  DateTime? get contentChangedAt {
    if (raw.containsKey('generated')) {
      return generated?.atDateTime;
    }
    return _parseDateTime(raw['timestamp']);
  }

  /// Whether the concept declares the Attested Computation type.
  bool get isAttestedComputation => type == 'Attested Computation';

  /// Runtime defining computation execution and parameter semantics.
  String? get runtime => _scalarString(raw['runtime']);

  /// Typed computation parameters; malformed list entries are ignored.
  List<OkfComputationParameter> get parameters {
    final value = raw['parameters'];
    if (value is! Iterable || value is String) {
      return const <OkfComputationParameter>[];
    }
    return List<OkfComputationParameter>.unmodifiable(
      value
          .map(OkfComputationParameter.tryParse)
          .whereType<OkfComputationParameter>(),
    );
  }

  /// Optional path to a file containing the computation.
  String? get computation => _scalarString(raw['computation']);

  /// Computation runner declaration.
  OkfExecutor? get executor => OkfExecutor.tryParse(raw['executor']);

  /// Computation receipt checker declaration.
  OkfAttester? get attester => OkfAttester.tryParse(raw['attester']);

  /// Typed computation contract for an Attested Computation concept.
  ///
  /// Returns `null` for other concept types, even if similarly named extension
  /// keys are present.
  OkfComputationContract? get computationContract => isAttestedComputation
      ? OkfComputationContract(
          runtime: runtime,
          parameters: parameters,
          computation: computation,
          executor: executor,
          attester: attester,
        )
      : null;

  /// Producer-defined top-level keys in insertion order.
  List<String> get extensionKeys => List<String>.unmodifiable(
    raw.keys.where((key) => !okfKnownFrontmatterKeys.contains(key)),
  );
}

Map<String, Object?>? _stringMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is String) {
      result[entry.key! as String] = entry.value;
    }
  }
  return result;
}

String? _scalarString(Object? value) {
  if (value == null || value is Map || value is Iterable && value is! String) {
    return null;
  }
  if (value is DateTime) {
    return value.toIso8601String();
  }
  return value.toString();
}

List<String> _scalarList(Object? value) {
  if (value is! Iterable || value is String) {
    return const <String>[];
  }
  return List<String>.unmodifiable(
    value.map(_scalarString).whereType<String>(),
  );
}

DateTime? _parseInstant(Object? value) {
  if (value is DateTime) {
    return value;
  }
  return parseOkfInstant(_scalarString(value));
}

DateTime? _parseDateTime(Object? value) {
  if (value is DateTime) {
    return value;
  }
  final raw = _scalarString(value);
  return raw == null ? null : parseIsoDateTime(raw);
}
