// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inputs.dart';

// **************************************************************************
// AckModelGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

/// Immutable model generated from `listConceptsInputSchema`.
final class ListConceptsInput {
  /// Creates a model without validating it.
  ///
  /// Use `parse` or `fromJson` for untrusted input. `toJson` validates
  /// the model while encoding it.
  ListConceptsInput({this.prefix, this.type, this.query});

  /// Validates [input] and creates the model.
  ///
  /// Throws an `AckException` when validation fails.
  factory ListConceptsInput.parse(Object? input) {
    return $ack.parse(input);
  }

  /// Validates decoded [json] and creates the model.
  ///
  /// Throws an `AckException` when validation fails.
  factory ListConceptsInput.fromJson(Map<String, dynamic> json) {
    return $ack.parse(json);
  }

  final String? prefix;

  final String? type;

  /// Case-insensitive substring matched against each concept ID and title.
  final String? query;

  /// The Ack adapter that parses and encodes this model.
  static final $ack = AckModelAdapter(
    schema: () => listConceptsInputSchema,
    fromRuntime: ListConceptsInput._fromAckRuntime,
    toRuntime: (model) => model._toAckRuntime(),
  );

  /// The Ack schema that parses input into [ListConceptsInput] and encodes it back.
  ///
  /// A shorthand for `$ack.modelSchema`, created once.
  static final schema = $ack.modelSchema;

  /// Validates [input] and returns the model or the validation failure.
  static SchemaResult<ListConceptsInput> safeParse(Object? input) =>
      $ack.safeParse(input);

  /// Validates this model and encodes it for JSON.
  ///
  /// Throws an `AckException` when validation fails.
  Map<String, dynamic> toJson() => Map<String, dynamic>.from($ack.encode(this));

  /// Validates this model and encodes it for JSON, returning the validation
  /// failure instead of throwing.
  SchemaResult<Map<String, Object?>> safeToJson() => $ack.safeEncode(this);

  /// Creates a copy of this model with selected fields replaced.
  $ListConceptsInputCopyWith<ListConceptsInput> get copyWith =>
      _$ListConceptsInputCopyWith(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ListConceptsInput &&
          runtimeType == other.runtimeType &&
          deepEquals(prefix, other.prefix) &&
          deepEquals(type, other.type) &&
          deepEquals(query, other.query));

  @override
  int get hashCode => Object.hashAll([
    runtimeType,
    deepHashCode(prefix),
    deepHashCode(type),
    deepHashCode(query),
  ]);

  @override
  String toString() =>
      'ListConceptsInput(prefix: $prefix, type: $type, query: $query)';

  static ListConceptsInput _fromAckRuntime(Map<String, Object?> value) =>
      ListConceptsInput(
        prefix: value['prefix'] as String?,
        type: value['type'] as String?,
        query: value['query'] as String?,
      );

  Map<String, Object?> _toAckRuntime() => <String, Object?>{
    'prefix': ?prefix,
    'type': ?type,
    'query': ?query,
  };
}

final class _ListConceptsInputCopyWithUnset {
  const _ListConceptsInputCopyWithUnset();
}

/// Creates copies of [ListConceptsInput] with selected fields replaced.
abstract interface class $ListConceptsInputCopyWith<$Result> {
  /// Returns a copy with the given fields replaced.
  ///
  /// An omitted argument keeps the current value. An explicit `null` clears a
  /// nullable field.
  $Result call({String? prefix, String? type, String? query});
}

final class _$ListConceptsInputCopyWith
    implements $ListConceptsInputCopyWith<ListConceptsInput> {
  const _$ListConceptsInputCopyWith(this._source);

  static const _ListConceptsInputCopyWithUnset _ackCopyWithUnset =
      _ListConceptsInputCopyWithUnset();

  final ListConceptsInput _source;

  @override
  ListConceptsInput call({
    Object? prefix = _ackCopyWithUnset,
    Object? type = _ackCopyWithUnset,
    Object? query = _ackCopyWithUnset,
  }) => ListConceptsInput(
    prefix: identical(prefix, _ackCopyWithUnset)
        ? _source.prefix
        : prefix as String?,
    type: identical(type, _ackCopyWithUnset) ? _source.type : type as String?,
    query: identical(query, _ackCopyWithUnset)
        ? _source.query
        : query as String?,
  );
}

