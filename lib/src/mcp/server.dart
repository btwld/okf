import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ack/ack.dart' as ack;
import 'package:mcp_dart/mcp_dart.dart';

import '../ack_error.dart';
import '../bundle.dart';
import '../bundle_change_set.dart';
import '../concept_id.dart';
import '../document.dart';
import '../finding.dart';
import '../graph.dart';
import '../io/bundle_change_applier.dart';
import '../io/bundle_loader.dart';
import '../version.dart';
import 'inputs.dart';

/// The OKF tool surface served over the Model Context Protocol.
///
/// Every tool re-reads the bundle from disk, so an agent that edits files
/// between calls never observes a stale answer. The write verbs are adapters
/// over [OkfBundleChangeApplier]: they translate tool arguments into a change
/// description and return its result, so validation, index and log
/// maintenance, and atomicity have one owner.
final class OkfMcpServer {
  /// Creates a server that reads and writes the bundle at [rootPath].
  OkfMcpServer({
    required this.rootPath,
    OkfBundleLoader loader = const OkfBundleLoader(),
  }) : _loader = loader,
       _applier = const OkfBundleChangeApplier();

  /// The bundle root every tool reads.
  final String rootPath;

  final OkfBundleLoader _loader;

  /// Owns preparation and exact prepared commits for every write tool.
  final OkfBundleChangeApplier _applier;

  /// Serves the tool surface over stdio until the client disconnects.
  ///
  /// Standard output carries JSON-RPC alone, so every diagnostic goes to
  /// standard error. Reading the bundle before the transport starts tells a
  /// client that the root is unreadable at startup rather than through a tool
  /// error on every later call.
  Future<void> serve() async {
    final loaded = await _loader.inspect(rootPath);
    stderr.writeln(
      'okf mcp: serving ${loaded.bundle.concepts.length} concept(s) '
      'from ${loaded.rootPath}'
      '${loaded.hasFindings ? '; ${loaded.report.findings.length} unreadable file(s)' : ''}',
    );

    final server = _buildServer();
    final closed = Completer<void>();
    server.server.onclose = () {
      if (!closed.isCompleted) {
        closed.complete();
      }
    };
    await server.connect(StdioServerTransport());
    await closed.future;
  }

  McpServer _buildServer() {
    final server = McpServer(
      const Implementation(name: 'okf', version: okfVersion),
      options: const McpServerOptions(
        capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
      ),
    );
    _registerReadTools(server);
    _registerWriteTools(server);
    return server;
  }

  void _registerReadTools(McpServer server) {
    server.registerTool(
      'list-concepts',
      description:
          'List concepts with their metadata, optionally narrowed '
          'by bundle area, concept type, or a text query.',
      inputSchema: JsonObject.fromJson(
        ListConceptsInput.$ack.schema.toJsonSchema(),
      ),
      annotations: _readOnlyAnnotations,
      callback: (arguments, extra) => _readComplete(
        (loaded) => _payload(
          _conceptListing(loaded.bundle, ListConceptsInput.parse(arguments)),
        ),
      ),
    );

    server.registerTool(
      'lookup-concept',
      description: 'Read one concept in its canonical Markdown form.',
      inputSchema: JsonObject.fromJson(
        LookupConceptInput.$ack.schema.toJsonSchema(),
      ),
      annotations: _readOnlyAnnotations,
      callback: (arguments, extra) => _readComplete((loaded) {
        final id = LookupConceptInput.parse(arguments).id;
        final document = loaded.bundle.concept(id);
        if (document == null) {
          throw FormatException('Unknown concept: ${id.value}');
        }
        return _payload(<String, Object?>{
          ..._conceptSummary(id, document),
          'markdown': document.serialize(),
        });
      }),
    );

    server.registerTool(
      'query-graph',
      description: 'Query the bundle relationship graph as versioned JSON.',
      inputSchema: JsonObject.fromJson(OkfGraphQuery.jsonSchema),
      annotations: _readOnlyAnnotations,
      callback: (arguments, extra) => _readComplete(
        (loaded) => _payload(
          OkfGraph.fromBundle(
            loaded.bundle,
            query: OkfGraphQuery.fromJson(arguments),
          ).toJson(),
        ),
      ),
    );

    server.registerTool(
      'validate',
      description: 'Validate the bundle and judge it as the CI gate does.',
      inputSchema: JsonObject.fromJson(
        ValidateInput.$ack.schema.toJsonSchema(),
      ),
      annotations: _readOnlyAnnotations,
      callback: (arguments, extra) => _readInspection((loaded) {
        final verdict = OkfVerdict.of(
          loaded.validate().report,
          strict: ValidateInput.parse(arguments).strict ?? false,
        );
        return _payload(<String, Object?>{
          'report': verdict.report.toJson(),
          'strict': verdict.strict,
          'exit_code': verdict.exitCode,
        });
      }),
    );
  }

