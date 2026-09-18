import 'package:ack/ack.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;

import 'ack_error.dart';
import 'bundle.dart';
import 'concept_id.dart';
import 'control_characters.dart';
import 'link_path.dart';

/// Current schema version emitted by [OkfGraph.toJson].
const okfGraphJsonSchemaVersion = '1';

const _graphQueryTypesField = 'types';
const _graphQueryPathPrefixesField = 'path_prefixes';
const _graphQueryResolutionsField = 'resolutions';

// One schema owns the JSON parser's constraints and the schema advertised by
// MCP. The public query keeps its Set-based API and constructor semantics.
final _graphQuerySchema =
    Ack.object({
      _graphQueryTypesField: Ack.list(
        Ack.string().minLength(1),
      ).unique().optional(),
      _graphQueryPathPrefixesField: Ack.list(
        Ack.string().minLength(1),
      ).unique().optional(),
      _graphQueryResolutionsField: Ack.list(
        Ack.enumString(
          OkfGraphResolution.values
              .map((resolution) => resolution.wireValue)
              .toList(),
        ),
      ).unique().optional(),
    }).codec<OkfGraphQuery>(
      decode: (data) => OkfGraphQuery(
        conceptTypes: data[_graphQueryTypesField] as List<String>? ?? const [],
        pathPrefixes:
            data[_graphQueryPathPrefixesField] as List<String>? ?? const [],
        resolutions:
            (data[_graphQueryResolutionsField] as List<String>? ?? const [])
                .map(OkfGraphResolution.fromWireValue),
      ),
      encode: (query) => query.toJson(),
    );

/// Where a graph relationship was discovered.
enum OkfGraphEdgeOrigin {
  bodyLink('body'),
  resource('resource'),
  sourceResource('sources.resource'),
  computation('computation'),
  executorResource('executor.resource'),
  attesterResource('attester.resource');

  const OkfGraphEdgeOrigin(this.wireValue);

  /// Stable JSON and diagram label.
  final String wireValue;
}

/// How an edge target was classified.
enum OkfGraphResolution {
  resolvedConcept('resolved-concept'),
  resolvedAsset('resolved-asset'),
  external('external'),
  descriptor('descriptor'),
  unresolved('unresolved'),
  invalid('invalid');

  const OkfGraphResolution(this.wireValue);

  /// Parses the stable JSON representation.
  factory OkfGraphResolution.fromWireValue(String value) {
    for (final resolution in values) {
      if (resolution.wireValue == value) {
        return resolution;
      }
    }
    throw FormatException('Unknown graph resolution', value);
  }

  /// Stable JSON representation.
  final String wireValue;
}

/// Composable filters for constructing an [OkfGraph].
///
/// Values within one field are alternatives. Non-empty fields are combined,
/// so a node must match both [conceptTypes] and [pathPrefixes].
final class OkfGraphQuery {
  OkfGraphQuery({
    Iterable<String> conceptTypes = const <String>[],
    Iterable<String> pathPrefixes = const <String>[],
    Iterable<OkfGraphResolution> resolutions = const <OkfGraphResolution>[],
  }) : conceptTypes = _queryStringSet(conceptTypes, 'conceptTypes'),
       pathPrefixes = _queryStringSet(pathPrefixes, 'pathPrefixes'),
       resolutions = Set<OkfGraphResolution>.unmodifiable(resolutions);

  /// Parses a graph query from the shape described by [jsonSchema].
  factory OkfGraphQuery.fromJson(Map<String, Object?> json) {
    try {
      return _graphQuerySchema.parse(json)!;
    } on AckException catch (error) {
      throw FormatException(
        'Invalid graph query: ${formatAckErrors(error)}',
        json,
      );
    }
  }

  /// JSON Schema for adapters that accept graph queries as structured input.
  static Map<String, Object?> get jsonSchema =>
      _graphQuerySchema.toJsonSchema();

  bool get _isEmpty =>
      conceptTypes.isEmpty && pathPrefixes.isEmpty && resolutions.isEmpty;

  /// Producer-defined concept types to include.
  final Set<String> conceptTypes;

  /// Bundle areas to include, matched per [OkfConceptId.isWithin]: a value
  /// names a concept or a directory, and matches whole path segments only.
  final Set<String> pathPrefixes;

