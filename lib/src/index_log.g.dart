// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'index_log.dart';

// **************************************************************************
// AckModelGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

final _okfIndexEntryObject = Ack.object({
  'type': Ack.string(),
  'title': Ack.string(),
  'link': Ack.string(),
  'description': Ack.string(),
});

final _okfIndexEntryWireSchema = Ack.preserveBoundary(_okfIndexEntryObject);

final _okfIndexEntrySchema = _okfIndexEntryObject.codec<OkfIndexEntry>(
  decode: _$OkfIndexEntryFromRuntime,
  encode: _$OkfIndexEntryToRuntime,
);

/// Parses, validates, and encodes [OkfIndexEntry] values.
abstract final class OkfIndexEntrySchema {
  /// The typed schema, for composing [OkfIndexEntry] into other schemas.
  static AckSchema<Map<String, Object?>, OkfIndexEntry> get schema =>
      _okfIndexEntrySchema;

  /// The structural JSON map schema behind [schema].
  static AckSchema<Map<String, Object?>, Map<String, Object?>> get wireSchema =>
      _okfIndexEntryWireSchema;

  /// Validates [value] and creates the model.
  ///
  /// Throws an `AckException` when validation fails.
  static OkfIndexEntry parse(Object? value, {String? debugName}) =>
      _okfIndexEntrySchema.parse(value, debugName: debugName)!;

  /// Validates [value] and returns the model or the validation failure.
  static SchemaResult<OkfIndexEntry> safeParse(
    Object? value, {
    String? debugName,
  }) => _okfIndexEntrySchema.safeParse(value, debugName: debugName);

  /// Validates decoded [json] and creates the model.
  ///
  /// Throws an `AckException` when validation fails.
  static OkfIndexEntry fromJson(Map<String, dynamic> json) => parse(json);

  /// Validates [value] and encodes it as a JSON map.
  ///
  /// Throws an `AckException` when validation fails.
  static Map<String, Object?> encode(
    OkfIndexEntry value, {
    String? debugName,
  }) => _okfIndexEntrySchema.encode(value, debugName: debugName)!;

  /// Validates [value] and encodes it as a JSON map, returning the validation
  /// failure instead of throwing.
  static SchemaResult<Map<String, Object?>> safeEncode(
    OkfIndexEntry value, {
    String? debugName,
  }) => _okfIndexEntrySchema.safeEncode(value, debugName: debugName);

  /// The JSON Schema that describes [OkfIndexEntry].
  static Map<String, Object?> toJsonSchema() =>
      _okfIndexEntrySchema.toJsonSchema();

  /// The schema model that describes [OkfIndexEntry].
  static AckSchemaModel toSchemaModel() =>
      AckSchemaModelExtension(_okfIndexEntrySchema).toSchemaModel();
}

OkfIndexEntry _$OkfIndexEntryFromRuntime(Map<String, Object?> value) =>
    OkfIndexEntry(
      type: value['type'] as String,
      title: value['title'] as String,
      link: value['link'] as String,
      description: value['description'] as String,
    );

Map<String, Object?> _$OkfIndexEntryToRuntime(OkfIndexEntry model) =>
    <String, Object?>{
      'type': model.type,
      'title': model.title,
      'link': model.link,
      'description': model.description,
    };

/// Creates copies of [OkfIndexEntry] with selected fields replaced.
abstract interface class $OkfIndexEntryCopyWith<$Result> {
  /// Returns a copy with the given fields replaced.
  ///
  /// An omitted argument keeps the current value. An explicit `null` clears a
  /// nullable field.
  $Result call({
    String? type,
    String? title,
    String? link,
    String? description,
  });
}

final class _$OkfIndexEntryCopyWith
    implements $OkfIndexEntryCopyWith<OkfIndexEntry> {
  const _$OkfIndexEntryCopyWith(this._source);

  final OkfIndexEntry _source;

  @override
  OkfIndexEntry call({
    String? type,
    String? title,
    String? link,
    String? description,
  }) => OkfIndexEntry(
    type: type ?? _source.type,
    title: title ?? _source.title,
    link: link ?? _source.link,
    description: description ?? _source.description,
  );
}

mixin _$OkfIndexEntryAck {
  /// Creates a copy of this model with selected fields replaced.
  $OkfIndexEntryCopyWith<OkfIndexEntry> get copyWith =>
      _$OkfIndexEntryCopyWith(this as OkfIndexEntry);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! OkfIndexEntry || runtimeType != other.runtimeType) {
      return false;
    }
    final self = this as OkfIndexEntry;
    return deepEquals(self.type, other.type) &&
        deepEquals(self.title, other.title) &&
        deepEquals(self.link, other.link) &&
        deepEquals(self.description, other.description);
  }

  @override
  int get hashCode {
    final self = this as OkfIndexEntry;
    return Object.hashAll([
      runtimeType,
      deepHashCode(self.type),
      deepHashCode(self.title),
      deepHashCode(self.link),
      deepHashCode(self.description),
    ]);
  }

  @override
  String toString() {
    final self = this as OkfIndexEntry;
    return 'OkfIndexEntry(type: ${self.type}, title: ${self.title}, link: ${self.link}, description: ${self.description})';
  }

  /// Validates this model and encodes it for JSON.
  ///
  /// Throws an `AckException` when validation fails.
  Map<String, dynamic> toJson() => Map<String, dynamic>.from(
    OkfIndexEntrySchema.encode(this as OkfIndexEntry),
  );

  /// Validates this model and encodes it for JSON, returning the validation
  /// failure instead of throwing.
  SchemaResult<Map<String, Object?>> safeToJson() =>
      OkfIndexEntrySchema.safeEncode(this as OkfIndexEntry);
}

