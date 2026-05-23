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