  /// Edge resolution states to include.
  final Set<OkfGraphResolution> resolutions;

  /// Converts this query to the shape described by [jsonSchema].
  Map<String, Object?> toJson() => <String, Object?>{
    _graphQueryTypesField: conceptTypes.toList(growable: false),
    _graphQueryPathPrefixesField: pathPrefixes.toList(growable: false),
    _graphQueryResolutionsField: resolutions
        .map((resolution) => resolution.wireValue)
        .toList(growable: false),
  };

  bool _matchesNode(OkfGraphNode node) =>
      (conceptTypes.isEmpty || conceptTypes.contains(node.type)) &&
      (pathPrefixes.isEmpty || pathPrefixes.any(node.id.isWithin));

  bool _matchesEdge(OkfGraphEdge edge) =>
      resolutions.isEmpty || resolutions.contains(edge.resolution);
}

Set<String> _queryStringSet(Iterable<String> values, String name) {
  final result = Set<String>.unmodifiable(values);
  if (result.any((value) => value.isEmpty)) {
    throw ArgumentError.value(values, name, 'Values must not be empty');
  }
  return result;
}

/// A concept node in an [OkfGraph].
final class OkfGraphNode {
  const OkfGraphNode({
    required this.id,
    required this.type,
    required this.title,
    required this.status,
    required this.trustTier,
    required this.staleAfter,
  });

  /// Logical concept ID.
  final OkfConceptId id;

  /// Producer-defined concept type.
  final String type;

  /// Display title, falling back to the concept basename.
  final String title;

  /// Lifecycle status in its wire representation.
  final String status;

  /// Derived trust tier in its wire representation.
  final String trustTier;

  /// Raw `stale_after` scalar when present.
  final String? staleAfter;

  /// Converts this node to a JSON-compatible object.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'path': id.documentPath,
    'type': type,
    'title': title,
    'status': status,
    'trust_tier': trustTier,
    if (staleAfter != null) 'stale_after': staleAfter,
  };
}

/// A directed relationship originating at an OKF concept.
final class OkfGraphEdge {
  const OkfGraphEdge({
    required this.source,
    required this.rawTarget,
    required this.origin,
    required this.resolution,
    this.resolvedPath,
    this.targetConcept,
  });

  /// Source concept.
  final OkfConceptId source;

  /// Target exactly as written by the producer.
  final String rawTarget;

  /// Field or Markdown body in which the relationship appeared.
  final OkfGraphEdgeOrigin origin;

  /// Result of resolving the target against the bundle.
  final OkfGraphResolution resolution;

  /// Normalized bundle-relative target path, if path resolution succeeded.
  final String? resolvedPath;

  /// Target concept when [resolution] is
  /// [OkfGraphResolution.resolvedConcept].
  final OkfConceptId? targetConcept;

  /// Converts this edge to a JSON-compatible object.
  Map<String, Object?> toJson() => <String, Object?>{
    'source': source.value,
    'raw_target': rawTarget,
    'origin': origin.wireValue,
    'resolution': resolution.wireValue,
    if (resolvedPath != null) 'resolved_path': resolvedPath,
    if (targetConcept != null) 'target_concept': targetConcept!.value,
  };
}

/// A deterministic graph derived from concept links and path-valued fields.
final class OkfGraph {
  OkfGraph._({
    required List<OkfGraphNode> nodes,
    required List<OkfGraphEdge> edges,
  }) : nodes = List<OkfGraphNode>.unmodifiable(nodes),
       edges = List<OkfGraphEdge>.unmodifiable(edges);