final _okfLogEntryObject = Ack.object({
  'date': Ack.string(),
  'action': Ack.string(),
  'description': Ack.string(),
});

final _okfLogEntryWireSchema = Ack.preserveBoundary(_okfLogEntryObject);

final _okfLogEntrySchema = _okfLogEntryObject.codec<OkfLogEntry>(
  decode: _$OkfLogEntryFromRuntime,
  encode: _$OkfLogEntryToRuntime,
);

/// Parses, validates, and encodes [OkfLogEntry] values.
abstract final class OkfLogEntrySchema {
  /// The typed schema, for composing [OkfLogEntry] into other schemas.
  static AckSchema<Map<String, Object?>, OkfLogEntry> get schema =>
      _okfLogEntrySchema;

  /// The structural JSON map schema behind [schema].
  static AckSchema<Map<String, Object?>, Map<String, Object?>> get wireSchema =>
      _okfLogEntryWireSchema;

  /// Validates [value] and creates the model.
  ///
  /// Throws an `AckException` when validation fails.
  static OkfLogEntry parse(Object? value, {String? debugName}) =>
      _okfLogEntrySchema.parse(value, debugName: debugName)!;

  /// Validates [value] and returns the model or the validation failure.
  static SchemaResult<OkfLogEntry> safeParse(
    Object? value, {
    String? debugName,
  }) => _okfLogEntrySchema.safeParse(value, debugName: debugName);

  /// Validates decoded [json] and creates the model.
  ///
  /// Throws an `AckException` when validation fails.
  static OkfLogEntry fromJson(Map<String, dynamic> json) => parse(json);

  /// Validates [value] and encodes it as a JSON map.
  ///
  /// Throws an `AckException` when validation fails.
  static Map<String, Object?> encode(OkfLogEntry value, {String? debugName}) =>
      _okfLogEntrySchema.encode(value, debugName: debugName)!;

  /// Validates [value] and encodes it as a JSON map, returning the validation
  /// failure instead of throwing.
  static SchemaResult<Map<String, Object?>> safeEncode(
    OkfLogEntry value, {
    String? debugName,
  }) => _okfLogEntrySchema.safeEncode(value, debugName: debugName);

  /// The JSON Schema that describes [OkfLogEntry].
  static Map<String, Object?> toJsonSchema() =>
      _okfLogEntrySchema.toJsonSchema();

  /// The schema model that describes [OkfLogEntry].
  static AckSchemaModel toSchemaModel() =>
      AckSchemaModelExtension(_okfLogEntrySchema).toSchemaModel();
}

OkfLogEntry _$OkfLogEntryFromRuntime(Map<String, Object?> value) => OkfLogEntry(
  date: value['date'] as String,
  action: value['action'] as String,
  description: value['description'] as String,
);

Map<String, Object?> _$OkfLogEntryToRuntime(OkfLogEntry model) =>
    <String, Object?>{
      'date': model.date,
      'action': model.action,
      'description': model.description,
    };

/// Creates copies of [OkfLogEntry] with selected fields replaced.
abstract interface class $OkfLogEntryCopyWith<$Result> {
  /// Returns a copy with the given fields replaced.
  ///
  /// An omitted argument keeps the current value. An explicit `null` clears a
  /// nullable field.
  $Result call({String? date, String? action, String? description});
}

final class _$OkfLogEntryCopyWith implements $OkfLogEntryCopyWith<OkfLogEntry> {
  const _$OkfLogEntryCopyWith(this._source);

  final OkfLogEntry _source;

  @override
  OkfLogEntry call({String? date, String? action, String? description}) =>
      OkfLogEntry(
        date: date ?? _source.date,
        action: action ?? _source.action,
        description: description ?? _source.description,
      );
}

mixin _$OkfLogEntryAck {
  /// Creates a copy of this model with selected fields replaced.
  $OkfLogEntryCopyWith<OkfLogEntry> get copyWith =>
      _$OkfLogEntryCopyWith(this as OkfLogEntry);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! OkfLogEntry || runtimeType != other.runtimeType) {
      return false;
    }
    final self = this as OkfLogEntry;
    return deepEquals(self.date, other.date) &&
        deepEquals(self.action, other.action) &&
        deepEquals(self.description, other.description);
  }

  @override
  int get hashCode {
    final self = this as OkfLogEntry;
    return Object.hashAll([
      runtimeType,
      deepHashCode(self.date),
      deepHashCode(self.action),
      deepHashCode(self.description),
    ]);
  }

  @override
  String toString() {
    final self = this as OkfLogEntry;
    return 'OkfLogEntry(date: ${self.date}, action: ${self.action}, description: ${self.description})';
  }

  /// Validates this model and encodes it for JSON.
  ///
  /// Throws an `AckException` when validation fails.
  Map<String, dynamic> toJson() =>
      Map<String, dynamic>.from(OkfLogEntrySchema.encode(this as OkfLogEntry));

  /// Validates this model and encodes it for JSON, returning the validation
  /// failure instead of throwing.
  SchemaResult<Map<String, Object?>> safeToJson() =>
      OkfLogEntrySchema.safeEncode(this as OkfLogEntry);
}
