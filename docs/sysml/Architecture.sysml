package WstxArchitecture {
    private import ScalarValues::*;
    private import ModelNotes::FollowsSource;
    private import WstxRadioProperties::RadioCapabilities;
    private import WstxRadioProperties::RadioResultStatus;
    private import WstxRadioProperties::RadioState;
    private import WstxRadioProperties::RadioSettings;
    private import WstxRadioProperties::RadioMeters;
    private import WstxRadioProperties::FrequencyRange;
    private import WstxRadioProperties::RadioAudioSettings;
    private import WstxRadioProperties::RadioDigitalValues;
    private import WstxRadioProperties::RadioFrontPanelValues;
    private import WstxRadioProperties::RadioKeyerSettings;
    private import WstxRadioProperties::RadioMemoryValues;
    private import WstxRadioProperties::RadioReceiverSettings;
    private import WstxRadioProperties::RadioScanningValues;
    private import WstxRadioProperties::RadioScopeSettings;
    private import WstxRadioProperties::RadioSpectrum;
    private import WstxRadioProperties::RadioToneSettings;
    private import WstxRadioProperties::RadioTransmitterSettings;
    private import WstxRadioProperties::RadioTuningValues;
    doc /* Product structure: one selected-radio deployment context, its frontend and backend
         containers of the product's functions, software owners and typed exchanges.
         The frontend may run locally on the backend computer or remotely over the
         station link; the logical
         roles and profile-scoped protocol remain the same. Windows x64/MSVC is the
         first desktop target; portability and later platforms follow
         WstxProductScope::ReleasePolicy, not an assertion of platform acceptance.
         WstxRequirements owns stable capability/status and verification declarations.
         WstxProductScope owns capability scope, shared data ownership, processing/halt,
         remote delivery and transmit safety policies. This structure includes target
         responsibilities; a part or connection does not assert delivered capability.
         System processes classify technical capabilities in the existing receive,
         mode, transport and device owners. Operating workflows classify operator
         QSO actions in station/transmit/QSO and browser responsibilities; configuration
         workflows classify persisted settings in profile/station responsibilities.
         Strategy workflows classify objectives, ranking and automation, all target
         only; selection/ownership policies remain planned. These four behavioural
         groups do not introduce additional runtime services or a strategy engine.
         Items below describe semantic responsibilities, not wire schemas or Rust APIs.
         Detailed behaviour stays with WstxStationProtocol, WstxProfiles,
         WstxRecordingReceive, WstxOfflineDecode, WstxModemDecode, WstxRadioIO,
         WstxOperatingLayout and WstxOperatingReceive. */

    part physicalStation {
        doc /* The deployment of the product's functions: the browser client functions
             (frontend) and the server process functions (backend), with their populations
             and connections. Outside things are not parts; OutsideThing lists them. */
        part frontend : Frontend;
        part backend : Backend;
        part browserAttachments[*] : BrowserAttachment;
    }
    view physicalInterconnection : StandardViewDefinitions::InterconnectionView {
        expose physicalStation::*;
    }

    enum def OutsideThing {
        doc /* The outside things the server opens a socket, device or file to. None is a
             part or has a port. The function that owns each carries its information and
             state on the ports it offers to other functions; the wire protocol is that
             function's inside. */
        enum catRadio {
            doc /* The transceiver's CAT serial link, a COM port found by device enumeration. */
            @FollowsSource {
                reference = "Icom IC-7300 Full Manual A7292-4EX-12a, CI-V command table";
            }
        }
        enum flexRadio {
            doc /* A FlexRadio through its native API: a TCP command channel and UDP VITA-49
                 streams. */
            @FollowsSource {
                reference = "SmartSDR TCP/IP API and FlexLib, as "
                    + "WstxProductScope::NativeFlexWireSubset pins them";
            }
        }
        enum soundDevice {
            doc /* The sound-card capture and playback endpoints. */
            @FollowsSource { reference = "Windows Core Audio WASAPI, shared event-driven mode"; }
        }
        enum browser {
            doc /* The operator's browser, over HTTPS and WebSocket on the station listener.
                 WstxStationProtocol is the product's own protocol over them. */
            @FollowsSource {
                reference = "RFC 9110 HTTP, RFC 6455 WebSocket, TLS 1.2 and 1.3 "
                    + "(RFC 5246, RFC 8446)";
            }
        }
        enum mcpClient {
            doc /* MCP clients, POST /mcp on the same listener. A client reaches one station's
                 McpAdapter over that station's own HTTPS listener with its own auth-v1 grant
                 (WstxMcpEndpoint::McpEndpoint, McpCredential); it may run on any authorized
                 computer. */
            @FollowsSource {
                reference = "Model Context Protocol, Streamable HTTP, "
                    + "the eras WstxMcp::ProtocolEras names";
            }
        }
        enum udpPeer {
            doc /* The configured WSJT-X UDP targets, send-only. */
            @FollowsSource {
                reference = "WSJT-X Network/NetworkMessage.hpp, the version WstxUdp names";
            }
        }
        enum pskReporter {
            doc /* The PSK Reporter MQTT broker, subscribe-only over TLS. */
            @FollowsSource { reference = "MQTT 3.1.1 (OASIS), PSK Reporter MQTT feed"; }
        }
        enum clubLog {
            doc /* The Club Log Most Wanted download, on request. */
            @FollowsSource { reference = "Club Log mostwanted.php API, JSON"; }
        }
        enum timeServer {
            doc /* The SNTP servers. */
            @FollowsSource { reference = "RFC 4330 SNTP client, RFC 5905 packet"; }
        }
        enum windowsTime {
            doc /* The Windows Time service, its state read only. */
            @FollowsSource { reference = "Win32 Service Control Manager API"; }
        }
        enum profileFiles {
            doc /* The profile directory and its files. */
            @FollowsSource {
                reference = "ADIF 3.1.8 ADI (contacts.adi); RIFF WAVE PCM (recordings); "
                    + "AD1C cty.dat; the other files are the product's own formats "
                    + "of their owning packages";
            }
        }
        enum tlsFiles {
            doc /* The TLS certificate and key files named at launch. */
            @FollowsSource { reference = "RFC 7468 PEM, X.509 certificate, PKCS#8 key"; }
        }
        enum resourceLocks {
            doc /* The radio identity lock files under %LOCALAPPDATA%. */
            @FollowsSource { reference = "Windows file locking through std::fs::File::try_lock"; }
        }
    }
    dependency catRadioOwner from OutsideThing::catRadio
        to physicalStation::backend::stations::radioControl;
    dependency flexRadioOwner from OutsideThing::flexRadio
        to physicalStation::backend::stations::receive;
    dependency soundDeviceOwner from OutsideThing::soundDevice
        to physicalStation::backend::stations::audio;
    dependency browserOwner from OutsideThing::browser
        to physicalStation::backend::stations::web;
    dependency mcpClientOwner from OutsideThing::mcpClient
        to physicalStation::backend::stations::mcp;
    dependency udpPeerOwner from OutsideThing::udpPeer
        to physicalStation::backend::stations::station;
    dependency pskReporterOwner from OutsideThing::pskReporter
        to physicalStation::backend::stations::qso;
    dependency clubLogOwner from OutsideThing::clubLog
        to physicalStation::backend::stations::qso;
    dependency timeServerOwner from OutsideThing::timeServer
        to physicalStation::backend::stations::transmit;
    dependency windowsTimeOwner from OutsideThing::windowsTime
        to physicalStation::backend::stations::transmit;
    dependency profileFilesOwner from OutsideThing::profileFiles
        to physicalStation::backend::stations::profile;
    dependency tlsFilesOwner from OutsideThing::tlsFiles
        to physicalStation::backend::stations::web;
    dependency resourceLocksOwner from OutsideThing::resourceLocks
        to physicalStation::backend::radioAuthority;

    requirement PhysicalDeploymentStructure {
        doc /* The model MUST contain the frontend and backend containers of the product's
             functions. Frontend and Backend are pure deployment containers without
             forwarding ports or functional policy. Browser and station exchanges MUST
             connect selected functional endpoints directly, retaining profile-scoped
             browser and station selection. Audio and radio control MUST stay separate
             functions. No outside thing is a part or has a port; each is an entry of
             OutsideThing with one owning function. Variable browser and station
             populations MUST NOT become a fixed station count, all-to-all routing, or an
             additional detached deployment. */
    }
    requirement StationResourceIdentity {
        doc /* Architectural refinement of WstxProfiles and
             WstxProductScope::NativeFlexBoundary: each station MUST compose one profile,
             one audio device adapter, one CAT driver and one selected-radio binding, and
             reference the common authority contained in Backend. All control requests
             and outcomes MUST retain request/resource identity through that authority
             to the selected CAT driver. Audio and CAT MUST be separate direct station parts,
             with no combined radio-backend wrapper or variation. Both adapters MUST
             serve the radio the station's radio binding selects, and control MUST NOT
             bypass the common authority.
             A native FlexRadio profile instead reaches its radio through the one native
             session of its station (WstxFlexSession::NativeFlexWireSubset), owned by the
             station's receive owner, with no CAT driver in the path. */
    }
    requirement ResponsibilityAndExchangeBoundaries {
        doc /* Architectural refinement of WstxProductScope::SharedDataOwnership,
             ProcessingAndHaltOwnership, RemoteDeliveryPolicy and TransmitSafetyPolicy:
             the declared owners MUST retain their separate typed/directed exchanges.
             Recording storage MUST feed the common receive path; receive and encode
             MUST connect to pure mode functions; audio and control MUST stay separate.
             Browser/MCP adapters MUST use station operations rather than direct radio
             adapter access. The ownership explanations and existing policy contracts apply
             together; target parts do not claim runtime delivery or settled policy. */
    }
    dependency deploymentOwnership from physicalStation to PhysicalDeploymentStructure;
    dependency stationIdentityOwnership from physicalStation::backend::stations to StationResourceIdentity;
    dependency boundaryOwnership from physicalStation::backend::stations to ResponsibilityAndExchangeBoundaries;

    verification ResolvedArchitectureGraph {
        subject deployment :> physicalStation;
        doc /* Level 2 isolated automated model test on the development PC; no radio,
             device or runtime service. Resolve the accepted model and legal negative
             mutations with the pinned semantic validator. Independent expectations are
             literal required endpoints, complete item-kind/direction signatures,
             population/reference subsets, separate audio/CAT adapter ownership and identity
             bindings
             in the existing architecture integrity oracle, not candidate-derived counts.
             Expect selected-browser-to-web/station direct
             connections through portless associations; frontend/backend containers MUST
             have no forwarding ports. Expect exactly one AudioDeviceAdapter and one
             RustRadioDriver directly
             composed by each station, without combined backend or native-Flex topology;
             audio.backend connects to audioAdapter.host and authorizedControl connects
             to catAdapter.authorized; upload-to-profile-to-receive,
             receive-to-mode and encode-to-mode paths; exactly one effective authority
             whose bound request/outcome and resource context reach that CAT driver.
             Missing direct browser/encode connections, added container forwarding ports,
             reversed provider/waveform direction, wrong item kind, redirected association
             or context, weakened identity binding, split or bypassed authority, missing,
             duplicate or detached audio/CAT adapters, mixed audio/CAT paths, detached
             stations, view-created structure and a port joined to no function
             MUST be rejected even if legal SysML. Two deployment containers and the
             portless browser association population retain selected endpoint identity;
             counts alone are insufficient. This case checks structure, not runtime
             timing, persistence, failure handling, platform operation or RF safety. */
        objective {
            verify PhysicalDeploymentStructure;
            verify StationResourceIdentity;
            verify ResponsibilityAndExchangeBoundaries;
        }
        attribute automation : WstxRequirements::AutomationState = WstxRequirements::AutomationState::implemented;
        attribute executable : String = "tools/sysml.py check; tools/sysml/tests/test_architecture_integrity.py";
        attribute executionStatus : String = "defined automated companion; declaration records no execution verdict";
    }
    verification ArchitecturalOwnershipReview {
        subject deployment :> physicalStation;
        doc /* Manual contract review on the development PC, without external effects.
             Compare this decomposition with WstxProductScope::ReleasePolicy,
             SharedDataOwnership, ProcessingAndHaltOwnership, RemoteDeliveryPolicy,
             TransmitSafetyPolicy and NativeFlexBoundary, plus existing FR responsibility
             dependencies below and their canonical verification cases. Independently
             expect server-owned state/results/contacts, profile-owned storage, pure
             mode calculations, one conversion owner, independent audio/CAT failure
             boundaries, station-scoped browser/MCP access and priority halt outside
             receive/display work. Check local/remote roles and Windows-first scope
             without asserting later-platform acceptance, fixed radio capacity or
             native-session lifetime decisions. Strategy remains target and introduces
             no service or selection policy. Reject duplicate policy definitions,
             inferred delivery or any ownership/safety weakening.
             ResolvedArchitectureGraph covers only graph/signature/identity obligations;
             this review covers responsibility prose and policy correspondence. Existing
             WstxRequirements cases own executable product behaviour coverage. Target
             TX/MCP/native and future-platform acceptance remain planned where declared
             there; neither this review nor semantic validation executes those cases. */
        objective {
            verify PhysicalDeploymentStructure;
            verify StationResourceIdentity;
            verify ResponsibilityAndExchangeBoundaries;
        }
        attribute method : String = "manual independent contract correspondence review";
        attribute executionStatus : String = "planned review; no verdict recorded by this declaration";
    }

    requirement ComponentPropertyOwnership {
        doc /* Public values MUST be navigable under their owning parts using canonical
             types and value references. Backend-owned persisted profile configuration,
             private runtime input, frontend-owned preference, requested settings and
             observed state MUST remain distinct. A property attachment MUST NOT create
             persistence fields, controls, credentials, workers or another authority. */
    }
    requirement RadioModelReferenceSeparation {
        doc /* A physical radio's model identifier, sparse capabilities, requested
             settings and actual observations MUST remain separate. Current driver
             coverage MUST NOT limit the intended physical-radio property domains.
             Capability observations MUST NOT grant command or transmit permission.
             Receiver filter width MUST NOT be inferred from a named filter or either
             the radio scope span or the browser waterfall span. */
    }
    dependency browserPropertyOwnership from physicalStation::frontend::browsers to ComponentPropertyOwnership;
    dependency stationPropertyOwnership from physicalStation::backend::stations to ComponentPropertyOwnership;
    dependency radioPropertyOwnership from physicalStation::backend::stations::radioControl
        to RadioModelReferenceSeparation;

    verification ComponentPropertyInventoryReview {
        subject deployment :> physicalStation;
        objective {
            verify ComponentPropertyOwnership;
            verify RadioModelReferenceSeparation;
        }
        doc /* Level 2 isolated independent manual contract review on the development PC;
             no device, credential or external effects. Compare the public properties
             and interface signatures against the owning canonical profile, station,
             receive, layout and radio contracts. Expect backend-owned saved profile
             configuration distinct from runtime inputs, frontend-owned preferences,
             boot/live station selection with twelve canonical preferred-band references,
             and requested radio settings distinct from confirmed state and readonly
             meters. Expect optional model/context-dependent semantic radio controls,
             explicit physical units and multivalued/compound states without C codes,
             universal defaults or driver-support ceilings. RadioControl retains the
             common authority/resource and reply identities; audio remains separate.
             Reject catalogue/inventory/driver management, implementation algorithms,
             invented filter widths, conflation of the three Hz spans and inferred
             delivery. Existing graph validation and product verification cases remain
             companions; this declaration records no review or runtime verdict.
             For radio property verification, read pinned Hamlib rig.h standard IDs and
             channel/channel_cap definitions independently, then compare the companion
             tools/sysml/tests/radio_source_coverage.tsv and owning types. Check all114
             standard meanings, stored28members, units, exact native metadata-owner links,
             context-conditioned ranges/power/steps/filter choices and separate access.
             Remove/misroute a metadata owner or change a Hz field to fraction: focused
             tests must refuse it. Expect one current value per property/context, separate
             capabilities, typed temporary query/set parameters, readonly meters, explicit
             failure/stale/unknown semantics, and no requested value confirmed by ACK.
             Inspect unresolved extension limits rather than accepting a completeness claim.
             Run focused tests on this PC at cost2, full Pilot/graph validation and99traces;
             parser success does not execute these planned action contracts. */
        attribute method : String = "manual independent public-property and interface correspondence review";
        attribute executionStatus : String = "planned; semantic resolution does not establish review or runtime acceptance";
    }

    item def StationRequest;
    item def StationOutcome;
    item def Recording;
    item def SampleBlock {
        doc /* Immutable recorded and live samples feed the same receive boundary.
             WstxAudio::SampleBlock owns concrete recorded element units,
             clocks, ownership/lifetime and bounds; WstxRadioIO owns live adaptation.
             Source-specific metadata and discontinuities must be explicit; a generic
             architectural item does not settle every future live format. */
    }
    item def AudioOutcome;
    item def ControlRequest { ref part resourceContext : RadioBinding; }
    item def ControlOutcome { ref item request : ControlRequest; }
    item def ReadRadioCapabilities :> ControlRequest;
    item def RadioCapabilitiesOutcome :> ControlOutcome {
        attribute status : RadioResultStatus;
        attribute capabilities : RadioCapabilities[0..1];
        attribute explanation : String[0..1];
    }
    item def ReadRadioState :> ControlRequest;
    item def RadioStateOutcome :> ControlOutcome {
        attribute status : RadioResultStatus;
        attribute observedState : RadioState[0..1];
        attribute explanation : String[0..1];
    }
    item def ApplyRadioSettings :> ControlRequest {
        attribute requested : RadioSettings;
    }
    item def RadioSettingsOutcome :> ControlOutcome {
        attribute status : RadioResultStatus;
        attribute confirmedState : RadioState[0..1];
        attribute explanation : String[0..1];
    }
    item def ReadRadioMeters :> ControlRequest;
    item def RadioMetersOutcome :> ControlOutcome {
        attribute status : RadioResultStatus;
        attribute meters : RadioMeters[0..1];
        attribute explanation : String[0..1];
    }
    doc /* The operations the CAT driver makes the radio perform, carried by the control
         request and outcome items through the selected binding and the common authority:
         readCapabilities(ReadRadioCapabilities) -> RadioCapabilitiesOutcome;
         readState(ReadRadioState) -> RadioStateOutcome;
         applySettings(ApplyRadioSettings { requested : RadioSettings }) -> RadioSettingsOutcome;
         readMeters(ReadRadioMeters) -> RadioMetersOutcome.
         Each request inherits resourceContext : RadioBinding and every outcome inherits
         request : ControlRequest. Status distinguishes confirmed results from unavailable,
         unsupported, rejected and failed operations. Optional payload absence is never
         confirmation; a returned state contains only actual observations, never requested
         values copied into observations. A successful acknowledgement without observed
         state does not establish confirmedState. Concrete readback behaviour remains
         in the responsible radio contract. Existing CAT request refinements remain valid.
         These are semantic signatures, not new wire protocols or executable adapters. */
    item def ProcessingRequest {
        doc /* Receive job/cancel lifecycle correlates profile, boot, source, job and
             generation with immutable settings/results. WstxRecordingReceive owns
             recorded spectrum lifetimes, bounds and cancellation; WstxOfflineDecode
             refines mode settings/results on that lifecycle. Transmit lifecycle and
             independent halt remain outside receive jobs. */
    }
    item def ProcessingResult {
        doc /* WstxReceiveSpectrum::SpectrumFrame owns spectrum units, identity,
             bounds and replaceable display delivery. WstxOfflineDecode::ResultRecord
             and WstxLiveReceive::ResultPage own mode payloads and required result
             delivery/retention.
             These have different delivery obligations despite sharing processing. */
    }
    item def EncodeRequest;
    item def Waveform;
    item def ProfileRequest;
    item def ProfileOutcome;

    port def StationOperations {
        out item request : StationRequest;
        in item outcome : StationOutcome;
    }
    port def BrowserExchange :> StationOperations {
        out item upload : Recording;
    }
    port def RecordingTransfer { out item recording : Recording; }
    port def ProfileAccess {
        out item request : ProfileRequest;
        in item outcome : ProfileOutcome;
    }
    port def AudioExchange {
        out item playback : SampleBlock;
        in item capture : SampleBlock;
        in item outcome : AudioOutcome;
    }
    port def AudioStatus { out item outcome : AudioOutcome; }
    port def ReceiveSamples {
        out item samples : SampleBlock;
        out item outcome : AudioOutcome;
    }
    port def ReceiveProcessing {
        out item request : ProcessingRequest;
        in item result : ProcessingResult;
    }
    port def EncodeProcessing {
        out item request : EncodeRequest;
        in item waveform : Waveform;
    }
    port def RadioControl {
        out item request : ControlRequest;
        in item outcome : ControlOutcome;
        binding replyContext bind outcome.request = request;
    }
    part def BrowserClient {
        attribute localDisplayLevels : WstxRecordingReceive::DisplayLevels;
        attribute localDisplayPreference : WstxRecordingReceive::BrowserDisplayPreference;
        attribute localActivityOrdering : WstxOperatingLayout::ActivityOrdering;
        attribute observedPresentation : WstxOperatingLayout::OperatingPresentation;
        attribute receivePresentation : WstxOperatingReceive::ReceivePresentation;
        attribute browserWaterfallSpanHz : FrequencyRange;
        doc /* Presentation and preferences are frontend-owned. Waterfall frequency span
             is independent of physical receiver filter width and the radio's own scope. */
        doc /* Own presentation/local filtering/color, pending/stale state and requests; not authoritative radio state, timing-critical modulation or transmit authority. */
        doc /* Holds station state from one snapshot plus the station's pushed events and does not poll it (WstxStationProtocol::PushedStationState, the governing rule of this exchange). */
        port station : BrowserExchange;
    }
    part def Frontend {
        doc /* Deployment container only; station exchanges terminate
             directly on selected contained BrowserClient instances. */
        part browsers[*] : BrowserClient;
    }
    part def Radio {
        attribute modelId : String[0..1];
        attribute physicalIdentity : String[0..1];
        attribute capabilities : RadioCapabilities[0..1];
        attribute tuning : RadioTuningValues[0..1];
        attribute transmitter : RadioTransmitterSettings[*];
        attribute receiver : RadioReceiverSettings[*];
        attribute audioControls : RadioAudioSettings[*];
        attribute keyer : RadioKeyerSettings[*];
        attribute tones : RadioToneSettings[*];
        attribute scope : RadioScopeSettings[*];
        attribute meters : RadioMeters[*];
        attribute frontPanel : RadioFrontPanelValues[*];
        attribute scanning : RadioScanningValues[*];
        attribute digital : RadioDigitalValues[*];
        attribute memories : RadioMemoryValues[0..1];
        attribute spectrum : RadioSpectrum[*];
        doc /* Physical model identity and sparse exposed facts are navigable from the
             selected radio. No catalogue/driver-management service is implied. Observed
             controls, meters and scope remain distinct from requested settings. */
    }
    part def Backend {
        doc /* The variable station population has no architecture-imposed numeric limit. */
        doc /* One backend role hosts variable N station processes. The common authority
             is effective shared-radio responsibility, not a per-process mutex.
             Cross-process placement/leases and actual hardware capacity are constrained
             by WstxProductScope::NativeFlexBoundary and WstxRadioIO. Profile-scoped
             routing is not all-to-all delivery or simultaneous transmission. */
        doc /* Deployment container only; no host forwarding interfaces. Release and
             acceleration policy remain owned by WstxProductScope. */
        part stations[*] : StationProcess;
        part radioAuthority : RadioAuthority;
    }
    part def BrowserAttachment {
        doc /* One profile-scoped browser/station association carried by the physical IP
             link. This portless association selects one browser and one station, never
             the whole population. The station exchange terminates directly on the
             selected WebAdapter. */
        ref part browser : BrowserClient :> physicalStation.frontend.browsers;
        ref part station : StationProcess :> physicalStation.backend.stations;
        connection browserStation connect browser.station to station.web.client;
    }
    part def RadioBinding {
        doc /* The station's selected radio resource. Persisted intent resolves it at
             connection, and every control request carries it as resource context. The
             radio itself is an outside thing (OutsideThing catRadio, flexRadio).
             WstxFlexSession::NativeFlexWireSubset settles native slice and handle
             reconciliation; actual radio capacity is reported at runtime. */
    }
    part def RadioAuthority {
        doc /* One effective authority for constrained resources and transmit access across
             all station/backend choices. This is not a new process placement decision. */
        port requests : ~RadioControl;
        port authorized : RadioControl;
        binding authorizedContext bind authorized.request = requests.request;
        binding returnedContext bind requests.outcome = authorized.outcome;
    }
    part def StationService {
        attribute currentOperatingSelection : WstxOperatingReceive::WireSelection;
        attribute resolvedOperatingSelection : WstxOperatingReceive::Selection[0..1];
        attribute activeSelectionOperation : WstxOperatingReceive::OperationRecord[0..1];
        attribute snapshotIdentity : WstxOperatingReceive::SnapshotIdentity;
        attribute preferred160m : WstxOperatingReceive::PreferredBandEntry = WstxOperatingReceive::preferred160m;
        attribute preferred80m : WstxOperatingReceive::PreferredBandEntry = WstxOperatingReceive::preferred80m;
        attribute preferred60m : WstxOperatingReceive::PreferredBandEntry = WstxOperatingReceive::preferred60m;
        attribute preferred40m : WstxOperatingReceive::PreferredBandEntry = WstxOperatingReceive::preferred40m;
        attribute preferred30m : WstxOperatingReceive::PreferredBandEntry = WstxOperatingReceive::preferred30m;
        attribute preferred20m : WstxOperatingReceive::PreferredBandEntry = WstxOperatingReceive::preferred20m;
        attribute preferred17m : WstxOperatingReceive::PreferredBandEntry = WstxOperatingReceive::preferred17m;
        attribute preferred15m : WstxOperatingReceive::PreferredBandEntry = WstxOperatingReceive::preferred15m;
        attribute preferred12m : WstxOperatingReceive::PreferredBandEntry = WstxOperatingReceive::preferred12m;
        attribute preferred10m : WstxOperatingReceive::PreferredBandEntry = WstxOperatingReceive::preferred10m;
        attribute preferred6m : WstxOperatingReceive::PreferredBandEntry = WstxOperatingReceive::preferred6m;
        attribute preferred4m : WstxOperatingReceive::PreferredBandEntry = WstxOperatingReceive::preferred4m;
        attribute preferredTableSourceCommit : String = WstxOperatingReceive::preferredTableSourceCommit;
        attribute preferredTableSourcePath : String = WstxOperatingReceive::preferredTableSourcePath;
        attribute preferredTableSourceSha256 : String = WstxOperatingReceive::preferredTableSourceSha256;
        attribute minimumSelectionHz : Integer = WstxOperatingReceive::receiveSelectionMinimumHz;
        attribute maximumSelectionHz : Integer = WstxOperatingReceive::receiveSelectionMaximumHz;
        doc /* Mode, band and nominal frequency are live boot/session state, not saved
             profile fields. Preferred entries reference the canonical twelve-band table;
             they do not confer transmit permission or confirm actual radio state. */
        doc /* Own authoritative station state, operations/jobs/transitions and authorization; not HTTP/MCP parsing or device protocol syntax. One owner validates profile/source/generation and rejects obsolete results. */
        doc /* The WSJT-X UDP interface (#40, WstxUdp) is a station-owned adapter of this
             service: it observes station state and results and sends to its configured
             targets; send-only, it enters no command into the station (operator 2026-11-06)
             and owns no station state, modem or transmit authority. */
        doc /* Station-owned validation, state, jobs and operation authority. This owner
             validates uploads before handing them to its selected profile's storage. */
        port webOperations : ~StationOperations;
        port mcpOperations : ~StationOperations;
        port profile : ProfileAccess;
        port receive : StationOperations;
        port transmit : StationOperations;
        port qso : StationOperations;
        port control : RadioControl;
        port upload : ~RecordingTransfer;
        port acceptedRecording : RecordingTransfer;
        port audioStatus : ~AudioStatus;
    }
    part def WebAdapter {
        attribute privateRuntimeInputs : WstxStationProtocol::RuntimeInputs;
        attribute effectiveEndpoint : WstxStationProtocol::EndpointPolicy;
        doc /* Runtime inputs and effective transport/authentication settings are distinct
             from saved endpoint intent. No credential values are instantiated here. */
        doc /* Own embedded client, HTTP/file transfer/versioned WebSocket, transport authentication and Origin checks; no second QSO/modem engine or direct radio writes. */
        doc /* WstxStationProtocol owns shared authentication, Origin and HTTP/WebSocket
             semantics. WstxHttpContentCoding::HttpContentCodingBoundary refines bounded
             GET coding after handler/auth/errors/caps, with one dispatch and unchanged
             JSON/WebSocket identity; it creates no second transport authority. */
        port client : ~BrowserExchange;
        port station : StationOperations;
        port recording : RecordingTransfer;
    }
    part def McpAdapter {
        doc /* Own protocol validation/caller context and configured station-selection/automation requests. No independent station state, backend access or separate transmit permission; same station operations and safety policy as browser. Delivered (#12) as the station's Streamable HTTP endpoint mapping each tool onto one existing station route in-process (WstxMcpEndpoint::ToolCatalog); the configured automation run is owned with the contact engine (WstxMcp::OperatingAutomation) and reaches it only through ContactCommand. */
        port station : StationOperations;
    }
    part def PersistedProfile {
        attribute configuration : WstxProfiles::ProfileDocument;
        doc /* Backend-owned saved configuration uses exactly the canonical profile schema.
             Live operating selection, browser preference and runtime secrets are separate. */
        doc /* Bootstrap/profile owns selection, stable identity, endpoints, exclusive ownership, validation and storage; not DSP or browser state. */
        doc /* Exactly one explicitly selected profile per process owns stable identity,
             configuration, contacts and recordings. WstxProfiles owns its schema,
             persistence, validation and session behaviour. */
        port context : ~ProfileAccess;
        port contacts : ~ProfileAccess;
        port upload : ~RecordingTransfer;
        port recordedSamples : ReceiveSamples;
        part recordings : RecordedSource;
        connection storedUpload connect upload to recordings.upload;
        connection storedSamples connect recordings.samples to recordedSamples;
    }
    part def RecordedSource {
        attribute storedMetadata : WstxProfileRecordings::RecordingMetadata[*];
        attribute storedManifests : WstxProfileRecordings::RecordingManifest[*];
        doc /* Validated profile-owned recording, selected by identity rather than arbitrary
             client paths. No live audio device is required for this input. */
        port upload : ~RecordingTransfer;
        port samples : ReceiveSamples;
    }
    part def ReceivePipeline {
        doc /* Own sample-window handling, normalization/resampling and bounded jobs/spectrum; not file dialogs, HTTP, CAT or UI rendering. PCM-unit mapping is not gain control and native conversion has one owner. */
        doc /* One shared native-format/rate conversion owner feeds canonical samples;
             no source-specific modem resamplers. PCM unit mapping differs from AGC
             and modem normalization. WstxRecordingReceive owns recorded spectrum,
             shared RustFFT 6.4.1 ordering/scaling and buffer obligations;
             WstxModemDecode owns mode window/history/decoder quanta and independent
             vectors; WstxRadioIO owns live adapter/conversion semantics. */
        port jobs : ~StationOperations;
        port audio : ~ReceiveSamples;
        port processing : ReceiveProcessing;
    }
    part def ModeFunctions {
        attribute currentReceiveSettings : WstxOfflineDecode::Settings[0..1];
        attribute intendedModeCapabilities : WstxProductScope::ModeCapability[*];
        doc /* Pure protocol/symbol/waveform and decoding calculations with independent vectors; no filesystem/hardware/network/wall-clock dependency. */
        doc /* Pure receive calculations and encoding/waveform generation depend on no
             device, filesystem, wall-clock or network. WstxModemDecode and
             WstxOfflineDecode own concrete mode contracts and status; hardware format
             adaptation and common rate conversion remain outside this boundary. */
        port receive : ~ReceiveProcessing;
        port encode : ~EncodeProcessing;
    }
    part def TransmitService {
        doc /* Own UTC scheduling, transmit state, audio/PTT coordination and priority halt; no browser timer or visualization-queue dependency. Defaults UNARMED on startup. Halt never waits for decode, receive cancellation or congestion. Backend/device loss and authority-expiry policy are settled before hardware TX and cannot be replaced in MCP. */
        doc /* UTC scheduling, operation authority and audio/PTT coordination reuse the
             common resource context. WstxProductScope::TransmitSafetyPolicy owns
             unresolved deadlines/backend-loss/expiry policy before hardware TX;
             WstxProductScope::ProcessingAndHaltOwnership separates priority halt from
             receive completion/cancellation and optional display congestion. */
        port operations : ~StationOperations;
        port contacts : ~StationOperations;
        port encode : EncodeProcessing;
        port audio : AudioExchange;
        port control : RadioControl;
        doc /* contacts receives QsoAndLogging's arm/disarm, TransmitRequest and halt
             requests and returns TransmitOutcome (WstxTransmit #9 slice B consumer
             contract, target). It is the only RF path of the contact workflow. */
    }
    part def QsoAndLogging {
        doc /* Own exchange/completion/cancel and durable contacts; never bypass transmit authority or another profile storage. Stable completion identity and explicit persisted/unsaved outcome prevent silent duplicate contacts when completion replays. Concrete log schema/compatibility remains a target decision. */
        port operations : ~StationOperations;
        port contacts : ProfileAccess;
        port transmit : StationOperations;
        doc /* transmit carries contact transmissions only to TransmitService (WstxContact);
             no PTT, audio or radio port exists here. */
    }
    part def AudioInterface {
        attribute configuredIntent : WstxAudio::DeviceIntent;
        attribute observedState : WstxAudio::AudioState;
        attribute observedNativeFormat : WstxAudio::NativeFormat[0..1];
        attribute observedNativeRateHz : Integer[0..1];
        attribute observedNativeChannels : Integer[0..1];
        attribute observedNativeEndpointId : String[0..1];
        doc /* Own sources/sinks, device/channel sample movement, metadata and device failures. No CAT/PTT, mode decoding or QSO decisions. CAT-disabled audio and control without an open audio device remain independent. */
        doc /* Independent samples, timing and failures; CAT-disabled live input and stored
             recordings use the same receive boundary. Does not issue control commands. */
        port status : AudioStatus;
        port recorded : ~ReceiveSamples;
        port receive : ReceiveSamples;
        port transmit : ~AudioExchange;
        port backend : AudioExchange;
    }
    part def RadioControlInterface {
        attribute configuredIntent : WstxProfiles::ControlSelection;
        attribute observedState : WstxRadioIO::CatState;
        attribute currentFacts : WstxRadioFacts::RadioFacts[0..1];
        attribute frequencyProvenance : WstxRadioFacts::FactProvenance;
        attribute modeProvenance : WstxRadioFacts::FactProvenance;
        attribute dataProvenance : WstxRadioFacts::FactProvenance;
        doc /* Own selected capabilities, typed CAT/control/PTT/status/resource claims; not audio samples/sound devices, browser/MCP policy or duplicate modem logic. */
        doc /* Capabilities, CAT/PTT/status, independent failures and resource claims. No
             samples; control implementation coverage does not limit physical radio capabilities. */
        port station : ~RadioControl;
        port transmit : ~RadioControl;
        port backend : RadioControl;
    }
    part def AudioDeviceAdapter {
        port host : ~AudioExchange;
    }
    part def RustRadioDriver {
        attribute connectionSettings : WstxProfiles::ControlSelection;
        attribute observed : WstxRadioIO::RadioObservation[0..1];
        port authorized : ~RadioControl;
    }
    part def StationProcess {
        part profile : PersistedProfile;
        part station : StationService;
        part web : WebAdapter;
        part mcp : McpAdapter;
        part receive : ReceivePipeline;
        part modes : ModeFunctions;
        part audio : AudioInterface;
        part radioControl : RadioControlInterface;
        part transmit : TransmitService;
        part qso : QsoAndLogging;
        part radioBinding : RadioBinding;
        ref part authority : RadioAuthority :> physicalStation.backend.radioAuthority;
        port authorityRequest : RadioControl;
        port authorizedControl : ~RadioControl;
        doc /* Phase 1 radio-facing parts are independent audio and CAT adapters.
             Logical driver existence does not assert connected control or ready TX.
             FR-023 native Flex runs as a per-station session behind these same audio
             and control boundaries (WstxFlexSession::NativeFlexWireSubset); it adds
             no part, combined backend or common connector to this graph. */
        part audioAdapter : AudioDeviceAdapter;
        part catAdapter : RustRadioDriver;
        connection webOperations connect web.station to station.webOperations;
        connection mcpOperations connect mcp.station to station.mcpOperations;
        connection profileContext connect station.profile to profile.context;
        connection receiveJobs connect station.receive to receive.jobs;
        connection transmitOperations connect station.transmit to transmit.operations;
        connection qsoOperations connect station.qso to qso.operations;
        connection stationControl connect station.control to radioControl.station;
        connection receiveSamples connect audio.receive to receive.audio;
        connection audioAvailability connect audio.status to station.audioStatus;
        connection receiveModem connect receive.processing to modes.receive;
        connection encodeModem connect transmit.encode to modes.encode;
        connection transmitAudio connect transmit.audio to audio.transmit;
        connection transmitControl connect transmit.control to radioControl.transmit;
        connection uploadedRecording connect web.recording to station.upload;
        connection validatedRecording connect station.acceptedRecording to profile.upload;
        connection recordedInput connect profile.recordedSamples to audio.recorded;
        connection contactStorage connect qso.contacts to profile.contacts;
        connection contactTransmit connect qso.transmit to transmit.contacts;
        connection selectedAudio connect audio.backend to audioAdapter.host;
        connection authorityRequestDelegation connect radioControl.backend to authorityRequest;
        connection authorizedControlDelegation connect authorizedControl to catAdapter.authorized;
        connection commonAuthority connect authorityRequest to authority.requests;
        connection authorizedBackend connect authority.authorized to authorizedControl;
        binding requestContext bind authorityRequest.request.resourceContext = radioBinding;
        binding catContext bind catAdapter.authorized.request.resourceContext = radioBinding;
    }

    dependency audioPromise from AudioInterface to WstxRequirements::'FR-002';
    dependency controlPromise from RadioControlInterface to WstxRequirements::'FR-009';
    dependency profilesPromise from PersistedProfile to WstxRequirements::'FR-022';
    doc /* Responsibility traces identify the owning boundary for an existing requirement,
         not delivered capability or an executed verification. */
    dependency configurationPromise from StationService to WstxRequirements::'FR-001';
    dependency receivePromise from ReceivePipeline to WstxRequirements::'FR-003';
    dependency decodePromise from ModeFunctions to WstxRequirements::'FR-004';
    dependency encodePromise from ModeFunctions to WstxRequirements::'FR-005';
    dependency timingPromise from TransmitService to WstxRequirements::'FR-006';
    dependency receiveTimingPromise from ReceivePipeline to WstxRequirements::'FR-006';
    dependency qsoPromise from QsoAndLogging to WstxRequirements::'FR-007';
    dependency haltPromise from TransmitService to WstxRequirements::'FR-008';
    dependency displayPromise from BrowserClient to WstxRequirements::'FR-010';
    dependency loggingPromise from QsoAndLogging to WstxRequirements::'FR-011';
    dependency integrationPromise from StationService to WstxRequirements::'FR-012';
    dependency emePromise from ModeFunctions to WstxRequirements::'FR-013';
    dependency widebandPromise from ReceivePipeline to WstxRequirements::'FR-014';
    dependency utilitiesPromise from ModeFunctions to WstxRequirements::'FR-015';
    dependency persistencePromise from PersistedProfile to WstxRequirements::'FR-016';
    dependency helpPromise from BrowserClient to WstxRequirements::'FR-017';
    dependency recordingPromise from RecordedSource to WstxRequirements::'FR-018';
    dependency htmlPromise from WebAdapter to WstxRequirements::'FR-019';
    dependency mcpPromise from McpAdapter to WstxRequirements::'FR-020';
    dependency linkPromise from BrowserAttachment to WstxRequirements::'FR-021';
    package ImplementedStatusSlice {
        doc /* Implemented status/TLS subset alongside WstxProfiles profile functionality.
             The target deployment does not assert full radio/modem or MCP delivery;
             detailed coverage remains in WstxRequirements and the owning packages. */
        part def StatusServer;
        dependency statusScope from StatusServer to WstxStationProtocol::'CL-003-01';
        dependency statusProtocol from StatusServer to WstxStationProtocol::'CL-003-02';
    }
    dependency coordinatedReceivePromise from ReceivePipeline to WstxRequirements::'CL-008-07';
    doc /* WstxOperatingReceive refines coordinated receive controls on the existing
         receive and radio authority path: single-owner release/setup/readback/restart
         and cancellation fences. It introduces no additional station/backend/physical
         connector, sample source or deployment. */
}
