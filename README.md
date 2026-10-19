# meshagent_agents

Dart agent chat session and transport helpers for Meshagent applications.


## Anonymous website connections

On a website bound to a managed agent, use the existing client
with anonymous authorization:

```dart
import 'package:meshagent_agents/meshagent_agents.dart';

final chat = WebSocketChatClient.withAnonymous();
await chat.start();
```

Grant the resource an appropriate IAM role for `everyone:all` first. The default
authorization URL is `/.well-known/meshagent/authorize` on the current website.
Pass an absolute `authorizationUrl` when running outside a browser.
Managed agents must use `thread_isolation: participant`.

Each initial connection and reconnect obtains a fresh token before opening the
WebSocket. The anonymous cookie preserves the visitor identity; token expiration
does not interrupt an open connection. Browsers retain the HttpOnly cookie across
visits. Native clients retain it within the provider instance. Removing the browser
cookie or creating a new native provider starts a new anonymous identity.

For custom authentication, supply `tokenProvider` to `WebSocketChatClient`.
Use an `AccessTokenProvider` in Dart. The provider is called on every connection attempt and replaces the static token.
`AnonymousAccessTokenProvider` is also available for explicit reuse and exposes
`expiresAt` after a successful exchange. Keep one provider for a native session.

Anonymous authorization failures include the server's denial reason. The token
provider's exceptions expose `statusCode` and `errorCode`, which are also retained
when initial connection is denied. Denial uses
`anonymous_access_denied`, other HTTP failures use
`anonymous_authorization_failed`, and malformed success responses use
`invalid_anonymous_authorization_response`. Connection failures during refresh
retain the reason in the existing connection lifecycle notifications. A denied
refresh stops automatic retries; transient failures retain the usual retry behavior.