  void _registerWriteTools(McpServer server) {
    _registerWrite(
      server,
      'create-concept',
      'Create a concept, maintaining the index and log with it.',
      input: CreateConceptInput.$ack,
      destructive: false,
      idempotent: false,
      describe: (input) => OkfCreateConceptChange(
        id: input.id,
        document: OkfDocument(
          frontmatter: <String, Object?>{
            'type': input.type,
            'title': ?input.title,
            'description': ?input.description,
            'tags': ?input.tags,
          },
          body: input.body ?? '',
        ),
      ),
    );

    _registerWrite(
      server,
      'update-concept',
      'Update the managed fields of an existing concept.',
      input: UpdateConceptInput.$ack,
      destructive: true,
      idempotent: true,
      describe: (input) {
        final frontmatter = <String, Object?>{
          'type': ?input.type,
          'title': ?input.title,
          'description': ?input.description,
          'tags': ?input.tags,
        };
        if (frontmatter.isEmpty && input.body == null) {
          throw OkfBundleChangeException(
            'Update for ${input.id} does not change a managed field.',
          );
        }
        return OkfUpdateConceptChange(
          id: input.id,
          frontmatterChanges: frontmatter,
          body: input.body,
        );
      },
    );

    _registerWrite(
      server,
      'link-concepts',
      'Relate two concepts, recording the link on the source.',
      input: LinkConceptsInput.$ack,
      destructive: false,
      idempotent: true,
      describe: (input) => OkfLinkConceptsChange(
        source: input.source,
        target: input.target,
        relationship: input.relationship,
      ),
    );

    _registerWrite(
      server,
      'deprecate-concept',
      'Retire a concept, recording why in the log.',
      input: DeprecateConceptInput.$ack,
      destructive: true,
      idempotent: true,
      describe: (input) =>
          OkfDeprecateConceptChange(id: input.id, note: input.note),
    );
  }

  /// Registers one write verb from its parameters and [describe], the
  /// translation from those parameters into a change description.
  ///
  /// Declaring every write verb through here keeps what they share from
  /// drifting apart: a closed schema is what decides the malformed-input
  /// tier, so it is not a per-verb choice.
  void _registerWrite<T extends Object>(
    McpServer server,
    String name,
    String description, {
    required ack.AckModelAdapter<ack.JsonMap, ack.JsonMap, T> input,
    required bool destructive,
    required bool idempotent,
    required OkfBundleChange Function(T input) describe,
  }) => server.registerTool(
    name,
    description: description,
    inputSchema: JsonObject.fromJson(input.schema.toJsonSchema()),
    annotations: ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: destructive,
      idempotentHint: idempotent,
      openWorldHint: false,
    ),
    callback: (arguments, extra) =>
        _write(() => describe(input.parse(arguments))),
  );

  Future<CallToolResult> _readComplete(
    CallToolResult Function(OkfBundleLoadResult) answer,
  ) => _readInspection((loaded) {
    if (loaded.hasFindings) {
      return _error(
        'The bundle has files that could not be read.',
        report: loaded.report,
      );
    }
    return answer(loaded);
  });

  Future<CallToolResult> _readInspection(
    CallToolResult Function(OkfBundleLoadResult) answer,
  ) => _guard(() async => answer(await _loader.inspect(rootPath)));

  /// Prepares and commits the change returned by [describe].
  ///
  /// A Spec-invalid candidate comes back as a refusal carrying the report —
  /// the finding IDs `okf validate` prints for the same state — and the bundle
  /// is left exactly as it was.
  ///
  /// [describe] runs inside the guard below, so a rejected argument stays on
  /// the tool-error path.
  Future<CallToolResult> _write(OkfBundleChange Function() describe) =>
      _guard(() async {
        final application = await _applier.apply(
          rootPath,
          OkfBundleChangeSet(<OkfBundleChange>[describe()]),
        );
        return switch (application) {
          OkfBundleApplied(result: final result) => _payload(<String, Object?>{
            'changed_paths': result.changedPaths,
          }),
          OkfBundleApplicationRefused(validation: final validation) => _error(
            'The change was refused; the bundle is unchanged.',
            report: validation.report,
          ),
        };
      });

  /// Runs one tool call, turning every failure below the protocol into a tool
  /// error so a bad request never ends the session.
  ///
  /// This is the malformed-input tier that the static input schemas do not
  /// already cover: an unreadable root, a rejected concept ID, or a change
  /// that describes no bundle state at all. None of them carries a report,
  /// which is what separates them from a refusal.
  Future<CallToolResult> _guard(
    Future<CallToolResult> Function() answer,
  ) async {
    try {
      return await answer();
    } on OkfBundleChangeException catch (error) {
      return _error(error.message);
    } on FormatException catch (error) {
      return _error(error.message);
    } on ack.AckException catch (error) {
      return _error('Invalid tool arguments: ${formatAckErrors(error)}');
    } on Exception catch (error) {
      return _error('$error');
    }
  }
}

