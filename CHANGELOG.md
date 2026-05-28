## [0.43.0]
- Room websocket clients now support IAP connections through `withIAP()` helpers, nullable tokens, and the new auth flow that avoids query-string token handling.
- Agent and chat payloads now carry backend metadata through thread starts, turn starts, model changes, and realtime audio commits.
- The shared Dart UI/tooling packages now understand backend-aware model lists, unified diff previews, and Codex diff tool calls, and the desktop updater exports reusable dialog and scope helpers.

## [0.42.2]
- Added container and build model fields for image IDs, runtime stats, exit status details, and published build image metadata.
- Added `waitForExitStatus` alongside `waitForExit`, preserving the existing exit-code convenience while exposing richer exit information.
- Updated container list parsing to consume the new metadata fields in responses without breaking existing callers.

## [0.42.1]
- Stability

## [0.42.0]
- Added project lookup by key.
- Container and room APIs now model ports as structured `containerPort`/`hostPort` pairs, which is a breaking response-shape change for container listings.
- `RoutePath` and `PortSpec` now support `stripPrefix` and `hostPort`, and room service MCP URL resolution uses `hostPort` when present.
- Room creation now serializes permissions correctly and preserves annotations.
- Container creation now accepts a `template` option.

## [0.41.10]
- Stability

## [0.41.9]
- Stability

## [0.41.8]
- Stability

## [0.41.7]
- Stability

## [0.41.6]
- Extended the Dart storage client `downloadUrl` API with an optional `download` flag for inline versus attachment links.

## [0.41.5]
- Stability

## [0.41.4]
- Stability

## [0.41.3]
- Stability

## [0.41.2]
- The Dart backend-agent sample now exposes a hosted local toolkit with `ping`, `status`, and `echo`, verifies the toolkit through room tool calls, and persists a small proof payload once validation succeeds.

## [0.41.1]
- Dart feed subscription models and create/update methods now carry an optional `filenameDatetimeFormat` through the client.

## [0.41.0]
- Route APIs now use `RouteSpec`, support room or agent backends, and still parse legacy route payloads.
- Managed-agent chat/session APIs now support thread listing, thread lifecycle events, and attachment names.
- `AgentsClient.invoke` no longer accepts `callerContext`, and `ToolStreamOutput` now carries `inputClosed`.
- Toolkit metadata serialization no longer includes `thumbnailUrl` or `pricing`.
- The SDK's Dart bridge packages were refreshed to align the generated models and interop helpers with the new route and managed-agent shapes.

## [0.40.3]
- Added `meshagent-agents-dart`, a websocket-backed agent chat package with rich agent message types, thread storage, and pending-input/session management.
- Expanded the core Dart client with route-spec CRUD/listing, agent sessions, managed-agent secret APIs, and agent route queries.
- Added the reusable Flutter desktop updater package.
- Added third-party dependencies `msgpack_dart ^1.0.1`, `uuid ^4.5.1`, and `web_socket_channel ^3.0.3`.

## [0.40.2]
- Initial Dart agent chat session support.
