package WstxArchitecture {
    private import ScalarValues::*;
    doc /* Product structure: one selected-radio deployment context, its four physical
         participants, software owners and typed exchanges. The viewer may run locally
         on the controller computer or remotely over the station link; the logical
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
        doc /* One selected-radio reference context with user, viewer, controller and radio
             roles. Viewer/controller roles may share a computer. This is not universal
             radio cardinality or a radio count derived from station count. */
        part user : Operator;
        part viewer : ViewerComputer;
        part controller : StationControllerComputer;
        part radio : Radio;
        connection localInteraction connect user.interaction to viewer.operator;
        connection stationLink connect viewer.stationLink to controller.viewerLink {
            part attachments[*] : BrowserAttachment;
        }
        connection radioAudio connect controller.radioAudio to radio.audio {
            part channels[*] : RadioAudioAttachment;
        }
        connection radioControl connect controller.radioControl to radio.control {
            part channels[*] : RadioControlAttachment;
        }
    }
    view physicalInterconnection : StandardViewDefinitions::InterconnectionView {
        expose physicalStation::*;
    }


    doc /* Component attributes below are owned views/usages of canonical property
         definitions. Their inherited defaults/ranges do not create a second settings
         schema. Contract limits and algorithm parameters are read-only obligations,
         not additional operator controls. Optional observed values remain unknown
         until measured; requested values and catalogue claims never confirm them.
         Model metadata contains no real token, key, device selection or station UUID. */

    attribute def ParsedCatConfiguration {
        doc /* Derived view of the existing profile control endpoint, not new persisted
             fields. server/src/radio_control/mod.rs::Configuration owns the current
             parser: COM1..256, Auto or the listed fixed baud rates, distinct CI-V
             addresses 01..EF. Plain COM means Auto/radio94/controllerE0 in hexadecimal.
             Transport is 8N1/no handshake; DTR/RTS disabled only after the verified
             receive-only precondition. No retry/replay or additional CAT operation. */
        attribute port : Integer;
        attribute fixedBaud : Integer[0..1];
        attribute radioAddress : Integer;
        attribute controllerAddress : Integer;
        assert constraint validPort { port >= 1 and port <= 256 }
        assert constraint validBaud {
            fixedBaud == null or fixedBaud == 4800 or fixedBaud == 9600 or
            fixedBaud == 19200 or fixedBaud == 38400 or fixedBaud == 57600 or fixedBaud == 115200
        }
        assert constraint validAddresses {
            radioAddress >= 1 and radioAddress <= 239 and
            controllerAddress >= 1 and controllerAddress <= 239 and radioAddress != controllerAddress
        }
    }
    attribute def DisplayGeometry {
        doc /* Fixed browser presentation from WstxRecordingReceive spectrum rendering
             and WstxOperatingLayout::SplitGeometry: half-open Hz span, no frequency
             scrolling, curve:waterfall height ratio and ruler spacing. Native bin,
             row, FFT, interval and delivery limits remain WstxRecordingReceive::Limits.
             These values are not physical receiver bandwidth or CAT FIL identifiers. */
        attribute lowerHz : Integer = 0;
        attribute upperExclusiveHz : Integer = 3000;
        attribute frequencyScrolling : Boolean = false;
        attribute curveHeightUnits : Integer = 1;
        attribute waterfallHeightUnits : Integer = 5;
        attribute majorRulerHz : Integer = 500;
        attribute minorRulerHz : Integer = 100;
    }
    attribute def ConversionContract {
        doc /* Read-only live conversion properties from WstxRadioIO::ConvertAndReceive.
             One FIR owner, no AGC; sample counts, packet/queue/latency/memory bounds
             remain WstxRadioIO::Limits. Window advances follow the selected mode;
             none is a physical radio filter or user-set decoder search range. */
        attribute passbandLowerHz : Integer = 0;
        attribute passbandUpperHz : Integer = 3500;
        attribute passbandToleranceDb : Real = 0.1;
        attribute stopbandFromHz : Integer = 5500;
        attribute minimumStopbandAttenuationDb : Integer = 60;
        attribute usesAgc : Boolean = false;
        attribute ft8WindowSeconds : Real = 30.0;
        attribute ft8AdvanceSeconds : Real = 15.0;
        attribute ft4WindowSeconds : Real = 15.0;
        attribute ft4AdvanceSeconds : Real = 7.5;
    }

    enum def RadioPropertyValueKind {
        enum booleanValue; enum integerValue; enum realValue; enum textValue;
        enum enumValue; enum setValue; enum bitmaskValue; enum listValue;
        enum recordValue; enum bytesValue;
    }
    enum def RadioPropertyGroup {
        enum identityAndProvenance; enum connectionAndTransport; enum frequencyModeAndPassband;
        enum vfoAndSplit; enum offsetsRepeaterAndSignalling; enum antennaAndRouting;
        enum functionsLevelsAndParameters; enum memoryAndChannels; enum scanAndVfoOperations;
        enum messagingPowerResetAndClock; enum asynchronousStateAndSpectrum;
        enum audioAndIq; enum vendorExtension;
    }
    attribute def RadioReferenceSource {
        attribute id : String;
        attribute publisher : String;
        attribute url : String;
        attribute revision : String;
        attribute licence : String;
        attribute contentHash : String[0..1];
        doc /* Pinned source identity/provenance for immutable reference data. Missing
             hash is not an asserted integrity verification. No source code execution. */
    }
    attribute def RadioPropertyDomain {
        attribute valueKind : RadioPropertyValueKind;
        attribute unit : String[0..1];
        attribute integerMinimum : Integer[0..1];
        attribute integerMaximum : Integer[0..1];
        attribute integerStep : Integer[0..1];
        attribute realMinimum : Real[0..1];
        attribute realMaximum : Real[0..1];
        attribute realStep : Real[0..1];
        attribute allowedIntegers : Integer[*];
        attribute allowedReals : Real[*];
        attribute allowedTextValues : String[*];
        attribute memberDefinitionIds : String[*];
        attribute minimumCardinality : Integer[0..1];
        attribute maximumCardinality : Integer[0..1];
        attribute integerDefault : Integer[0..1];
        attribute realDefault : Real[0..1];
        attribute booleanDefault : Boolean[0..1];
        attribute textDefault : String[0..1];
        doc /* Full scalar, enum/set/bitmask/list/record/bytes domain; member IDs describe
             structured members rather than flattening them into operator settings.
             Typed ranges, steps, choices, ordering and defaults are supplied only when
             source-defined for this context. Missing means unknown/not specified,
             never zero, unrestricted, a guessed default or automatic applicability. */
    }
    attribute def RadioApplicabilityContext {
        attribute vfo : String[0..1];
        attribute receiverOrSlice : String[0..1];
        attribute antenna : String[0..1];
        attribute memoryBank : String[0..1];
        attribute memoryChannel : String[0..1];
        attribute scope : String[0..1];
        attribute region : String[0..1];
        attribute firmware : String[0..1];
        attribute mode : String[0..1];
        attribute rangeId : String[0..1];
        attribute sourceCondition : String[0..1];
        doc /* Explicit source-defined applicability context. Absence is unspecified,
             not all VFOs/regions/firmware. Ordered capability tables remain ordered;
             model-specific exceptions are retained instead of generalized. */
    }
    attribute def RadioPropertyDefinition {
        attribute id : String;
        attribute namespace : String;
        attribute name : String;
        attribute description : String;
        attribute group : RadioPropertyGroup;
        attribute domain : RadioPropertyDomain;
        attribute sourceIds : String[*];
        doc /* One union-dictionary definition per stable qualified property ID.
             Standardized properties and namespaced vendor/backend extensions coexist.
             RF filter identity and physical width use separate IDs/units; a FIL
             number supplies no Hz width. No selected model values are invented here. */
    }
    attribute def RadioInteractionDefinition {
        attribute id : String;
        attribute namespace : String;
        attribute description : String;
        attribute protocol : String[0..1];
        attribute propertyIds : String[*];
        attribute requestSemantics : String;
        attribute responseSemantics : String;
        attribute preconditions : String;
        attribute failureSemantics : String;
        attribute sourceIds : String[*];
        doc /* Full intended queries, changes, actions/events and model interactions,
             including planned capabilities. Vocabulary is not limited to current Rust
             operations. Protocol semantics are passive reference data, not executable
             commands, a raw-command API, or TX authorization. */
    }
    attribute def RadioPropertyDictionary {
        attribute revision : String;
        attribute sources : RadioReferenceSource[*];
        attribute properties : RadioPropertyDefinition[*];
        attribute interactions : RadioInteractionDefinition[*];
        doc /* Consolidated union dataset: standard Hamlib vocabulary and namespaced
             vendor/backend properties/interactions, with canonical meanings/types.
             Models refer to these IDs rather than copying definitions. Extensible
             vocabulary retains unknown metadata and does not imply every radio has
             every feature or that a C capability callback alone proves its behaviour. */
    }
    attribute def RadioModelProperty {
        attribute dictionaryPropertyId : String;
        attribute context : RadioApplicabilityContext;
        attribute domain : RadioPropertyDomain;
        attribute readable : Boolean[0..1];
        attribute writable : Boolean[0..1];
        attribute sourceIds : String[*];
        doc /* One model's applicable property/domain/access, not the generic meaning.
             Null access means unknown; advertised getters/setters, actual driver
             implementation, observed availability and permission are distinct. */
    }
    attribute def RadioModelInteraction {
        attribute dictionaryInteractionId : String;
        attribute context : RadioApplicabilityContext;
        attribute actionAvailable : Boolean[0..1];
        attribute eventAvailable : Boolean[0..1];
        attribute sourceIds : String[*];
    }
    attribute def RadioModelDefinition {
        attribute id : String;
        attribute manufacturer : String;
        attribute model : String;
        attribute protocol : String;
        attribute hamlibModelId : Integer[0..1];
        attribute catalogueRevision : String;
        attribute dictionaryRevision : String;
        attribute sourceIds : String[*];
        attribute properties : RadioModelProperty[*];
        attribute interactions : RadioModelInteraction[*];
        doc /* Intended per-model definition independent of Rust implementation coverage.
             Property/interaction IDs resolve in the named dictionary revision, source
             IDs in this catalogue. Applicable range/mode/filter/step tables and context
             retain source ordering. Hamlib models identify reference knowledge, not
             a Hamlib runtime dependency or identical capabilities for every radio. */
    }
    attribute def RadioReferenceCatalogue {
        attribute schemaVersion : String;
        attribute revision : String;
        attribute dictionaryRevision : String;
        attribute sources : RadioReferenceSource[*];
        attribute models : RadioModelDefinition[*];
        attribute coverage : WstxRequirements::ImplementationState = WstxRequirements::ImplementationState::target;
        doc /* Second dataset: planned broad immutable/versioned Hamlib-derived model
             catalogue, stored as back-end data and consulted on selection/configuration/
             connection as needed. It references the union dictionary, not a second
             vocabulary. Not a service, periodic task, always-running Hamlib process,
             completed bulk import or additional physical command path. Source revisions/
             licences/context must be retained; ingestion/completeness remain unsettled.
             The implemented limited IC-7300 artifact is tracked separately below. */
    }
    attribute def SelectedRadioModel {
        attribute catalogueRevision : String;
        attribute dictionaryRevision : String;
        attribute modelId : String;
        attribute definition : RadioModelDefinition;
        doc /* Reference by immutable catalogue revision/model ID to one stored model
             record and its dictionary revision. definition MUST be that record, not
             a second independently edited definition. The physical radio exposes its
             applicable properties/interactions; unknown actual values remain unknown.
             Selection neither narrows the abstract radio to today's Rust subset nor
             enables commands. This is a data reference, not an additional runtime part. */
    }
    attribute def RadioDriverCoverage {
        attribute modelId : String;
        attribute coverage : WstxRequirements::ImplementationState;
        attribute interactionIds : String[*];
        attribute implementation : String;
        attribute verification : String;
        doc /* Separate implementation tracking for the driver/model link: implemented,
             partial or target per interaction. Planned model capabilities stay normative
             even when this driver lacks them. Current operation admission continues to
             require the validated selected model, implemented typed driver and existing
             station/common-authority/safety guards; catalogue data cannot grant access.
             This metadata is not observed radio state or the model's full vocabulary. */
    }

    requirement PhysicalDeploymentStructure {
        doc /* Architectural refinement of the existing deployment scope: the model MUST
             contain the user/viewer/controller/radio context and its operator, station,
             separate audio and control paths, with profile-scoped endpoint selection.
             Variable browser and station populations MUST NOT become a fixed station
             count, all-to-all routing, or an additional detached deployment. */
    }
    requirement StationResourceIdentity {
        doc /* Architectural refinement of WstxProfiles and
             WstxProductScope::NativeFlexBoundary: each station MUST compose one profile,
             one selected backend variation and one selected-radio binding, and reference
             the controller's common authority. All control requests/outcomes MUST retain
             request/resource identity through that authority to the selected backend.
             A backend or native session MUST NOT introduce an authority bypass. */
    }
    requirement ResponsibilityAndExchangeBoundaries {
        doc /* Architectural refinement of WstxProductScope::SharedDataOwnership,
             ProcessingAndHaltOwnership, RemoteDeliveryPolicy and TransmitSafetyPolicy:
             the declared owners MUST retain their separate typed/directed exchanges.
             Recording storage MUST feed the common receive path; receive and encode
             MUST connect to pure mode functions; audio and control MUST stay separate.
             Browser/MCP adapters MUST use station operations rather than direct backend
             access. The ownership explanations and existing policy contracts apply
             together; target parts do not claim runtime delivery or settled policy. */
    }
    dependency deploymentOwnership from physicalStation to PhysicalDeploymentStructure;
    dependency stationIdentityOwnership from physicalStation::controller::stations to StationResourceIdentity;
    dependency boundaryOwnership from physicalStation::controller::stations to ResponsibilityAndExchangeBoundaries;

    verification ResolvedArchitectureGraph {
        subject deployment :> physicalStation;
        doc /* Level 2 isolated automated model test on the development PC; no radio,
             device or runtime service. Resolve the accepted model and legal negative
             mutations with the pinned semantic validator. Independent expectations are
             literal required endpoints, complete item-kind/direction signatures,
             population/reference subsets, backend alternatives and identity bindings
             in the existing architecture integrity oracle, not candidate-derived counts.
             Expect user-to-viewer, profile-selected viewer-to-web/station and separate
             backend-to-selected-radio audio/control paths; upload-to-profile-to-receive,
             receive-to-mode and encode-to-mode paths; exactly one effective authority
             whose bound request/outcome and resource context reach that same backend.
             Missing delegation/encode, reversed provider/waveform direction, wrong item
             kind, redirected association/context, weakened identity binding, split or
             bypassed authority, duplicate backend, detached stations and view-created
             structure MUST be rejected even if legal SysML. The unchanged graph has
             33 parts, 8 references, 80 ports and 69 connections; counts alone are
             insufficient. This case checks structure, not runtime timing, persistence,
             failure handling, platform operation or RF safety. */
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
        doc /* Known component values MUST be navigable under their owning parts using
             canonical typed definitions/value references. Persisted profile configuration,
             private runtime input, browser-local preference, requested/live selection,
             observed state, reference capability and implementation coverage MUST remain
             distinct. A property attachment MUST NOT add persistence fields, controls,
             commands, credentials, workers or a second authority for shared constants.
             Inherited numerical limits/defaults remain their existing contract; source-
             only parsed endpoint/display/conversion views identify the existing source
             or canonical prose that determines them. Unsettled properties stay explicit. */
    }
    requirement RadioModelReferenceSeparation {
        doc /* A radio MUST expose its selected model's applicable property definitions,
             limits and interactions through an immutable/versioned catalogue reference.
             The generic model MUST represent intended capability independently of current
             driver coverage, preserving planned interactions. Reference catalogue data,
             requested values, actual observations and driver implementation metadata
             MUST NOT be substituted for each other. Passive catalogue lookup MUST NOT
             imply background Hamlib execution, command permission or a new physical
             path; existing common authority and runtime safety/admission remain binding.
             Unknown radio filter width MUST NOT be inferred from filter ID or display span. */
    }
    dependency browserPropertyOwnership from physicalStation::viewer::browsers to ComponentPropertyOwnership;
    dependency stationPropertyOwnership from physicalStation::controller::stations to ComponentPropertyOwnership;
    dependency radioPropertyOwnership from physicalStation::radio to RadioModelReferenceSeparation;

    verification ComponentPropertyInventoryReview {
        subject deployment :> physicalStation;
        objective {
            verify ComponentPropertyOwnership;
            verify RadioModelReferenceSeparation;
        }
        doc /* Level 2 isolated manual independent inventory/correspondence review on
             the development PC, no station/device/credential access or external effects.
             Independent inputs are existing WstxProfiles, WstxStationProtocol,
             WstxRecordingReceive, WstxOfflineDecode, WstxRadioIO,
             WstxOperatingLayout, WstxOperatingReceive and WstxProductScope contracts,
             plus Configuration in server/src/radio_control/mod.rs and the limited
             fixtures/radio/ic7300-catalogue.json / radio_control/catalogue.rs companion.
             Expect ProfileDocument ownership of exactly its existing persisted schema;
             no saved live band/mode/frequency, browser preference or secret. Expect
             private runtime/effective endpoint/transport and HTTP bounds on WebAdapter;
             local display choice keyed effective origin+validated UUID, levels/speed,
             sort, geometry and observed/pending presentation on BrowserClient.
             Expect all twelve canonical preferred values (160m,80m,60m,40m,30m,20m,
             17m,15m,12m,10m,6m,4m), their provenance and admitted range on StationService;
             FT4 remains absent for 160m/4m and initial nominal remains unknown.
             Compare identities to original qualified values, not a copied table.
             Expect device/CAT endpoint intent distinct from parsed config and actual
             state; requested nominal/typed CAT operands distinct from per-query confirmed
             facts, unknown stale/null values and observed physical radio properties.
             Expect capture/timing/conversion/queues on audio/receive owners, numerical
             modem/search/FEC contracts on ModeFunctions, common-platform/CPU policy
             and acceptance workload on controller, and target safety on TransmitService.
             Expect complete known groups rather than representative settings; import,
             result and wire schemas are not mislabeled as operator configuration.
             Reject omitted ownership, duplicated numeric defaults/tables, invented RF
             filter width, a fixed station/radio capacity, MCP/TX/native policy defaults,
             current Rust support used as abstract-radio ceiling, catalogue-as-command
             permission or inferred delivery. Review passive source/version/model links
             independently from Rust implementation coverage and runtime observations.
             Static name/type/value resolution and ResolvedArchitectureGraph are existing
             executable companions, not automated completeness or behavioural proofs.
             Existing WstxRequirements cases retain actual runtime coverage/status;
             broad-catalogue lookup/ingestion and unresolved future feature acceptance
             remain planned. No claim that this declaration executes those cases. */
        attribute method : String = "manual independent source/property inventory and canonical correspondence review";
        attribute executionStatus : String = "planned; typed resolution and structural companions do not establish review or runtime acceptance";
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

    part def Operator { port interaction : LocalInteraction; }
    part def BrowserClient {
        attribute localDisplayLevels : WstxRecordingReceive::DisplayLevels;
        attribute localDisplayPreference : WstxRecordingReceive::BrowserDisplayPreference;
        attribute localActivityOrdering : WstxOperatingLayout::ActivityOrdering;
        attribute observedPresentation : WstxOperatingLayout::OperatingPresentation;
        attribute receivePresentation : WstxOperatingReceive::ReceivePresentation;
        attribute snapshotPolicy : WstxStationProtocol::BrowserSnapshotPolicy;
        attribute splitGeometry : WstxOperatingLayout::SplitGeometry;
        attribute operatingDesign : WstxOperatingLayout::AgreedOperatingDesign;
        attribute fixedDisplayGeometry : DisplayGeometry;
        attribute displayContractLimits : WstxRecordingReceive::Limits;
        doc /* Local display choices/sensitivity/speed/sort are browser-owned. Only
             display profile choice persists by effective origin plus validated UUID;
             black/range/auto reset by source/job/display profile, sensitivity/speed
             last for the page. Presentation reports actual capability/pending/stale
             state and never becomes station authority. displayContractLimits projects
             native bins/rows/repaint/delivery bounds, not extra user controls. */
        doc /* Own presentation/local filtering/color, pending/stale state and requests; not authoritative radio state, timing-critical modulation or transmit authority. */
        port operator : ~LocalInteraction;
        port station : BrowserExchange;
    }
    part def McpClient { port station : StationOperations; }
    part def ViewerComputer {
        doc /* Browser placement is local or remote; no different profile schema or
             physical radio policy follows from co-resident viewer/controller roles. */
        port operator : ~LocalInteraction;
        port stationLink : BrowserExchange;
        part browsers[*] : BrowserClient;
        connection operatorDelegation connect operator to browsers.operator;

    }
    part def Radio {
        attribute physicalIdentity : String[0..1];
        attribute selectedModelDefinition : SelectedRadioModel[0..1];
        attribute observedProperties : WstxRadioIO::RadioObservation[0..1];
        attribute physicalReceiverBandwidthHz : Real[0..1];
        doc /* Selected model reference exposes its full applicable property/interaction
             definitions, independent of Rust coverage. Physical identity is not a
             station-count-derived radio number. Actual filter width remains unknown
             unless independently established for this radio/filter; FIL1..3, DSP
             passband and browser 0..3000Hz do not establish receiver bandwidth. */
        port audio : ~AudioExchange;
        port control : ~RadioControl;
    }
    part def StationControllerComputer {
        attribute platformPolicy : WstxProductScope::ReleasePolicy;
        attribute accelerationPolicy : WstxProductScope::AccelerationPolicy;
        attribute thinLinkAcceptanceWorkload : WstxStationProtocol::ThinLinkBudget;
        attribute hasFixedStationPopulationLimit : Boolean = WstxProfiles::hasFixedPopulationLimit;
        attribute profileAcceptanceStationCount : Integer = WstxProfiles::referenceAcceptanceCount;
        doc /* Acceptance population/link workload is not a deployment capacity limit.
             Acceleration policy is planned: bounded workers across profiles, CPU path
             and operator override; no numeric override or GPU API is selected. */
        doc /* One controller role hosts variable N station processes. The common authority
             is effective shared-radio responsibility, not a per-process mutex.
             Cross-process placement/leases and actual hardware capacity are constrained
             by WstxProductScope::NativeFlexBoundary and WstxRadioIO. Profile-scoped
             routing is not all-to-all delivery or simultaneous transmission. */
        port viewerLink : ~BrowserExchange;
        port radioAudio : AudioExchange;
        port radioControl : RadioControl;
        part stations[*] : StationProcess;
        ref part mcpClients[*] : McpClient;
        doc /* MCP clients are referenced, not deployed onto this computer by composition.
             Controller attachments own routing associations only. Client placement and
             detailed authority remain unresolved before MCP implementation. */
        part radioAuthority : RadioAuthority;

        part mcpAttachments[*] : McpAttachment;

    }
    part def BrowserAttachment {
        doc /* One profile-scoped browser/station association carried by the physical IP
             link. Each endpoint reference selects one member, never the whole population. */
        ref part browser : BrowserClient :> physicalStation.viewer.browsers;
        ref part station : StationProcess :> physicalStation.controller.stations;
        port clientBoundary : ~BrowserExchange;
        connection browserDelegation connect browser.station to clientBoundary;
        connection webDelegation connect clientBoundary to station.web.client;
    }
    part def McpAttachment {
        ref part client : McpClient :> physicalStation.controller.mcpClients;
        ref part station : StationProcess :> physicalStation.controller.stations;
        connection mcpClientOperations connect client.station to station.mcp.client;
    }
    part def RadioBinding {
        doc /* Persisted intent resolves the selected physical radio/resource at connection.
             WstxProductScope::NativeFlexBoundary leaves native slice/handle schema
             and actual radio capacity as implementation prerequisites. */
        ref part radio : Radio :> physicalStation.radio;
    }
    part def RadioAudioAttachment {
        ref part station : StationProcess :> physicalStation.controller.stations;
        connection audioDelegation connect station.backend.radioAudio to station.radioBinding.radio.audio;
    }
    part def RadioControlAttachment {
        ref part station : StationProcess :> physicalStation.controller.stations;
        connection controlDelegation connect station.backend.radioControl to station.radioBinding.radio.control;
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
        doc /* Current/desired mode, band and nominal frequency are boot/live operating
             state, NOT additional saved ProfileDocument fields. Fresh nominal/band
             remain absent; resolved selection exists only after valid resolution.
             Twelve receive-preferred entries reuse the canonical table, including
             unsupported FT4 entries; no fallback, jurisdictional TX permission or
             additional mode inventory follows. Requested nominal differs from CAT
             readback; operation identity/revisions fence stale completions. */
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
        attribute transportLimits : WstxStationProtocol::Limits;
        attribute operatingWireLimits : WstxOperatingReceive::WireLimits;
        attribute maxProfileHttpBytes : Integer = WstxProfiles::profileHttpMaxBytes;
        attribute maxLoginBodyBytes : Integer = WstxProfiles::loginBodyMaxBytes;
        attribute readinessDeadlineSeconds : Integer = WstxProfiles::readinessDeadlineSeconds;
        attribute loopbackRefreshDeadlineSeconds : Integer = WstxProfiles::loopbackRefreshDeadlineSeconds;
        attribute reconnectAfterDetectionDeadlineSeconds : Integer = WstxProfiles::reconnectAfterDetectionDeadlineSeconds;
        attribute silentLossDetectionSeconds : Integer = WstxProfiles::silentLossDetectionSeconds;
        doc /* Runtime TLS paths/token are private input shapes with no secret values
             instantiated here and never profile/settings response fields. Saved endpoint
             intent remains profile-owned; effective endpoint/auth/origin are validated
             runtime properties. Compression policy remains the existing
             WstxOperatingReceive::HttpContentCodingBoundary, not another part. */
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
        doc /* Authentication/endpoint/configuration schema and detailed caller policy
             remain planned. No invented port, credential, native access or TX permission
             is supplied by the architectural property inventory. */
        doc /* Own protocol validation/caller context and configured station-selection/automation requests. No independent station state, backend access or separate transmit permission; same station operations and safety policy as browser. */
        port client : ~StationOperations;
        port station : StationOperations;
    }
    part def PersistedProfile {
        attribute configuration : WstxProfiles::ProfileDocument;
        attribute maxFileBytes : Integer = WstxProfiles::profileFileMaxBytes;
        attribute maxRevision : Integer = WstxProfiles::maxRevision;
        doc /* configuration is the single canonical persisted value shape: identity,
             revision, station settings, audio/control endpoint intent, connection type
             and endpoint. Inherited defaults/ranges retain WstxProfiles ownership.
             No live operating selection, browser preference or TLS secret is added. */
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
        doc /* Profile-owned original recordings and metadata/manifests use existing
             storage schemas; these are stored data descriptions, not new settings,
             a live-audio archive or a second recording store. */
        doc /* Validated profile-owned recording, selected by identity rather than arbitrary
             client paths. No live audio device is required for this input. */
        port upload : ~RecordingTransfer;
        port samples : ReceiveSamples;
    }
    part def ReceivePipeline {
        attribute recordingContractLimits : WstxRecordingReceive::Limits;
        attribute liveContractLimits : WstxRadioIO::Limits;
        attribute decoderLifecycleLimits : WstxOfflineDecode::Limits;
        attribute conversion : ConversionContract;
        attribute observedSourceTiming : WstxRadioIO::SourceTiming[0..1];
        doc /* Read-only contract limits cover recorded import/spectrum, canonical/live
             sample queues/conversion/timing and bounded decode history/worker/results.
             Fields are shared contract facets, not three schedulers, per-source
             resamplers or persisted operator knobs. Decoder mathematics stays modes. */
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
        attribute numericalLimits : WstxOfflineDecode::Limits;
        attribute modeParameters : WstxOfflineDecode::ModeParameters[*];
        attribute ft8SearchPolicy : WstxOfflineDecode::Ft8CarrierSearchPolicy;
        attribute ft8PhysicalLimits : WstxOfflineDecode::Ft8PhysicalLimits;
        attribute ft4PhysicalLimits : WstxOfflineDecode::Ft4PhysicalLimits;
        doc /* Mode inventory/state retains WstxProductScope::BaselineMode and
             WstxRequirements capability declarations. Numerical/FEC/FFT/search/window
             constants are algorithm contracts, not user-adjustable decoder controls.
             Wire/result/payload codebooks remain schemas in their canonical package,
             not additional component settings. */
        doc /* Pure protocol/symbol/waveform and decoding calculations with independent vectors; no filesystem/hardware/network/wall-clock dependency. */
        doc /* Pure receive calculations and encoding/waveform generation depend on no
             device, filesystem, wall-clock or network. WstxOfflineDecode owns concrete
             mode contracts and status; hardware format adaptation and common rate
             conversion remain outside this boundary. */
        port receive : ~ReceiveProcessing;
        port encode : ~EncodeProcessing;
    }
    part def TransmitService {
        attribute safetyPolicy : WstxProductScope::TransmitSafetyPolicy;
        doc /* Target properties only: startup unarmed, independent halt and common
             policy. UTC/device-loss/expiry/VOX/stop deadlines remain unsettled before
             hardware TX; no new defaults, controls or current TX support are implied. */
        doc /* Own UTC scheduling, transmit state, audio/PTT coordination and priority halt; no browser timer or visualization-queue dependency. Defaults UNARMED on startup. Halt never waits for decode, receive cancellation or congestion. Controller/device loss and authority-expiry policy are settled before hardware TX and cannot be replaced in MCP. */
        doc /* UTC scheduling, operation authority and audio/PTT coordination reuse the
             common resource context. WstxProductScope::TransmitSafetyPolicy owns
             unresolved deadlines/controller-loss/expiry policy before hardware TX;
             WstxProductScope::ProcessingAndHaltOwnership separates priority halt from
             receive completion/cancellation and optional display congestion. */
        port operations : ~StationOperations;
        port encode : EncodeProcessing;
        port audio : AudioExchange;
        port control : RadioControl;
    }
    part def QsoAndLogging {
        doc /* Planned completion/contact properties are governed by
             WstxProductScope::CompletedContactIdentity. Concrete contact schema,
             compatibility, recovery and configuration remain unsettled; no substitute
             settings record is introduced. */
        doc /* Own exchange/completion/cancel and durable contacts; never bypass transmit authority or another profile storage. Stable completion identity and explicit persisted/unsaved outcome prevent silent duplicate contacts when completion replays. Concrete log schema/compatibility remains a target decision. */
        port operations : ~StationOperations;
        port contacts : ProfileAccess;
    }
    part def AudioInterface {
        attribute configuredIntent : WstxRadioIO::DeviceIntent;
        attribute observedState : WstxRadioIO::AudioState;
        attribute observedSourceTiming : WstxRadioIO::SourceTiming[0..1];
        attribute deviceAndTimingLimits : WstxRadioIO::Limits;
        doc /* configuredIntent is a derived selected-profile view, not independent
             persistence. Endpoint/channel intent differs from actual open source,
             format/rate, device clock and failure state. Supported native packet
             rates/channels/formats remain WstxRadioIO::NativePacket and NativeFormat;
             no physical radio rate promise or additional device enumeration/open. */
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
        attribute controlContractLimits : WstxRadioIO::Limits;
        doc /* ControlSelection derives from the selected profile; it does not assert
             availability. Existing request ports carry WstxRadioIO::CatRequest typed
             operands, not a settings attribute or raw-command channel. Confirmed facts
             require current matching query provenance independently per field;
             aggregate timestamp, requested nominal and ACK alone do not confirm them. */
        doc /* Own selected capabilities, typed CAT/control/PTT/status/resource claims; not audio samples/sound devices, browser/MCP policy or duplicate modem logic. */
        doc /* Capabilities, CAT/PTT/status, independent failures and resource claims. No
             samples; Rust control subset only, no full Hamlib port/API or mandatory library. */
        port station : ~RadioControl;
        port transmit : ~RadioControl;
        port backend : RadioControl;
    }
    part def AudioDeviceAdapter {
        doc /* Native input contract WstxRadioIO::NativePacket describes actual
             endpoint/rate/channel/format/timestamp metadata, not persisted selections.
             Hardware capability expansion remains explicit rather than inferred. */
        port host : ~AudioExchange;
        port radio : AudioExchange;
    }
    part def RustRadioDriver {
        attribute parsedConfiguration : ParsedCatConfiguration[0..1];
        attribute observed : WstxRadioIO::RadioObservation[0..1];
        attribute implementationCoverage : RadioDriverCoverage[*];
        attribute currentIc7300Coverage : RadioDriverCoverage {
            attribute :>> modelId = "icom.ic7300";
            attribute :>> coverage = WstxRequirements::ImplementationState::partial;
            attribute :>> implementation = "server/src/radio_control/mod.rs; server/src/radio_control/catalogue.rs; fixtures/radio/ic7300-catalogue.json";
            attribute :>> verification = "WstxRequirements::TC-009-001; WstxRequirements::TC-009-003; server/tests/radio_control.rs";
        }
        doc /* Current IC-7300 compiled typed receive-control subset is delivery
             metadata, not a ceiling on RadioModelDefinition. The existing catalogue
             validates known command metadata and cannot install a driver/raw/TX action.
             Parsed endpoint, requested operation and actual observation stay separate. */
        port authorized : ~RadioControl;
        port radio : RadioControl;
    }
    abstract part def RadioBackend {
        attribute propertyDictionary : RadioPropertyDictionary[0..1];
        attribute referenceCatalogue : RadioReferenceCatalogue[0..1];
        doc /* Passive back-end reference data may be shared immutably across stations.
             SelectedRadioModel identifies one record by revision/model ID; catalogue
             property/interaction knowledge stays separate from driver implementation
             coverage and live observations. No process/session/authority is added. */
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
        doc /* Native API/stream formats, sharing/lifetime, capacity and leases remain
             unresolved in WstxProductScope::NativeFlexBoundary. No invented native
             settings/capacity values are part of this property attachment. */
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
        ref part authority : RadioAuthority :> physicalStation.controller.radioAuthority;
        port authorityRequest : RadioControl;
        port authorizedControl : ~RadioControl;
        variation part backend : RadioBackend {
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
        connection selectedAudio connect audio.backend to backend.audio;
        connection authorityRequestDelegation connect radioControl.backend to authorityRequest;
        connection authorizedControlDelegation connect authorizedControl to backend.control;
        connection commonAuthority connect authorityRequest to authority.requests;
        connection authorizedBackend connect authority.authorized to authorizedControl;
        binding requestContext bind authorityRequest.request.resourceContext = radioBinding;
        binding backendContext bind backend.control.request.resourceContext = radioBinding;
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