/// Immutable model generated from `lookupConceptInputSchema`.
final class LookupConceptInput {
  /// Creates a model without validating it.
  ///
  /// Use `parse` or `fromJson` for untrusted input. `toJson` validates
  /// the model while encoding it.
  LookupConceptInput({required this.id});

  /// Validates [input] and creates the model.
  ///
  /// Throws an `AckException` when validation fails.
  factory LookupConceptInput.parse(Object? input) {
    return $ack.parse(input);
  }

  /// Validates decoded [json] and creates the model.
  ///
  /// Throws an `AckException` when validation fails.
  factory LookupConceptInput.fromJson(Map<String, dynamic> json) {
    return $ack.parse(json);
  }

  final OkfConceptId id;

  /// The Ack adapter that parses and encodes this model.
  static final $ack = AckModelAdapter(
    schema: () => lookupConceptInputSchema,
    fromRuntime: LookupConceptInput._fromAckRuntime,
    toRuntime: (model) => model._toAckRuntime(),
  );

  /// The Ack schema that parses input into [LookupConceptInput] and encodes it back.
  ///
  /// A shorthand for `$ack.modelSchema`, created once.
  static final schema = $ack.modelSchema;

  /// Validates [input] and returns the model or the validation failure.
  static SchemaResult<LookupConceptInput> safeParse(Object? input) =>
      $ack.safeParse(input);

  /// Validates this model and encodes it for JSON.
  ///
  /// Throws an `AckException` when validation fails.
  Map<String, dynamic> toJson() => Map<String, dynamic>.from($ack.encode(this));

  /// Validates this model and encodes it for JSON, returning the validation
  /// failure instead of throwing.
  SchemaResult<Map<String, Object?>> safeToJson() => $ack.safeEncode(this);

  /// Creates a copy of this model with selected fields replaced.
  $LookupConceptInputCopyWith<LookupConceptInput> get copyWith =>
      _$LookupConceptInputCopyWith(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LookupConceptInput &&
          runtimeType == other.runtimeType &&
          deepEquals(id, other.id));

  @override
  int get hashCode => Object.hashAll([runtimeType, deepHashCode(id)]);

  @override
  String toString() => 'LookupConceptInput(id: $id)';

  static LookupConceptInput _fromAckRuntime(Map<String, Object?> value) =>
      LookupConceptInput(id: value['id'] as OkfConceptId);

  Map<String, Object?> _toAckRuntime() => <String, Object?>{'id': id};
}

/// Creates copies of [LookupConceptInput] with selected fields replaced.
abstract interface class $LookupConceptInputCopyWith<$Result> {
  /// Returns a copy with the given fields replaced.
  ///
  /// An omitted argument keeps the current value. An explicit `null` clears a
  /// nullable field.
  $Result call({OkfConceptId? id});
}

final class _$LookupConceptInputCopyWith
    implements $LookupConceptInputCopyWith<LookupConceptInput> {
  const _$LookupConceptInputCopyWith(this._source);

  final LookupConceptInput _source;

  @override
  LookupConceptInput call({OkfConceptId? id}) =>
      LookupConceptInput(id: id ?? _source.id);
}

/// Immutable model generated from `validateInputSchema`.
final class ValidateInput {
  /// Creates a model without validating it.
  ///
  /// Use `parse` or `fromJson` for untrusted input. `toJson` validates
  /// the model while encoding it.
  ValidateInput({this.strict});

  /// Validates [input] and creates the model.
  ///
  /// Throws an `AckException` when validation fails.
  factory ValidateInput.parse(Object? input) {
    return $ack.parse(input);
  }

  /// Validates decoded [json] and creates the model.
  ///
  /// Throws an `AckException` when validation fails.
  factory ValidateInput.fromJson(Map<String, dynamic> json) {
    return $ack.parse(json);
  }

  /// Fail on advisories, as `--warnings-as-errors` does.
  final bool? strict;

  /// The Ack adapter that parses and encodes this model.
  static final $ack = AckModelAdapter(
    schema: () => validateInputSchema,
    fromRuntime: ValidateInput._fromAckRuntime,
    toRuntime: (model) => model._toAckRuntime(),
  );