  /// Builds a graph without rejecting broken or external references.
  factory OkfGraph.fromBundle(OkfBundle bundle, {OkfGraphQuery? query}) {
    final nodes = <OkfGraphNode>[];
    final edges = <OkfGraphEdge>[];

    for (final entry in bundle.concepts.entries) {
      final document = entry.value;
      final metadata = document.metadata;
      nodes.add(
        OkfGraphNode(
          id: entry.key,
          type: _scalarString(document.frontmatter['type']) ?? '',
          title:
              _scalarString(document.frontmatter['title']) ??
              entry.key.basename,
          status: metadata.status.wireValue,
          trustTier: metadata.trustTier.wireValue,
          staleAfter: _scalarString(document.frontmatter['stale_after']),
        ),
      );

      void addEdge(String rawTarget, OkfGraphEdgeOrigin origin) {
        final target = rawTarget.trim();
        if (target.isEmpty) {
          return;
        }
        final resolved = _resolveTarget(
          bundle,
          entry.key,
          target,
          descriptorAllowed: origin == OkfGraphEdgeOrigin.sourceResource,
        );
        edges.add(
          OkfGraphEdge(
            source: entry.key,
            rawTarget: target,
            origin: origin,
            resolution: resolved.resolution,
            resolvedPath: resolved.path,
            targetConcept: resolved.concept,
          ),
        );
      }

      for (final href in _markdownLinks(document.body)) {
        addEdge(href, OkfGraphEdgeOrigin.bodyLink);
      }
      _addScalarEdge(
        document.frontmatter['resource'],
        OkfGraphEdgeOrigin.resource,
        addEdge,
      );
      _addSourceEdges(document.frontmatter['sources'], addEdge);
      _addScalarEdge(
        document.frontmatter['computation'],
        OkfGraphEdgeOrigin.computation,
        addEdge,
      );
      _addNestedResourceEdge(
        document.frontmatter['executor'],
        OkfGraphEdgeOrigin.executorResource,
        addEdge,
      );
      _addNestedResourceEdge(
        document.frontmatter['attester'],
        OkfGraphEdgeOrigin.attesterResource,
        addEdge,
      );
    }

    nodes.sort((left, right) => left.id.compareTo(right.id));
    edges.sort(_compareEdges);
    final uniqueEdges = <OkfGraphEdge>[];
    String? previousKey;
    for (final edge in edges) {
      final key =
          '${edge.source.value}\u0000${edge.origin.wireValue}\u0000'
          '${edge.rawTarget}\u0000${edge.resolution.wireValue}\u0000'
          '${edge.resolvedPath ?? ''}';
      if (key != previousKey) {
        uniqueEdges.add(edge);
        previousKey = key;
      }
    }

    if (query == null || query._isEmpty) {
      return OkfGraph._(nodes: nodes, edges: uniqueEdges);
    }

    final filteredNodes = nodes.where(query._matchesNode).toList();
    final nodeIds = filteredNodes.map((node) => node.id).toSet();
    final filteredEdges = uniqueEdges.where(
      (edge) =>
          nodeIds.contains(edge.source) &&
          (edge.targetConcept == null ||
              nodeIds.contains(edge.targetConcept)) &&
          query._matchesEdge(edge),
    );
    return OkfGraph._(nodes: filteredNodes, edges: filteredEdges.toList());
  }

  /// Concept nodes sorted by ID.
  final List<OkfGraphNode> nodes;

  /// Relationship edges sorted by source, origin, and raw target.
  final List<OkfGraphEdge> edges;

  /// Converts this graph to a JSON-compatible object.
  Map<String, Object?> toJson() => <String, Object?>{
    'schema_version': okfGraphJsonSchemaVersion,
    'nodes': nodes.map((node) => node.toJson()).toList(growable: false),
    'edges': edges.map((edge) => edge.toJson()).toList(growable: false),
  };

  /// Renders this graph in Graphviz DOT format.
  String toDot() {
    final lines = <String>['digraph okf {', '  rankdir=LR;'];
    for (final node in nodes) {
      lines.add(
        '  "${_dot('concept:${node.id.value}')}" '
        '[label="${_dot('${node.title}\n${node.id.value}')}"];',
      );
    }

    final virtualIds = _virtualTargetIds();
    final emittedVirtualIds = <String>{};
    for (final entry in virtualIds.entries) {
      if (!emittedVirtualIds.add(entry.value)) {
        continue;
      }
      lines.add(
        '  "${_dot(entry.value)}" '
        '[label="${_dot(entry.key.rawTarget)}", style=dashed];',
      );
    }
    for (final edge in edges) {
      final target = edge.targetConcept == null
          ? virtualIds[edge]!
          : 'concept:${edge.targetConcept!.value}';
      lines.add(
        '  "${_dot('concept:${edge.source.value}')}" -> '
        '"${_dot(target)}" '
        '[label="${_dot(edge.origin.wireValue)}"];',
      );
    }
    lines.add('}');
    return '${lines.join('\n')}\n';
  }