const ToolAnnotations _readOnlyAnnotations = ToolAnnotations(
  readOnlyHint: true,
  destructiveHint: false,
  idempotentHint: true,
  openWorldHint: false,
);

/// The response to a list call: the summaries [filter] keeps and, when none
/// survive in a non-empty bundle, the type and area vocabulary the bundle
/// actually holds — so the caller corrects its filters in the same round trip
/// instead of falling back to an unfiltered dump to find out what to ask for.
Map<String, Object?> _conceptListing(
  OkfBundle bundle,
  ListConceptsInput filter,
) {
  final query = filter.query?.toLowerCase();

  bool matches(OkfConceptId id, OkfDocument document) {
    if (filter.prefix case final String prefix when !id.isWithin(prefix)) {
      return false;
    }
    if (filter.type case final String type when document.type != type) {
      return false;
    }
    return query == null ||
        id.value.toLowerCase().contains(query) ||
        (document.title ?? '').toLowerCase().contains(query);
  }

  final concepts = <Map<String, Object?>>[
    for (final entry in bundle.concepts.entries)
      if (matches(entry.key, entry.value))
        _conceptSummary(entry.key, entry.value),
  ];
  return <String, Object?>{
    'concepts': concepts,
    if (concepts.isEmpty && bundle.concepts.isNotEmpty) ...{
      'available_types': _histogram(<String>[
        for (final document in bundle.concepts.values)
          if (document.type case final String type) type,
      ]),
      'available_areas': _histogram(<String>[
        for (final id in bundle.concepts.keys) id.segments.first,
      ]),
    },
  };
}

/// The metadata every listing and lookup carries for a concept.
///
/// The document path is deliberately absent: it is always the ID plus the
/// `.md` suffix, and repeating it once per concept is what pushed full-bundle
/// listings past client tool-result limits.
Map<String, Object?> _conceptSummary(OkfConceptId id, OkfDocument document) =>
    <String, Object?>{
      'id': id.value,
      'type': ?document.type,
      'title': ?document.title,
      'status': document.status.wireValue,
      'trust_tier': document.trustTier.wireValue,
    };

/// Counts [values], largest first, ties broken alphabetically so the same
/// bundle always reports the same hint.
Map<String, int> _histogram(Iterable<String> values) {
  final counts = <String, int>{};
  for (final value in values) {
    counts[value] = (counts[value] ?? 0) + 1;
  }
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
  return <String, int>{for (final entry in entries) entry.key: entry.value};
}

/// Returns [payload] serialized once, as the text block alone.
///
/// Carrying a structured copy next to the serialized one doubled every
/// result on the wire, which is what pushed full-bundle reads past client
/// tool-result token limits.
CallToolResult _payload(Map<String, Object?> payload) =>
    CallToolResult(content: <Content>[TextContent(text: jsonEncode(payload))]);

/// Refuses a call, carrying [report] so the caller learns why in one round
/// trip instead of having to ask the validate tool. Like [_payload], the
/// report is serialized exactly once — as the text block after the message.
CallToolResult _error(String message, {OkfReport? report}) => CallToolResult(
  isError: true,
  content: <Content>[
    TextContent(text: message),
    if (report != null)
      TextContent(
        text: jsonEncode(<String, Object?>{'report': report.toJson()}),
      ),
  ],
);