  /// The Ack schema that parses input into [ValidateInput] and encodes it back.
  ///
  /// A shorthand for `$ack.modelSchema`, created once.
  static final schema = $ack.modelSchema;

  /// Validates [input] and returns the model or the validation failure.
  static SchemaResult<ValidateInput> safeParse(Object? input) =>
      $ack.safeParse(input);

  /// Validates this model and encodes it for JSON.
  ///
  /// Throws an `AckException` when validation fails.
  Map<String, dynamic> toJson() => Map<String, dynamic>.from($ack.encode(this));

  /// Validates this model and encodes it for JSON, returning the validation
  /// failure instead of throwing.
  SchemaResult<Map<String, Object?>> safeToJson() => $ack.safeEncode(this);

  /// Creates a copy of this model with selected fields replaced.
  $ValidateInputCopyWith<ValidateInput> get copyWith =>
      _$ValidateInputCopyWith(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ValidateInput &&
          runtimeType == other.runtimeType &&
          deepEquals(strict, other.strict));

  @override
  int get hashCode => Object.hashAll([runtimeType, deepHashCode(strict)]);

  @override
  String toString() => 'ValidateInput(strict: $strict)';

  static ValidateInput _fromAckRuntime(Map<String, Object?> value) =>
      ValidateInput(strict: value['strict'] as bool?);

  Map<String, Object?> _toAckRuntime() => <String, Object?>{'strict': ?strict};
}

final class _ValidateInputCopyWithUnset {
  const _ValidateInputCopyWithUnset();
}

/// Creates copies of [ValidateInput] with selected fields replaced.
abstract interface class $ValidateInputCopyWith<$Result> {
  /// Returns a copy with the given fields replaced.
  ///
  /// An omitted argument keeps the current value. An explicit `null` clears a
  /// nullable field.
  $Result call({bool? strict});
}

final class _$ValidateInputCopyWith
    implements $ValidateInputCopyWith<ValidateInput> {
  const _$ValidateInputCopyWith(this._source);

  static const _ValidateInputCopyWithUnset _ackCopyWithUnset =
      _ValidateInputCopyWithUnset();

  final ValidateInput _source;

  @override
  ValidateInput call({Object? strict = _ackCopyWithUnset}) => ValidateInput(
    strict: identical(strict, _ackCopyWithUnset)
        ? _source.strict
        : strict as bool?,
  );
}

/// Immutable model generated from `createConceptInputSchema`.
final class CreateConceptInput {
  /// Creates a model without validating it.
  ///
  /// Use `parse` or `fromJson` for untrusted input. `toJson` validates
  /// the model while encoding it.
  CreateConceptInput({
    required this.id,
    required this.type,
    this.title,
    this.description,
    List<String>? tags,
    this.body,
  }) : tags = switch (tags) {
         null => null,
         final fieldValue => List<String>.unmodifiable(
           fieldValue.map((item) => item),
         ),
       };

  /// Validates [input] and creates the model.
  ///
  /// Throws an `AckException` when validation fails.
  factory CreateConceptInput.parse(Object? input) {
    return $ack.parse(input);
  }

  /// Validates decoded [json] and creates the model.
  ///
  /// Throws an `AckException` when validation fails.
  factory CreateConceptInput.fromJson(Map<String, dynamic> json) {
    return $ack.parse(json);
  }

  final OkfConceptId id;

  final String type;

  final String? title;

  final String? description;

  final List<String>? tags;

  final String? body;

  /// The Ack adapter that parses and encodes this model.
  static final $ack = AckModelAdapter(
    schema: () => createConceptInputSchema,
    fromRuntime: CreateConceptInput._fromAckRuntime,
    toRuntime: (model) => model._toAckRuntime(),
  );

  /// The Ack schema that parses input into [CreateConceptInput] and encodes it back.
  ///
  /// A shorthand for `$ack.modelSchema`, created once.
  static final schema = $ack.modelSchema;

  /// Validates [input] and returns the model or the validation failure.
  static SchemaResult<CreateConceptInput> safeParse(Object? input) =>
      $ack.safeParse(input);