  /// Renders this graph as a Mermaid flowchart.
  String toMermaid() {
    final lines = <String>['flowchart LR'];
    final nodeIds = <OkfConceptId, String>{
      for (var index = 0; index < nodes.length; index++)
        nodes[index].id: 'n$index',
    };
    for (final node in nodes) {
      lines.add(
        '  ${nodeIds[node.id]}["${_mermaid('${node.title}\n${node.id.value}')}"]',
      );
    }

    final virtualIds = _virtualTargetIds(
      prefix: 'x',
      idValue: (index) => 'x$index',
    );
    final emittedVirtualIds = <String>{};
    for (final entry in virtualIds.entries) {
      if (!emittedVirtualIds.add(entry.value)) {
        continue;
      }
      lines.add('  ${entry.value}["${_mermaid(entry.key.rawTarget)}"]');
    }
    for (final edge in edges) {
      final target = edge.targetConcept == null
          ? virtualIds[edge]!
          : nodeIds[edge.targetConcept]!;
      lines.add(
        '  ${nodeIds[edge.source]} -->|${_mermaid(edge.origin.wireValue)}| '
        '$target',
      );
    }
    return '${lines.join('\n')}\n';
  }

  Map<OkfGraphEdge, String> _virtualTargetIds({
    String prefix = 'target:',
    String Function(int index)? idValue,
  }) {
    final result = <OkfGraphEdge, String>{};
    final idsByTarget = <String, String>{};
    var index = 0;
    for (final edge in edges) {
      if (edge.targetConcept != null) {
        continue;
      }
      final key =
          '${edge.rawTarget}\u0000${edge.resolution.wireValue}\u0000'
          '${edge.resolvedPath ?? ''}';
      var id = idsByTarget[key];
      if (id == null) {
        id =
            idValue?.call(index) ??
            '$prefix${edge.resolution.wireValue}:$index';
        idsByTarget[key] = id;
        index++;
      }
      result[edge] = id;
    }
    return result;
  }
}

void _addScalarEdge(
  Object? value,
  OkfGraphEdgeOrigin origin,
  void Function(String, OkfGraphEdgeOrigin) add,
) {
  if (value is String) {
    add(value, origin);
  }
}

void _addSourceEdges(
  Object? value,
  void Function(String, OkfGraphEdgeOrigin) add,
) {
  if (value is! List<Object?>) {
    return;
  }
  for (final source in value) {
    if (source is Map<Object?, Object?> && source['resource'] is String) {
      add(source['resource']! as String, OkfGraphEdgeOrigin.sourceResource);
    }
  }
}

void _addNestedResourceEdge(
  Object? value,
  OkfGraphEdgeOrigin origin,
  void Function(String, OkfGraphEdgeOrigin) add,
) {
  if (value is Map<Object?, Object?> && value['resource'] is String) {
    add(value['resource']! as String, origin);
  }
}

List<String> _markdownLinks(String body) {
  final collector = _LinkCollector();
  final document = md.Document(extensionSet: md.ExtensionSet.gitHubWeb);
  for (final node in document.parseLines(body.split(RegExp(r'\r?\n')))) {
    node.accept(collector);
  }
  return collector.links;
}

final class _LinkCollector implements md.NodeVisitor {
  final List<String> links = <String>[];

  @override
  bool visitElementBefore(md.Element element) {
    if (element.tag == 'a') {
      final href = element.attributes['href'];
      final isGeneratedFootnoteLink =
          (element.attributes['id']?.startsWith('fnref-') ?? false) ||
          element.attributes['class'] == 'footnote-backref';
      if (href != null && !isGeneratedFootnoteLink) {
        links.add(href);
      }
    }
    return true;
  }

  @override
  void visitElementAfter(md.Element element) {}

  @override
  void visitText(md.Text text) {}
}

final class _ResolvedTarget {
  const _ResolvedTarget(this.resolution, {this.path, this.concept});

  final OkfGraphResolution resolution;
  final String? path;
  final OkfConceptId? concept;
}

