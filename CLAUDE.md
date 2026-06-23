# CLAUDE.md — Liita

This file gives you (Claude Code) persistent context about this project. Read it at the
start of every session before making changes.

---

## What Liita is

Liita is an **offline, peer-to-peer messaging and gaming app** that connects nearby phones
over a **Bluetooth Low Energy (BLE) mesh network**. No internet, WiFi, cell signal, or server
is required — phones discover each other over BLE and data hops device-to-device across the
mesh. It's built for environments where people are physically near each other but cut off from
the internet: flights, trains, festivals, remote areas.

Origin: started as a concept for a flight dating app ("love is in the air" → Liita), grew into
a broader proximity-based social + gaming app.

---

## Tech stack

- **UI:** Flutter / Dart (SDK ^3.7.2)
- **State management:** Riverpod (`flutter_riverpod`)
- **Routing:** GoRouter (`go_router`)
- **Local DB:** SQLite via `sqflite`
- **BLE mesh:** native **Kotlin**, bridged to Dart via platform channels
  (`flutter_blue_plus` is in the stack but the core mesh is custom native Kotlin)
- **Crypto:** ECDH (P-256) + AES-256-GCM via `pointycastle` + `crypto`; keys in
  `flutter_secure_storage` (Android Keystore)
- **Platform:** Android only. iOS is planned but NOT started (the BLE layer is native Android —
  iOS would require a CoreBluetooth rebuild, not a port).

---

## Architecture (how it fits together)

**Three layers:**

1. **Flutter UI (`lib/features/`)** — reactive screens that watch Riverpod providers. Providers
   expose streams off the database, so UI rebuilds when data changes.

2. **The bridge (`lib/core/services/mesh_service*.dart`)** — platform-channel boundary. Dart
   calls native methods (start mesh, send packet); native streams received packets back up.

3. **Native mesh engine (`android/.../kotlin/com/liita/liita/`)** — runs in an Android
   **foreground service** (persistent notification, survives backgrounding). Each phone
   simultaneously **advertises** (to be discovered), **scans** (to discover others), runs a
   **GATT server** (receive writes from peers), and acts as a **GATT client** (write to peers).
   Every phone is both sender and receiver — that symmetry is what makes the mesh work.

**The brain:** `lib/core/controllers/app_controller.dart` is the central router. Every
incoming `MeshPacket` is parsed and dispatched by payload type to the right provider/handler
(lounge, chat, game, etc.). Handlers are deduped and ignore local echo.

---

## The mesh protocol (the core of the system)

Liita uses **controlled flooding** with TTL-based relay and deduplication.

**`MeshPacket`** (`lib/core/models/mesh_packet.dart`) fields:
- `packetId` (unique, for dedup), `originId`, `destinationId` (`*` = broadcast),
  `ttl` (starts at **8**), `payloadType`, `data`, `timestamp`.
- JSON keys are single chars (`p o d l y a t`) to keep BLE payloads compact.

**Payload types** (single-char codes): `wave('w')`, `waveAccept('a')`, `text('t')`,
`profileSync('p')`, `photoChunk('c')`, `broadcast('b')`, `ack('k')`, `game('g')`.

**Relay rules** (`RelayController.kt`, `DeduplicationCache.kt`):
- Drop if `originId == localDeviceId` (own echo).
- Drop if `ttl <= 1`.
- **Dedup:** `DeduplicationCache` (max 1000 entries, 10-min expiry) tracks each packet's
  "degree" (times seen). First sighting = degree 1. Only relay if degree == 1.
- **Relay jitter:** before relaying, wait random 20–150ms, then re-check degree. If another
  node already relayed it during the window (degree > 1), suppress. This prevents broadcast
  storms. **Do not remove this — it's load-bearing.**
- On relay: decrement TTL, re-broadcast.

---

## Crypto

- Match handshake: peers exchange public keys, derive a 32-byte shared secret via
  **ECDH (P-256) + HKDF-SHA256**.
- Messages: **AES-256-GCM**, fresh 12-byte nonce per message, GCM auth tag for integrity.
- Private keys: `flutter_secure_storage`. Shared keys persisted per-match (survive restart).
- The public **Lounge** chat is intentionally NOT encrypted (broadcast to everyone in range).

---

## Features & current state (as of this file's writing)

| Feature | State |
|---|---|
| Radar (peer discovery) | Working |
| Wave / Match (mutual connect) | Working |
| Private chat (E2EE) | Working |
| Lounge (public broadcast) | Working |
| Tic-Tac-Toe | Working |
| Cabin Trivia | Built (both-players-answer, 15s timer, 10 questions). **Not yet device-tested.** |
| Word Chain / Chess / Battleship | "Coming Soon" placeholders only |
| Photo syncing | Receiving stores chunks to DB; **reassembly into avatars NOT wired up** |
| iOS | Not started |

**Roadmap order:** (1) more games, (2) photo sync, (3) UI/UX, (4) UX improvements,
(5) code cleanup, (6) security/legal compliance, (7) iOS, (8) launch.

---

## The game system