  /// Validates this model and encodes it for JSON.
  ///
  /// Throws an `AckException` when validation fails.
  Map<String, dynamic> toJson() => Map<String, dynamic>.from($ack.encode(this));

  /// Validates this model and encodes it for JSON, returning the validation
  /// failure instead of throwing.
  SchemaResult<Map<String, Object?>> safeToJson() => $ack.safeEncode(this);

  /// Creates a copy of this model with selected fields replaced.
  $CreateConceptInputCopyWith<CreateConceptInput> get copyWith =>
      _$CreateConceptInputCopyWith(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CreateConceptInput &&
          runtimeType == other.runtimeType &&
          deepEquals(id, other.id) &&
          deepEquals(type, other.type) &&
          deepEquals(title, other.title) &&
          deepEquals(description, other.description) &&
          deepEquals(tags, other.tags) &&
          deepEquals(body, other.body));

  @override
  int get hashCode => Object.hashAll([
    runtimeType,
    deepHashCode(id),
    deepHashCode(type),
    deepHashCode(title),
    deepHashCode(description),
    deepHashCode(tags),
    deepHashCode(body),
  ]);

  @override
  String toString() =>
      'CreateConceptInput(id: $id, type: $type, title: $title, description: $description, tags: $tags, body: $body)';

  static CreateConceptInput _fromAckRuntime(Map<String, Object?> value) =>
      CreateConceptInput(
        id: value['id'] as OkfConceptId,
        type: value['type'] as String,
        title: value['title'] as String?,
        description: value['description'] as String?,
        tags: switch (value['tags']) {
          null => null,
          final fieldValue => (fieldValue as List).cast<String>(),
        },
        body: value['body'] as String?,
      );

  Map<String, Object?> _toAckRuntime() => <String, Object?>{
    'id': id,
    'type': type,
    'title': ?title,
    'description': ?description,
    'tags': ?tags?.map((item) => item).toList(growable: false),
    'body': ?body,
  };
}

final class _CreateConceptInputCopyWithUnset {
  const _CreateConceptInputCopyWithUnset();
}

/// Creates copies of [CreateConceptInput] with selected fields replaced.
abstract interface class $CreateConceptInputCopyWith<$Result> {
  /// Returns a copy with the given fields replaced.
  ///
  /// An omitted argument keeps the current value. An explicit `null` clears a
  /// nullable field.
  $Result call({
    OkfConceptId? id,
    String? type,
    String? title,
    String? description,
    List<String>? tags,
    String? body,
  });
}

final class _$CreateConceptInputCopyWith
    implements $CreateConceptInputCopyWith<CreateConceptInput> {
  const _$CreateConceptInputCopyWith(this._source);

  static const _CreateConceptInputCopyWithUnset _ackCopyWithUnset =
      _CreateConceptInputCopyWithUnset();

  final CreateConceptInput _source;

  @override
  CreateConceptInput call({
    OkfConceptId? id,
    String? type,
    Object? title = _ackCopyWithUnset,
    Object? description = _ackCopyWithUnset,
    Object? tags = _ackCopyWithUnset,
    Object? body = _ackCopyWithUnset,
  }) => CreateConceptInput(
    id: id ?? _source.id,
    type: type ?? _source.type,
    title: identical(title, _ackCopyWithUnset)
        ? _source.title
        : title as String?,
    description: identical(description, _ackCopyWithUnset)
        ? _source.description
        : description as String?,
    tags: identical(tags, _ackCopyWithUnset)
        ? _source.tags
        : tags as List<String>?,
    body: identical(body, _ackCopyWithUnset) ? _source.body : body as String?,
  );
}

/// Immutable model generated from `updateConceptInputSchema`.
final class UpdateConceptInput {
  /// Creates a model without validating it.
  ///
  /// Use `parse` or `fromJson` for untrusted input. `toJson` validates
  /// the model while encoding it.
  UpdateConceptInput({
    required this.id,
    this.type,
    this.title,
    this.description,
    List<String>? tags,
    this.body,
  }) : tags = switch (tags) {
         null => null,
         final fieldValue => List<String>.unmodifiable(
           fieldValue.map((item) => item),
         ),
       };

  /// Validates [input] and creates the model.
  ///
  /// Throws an `AckException` when validation fails.
  factory UpdateConceptInput.parse(Object? input) {
    return $ack.parse(input);
  }