_ResolvedTarget _resolveTarget(
  OkfBundle bundle,
  OkfConceptId source,
  String raw, {
  required bool descriptorAllowed,
}) {
  if (_scheme.hasMatch(raw) || raw.startsWith('//')) {
    return const _ResolvedTarget(OkfGraphResolution.external);
  }
  final cut = raw.indexOf(_queryOrFragment);
  var pathPart = cut < 0 ? raw : raw.substring(0, cut);
  if (descriptorAllowed && !_looksLikePath(pathPart)) {
    return const _ResolvedTarget(OkfGraphResolution.descriptor);
  }
  if (pathPart.isEmpty) {
    pathPart = '${source.basename}.md';
  }

  final absolute = pathPart.startsWith('/');
  final rawSegments = pathPart.split('/');
  final resolved = absolute
      ? <String>[]
      : <String>[
          if (source.directory.isNotEmpty) ...source.directory.split('/'),
        ];
  for (final rawSegment in rawSegments) {
    if (rawSegment.isEmpty || rawSegment == '.') {
      continue;
    }
    final segment = decodeOkfLinkSegment(rawSegment);
    if (segment == null) {
      return const _ResolvedTarget(OkfGraphResolution.invalid);
    }
    if (segment.contains('/') ||
        segment.contains(r'\') ||
        segment.runes.any(isControlCharacter)) {
      return const _ResolvedTarget(OkfGraphResolution.invalid);
    }
    if (segment == '..') {
      if (resolved.isEmpty) {
        return const _ResolvedTarget(OkfGraphResolution.invalid);
      }
      resolved.removeLast();
    } else {
      resolved.add(segment);
    }
  }
  if (resolved.isEmpty) {
    return const _ResolvedTarget(OkfGraphResolution.invalid);
  }

  final normalized = resolved.join('/');
  if (!bundle.containsPath(normalized)) {
    return _ResolvedTarget(OkfGraphResolution.unresolved, path: normalized);
  }

  try {
    final concept = OkfConceptId.fromDocumentPath(normalized);
    if (bundle.concepts.containsKey(concept)) {
      return _ResolvedTarget(
        OkfGraphResolution.resolvedConcept,
        path: normalized,
        concept: concept,
      );
    }
  } on FormatException {
    // A present reserved document or asset is a resolved non-concept target.
  }
  return _ResolvedTarget(OkfGraphResolution.resolvedAsset, path: normalized);
}

/// Whether [pathPart] (a target already stripped of query and fragment)
/// names a bundle location rather than a prose source descriptor.
bool _looksLikePath(String pathPart) {
  if (pathPart.isEmpty) {
    return true;
  }
  // Prose signals outrank the slash test: real source descriptors contain
  // slashes ("extracted PDF/OOXML text"), while a genuine path is a single
  // token — link paths percent-encode whitespace and never carry backticks.
  if (_proseSignal.hasMatch(pathPart)) {
    return false;
  }
  if (pathPart.startsWith('.') ||
      pathPart.startsWith('/') ||
      pathPart.contains('/')) {
    return true;
  }
  return p.posix.extension(pathPart).isNotEmpty;
}

final RegExp _proseSignal = RegExp(r'[`\s]');
final RegExp _queryOrFragment = RegExp(r'[?#]');
final RegExp _scheme = RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:');

String? _scalarString(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  if (value is num || value is bool || value is DateTime) {
    return value.toString();
  }
  return null;
}

int _compareEdges(OkfGraphEdge left, OkfGraphEdge right) {
  var comparison = left.source.compareTo(right.source);
  if (comparison != 0) {
    return comparison;
  }
  comparison = left.origin.index.compareTo(right.origin.index);
  if (comparison != 0) {
    return comparison;
  }
  comparison = left.rawTarget.compareTo(right.rawTarget);
  if (comparison != 0) {
    return comparison;
  }
  return left.resolution.index.compareTo(right.resolution.index);
}

String _dot(String value) => _visibleControlCharacters(
  value,
).replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n');

String _mermaid(String value) => _visibleControlCharacters(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll('[', '&#91;')
    .replaceAll(']', '&#93;')
    .replaceAll('\n', '<br/>');

String _visibleControlCharacters(String value) {
  final output = StringBuffer();
  for (final rune in value.runes) {
    if (rune == 0x0a) {
      output.write('\n');
    } else if (isControlCharacter(rune)) {
      output
        ..write(r'\u{')
        ..write(rune.toRadixString(16).padLeft(4, '0'))
        ..write('}');
    } else {
      output.writeCharCode(rune);
    }
  }
  return output.toString();
}
