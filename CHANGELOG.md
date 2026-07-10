## [0.46.3]
- Added `Meshagent.getProjectSettings(projectId)` to fetch project settings from the API and return them as a JSON map.
- The Dart service webhook helper now merges optional headers with null-aware spread semantics.

## [0.46.2]
- Stability

## [0.46.1]
- Breaking change: `ServicesClient.list()` now returns the combined services-and-runtime-state result instead of a plain service array, so callers must read the `services` field for the old list-only behavior.

## [0.46.0]
- Stability

## [0.45.9]
- Breaking change: `SecretVersion.encryptionKeyId` was removed from the generated client models.
- Room server clients now expose typed service runtime state via `list()`, including `ServiceRuntimeStatus` and per-port liveness records, and `PortNum` now compares by value.
- The dev terminal and trace-viewer package now uses a Ghostty-backed controller/view API, bundles the `libghostty` 0.0.10 WASM runtime, and formats durations in milliseconds with improved span handling.
- The deprecated `meshagent_flutter_widgets` and `meshagent_luau` packages were removed.

## [0.45.8]
- Stability

## [0.45.7]
- Updated Dart SDK package dependency versions and release metadata for the published Dart APIs.

## [0.45.6]
- Aligned the core Dart SDK packages and their inter-package dependencies across the Dart, service, arrow, agents, Flutter, and Luau surfaces.

## [0.45.5]
- Fixed the status counter wheel animation so digits wrap smoothly during transitions and no longer glitch at rollover.

## [0.45.4]
- Stability

## [0.45.3]
- Added `pull_secret` support for service container specs, service-account `view` filtering, and surfaced service runtime startup errors plus lifecycle events in Dart clients.
- Improved dataset-thread shutdown so close operations do not hang on long-running subscriptions or refresh work.
- Updated injected chat-client handling so new threads wait for agent readiness and refresh when the agent participant changes.
- Enforced id-only secret payload validation, which breaks older named-secret service specs.

## [0.45.2]
- Added `pull_secret` support to service container specs and exposed service runtime startup errors plus lifecycle events in Dart clients.
- Added `view` support to service-account listing and tightened service-spec validation so pull secrets must be id-only, which breaks legacy named-secret payloads.
- Improved dataset thread storage shutdown so close operations do not hang on long-running subscriptions or refresh work.

## [0.45.1]
- `listServiceAccountsPage` now accepts a `view` parameter so Dart callers can request personal or full service-account listings.

## [0.45.0]
- Added `pull_secret` to service container specs and exposed service runtime startup errors and lifecycle events in the Dart room client.
- Enforced id-only secret payloads, rejecting legacy secret fields, which is a breaking change for older service specs.
- Updated service-state and room-client tests to cover the new runtime fields and secret handling.

## [0.44.13]
- Added `ChatThreadCustomInputBuilder` and `ChatThreadInputConfig` so callers can replace the default composer while still reusing thread state, attachment handling, audio hooks, and menu wiring.
- Added `ThreadTypographyOverride` and helper APIs to customize thread fonts, spacing, colors, link styling, code blocks, inline code, markdown headings, and attachment/error surfaces.
- Extended chat bubble and message widgets with border color and typography override support for finer-grained rendering control.
- Exported the new typography and composer primitives through the SDK surface.

## [0.44.12]
- Added shared profile and session support for native auth flows, including profile switching and environment-aware API URL overrides.
- Added realtime audio output and refreshed voice session state, controls, and waveform rendering behavior.
- Improved meeting layout responsiveness and right-sidebar behavior.
- Powerboards config handling now sources the mail domain from runtime configuration instead of a fixed value.

## [0.44.11]
- Stability

## [0.44.10]
- Stability

## [0.44.9]
START SUMMARY OF NODEJS API CHANGES END SUMMARY OF NODEJS API CHANGES
START SUMMARY OF PYTHON API CHANGES END SUMMARY OF PYTHON API CHANGES

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