  /// Validates decoded [json] and creates the model.
  ///
  /// Throws an `AckException` when validation fails.
  factory UpdateConceptInput.fromJson(Map<String, dynamic> json) {
    return $ack.parse(json);
  }

  final OkfConceptId id;

  final String? type;

  final String? title;

  final String? description;

  final List<String>? tags;

  final String? body;

  /// The Ack adapter that parses and encodes this model.
  static final $ack = AckModelAdapter(
    schema: () => updateConceptInputSchema,
    fromRuntime: UpdateConceptInput._fromAckRuntime,
    toRuntime: (model) => model._toAckRuntime(),
  );

  /// The Ack schema that parses input into [UpdateConceptInput] and encodes it back.
  ///
  /// A shorthand for `$ack.modelSchema`, created once.
  static final schema = $ack.modelSchema;

  /// Validates [input] and returns the model or the validation failure.
  static SchemaResult<UpdateConceptInput> safeParse(Object? input) =>
      $ack.safeParse(input);

  /// Validates this model and encodes it for JSON.
  ///
  /// Throws an `AckException` when validation fails.
  Map<String, dynamic> toJson() => Map<String, dynamic>.from($ack.encode(this));

  /// Validates this model and encodes it for JSON, returning the validation
  /// failure instead of throwing.
  SchemaResult<Map<String, Object?>> safeToJson() => $ack.safeEncode(this);

  /// Creates a copy of this model with selected fields replaced.
  $UpdateConceptInputCopyWith<UpdateConceptInput> get copyWith =>
      _$UpdateConceptInputCopyWith(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UpdateConceptInput &&
          runtimeType == other.runtimeType &&
          deepEquals(id, other.id) &&
          deepEquals(type, other.type) &&
          deepEquals(title, other.title) &&
          deepEquals(description, other.description) &&
          deepEquals(tags, other.tags) &&
          deepEquals(body, other.body));

  @override
  int get hashCode => Object.hashAll([
    runtimeType,
    deepHashCode(id),
    deepHashCode(type),
    deepHashCode(title),
    deepHashCode(description),
    deepHashCode(tags),
    deepHashCode(body),
  ]);

  @override
  String toString() =>
      'UpdateConceptInput(id: $id, type: $type, title: $title, description: $description, tags: $tags, body: $body)';

  static UpdateConceptInput _fromAckRuntime(Map<String, Object?> value) =>
      UpdateConceptInput(
        id: value['id'] as OkfConceptId,
        type: value['type'] as String?,
        title: value['title'] as String?,
        description: value['description'] as String?,
        tags: switch (value['tags']) {
          null => null,
          final fieldValue => (fieldValue as List).cast<String>(),
        },
        body: value['body'] as String?,
      );

  Map<String, Object?> _toAckRuntime() => <String, Object?>{
    'id': id,
    'type': ?type,
    'title': ?title,
    'description': ?description,
    'tags': ?tags?.map((item) => item).toList(growable: false),
    'body': ?body,
  };
}

final class _UpdateConceptInputCopyWithUnset {
  const _UpdateConceptInputCopyWithUnset();
}

/// Creates copies of [UpdateConceptInput] with selected fields replaced.
abstract interface class $UpdateConceptInputCopyWith<$Result> {
  /// Returns a copy with the given fields replaced.
  ///
  /// An omitted argument keeps the current value. An explicit `null` clears a
  /// nullable field.
  $Result call({
    OkfConceptId? id,
    String? type,
    String? title,
    String? description,
    List<String>? tags,
    String? body,
  });
}

final class _$UpdateConceptInputCopyWith
    implements $UpdateConceptInputCopyWith<UpdateConceptInput> {
  const _$UpdateConceptInputCopyWith(this._source);

  static const _UpdateConceptInputCopyWithUnset _ackCopyWithUnset =
      _UpdateConceptInputCopyWithUnset();

  final UpdateConceptInput _source;

  @override
  UpdateConceptInput call({
    OkfConceptId? id,
    Object? type = _ackCopyWithUnset,
    Object? title = _ackCopyWithUnset,
    Object? description = _ackCopyWithUnset,
    Object? tags = _ackCopyWithUnset,
    Object? body = _ackCopyWithUnset,
  }) => UpdateConceptInput(
    id: id ?? _source.id,
    type: identical(type, _ackCopyWithUnset) ? _source.type : type as String?,
    title: identical(title, _ackCopyWithUnset)
        ? _source.title
        : title as String?,
    description: identical(description, _ackCopyWithUnset)
        ? _source.description
        : description as String?,
    tags: identical(tags, _ackCopyWithUnset)
        ? _source.tags
        : tags as List<String>?,
    body: identical(body, _ackCopyWithUnset) ? _source.body : body as String?,
  );
}

