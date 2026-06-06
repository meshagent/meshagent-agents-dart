## [0.44.8]
- Stability

## [0.44.7]
- Stability

## [0.44.6]
- Updated `code_forge` to 9.10.0 and `code_forge_web` to 2.10.0, and removed the git override so the Flutter package now resolves `code_forge_web` from pub.dev.

## [0.44.5]
- Chat thread attachments and pending attachment previews now use stable widget identities, preserving image and file preview state across rebuilds and tab changes.

## [0.44.4]
- `AgentMessage` now carries arbitrary metadata and round-trips it through JSON parsing and serialization, preserving provider-specific payloads such as encrypted reasoning content.

## [0.44.3]
- Fixed animated status counters in the Flutter chat UI so large byte and count jumps render correctly without runaway digit growth.

## [0.44.2]
- Messaging chat clients now track agent participant presence and room status more accurately, distinguish first connect from reconnect, and reopen open thread sessions after reconnect.
- Thread storage repositories now resubscribe and refresh thread lists after a reconnect, restoring watched-thread state automatically.
- Agent connection status is no longer fanned out into open thread sessions, preventing duplicate status messages from appearing in reopened chats.

## [0.44.1]
- Stability

## [0.44.0]
- Added thread watch/unwatch messages plus multiple thread-storage support to the Dart agent client API.
- Chat session state now preserves created timestamps and resets replay state correctly when reopening threads, improving message ordering and pending-input handling.
- Updated agent message modeling to carry richer thread metadata for live assistant, mail, and storage-aware workflows.

## [0.43.4]
- `AgentMessage` now serializes `created_at` and restores it from incoming payloads so Dart agents keep message timestamps across round trips.
- `AgentMessageEvent` now carries its own timestamp, supports listeners, and keeps merged payloads aligned with the original event time.
- `MessagingChatClient` now routes participantless thread lifecycle updates and preserves room message timestamps when turning messages into session events.
- UI helpers now support an injectable reference time for relative labels, show seconds for recent timestamps, and expose more resilient dataset row timestamp resolution.

## [0.43.3]
- Stability

## [0.43.2]
- Added optional backend fields throughout `meshagent-agents-dart` messages and chat session methods, enabling multi-backend conversations and model changes.
- Added IAP-aware websocket helpers in `meshagent-api`, including `WebSocketClientProtocol.withIAP()` and Authorization-header based room connections instead of token query parameters.
- Breaking: websocket room auth now uses `meshagent-agent.<token>` instead of `bearer.<token>`.
- Expanded `meshagent_flutter_desktop_updater` with update-check dialog, controller-scope, and menu-copy exports for desktop apps.

## [0.43.1]
- Added IAP room websocket support to the Dart agent chat client.
- Reworked the Flutter chat and thread components to load thread lists through `MessagingChatClient` and `AgentThreadStorageRepository` instead of direct document mutation.
- Added the desktop update bridge APIs used by Flutter apps for update checks on macOS and Windows.

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
