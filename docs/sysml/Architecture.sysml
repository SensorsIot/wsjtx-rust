package WstxArchitecture {
    private import ScalarValues::*;
    doc /* Product structure: one selected-radio deployment context, its four deployment
         participants, software owners and typed exchanges. The frontend may run locally
         on the backend computer or remotely over the station link; the logical
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
         WstxRecordingReceive, WstxOfflineDecode, WstxRadioIO,
         WstxOperatingLayout and WstxOperatingReceive. */

    part physicalStation {
        doc /* One selected-radio reference context with user, frontend, backend and radio
             roles. Frontend/backend roles may share a computer. This is not universal
             radio cardinality or a radio count derived from station count. */
        part user : User;
        part frontend : Frontend;
        part backend : Backend;
        part radio : Radio;
        part browserAttachments[*] : BrowserAttachment;
        part radioAudioAttachments[*] : RadioAudioAttachment;
        part radioControlAttachments[*] : RadioControlAttachment;
    }
    view physicalInterconnection : StandardViewDefinitions::InterconnectionView {
        expose physicalStation::*;
    }

    doc /* Radio properties describe semantic controls and observations a physical model
         can expose. Every optional field is model/context-dependent: absence means no
         value is supplied, not zero, false, unsupported or a universal default. Capability
         observations determine supported choices and read/write availability for the
         selected model, firmware, VFO, antenna and mode. Names are public meanings,
         never driver keywords, protocol codes or SysML enum ordinal encodings.
         RF modes such as USB/LSB are distinct from FT4/FT8 signal modem selection.
         Requested settings never become confirmed state merely by being submitted.
         Existing resource authority, safety and readback contracts remain binding. */

    enum def RadioPttState { enum off; enum on; enum microphoneOnly; enum dataOnly; }
    enum def RadioPowerState { enum off; enum on; enum standby; }
    enum def RepeaterShift { enum simplex; enum negative; enum positive; }
    enum def BreakInMode { enum off; enum semi; enum full; }
    enum def RadioResultStatus { enum confirmed; enum unavailable; enum unsupported; enum rejected; enum failed; }

    attribute def FrequencyRange {
        attribute lowerHz : Real;
        attribute upperHz : Real;
    }
    attribute def VfoSelection {
        attribute role : String[0..1];
        attribute selector : String[0..1];
        doc /* Semantic role (for example A/B/main/sub/memory) and model-specific named
             selector identify the VFO; neither is a packed integer or protocol address. */
    }
    attribute def SplitSelection {
        attribute enabled : Boolean[0..1];
        attribute receiveVfo : VfoSelection[0..1];
        attribute transmitVfo : VfoSelection[0..1];
    }
    attribute def AntennaSelection {
        attribute receiveAntenna : String[0..1];
        attribute transmitAntenna : String[0..1];
    }
    attribute def RadioTuningSettings {
        attribute vfo : VfoSelection[0..1];
        attribute frequencyHz : Real[0..1];
        attribute rfMode : String[0..1];
        attribute receiverFilterHz : Real[0..1];
        attribute filterSelection : String[0..1];
        attribute tuningStepHz : Real[0..1];
        attribute split : SplitSelection[0..1];
        attribute transmitFrequencyHz : Real[0..1];
        attribute transmitRfMode : String[0..1];
        attribute transmitFilterHz : Real[0..1];
        attribute ritEnabled : Boolean[0..1];
        attribute ritOffsetHz : Real[0..1];
        attribute xitEnabled : Boolean[0..1];
        attribute xitOffsetHz : Real[0..1];
        attribute repeaterShift : RepeaterShift[0..1];
        attribute repeaterOffsetHz : Real[0..1];
        attribute antennas : AntennaSelection[0..1];
        attribute tuningLocked : Boolean[0..1];
        attribute satelliteMode : Boolean[0..1];
        attribute dualWatch : Boolean[0..1];
        attribute diversity : Boolean[0..1];
        doc /* Width is an independently known physical filter bandwidth in Hz. A named
             filter alone supplies no width. Each frequency/mode is contextual to its
             selected VFO; split is a compound RX/TX selection, not one flag/number. */
    }
    attribute def RadioTransmitterSettings {
        attribute ptt : RadioPttState[0..1];
        attribute powerState : RadioPowerState[0..1];
        attribute outputPowerW : Real[0..1];
        attribute outputPowerFraction : Real[0..1];
        attribute microphoneGainFraction : Real[0..1];
        attribute compressionEnabled : Boolean[0..1];
        attribute compressionFraction : Real[0..1];
        attribute voxEnabled : Boolean[0..1];
        attribute voxGainFraction : Real[0..1];
        attribute antiVoxFraction : Real[0..1];
        attribute voxDelaySeconds : Real[0..1];
        attribute tunerEnabled : Boolean[0..1];
        doc /* Fraction quantities are dimensionless normalized levels where the model
             supports them; watts are not inferred from a fractional power setting.
             Exposing PTT does not grant transmission authority. */
    }
    attribute def RadioReceiverSettings {
        attribute rfGainFraction : Real[0..1];
        attribute squelchFraction : Real[0..1];
        attribute squelchEnabled : Boolean[0..1];
        attribute preamplifierDb : Real[0..1];
        attribute attenuationDb : Real[0..1];
        attribute agcMode : String[0..1];
        attribute agcTimeSeconds : Real[0..1];
        attribute noiseBlankerMode : String[0..1];
        attribute noiseBlankerFraction : Real[0..1];
        attribute noiseReductionMode : String[0..1];
        attribute noiseReductionFraction : Real[0..1];
        attribute automaticNotchEnabled : Boolean[0..1];
        attribute manualNotchEnabled : Boolean[0..1];
        attribute notchFrequencyHz : Real[0..1];
        attribute ifShiftHz : Real[0..1];
        attribute passbandInnerFraction : Real[0..1];
        attribute passbandOuterFraction : Real[0..1];
        attribute filterSlopeLow : String[0..1];
        attribute filterSlopeHigh : String[0..1];
        attribute audioPeakFilterEnabled : Boolean[0..1];
        attribute audioPeakFilterFraction : Real[0..1];
        attribute automaticFrequencyControl : Boolean[0..1];
        doc /* AGC, blanker, reduction and slope choices retain model-specific named
             multivalued states. They are not flattened into universal Boolean switches.
             Fractional controls carry no inferred conversion to dB, Hz or seconds. */
    }
    attribute def RadioAudioSettings {
        attribute afGainFraction : Real[0..1];
        attribute balanceFraction : Real[0..1];
        attribute muted : Boolean[0..1];
        attribute monitorEnabled : Boolean[0..1];
        attribute monitorGainFraction : Real[0..1];
        attribute usbOutputGainFraction : Real[0..1];
        attribute usbInputGainFraction : Real[0..1];
        attribute inputSource : String[0..1];
        attribute outputSource : String[0..1];
    }
    attribute def RadioKeyerSettings {
        attribute speedWordsPerMinute : Real[0..1];
        attribute pitchHz : Real[0..1];
        attribute keyerType : String[0..1];
        attribute breakIn : BreakInMode[0..1];
        attribute breakInDelaySeconds : Real[0..1];
    }
    attribute def RadioToneSettings {
        attribute ctcssToneHz : Real[0..1];
        attribute ctcssSquelchToneHz : Real[0..1];
        attribute ctcssEnabled : Boolean[0..1];
        attribute ctcssSquelchEnabled : Boolean[0..1];
        attribute dcsCode : String[0..1];
        attribute dcsSquelchCode : String[0..1];
        attribute dcsEnabled : Boolean[0..1];
        attribute dcsSquelchEnabled : Boolean[0..1];
        attribute toneBurstEnabled : Boolean[0..1];
        doc /* Tone frequencies use Hz, DCS values use named codes with leading zeroes
             preserved; no raw tenths-of-Hz or packed protocol representation. */
    }
    attribute def RadioScopeSettings {
        attribute scopeId : String[0..1];
        attribute enabled : Boolean[0..1];
        attribute held : Boolean[0..1];
        attribute mode : String[0..1];
        attribute radioScopeHz : FrequencyRange[0..1];
        attribute spanHz : Real[0..1];
        attribute referenceLevelDb : Real[0..1];
        attribute attenuationDb : Real[0..1];
        attribute averagingMode : String[0..1];
        attribute speed : String[0..1];
        doc /* This is the radio's physical spectrum scope. Its Hz range/span is
             independent of receiverFilterHz and frontend browserWaterfallSpanHz. */
    }
    attribute def RadioSettings {
        attribute tuning : RadioTuningSettings[0..1];
        attribute transmitter : RadioTransmitterSettings[0..1];
        attribute receiver : RadioReceiverSettings[0..1];
        attribute audio : RadioAudioSettings[0..1];
        attribute keyer : RadioKeyerSettings[0..1];
        attribute tones : RadioToneSettings[0..1];
        attribute scope : RadioScopeSettings[0..1];
        doc /* Only writable control groups; for applySettings, supplied members express
             requested changes and absent members express no requested change. A model
             may expose any member read-only; such writes must be rejected. */
    }
    attribute def RadioMeters {
        attribute signalStrengthDbm : Real[0..1];
        attribute signalStrengthDbRelativeS9 : Real[0..1];
        attribute standingWaveRatio : Real[0..1];
        attribute alcFraction : Real[0..1];
        attribute compressionDb : Real[0..1];
        attribute forwardPowerW : Real[0..1];
        attribute reflectedPowerW : Real[0..1];
        attribute drainCurrentA : Real[0..1];
        attribute supplyVoltageV : Real[0..1];
        attribute temperatureCelsius : Real[0..1];
        attribute batteryFraction : Real[0..1];
        attribute carrierDetected : Boolean[0..1];
        attribute overflowDetected : Boolean[0..1];
        doc /* Read-only physical measurements. Units are explicit; no raw meter counts
             or unverified calibration conversion is supplied. */
    }
    attribute def RadioSpectrum {
        attribute scopeId : String;
        attribute frequenciesHz : Real[*];
        attribute levels : Real[*];
        attribute levelUnit : String;
        doc /* Observed spectrum samples pair frequency and level by position. The
             radio supplies the level unit (for example dBm); no universal calibration
             is assumed. This is not a sample transport frame or buffer layout. */
    }
    attribute def RadioCapabilities {
        attribute receiveRangesHz : FrequencyRange[*];
        attribute transmitRangesHz : FrequencyRange[*];
        attribute rfModes : String[*];
        attribute vfoSelectors : String[*];
        attribute antennaNames : String[*];
        attribute receiverFilterWidthsHz : Real[*];
        attribute filterNames : String[*];
        attribute tuningStepsHz : Real[*];
        attribute agcModes : String[*];
        attribute noiseBlankerModes : String[*];
        attribute noiseReductionModes : String[*];
        attribute keyerTypes : String[*];
        attribute scopeModes : String[*];
        attribute scopeAveragingModes : String[*];
        attribute ctcssTonesHz : Real[*];
        attribute dcsCodes : String[*];
        attribute splitAvailable : Boolean[0..1];
        attribute pttStates : RadioPttState[*];
        attribute powerStates : RadioPowerState[*];
        attribute audioInputSources : String[*];
        attribute audioOutputSources : String[*];
        doc /* Sparse capability observations for this model/context, not an exhaustive
             vendor catalogue or runtime driver support claim. Empty lists mean no
             choices supplied. Range/mode/filter relationships stay contextual; these
             lists do not assert all combinations valid or grant writable access. */
    }
    attribute def RadioState {
        attribute controls : RadioSettings[0..1];
        attribute meters : RadioMeters[0..1];
        attribute spectrum : RadioSpectrum[0..1];
        doc /* Observations only; the controls record reports actual readable settings,
             including read-only members. It is distinct from requested settings. */
    }

    requirement PhysicalDeploymentStructure {
        doc /* Architectural refinement of the existing deployment scope: the model MUST
             contain the user/frontend/backend/radio context. Frontend and Backend are
             pure deployment containers without forwarding ports or functional policy.
             Operator and station exchanges MUST connect selected functional endpoints
             directly, retaining profile-scoped browser/station selection. Separate audio
             and control paths MUST connect the selected radio adapter and radio.
             Variable browser and station populations MUST NOT become a fixed station
             count, all-to-all routing, or an additional detached deployment. */
    }
    requirement StationResourceIdentity {
        doc /* Architectural refinement of WstxProfiles and
             WstxProductScope::NativeFlexBoundary: each station MUST compose one profile,
             one selected radio-adapter variation and one selected-radio binding, and
             reference the common authority contained in Backend. All control requests
             and outcomes MUST retain request/resource identity through that authority
             to the selected radio adapter. A radio adapter or native session MUST NOT
             introduce an authority bypass. */
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
             population/reference subsets, backend alternatives and identity bindings
             in the existing architecture integrity oracle, not candidate-derived counts.
             Expect user-to-selected-browser and selected-browser-to-web/station direct
             connections through portless associations; frontend/backend containers MUST
             have no forwarding ports. Expect separate selected-radio-adapter-to-radio
             audio/control paths; upload-to-profile-to-receive,
             receive-to-mode and encode-to-mode paths; exactly one effective authority
             whose bound request/outcome and resource context reach that same radio adapter.
             Missing direct browser/encode connections, added container forwarding ports,
             reversed provider/waveform direction, wrong item kind, redirected association
             or context, weakened identity binding, split or bypassed authority, duplicate backend, detached stations and view-created
             structure MUST be rejected even if legal SysML. Four deployment participants
             and three portless association populations retain selected endpoint identity;
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
    dependency radioPropertyOwnership from physicalStation::radio to RadioModelReferenceSeparation;

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
             companions; this declaration records no review or runtime verdict. */
        attribute method : String = "manual independent public-property and interface correspondence review";
        attribute executionStatus : String = "planned; semantic resolution does not establish review or runtime acceptance";
    }

    item def OperatorRequest;
    item def Presentation;
    item def StationRequest;
    item def StationOutcome;
    item def Recording;
    item def SampleBlock {
        doc /* Immutable recorded and live samples feed the same receive boundary.
             WstxRecordingReceive::SampleBlock owns concrete recorded element units,
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
    doc /* Radio-adapter-to-radio public signatures carried by the existing RadioControl
         request/outcome items, through the selected binding and common authority:
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
        doc /* WstxRecordingReceive::SpectrumFrame owns spectrum units, identity,
             bounds and replaceable display delivery. WstxOfflineDecode::ResultRecord
             and ResultPage own mode payloads and required result delivery/retention.
             These have different delivery obligations despite sharing processing. */
    }
    item def EncodeRequest;
    item def Waveform;
    item def ProfileRequest;
    item def ProfileOutcome;
    item def NativeSessionOperation;
    item def NativeSessionOutcome;

    port def LocalInteraction {
        out item request : OperatorRequest;
        in item presentation : Presentation;
    }
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
    port def SessionAccess {
        out item operation : NativeSessionOperation;
        in item outcome : NativeSessionOutcome;
    }

    part def User { port interaction : LocalInteraction; }
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
        port operator : ~LocalInteraction;
        port station : BrowserExchange;
    }
    part def McpClient { port station : StationOperations; }
    part def Frontend {
        doc /* Deployment container only; interaction and station exchanges terminate
             directly on selected contained BrowserClient instances. */
        part browsers[*] : BrowserClient;
    }
    part def Radio {
        attribute modelId : String[0..1];
        attribute physicalIdentity : String[0..1];
        attribute capabilities : RadioCapabilities[0..1];
        attribute observedState : RadioState[0..1];
        doc /* Physical model identity and sparse exposed facts are navigable from the
             selected radio. No catalogue/driver-management service is implied. Observed
             controls, meters and scope remain distinct from requested settings. */
        port audio : ~AudioExchange;
        port control : ~RadioControl;
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
        ref part mcpClients[*] : McpClient;
        doc /* MCP clients are referenced, not deployed onto this computer by composition.
             Backend attachments own routing associations only. Client placement and
             detailed authority remain unresolved before MCP implementation. */
        part radioAuthority : RadioAuthority;

        part mcpAttachments[*] : McpAttachment;

    }
    part def BrowserAttachment {
        doc /* One profile-scoped browser/station association carried by the physical IP
             link. This portless association selects one browser and one station, never
             the whole population. User interaction terminates on that same browser;
             the station exchange terminates directly on the selected WebAdapter. */
        ref part browser : BrowserClient :> physicalStation.frontend.browsers;
        ref part station : StationProcess :> physicalStation.backend.stations;
        connection localInteraction connect physicalStation.user.interaction to browser.operator;
        connection browserStation connect browser.station to station.web.client;
    }
    part def McpAttachment {
        ref part client : McpClient :> physicalStation.backend.mcpClients;
        ref part station : StationProcess :> physicalStation.backend.stations;
        connection mcpClientOperations connect client.station to station.mcp.client;
    }
    part def RadioBinding {
        doc /* Persisted intent resolves the selected physical radio/resource at connection.
             WstxProductScope::NativeFlexBoundary leaves native slice/handle schema
             and actual radio capacity as implementation prerequisites. */
        ref part radio : Radio :> physicalStation.radio;
    }
    part def RadioAudioAttachment {
        ref part station : StationProcess :> physicalStation.backend.stations;
        connection audioDelegation connect station.radioAdapter.radioAudio to station.radioBinding.radio.audio;
    }
    part def RadioControlAttachment {
        ref part station : StationProcess :> physicalStation.backend.stations;
        connection controlDelegation connect station.radioAdapter.radioControl to station.radioBinding.radio.control;
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
        attribute privateRuntimeInputs : WstxProfiles::RuntimeInputs;
        attribute effectiveEndpoint : WstxStationProtocol::EndpointPolicy;
        doc /* Runtime inputs and effective transport/authentication settings are distinct
             from saved endpoint intent. No credential values are instantiated here. */
        doc /* Own embedded client, HTTP/file transfer/versioned WebSocket, transport authentication and Origin checks; no second QSO/modem engine or direct radio writes. */
        doc /* WstxStationProtocol owns shared authentication, Origin and HTTP/WebSocket
             semantics. WstxOperatingReceive::HttpContentCodingBoundary refines bounded
             GET coding after handler/auth/errors/caps, with one dispatch and unchanged
             JSON/WebSocket identity; it creates no second transport authority. */
        port client : ~BrowserExchange;
        port station : StationOperations;
        port recording : RecordingTransfer;
    }
    part def McpAdapter {
        doc /* Own protocol validation/caller context and configured station-selection/automation requests. No independent station state, backend access or separate transmit permission; same station operations and safety policy as browser. */
        port client : ~StationOperations;
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
        attribute storedMetadata : WstxRecordingReceive::RecordingMetadata[*];
        attribute storedManifests : WstxRecordingReceive::RecordingManifest[*];
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
             WstxOfflineDecode owns mode window/history/decoder quanta and independent
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
             device, filesystem, wall-clock or network. WstxOfflineDecode owns concrete
             mode contracts and status; hardware format adaptation and common rate
             conversion remain outside this boundary. */
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
        port encode : EncodeProcessing;
        port audio : AudioExchange;
        port control : RadioControl;
    }
    part def QsoAndLogging {
        doc /* Own exchange/completion/cancel and durable contacts; never bypass transmit authority or another profile storage. Stable completion identity and explicit persisted/unsaved outcome prevent silent duplicate contacts when completion replays. Concrete log schema/compatibility remains a target decision. */
        port operations : ~StationOperations;
        port contacts : ProfileAccess;
    }
    part def AudioInterface {
        attribute configuredIntent : WstxRadioIO::DeviceIntent;
        attribute observedState : WstxRadioIO::AudioState;
        attribute observedNativeFormat : WstxRadioIO::NativeFormat[0..1];
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
        attribute currentFacts : WstxOperatingReceive::RadioFacts[0..1];
        attribute frequencyProvenance : WstxOperatingReceive::FactProvenance;
        attribute modeProvenance : WstxOperatingReceive::FactProvenance;
        attribute dataProvenance : WstxOperatingReceive::FactProvenance;
        doc /* Own selected capabilities, typed CAT/control/PTT/status/resource claims; not audio samples/sound devices, browser/MCP policy or duplicate modem logic. */
        doc /* Capabilities, CAT/PTT/status, independent failures and resource claims. No
             samples; control implementation coverage does not limit physical radio capabilities. */
        port station : ~RadioControl;
        port transmit : ~RadioControl;
        port backend : RadioControl;
    }
    part def AudioDeviceAdapter {
        port host : ~AudioExchange;
        port radio : AudioExchange;
    }
    part def RustRadioDriver {
        attribute connectionSettings : WstxProfiles::ControlSelection;
        attribute observed : WstxRadioIO::RadioObservation[0..1];
        port authorized : ~RadioControl;
        port radio : RadioControl;
    }
    abstract part def RadioBackend {
        port audio : ~AudioExchange;
        port control : ~RadioControl;
        port radioAudio : AudioExchange;
        port radioControl : RadioControl;
    }
    part def StandardBackend :> RadioBackend {
        doc /* Standard selected audio devices and optional CAT/PTT capabilities. Logical
             driver existence does not assert connected/available control or ready TX. */
        part audioDevices : AudioDeviceAdapter;
        part controlDriver : RustRadioDriver;
        connection audioHost connect audio to audioDevices.host;
        connection audioRadio connect audioDevices.radio to radioAudio;
        connection controlHost connect control to controlDriver.authorized;
        connection controlRadio connect controlDriver.radio to radioControl;
    }
    part def NativeAudio :> AudioDeviceAdapter { port session : SessionAccess; }
    part def NativeControl :> RustRadioDriver { port session : SessionAccess; }
    part def NativeSession {
        doc /* A managed native session may serve audio and control. It is not a second
             arbitration authority. WstxProductScope::NativeFlexBoundary leaves session
             ownership/sharing/lifetime unresolved; this provider type does not require
             a separate session per station. */
        port audio : ~SessionAccess;
        port control : ~SessionAccess;
    }
    part def NativeBackend :> RadioBackend {
        doc /* Optional Phase 2 alternate without external SmartSDR/CAT/DAX bridges.
             Logical associations select no native API schema or physical streams.
             The session is referenced, not composed by this backend. Required
             ownership/sharing/lifetime decisions in WstxProductScope::NativeFlexBoundary
             remain prerequisites; this alternative does not assert full native delivery. */
        part audioDevices : NativeAudio;
        part controlDriver : NativeControl;
        ref part session : NativeSession;
        connection audioHost connect audio to audioDevices.host;
        connection audioRadio connect audioDevices.radio to radioAudio;
        connection controlHost connect control to controlDriver.authorized;
        connection controlRadio connect controlDriver.radio to radioControl;
        connection audioSession connect audioDevices.session to session.audio;
        connection controlSession connect controlDriver.session to session.control;
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
        variation part radioAdapter : RadioBackend {
            doc /* Exactly one backend selection per station; alternatives are not concurrent
                 instances. Cardinality/selection are structural review obligations. */
            variant part standardDevices : StandardBackend;
            variant part nativeFlex : NativeBackend;
        }
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
        connection selectedAudio connect audio.backend to radioAdapter.audio;
        connection authorityRequestDelegation connect radioControl.backend to authorityRequest;
        connection authorizedControlDelegation connect authorizedControl to radioAdapter.control;
        connection commonAuthority connect authorityRequest to authority.requests;
        connection authorizedBackend connect authority.authorized to authorizedControl;
        binding requestContext bind authorityRequest.request.resourceContext = radioBinding;
        binding backendContext bind radioAdapter.control.request.resourceContext = radioBinding;
    }

    dependency audioPromise from AudioInterface to WstxRequirements::'FR-002';
    dependency controlPromise from RadioControlInterface to WstxRequirements::'FR-009';
    dependency profilesPromise from PersistedProfile to WstxRequirements::'FR-022';
    dependency flexPromise from NativeBackend to WstxRequirements::'FR-023';
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
        dependency statusScope from StatusServer to WstxRequirements::'CL-003-01';
        dependency statusProtocol from StatusServer to WstxRequirements::'CL-003-02';
    }
    dependency coordinatedReceivePromise from ReceivePipeline to WstxRequirements::'CL-008-07';
    doc /* WstxOperatingReceive refines coordinated receive controls on the existing
         receive and radio authority path: single-owner release/setup/readback/restart
         and cancellation fences. It introduces no additional station/backend/physical
         connector, sample source or deployment. */
}