/// Immutable model generated from `linkConceptsInputSchema`.
final class LinkConceptsInput {
  /// Creates a model without validating it.
  ///
  /// Use `parse` or `fromJson` for untrusted input. `toJson` validates
  /// the model while encoding it.
  LinkConceptsInput({
    required this.source,
    required this.target,
    required this.relationship,
  });

  /// Validates [input] and creates the model.
  ///
  /// Throws an `AckException` when validation fails.
  factory LinkConceptsInput.parse(Object? input) {
    return $ack.parse(input);
  }

  /// Validates decoded [json] and creates the model.
  ///
  /// Throws an `AckException` when validation fails.
  factory LinkConceptsInput.fromJson(Map<String, dynamic> json) {
    return $ack.parse(json);
  }

  final OkfConceptId source;

  final OkfConceptId target;

  /// Producer-defined relationship type.
  final String relationship;

  /// The Ack adapter that parses and encodes this model.
  static final $ack = AckModelAdapter(
    schema: () => linkConceptsInputSchema,
    fromRuntime: LinkConceptsInput._fromAckRuntime,
    toRuntime: (model) => model._toAckRuntime(),
  );

  /// The Ack schema that parses input into [LinkConceptsInput] and encodes it back.
  ///
  /// A shorthand for `$ack.modelSchema`, created once.
  static final schema = $ack.modelSchema;

  /// Validates [input] and returns the model or the validation failure.
  static SchemaResult<LinkConceptsInput> safeParse(Object? input) =>
      $ack.safeParse(input);

  /// Validates this model and encodes it for JSON.
  ///
  /// Throws an `AckException` when validation fails.
  Map<String, dynamic> toJson() => Map<String, dynamic>.from($ack.encode(this));

  /// Validates this model and encodes it for JSON, returning the validation
  /// failure instead of throwing.
  SchemaResult<Map<String, Object?>> safeToJson() => $ack.safeEncode(this);

  /// Creates a copy of this model with selected fields replaced.
  $LinkConceptsInputCopyWith<LinkConceptsInput> get copyWith =>
      _$LinkConceptsInputCopyWith(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LinkConceptsInput &&
          runtimeType == other.runtimeType &&
          deepEquals(source, other.source) &&
          deepEquals(target, other.target) &&
          deepEquals(relationship, other.relationship));

  @override
  int get hashCode => Object.hashAll([
    runtimeType,
    deepHashCode(source),
    deepHashCode(target),
    deepHashCode(relationship),
  ]);

  @override
  String toString() =>
      'LinkConceptsInput(source: $source, target: $target, relationship: $relationship)';

  static LinkConceptsInput _fromAckRuntime(Map<String, Object?> value) =>
      LinkConceptsInput(
        source: value['source'] as OkfConceptId,
        target: value['target'] as OkfConceptId,
        relationship: value['relationship'] as String,
      );

  Map<String, Object?> _toAckRuntime() => <String, Object?>{
    'source': source,
    'target': target,
    'relationship': relationship,
  };
}

/// Creates copies of [LinkConceptsInput] with selected fields replaced.
abstract interface class $LinkConceptsInputCopyWith<$Result> {
  /// Returns a copy with the given fields replaced.
  ///
  /// An omitted argument keeps the current value. An explicit `null` clears a
  /// nullable field.
  $Result call({
    OkfConceptId? source,
    OkfConceptId? target,
    String? relationship,
  });
}

