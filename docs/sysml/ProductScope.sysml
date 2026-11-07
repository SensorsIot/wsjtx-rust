package WstxProductScope {
    private import ScalarValues::*;
    private import WstxRequirements::*;
    private import WstxArchitecture::*;
    private import WstxStationProtocol::*;
    private import WstxProfiles::*;
    private import WstxRecordingReceive::*;
    private import WstxOfflineDecode::*;
    private import WstxRadioIO::*;
    private import WstxOperatingLayout::*;
    private import WstxOperatingReceive::*;
    private import WstxTransmit::*;
    private import WstxContact::*;
    private import WstxMcp::*;
    private import WstxUdp::*;
    private import WstxStrategy::*;
    private import WstxContest::*;
    doc /* Canonical product scope and navigation. WstxRequirements owns stable
         FR/CL/TC declarations. WstxArchitecture owns parts/ports/connections;
         WstxStationProtocol the shared status/auth/transport contract;
         WstxProfiles configuration/persistence; WstxRecordingReceive recording/display;
         WstxOfflineDecode pure FT4/FT8 processing and payloads; WstxRadioIO live
         capture/conversion/CAT; WstxOperatingLayout presentation and WstxOperatingReceive receive selection/content coding;
         WstxTransmit FT8/FT4 message packing, waveform and transmit period scheduling;
         WstxContact the standard FT8 contact, sequencing, log and operator displays;
         WstxStrategy award strategies, their value order and strategy runs;
         WstxContest the contest strategies and their profiles from the official rules.
         Requirements and exact algorithm/interface/verification semantics in these
         packages are one functional authority. A view renders existing facts; it is
         not an extra architecture. Declared coverage is not an execution verdict.
         Process/build/skill documentation remains outside the product model. */

    attribute def BehaviorBaseline {
        attribute suite : String = "WSJT-X";
        attribute release : String = "v3.3.0-beta4";
        attribute sourceCommit : String = "0f7d5928449ec747c3d1f6da1306f8c94404c3a9";
        attribute releaseReference : String = "https://github.com/WSJTX/wsjtx/releases/tag/v3.3.0-beta4";
        attribute portableCodecManifest : String = "fixtures/decoder/reference-manifest.json";
        doc /* Extract useful documented/observed suite behaviour, not its file/module
             layout or every utility executable. The imported original branch remains
             an archive, not this current behaviour baseline. A newer beta requires an
             explicit baseline change. Selected GPL-compatible numerical routines may
             be adapted into Rust with provenance/attribution retained. Rust is the
             station/protocol implementation; HTML/CSS/JavaScript is the browser.
             Existing native Windows audio/CAT bindings are allowed only at their
             reviewed safe-interface boundary; Fortran/C++ is not the final runtime. */
    }
    enum def BaselineMode { enum FST4; enum FST4W; enum FT4; enum FT8; enum JT4; enum JT9;
        enum JT65; enum MSK144; enum Q65; enum WSPR; enum Echo; enum JTTY; }
    attribute def ModeCapability {
        attribute mode : BaselineMode;
        attribute receive : WstxRequirements::ImplementationState;
        attribute encode : WstxRequirements::ImplementationState;
        attribute operation : WstxRequirements::ImplementationState;
        doc /* Initial inventory, not a claim of implemented support. Only FT4/FT8
             have partial live-receive implementations in the current baseline.
             Transmission and full QSO remain target for both; all other listed modes
             require variant/submode/timing/message/special-workflow inventory before
             implementation completeness. A decoder alone never enables transmit.
             Unsupported operations are refused rather than silently using another mode. */
    }
    attribute def ReleasePolicy {
        attribute firstDesktopPlatform : String = "Windows x64/MSVC";
        attribute laterDesktopPlatforms : String = "macOS; Linux";
        attribute firstReleaseIncludesMicrocontrollers : Boolean = false;
        attribute optionalSecondaryEdition : String = "microcontrollers and constrained devices";
        doc /* Exact supported Windows versions and final hardware matrix remain
             unsettled beyond the initial x64 development target. Validate platform
             audio/control/UI/packaging/performance before claiming a later desktop
             target. A secondary edition chooses its own modes/hardware/memory/link
             limits; desktop features need not fit a microcontroller. Keep protocol
             and DSP boundaries portable where practical. No fixed physical radio
             count follows from station count. Four concurrent stations is a minimum
             reference acceptance workload, not a software limit or hardware promise. */
    }
    requirement ProductCapabilities {
        doc /* Intended useful WSJT-X/MAP65/QMAP scope includes receive/transmit audio
             and DSP; encoding/decoding/synchronization/message handling; station/radio
             configuration and sequencing; spectrum/waterfall/decode/operator displays;
             QSO/logging/reporting and external protocols; EME astronomical/Doppler/Echo
             workflows; wideband/IQ/polarization/application coordination; selected
             command-line/data/help/packaging utilities. Each selected capability has
             an owner and explicit target/partial/implemented state. Do not infer full
             suite parity from FT4/FT8 receive or construct speculative services.
             Exact inventories for logging compatibility, external UDP/reporting,
             EME, wideband and utilities remain unresolved before their implementation.
             Wideband/complex/multichannel input requires explicit typed capabilities,
             never reinterpretation as mono real audio. Modes need not share FT8's
             timing or interactive-QSO assumptions. */
    }
    attribute def AccelerationPolicy {
        attribute coverage : WstxRequirements::ImplementationState = WstxRequirements::ImplementationState::target;
        attribute cpuOnlyRequired : Boolean = true;
        attribute cpuWorkersBounded : Boolean = true;
        attribute automaticWorkersAccountForAllProfiles : Boolean = true;
        attribute operatorWorkerOverrideRequired : Boolean = true;
        attribute preserveDependentStageOrder : Boolean = true;
        attribute gpuRequiredForFirstRelease : Boolean = false;
        attribute selectedGpuApi : String[0..1];
        doc /* Planned desktop optimization route, not implemented acceleration.
             Use bounded CPU workers for independent jobs while reserving audio,
             control and UI capacity. Automatic selection cannot assume each station
             owns the whole PC. Profile optimized FFT/layout/buffer reuse/SIMD first;
             capability-select instruction paths and retain a portable CPU path.
             GPU or other batch/spectrum acceleration is optional; no CUDA/Vulkan/
             Metal/vendor API has been selected. Unavailable/failed optional backends
             fall back to CPU with understandable status. All paths use the same
             independent protocol vectors/recordings, correctness/missed/false-result
             criteria, numeric tolerances and cancellation obligations.
             Measure full audio-to-usable-result latency, scheduling/transfers/delivery,
             interface responsiveness and memory, not just arithmetic throughput.
             Keep an optimization only when measured end-to-end benefit justifies
             maintenance. Evidence names CPU/GPU/OS/compiler/build/workers/workload,
             memory and timing distributions. Benchmark one/multiple workers and each
             available backend on identical inputs; release-specific acceleration
             budgets and supported backends require measured agreement. */
    }
    requirement QualityAndVerification {
        doc /* Preserve selected on-air message and waveform interoperability. Exact
             discrete packing/FEC/symbol vectors and justified floating tolerances are
             independent expectations. Evaluate success, false positives, sensitivity,
             runtime, weak/overlapping/offset signals and device/operator workflows.
             WstxOfflineDecode fixes its current mode-specific numeric/resource limits;
             those concrete limits supersede general unsettled-budget language.
             Reference decoder output alone is not exhaustive truth. Pin reference
             binary/version/hash/settings/input; do not substitute the original archive.
             Compare receive/transmit interoperability through recordings/controlled
             loopback before applicable live operations. Preserve configuration/logs
             across ordinary restart and report device/connection failure truthfully.
             DSP/protocol processing remains independently testable without GUI/radio.
             Dependencies must be GPLv3-compatible with applicable notices retained.
             Windows acceptance precedes its first release; each later platform has
             its own validation and explicit unsupported capability declarations. */
    }
    requirement SharedDataOwnership {
        doc /* Profile/boot identity, revision, authentication, Origin, HTTP/WebSocket
             validation and liveness have one shared owner. Native audio/conversion,
             canonical immutable sample blocks, shared receive jobs, FFT spectrum and
             pure FT4/FT8 modem are implemented boundaries, not a second profile or
             transport authority. WstxRecordingReceive defines source schema/lifetime,
             WstxRadioIO native conversion/timing and WstxOfflineDecode numerical work.
             Integer-to-real PCM mapping is not AGC/filtering/normalization. Native
             rate conversion has one owner; no recorded/live-specific modem resamplers.
             RustFFT provider/conventions are shared while mode/display plans remain
             scoped by their contracts. No speculative FFT wrapper or duplicate cache.
             Context carries stable profile/display identity, validated config revision
             and boot; ports/names are not identity. Secrets are not ordinary snapshots.
             Operations distinguish caller authority, request/operation ID, result/error,
             current revision, pending and completion. Reconnection snapshots never
             replay a stale transmit request. Concrete wire mappings are explicit,
             never serialization of whole internal objects. File transfer is separate
             from small control messages and selects recording identity, not client paths. */
    }
    requirement CompletedContactIdentity {
        attribute coverage : WstxRequirements::ImplementationState = WstxRequirements::ImplementationState::target;
        doc /* QSO/logging owns stable completion identity, agreed fields and explicit
             persisted-versus-unsaved outcome. Replayed completion cannot silently
             create a second contact. Each profile owns contact storage; the browser,
             MCP and reconnect path cannot bypass station/transmit authority or another
             profile's storage. Exact fields/format/compatibility and duplicate/recovery
             behaviour are settled before this capability is implemented. */
    }
    requirement ProcessingAndHaltOwnership {
        doc /* One station owner serializes validated state transitions while bounded
             CPU work runs outside it and returns job-tagged output. Validate profile,
             source and generation on input/completion/cancel; obsolete results cannot
             overwrite a new source/mode. Clients distinguish confirmed/pending/stale;
             required results, radio/QSO/contact state remain server-owned.
             Recorded/live samples share one receive boundary; sample clock differs
             from optional UTC metadata. Live device/sample-to-UTC mapping never uses
             browser timers. Network execution is not a decoder work queue. All jobs,
             buffers/concurrency have declared bounds and an operator-visible budget
             across profiles. Cooperative cancellation has bounded checkpoints; halt
             MUST NOT wait for decode completion, receive cancellation or visualization.
             Unbounded blocking workers are not a CPU scheduler; an already running
             blocking task is not claimed abortable. Concrete shared executor and
             acceleration choices require measured workloads, with CPU correctness. */
    }
    attribute def TransmitSafetyPolicy {
        attribute coverage : WstxRequirements::ImplementationState = WstxRequirements::ImplementationState::partial;
        attribute armedOnStartup : Boolean = false;
        attribute haltWaitsForDecode : Boolean = false;
        attribute mcpMayOverrideLossPolicy : Boolean = false;
        doc /* Transmission is not enabled by the receive baseline. Before hardware
             TX, settle controller/device loss and authority expiry, local stop deadline
             and resource/VOX policy. MCP cannot invent a different safety policy.
             Obtain common authority, prepare selected audio and radio/PTT, schedule,
             then handle completion/halt/failure. Audio failure leaves control-side
             halt/release usable; control failure never fabricates radio-ready state.
             Browser timers or optional display congestion cannot hold transmit authority.
             Settled by #9 slice B (WstxTransmit::TransmitAuthority, TransmitTiming,
             PttControl): per-boot explicit authority, 250 ms halt, release on device
             or CAT loss, off-only recovery, no VOX; physical acceptance remains
             TC-008-002. */
    }
    requirement RemoteDeliveryPolicy {
        doc /* Commands/state/results have priority over discardable visualization.
             Server produces reduced display data; JavaScript renders/colors/local
             filters it. Visualization may be disabled. Raw audio is an explicit
             source/transfer, not mandatory continuous remote browser traffic.
             Commands are accepted/refused/failed explicitly, never silently dropped.
             Old display frames may be replaced; required state/QSO/decode information
             instead has delivery/resynchronization or explicit loss reporting. Refuse
             new work at its budget without disrupting other instances. Restart/link
             loss cancels or marks operations unavailable according to their contract.
             No single-instance status test proves aggregate audio/DSP/display for N
             instances; each workload names its limits and measurement layer. */
    }
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
    attribute def FixtureProvenance {
        attribute ft8Manifest : String = "fixtures/decoder/manifest.json";
        attribute ft4Manifest : String = "fixtures/decoder/ft4-manifest.json";
        attribute codecReference : String = "fixtures/decoder/reference-manifest.json";
        attribute simulatorManifest : String = "fixtures/decoder/simulator-cases.json";
        attribute sampleSource : String = "https://github.com/kgoba/ft8_lib/tree/9fec6ca39886edbf96f4f5e71edc76da5074e871/test/wav";
        doc /* Manifests pin identity/hashes/source/license limitations. Existing text
             outputs are historical references, NOT exhaustive independently verified
             ground truth. Independently synthetic/noise/overlap/offset inputs accompany
             live recordings to measure sensitivity, false decodes and numeric error.
             Evaluate interoperability/quality/latency rather than adopting embedded
             resource limits. Sample use does not require importing its decoder.
             WstxOfflineDecode owns concrete protocol/physical fixture expectations and
             simulator admission; README retains attribution and sample licensing.
             Investigation dates or discovery history are not functional obligations. */
    }
    package ContractIndex {
        doc /* Numeric references inside model prose are local contract aliases. 4.1/6.1/12.1..12.4:
             SharedProtocol. 4.2/6.2/12.5: Profiles. 4.3/6.3: NativeFlex plus FR-023
             and its six TC-023 cases. 4.4/6.4: RecordingAndDisplay and Modem;
             4.5/12.8: LiveRadio. 4.7/6.6: Operating. 11: Architecture.
             12.1.1/4.7.3/4.7.5/12.8.1: OperatingReceive. 12.6: RecordingAndDisplay. 12.7: SharedRecord. 13.6: Modem's simulator
             verifications. Other scope/quality/provenance clauses are in this package.
             These aliases are resolved model elements, not external file references. */
        alias SharedProtocol for WstxStationProtocol;
        alias Profiles for WstxProfiles;
        alias NativeFlex for WstxProductScope::NativeFlexBoundary;
        alias RecordingAndDisplay for WstxRecordingReceive;
        alias Modem for WstxOfflineDecode;
        alias LiveRadio for WstxRadioIO;
        alias Operating for WstxOperatingLayout;
        alias OperatingReceive for WstxOperatingReceive;
        alias Architecture for WstxArchitecture;
        alias Transmit for WstxTransmit;
        alias Contact for WstxContact;
        alias Mcp for WstxMcp;
        alias Udp for WstxUdp;
        alias Strategy for WstxStrategy;
        alias ContestStrategies for WstxContest;
        alias SharedRecord for WstxOfflineDecode::ResultRecord;
    }
    dependency scopeBoundary from ProductCapabilities to WstxRequirements::'FR-004';
    dependency contactBoundary from CompletedContactIdentity to WstxRequirements::'FR-011';
    dependency safetyBoundary from TransmitSafetyPolicy to WstxRequirements::'FR-008';
    dependency nativeBoundary from NativeFlexBoundary to WstxRequirements::'FR-023';
    dependency deliveryBoundary from RemoteDeliveryPolicy to WstxRequirements::'FR-021';
}
