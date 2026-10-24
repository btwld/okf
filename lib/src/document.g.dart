// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'document.dart';

// **************************************************************************
// AckModelGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

final _okfLegacyCitationObject = Ack.object({
  'number': Ack.integer(),
  'title': Ack.string(),
  'target': Ack.string(),
  'raw': Ack.string(),
});

final _okfLegacyCitationWireSchema = Ack.preserveBoundary(
  _okfLegacyCitationObject,
);

final _okfLegacyCitationSchema = _okfLegacyCitationObject
    .codec<OkfLegacyCitation>(
      decode: _$OkfLegacyCitationFromRuntime,
      encode: _$OkfLegacyCitationToRuntime,
    );

/// Parses, validates, and encodes [OkfLegacyCitation] values.
abstract final class OkfLegacyCitationSchema {
  /// The typed schema, for composing [OkfLegacyCitation] into other schemas.
  static AckSchema<Map<String, Object?>, OkfLegacyCitation> get schema =>
      _okfLegacyCitationSchema;

  /// The structural JSON map schema behind [schema].
  static AckSchema<Map<String, Object?>, Map<String, Object?>> get wireSchema =>
      _okfLegacyCitationWireSchema;

  /// Validates [value] and creates the model.
  ///
  /// Throws an `AckException` when validation fails.
  static OkfLegacyCitation parse(Object? value, {String? debugName}) =>
      _okfLegacyCitationSchema.parse(value, debugName: debugName)!;

  /// Validates [value] and returns the model or the validation failure.
  static SchemaResult<OkfLegacyCitation> safeParse(
    Object? value, {
    String? debugName,
  }) => _okfLegacyCitationSchema.safeParse(value, debugName: debugName);

  /// Validates decoded [json] and creates the model.
  ///
  /// Throws an `AckException` when validation fails.
  static OkfLegacyCitation fromJson(Map<String, dynamic> json) => parse(json);

  /// Validates [value] and encodes it as a JSON map.
  ///
  /// Throws an `AckException` when validation fails.
  static Map<String, Object?> encode(
    OkfLegacyCitation value, {
    String? debugName,
  }) => _okfLegacyCitationSchema.encode(value, debugName: debugName)!;

  /// Validates [value] and encodes it as a JSON map, returning the validation
  /// failure instead of throwing.
  static SchemaResult<Map<String, Object?>> safeEncode(
    OkfLegacyCitation value, {
    String? debugName,
  }) => _okfLegacyCitationSchema.safeEncode(value, debugName: debugName);

  /// The JSON Schema that describes [OkfLegacyCitation].
  static Map<String, Object?> toJsonSchema() =>
      _okfLegacyCitationSchema.toJsonSchema();

  /// The schema model that describes [OkfLegacyCitation].
  static AckSchemaModel toSchemaModel() =>
      AckSchemaModelExtension(_okfLegacyCitationSchema).toSchemaModel();
}

OkfLegacyCitation _$OkfLegacyCitationFromRuntime(Map<String, Object?> value) =>
    OkfLegacyCitation(
      number: value['number'] as int,
      title: value['title'] as String,
      target: value['target'] as String,
      raw: value['raw'] as String,
    );

Map<String, Object?> _$OkfLegacyCitationToRuntime(OkfLegacyCitation model) =>
    <String, Object?>{
      'number': model.number,
      'title': model.title,
      'target': model.target,
      'raw': model.raw,
    };

/// Creates copies of [OkfLegacyCitation] with selected fields replaced.
abstract interface class $OkfLegacyCitationCopyWith<$Result> {
  /// Returns a copy with the given fields replaced.
  ///
  /// An omitted argument keeps the current value. An explicit `null` clears a
  /// nullable field.
  $Result call({int? number, String? title, String? target, String? raw});
}

final class _$OkfLegacyCitationCopyWith
    implements $OkfLegacyCitationCopyWith<OkfLegacyCitation> {
  const _$OkfLegacyCitationCopyWith(this._source);

  final OkfLegacyCitation _source;

  @override
  OkfLegacyCitation call({
    int? number,
    String? title,
    String? target,
    String? raw,
  }) => OkfLegacyCitation(
    number: number ?? _source.number,
    title: title ?? _source.title,
    target: target ?? _source.target,
    raw: raw ?? _source.raw,
  );
}

mixin _$OkfLegacyCitationAck {
  /// Creates a copy of this model with selected fields replaced.
  $OkfLegacyCitationCopyWith<OkfLegacyCitation> get copyWith =>
      _$OkfLegacyCitationCopyWith(this as OkfLegacyCitation);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! OkfLegacyCitation || runtimeType != other.runtimeType) {
      return false;
    }
    final self = this as OkfLegacyCitation;
    return deepEquals(self.number, other.number) &&
        deepEquals(self.title, other.title) &&
        deepEquals(self.target, other.target) &&
        deepEquals(self.raw, other.raw);
  }

  @override
  int get hashCode {
    final self = this as OkfLegacyCitation;
    return Object.hashAll([
      runtimeType,
      deepHashCode(self.number),
      deepHashCode(self.title),
      deepHashCode(self.target),
      deepHashCode(self.raw),
    ]);
  }

  @override
  String toString() {
    final self = this as OkfLegacyCitation;
    return 'OkfLegacyCitation(number: ${self.number}, title: ${self.title}, target: ${self.target}, raw: ${self.raw})';
  }

  /// Validates this model and encodes it for JSON.
  ///
  /// Throws an `AckException` when validation fails.
  Map<String, dynamic> toJson() => Map<String, dynamic>.from(
    OkfLegacyCitationSchema.encode(this as OkfLegacyCitation),
  );

  /// Validates this model and encodes it for JSON, returning the validation
  /// failure instead of throwing.
  SchemaResult<Map<String, Object?>> safeToJson() =>
      OkfLegacyCitationSchema.safeEncode(this as OkfLegacyCitation);
}