final class _$LinkConceptsInputCopyWith
    implements $LinkConceptsInputCopyWith<LinkConceptsInput> {
  const _$LinkConceptsInputCopyWith(this._source);

  final LinkConceptsInput _source;

  @override
  LinkConceptsInput call({
    OkfConceptId? source,
    OkfConceptId? target,
    String? relationship,
  }) => LinkConceptsInput(
    source: source ?? _source.source,
    target: target ?? _source.target,
    relationship: relationship ?? _source.relationship,
  );
}

/// Immutable model generated from `deprecateConceptInputSchema`.
final class DeprecateConceptInput {
  /// Creates a model without validating it.
  ///
  /// Use `parse` or `fromJson` for untrusted input. `toJson` validates
  /// the model while encoding it.
  DeprecateConceptInput({required this.id, this.note});

  /// Validates [input] and creates the model.
  ///
  /// Throws an `AckException` when validation fails.
  factory DeprecateConceptInput.parse(Object? input) {
    return $ack.parse(input);
  }

  /// Validates decoded [json] and creates the model.
  ///
  /// Throws an `AckException` when validation fails.
  factory DeprecateConceptInput.fromJson(Map<String, dynamic> json) {
    return $ack.parse(json);
  }

  final OkfConceptId id;

  /// Context recorded with the lifecycle change.
  final String? note;

  /// The Ack adapter that parses and encodes this model.
  static final $ack = AckModelAdapter(
    schema: () => deprecateConceptInputSchema,
    fromRuntime: DeprecateConceptInput._fromAckRuntime,
    toRuntime: (model) => model._toAckRuntime(),
  );

  /// The Ack schema that parses input into [DeprecateConceptInput] and encodes it back.
  ///
  /// A shorthand for `$ack.modelSchema`, created once.
  static final schema = $ack.modelSchema;

  /// Validates [input] and returns the model or the validation failure.
  static SchemaResult<DeprecateConceptInput> safeParse(Object? input) =>
      $ack.safeParse(input);

  /// Validates this model and encodes it for JSON.
  ///
  /// Throws an `AckException` when validation fails.
  Map<String, dynamic> toJson() => Map<String, dynamic>.from($ack.encode(this));

  /// Validates this model and encodes it for JSON, returning the validation
  /// failure instead of throwing.
  SchemaResult<Map<String, Object?>> safeToJson() => $ack.safeEncode(this);

  /// Creates a copy of this model with selected fields replaced.
  $DeprecateConceptInputCopyWith<DeprecateConceptInput> get copyWith =>
      _$DeprecateConceptInputCopyWith(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeprecateConceptInput &&
          runtimeType == other.runtimeType &&
          deepEquals(id, other.id) &&
          deepEquals(note, other.note));

  @override
  int get hashCode =>
      Object.hashAll([runtimeType, deepHashCode(id), deepHashCode(note)]);

  @override
  String toString() => 'DeprecateConceptInput(id: $id, note: $note)';

  static DeprecateConceptInput _fromAckRuntime(Map<String, Object?> value) =>
      DeprecateConceptInput(
        id: value['id'] as OkfConceptId,
        note: value['note'] as String?,
      );

  Map<String, Object?> _toAckRuntime() => <String, Object?>{
    'id': id,
    'note': ?note,
  };
}

final class _DeprecateConceptInputCopyWithUnset {
  const _DeprecateConceptInputCopyWithUnset();
}

/// Creates copies of [DeprecateConceptInput] with selected fields replaced.
abstract interface class $DeprecateConceptInputCopyWith<$Result> {
  /// Returns a copy with the given fields replaced.
  ///
  /// An omitted argument keeps the current value. An explicit `null` clears a
  /// nullable field.
  $Result call({OkfConceptId? id, String? note});
}

final class _$DeprecateConceptInputCopyWith
    implements $DeprecateConceptInputCopyWith<DeprecateConceptInput> {
  const _$DeprecateConceptInputCopyWith(this._source);

  static const _DeprecateConceptInputCopyWithUnset _ackCopyWithUnset =
      _DeprecateConceptInputCopyWithUnset();

  final DeprecateConceptInput _source;

  @override
  DeprecateConceptInput call({
    OkfConceptId? id,
    Object? note = _ackCopyWithUnset,
  }) => DeprecateConceptInput(
    id: id ?? _source.id,
    note: identical(note, _ackCopyWithUnset) ? _source.note : note as String?,
  );
}