- `lib/core/models/game_message.dart`: `GameMessage` has `gameId`, **`gameType`** (`GameType`
  enum: `ticTacToe('ttt')`, `trivia('trivia')`), `type` (`GameMessageType`: invite, accept,
  decline, move, question, answer, result, end), and a `payload` map.
- `_handleGame()` in `app_controller.dart` routes by `gameType` to `_handleTicTacToe` or
  `_handleTrivia`. Each game has its own notifier in `lib/core/providers/game_provider.dart`
  (`ticTacToeProvider`, `triviaGameProvider`).
- **To add a new game:** add a `GameType`, a notifier + state, a `_handleX` method, a screen,
  a route in `router.dart`, and entries in BOTH game pickers (`games_screen.dart` and
  `matches_screen.dart`). Both pickers carry `gameType` + `routePath` per game.
- `game_provider.dart` must NOT import `app_controller.dart` or `providers.dart` (circular
  import). Packet sending happens in `AppController` (for packets sent in response to received
  packets) or in the game screen widget (for user/timer-triggered packets).

---

## Critical constraints — DO NOT BREAK

**Never modify these native files casually** (they hold the mesh engine and its bug fixes;
changes here have broken discovery before):
`MeshForegroundService.kt`, `MeshPlugin.kt`, `RelayController.kt`, `DeduplicationCache.kt`,
`BlePeerRegistry.kt`, `MeshPacket.kt` (Kotlin). If a task requires changing them, call it out
explicitly and explain why.

**Treat these data models as stable** unless the task is specifically about them:
`user_profile.dart`, `mesh_packet.dart`, `chat_message.dart`, `match_event.dart`,
`broadcast_message.dart`.

**Riverpod gotcha:** the singleton `AppController` must be created with `ref.read` on its
dependencies, NOT `ref.watch`. Using `ref.watch` causes the controller to be disposed and
recreated whenever a provider updates, which kills all BLE subscriptions. This was a real bug.

---

## Android BLE constraints (hard-won — these caused real bugs)

These are platform limits that have bitten this project. Keep them in mind for any BLE work:

- **Scan throttle:** Android silently throttles an app that calls `startScan` more than **5×
  per 30s**. Do not restart scanning on every connect/disconnect event — only restart if the
  scan loop is actually dead.
- **GATT connection ceiling:** ~**7 concurrent** GATT connections on many devices. Discovery
  connections are closed after reading a peer's profile (with a 60s re-profile guard) to free
  slots — important for crowded environments.
- **GATT client interface leak:** every `connectGatt` must be `close()`d, including on timeout.
  Leaked client interfaces (~30 cap) eventually make ALL connections fail with status 133.
  The send path keeps the GATT in an `AtomicReference` and closes it on timeout. Don't
  reintroduce a path where a hung connect leaks its GATT.
- **MAC rotation:** Android randomizes BLE MACs. A stale `deviceId → MAC` mapping can make a
  unicast send fail; there's a broadcast fallback for that case.
- **UTF-8 in advertising:** advertising/scan-response byte buffers are fixed-size. Truncate by
  BYTE count, not character count (multibyte chars overflow fixed arrays).

---

## Conventions

- Run `flutter analyze` after changes; stop on any new error (a couple of pre-existing SPM
  deprecation infos are acceptable).
- No emoji in UI.
- Match existing styling via `AppColors` / `AppSpacing` in `lib/core/theme/app_theme.dart`.
- Native logging uses the tag `LiitaBLE` — useful for debugging BLE on a physical device via
  logcat.
- Prefer diff-style, surgical changes. When editing existing files, don't rewrite whole files
  unless necessary.

---

## Testing notes

- The app currently only runs on recent Android. There's an unresolved issue where it doesn't
  work on older Android versions — likely the API-31 BLE permission split
  (`BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` / `BLUETOOTH_ADVERTISE` vs legacy `BLUETOOTH` +
  `ACCESS_FINE_LOCATION`). Worth fixing before launch.
- Real testing requires 2–3 physical Android devices (BLE doesn't work on emulators).
  `flutter analyze` passing means it compiles, NOT that BLE behavior is correct — always
  validate mesh changes on real hardware.

---

## Known issues to investigate (owner-reported — root causes UNVERIFIED)

These are observed symptoms, not diagnoses. Treat them as leads to investigate from
first principles; do not assume any prior explanation is correct.

- **Cabin Trivia** does not work reliably across a full multi-question game (both players
  answering, scoring, advancing).
- **"Play Again" / rematch** in the games is unreliable.
- **Core mesh is intermittent** — discovery, waving, matching, private messaging, and the
  lounge work sometimes and fail other times.
- **Older Android versions** don't work (see the API-31 permission-split note above as one
  lead to verify, not a conclusion).
- **Behavior under load is untested** — many messages, messaging after extended gameplay,
  many packets in flight.

## Notable config

- `android:allowBackup="false"` is set in `AndroidManifest.xml`. (Android Auto Backup was
  restoring app data — the SQLite DB and the secure-storage prefs — across uninstall/reinstall;
  the restored, Keystore-encrypted secure-storage could not be decrypted on the new install.)
