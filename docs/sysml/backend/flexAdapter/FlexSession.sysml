package WstxFlexSession {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::'FR-023';
    private import WstxRequirements::'FR-008';
    private import WstxRequirements::'FR-009';
    private import WstxRequirements::AutomationState;
    requirement 'CL-013-01' {
        doc /* Phase 2 MUST offer direct native-network integration as an optional profile connection type for the selected radio control, status and sample-stream functions. When selected, that native path MUST NOT require the external SmartSDR desktop application, SmartSDR CAT or DAX applications to be installed/running as bridges. This restriction does not prohibit those tools as operator-selected infrastructure for the standard connection path. A Rust implementation may coordinate shared radio access internally without forcing one hardware GUI-client session per logical station server. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/flex/session.rs; server/src/main.rs";
    }
    dependency CL_013_01_to_FR_023 from 'CL-013-01' to 'FR-023';
    requirement 'CL-013-02' {
        doc /* This independence concerns desktop applications. Compatible radio-side firmware and its API remain required; this specification does not promise a FlexRadio operating without its SmartSDR radio firmware or an unrestricted firmware compatibility range. Pin supported models, firmware/API versions and selected stream formats before implementation. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/flex/wire.rs; server/src/flex/session.rs";
    }
    dependency CL_013_02_to_FR_023 from 'CL-013-02' to 'FR-023';
    requirement 'CL-013-03' {
        doc /* Each native FlexRadio profile MUST persist its receive intent: its own client identity and receive antenna, and no radio identity (operator decision 2026-11-06 on #22: the station uses whichever radio discovery finds available). Where discovery cannot reach the radio, the profile may also save the radio's address (operator decision 2026-11-06 on #13): a locator for that one radio, not compared with anything. On every connection/reconnection the system MUST reconcile that intent with authoritative discovery/status and current runtime handles. A changed/transient slice index MUST NOT redirect a station to another station's slice. Unresolvable associations MUST produce a visible unavailable/conflict state rather than guessing a replacement. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/flex/session.rs; server/src/profile.rs";
    }
    dependency CL_013_03_to_FR_023 from 'CL-013-03' to 'FR-023';
    requirement 'CL-013-04' {
        doc /* Control responses and received stream data MUST be routed to the associated station. Capacity shortages, occupied resources and incompatible API behavior MUST be reported without stealing another profile's slice or silently reducing the requested independence. Four-slice hardware validation requires a model/configuration that actually provides at least four usable slices. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/flex/session.rs";
    }
    dependency CL_013_04_to_FR_023 from 'CL-013-04' to 'FR-023';
    requirement 'CL-013-05' {
        doc /* Shared-radio transmit, tuning and other constrained-resource authority MUST be coordinated under FR-008/FR-009 before those operations are enabled. Four station profiles do not confer simultaneous independent transmit authority. Reconnect/profile restoration MUST NOT replay an old transmit request or bypass the future ownership policy. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/flex/session.rs; server/src/transmit_http.rs";
    }
    dependency CL_013_05_to_FR_008 from 'CL-013-05' to 'FR-008';
    dependency CL_013_05_to_FR_009 from 'CL-013-05' to 'FR-009';
    dependency CL_013_05_to_FR_023 from 'CL-013-05' to 'FR-023';
    requirement 'CL-013-06' {
        doc /* The native path MUST reuse the common browser, station-operation, DSP/modem and future MCP interfaces. The default standard connection remains usable without FlexRadio hardware or native-profile fields. A mixed set of instances MUST preserve each profile's selected path, configuration and routing independently. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/recording.rs; server/src/receive_http.rs; server/src/selection_http.rs; client/recording.js; client/contact.js";
    }
    dependency CL_013_06_to_FR_023 from 'CL-013-06' to 'FR-023';
    verification 'TC-023-001' {
        doc /* #### TC-023-001 — Direct protocol and four-station route isolation

             **Promise:** FR-023; CL-013-01, CL-013-04. **Level: 2 — Isolated automated tests.**
             **Where it runs:** Windows PC, candidate Rust system, four station profiles/windows
             and an independent local FlexRadio protocol emulator; no real radio or external service.

             **Inputs/actions:** Run with external SmartSDR desktop/CAT/DAX applications absent or
             stopped. Exercise the selected native TCP command/status exchange and UDP sample-stream
             path against pinned reference fixtures. Give each emulated slice distinguishable state
             and data; send concurrent operations from the four logical station servers.

             **Expected results:** The Rust system connects directly to the emulated API without a
             desktop bridge. Each response/state update/stream reaches the intended station and no
             other station. Operations change only the associated emulated resource. The oracle uses
             independently specified protocol fixtures, not packets generated by the code under test.

             **Level-2 realization:** tests/native-flex.test.cjs starts the independent loopback
             emulator tests/flex-emulator.cjs (TCP command/status, unicast loopback discovery and
             VITA-49 DAX float 24 kHz streams at the radio's 187.5 packets/s in the form a real
             FLEX-6600 sent, its encoder checked byte for byte against that captured packet; no code
             shared with the candidate) and four real
             station servers with disposable schema-2 HTTPS profiles. Each emulated slice carries
             a 1 kHz tone of a slice-specific amplitude, and every eighth packet another client's
             stream ID is sent at amplitude 0.95. Oracle: the emulator's own slice/stream/owner
             records and command log. Each station owns exactly one slice and stream whose index
             and ID its /native-flex snapshot repeats; its accepted channel-0 peak equals its own
             slice amplitude within 1e-4 with foreign packets counted. Four concurrent band
             selections through /receive/select tune only the selecting client's slice and return
             control native/origin native_readback; the restarted live receive runs on device
             native_flex with advancing source frames and a correlated UTC anchor within 2 s of the
             test's own clock. Read first: repeating a selection whose slice already reports the
             frequency sends no slice tune and no mode write (command log count unchanged); an
             emulator that does not report the new frequency makes the selection fail visibly with
             error radio_timeout and leaves no native_readback origin. The emulator reports a tune
             only when asked, as the real radio does; a selection is confirmed also with its replies
             and statuses 130 to 260 ms late, and a repeated selection also sends no sub slice all. One packet in 60 delayed by 4 places counts neither lost nor late; delayed by 6
             places it counts lost once and late once. Neither opens an epoch or changes the rate. A 400 ms
             outage after which the count comes back shifted by 9 opens an epoch (native_discontinuity)
             and changes neither lost nor late: the count starts over, and what waited goes on first.
             Rust unit tests also check that a duplicate is dropped, whether its first copy still waits or
             its turn has passed, and the burst limit: 7 lost in a row count lost, 8 read as late. Two stations whose DAX
             status arrives 300 ms late end on different channels, the emulator's audio following
             the channel, not the owner. Datagrams with the own stream ID from another address
             (127.0.0.2, amplitude 0.95) are never accepted. No slice command targets another
             client's slice and no transmit, disconnect or persistence command is sent. Rust unit
             tests check the captured packet and the pinned independent vector field by field, their
             negative cases, documented control lines and the 4096-byte line bound. The live check
             script tests/flex-live-check.cjs, run against the emulator streaming the verified FT8
             vector on the UTC period at 24 kHz with one packet in 64 lost, measures that loss, reports jitter, shows the
             vector's expected text from the station's decoder with DT within 0.3 s from arrival
             anchoring, saves the windows and leaves no slice or client. It stops as occupied with a
             client or slice present, whichever way round the replies come, as unverified when a
             reply is refused, reports not_released for a slice left behind or a closing look it cannot
             verify, and reports the loss it saw. One packet in four
             lost is counted at 25% and filled with silence, with the canonical frame rate kept and no new epoch, and a
             120 ms stall reads as at least 90 ms of jitter; a 400 ms stall with packets missing opens a
             new epoch (native_discontinuity). Another model on the admitted API connects and its announced
             model, serial and firmware are shown. GET /native-flex reports the packet's timestamp
             kind and this host's clock minus its time, which a new session without own packets
             shows as null. A saved address connects with nothing announced and no discovery
             listener; model, serial and firmware then come from the radio's info reply; the stream
             arrives only after client udp_register from the stream's port, which repeats, and no
             command names a local address. A full radio on a saved address reports
             radio_refused. */
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String = "tests/native-flex.test.cjs; server/src/flex/wire_tests.rs; server/src/flex/session_tests.rs";
        objective {
            verify 'CL-013-01';
            verify 'CL-013-04';
            verify 'FR-023';
        }
    }
    verification 'TC-023-002' {
        doc /* #### TC-023-002 — Persisted intent and changed runtime handles

             **Promise:** FR-023; CL-013-03, CL-013-04, CL-013-05. **Level: 2 — Isolated automated tests.**
             **Where it runs:** Windows PC, disposable persisted profiles and a local radio emulator.

             **Inputs/actions:** Save the native receive intent, disconnect/restart the
             emulated radio and assign different runtime handles before reconnecting. Also present
             missing, ambiguous or occupied intended resources and stale status updates.

             **Expected results:** Each profile reconciles its intent with current authoritative
             resources; transient indices do not route it to another station. Unresolved intent is
             reported as unavailable/conflicting without stealing a resource, replaying transmit
             requests or accepting stale handles as authority.

             **Level-2 realization:** two native stations on the loopback emulator. The emulator is
             stopped and restarted with new client handles, reversed slice indices, new stream IDs
             and the old stream IDs replayed: each station reports transport_lost, then a new session
             reaches ready on its own newly created slice (emulator owner record), the old stream
             IDs are only counted as foreign, the accepted peak follows the new own slice, and a
             receive job running before the restart stays the operator's running job and advances
             again after a new source epoch, without an operator action. Occupied: an external
             connected client carries station A's saved client identity; A shows
             conflict/client_identity_in_use, sends no client gui and creates no slice while B is
             ready, and recovers once the identity disappears. Ambiguous: a slice already attributed
             to A's fresh handle yields conflict/ownership_ambiguous with no slice/stream command
             from A. Missing: nothing is announced; both report radio_not_found with zero TCP
             connections. Next available: of two emulators on one discovery port, the one announcing
             available_clients=0 receives no connection and the station becomes ready on the other.
             A selected frequency returns on the new slice after a restart, and the same occupied
             case holds when the radio answers before it lists the clients. Without a session a
             new receive start is refused radio_unavailable. Startup resume (CL-045-02): a
             spectrum and a band choice resume started, the band on the slice, and with no radio
             the resume ends failed/radio_unavailable after 15 to 30 s.
             Authorization: a native station without a grant makes no TCP connection and, after
             its only grant is revoked, its client and slice leave the emulator.
             profile.json bytes stay unchanged and hold no radio identity (no serial key). */
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String = "tests/native-flex.test.cjs; server/src/flex/wire_tests.rs; server/src/flex/session_tests.rs; server/src/profile_tests.rs";
        objective {
            verify 'CL-013-03';
            verify 'CL-013-04';
            verify 'CL-013-05';
            verify 'FR-023';
        }
    }
    verification 'TC-023-003' {
        doc /* #### TC-023-003 — Capability limits and shared-resource coordination

             **Promise:** FR-023; FR-008/FR-009; CL-013-02, CL-013-04, CL-013-05, CL-013-06. **Level: 2 — Isolated automated tests.**
             **Where it runs:** Windows PC, four logical station servers and an API/resource emulator.

             **Inputs/actions:** Emulate sufficient and insufficient slice capacities, incompatible
             supported-version conditions and concurrent conflicting resource requests. Include a
             mixed set of standard audio/rig-control profiles and native FlexRadio profiles, with
             the standard device/rig-control side represented by independent local fixtures. Exercise
             the shared-radio authority policy once specified; use simulated transmit intent only.

             **Expected results:** Supported capacity permits the requested independent receive
             resources; insufficient capacity/version incompatibility is explicit and preserves
             existing station ownership. Conflicting operations follow the agreed coordination
             policy. Four server instances never imply four independently authorized transmitters.
             Standard profiles continue through their selected audio/rig-control path without native
             FlexRadio settings; native profiles use the direct API. Both are presented through the
             same browser and shared station-operation interfaces, with no cross-profile routing.

             **Level-2 realization:** emulator capacity two slices with three native stations: two
             become ready, the third reports capacity_slices, and the two owners' slice records stay
             identical. Announced available_clients=0 yields capacity_clients with zero connections;
             API version 1.5.0.0 yields incompatible_api with zero commands. A schema-1 standard
             station on the same PC returns 404 for /native-flex, control manual and the unchanged
             audio_unconfigured receive refusal and makes no connection to a radio it could hear, while the native
             station reports control native and starts receive. Safety: on both, transmit capability
             is unsupported, Enable Tx is refused with the same error, and HALT answers with the same
             status and halt state; no transmit command reaches the radio. A native settings edit
             naming an audio device or CAT control and Detect radio are refused without changing
             profile.json. One real browser shows Standard and Native FlexRadio as read-only
             connection types. The native status line and error-field entry arrive only by the
             radio.native WebSocket push: the page sends no /native-flex request, and stopping the
             emulator changes the line without a request or reload. The error field never shows
             No audio input for it. The line stands in the receive details, not in the top bar, and
             opens from its error-field entry; the screen has no page scroll at 1366x768. Stopping
             the station turns the line stale. No page errors. */
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String = "tests/native-flex.test.cjs";
        objective {
            verify 'CL-013-02';
            verify 'CL-013-04';
            verify 'CL-013-05';
            verify 'CL-013-06';
            verify 'FR-008';
            verify 'FR-009';
            verify 'FR-023';
        }
    }
    verification 'TC-023-004' {
        doc /* #### TC-023-004 — Live direct-radio tuning and slice lifecycle

             **Promise:** FR-023; FR-009. **Level: 4 — Controlled live tests with operator consent.**
             **Where it runs:** Windows PC and a designated FlexRadio test station, using a recorded
             supported model/firmware and hardware capacity of at least four usable slices.

             **Inputs/actions:** With explicit consent, stop the external SmartSDR desktop/CAT/DAX
             applications, connect the candidate directly, establish the intended slice associations
             and perform approved receive tuning and slice allocation/release/reconnection. Record
             and restore the test station's agreed operating state. Do not transmit in this case.

             **Expected results:** Direct control/status and selected receive streams operate without
             those desktop applications. Each station retains its intended slice and other stations
             remain isolated through the approved lifecycle actions. Live tuning/allocation changes
             radio state, so this case is not classified as read-only level 3. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'FR-009';
            verify 'FR-023';
        }
    }
    verification 'TC-023-005' {
        doc /* #### TC-023-005 — Observational live status, only where genuinely read-only

             **Promise:** FR-023. **Level: 3 — Live read-only tests.**
             **Where it runs:** An authorized designated FlexRadio station and the Windows PC.

             **Inputs/actions:** Observe existing discovery/status/stream identity using a path that
             does not allocate/release slices, tune, change configuration or request transmission.

             **Expected results:** Reported state matches the designated radio without changing its
             operating resources. If the selected API workflow requires such changes, use the level-4
             case and operator consent instead; do not relabel a mutating test as observational. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'FR-023';
        }
    }
    verification 'TC-023-006' {
        doc /* #### TC-023-006 — Conditional future transmit validation

             **Promise:** FR-008/FR-009, FR-023; CL-013-05.
             **Level: 5 — Tests with external effects and explicit operator consent.**
             **Where it runs:** A designated authorized physical test station, only after transmit
             functionality, its ownership policy and the specific test operation have been approved.

             **Inputs/actions:** Under that later approval, request a controlled transmission from
             the owning station and a conflicting request from another profile; exercise the
             specified abort/device-loss path.

             **Expected results:** The agreed single-radio transmit authority is enforced, conflicts
             are refused and FR-008 halt/failure behavior is met. This conditional definition does
             not authorize transmission now or make it part of the receive-only live test above. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-013-05';
            verify 'FR-008';
            verify 'FR-009';
            verify 'FR-023';
        }
    }
    dependency CL_013_01_verified_by_TC_023_001 from 'CL-013-01' to 'TC-023-001';
    dependency CL_013_02_verified_by_TC_023_003 from 'CL-013-02' to 'TC-023-003';
    dependency CL_013_03_verified_by_TC_023_002 from 'CL-013-03' to 'TC-023-002';
    dependency CL_013_04_verified_by_TC_023_001 from 'CL-013-04' to 'TC-023-001';
    dependency CL_013_04_verified_by_TC_023_002 from 'CL-013-04' to 'TC-023-002';
    dependency CL_013_04_verified_by_TC_023_003 from 'CL-013-04' to 'TC-023-003';
    dependency CL_013_05_verified_by_TC_023_002 from 'CL-013-05' to 'TC-023-002';
    dependency CL_013_05_verified_by_TC_023_003 from 'CL-013-05' to 'TC-023-003';
    dependency CL_013_05_verified_by_TC_023_006 from 'CL-013-05' to 'TC-023-006';
    dependency CL_013_06_verified_by_TC_023_003 from 'CL-013-06' to 'TC-023-003';
    requirement NativeFlexWireSubset {
        attribute coverage : WstxRequirements::ImplementationState = WstxRequirements::ImplementationState::partial;
        doc /* FR-023 delivered receive/control subset and the defaults chosen where the
             model left gaps (issue #13, level 2). Wire facts come from the SmartSDR TCP/IP
             API wiki and the pinned FlexLib 4.3.16.42034 reference archive SHA-256
             60978db51dac6ea781899dd80832ad4e7876ce96ed72532b57106376fc26463f, used as a
             protocol reference only: no vendor code is translated, linked, run or
             redistributed, and the station needs no .NET, SmartSDR, CAT or DAX program.
             Placement: one station process is one GUI-class API client on its own TCP
             session; the radio's client-scoped ownership of slices/streams is the shared
             arbitration authority. The station changes only the one slice and stream it
             created and confirmed under its current client handle and never sends client
             disconnect, start_persistence on, load_from, tx, xmit or other transmit or
             global commands. A common cross-process connector stays unimplemented; the
             radio's GUI-client limit is therefore a visible capacity limit. The session is
             owned by the station's receive owner and started with the process; a band
             selection tunes through it inside the selection's own operation, one at a time,
             without a CAT transition lease.
             Authorization (mirrors CL-022-03): the session sends and opens nothing on the radio
             until the HTTPS profile holds a current grant for its scope (state unauthorized);
             no commissioning applies, because no port opens and nothing can key. Losing the
             last grant closes the session, whose slice the radio then releases. A plaintext
             profile therefore never reaches a radio. Monitor-off and receive state do not
             affect the session. States: unauthorized, discovering, connecting, ready,
             unavailable, conflict, stopped. Conflict is client_identity_in_use,
             ownership_ambiguous, slice_ownership or dax_channel_conflict; every other error is unavailable:
             discovery_unavailable, radio_not_found, incompatible_api, capacity_clients,
             capacity_slices, capacity_dax, antenna_unavailable, radio_refused, transport_lost,
             protocol_error, timeout, resource_lost.
             Discovery: passive listening on UDP 4992 shared with address reuse, never a
             broadcast or any datagram sent (WSTX_FLEX_DISCOVERY may name another IPv4 bind
             address, which the tests use with loopback); VITA type 3, OUI 0x001C2D, class
             0xFFFF; 3 s per attempt. No radio identity is saved (#22): the station takes the
             first announced radio with a free GUI client (next available); a radio announcing
             available_clients=0 gets no connection, and when only such radios are heard the
             result is capacity_clients; nothing heard is radio_not_found. The serial in an
             announcement is shown, never saved or compared. This inbound radio traffic is not
             the WSJT-X UDP interface, which stays send-only (#40). A profile's radio_address
             replaces discovery (nothing listens) and means that one radio, with no fallback: a
             routed path carries no broadcast. A full radio there reports radio_refused, since no
             announcement states capacity. Model, serial and firmware then come from the radio's
             info reply, sent after the API check. The radio takes the client's address from the
             control connection, so a NAT stays right and only the port is told (client udpport).
             On that path the session sends client udp_register handle=<own handle> from the
             stream's own UDP port to the radio's UDP ports 4991 and 4993, right after client
             udpport and every 5 s, to open and keep open the way back through connection tracking
             (WSTX_FLEX_REGISTER_PORT replaces both ports for tests).
             Control: TCP to the announced ip/port (default 4992) or the saved address, connect/step deadline 5 s,
             lines <= 4096 bytes incoming and <= 1024 outgoing, one outstanding command, reply
             codes hexadecimal. Only API protocol V1.4.0.0 is admitted; any other version
             refuses before the first command (incompatible_api). Firmware/model are displayed,
             not qualified.
             Session: sub client all; client start_persistence off, whose reply proves the client
             list has arrived; then refuse if the saved client identity is already connected
             (client_identity_in_use, no takeover); client gui <saved client identity>; sub slice all; sub dax all; any slice already
             attributed to the fresh handle is ownership_ambiguous and untouched; client udpport
             <own UDP port>; slice create rxant=<saved antenna> mode=DIGU (no frequency: the
             radio's choice until the station operation tunes); success needs the slice status
             with the own client handle; reply 50000001/50000003/5000001D is capacity_slices; a
             different reported antenna releases the own slice (antenna_unavailable); DAX channel
             = lowest of 1..8 unused by any visible slice (else capacity_dax); slice set dax;
             stream create type=dax_rx; ready only with the stream status of the own handle and
             channel, and with the slice on the frequency of the last confirmed selection when
             there is one (read first, a read-back failure ends the attempt), so the selection
             stays true after a reconnect. Stations choosing together can pick one channel: while
             a lower slice shows the own channel, the session closes (dax_channel_conflict) and
             chooses again.
             Read first (CL-044 rule): a slice setting (mode, frequency, DAX channel) is compared
             with the slice's current status and written only on a difference, then read back
             from the radio's status for that slice. A FLEX-6600 on firmware 4.3.16 replies to slice
             tune and volunteers no status (measured 2026-11-06), so after a write the session asks
             with sub slice all, whose full status is the read-back; a read-back that does not arrive
             by the step deadline fails the operation. A band selection then fails with radio_timeout (a
             radio refusal with radio_rejected, a lost session with radio_unavailable) and keeps
             no native_readback origin. Equal status sends no command. All BANDS stay admitted:
             the radio's refusal decides. The radio object of /receive/selection keeps its shape:
             connection_generation is the session number, state ready / connecting (discovering,
             connecting) / closed (stopped, unauthorized) / unavailable (unavailable, conflict),
             error the session error, frequency the own slice's status while ready, every other
             observation null.
             Samples: only datagrams from the radio address with the own stream ID, VITA type 3
             and packet class 0x03E3 (stereo big-endian float32, 24 kHz, 128 frames per packet, as
             the station's FLEX-6600 sent on 2026-11-06) enter the existing native
             queue/converter/epoch path, channel 0 only, each frame held twice for the 48 kHz
             converter, whose 6 kHz low-pass removes the images; other IDs are counted foreign,
             48/96 kHz and reduced-bandwidth classes are refused as invalid. A real routed path reorders
             about one packet in 300 and truly loses about 0.04% (measured 2026-11-06), so packets go
             on in the order of their 4-bit count, waiting until at most 5 packets wait behind a
             missing one (8 or more lost in a row cannot be told from late by the count, and read as late). A turn given up becomes silence of the packet's length, keeping the timeline
             and the analysis window, and counts lost; that packet arriving later, or any packet
             arriving twice, is dropped and counted late. An arrival gap above 200 ms is unknown loss
             (native_discontinuity) because the count may have wrapped: what waits goes on first and
             the count starts over. The receive socket asks for a 1 MiB buffer, and packets enter the queue in
             groups of at least 10 ms, as an audio device delivers them. Timing: each packet carries its host arrival
             time less its own duration, so the epoch is correlated to the system clock; network
             and radio latency stay in it: the same anchor gave 453 decodes in 11 of 11 periods with
             a median DT of -0.1 s against jt9 over a routed path (2026-11-06). VITA timestamps are not used: that radio, with no
             GPS, sent a frozen filler value on every packet (GET /native-flex reports the radio's timestamp kind and this host's
             clock minus it, for that measurement), and drift follows the same filtered clock tracking as an audio device.
             Tuning: the station operation's band selection on the own slice (origin
             native_readback).
             Loss: closing the own TCP session is the only cleanup of a lost session; the radio's
             release of a GUI client's resources on disconnect is assumed and must be confirmed
             live. Retry backoff 1, 2, 4 s (cap 4 s), reset after ready. A receive job started on
             the native input survives a lost session: its audio status shows unavailable, and the
             new session's first packet opens a new source epoch (reason capture_loss, trigger
             native_discontinuity, counted in loss_epochs and last_loss). A new receive start while
             the session is not ready is refused radio_unavailable. Startup resume (CL-045-02)
             uses the session as its input and waits up to the same 20 s for it.
             Push: state, error, radio facts and own slice facts reach the client only as the
             radio.native WebSocket event under the PushedStationState subscription rule, sent once
             per peer as its snapshot and then on each change, never for packet counters; the client
             sends no request for them. Exact data {profile_id,boot_id,state,error,radio_code,
             session,radio,slice,retry_after_ms,transmit}, radio null or {serial,model,firmware,
             protocol,address}, slice null or {index,letter,frequency_hz,mode,rx_antenna,
             dax_channel,stream_id}, transmit always unsupported, at most 4096
             encoded bytes. GET /native-flex is the read-only snapshot, the same keys plus v, packets
             {accepted,foreign,invalid,lost,late}, last_peak and vita {tsi,host_minus_radio_ms} and arrival
             {jitter_mean_ms,jitter_max_ms}, reset per session, for diagnosis and tests, 404 for standard
             profiles; no request accepts a slice, stream or handle as authority. A session that is
             not ready shows the ErrorFieldEntry nativeRadio with its state and error; the
             "No audio input" entry does not apply to a native profile. The status line stands
             below the operating radio line in the receive details, never in the top bar; on a
             lost station link it reads stale instead of the last radio state.
             Transmit: not offered (capability unsupported, TC-023-006 later and separately
             approved). HALT, the Tx watchdog and Abort stay in the server's one transmit owner
             with no native key path, so they answer as on an unconfigured standard station and
             nothing can key the radio. CAT, Detect radio, radio settings and the Tx level do not
             apply and are refused or inert; the standard path is unaffected and never opens a
             native socket.
             Pinned (CL-013-02), read from the station's radio on 2026-11-06: model FLEX-6600,
             firmware SmartSDR 4.3.16.42034, API V1.4.0.0, 4 slices. Admission is by API version;
             another model or firmware speaking it connects and is displayed but not claimed as
             supported. The displayed model, serial and firmware are the announced ones, or the
             info reply's on a saved address.
             Profile: the connection type is chosen at creation (--create-native-flex-profile
             <dir> <rx antenna> [<address:port>]) and is read-only in the browser. tests/flex-live-check.cjs is the one-run live measurement. Remaining: hardware/firmware,
             24 kHz DAX, latency/timestamps, >= 4 usable slices, broadcast discovery and resource
             release on disconnect (TC-023-004/005); transmit (TC-023-006). */
    }
    dependency nativeWireSubset from NativeFlexWireSubset to WstxRequirements::'FR-023';
    requirement NativeFlexBoundary {
        attribute coverage : WstxRequirements::ImplementationState = WstxRequirements::ImplementationState::partial;
        doc /* Phase2 optional native radio path retains standard independent audio/CAT
             and browser/DSP/QSO/MCP boundaries, without external SmartSDR desktop,
             CAT or DAX bridges. Radio-side firmware/API support still matters. Audio
             and control may reference one managed session, settled in NativeFlexWireSubset.
             Persist profile intent without a radio identity (#22, 2026-11-06);
             reconcile transient handles on connection, never guess another slice or
             replay transmit intent. One effective arbitration authority spans shared
             physical resources and transmission; an in-process mutex per station is
             insufficient. A verified API may justify a common connector, but its
             lifetime cannot depend on one station whose stop must leave others usable.
             No fixed four-GUI-client or simultaneous independent transmitter promise. */
    }
    dependency nativeBoundary from NativeFlexBoundary to WstxRequirements::'FR-023';
}
