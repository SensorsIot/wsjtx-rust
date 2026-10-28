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
        attribute 'port' : Integer;
        attribute fixedBaud : Integer[0..1];
        attribute radioAddress : Integer;
        attribute controllerAddress : Integer;
        assert constraint validPort { 'port' >= 1 and 'port' <= 256 }
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

    enum def RadioPublicationMode { enum off; enum radioEvents; enum polling; }
    enum def RadioVfoRole {
        enum a; enum b; enum c; enum main; enum sub; enum memory;
        enum current; enum transmit; enum receive; enum other;
    }
    enum def RadioPttState { enum off; enum on; enum microphoneOnly; enum dataOnly; }
    enum def RadioRfModeName {
        enum am; enum cw; enum usb; enum lsb; enum rtty; enum fm; enum wfm;
        enum cwr; enum rttyr; enum ams; enum pktlsb; enum pktusb; enum pktfm;
        enum ecssusb; enum ecsslsb; enum fax; enum sam; enum sal; enum sah;
        enum dsb; enum fmn; enum pktam; enum p25; enum dstar; enum dpmr;
        enum nxdnvn; enum nxdn_n; enum dcr; enum amn; enum psk; enum pskr;
        enum dd; enum c4fm; enum pktfmn; enum spec; enum cwn; enum iq;
        enum isbusb; enum isblsb; enum usbd1; enum usbd2; enum usbd3;
        enum lsbd1; enum lsbd2; enum lsbd3; enum wfms;
    }
    attribute def NormalizedRadioState {
        attribute rfMode : RadioRfModeName[0..1];
        attribute otherRfModeName : String[0..1];
        attribute vfoRole : RadioVfoRole[0..1];
        attribute vfoSelector : String[0..1];
        attribute ptt : RadioPttState[0..1];
        doc /* Intended normalized semantic radio mode/VFO/PTT observations, separately
             from raw source enum/bitmask integers and current RadioObservation wire
             fields. Names correspond to pinned public Hamlib concepts; SysML enum
             ordinals are NOT C codes. VFO aliases/indices and unrecognized modes retain
             their explicit selector/name; absence remains unknown. Concrete adapter
             mappings require source-defined decoding and matching observations.
             These are RF modes, not FT4/FT8 modem selection or transmit permission. */
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
    attribute def RadioInteractionDefinition {
        attribute id : String;
        attribute 'namespace' : String;
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
    attribute def HamlibUnresolvedProperty {
        attribute sourceExpression : String[0..1];
        doc /* Explicit unresolved/union/opaque source domain. Not a guessed Boolean,
             writable value, executable C expression or invented default. */
    }
    doc /* Hamlib property-column authority, pinned source commit
         075b78cb0560e892c81bc73890d633cc11f23f59. The following 1064 distinct named
         property features cover the finite pinned public radio surface and scanned
         vendor metadata, not every future firmware/raw command or amplifier/rotator.
         Names are catalogue column IDs; types, meanings, units and access/source notes
         live here once. Optional means value/applicability may be unknown, not universal
         support. Integer enum/bitmask codes retain explicit source domains; SysML enum
         ordinals are not C codes. Record navigation follows source declaration order;
         nested/union context is not a new C memory-layout/serialization specification.
         Per-model cells belong to data/hamlib-models.json. A source mask/handler pointer
         is not live success. Read-only properties never gain a setter from sharing a
         vocabulary datatype. Column source corpus SHA256:
         83451f458fbcb66fb560326d1ed3e07c53609bc94d80a8a2a738b30bae4e1380. */
    attribute def HamlibBackendModelProperties {
        attribute 'hamlib.rig_caps.async_data_supported' : Integer[0..1] {
            doc /* Meaning: Indicates that rig is capable of outputting asynchronous data updates, such as transceive state updates or spectrum data. 1 if true, 0 otherwise.. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: int async_data_supported. Owner: RadioControlConnection/backend. Context: model-specific. Source: include/hamlib/rig.h:2639. */
        }
        attribute 'hamlib.rig_caps.cfgparams' : HamlibUnresolvedProperty[0..1] {
            doc /* Meaning: Configuration parameters.. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: const struct confparams *cfgparams. Owner: RadioControlConnection/backend. Context: model-specific. Source: include/hamlib/rig.h:2451. */
        }
        attribute 'hamlib.rig_caps.copyright' : String[0..1] {
            doc /* Meaning: Copyright info.. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: const char *copyright. Owner: RadioControlConnection/backend. Context: model-specific. Source: include/hamlib/rig.h:2360. */
        }
        attribute 'hamlib.rig_caps.dcd_type' : Integer[0..1] {
            doc /* Meaning: Type of the DCD port.. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: dcd_type_t dcd_type. Owner: RadioControlConnection/backend. Context: model-specific. Source: include/hamlib/rig.h:2365. */
        }
        attribute 'hamlib.rig_caps.has_get_func' : Integer[0..1] {
            doc /* Meaning: List of get functions. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: setting_t has_get_func. Owner: RadioControlConnection/backend. Context: model-specific. Source: include/hamlib/rig.h:2380. */
        }
        attribute 'hamlib.rig_caps.has_get_level' : Integer[0..1] {
            doc /* Meaning: List of get level. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: setting_t has_get_level. Owner: RadioControlConnection/backend. Context: model-specific. Source: include/hamlib/rig.h:2382. */
        }
        attribute 'hamlib.rig_caps.has_get_parm' : Integer[0..1] {
            doc /* Meaning: List of get parm. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: setting_t has_get_parm. Owner: RadioControlConnection/backend. Context: model-specific. Source: include/hamlib/rig.h:2384. */
        }
        attribute 'hamlib.rig_caps.has_set_func' : Integer[0..1] {
            doc /* Meaning: List of set functions. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: setting_t has_set_func. Owner: RadioControlConnection/backend. Context: model-specific. Source: include/hamlib/rig.h:2381. */
        }
        attribute 'hamlib.rig_caps.has_set_level' : Integer[0..1] {
            doc /* Meaning: List of set level. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: setting_t has_set_level. Owner: RadioControlConnection/backend. Context: model-specific. Source: include/hamlib/rig.h:2383. */
        }
        attribute 'hamlib.rig_caps.has_set_parm' : Integer[0..1] {
            doc /* Meaning: List of set parm. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: setting_t has_set_parm. Owner: RadioControlConnection/backend. Context: model-specific. Source: include/hamlib/rig.h:2385. */
        }
        attribute 'hamlib.rig_caps.port_type' : Integer[0..1] {
            doc /* Meaning: Type of communication port.. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: rig_port_t port_type. Owner: RadioControlConnection/backend. Context: model-specific. Source: include/hamlib/rig.h:2366. */
        }
        attribute 'hamlib.rig_caps.post_write_delay' : Integer[0..1] {
            doc /* Meaning: Delay between each commands send out, in mS. Unit: ms. Access/role: catalogue description/capability; not live state.
                 Source type: int post_write_delay. Owner: RadioControlConnection/backend. Context: model-specific. Source: include/hamlib/rig.h:2376. */
        }
        attribute 'hamlib.rig_caps.ptt_type' : Integer[0..1] {
            doc /* Meaning: Type of the PTT port.. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: ptt_type_t ptt_type. Owner: RadioControlConnection/backend. Context: model-specific. Source: include/hamlib/rig.h:2364. */
        }
        attribute 'hamlib.rig_caps.retry' : Integer[0..1] {
            doc /* Meaning: Maximum number of retries if command fails, 0 to disable. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: int retry. Owner: RadioControlConnection/backend. Context: model-specific. Source: include/hamlib/rig.h:2378. */
        }
        attribute 'hamlib.rig_caps.serial_data_bits' : Integer[0..1] {
            doc /* Meaning: Number of data bits.. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: int serial_data_bits. Owner: RadioControlConnection/backend. Context: model-specific. Source: include/hamlib/rig.h:2370. */
        }
        attribute 'hamlib.rig_caps.serial_handshake' : Integer[0..1] {
            doc /* Meaning: Handshake.. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: enum serial_handshake_e serial_handshake. Owner: RadioControlConnection/backend. Context: model-specific. Source: include/hamlib/rig.h:2373. */
        }
        attribute 'hamlib.rig_caps.serial_parity' : Integer[0..1] {
            doc /* Meaning: Parity.. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: enum serial_parity_e serial_parity. Owner: RadioControlConnection/backend. Context: model-specific. Source: include/hamlib/rig.h:2372. */
        }
        attribute 'hamlib.rig_caps.serial_rate_max' : Integer[0..1] {
            doc /* Meaning: Maximum serial speed.. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: int serial_rate_max. Owner: RadioControlConnection/backend. Context: model-specific. Source: include/hamlib/rig.h:2369. */
        }
        attribute 'hamlib.rig_caps.serial_rate_min' : Integer[0..1] {
            doc /* Meaning: Minimum serial speed.. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: int serial_rate_min. Owner: RadioControlConnection/backend. Context: model-specific. Source: include/hamlib/rig.h:2368. */
        }
        attribute 'hamlib.rig_caps.serial_stop_bits' : Integer[0..1] {
            doc /* Meaning: Number of stop bits.. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: int serial_stop_bits. Owner: RadioControlConnection/backend. Context: model-specific. Source: include/hamlib/rig.h:2371. */
        }
        attribute 'hamlib.rig_caps.status' : Integer[0..1] {
            doc /* Meaning: Driver status.. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: enum rig_status_e status. Owner: RadioControlConnection/backend. Context: model-specific. Source: include/hamlib/rig.h:2361. */
        }
        attribute 'hamlib.rig_caps.targetable_vfo' : Integer[0..1] {
            doc /* Meaning: Bit field list of direct VFO access commands. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: int targetable_vfo. Owner: RadioControlConnection/backend. Context: model-specific. Source: include/hamlib/rig.h:2411. */
        }
        attribute 'hamlib.rig_caps.timeout' : Integer[0..1] {
            doc /* Meaning: Timeout, in mS. Unit: ms. Access/role: catalogue description/capability; not live state.
                 Source type: int timeout. Owner: RadioControlConnection/backend. Context: model-specific. Source: include/hamlib/rig.h:2377. */
        }
        attribute 'hamlib.rig_caps.transceive' : Integer[0..1] {
            doc /* Meaning: \deprecated Use async_data_supported instead. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: int transceive. Owner: RadioControlConnection/backend. Context: model-specific. Source: include/hamlib/rig.h:2412. */
        }
        attribute 'hamlib.rig_caps.version' : String[0..1] {
            doc /* Meaning: Driver version.. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: const char *version. Owner: RadioControlConnection/backend. Context: model-specific. Source: include/hamlib/rig.h:2359. */
        }
        attribute 'hamlib.rig_caps.write_delay' : Integer[0..1] {
            doc /* Meaning: Delay between each byte sent out, in mS. Unit: ms. Access/role: catalogue description/capability; not live state.
                 Source type: int write_delay. Owner: RadioControlConnection/backend. Context: model-specific. Source: include/hamlib/rig.h:2375. */
        }
    }
    attribute def HamlibBackendVendorProperties {
        attribute 'hamlib.extension.rigs/kenwood/kenwood.c::kenwood_cfg_params::TOK_NO_ID' : Boolean[0..1] {
            doc /* Meaning: If true do not send ID; with set commands. Unit: unspecified; do not infer units. Access/role: backend identification-probe policy via ext_parm API.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: RadioControlConnection/backend. Context: rig-global. Source: rigs/kenwood/kenwood.c:230. */
        }
    }
    attribute def HamlibCalTableFloatProperties {
        doc /* Source HAMLIB_MAX_CAL_LENGTH=32 (rig.h299) bounds the ordered table
             declared at rig.h1868; each source-defined entry remains opaque here. */
        attribute 'hamlib.struct.cal_table_float.size' : Integer[0..1] {
            doc /* Meaning: number of plots in the table. Unit: unspecified; do not infer units. Access/role: model parameter-domain/calibration metadata.
                 Source type: int size. Owner: physicalRadio/model definition. Context: cal_table_float record context. Source: include/hamlib/rig.h:1864. */
        }
        attribute 'hamlib.struct.cal_table_float.raw' : Integer[0..1] {
            doc /* Meaning: raw (A/D) value. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int raw. Owner: physicalRadio/model definition. Context: cal_table_float record context. Source: include/hamlib/rig.h:1866. */
        }
        attribute 'hamlib.struct.cal_table_float.val' : Real[0..1] {
            doc /* Meaning: associated value. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: float val. Owner: physicalRadio/model definition. Context: cal_table_float record context. Source: include/hamlib/rig.h:1867. */
        }
        attribute 'hamlib.struct.cal_table_float.table' : HamlibUnresolvedProperty[0..32] {
            doc /* Meaning: table of plots. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: table[HAMLIB_MAX_CAL_LENGTH]. Owner: physicalRadio/model definition. Context: cal_table_float record context. Source: include/hamlib/rig.h:1868. */
        }
    }
    attribute def HamlibCalTableProperties {
        doc /* Source HAMLIB_MAX_CAL_LENGTH=32 (rig.h299) bounds the ordered table
             declared at rig.h1838; each source-defined entry remains opaque here. */
        attribute 'hamlib.struct.cal_table.size' : Integer[0..1] {
            doc /* Meaning: number of plots in the table. Unit: unspecified; do not infer units. Access/role: model parameter-domain/calibration metadata.
                 Source type: int size. Owner: physicalRadio/model definition. Context: cal_table record context. Source: include/hamlib/rig.h:1834. */
        }
        attribute 'hamlib.struct.cal_table.raw' : Integer[0..1] {
            doc /* Meaning: raw (A/D) value, as returned by \a RIG_LEVEL_RAWSTR. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int raw. Owner: physicalRadio/model definition. Context: cal_table record context. Source: include/hamlib/rig.h:1836. */
        }
        attribute 'hamlib.struct.cal_table.val' : Integer[0..1] {
            doc /* Meaning: associated value, basically the measured dB value. Unit: dB. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int val. Owner: physicalRadio/model definition. Context: cal_table record context. Source: include/hamlib/rig.h:1837. */
        }
        attribute 'hamlib.struct.cal_table.table' : HamlibUnresolvedProperty[0..32] {
            doc /* Meaning: table of plots. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: table[HAMLIB_MAX_CAL_LENGTH]. Owner: physicalRadio/model definition. Context: cal_table record context. Source: include/hamlib/rig.h:1838. */
        }
    }
    attribute def HamlibChanListProperties {
        attribute 'hamlib.struct.chan_list.startc' : Integer[0..1] {
            doc /* Meaning: Starting memory channel \b number. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int startc. Owner: physicalRadio/model definition. Context: chan_list record context. Source: include/hamlib/rig.h:1775. */
        }
        attribute 'hamlib.struct.chan_list.endc' : Integer[0..1] {
            doc /* Meaning: Ending memory channel \b number. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int endc. Owner: physicalRadio/model definition. Context: chan_list record context. Source: include/hamlib/rig.h:1776. */
        }
        attribute 'hamlib.struct.chan_list.type' : Integer[0..1] {
            doc /* Meaning: Memory type. See #chan_type_t. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: chan_type_t type. Owner: physicalRadio/model definition. Context: chan_list record context. Source: include/hamlib/rig.h:1777. */
        }
        attribute 'hamlib.struct.chan_list.mem_caps' : HamlibChannelCapProperties[0..1] {
            doc /* Meaning: Definition of attributes that can be stored/retrieved. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: channel_cap_t mem_caps. Owner: physicalRadio/model definition. Context: chan_list record context. Source: include/hamlib/rig.h:1778. */
        }
    }
    attribute def HamlibChannelCapProperties {
        attribute 'hamlib.struct.channel_cap.bank_num' : Boolean[0..1] {
            doc /* Meaning: Bank number. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: unsigned bank_num: 1. Owner: physicalRadio/model definition. Context: channel_cap record context. Source: include/hamlib/rig.h:1699. */
        }
        attribute 'hamlib.struct.channel_cap.vfo' : Boolean[0..1] {
            doc /* Meaning: VFO. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: unsigned vfo: 1. Owner: physicalRadio/model definition. Context: channel_cap record context. Source: include/hamlib/rig.h:1700. */
        }
        attribute 'hamlib.struct.channel_cap.ant' : Boolean[0..1] {
            doc /* Meaning: Selected antenna. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: unsigned ant: 1. Owner: physicalRadio/model definition. Context: channel_cap record context. Source: include/hamlib/rig.h:1701. */
        }
        attribute 'hamlib.struct.channel_cap.freq' : Boolean[0..1] {
            doc /* Meaning: Receive frequency. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: unsigned freq: 1. Owner: physicalRadio/model definition. Context: channel_cap record context. Source: include/hamlib/rig.h:1702. */
        }
        attribute 'hamlib.struct.channel_cap.mode' : Boolean[0..1] {
            doc /* Meaning: Receive mode. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: unsigned mode: 1. Owner: physicalRadio/model definition. Context: channel_cap record context. Source: include/hamlib/rig.h:1703. */
        }
        attribute 'hamlib.struct.channel_cap.width' : Boolean[0..1] {
            doc /* Meaning: Receive passband width associated with mode. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: unsigned width: 1. Owner: physicalRadio/model definition. Context: channel_cap record context. Source: include/hamlib/rig.h:1704. */
        }
        attribute 'hamlib.struct.channel_cap.tx_freq' : Boolean[0..1] {
            doc /* Meaning: Transmit frequency. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: unsigned tx_freq: 1. Owner: physicalRadio/model definition. Context: channel_cap record context. Source: include/hamlib/rig.h:1706. */
        }
        attribute 'hamlib.struct.channel_cap.tx_mode' : Boolean[0..1] {
            doc /* Meaning: Transmit mode. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: unsigned tx_mode: 1. Owner: physicalRadio/model definition. Context: channel_cap record context. Source: include/hamlib/rig.h:1707. */
        }
        attribute 'hamlib.struct.channel_cap.tx_width' : Boolean[0..1] {
            doc /* Meaning: Transmit passband width associated with mode. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: unsigned tx_width: 1. Owner: physicalRadio/model definition. Context: channel_cap record context. Source: include/hamlib/rig.h:1708. */
        }
        attribute 'hamlib.struct.channel_cap.split' : Boolean[0..1] {
            doc /* Meaning: Split mode. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: unsigned split: 1. Owner: physicalRadio/model definition. Context: channel_cap record context. Source: include/hamlib/rig.h:1710. */
        }
        attribute 'hamlib.struct.channel_cap.tx_vfo' : Boolean[0..1] {
            doc /* Meaning: Split transmit VFO. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: unsigned tx_vfo: 1. Owner: physicalRadio/model definition. Context: channel_cap record context. Source: include/hamlib/rig.h:1711. */
        }
        attribute 'hamlib.struct.channel_cap.rptr_shift' : Boolean[0..1] {
            doc /* Meaning: Repeater shift. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: unsigned rptr_shift: 1. Owner: physicalRadio/model definition. Context: channel_cap record context. Source: include/hamlib/rig.h:1712. */
        }
        attribute 'hamlib.struct.channel_cap.rptr_offs' : Boolean[0..1] {
            doc /* Meaning: Repeater offset. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: unsigned rptr_offs: 1. Owner: physicalRadio/model definition. Context: channel_cap record context. Source: include/hamlib/rig.h:1713. */
        }
        attribute 'hamlib.struct.channel_cap.tuning_step' : Boolean[0..1] {
            doc /* Meaning: Tuning step. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: unsigned tuning_step: 1. Owner: physicalRadio/model definition. Context: channel_cap record context. Source: include/hamlib/rig.h:1714. */
        }
        attribute 'hamlib.struct.channel_cap.rit' : Boolean[0..1] {
            doc /* Meaning: RIT. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: unsigned rit: 1. Owner: physicalRadio/model definition. Context: channel_cap record context. Source: include/hamlib/rig.h:1715. */
        }
        attribute 'hamlib.struct.channel_cap.xit' : Boolean[0..1] {
            doc /* Meaning: XIT. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: unsigned xit: 1. Owner: physicalRadio/model definition. Context: channel_cap record context. Source: include/hamlib/rig.h:1716. */
        }
        attribute 'hamlib.struct.channel_cap.funcs' : Integer[0..1] {
            doc /* Meaning: Function status. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: setting_t funcs. Owner: physicalRadio/model definition. Context: channel_cap record context. Source: include/hamlib/rig.h:1717. */
        }
        attribute 'hamlib.struct.channel_cap.levels' : Integer[0..1] {
            doc /* Meaning: Level values. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: setting_t levels. Owner: physicalRadio/model definition. Context: channel_cap record context. Source: include/hamlib/rig.h:1718. */
        }
        attribute 'hamlib.struct.channel_cap.ctcss_tone' : Boolean[0..1] {
            doc /* Meaning: CTCSS tone. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: unsigned ctcss_tone: 1. Owner: physicalRadio/model definition. Context: channel_cap record context. Source: include/hamlib/rig.h:1719. */
        }
        attribute 'hamlib.struct.channel_cap.ctcss_sql' : Boolean[0..1] {
            doc /* Meaning: CTCSS squelch tone. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: unsigned ctcss_sql: 1. Owner: physicalRadio/model definition. Context: channel_cap record context. Source: include/hamlib/rig.h:1720. */
        }
        attribute 'hamlib.struct.channel_cap.dcs_code' : Boolean[0..1] {
            doc /* Meaning: DCS code. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: unsigned dcs_code: 1. Owner: physicalRadio/model definition. Context: channel_cap record context. Source: include/hamlib/rig.h:1721. */
        }
        attribute 'hamlib.struct.channel_cap.dcs_sql' : Boolean[0..1] {
            doc /* Meaning: DCS squelch code. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: unsigned dcs_sql: 1. Owner: physicalRadio/model definition. Context: channel_cap record context. Source: include/hamlib/rig.h:1722. */
        }
        attribute 'hamlib.struct.channel_cap.scan_group' : Boolean[0..1] {
            doc /* Meaning: Scan group. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: unsigned scan_group: 1. Owner: physicalRadio/model definition. Context: channel_cap record context. Source: include/hamlib/rig.h:1723. */
        }
        attribute 'hamlib.struct.channel_cap.flags' : Boolean[0..1] {
            doc /* Meaning: Channel flags. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: unsigned flags: 1. Owner: physicalRadio/model definition. Context: channel_cap record context. Source: include/hamlib/rig.h:1724. */
        }
        attribute 'hamlib.struct.channel_cap.channel_desc' : Boolean[0..1] {
            doc /* Meaning: Name. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: unsigned channel_desc: 1. Owner: physicalRadio/model definition. Context: channel_cap record context. Source: include/hamlib/rig.h:1725. */
        }
        attribute 'hamlib.struct.channel_cap.ext_levels' : Boolean[0..1] {
            doc /* Meaning: Extension level value list. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: unsigned ext_levels: 1. Owner: physicalRadio/model definition. Context: channel_cap record context. Source: include/hamlib/rig.h:1726. */
        }
        attribute 'hamlib.struct.channel_cap.tag' : Boolean[0..1] {
            doc /* Meaning: Has tag field e.g. FT991. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: unsigned tag: 1. Owner: physicalRadio/model definition. Context: channel_cap record context. Source: include/hamlib/rig.h:1727. */
        }
    }
    attribute def HamlibChannelProperties {
        doc /* RIG_SETTING_MAX=64 (rig.h1286) bounds the source value_t levels array
             declared at rig.h1675; no active union member or data value is invented. */
        attribute 'hamlib.struct.channel.channel_num' : Integer[0..1] {
            doc /* Meaning: Channel number. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int channel_num. Owner: physicalRadio/model definition. Context: channel record context. Source: include/hamlib/rig.h:1654. */
        }
        attribute 'hamlib.struct.channel.bank_num' : Integer[0..1] {
            doc /* Meaning: Bank number. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int bank_num. Owner: physicalRadio/model definition. Context: channel record context. Source: include/hamlib/rig.h:1655. */
        }
        attribute 'hamlib.struct.channel.vfo' : Integer[0..1] {
            doc /* Meaning: VFO. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: vfo_t vfo. Owner: physicalRadio/model definition. Context: channel record context. Source: include/hamlib/rig.h:1656. */
        }
        attribute 'hamlib.struct.channel.ant' : Integer[0..1] {
            doc /* Meaning: Selected antenna. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: ant_t ant. Owner: physicalRadio/model definition. Context: channel record context. Source: include/hamlib/rig.h:1657. */
        }
        attribute 'hamlib.struct.channel.freq' : Real[0..1] {
            doc /* Meaning: Receive frequency. Unit: Hz. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: freq_t freq. Owner: physicalRadio/model definition. Context: channel record context. Source: include/hamlib/rig.h:1658. */
        }
        attribute 'hamlib.struct.channel.mode' : Integer[0..1] {
            doc /* Meaning: Receive mode. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: rmode_t mode. Owner: physicalRadio/model definition. Context: channel record context. Source: include/hamlib/rig.h:1659. */
        }
        attribute 'hamlib.struct.channel.width' : Integer[0..1] {
            doc /* Meaning: Receive passband width associated with mode. Unit: Hz. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: pbwidth_t width. Owner: physicalRadio/model definition. Context: channel record context. Source: include/hamlib/rig.h:1660. */
        }
        attribute 'hamlib.struct.channel.tx_freq' : Real[0..1] {
            doc /* Meaning: Transmit frequency. Unit: Hz. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: freq_t tx_freq. Owner: physicalRadio/model definition. Context: channel record context. Source: include/hamlib/rig.h:1662. */
        }
        attribute 'hamlib.struct.channel.tx_mode' : Integer[0..1] {
            doc /* Meaning: Transmit mode. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: rmode_t tx_mode. Owner: physicalRadio/model definition. Context: channel record context. Source: include/hamlib/rig.h:1663. */
        }
        attribute 'hamlib.struct.channel.tx_width' : Integer[0..1] {
            doc /* Meaning: Transmit passband width associated with mode. Unit: Hz. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: pbwidth_t tx_width. Owner: physicalRadio/model definition. Context: channel record context. Source: include/hamlib/rig.h:1664. */
        }
        attribute 'hamlib.struct.channel.split' : Integer[0..1] {
            doc /* Meaning: Split mode. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: split_t split. Owner: physicalRadio/model definition. Context: channel record context. Source: include/hamlib/rig.h:1666. */
        }
        attribute 'hamlib.struct.channel.tx_vfo' : Integer[0..1] {
            doc /* Meaning: Split transmit VFO. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: vfo_t tx_vfo. Owner: physicalRadio/model definition. Context: channel record context. Source: include/hamlib/rig.h:1667. */
        }
        attribute 'hamlib.struct.channel.rptr_shift' : Integer[0..1] {
            doc /* Meaning: Repeater shift. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: rptr_shift_t rptr_shift. Owner: physicalRadio/model definition. Context: channel record context. Source: include/hamlib/rig.h:1669. */
        }
        attribute 'hamlib.struct.channel.rptr_offs' : Integer[0..1] {
            doc /* Meaning: Repeater offset. Unit: Hz. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: shortfreq_t rptr_offs. Owner: physicalRadio/model definition. Context: channel record context. Source: include/hamlib/rig.h:1670. */
        }
        attribute 'hamlib.struct.channel.tuning_step' : Integer[0..1] {
            doc /* Meaning: Tuning step. Unit: Hz. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: shortfreq_t tuning_step. Owner: physicalRadio/model definition. Context: channel record context. Source: include/hamlib/rig.h:1671. */
        }
        attribute 'hamlib.struct.channel.rit' : Integer[0..1] {
            doc /* Meaning: RIT. Unit: Hz. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: shortfreq_t rit. Owner: physicalRadio/model definition. Context: channel record context. Source: include/hamlib/rig.h:1672. */
        }
        attribute 'hamlib.struct.channel.xit' : Integer[0..1] {
            doc /* Meaning: XIT. Unit: Hz. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: shortfreq_t xit. Owner: physicalRadio/model definition. Context: channel record context. Source: include/hamlib/rig.h:1673. */
        }
        attribute 'hamlib.struct.channel.funcs' : Integer[0..1] {
            doc /* Meaning: Function status. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: setting_t funcs. Owner: physicalRadio/model definition. Context: channel record context. Source: include/hamlib/rig.h:1674. */
        }
        attribute 'hamlib.struct.channel.levels' : HamlibUnresolvedProperty[0..64] {
            doc /* Meaning: Level values. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: value_t levels[RIG_SETTING_MAX]. Owner: physicalRadio/model definition. Context: channel record context. Source: include/hamlib/rig.h:1675. */
        }
        attribute 'hamlib.struct.channel.ctcss_tone' : Integer[0..1] {
            doc /* Meaning: CTCSS tone. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: tone_t ctcss_tone. Owner: physicalRadio/model definition. Context: channel record context. Source: include/hamlib/rig.h:1676. */
        }
        attribute 'hamlib.struct.channel.ctcss_sql' : Integer[0..1] {
            doc /* Meaning: CTCSS squelch tone. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: tone_t ctcss_sql. Owner: physicalRadio/model definition. Context: channel record context. Source: include/hamlib/rig.h:1677. */
        }
        attribute 'hamlib.struct.channel.dcs_code' : Integer[0..1] {
            doc /* Meaning: DCS code. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: tone_t dcs_code. Owner: physicalRadio/model definition. Context: channel record context. Source: include/hamlib/rig.h:1678. */
        }
        attribute 'hamlib.struct.channel.dcs_sql' : Integer[0..1] {
            doc /* Meaning: DCS squelch code. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: tone_t dcs_sql. Owner: physicalRadio/model definition. Context: channel record context. Source: include/hamlib/rig.h:1679. */
        }
        attribute 'hamlib.struct.channel.scan_group' : Integer[0..1] {
            doc /* Meaning: Scan group. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int scan_group. Owner: physicalRadio/model definition. Context: channel record context. Source: include/hamlib/rig.h:1680. */
        }
        attribute 'hamlib.struct.channel.flags' : Integer[0..1] {
            doc /* Meaning: Channel flags, see RIG_CHFLAG's. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: unsigned int flags. Owner: physicalRadio/model definition. Context: channel record context. Source: include/hamlib/rig.h:1681. */
        }
        attribute 'hamlib.struct.channel.channel_desc' : String[0..1] {
            doc /* Meaning: Name. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: char channel_desc[HAMLIB_MAXCHANDESC]. Owner: physicalRadio/model definition. Context: channel record context. Source: include/hamlib/rig.h:1682. */
        }
        attribute 'hamlib.struct.channel.ext_levels' : HamlibExtListProperties[*] {
            doc /* Meaning: Extension level value list, NULL ended. ext_levels can be NULL. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: struct ext_list *ext_levels. Owner: physicalRadio/model definition. Context: channel record context. Source: include/hamlib/rig.h:1683. */
        }
        attribute 'hamlib.struct.channel.tag' : String[0..1] {
            doc /* Meaning: TAG ASCII for channel name, etc. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: char tag[32]. Owner: physicalRadio/model definition. Context: channel record context. Source: include/hamlib/rig.h:1685. */
        }
    }
    attribute def HamlibConnectionProperties {
        attribute 'hamlib.extension.rigs/anytone/d578.c::anytone_cfg_params::TOK_COMMODE' : Boolean[0..1] {
            doc /* Meaning: Enable ADATA/COM MODE for freq/vfo/clock (locks radio display). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/anytone/d578.c:40. */
        }
        attribute 'hamlib.extension.rigs/dummy/dummy.c::dummy_cfg_params::TOK_CFG_MAGICCONF' : String[0..1] {
            doc /* Meaning: Magic parameter, as an example. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_STRING. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/dummy/dummy.c:100. */
        }
        attribute 'hamlib.extension.rigs/dummy/dummy.c::dummy_cfg_params::TOK_CFG_STATIC_DATA' : Boolean[0..1] {
            doc /* Meaning: Output only static data, no randomization of meter values. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/dummy/dummy.c:104. */
        }
        attribute 'hamlib.extension.rigs/dummy/dummy.c::dummy_cfg_params::TOK_CFG_STREAM_IQ_OFFSET' : Real[0..1] {
            doc /* Meaning: I/Q offset frequency in Hz. Unit: Hz. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/dummy/dummy.c:120. */
        }
        attribute 'hamlib.extension.rigs/dummy/dummy.c::dummy_cfg_params::TOK_CFG_STREAM_MODE' : String[0..1] {
            doc /* Meaning: Streaming mode: tone, silence, or loopback. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_STRING. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/dummy/dummy.c:108. */
        }
        attribute 'hamlib.extension.rigs/dummy/dummy.c::dummy_cfg_params::TOK_CFG_STREAM_SYNTH_GAP' : Real[0..1] {
            doc /* Meaning: Inject one RX gap of N samples for testing (0 = off). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/dummy/dummy.c:124. */
        }
        attribute 'hamlib.extension.rigs/dummy/dummy.c::dummy_cfg_params::TOK_CFG_STREAM_TONE_AMP' : Real[0..1] {
            doc /* Meaning: Tone amplitude 0.0 to 1.0. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/dummy/dummy.c:116. */
        }
        attribute 'hamlib.extension.rigs/dummy/dummy.c::dummy_cfg_params::TOK_CFG_STREAM_TONE_FREQ' : Real[0..1] {
            doc /* Meaning: Audio tone frequency in Hz. Unit: Hz. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/dummy/dummy.c:112. */
        }
        attribute 'hamlib.extension.rigs/elad/elad.c::elad_cfg_params::TOK_FINE' : Boolean[0..1] {
            doc /* Meaning: Fine step mode. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/elad/elad.c:129. */
        }
        attribute 'hamlib.extension.rigs/elad/elad.c::elad_cfg_params::TOK_RIT' : Boolean[0..1] {
            doc /* Meaning: RIT. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/elad/elad.c:141. */
        }
        attribute 'hamlib.extension.rigs/elad/elad.c::elad_cfg_params::TOK_VOICE' : RadioInteractionDefinition[0..1] {
            doc /* Meaning: Voice recall. Unit: unspecified; do not infer units. Access/role: action/button; not a persistent Boolean state.
                 Source type: RIG_CONF_BUTTON. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/elad/elad.c:133. */
        }
        attribute 'hamlib.extension.rigs/elad/elad.c::elad_cfg_params::TOK_XIT' : Boolean[0..1] {
            doc /* Meaning: XIT. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/elad/elad.c:137. */
        }
        attribute 'hamlib.extension.rigs/flexradio/dttsp.c::dttsp_cfg_params::TOK_SAMPLE_RATE' : Real[0..1] {
            doc /* Meaning: DttSP sample rate in Spls/sec. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/flexradio/dttsp.c:107. */
        }
        attribute 'hamlib.extension.rigs/flexradio/dttsp.c::dttsp_cfg_params::TOK_TUNER_MODEL' : Real[0..1] {
            doc /* Meaning: Hamlib rig tuner model number. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/flexradio/dttsp.c:103. */
        }
        attribute 'hamlib.extension.rigs/icmarine/icm710.c::icm710_cfg_params::TOK_REMOTEID' : Real[0..1] {
            doc /* Meaning: Transceiver's remote ID. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/icmarine/icm710.c:241. */
        }
        attribute 'hamlib.extension.rigs/icmarine/icmarine.c::icmarine_cfg_params::TOK_REMOTEID' : Real[0..1] {
            doc /* Meaning: Transceiver's remote ID. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/icmarine/icmarine.c:103. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_cfg_params::TOK_CIVADDR' : Real[0..1] {
            doc /* Meaning: Transceiver's CI-V address. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/icom/icom.c:400. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_cfg_params::TOK_FILTER_CW' : Real[0..1] {
            doc /* Meaning: Filter to use for CW/CWR when setting mode. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/icom/icom.c:427. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_cfg_params::TOK_FILTER_FM' : Real[0..1] {
            doc /* Meaning: Filter to use for FM/PKTFM when setting mode. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/icom/icom.c:431. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_cfg_params::TOK_FILTER_USB' : Real[0..1] {
            doc /* Meaning: Filter to use when for USB/LSB setting mode. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/icom/icom.c:423. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_cfg_params::TOK_FILTER_USBD' : Real[0..1] {
            doc /* Meaning: Filter to use for USBD/LSBD when setting mode. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/icom/icom.c:419. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_cfg_params::TOK_MODE731' : Boolean[0..1] {
            doc /* Meaning: CI-V operating frequency data length, needed for IC731 and IC735. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/icom/icom.c:404. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_cfg_params::TOK_NOXCHG' : Boolean[0..1] {
            doc /* Meaning: Don't Use VFO XCHG to set other VFO mode and Frequency. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/icom/icom.c:409. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_cfg_params::TOK_TONE_ENABLE' : Boolean[0..1] {
            doc /* Meaning: Overcome a bug in IC-705 to enable tone after frequency change. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/icom/icom.c:414. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts480.c::malachite_cfg_parms::TOK_NO_ID' : Boolean[0..1] {
            doc /* Meaning: If true do not send ID; with set commands. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/kenwood/ts480.c:2533. */
        }
        attribute 'hamlib.extension.rigs/kit/dds60.c::dds60_cfg_params::TOK_IFMIXFREQ' : Real[0..1] {
            doc /* Meaning: IF mixing frequency in Hz. Unit: Hz. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/kit/dds60.c:65. */
        }
        attribute 'hamlib.extension.rigs/kit/dds60.c::dds60_cfg_params::TOK_MULTIPLIER' : Boolean[0..1] {
            doc /* Meaning: Optional X6 multiplier. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/kit/dds60.c:69. */
        }
        attribute 'hamlib.extension.rigs/kit/dds60.c::dds60_cfg_params::TOK_OSCFREQ' : Real[0..1] {
            doc /* Meaning: Oscillator frequency in Hz. Unit: Hz. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/kit/dds60.c:61. */
        }
        attribute 'hamlib.extension.rigs/kit/drt1.c::drt1_cfg_params::TOK_IFMIXFREQ' : Real[0..1] {
            doc /* Meaning: IF mixing frequency in Hz. Unit: Hz. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/kit/drt1.c:65. */
        }
        attribute 'hamlib.extension.rigs/kit/drt1.c::drt1_cfg_params::TOK_OSCFREQ' : Real[0..1] {
            doc /* Meaning: Oscillator frequency in Hz. Unit: Hz. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/kit/drt1.c:61. */
        }
        attribute 'hamlib.extension.rigs/kit/drt1.c::drt1_cfg_params::TOK_PUMPCRNT' : Real[0..1] {
            doc /* Meaning: Charge pump current in uA. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/kit/drt1.c:73. */
        }
        attribute 'hamlib.extension.rigs/kit/drt1.c::drt1_cfg_params::TOK_REFMULT' : Real[0..1] {
            doc /* Meaning: REFCLK Multiplier. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/kit/drt1.c:69. */
        }
        attribute 'hamlib.extension.rigs/kit/elektor304.c::elektor304_cfg_params::TOK_IFMIXFREQ' : Real[0..1] {
            doc /* Meaning: IF mixing frequency in Hz. Unit: Hz. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/kit/elektor304.c:59. */
        }
        attribute 'hamlib.extension.rigs/kit/elektor304.c::elektor304_cfg_params::TOK_OSCFREQ' : Real[0..1] {
            doc /* Meaning: Oscillator frequency in Hz. Unit: Hz. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/kit/elektor304.c:55. */
        }
        attribute 'hamlib.extension.rigs/kit/elektor507.c::elektor507_cfg_params::TOK_OSCFREQ' : Real[0..1] {
            doc /* Meaning: Oscillator frequency in Hz. Unit: Hz. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/kit/elektor507.c:181. */
        }
        attribute 'hamlib.extension.rigs/kit/elektor507.c::elektor507_cfg_params::TOK_XTALCAL' : Real[0..1] {
            doc /* Meaning: Crystal calibration. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/kit/elektor507.c:185. */
        }
        attribute 'hamlib.extension.rigs/kit/hiqsdr.c::hiqsdr_cfg_params::TOK_OSCFREQ' : Real[0..1] {
            doc /* Meaning: Oscillator frequency of reference clock in Hz. Unit: Hz. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/kit/hiqsdr.c:76. */
        }
        attribute 'hamlib.extension.rigs/kit/hiqsdr.c::hiqsdr_cfg_params::TOK_SAMPLE_RATE' : Real[0..1] {
            doc /* Meaning: Sample rate. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/kit/hiqsdr.c:80. */
        }
        attribute 'hamlib.extension.rigs/kit/si570avrusb.c::si570xxxusb_cfg_params::TOK_BPF' : Boolean[0..1] {
            doc /* Meaning: Enable Band Pass Filter. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/kit/si570avrusb.c:107. */
        }
        attribute 'hamlib.extension.rigs/kit/si570avrusb.c::si570xxxusb_cfg_params::TOK_I2C_ADDR' : Real[0..1] {
            doc /* Meaning: Si570 I2C Address. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/kit/si570avrusb.c:103. */
        }
        attribute 'hamlib.extension.rigs/kit/si570avrusb.c::si570xxxusb_cfg_params::TOK_MULTIPLIER' : Real[0..1] {
            doc /* Meaning: Frequency multiplier. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/kit/si570avrusb.c:99. */
        }
        attribute 'hamlib.extension.rigs/kit/si570avrusb.c::si570xxxusb_cfg_params::TOK_OSCFREQ' : Real[0..1] {
            doc /* Meaning: Oscillator frequency in Hz. Unit: Hz. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/kit/si570avrusb.c:95. */
        }
        attribute 'hamlib.extension.rigs/kit/usrp.c::usrp_cfg_params::TOK_IFMIXFREQ' : Real[0..1] {
            doc /* Meaning: IF mixing frequency in Hz. Unit: Hz. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/kit/usrp.c:52. */
        }
        attribute 'hamlib.extension.rigs/racal/ra37xx.c::ra37xx_cfg_params::TOK_RIGID' : Real[0..1] {
            doc /* Meaning: receiver ID, -1 to disable addressing. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/racal/ra37xx.c:36. */
        }
        attribute 'hamlib.extension.rigs/racal/racal.c::racal_cfg_params::TOK_RIGID' : Real[0..1] {
            doc /* Meaning: receiver ID. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/racal/racal.c:37. */
        }
        attribute 'hamlib.extension.rigs/tci/tci2.c::tci2_cfg_params::RIG_CONF_END' : String[0..1] {
            doc /* Meaning: NULL. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_STRING. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/tci/tci2.c:245. */
        }
        attribute 'hamlib.extension.rigs/tci/tci2.c::tci2_cfg_params::TOK_TCI2_DIGL_OFFSET' : Integer[0..1] {
            doc /* Meaning: Frequency offset for DIGL (digital lower sideband) mode, Hz (0..4000). Sent to the server on connect.. Unit: Hz. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_INT. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/tci/tci2.c:233. */
        }
        attribute 'hamlib.extension.rigs/tci/tci2.c::tci2_cfg_params::TOK_TCI2_DIGU_OFFSET' : Integer[0..1] {
            doc /* Meaning: Frequency offset for DIGU (digital upper sideband) mode, Hz (0..4000). Sent to the server on connect.. Unit: Hz. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_INT. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/tci/tci2.c:239. */
        }
        attribute 'hamlib.extension.rigs/tci/tci2.c::tci2_cfg_params::TOK_TCI2_TRX' : Integer[0..1] {
            doc /* Meaning: TCI transceiver (receiver) index (0-based). Selects which TRX to control on multi-receiver hardware (e.g. SunSDR2 DX has two).. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_INT. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/tci/tci2.c:220. */
        }
        attribute 'hamlib.extension.rigs/tci/tci2.c::tci2_cfg_params::TOK_TCI2_TXSRC' : String[0..1] {
            doc /* Meaning: Audio source used when keying TX: default, mic, or vac. Overridden per-PTT-call by RIG_PTT_ON_MIC (mic) and RIG_PTT_ON_DATA (vac).. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_STRING. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/tci/tci2.c:227. */
        }
        attribute 'hamlib.extension.rigs/tentec/rx331.c::rx331_cfg_params::TOK_RIGID' : Real[0..1] {
            doc /* Meaning: receiver ID. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/tentec/rx331.c:35. */
        }
        attribute 'hamlib.extension.rigs/winradio/g313-posix.c::g313_cfg_params::TOK_SHM_AUDIO' : String[0..1] {
            doc /* Meaning: POSIX shared memory path name to the audio ringbuffer. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_STRING. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/winradio/g313-posix.c:53. */
        }
        attribute 'hamlib.extension.rigs/winradio/g313-posix.c::g313_cfg_params::TOK_SHM_IF' : String[0..1] {
            doc /* Meaning: POSIX shared memory path name to the I/F ringbuffer. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_STRING. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/winradio/g313-posix.c:58. */
        }
        attribute 'hamlib.extension.rigs/winradio/g313-posix.c::g313_cfg_params::TOK_SHM_SPECTRUM' : String[0..1] {
            doc /* Meaning: POSIX shared memory path name to the spectrum ringbuffer. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_STRING. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/winradio/g313-posix.c:63. */
        }
        attribute 'hamlib.extension.rigs/winradio/g313-win.c::g313_cfg_params::WAVEOUT_SOUNDCARDID' : Real[0..1] {
            doc /* Meaning: Sound card device ID for playing IF signal from receiver. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/winradio/g313-win.c:52. */
        }
        attribute 'hamlib.extension.rigs/wj/wj.c::wj_cfg_params::TOK_RIGID' : Real[0..1] {
            doc /* Meaning: receiver ID. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/wj/wj.c:39. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft757gx.c::ft757gx_cfg_params::TOK_FAKEFREQ' : Boolean[0..1] {
            doc /* Meaning: Fake getting freq. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/yaesu/ft757gx.c:102. */
        }
        attribute 'hamlib.extension.rigs/yaesu/newcat.c::newcat_cfg_params::TOK_FAST_SET_CMD' : Real[0..1] {
            doc /* Meaning: Enabled high throughput of >200 messages/sec by not waiting for ACK/NAK of messages. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: rigs/yaesu/newcat.c:615. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_ASYNC' : Boolean[0..1] {
            doc /* Meaning: True enables async data for rigs that support it to allow use of transceive and spectrum data. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:253. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_AUTO_DISABLE_SCREENSAVER' : Boolean[0..1] {
            doc /* Meaning: True enables compatible rigs to have their screen saver disabled on open. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:223. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_AUTO_POWER_OFF' : Boolean[0..1] {
            doc /* Meaning: True enables compatible rigs to be powered down on close. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:218. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_AUTO_POWER_ON' : Boolean[0..1] {
            doc /* Meaning: True enables compatible rigs to be powered up on open. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:213. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_CACHE_TIMEOUT' : Real[0..1] {
            doc /* Meaning: Cache timeout, value of 0 disables caching. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:144. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_CLIENT' : Boolean[0..1] {
            doc /* Meaning: Knows about WSJTX and GPREDICT as of 20240702. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:298. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_DCD_PATHNAME' : String[0..1] {
            doc /* Meaning: Path to the device of the Data Carrier Detect (or squelch). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_STRING. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:134. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_DCD_TYPE' : String[0..1] {
            doc /* Meaning: Data Carrier Detect (or squelch) interface type override. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:129. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_DEVICE_ID' : String[0..1] {
            doc /* Meaning: User-specified device ID for multicast state data and commands. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_STRING. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:96. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_DISABLE_YAESU_BANDSELECT' : Boolean[0..1] {
            doc /* Meaning: True disables the automatic band select on band change for Yaesu rigs. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:228. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_FLUSHX' : Boolean[0..1] {
            doc /* Meaning: True enables flushing serial port with read instead of TCFLUSH -- MicroHam. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:238. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_FREQ_SKIP' : Boolean[0..1] {
            doc /* Meaning: True enables skipping setting the TX_VFO when RX_VFO is receiving and skips RX_VFO when TX_VFO is transmitting. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:293. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_LO_FREQ' : Real[0..1] {
            doc /* Meaning: Frequency to add to the VFO frequency for use with a transverter. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:139. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_MULTICAST_CMD_ADDR' : String[0..1] {
            doc /* Meaning: Multicast command UDP address for sending commands to rig, value of 0.0.0.0 disables multicast command server. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_STRING. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:283. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_MULTICAST_CMD_PORT' : Real[0..1] {
            doc /* Meaning: Multicast data UDP port for sending commands to rig. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:288. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_MULTICAST_DATA_ADDR' : String[0..1] {
            doc /* Meaning: Multicast data UDP address for publishing rig data and state, value of 0.0.0.0 disables multicast data publishing. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_STRING. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:273. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_MULTICAST_DATA_PORT' : Real[0..1] {
            doc /* Meaning: Multicast data UDP port for publishing rig data and state. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:278. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_OFFSET_VFOA' : Real[0..1] {
            doc /* Meaning: Add Hz to VFOA/Main frequency set. Unit: Hz. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:263. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_OFFSET_VFOB' : Real[0..1] {
            doc /* Meaning: Add Hz to VFOB/Sub frequency set. Unit: Hz. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:268. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_PATHNAME' : String[0..1] {
            doc /* Meaning: Path name to the device file of the rig. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_STRING. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:53. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_POLL_INTERVAL' : Real[0..1] {
            doc /* Meaning: Maximum interval between multicast state keepalives; changes may publish sooner, defaults to 1000, value of 0 disables publication. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:107. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_POST_PTT_DELAY' : Real[0..1] {
            doc /* Meaning: Delay in ms after PTT is asserted. Unit: ms. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:68. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_POST_WRITE_DELAY' : Real[0..1] {
            doc /* Meaning: Delay in ms between each command sent out. Unit: ms. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:63. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_PTT_BITNUM' : Real[0..1] {
            doc /* Meaning: Push-To-Talk GPIO bit number. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:124. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_PTT_PATHNAME' : String[0..1] {
            doc /* Meaning: Path to the device of the Push-To-Talk. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_STRING. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:119. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_PTT_SHARE' : Boolean[0..1] {
            doc /* Meaning: True enables ptt port to be shared with other apps. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:233. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_PTT_TYPE' : String[0..1] {
            doc /* Meaning: Push-To-Talk interface type override. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:114. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_RANGE_NAME' : String[0..1] {
            doc /* Meaning: The tx/rx range list name in use. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_STRING. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:91. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_RANGE_SELECTED' : Real[0..1] {
            doc /* Meaning: The tx/rx range list number in use. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:86. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_RETRY' : Real[0..1] {
            doc /* Meaning: Max number of retry. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:77. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_STREAM_KEEPALIVE_INTERVAL' : Real[0..1] {
            doc /* Meaning: Must stay well below stream_keepalive_timeout, since the ratio of the two is how many lost pings a stream survives; 0 selects the built-in default. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:205. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_STREAM_KEEPALIVE_TIMEOUT' : Real[0..1] {
            doc /* Meaning: Raise it on a lossy link so consecutive lost pings do not end the stream; 0 selects the built-in default. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:191. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_STREAM_METADATA_INTERVAL' : Real[0..1] {
            doc /* Meaning: Default for all streams; 0 selects the built-in default. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:179. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_STREAM_METADATA_REFRESH' : Real[0..1] {
            doc /* Meaning: Default for all streams; 0 selects the built-in default. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:173. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_STREAM_RESAMPLE_QUALITY' : String[0..1] {
            doc /* Meaning: libsamplerate sinc converter for stream rate conversion, applied to pipelines created after the change. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:198. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_STREAM_SOURCE_ID' : Real[0..1] {
            doc /* Meaning: -1 derives a stable ID from static configuration; 0 emits unset. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:185. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_STREAM_TIME_STALE_COARSE' : Real[0..1] {
            doc /* Meaning: Default for all streams; 0 selects the built-in default (1000 ms). Unit: ms. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:149. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_STREAM_TIME_STALE_INVALIDATE' : Real[0..1] {
            doc /* Meaning: Default for all streams; 0 selects the built-in default (5000 ms). Unit: ms. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:155. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_STREAM_TRANSPORT_BUFFER_BYTES' : Real[0..1] {
            doc /* Meaning: Default for all streams; 0 derives the size from the stream rate. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:167. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_STREAM_TRANSPORT_BUFFER_MS' : Real[0..1] {
            doc /* Meaning: Default for all streams; 0 selects the built-in default (250 ms). Unit: ms. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:161. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_TIMEOUT' : Real[0..1] {
            doc /* Meaning: Timeout in ms. Unit: ms. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:73. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_TIMEOUT_RETRY' : Real[0..1] {
            doc /* Meaning: Set the # of retries for read timeouts that may occur with some serial interfaces. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:81. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_TUNER_CONTROL_PATHNAME' : String[0..1] {
            doc /* Meaning: Path to a program to control a tuner with 1 argument of 0/1 for Tuner Off/On. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_STRING. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:258. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_TWIDDLE_RIT' : String[0..1] {
            doc /* Meaning: Suppress get_freq on VFOB for RIT tuning satellites. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:248. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_TWIDDLE_TIMEOUT' : Real[0..1] {
            doc /* Meaning: For satellite ops when VFOB is twiddled will pause VFOB commands until timeout. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:243. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_VFO_COMP' : Real[0..1] {
            doc /* Meaning: VFO compensation in ppm. Unit: ppm. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:102. */
        }
        attribute 'hamlib.extension.src/conf.c::frontend_cfg_params::TOK_WRITE_DELAY' : Real[0..1] {
            doc /* Meaning: Delay in ms between each byte sent out. Unit: ms. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: RadioControlConnection/backend. Context: backend-defined; may be global or VFO. Source: src/conf.c:58. */
        }
    }
    attribute def HamlibExtListProperties {
        attribute 'hamlib.struct.ext_list.token' : Integer[0..1] {
            doc /* Meaning: Token ID. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: hamlib_token_t token. Owner: physicalRadio/model definition. Context: ext_list record context. Source: include/hamlib/rig.h:1637. */
        }
        attribute 'hamlib.struct.ext_list.val' : HamlibUnresolvedProperty[0..1] {
            doc /* Meaning: Value. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: value_t val. Owner: physicalRadio/model definition. Context: ext_list record context. Source: include/hamlib/rig.h:1638. */
        }
    }
    attribute def HamlibFilterListProperties {
        attribute 'hamlib.struct.filter_list.modes' : Integer[0..1] {
            doc /* Meaning: Bit field of RIG_MODE's. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: rmode_t modes. Owner: physicalRadio/model definition. Context: filter_list record context. Source: include/hamlib/rig.h:1604. */
        }
        attribute 'hamlib.struct.filter_list.width' : Integer[0..1] {
            doc /* Meaning: Passband width in Hz. Unit: Hz. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: pbwidth_t width. Owner: physicalRadio/model definition. Context: filter_list record context. Source: include/hamlib/rig.h:1605. */
        }
    }
    attribute def HamlibFreqRangeListProperties {
        attribute 'hamlib.struct.freq_range_list.startf' : Real[0..1] {
            doc /* Meaning: Start frequency. Unit: Hz. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: freq_t startf. Owner: physicalRadio/model definition. Context: freq_range_list record context. Source: include/hamlib/rig.h:1537. */
        }
        attribute 'hamlib.struct.freq_range_list.endf' : Real[0..1] {
            doc /* Meaning: End frequency. Unit: Hz. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: freq_t endf. Owner: physicalRadio/model definition. Context: freq_range_list record context. Source: include/hamlib/rig.h:1538. */
        }
        attribute 'hamlib.struct.freq_range_list.modes' : Integer[0..1] {
            doc /* Meaning: Bit field of RIG_MODE's. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: rmode_t modes. Owner: physicalRadio/model definition. Context: freq_range_list record context. Source: include/hamlib/rig.h:1539. */
        }
        attribute 'hamlib.struct.freq_range_list.low_power' : Integer[0..1] {
            doc /* Meaning: Lower RF power in mW, -1 for no power (ie. rx list). Unit: mW. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int low_power. Owner: physicalRadio/model definition. Context: freq_range_list record context. Source: include/hamlib/rig.h:1540. */
        }
        attribute 'hamlib.struct.freq_range_list.high_power' : Integer[0..1] {
            doc /* Meaning: Higher RF power in mW, -1 for no power (ie. rx list). Unit: mW. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int high_power. Owner: physicalRadio/model definition. Context: freq_range_list record context. Source: include/hamlib/rig.h:1541. */
        }
        attribute 'hamlib.struct.freq_range_list.vfo' : Integer[0..1] {
            doc /* Meaning: VFO list equipped with this range. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: vfo_t vfo. Owner: physicalRadio/model definition. Context: freq_range_list record context. Source: include/hamlib/rig.h:1542. */
        }
        attribute 'hamlib.struct.freq_range_list.ant' : Integer[0..1] {
            doc /* Meaning: Antenna list equipped with this range, 0 means all, RIG_ANT_CURR means dedicated to certain bands and automatically switches, no set_ant command. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: ant_t ant. Owner: physicalRadio/model definition. Context: freq_range_list record context. Source: include/hamlib/rig.h:1543. */
        }
    }
    attribute def HamlibFunctionProperties {
        doc /* Generic RIG_FUNC status values retain the int status API domain from
             src/settings.c506. The descriptor shorthand boolean/int does not imply
             universal Boolean semantics: model-specific values such as Kenwood NR=2
             are valid in their declared context (kenwood.c4441..4450). Legal statuses,
             get/set support and any normalized Boolean view are per-model constraints;
             representing an Integer does not admit every Integer to every radio.
             Explicit RIG_CONF_CHECKBUTTON property types remain Boolean. */
        attribute 'hamlib.RIG_FUNC_ABM' : Integer[0..1] {
            doc /* Meaning: ABM -- Auto Band Mode. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1348. */
        }
        attribute 'hamlib.RIG_FUNC_AFC' : Integer[0..1] {
            doc /* Meaning: AFC -- Auto Frequency Control ON/OFF. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1352. */
        }
        attribute 'hamlib.RIG_FUNC_AFLT' : Integer[0..1] {
            doc /* Meaning: AFLT -- AF Filter setting. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1363. */
        }
        attribute 'hamlib.RIG_FUNC_AIP' : Integer[0..1] {
            doc /* Meaning: AIP -- RF pre-amp (AIP on Kenwood, IPO on Yaesu, etc.). Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1337. */
        }
        attribute 'hamlib.RIG_FUNC_ANF' : Integer[0..1] {
            doc /* Meaning: ANF -- Automatic Notch Filter (DSP). Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1335. */
        }
        attribute 'hamlib.RIG_FUNC_ANL' : Integer[0..1] {
            doc /* Meaning: ANL -- Noise limiter setting. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1364. */
        }
        attribute 'hamlib.RIG_FUNC_APF' : Integer[0..1] {
            doc /* Meaning: APF -- Audio Peak Filter. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1338. */
        }
        attribute 'hamlib.RIG_FUNC_ARO' : Integer[0..1] {
            doc /* Meaning: ARO -- Auto Repeater Offset. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1342. */
        }
        attribute 'hamlib.RIG_FUNC_BC' : Integer[0..1] {
            doc /* Meaning: BC -- Beat Canceller. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1349. */
        }
        attribute 'hamlib.RIG_FUNC_BC2' : Integer[0..1] {
            doc /* Meaning: BC2 -- 2nd Beat Cancel. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1365. */
        }
        attribute 'hamlib.RIG_FUNC_COMP' : Integer[0..1] {
            doc /* Meaning: COMP -- Speech Compression. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1329. */
        }
        attribute 'hamlib.RIG_FUNC_CSQL' : Integer[0..1] {
            doc /* Meaning: CSQL -- DCS Squelch setting. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1362. */
        }
        attribute 'hamlib.RIG_FUNC_DIVERSITY' : Integer[0..1] {
            doc /* Meaning: DIVERSITY -- Diversity receive. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1367. */
        }
        attribute 'hamlib.RIG_FUNC_DSQL' : Integer[0..1] {
            doc /* Meaning: DSQL -- Digital modes squelch. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1368. */
        }
        attribute 'hamlib.RIG_FUNC_DUAL_WATCH' : Integer[0..1] {
            doc /* Meaning: DUAL_WATCH -- Dual Watch / Sub Receiver. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1366. */
        }
        attribute 'hamlib.RIG_FUNC_FAGC' : Integer[0..1] {
            doc /* Meaning: FAGC -- Fast AGC. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1327. */
        }
        attribute 'hamlib.RIG_FUNC_FBKIN' : Integer[0..1] {
            doc /* Meaning: FBKIN -- Full Break-in (CW mode). Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1334. */
        }
        attribute 'hamlib.RIG_FUNC_LOCK' : Integer[0..1] {
            doc /* Meaning: LOCK -- Lock. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1343. */
        }
        attribute 'hamlib.RIG_FUNC_MBC' : Integer[0..1] {
            doc /* Meaning: MBC -- Manual Beat Canceller. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1350. */
        }
        attribute 'hamlib.RIG_FUNC_MN' : Integer[0..1] {
            doc /* Meaning: MN -- Manual Notch. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1340. */
        }
        attribute 'hamlib.RIG_FUNC_MON' : Integer[0..1] {
            doc /* Meaning: MON -- Monitor transmitted signal. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1339. */
        }
        attribute 'hamlib.RIG_FUNC_MUTE' : Integer[0..1] {
            doc /* Meaning: MUTE -- Mute. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1344. */
        }
        attribute 'hamlib.RIG_FUNC_NB' : Integer[0..1] {
            doc /* Meaning: NB -- Noise Blanker. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1328. */
        }
        attribute 'hamlib.RIG_FUNC_NB2' : Integer[0..1] {
            doc /* Meaning: NB2 -- 2nd Noise Blanker. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1361. */
        }
        attribute 'hamlib.RIG_FUNC_NR' : Integer[0..1] {
            doc /* Meaning: NR -- Noise Reduction (DSP). Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1336. */
        }
        attribute 'hamlib.RIG_FUNC_OVF_STATUS' : Integer[0..1] {
            doc /* Meaning: OVF_STATUS -- Read overflow status 0=Off, 1=On. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1376. */
        }
        attribute 'hamlib.RIG_FUNC_RESUME' : Integer[0..1] {
            doc /* Meaning: RESUME -- Scan auto-resume. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1355. */
        }
        attribute 'hamlib.RIG_FUNC_REV' : Integer[0..1] {
            doc /* Meaning: REV -- Reverse transmit and receive frequencies. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1346. */
        }
        attribute 'hamlib.RIG_FUNC_RF' : Integer[0..1] {
            doc /* Meaning: RF -- RTTY Filter. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1341. */
        }
        attribute 'hamlib.RIG_FUNC_RIT' : Integer[0..1] {
            doc /* Meaning: RIT -- Receiver Incremental Tuning. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1351. */
        }
        attribute 'hamlib.RIG_FUNC_SATMODE' : Integer[0..1] {
            doc /* Meaning: SATMODE -- Satellite mode ON/OFF. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1353. */
        }
        attribute 'hamlib.RIG_FUNC_SBKIN' : Integer[0..1] {
            doc /* Meaning: SBKIN -- Semi Break-in (CW mode). Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1333. */
        }
        attribute 'hamlib.RIG_FUNC_SCEN' : Integer[0..1] {
            doc /* Meaning: SCEN -- scrambler/encryption. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1369. */
        }
        attribute 'hamlib.RIG_FUNC_SCOPE' : Integer[0..1] {
            doc /* Meaning: SCOPE -- Simple bandscope ON/OFF. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1354. */
        }
        attribute 'hamlib.RIG_FUNC_SEND_MORSE' : Integer[0..1] {
            doc /* Meaning: SEND_MORSE -- Send specified characters using CW. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1374. */
        }
        attribute 'hamlib.RIG_FUNC_SEND_VOICE_MEM' : Integer[0..1] {
            doc /* Meaning: SEND_VOICE_MEM -- Transmit in SSB message stored in memory. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1375. */
        }
        attribute 'hamlib.RIG_FUNC_SLICE' : Integer[0..1] {
            doc /* Meaning: SLICE -- Rig slice selection -- Flex. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1370. */
        }
        attribute 'hamlib.RIG_FUNC_SPECTRUM' : Integer[0..1] {
            doc /* Meaning: SPECTRUM -- Spectrum scope data output ON/OFF. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1372. */
        }
        attribute 'hamlib.RIG_FUNC_SPECTRUM_HOLD' : Integer[0..1] {
            doc /* Meaning: SPECTRUM_HOLD -- Pause spectrum scope updates ON/OFF. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1373. */
        }
        attribute 'hamlib.RIG_FUNC_SQL' : Integer[0..1] {
            doc /* Meaning: SQL -- Turn Squelch Monitor on/off. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1347. */
        }
        attribute 'hamlib.RIG_FUNC_SYNC' : Integer[0..1] {
            doc /* Meaning: Synchronize VFOs -- Yaesu FTDX101 SY cmd, IC-7610 "Tracking". Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1377. */
        }
        attribute 'hamlib.RIG_FUNC_TBURST' : Integer[0..1] {
            doc /* Meaning: TBURST -- 1750 Hz tone burst. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1356. */
        }
        attribute 'hamlib.RIG_FUNC_TONE' : Integer[0..1] {
            doc /* Meaning: TONE -- CTCSS Tone TX. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1331. */
        }
        attribute 'hamlib.RIG_FUNC_TRANSCEIVE' : Integer[0..1] {
            doc /* Meaning: TRANSCEIVE -- Send radio state changes automatically ON/OFF. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1371. */
        }
        attribute 'hamlib.RIG_FUNC_TSQL' : Integer[0..1] {
            doc /* Meaning: TSQL -- CTCSS Activate/De-activate RX. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1332. */
        }
        attribute 'hamlib.RIG_FUNC_TUNER' : Integer[0..1] {
            doc /* Meaning: TUNER -- Enable automatic tuner. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1357. */
        }
        attribute 'hamlib.RIG_FUNC_VOX' : Integer[0..1] {
            doc /* Meaning: VOX -- Voice Operated Relay. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1330. */
        }
        attribute 'hamlib.RIG_FUNC_VSC' : Integer[0..1] {
            doc /* Meaning: VSC -- Voice Scan Control. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1345. */
        }
        attribute 'hamlib.RIG_FUNC_XIT' : Integer[0..1] {
            doc /* Meaning: XIT -- Transmitter Incremental Tuning. Unit: unspecified; do not infer units. Access/role: requested/observed setting; separate get/set availability.
                 Source type: boolean/int status. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1358. */
        }
    }
    attribute def HamlibGlobalParameterProperties {
        attribute 'hamlib.RIG_PARM_AFIF' : Integer[0..1] {
            doc /* Meaning: AFIF for USB -- 0=AF audio, 1=IF audio -- see IC-7300/9700/705. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: rig-global. Source: include/hamlib/rig.h:1222. */
        }
        attribute 'hamlib.RIG_PARM_AFIF_ACC' : Integer[0..1] {
            doc /* Meaning: AFIF_ACC -- 0=AF audio, 1=IF audio -- see IC-9700. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: rig-global. Source: include/hamlib/rig.h:1227. */
        }
        attribute 'hamlib.RIG_PARM_AFIF_LAN' : Integer[0..1] {
            doc /* Meaning: AFIF for LAN -- 0=AF audio , 1=IF audio -- see IC-9700. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: rig-global. Source: include/hamlib/rig.h:1225. */
        }
        attribute 'hamlib.RIG_PARM_AFIF_WLAN' : Integer[0..1] {
            doc /* Meaning: AFIF_WLAN -- 0=AF audio, 1=IF audio -- see IC-705. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: rig-global. Source: include/hamlib/rig.h:1226. */
        }
        attribute 'hamlib.RIG_PARM_ANN' : Integer[0..1] {
            doc /* Meaning: ANN -- "Announce" level, see #ann_t. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: rig-global. Source: include/hamlib/rig.h:1214. */
        }
        attribute 'hamlib.RIG_PARM_APO' : Integer[0..1] {
            doc /* Meaning: APO -- Auto power off, int in minute. Unit: min. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: rig-global. Source: include/hamlib/rig.h:1215. */
        }
        attribute 'hamlib.RIG_PARM_BACKLIGHT' : Real[0..1] {
            doc /* Meaning: BACKLIGHT -- LCD light, float [0.0 ... 1.0]. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: rig-global. Source: include/hamlib/rig.h:1216.
                 Source domain: ['[0.0 ... 1.0]']. */
        }
        attribute 'hamlib.RIG_PARM_BANDSELECT' : String[0..1] {
            doc /* Meaning: BANDSELECT -- e.g. BAND160M, BAND80M, BAND70CM, BAND2CM. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: string/value_t.s. Owner: physicalRadio. Context: rig-global. Source: include/hamlib/rig.h:1223. */
        }
        attribute 'hamlib.RIG_PARM_BAT' : Real[0..1] {
            doc /* Meaning: BAT -- battery level, float [0.0 ... 1.0]. Unit: unspecified; do not infer units. Access/role: read-only.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: rig-global. Source: include/hamlib/rig.h:1219.
                 Source domain: ['[0.0 ... 1.0]']. */
        }
        attribute 'hamlib.RIG_PARM_BEEP' : Integer[0..1] {
            doc /* Meaning: BEEP -- Beep on keypressed, int (0,1). Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: rig-global. Source: include/hamlib/rig.h:1217. */
        }
        attribute 'hamlib.RIG_PARM_KEYERTYPE' : String[0..1] {
            doc /* Meaning: KEYERTYPE -- Has multiple Morse keyer types, see #rig_keyertype_e. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: string/value_t.s. Owner: physicalRadio. Context: rig-global. Source: include/hamlib/rig.h:1224. */
        }
        attribute 'hamlib.RIG_PARM_KEYLIGHT' : Real[0..1] {
            doc /* Meaning: KEYLIGHT -- Button backlight, on/off. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: rig-global. Source: include/hamlib/rig.h:1220.
                 Public prose says on/off; RIG_PARM_FLOAT_LIST includes KEYLIGHT. Preserve source discrepancy rather than guess encoding. */
        }
        attribute 'hamlib.RIG_PARM_SCREENSAVER' : Integer[0..1] {
            doc /* Meaning: SCREENSAVER -- rig specific timeouts. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: rig-global. Source: include/hamlib/rig.h:1221. */
        }
        attribute 'hamlib.RIG_PARM_TIME' : Integer[0..1] {
            doc /* Meaning: TIME -- hh:mm:ss, int in seconds from 00:00:00. Unit: s. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: rig-global. Source: include/hamlib/rig.h:1218. */
        }
    }
    attribute def HamlibGranProperties {
        attribute 'hamlib.struct.gran.min' : HamlibUnresolvedProperty[0..1] {
            doc /* Meaning: Minimum value. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: value_t min. Owner: physicalRadio/model definition. Context: gran record context. Source: include/hamlib/rig.h:1809. */
        }
        attribute 'hamlib.struct.gran.max' : HamlibUnresolvedProperty[0..1] {
            doc /* Meaning: Maximum value. Unit: unspecified; do not infer units. Access/role: model parameter-domain/calibration metadata.
                 Source type: value_t max. Owner: physicalRadio/model definition. Context: gran record context. Source: include/hamlib/rig.h:1810. */
        }
        attribute 'hamlib.struct.gran.step' : HamlibUnresolvedProperty[0..1] {
            doc /* Meaning: Step. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: value_t step. Owner: physicalRadio/model definition. Context: gran record context. Source: include/hamlib/rig.h:1811. */
        }
    }
    attribute def HamlibHamlibPortProperties {
        attribute 'hamlib.struct.hamlib_port.ptt' : Integer[0..1] {
            doc /* Meaning: PTT port of #ptt_type_e type.. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: ptt_type_t ptt. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:54. */
        }
        attribute 'hamlib.struct.hamlib_port.dcd' : Integer[0..1] {
            doc /* Meaning: DCD port of #dcd_type_e type.. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: dcd_type_t dcd. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:55. */
        }
        attribute 'hamlib.struct.hamlib_port.type' : HamlibUnresolvedProperty[0..1] {
            doc /* Meaning: Type of port in use.. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: type. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:56. */
        }
        attribute 'hamlib.struct.hamlib_port.write_delay' : Integer[0..1] {
            doc /* Meaning: Delay between each byte sent out, in mS. Unit: ms. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int write_delay. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:61. */
        }
        attribute 'hamlib.struct.hamlib_port.post_write_delay' : Integer[0..1] {
            doc /* Meaning: Delay between each commands send out, in mS. Unit: ms. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int post_write_delay. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:62. */
        }
        attribute 'hamlib.struct.hamlib_port.timeout' : Integer[0..1] {
            doc /* Meaning: Timeout, in mS. Unit: ms. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int timeout. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:68. */
        }
        attribute 'hamlib.struct.hamlib_port.retry' : Integer[0..1] {
            doc /* Meaning: Maximum number of retries, 0 to disable. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: short retry. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:69. */
        }
        attribute 'hamlib.struct.hamlib_port.pathname' : String[0..1] {
            doc /* Meaning: Port pathname. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: char pathname[HAMLIB_FILPATHLEN]. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:72. */
        }
        attribute 'hamlib.struct.hamlib_port.rate' : Integer[0..1] {
            doc /* Meaning: Serial baud rate. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int rate. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:76. */
        }
        attribute 'hamlib.struct.hamlib_port.data_bits' : Integer[0..1] {
            doc /* Meaning: Number of data bits. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int data_bits. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:77. */
        }
        attribute 'hamlib.struct.hamlib_port.stop_bits' : Integer[0..1] {
            doc /* Meaning: Number of stop bits. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int stop_bits. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:78. */
        }
        attribute 'hamlib.struct.hamlib_port.parity' : Integer[0..1] {
            doc /* Meaning: Serial parity. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: enum serial_parity_e parity. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:79. */
        }
        attribute 'hamlib.struct.hamlib_port.handshake' : Integer[0..1] {
            doc /* Meaning: Serial handshake. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: enum serial_handshake_e handshake. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:80. */
        }
        attribute 'hamlib.struct.hamlib_port.rts_state' : Integer[0..1] {
            doc /* Meaning: RTS set state. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: enum serial_control_state_e rts_state. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:81. */
        }
        attribute 'hamlib.struct.hamlib_port.dtr_state' : Integer[0..1] {
            doc /* Meaning: DTR set state. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: enum serial_control_state_e dtr_state. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:82. */
        }
        attribute 'hamlib.struct.hamlib_port.serial' : HamlibUnresolvedProperty[0..1] {
            doc /* Meaning: serial attributes. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: serial. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:83. */
        }
        attribute 'hamlib.struct.hamlib_port.pin' : Integer[0..1] {
            doc /* Meaning: Parallel port pin number. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int pin. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:86. */
        }
        attribute 'hamlib.struct.hamlib_port.parallel' : HamlibUnresolvedProperty[0..1] {
            doc /* Meaning: parallel attributes. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: parallel. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:87. */
        }
        attribute 'hamlib.struct.hamlib_port.ptt_bitnum' : Integer[0..1] {
            doc /* Meaning: Bit number for CM108 GPIO PTT. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int ptt_bitnum. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:90. */
        }
        attribute 'hamlib.struct.hamlib_port.cm108' : HamlibUnresolvedProperty[0..1] {
            doc /* Meaning: CM108 attributes. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: cm108. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:91. */
        }
        attribute 'hamlib.struct.hamlib_port.vid' : Integer[0..1] {
            doc /* Meaning: Vendor ID. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int vid. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:94. */
        }
        attribute 'hamlib.struct.hamlib_port.pid' : Integer[0..1] {
            doc /* Meaning: Product ID. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int pid. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:95. */
        }
        attribute 'hamlib.struct.hamlib_port.conf' : Integer[0..1] {
            doc /* Meaning: Configuration. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int conf. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:96. */
        }
        attribute 'hamlib.struct.hamlib_port.iface' : Integer[0..1] {
            doc /* Meaning: interface. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int iface. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:97. */
        }
        attribute 'hamlib.struct.hamlib_port.alt' : Integer[0..1] {
            doc /* Meaning: alternate. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int alt. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:98. */
        }
        attribute 'hamlib.struct.hamlib_port.vendor_name' : String[0..1] {
            doc /* Meaning: Vendor name (opt.). Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: char *vendor_name. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:99. */
        }
        attribute 'hamlib.struct.hamlib_port.product' : String[0..1] {
            doc /* Meaning: Product (opt.). Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: char *product. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:100. */
        }
        attribute 'hamlib.struct.hamlib_port.usb' : HamlibUnresolvedProperty[0..1] {
            doc /* Meaning: USB attributes. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: usb. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:101. */
        }
        attribute 'hamlib.struct.hamlib_port.on_value' : Integer[0..1] {
            doc /* Meaning: GPIO: 1 == normal, GPION: 0 == inverted. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int on_value. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:104. */
        }
        attribute 'hamlib.struct.hamlib_port.value' : Integer[0..1] {
            doc /* Meaning: Toggle PTT ON or OFF. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int value. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:105. */
        }
        attribute 'hamlib.struct.hamlib_port.gpio' : HamlibUnresolvedProperty[0..1] {
            doc /* Meaning: GPIO attributes. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: gpio. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:106. */
        }
        attribute 'hamlib.struct.hamlib_port.parm' : HamlibUnresolvedProperty[0..1] {
            doc /* Meaning: Port parameter union. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: parm. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:107. */
        }
        attribute 'hamlib.struct.hamlib_port.client_port' : Integer[0..1] {
            doc /* Meaning: client socket port for tcp connection. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int client_port. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:108. */
        }
        attribute 'hamlib.struct.hamlib_port.rig' : HamlibUnresolvedProperty[0..1] {
            doc /* Meaning: our parent RIG device. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: RIG *rig. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:109. */
        }
        attribute 'hamlib.struct.hamlib_port.asyncio' : Integer[0..1] {
            doc /* Meaning: enable asynchronous data handling if true -- async collides with python keyword so _async is used. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int asyncio. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:110. */
        }
        attribute 'hamlib.struct.hamlib_port.timeout_retry' : Integer[0..1] {
            doc /* Meaning: number of retries to make in case of read timeout errors, some serial interfaces may require this, 0 to disable. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: short timeout_retry. Owner: RadioControlConnection/backend. Context: hamlib_port record context. Source: include/hamlib/port.h:120. */
        }
    }
    attribute def HamlibLevelProperties {
        doc /* Radio spectrum span/edges are independent of physical filter passband
             and our browser waterfall span. */
        attribute 'hamlib.RIG_LEVEL_AF' : Real[0..1] {
            doc /* Meaning: AF -- Volume, arg float [0.0 ... 1.0]. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1125.
                 Source domain: ['[0.0 ... 1.0]']. */
        }
        attribute 'hamlib.RIG_LEVEL_AGC' : Integer[0..1] {
            doc /* Meaning: AGC -- AGC, arg int (see enum #agc_level_e). Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: enum integer/value_t.i. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1139. */
        }
        attribute 'hamlib.RIG_LEVEL_AGC_TIME' : Real[0..1] {
            doc /* Meaning: AGC_TIME -- in seconds, rig dependent. Unit: s. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1177. */
        }
        attribute 'hamlib.RIG_LEVEL_ALC' : Real[0..1] {
            doc /* Meaning: ALC -- ALC, arg float. Unit: unspecified; do not infer units. Access/role: read-only.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1153. */
        }
        attribute 'hamlib.RIG_LEVEL_ANTIVOX' : Real[0..1] {
            doc /* Meaning: ANTIVOX -- anti-VOX level, arg float [0.0 ... 1.0]. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1144.
                 Source domain: ['[0.0 ... 1.0]']. */
        }
        attribute 'hamlib.RIG_LEVEL_APF' : Real[0..1] {
            doc /* Meaning: APF -- Audio Peak Filter, arg float [0.0 ... 1.0]. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1129.
                 Source domain: ['[0.0 ... 1.0]']. */
        }
        attribute 'hamlib.RIG_LEVEL_ATT' : Integer[0..1] {
            doc /* Meaning: ATT -- Attenuator, arg int (dB). Unit: dB. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1123. */
        }
        attribute 'hamlib.RIG_LEVEL_BALANCE' : Real[0..1] {
            doc /* Meaning: BAL -- Balance (Dual Watch) arg float [0.0 ... 1.0]. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1141.
                 Source domain: ['[0.0 ... 1.0]']. */
        }
        attribute 'hamlib.RIG_LEVEL_BAND_SELECT' : Integer[0..1] {
            doc /* Meaning: BAND_SELECT -- arg enum BAND_ENUM. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1174. */
        }
        attribute 'hamlib.RIG_LEVEL_BKINDL' : Integer[0..1] {
            doc /* Meaning: BKINDL -- BKin Delay, arg int (tenth of dots). Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1140. */
        }
        attribute 'hamlib.RIG_LEVEL_BKIN_DLYMS' : Integer[0..1] {
            doc /* Meaning: BKIN_DLYMS -- BKin Delay, arg int Milliseconds. Unit: ms. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1147. */
        }
        attribute 'hamlib.RIG_LEVEL_COMP' : Real[0..1] {
            doc /* Meaning: COMP -- Compressor, arg float [0.0 ... 1.0]. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1138.
                 Source domain: ['[0.0 ... 1.0]']. */
        }
        attribute 'hamlib.RIG_LEVEL_COMP_METER' : Real[0..1] {
            doc /* Meaning: COMP_METER -- Audio output level compression meter, arg float (dB). Unit: dB. Access/role: read-only.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1157. */
        }
        attribute 'hamlib.RIG_LEVEL_CWPITCH' : Integer[0..1] {
            doc /* Meaning: CWPITCH -- CW pitch, arg int (Hz). Unit: Hz. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1133. */
        }
        attribute 'hamlib.RIG_LEVEL_ID_METER' : Real[0..1] {
            doc /* Meaning: ID_METER -- Current draw meter, arg float (A, amperes). Unit: A. Access/role: read-only.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1159. */
        }
        attribute 'hamlib.RIG_LEVEL_IF' : Integer[0..1] {
            doc /* Meaning: IF shift -- IF, arg int (+/-Hz). Unit: Hz. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1128. */
        }
        attribute 'hamlib.RIG_LEVEL_KEYSPD' : Integer[0..1] {
            doc /* Meaning: KEYSPD -- Key Speed, arg int (WPM). Unit: word/min. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1136. */
        }
        attribute 'hamlib.RIG_LEVEL_METER' : Integer[0..1] {
            doc /* Meaning: METER -- Display meter, arg int (see enum #meter_level_e). Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: enum integer/value_t.i. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1142. */
        }
        attribute 'hamlib.RIG_LEVEL_MICGAIN' : Real[0..1] {
            doc /* Meaning: MICGAIN -- MIC Gain, arg float [0.0 ... 1.0]. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1135.
                 Source domain: ['[0.0 ... 1.0]']. */
        }
        attribute 'hamlib.RIG_LEVEL_MONITOR_GAIN' : Real[0..1] {
            doc /* Meaning: MONITOR_GAIN -- Monitor gain (level for monitoring of transmitted audio) arg float [0.0 ... 1.0]. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1162.
                 Source domain: ['[0.0 ... 1.0]']. */
        }
        attribute 'hamlib.RIG_LEVEL_NB' : Real[0..1] {
            doc /* Meaning: NB -- Noise Blanker level, arg float [0.0 ... 1.0]. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1163.
                 Source domain: ['[0.0 ... 1.0]']. */
        }
        attribute 'hamlib.RIG_LEVEL_NOTCHF' : Integer[0..1] {
            doc /* Meaning: NOTCHF -- Notch Freq., arg int (Hz). Unit: Hz. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1137. */
        }
        attribute 'hamlib.RIG_LEVEL_NOTCHF_RAW' : Real[0..1] {
            doc /* Meaning: NOTCHF_RAW -- Notch Freq., arg float [0.0 ... 1.0]. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1160.
                 Source domain: ['[0.0 ... 1.0]']. */
        }
        attribute 'hamlib.RIG_LEVEL_NR' : Real[0..1] {
            doc /* Meaning: NR -- Noise Reduction, arg float [0.0 ... 1.0]. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1130.
                 Source domain: ['[0.0 ... 1.0]']. */
        }
        attribute 'hamlib.RIG_LEVEL_PBT_IN' : Real[0..1] {
            doc /* Meaning: PBT_IN -- Twin PBT (inside) arg float [0.0 ... 1.0]. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1131.
                 Source domain: ['[0.0 ... 1.0]']. */
        }
        attribute 'hamlib.RIG_LEVEL_PBT_OUT' : Real[0..1] {
            doc /* Meaning: PBT_OUT -- Twin PBT (outside) arg float [0.0 ... 1.0]. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1132.
                 Source domain: ['[0.0 ... 1.0]']. */
        }
        attribute 'hamlib.RIG_LEVEL_PREAMP' : Integer[0..1] {
            doc /* Meaning: PREAMP -- Preamp, arg int (dB). Unit: dB. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1122. */
        }
        attribute 'hamlib.RIG_LEVEL_RAWSTR' : Integer[0..1] {
            doc /* Meaning: RAWSTR -- Raw (A/D) value for signal strength, specific to each rig, arg int. Unit: unspecified; do not infer units. Access/role: read-only.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1150. */
        }
        attribute 'hamlib.RIG_LEVEL_RF' : Real[0..1] {
            doc /* Meaning: RF -- RF gain (not TX power) arg float [0.0 ... 1.0]. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1126.
                 Source domain: ['[0.0 ... 1.0]']. */
        }
        attribute 'hamlib.RIG_LEVEL_RFPOWER' : Real[0..1] {
            doc /* Meaning: RFPOWER -- RF Power, arg float [0.0 ... 1.0]. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1134.
                 Source domain: ['[0.0 ... 1.0]']. */
        }
        attribute 'hamlib.RIG_LEVEL_RFPOWER_METER' : Real[0..1] {
            doc /* Meaning: RFPOWER_METER -- RF power output meter, arg float [0.0 ... 1.0] (percentage of maximum power). Unit: unspecified; do not infer units. Access/role: read-only.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1156.
                 Source domain: ['[0.0 ... 1.0]']. */
        }
        attribute 'hamlib.RIG_LEVEL_RFPOWER_METER_WATTS' : Real[0..1] {
            doc /* Meaning: RFPOWER_METER_WATTS -- RF power output meter, arg float [0.0 ... MAX] (output power in watts). Unit: W. Access/role: read-only.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1164.
                 Source domain: ['[0.0 ... MAX]']. */
        }
        attribute 'hamlib.RIG_LEVEL_SLOPE_HIGH' : Integer[0..1] {
            doc /* Meaning: SLOPE_HIGH -- Slope tune, high frequency cut, arg int (Hz). Unit: Hz. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1146. */
        }
        attribute 'hamlib.RIG_LEVEL_SLOPE_LOW' : Integer[0..1] {
            doc /* Meaning: SLOPE_LOW -- Slope tune, low frequency cut, arg int (Hz). Unit: Hz. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1145. */
        }
        attribute 'hamlib.RIG_LEVEL_SPECTRUM_ATT' : Integer[0..1] {
            doc /* Meaning: SPECTRUM_ATT -- Spectrum scope attenuator, arg int (dB). Supported attenuator values defined in rig caps.. Unit: dB. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1172. */
        }
        attribute 'hamlib.RIG_LEVEL_SPECTRUM_AVG' : Integer[0..1] {
            doc /* Meaning: SPECTRUM_AVG -- Spectrum scope averaging mode, arg int (see struct rig_spectrum_avg_mode). Supported averaging modes defined in rig caps.. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1171. */
        }
        attribute 'hamlib.RIG_LEVEL_SPECTRUM_EDGE_HIGH' : Integer[0..1] {
            doc /* Meaning: SPECTRUM_EDGE_HIGH -- Spectrum scope high edge in fixed mode, arg int (Hz). Unit: Hz. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1168. */
        }
        attribute 'hamlib.RIG_LEVEL_SPECTRUM_EDGE_LOW' : Integer[0..1] {
            doc /* Meaning: SPECTRUM_EDGE_LOW -- Spectrum scope low edge in fixed mode, arg int (Hz). Unit: Hz. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1167. */
        }
        attribute 'hamlib.RIG_LEVEL_SPECTRUM_MODE' : Integer[0..1] {
            doc /* Meaning: SPECTRUM_MODE -- Spectrum scope mode, arg int (see enum #rig_spectrum_mode_e). Supported modes defined in rig caps.. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1165. */
        }
        attribute 'hamlib.RIG_LEVEL_SPECTRUM_REF' : Real[0..1] {
            doc /* Meaning: SPECTRUM_REF -- Spectrum scope reference display level, arg float (dB, define rig-specific granularity). Unit: dB. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1170. */
        }
        attribute 'hamlib.RIG_LEVEL_SPECTRUM_SPAN' : Integer[0..1] {
            doc /* Meaning: SPECTRUM_SPAN -- Spectrum scope span in center mode, arg int (Hz). Supported spans defined in rig caps. Radio hardware spectrum/scope display span; separate from radio receiver passband and application browser waterfall span.. Unit: Hz. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1166. */
        }
        attribute 'hamlib.RIG_LEVEL_SPECTRUM_SPEED' : Integer[0..1] {
            doc /* Meaning: SPECTRUM_SPEED -- Spectrum scope update speed, arg int (highest is fastest, define rig-specific granularity). Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1169. */
        }
        attribute 'hamlib.RIG_LEVEL_SQL' : Real[0..1] {
            doc /* Meaning: SQL -- Squelch, arg float [0.0 ... 1.0]. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1127.
                 Source domain: ['[0.0 ... 1.0]']. */
        }
        attribute 'hamlib.RIG_LEVEL_STRENGTH' : Integer[0..1] {
            doc /* Meaning: STRENGTH -- Effective (calibrated) signal strength relative to S9, arg int (dB). Unit: dB. Access/role: read-only.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1154. */
        }
        attribute 'hamlib.RIG_LEVEL_SWR' : Real[0..1] {
            doc /* Meaning: SWR -- SWR, arg float [0.0 ... infinite]. Unit: unspecified; do not infer units. Access/role: read-only.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1152.
                 Source domain: ['[0.0 ... infinite]']. */
        }
        attribute 'hamlib.RIG_LEVEL_TEMP_METER' : Real[0..1] {
            doc /* Meaning: TEMP_METER -- arg float (C, centigrade). Unit: degC. Access/role: read-only.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1173. */
        }
        attribute 'hamlib.RIG_LEVEL_USB_AF' : Real[0..1] {
            doc /* Meaning: ACC/USB AF output level. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1175. */
        }
        attribute 'hamlib.RIG_LEVEL_USB_AF_INPUT' : Real[0..1] {
            doc /* Meaning: ACC/USB AF input level. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1176. */
        }
        attribute 'hamlib.RIG_LEVEL_VD_METER' : Real[0..1] {
            doc /* Meaning: VD_METER -- Input voltage level meter, arg float (V, volts). Unit: V. Access/role: read-only.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1158. */
        }
        attribute 'hamlib.RIG_LEVEL_VOXDELAY' : Integer[0..1] {
            doc /* Meaning: VOXDELAY -- VOX delay, arg int (tenth of seconds). Unit: 0.1 s. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: integer/value_t.i. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1124. */
        }
        attribute 'hamlib.RIG_LEVEL_VOXGAIN' : Real[0..1] {
            doc /* Meaning: VOXGAIN -- VOX gain level, arg float [0.0 ... 1.0]. Unit: unspecified; do not infer units. Access/role: get/set eligibility; per-model availability remains separate.
                 Source type: float/value_t.f. Owner: physicalRadio. Context: VFO-context. Source: include/hamlib/rig.h:1143.
                 Source domain: ['[0.0 ... 1.0]']. */
        }
    }
    attribute def HamlibModelCapabilityProperties {
        attribute 'hamlib.rig_caps.agc_level_count' : Integer[0..1] {
            doc /* Meaning: Number of supported AGC levels. Zero indicates all modes should be available (for backwards-compatibility).. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: int agc_level_count. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2404. */
        }
        attribute 'hamlib.rig_caps.agc_levels' : Integer[*] {
            doc /* Meaning: Supported AGC levels. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: enum agc_level_e agc_levels[HAMLIB_MAX_AGC_LEVELS]. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2405. */
        }
        attribute 'hamlib.rig_caps.alc_cal' : HamlibCalTableFloatProperties[0..1] {
            doc /* Meaning: ALC meter calibration table. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: cal_table_float_t alc_cal. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2439. */
        }
        attribute 'hamlib.rig_caps.announces' : Integer[0..1] {
            doc /* Meaning: Announces bit field list. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: ann_t announces. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2407. */
        }
        attribute 'hamlib.rig_caps.attenuator' : Integer[*] {
            doc /* Meaning: Attenuator list in dB, 0 terminated. Unit: dB. Access/role: catalogue description/capability; not live state.
                 Source type: int attenuator[HAMLIB_MAXDBLSTSIZ]. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2399. */
        }
        attribute 'hamlib.rig_caps.bank_qty' : Integer[0..1] {
            doc /* Meaning: Number of banks. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: int bank_qty. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2414. */
        }
        attribute 'hamlib.rig_caps.chan_desc_sz' : Integer[0..1] {
            doc /* Meaning: Max length of memory channel name. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: int chan_desc_sz. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2415. */
        }
        attribute 'hamlib.rig_caps.chan_list' : HamlibChanListProperties[*] {
            doc /* Meaning: Channel list, zero ended. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: chan_t chan_list[HAMLIB_CHANLSTSIZ]. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2417. */
        }
        attribute 'hamlib.rig_caps.clone_combo_get' : String[0..1] {
            doc /* Meaning: String describing key combination to enter save cloning mode. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: const char *clone_combo_get. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2636. */
        }
        attribute 'hamlib.rig_caps.clone_combo_set' : String[0..1] {
            doc /* Meaning: String describing key combination to enter load cloning mode. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: const char *clone_combo_set. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2635. */
        }
        attribute 'hamlib.rig_caps.comp_meter_cal' : HamlibCalTableFloatProperties[0..1] {
            doc /* Meaning: COMP meter calibration table. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: cal_table_float_t comp_meter_cal. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2441. */
        }
        attribute 'hamlib.rig_caps.ctcss_list' : Integer[*] {
            doc /* Meaning: CTCSS tones list, zero ended. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: tone_t *ctcss_list. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2395. */
        }
        attribute 'hamlib.rig_caps.dcs_list' : Integer[*] {
            doc /* Meaning: DCS code list, zero ended. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: tone_t *dcs_list. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2396. */
        }
        attribute 'hamlib.rig_caps.ext_tokens' : Integer[*] {
            doc /* Meaning: Extension token list. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: int *ext_tokens. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2393. */
        }
        attribute 'hamlib.rig_caps.extfuncs' : HamlibUnresolvedProperty[0..1] {
            doc /* Meaning: Extension func list, \sa ext.c. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: const struct confparams *extfuncs. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2392. */
        }
        attribute 'hamlib.rig_caps.extlevels' : HamlibUnresolvedProperty[0..1] {
            doc /* Meaning: Extension level list, \sa ext.c. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: const struct confparams *extlevels. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2391. */
        }
        attribute 'hamlib.rig_caps.extparms' : HamlibUnresolvedProperty[0..1] {
            doc /* Meaning: Extension parm list, \sa ext.c. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: const struct confparams *extparms. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2390. */
        }
        attribute 'hamlib.rig_caps.filters' : HamlibFilterListProperties[*] {
            doc /* Meaning: mode/filter table, at -6dB. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: struct filter_list filters[HAMLIB_FLTLSTSIZ]. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2435. */
        }
        attribute 'hamlib.rig_caps.id_meter_cal' : HamlibCalTableFloatProperties[0..1] {
            doc /* Meaning: Current draw meter calibration table. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: cal_table_float_t id_meter_cal. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2443. */
        }
        attribute 'hamlib.rig_caps.level_gran' : HamlibGranProperties[*] {
            doc /* Meaning: level granularity (i.e. steps). Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: gran_t level_gran[RIG_SETTING_MAX]. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2387. */
        }
        attribute 'hamlib.rig_caps.max_ifshift' : Integer[0..1] {
            doc /* Meaning: max absolute IF-SHIFT. Unit: Hz. Access/role: catalogue description/capability; not live state.
                 Source type: shortfreq_t max_ifshift. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2402. */
        }
        attribute 'hamlib.rig_caps.max_rit' : Integer[0..1] {
            doc /* Meaning: max absolute RIT. Unit: Hz. Access/role: catalogue description/capability; not live state.
                 Source type: shortfreq_t max_rit. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2400. */
        }
        attribute 'hamlib.rig_caps.max_xit' : Integer[0..1] {
            doc /* Meaning: max absolute XIT. Unit: Hz. Access/role: catalogue description/capability; not live state.
                 Source type: shortfreq_t max_xit. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2401. */
        }
        attribute 'hamlib.rig_caps.mfg_name' : String[0..1] {
            doc /* Meaning: Manufacturer.. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: const char *mfg_name. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2358. */
        }
        attribute 'hamlib.rig_caps.model_name' : String[0..1] {
            doc /* Meaning: Model name.. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: const char *model_name. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2357. */
        }
        attribute 'hamlib.rig_caps.morse_qsize' : Integer[0..1] {
            doc /* Meaning: max length of morse message rig can accept in one command. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: short morse_qsize. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2657. */
        }
        attribute 'hamlib.rig_caps.parm_gran' : HamlibGranProperties[*] {
            doc /* Meaning: parm granularity (i.e. steps). Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: gran_t parm_gran[RIG_SETTING_MAX]. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2388. */
        }
        attribute 'hamlib.rig_caps.preamp' : Integer[*] {
            doc /* Meaning: Preamp list in dB, 0 terminated. Unit: dB. Access/role: catalogue description/capability; not live state.
                 Source type: int preamp[HAMLIB_MAXDBLSTSIZ]. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2398. */
        }
        attribute 'hamlib.rig_caps.rfpower_meter_cal' : HamlibCalTableFloatProperties[0..1] {
            doc /* Meaning: RF power meter calibration table. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: cal_table_float_t rfpower_meter_cal. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2440. */
        }
        attribute 'hamlib.rig_caps.rig_model' : Integer[0..1] {
            doc /* Meaning: Rig model.. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: rig_model_t rig_model. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2356. */
        }
        attribute 'hamlib.rig_caps.rig_type' : Integer[0..1] {
            doc /* Meaning: Rig type.. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: int rig_type. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2363. */
        }
        attribute 'hamlib.rig_caps.rx_range_list1' : HamlibFreqRangeListProperties[*] {
            doc /* Meaning: Receive frequency range list #1. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: freq_range_t rx_range_list1[HAMLIB_FRQRANGESIZ]. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2423. */
        }
        attribute 'hamlib.rig_caps.rx_range_list2' : HamlibFreqRangeListProperties[*] {
            doc /* Meaning: Receive frequency range list #2. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: freq_range_t rx_range_list2[HAMLIB_FRQRANGESIZ]. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2425. */
        }
        attribute 'hamlib.rig_caps.rx_range_list3' : HamlibFreqRangeListProperties[*] {
            doc /* Meaning: Receive frequency range list #3. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: freq_range_t rx_range_list3[HAMLIB_FRQRANGESIZ]. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2427. */
        }
        attribute 'hamlib.rig_caps.rx_range_list4' : HamlibFreqRangeListProperties[*] {
            doc /* Meaning: Receive frequency range list #4. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: freq_range_t rx_range_list4[HAMLIB_FRQRANGESIZ]. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2429. */
        }
        attribute 'hamlib.rig_caps.rx_range_list5' : HamlibFreqRangeListProperties[*] {
            doc /* Meaning: Receive frequency range list #5. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: freq_range_t rx_range_list5[HAMLIB_FRQRANGESIZ]. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2431. */
        }
        attribute 'hamlib.rig_caps.scan_ops' : Integer[0..1] {
            doc /* Meaning: Scan bit field list. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: scan_t scan_ops. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2410. */
        }
        attribute 'hamlib.rig_caps.spectrum_attenuator' : Integer[*] {
            doc /* Meaning: Spectrum attenuator list in dB, 0 terminated. Unit: dB. Access/role: catalogue description/capability; not live state.
                 Source type: int spectrum_attenuator[HAMLIB_MAXDBLSTSIZ]. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2449. */
        }
        attribute 'hamlib.rig_caps.spectrum_avg_modes' : HamlibRigSpectrumAvgModeProperties[*] {
            doc /* Meaning: Supported spectrum scope averaging modes. Last entry must have NULL name.. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: struct rig_spectrum_avg_mode spectrum_avg_modes[HAMLIB_MAX_SPECTRUM_AVG_MODES]. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2448. */
        }
        attribute 'hamlib.rig_caps.spectrum_modes' : Integer[*] {
            doc /* Meaning: Supported spectrum scope modes. Last entry must be RIG_SPECTRUM_MODE_NONE.. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: enum rig_spectrum_mode_e spectrum_modes[HAMLIB_MAX_SPECTRUM_MODES]. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2446. */
        }
        attribute 'hamlib.rig_caps.spectrum_scopes' : HamlibRigSpectrumScopeProperties[*] {
            doc /* Meaning: Supported spectrum scopes. The array index must match the scope ID. Last entry must have NULL name.. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: struct rig_spectrum_scope spectrum_scopes[HAMLIB_MAX_SPECTRUM_SCOPES]. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2445. */
        }
        attribute 'hamlib.rig_caps.spectrum_spans' : Real[*] {
            doc /* Meaning: Supported spectrum scope frequency spans in Hz in center mode. Last entry must be 0.. Unit: Hz. Access/role: catalogue description/capability; not live state.
                 Source type: freq_t spectrum_spans[HAMLIB_MAX_SPECTRUM_SPANS]. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2447. */
        }
        attribute 'hamlib.rig_caps.str_cal' : HamlibCalTableProperties[0..1] {
            doc /* Meaning: S-meter calibration table. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: cal_table_t str_cal. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2437. */
        }
        attribute 'hamlib.rig_caps.swr_cal' : HamlibCalTableFloatProperties[0..1] {
            doc /* Meaning: SWR meter calibration table. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: cal_table_float_t swr_cal. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2438. */
        }
        attribute 'hamlib.rig_caps.timeout_retry' : Integer[0..1] {
            doc /* Meaning: number of retries to make in case of read timeout errors, some serial interfaces may require this, 0 to use default value, -1 to disable. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: short timeout_retry. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2656. */
        }
        attribute 'hamlib.rig_caps.tuning_steps' : HamlibTuningStepListProperties[*] {
            doc /* Meaning: Tuning step list. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: struct tuning_step_list tuning_steps[HAMLIB_TSLSTSIZ]. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2434. */
        }
        attribute 'hamlib.rig_caps.tx_range_list1' : HamlibFreqRangeListProperties[*] {
            doc /* Meaning: Transmit frequency range list #1. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: freq_range_t tx_range_list1[HAMLIB_FRQRANGESIZ]. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2424. */
        }
        attribute 'hamlib.rig_caps.tx_range_list2' : HamlibFreqRangeListProperties[*] {
            doc /* Meaning: Transmit frequency range list #2. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: freq_range_t tx_range_list2[HAMLIB_FRQRANGESIZ]. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2426. */
        }
        attribute 'hamlib.rig_caps.tx_range_list3' : HamlibFreqRangeListProperties[*] {
            doc /* Meaning: Transmit frequency range list #3. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: freq_range_t tx_range_list3[HAMLIB_FRQRANGESIZ]. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2428. */
        }
        attribute 'hamlib.rig_caps.tx_range_list4' : HamlibFreqRangeListProperties[*] {
            doc /* Meaning: Transmit frequency range list #4. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: freq_range_t tx_range_list4[HAMLIB_FRQRANGESIZ]. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2430. */
        }
        attribute 'hamlib.rig_caps.tx_range_list5' : HamlibFreqRangeListProperties[*] {
            doc /* Meaning: Transmit frequency range list #5. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: freq_range_t tx_range_list5[HAMLIB_FRQRANGESIZ]. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2432. */
        }
        attribute 'hamlib.rig_caps.vd_meter_cal' : HamlibCalTableFloatProperties[0..1] {
            doc /* Meaning: Voltage meter calibration table. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: cal_table_float_t vd_meter_cal. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2442. */
        }
        attribute 'hamlib.rig_caps.vfo_ops' : Integer[0..1] {
            doc /* Meaning: VFO op bit field list. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: vfo_op_t vfo_ops. Owner: physicalRadio/model definition. Context: model-specific. Source: include/hamlib/rig.h:2409. */
        }
    }
    attribute def RadioAntennaSelectionRecord {
        attribute vfoSelector : Integer[0..1];
        attribute selectedAntenna : Integer[0..1];
        attribute option : HamlibUnresolvedProperty[0..1];
        attribute currentAntenna : Integer[0..1];
        attribute transmitAntenna : Integer[0..1];
        attribute receiveAntenna : Integer[0..1];
        doc /* Independent ant_t selectors and model-specific value_t option from
             rig_set_ant/rig_get_ant, pinned rig.h3380..3392. Selectors retain source
             enum/bitmask domains without packing fields into one integer. The input
             antenna selection differs from current/TX/RX observation outputs; no output
             is inferred from a request. Unknown option union representation remains
             explicit until the selected model supplies its meaning. */
    }
    attribute def RadioSplitVfoRecord {
        attribute receiveVfoSelector : Integer[0..1];
        attribute splitEnabled : Boolean[0..1];
        attribute transmitVfoSelector : Integer[0..1];
        doc /* rig_set_split_vfo/rig_get_split_vfo, pinned rig.h3203..3212, carry
             receive-VFO context, independent split_t off/on state and a TX-VFO selector.
             splitEnabled is the normalized off/on meaning, not a C enum ordinal cast;
             VFO selectors retain their source enum/alias/bitmask context. Requested
             values do not imply confirmed observations. No compound integer encoding. */
    }
    attribute def HamlibOperatingProperties {
        attribute 'radio.antennaSelection' : RadioAntennaSelectionRecord[0..1] {
            doc /* Meaning: antennaSelection. Unit: unspecified; do not infer units. Access/role: requested and/or observed; retain separately with status/freshness.
                 Source type: record(ant_t, value_t option, current/TX/RX). Owner: physicalRadio. Context: VFO. Source: include/hamlib/rig.h:3380; include/hamlib/rig.h:3385. */
        }
        attribute 'radio.asynchronousPublication' : RadioPublicationMode[0..1] {
            doc /* Meaning: asynchronousPublication. Unit: unspecified; do not infer units. Access/role: requested and/or observed; retain separately with status/freshness.
                 Source type: int/bool with event callbacks; rig.h1304..1306 defines raw codes
                 0=off, 1=radioEvents, 2=polling. These are explicit semantic names, not
                 SysML ordinal casts or an instruction to start application polling.
                 Owner: physicalRadio. Context: radio. Source: include/hamlib/rig.h:3555; include/hamlib/rig.h:3559. */
        }
        attribute 'radio.carrierDetect' : Integer[0..1] {
            doc /* Meaning: carrierDetect. Unit: unspecified; do not infer units. Access/role: requested and/or observed; retain separately with status/freshness.
                 Source type: dcd_t enum. Owner: physicalRadio. Context: VFO/DCD connection. Source: include/hamlib/rig.h:3111. */
        }
        attribute 'radio.clock' : HamlibUnresolvedProperty[0..1] {
            doc /* Meaning: clock. Unit: source-defined mixed time fields. Access/role: requested and/or observed; retain separately with status/freshness.
                 Source type: calendar/time/UTC offset record. Owner: physicalRadio. Context: radio. Source: include/hamlib/rig.h:4076; include/hamlib/rig.h:4077. */
        }
        attribute 'radio.ctcssSquelchTone' : Integer[0..1] {
            doc /* Meaning: ctcssSquelchTone. Unit: 0.1 Hz. Access/role: requested and/or observed; retain separately with status/freshness.
                 Source type: tone_t. Owner: physicalRadio. Context: VFO. Source: include/hamlib/rig.h:3152; include/hamlib/rig.h:3156. */
        }
        attribute 'radio.ctcssTone' : Integer[0..1] {
            doc /* Meaning: ctcssTone. Unit: 0.1 Hz. Access/role: requested and/or observed; retain separately with status/freshness.
                 Source type: tone_t. Owner: physicalRadio. Context: VFO. Source: include/hamlib/rig.h:3134; include/hamlib/rig.h:3138. */
        }
        attribute 'radio.dcsCode' : Integer[0..1] {
            doc /* Meaning: dcsCode. Unit: unspecified; do not infer units. Access/role: requested and/or observed; retain separately with status/freshness.
                 Source type: tone_t code. Owner: physicalRadio. Context: VFO. Source: include/hamlib/rig.h:3143; include/hamlib/rig.h:3147. */
        }
        attribute 'radio.dcsSquelchCode' : Integer[0..1] {
            doc /* Meaning: dcsSquelchCode. Unit: unspecified; do not infer units. Access/role: requested and/or observed; retain separately with status/freshness.
                 Source type: tone_t code. Owner: physicalRadio. Context: VFO. Source: include/hamlib/rig.h:3161; include/hamlib/rig.h:3165. */
        }
        attribute 'radio.frequency' : Real[0..1] {
            doc /* Meaning: frequency. Unit: Hz. Access/role: requested and/or observed; retain separately with status/freshness.
                 Source type: freq_t. Owner: physicalRadio. Context: VFO. Source: include/hamlib/rig.h:3044; include/hamlib/rig.h:3056. */
        }
        attribute 'radio.memoryChannel' : HamlibChannelProperties[0..1] {
            doc /* Meaning: memoryChannel. Unit: unspecified; do not infer units. Access/role: requested and/or observed; retain separately with status/freshness.
                 Source type: channel_t record. Owner: physicalRadio. Context: bank/channel/VFO. Source: include/hamlib/rig.h:3491; include/hamlib/rig.h:3495; include/hamlib/rig.h:3463; include/hamlib/rig.h:3467; include/hamlib/rig.h:3458. */
        }
        attribute 'radio.mode' : Integer[0..1] {
            doc /* Meaning: mode. Unit: unspecified; do not infer units. Access/role: requested and/or observed; retain separately with status/freshness.
                 Source type: rmode_t enum/bitmask. Owner: physicalRadio. Context: VFO. Source: include/hamlib/rig.h:3062; include/hamlib/rig.h:3067. */
        }
        attribute 'radio.passbandWidth' : Integer[0..1] {
            doc /* Meaning: passbandWidth. Unit: Hz. Access/role: requested and/or observed; retain separately with status/freshness.
                 Source type: pbwidth_t. Owner: physicalRadio. Context: VFO+mode. Source: include/hamlib/rig.h:3062; include/hamlib/rig.h:3067. */
        }
        attribute 'radio.powerState' : Integer[0..1] {
            doc /* Meaning: powerState. Unit: unspecified; do not infer units. Access/role: requested and/or observed; retain separately with status/freshness.
                 Source type: powerstat_t enum. Owner: physicalRadio. Context: radio. Source: include/hamlib/rig.h:3295; include/hamlib/rig.h:3298. */
        }
        attribute 'radio.ptt' : Integer[0..1] {
            doc /* Meaning: ptt. Unit: unspecified; do not infer units. Access/role: requested and/or observed; retain separately with status/freshness.
                 Source type: ptt_t enum. Owner: physicalRadio. Context: VFO/PTT connection. Source: include/hamlib/rig.h:3102; include/hamlib/rig.h:3106. */
        }
        attribute 'radio.repeaterOffset' : Integer[0..1] {
            doc /* Meaning: repeaterOffset. Unit: Hz. Access/role: requested and/or observed; retain separately with status/freshness.
                 Source type: shortfreq_t. Owner: physicalRadio. Context: VFO. Source: include/hamlib/rig.h:3125; include/hamlib/rig.h:3129. */
        }
        attribute 'radio.repeaterShift' : Integer[0..1] {
            doc /* Meaning: repeaterShift. Unit: unspecified; do not infer units. Access/role: requested and/or observed; retain separately with status/freshness.
                 Source type: rptr_shift_t enum. Owner: physicalRadio. Context: VFO. Source: include/hamlib/rig.h:3116; include/hamlib/rig.h:3120. */
        }
        attribute 'radio.ritOffset' : Integer[0..1] {
            doc /* Meaning: ritOffset. Unit: Hz. Access/role: requested and/or observed; retain separately with status/freshness.
                 Source type: shortfreq_t. Owner: physicalRadio. Context: VFO. Source: include/hamlib/rig.h:3214; include/hamlib/rig.h:3218. */
        }
        attribute 'radio.selectedVfo' : Integer[0..1] {
            doc /* Meaning: selectedVfo. Unit: unspecified; do not infer units. Access/role: requested and/or observed; retain separately with status/freshness.
                 Source type: vfo_t enum. Owner: physicalRadio. Context: radio. Source: include/hamlib/rig.h:3079; include/hamlib/rig.h:3083. */
        }
        attribute 'radio.spectrumSnapshot' : HamlibRigSpectrumLineProperties[0..1] {
            doc /* Meaning: spectrumSnapshot. Unit: frequency Hz; level source-defined. Access/role: requested and/or observed; retain separately with status/freshness.
                 Source type: rig_spectrum_line record. Owner: physicalRadio. Context: scope/VFO. Source: include/hamlib/rig.h:3592. */
        }
        attribute 'radio.splitEnabledAndTxVfo' : RadioSplitVfoRecord[0..1] {
            doc /* Meaning: splitEnabledAndTxVfo. Unit: unspecified; do not infer units. Access/role: requested and/or observed; retain separately with status/freshness.
                 Source type: record(split_t,vfo_t). Owner: physicalRadio. Context: RX/TX VFO pair. Source: include/hamlib/rig.h:3203; include/hamlib/rig.h:3208. */
        }
        attribute 'radio.splitFrequency' : Real[0..1] {
            doc /* Meaning: splitFrequency. Unit: Hz. Access/role: requested and/or observed; retain separately with status/freshness.
                 Source type: freq_t. Owner: physicalRadio. Context: TX VFO. Source: include/hamlib/rig.h:3170; include/hamlib/rig.h:3174. */
        }
        attribute 'radio.splitMode' : Integer[0..1] {
            doc /* Meaning: splitMode. Unit: unspecified; do not infer units. Access/role: requested and/or observed; retain separately with status/freshness.
                 Source type: rmode_t enum. Owner: physicalRadio. Context: TX VFO. Source: include/hamlib/rig.h:3179; include/hamlib/rig.h:3184. */
        }
        attribute 'radio.splitPassbandWidth' : Integer[0..1] {
            doc /* Meaning: splitPassbandWidth. Unit: Hz. Access/role: requested and/or observed; retain separately with status/freshness.
                 Source type: pbwidth_t. Owner: physicalRadio. Context: TX VFO+mode. Source: include/hamlib/rig.h:3179; include/hamlib/rig.h:3184. */
        }
        attribute 'radio.tuningStep' : Integer[0..1] {
            doc /* Meaning: tuningStep. Unit: Hz. Access/role: requested and/or observed; retain separately with status/freshness.
                 Source type: shortfreq_t. Owner: physicalRadio. Context: VFO+mode. Source: include/hamlib/rig.h:3232; include/hamlib/rig.h:3236. */
        }
        attribute 'radio.xitOffset' : Integer[0..1] {
            doc /* Meaning: xitOffset. Unit: Hz. Access/role: requested and/or observed; retain separately with status/freshness.
                 Source type: shortfreq_t. Owner: physicalRadio. Context: VFO. Source: include/hamlib/rig.h:3223; include/hamlib/rig.h:3227. */
        }
    }
    attribute def HamlibRadioStreamModelProperties {
        attribute 'hamlib.rig_caps.stream_caps' : HamlibRigStreamCapsProperties[*] {
            doc /* Meaning: Streaming capabilities, 0-terminated by type, or NULL. Unit: unspecified; do not infer units. Access/role: catalogue description/capability; not live state.
                 Source type: const struct rig_stream_caps *stream_caps. Owner: AudioInterface. Context: model-specific. Source: include/hamlib/rig.h:2677. */
        }
    }
    attribute def HamlibRigSpectrumAvgModeProperties {
        attribute 'hamlib.struct.rig_spectrum_avg_mode.id' : Integer[0..1] {
            doc /* Meaning: rig_spectrum_avg_mode.id. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int id. Owner: physicalRadio/model definition. Context: rig_spectrum_avg_mode record context. Source: include/hamlib/rig.h:1920. */
        }
        attribute 'hamlib.struct.rig_spectrum_avg_mode.name' : String[0..1] {
            doc /* Meaning: rig_spectrum_avg_mode.name. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: char *name. Owner: physicalRadio/model definition. Context: rig_spectrum_avg_mode record context. Source: include/hamlib/rig.h:1921. */
        }
    }
    attribute def HamlibRigSpectrumLineProperties {
        attribute 'hamlib.struct.rig_spectrum_line.id' : Integer[0..1] {
            doc /* Meaning: Numeric ID of the spectrum scope data stream identifying the VFO/receiver. First ID is zero. Rigs with multiple scopes usually have identifiers, such as 0 = Main, 1 = Sub.. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int id. Owner: physicalRadio/model definition. Context: rig_spectrum_line record context. Source: include/hamlib/rig.h:1937. */
        }
        attribute 'hamlib.struct.rig_spectrum_line.data_level_min' : Integer[0..1] {
            doc /* Meaning: The numeric value that represents the minimum signal level.. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int data_level_min. Owner: physicalRadio/model definition. Context: rig_spectrum_line record context. Source: include/hamlib/rig.h:1939. */
        }
        attribute 'hamlib.struct.rig_spectrum_line.data_level_max' : Integer[0..1] {
            doc /* Meaning: The numeric value that represents the maximum signal level.. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int data_level_max. Owner: physicalRadio/model definition. Context: rig_spectrum_line record context. Source: include/hamlib/rig.h:1940. */
        }
        attribute 'hamlib.struct.rig_spectrum_line.signal_strength_min' : Real[0..1] {
            doc /* Meaning: The strength of the minimum signal level in dB.. Unit: dB. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: double signal_strength_min. Owner: physicalRadio/model definition. Context: rig_spectrum_line record context. Source: include/hamlib/rig.h:1941. */
        }
        attribute 'hamlib.struct.rig_spectrum_line.signal_strength_max' : Real[0..1] {
            doc /* Meaning: The strength of the maximum signal level in dB.. Unit: dB. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: double signal_strength_max. Owner: physicalRadio/model definition. Context: rig_spectrum_line record context. Source: include/hamlib/rig.h:1942. */
        }
        attribute 'hamlib.struct.rig_spectrum_line.spectrum_mode' : Integer[0..1] {
            doc /* Meaning: Spectrum mode.. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: enum rig_spectrum_mode_e spectrum_mode. Owner: physicalRadio/model definition. Context: rig_spectrum_line record context. Source: include/hamlib/rig.h:1944. */
        }
        attribute 'hamlib.struct.rig_spectrum_line.center_freq' : Real[0..1] {
            doc /* Meaning: Center frequency of the spectrum scope in Hz in RIG_SPECTRUM_CENTER mode.. Unit: Hz. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: freq_t center_freq. Owner: physicalRadio/model definition. Context: rig_spectrum_line record context. Source: include/hamlib/rig.h:1946. */
        }
        attribute 'hamlib.struct.rig_spectrum_line.span_freq' : Real[0..1] {
            doc /* Meaning: Span of the spectrum scope in Hz in RIG_SPECTRUM_CENTER mode.. Unit: Hz. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: freq_t span_freq. Owner: physicalRadio/model definition. Context: rig_spectrum_line record context. Source: include/hamlib/rig.h:1947. */
        }
        attribute 'hamlib.struct.rig_spectrum_line.low_edge_freq' : Real[0..1] {
            doc /* Meaning: Low edge frequency of the spectrum scope in Hz in RIG_SPECTRUM_FIXED mode.. Unit: Hz. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: freq_t low_edge_freq. Owner: physicalRadio/model definition. Context: rig_spectrum_line record context. Source: include/hamlib/rig.h:1949. */
        }
        attribute 'hamlib.struct.rig_spectrum_line.high_edge_freq' : Real[0..1] {
            doc /* Meaning: High edge frequency of the spectrum scope in Hz in RIG_SPECTRUM_FIXED mode.. Unit: Hz. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: freq_t high_edge_freq. Owner: physicalRadio/model definition. Context: rig_spectrum_line record context. Source: include/hamlib/rig.h:1950. */
        }
        attribute 'hamlib.struct.rig_spectrum_line.spectrum_data_length' : Integer[0..1] {
            doc /* Meaning: Number of bytes of 8-bit spectrum data in the data buffer. The amount of data may vary if the rig has multiple spectrum scopes, depending on the scope.. Unit: byte. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: size_t spectrum_data_length. Owner: physicalRadio/model definition. Context: rig_spectrum_line record context. Source: include/hamlib/rig.h:1952. */
        }
    }
    attribute def HamlibRigSpectrumScopeProperties {
        attribute 'hamlib.struct.rig_spectrum_scope.id' : Integer[0..1] {
            doc /* Meaning: rig_spectrum_scope.id. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int id. Owner: physicalRadio/model definition. Context: rig_spectrum_scope record context. Source: include/hamlib/rig.h:1900. */
        }
        attribute 'hamlib.struct.rig_spectrum_scope.name' : String[0..1] {
            doc /* Meaning: rig_spectrum_scope.name. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: char *name. Owner: physicalRadio/model definition. Context: rig_spectrum_scope record context. Source: include/hamlib/rig.h:1901. */
        }
    }
    attribute def HamlibRigStreamCapsProperties {
        attribute 'hamlib.struct.rig_stream_caps.type' : Integer[0..1] {
            doc /* Meaning: rig_stream_caps.type. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: rig_stream_type_t type. Owner: AudioInterface. Context: rig_stream_caps record context. Source: include/hamlib/rig.h:2030. */
        }
        attribute 'hamlib.struct.rig_stream_caps.formats' : Integer[0..1] {
            doc /* Meaning: Openable formats (effective set * in the derived app view; backends * declare native here). Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: rig_stream_format_t formats. Owner: AudioInterface. Context: rig_stream_caps record context. Source: include/hamlib/rig.h:2031. */
        }
        attribute 'hamlib.struct.rig_stream_caps.sample_rates' : Integer[*] {
            doc /* Meaning: Openable rates, 0-terminated * (effective in the app view). Unit: sample/s. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int32_t sample_rates[HAMLIB_MAX_STREAM_RATES]. Owner: AudioInterface. Context: rig_stream_caps record context. Source: include/hamlib/rig.h:2034. */
        }
        attribute 'hamlib.struct.rig_stream_caps.channels' : Integer[*] {
            doc /* Meaning: Openable channel * counts, 0-terminated ascending * list (effective in the app * view; backends declare the * hardware-native counts, which * need not be contiguous). The * list is exact: every openable * count is listed, none implied. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int32_t channels[HAMLIB_MAX_STREAM_CHANNEL_COUNTS]. Owner: AudioInterface. Context: rig_stream_caps record context. Source: include/hamlib/rig.h:2036. */
        }
        attribute 'hamlib.struct.rig_stream_caps.max_streams' : Integer[0..1] {
            doc /* Meaning: Concurrent streams of this type. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int32_t max_streams. Owner: AudioInterface. Context: rig_stream_caps record context. Source: include/hamlib/rig.h:2044. */
        }
        attribute 'hamlib.struct.rig_stream_caps.tx_schedule_horizon_ms' : Integer[0..1] {
            doc /* Meaning: Max lead time for a timed TX * burst (0 = not schedulable). Unit: ms. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int32_t tx_schedule_horizon_ms. Owner: AudioInterface. Context: rig_stream_caps record context. Source: include/hamlib/rig.h:2045. */
        }
        attribute 'hamlib.struct.rig_stream_caps.caps_flags' : Integer[0..1] {
            doc /* Meaning: RIG_STREAM_CAP_* (8-aligned * offset by construction). Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint64_t caps_flags. Owner: AudioInterface. Context: rig_stream_caps record context. Source: include/hamlib/rig.h:2047. */
        }
        attribute 'hamlib.struct.rig_stream_caps.native_formats' : Integer[0..1] {
            doc /* Meaning: rig_stream_caps.native_formats. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: rig_stream_format_t native_formats. Owner: AudioInterface. Context: rig_stream_caps record context. Source: include/hamlib/rig.h:2054. */
        }
        attribute 'hamlib.struct.rig_stream_caps.native_sample_rates' : Integer[*] {
            doc /* Meaning: 0-terminated. Unit: sample/s. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int32_t native_sample_rates[HAMLIB_MAX_STREAM_RATES]. Owner: AudioInterface. Context: rig_stream_caps record context. Source: include/hamlib/rig.h:2055. */
        }
        attribute 'hamlib.struct.rig_stream_caps.native_channels' : Integer[*] {
            doc /* Meaning: 0-terminated. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int32_t native_channels[HAMLIB_MAX_STREAM_CHANNEL_COUNTS]. Owner: AudioInterface. Context: rig_stream_caps record context. Source: include/hamlib/rig.h:2056. */
        }
    }
    attribute def HamlibRigStreamConfigProperties {
        attribute 'hamlib.struct.rig_stream_config.type' : Integer[0..1] {
            doc /* Meaning: rig_stream_config.type. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: rig_stream_type_t type. Owner: AudioInterface. Context: rig_stream_config record context. Source: include/hamlib/rig.h:2077. */
        }
        attribute 'hamlib.struct.rig_stream_config.format' : Integer[0..1] {
            doc /* Meaning: Single RIG_STREAM_FORMAT_* value. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: rig_stream_format_t format. Owner: AudioInterface. Context: rig_stream_config record context. Source: include/hamlib/rig.h:2078. */
        }
        attribute 'hamlib.struct.rig_stream_config.sample_rate' : Integer[0..1] {
            doc /* Meaning: rig_stream_config.sample_rate. Unit: sample/s. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int32_t sample_rate. Owner: AudioInterface. Context: rig_stream_config record context. Source: include/hamlib/rig.h:2079. */
        }
        attribute 'hamlib.struct.rig_stream_config.channels' : Integer[0..1] {
            doc /* Meaning: rig_stream_config.channels. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int32_t channels. Owner: AudioInterface. Context: rig_stream_config record context. Source: include/hamlib/rig.h:2080. */
        }
        attribute 'hamlib.struct.rig_stream_config.frame_samples' : Integer[0..1] {
            doc /* Meaning: Samples per frame (0 = backend default). Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int32_t frame_samples. Owner: AudioInterface. Context: rig_stream_config record context. Source: include/hamlib/rig.h:2081. */
        }
        attribute 'hamlib.struct.rig_stream_config.buffer_bytes' : Integer[0..1] {
            doc /* Meaning: Ring buffer capacity in bytes (0 = default). Unit: byte. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: size_t buffer_bytes. Owner: AudioInterface. Context: rig_stream_config record context. Source: include/hamlib/rig.h:2082. */
        }
        attribute 'hamlib.struct.rig_stream_config.buffer_duration_ms' : Integer[0..1] {
            doc /* Meaning: If non-zero and buffer_bytes==0, derive size. Unit: ms. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint32_t buffer_duration_ms. Owner: AudioInterface. Context: rig_stream_config record context. Source: include/hamlib/rig.h:2083. */
        }
        attribute 'hamlib.struct.rig_stream_config.time_stale_coarse_ms' : Integer[0..1] {
            doc /* Meaning: Staleness: downgrade accuracy to * COARSE (0 = rig/built-in default). Unit: ms. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint32_t time_stale_coarse_ms. Owner: AudioInterface. Context: rig_stream_config record context. Source: include/hamlib/rig.h:2084. */
        }
        attribute 'hamlib.struct.rig_stream_config.time_stale_invalidate_ms' : Integer[0..1] {
            doc /* Meaning: Staleness: clear time_valid * (0 = rig/built-in default). Unit: ms. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint32_t time_stale_invalidate_ms. Owner: AudioInterface. Context: rig_stream_config record context. Source: include/hamlib/rig.h:2086. */
        }
        attribute 'hamlib.struct.rig_stream_config.mtu' : Integer[0..1] {
            doc /* Meaning: Sender path MTU in bytes for * datagram packetization (0 = * default 1500). Clamped to a * jumbo-frame ceiling; query the * effective, frame-aligned payload * with rig_stream_get_max_payload().. Unit: byte. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint32_t mtu. Owner: AudioInterface. Context: rig_stream_config record context. Source: include/hamlib/rig.h:2088. */
        }
        attribute 'hamlib.struct.rig_stream_config.transport_buffer_ms' : Integer[0..1] {
            doc /* Meaning: Transport buffer as ms of stream * data (0 = rig token / built-in * 250 ms). Overridden by transport_buffer_bytes.. Unit: ms. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint32_t transport_buffer_ms. Owner: AudioInterface. Context: rig_stream_config record context. Source: include/hamlib/rig.h:2094. */
        }
        attribute 'hamlib.struct.rig_stream_config.transport_buffer_bytes' : Integer[0..1] {
            doc /* Meaning: Explicit transport buffer bytes * (0 = derive from transport_buffer_ms/rate). Unit: byte. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint32_t transport_buffer_bytes. Owner: AudioInterface. Context: rig_stream_config record context. Source: include/hamlib/rig.h:2097. */
        }
        attribute 'hamlib.struct.rig_stream_config.require_native' : Integer[0..1] {
            doc /* Meaning: Stages that MUST be served * natively, as a bitmask of * RIG_STREAM_CONV_*: the open fails * with -RIG_ENAVAIL rather than * install any stage listed here. * RIG_STREAM_CONV_NONE (0, the * default) = convert whatever the * request needs; RIG_STREAM_CONV_ALL * = a fully native stream. Stages * left out are still converted as * needed, so RIG_STREAM_CONV_RATE * alone demands a native sample rate * while allowing format and channel * conversion.. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint32_t require_native. Owner: AudioInterface. Context: rig_stream_config record context. Source: include/hamlib/rig.h:2099. */
        }
    }
    attribute def HamlibRigStreamMetadataProperties {
        attribute 'hamlib.struct.rig_stream_metadata.field_mask' : Integer[0..1] {
            doc /* Meaning: Which fields are valid (RIG_STREAM_META_*). Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint32_t field_mask. Owner: AudioInterface. Context: rig_stream_metadata record context. Source: include/hamlib/rig.h:2129. */
        }
        attribute 'hamlib.struct.rig_stream_metadata.sample_index' : Integer[0..1] {
            doc /* Meaning: Sample index this metadata applies to (matches the 64-bit packet-header timestamp). Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint64_t sample_index. Owner: AudioInterface. Context: rig_stream_metadata record context. Source: include/hamlib/rig.h:2130. */
        }
        attribute 'hamlib.struct.rig_stream_metadata.vfo_id' : Integer[0..1] {
            doc /* Meaning: VFO identifier. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint8_t vfo_id. Owner: AudioInterface. Context: rig_stream_metadata record context. Source: include/hamlib/rig.h:2132. */
        }
        attribute 'hamlib.struct.rig_stream_metadata.ptt' : Integer[0..1] {
            doc /* Meaning: PTT state (0=RX, 1=TX). Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint8_t ptt. Owner: AudioInterface. Context: rig_stream_metadata record context. Source: include/hamlib/rig.h:2133. */
        }
        attribute 'hamlib.struct.rig_stream_metadata.center_freq' : Real[0..1] {
            doc /* Meaning: RF center of the I/Q window in Hz; the frequency that maps to DC/baseband. Mandatory for I/Q streams (equals vfo_freq for radios whose window tracks the dial). Unused for audio.. Unit: Hz. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: freq_t center_freq. Owner: AudioInterface. Context: rig_stream_metadata record context. Source: include/hamlib/rig.h:2134. */
        }
        attribute 'hamlib.struct.rig_stream_metadata.vfo_freq' : Real[0..1] {
            doc /* Meaning: Primary demod (dial) frequency in Hz. Optional: for a multi-slice I/Q window it is the primary slice or absent.. Unit: Hz. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: freq_t vfo_freq. Owner: AudioInterface. Context: rig_stream_metadata record context. Source: include/hamlib/rig.h:2139. */
        }
    }
    attribute def HamlibRigStreamReadInfoProperties {
        attribute 'hamlib.struct.rig_stream_read_info.sample_index' : Integer[0..1] {
            doc /* Meaning: producer index of first returned sample. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint64_t sample_index. Owner: AudioInterface. Context: rig_stream_read_info record context. Source: include/hamlib/rig.h:2207. */
        }
        attribute 'hamlib.struct.rig_stream_read_info.dropped_samples' : Integer[0..1] {
            doc /* Meaning: known-size hole before this read, any cause (marked gap and/or overrun). Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint32_t dropped_samples. Owner: AudioInterface. Context: rig_stream_read_info record context. Source: include/hamlib/rig.h:2208. */
        }
        attribute 'hamlib.struct.rig_stream_read_info.drop_flags' : Integer[0..1] {
            doc /* Meaning: RIG_STREAM_DROP_* cause attribution. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint8_t drop_flags. Owner: AudioInterface. Context: rig_stream_read_info record context. Source: include/hamlib/rig.h:2210. */
        }
        attribute 'hamlib.struct.rig_stream_read_info.time_valid' : Integer[0..1] {
            doc /* Meaning: 1 if the time fields are meaningful. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int32_t time_valid. Owner: AudioInterface. Context: rig_stream_read_info record context. Source: include/hamlib/rig.h:2211. */
        }
        attribute 'hamlib.struct.rig_stream_read_info.seconds' : Integer[0..1] {
            doc /* Meaning: UTC, Unix epoch. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int64_t seconds. Owner: AudioInterface. Context: rig_stream_read_info record context. Source: include/hamlib/rig.h:2212. */
        }
        attribute 'hamlib.struct.rig_stream_read_info.picoseconds' : Integer[0..1] {
            doc /* Meaning: 0..999,999,999,999. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint64_t picoseconds. Owner: AudioInterface. Context: rig_stream_read_info record context. Source: include/hamlib/rig.h:2213. */
        }
        attribute 'hamlib.struct.rig_stream_read_info.time_source' : Integer[0..1] {
            doc /* Meaning: enum rig_stream_time_source. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint8_t time_source. Owner: AudioInterface. Context: rig_stream_read_info record context. Source: include/hamlib/rig.h:2214. */
        }
        attribute 'hamlib.struct.rig_stream_read_info.time_flags' : Integer[0..1] {
            doc /* Meaning: RIG_STREAM_TIME_FLAG_*. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint8_t time_flags. Owner: AudioInterface. Context: rig_stream_read_info record context. Source: include/hamlib/rig.h:2215. */
        }
        attribute 'hamlib.struct.rig_stream_read_info.time_accuracy' : Integer[0..1] {
            doc /* Meaning: enum rig_stream_time_accuracy. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint8_t time_accuracy. Owner: AudioInterface. Context: rig_stream_read_info record context. Source: include/hamlib/rig.h:2216. */
        }
        attribute 'hamlib.struct.rig_stream_read_info.codec_frame_samples' : Integer[0..1] {
            doc /* Meaning: Codec streams: decoded duration of the * returned codec frame in samples (0 = * unknown). Raw streams: 0. (Occupies * former tail padding; the reserved * array below is untouched.). Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint32_t codec_frame_samples. Owner: AudioInterface. Context: rig_stream_read_info record context. Source: include/hamlib/rig.h:2217. */
        }
    }
    attribute def HamlibRigStreamStatsProperties {
        attribute 'hamlib.struct.rig_stream_stats.overruns' : Integer[0..1] {
            doc /* Meaning: local ring full on write; oldest overwritten. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint32_t overruns. Owner: AudioInterface. Context: rig_stream_stats record context. Source: include/hamlib/rig.h:2251. */
        }
        attribute 'hamlib.struct.rig_stream_stats.underruns' : Integer[0..1] {
            doc /* Meaning: local blocking read timed out empty. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint32_t underruns. Owner: AudioInterface. Context: rig_stream_stats record context. Source: include/hamlib/rig.h:2252. */
        }
        attribute 'hamlib.struct.rig_stream_stats.gaps' : Integer[0..1] {
            doc /* Meaning: radio/network-side gaps marked by backend. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint32_t gaps. Owner: AudioInterface. Context: rig_stream_stats record context. Source: include/hamlib/rig.h:2253. */
        }
        attribute 'hamlib.struct.rig_stream_stats.gaps_unknown' : Integer[0..1] {
            doc /* Meaning: subset of gaps with unknown size. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint32_t gaps_unknown. Owner: AudioInterface. Context: rig_stream_stats record context. Source: include/hamlib/rig.h:2254. */
        }
        attribute 'hamlib.struct.rig_stream_stats.link_loss' : Integer[0..1] {
            doc /* Meaning: network client only: app-link UDP loss. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint32_t link_loss. Owner: AudioInterface. Context: rig_stream_stats record context. Source: include/hamlib/rig.h:2255. */
        }
        attribute 'hamlib.struct.rig_stream_stats.tx_late' : Integer[0..1] {
            doc /* Meaning: timed TX bursts that missed their slot. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint32_t tx_late. Owner: AudioInterface. Context: rig_stream_stats record context. Source: include/hamlib/rig.h:2256. */
        }
        attribute 'hamlib.struct.rig_stream_stats.remote_overruns' : Integer[0..1] {
            doc /* Meaning: TX ring overruns / RX overrun-replay upstream. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint32_t remote_overruns. Owner: AudioInterface. Context: rig_stream_stats record context. Source: include/hamlib/rig.h:2258. */
        }
        attribute 'hamlib.struct.rig_stream_stats.remote_underruns' : Integer[0..1] {
            doc /* Meaning: TX ring underruns reported by the server. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint32_t remote_underruns. Owner: AudioInterface. Context: rig_stream_stats record context. Source: include/hamlib/rig.h:2259. */
        }
        attribute 'hamlib.struct.rig_stream_stats.write_events_dropped' : Integer[0..1] {
            doc /* Meaning: write-status events dropped on FIFO overflow. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint32_t write_events_dropped. Owner: AudioInterface. Context: rig_stream_stats record context. Source: include/hamlib/rig.h:2260. */
        }
        attribute 'hamlib.struct.rig_stream_stats.dropped_samples_gap' : Integer[0..1] {
            doc /* Meaning: lower bound if gaps_unknown > 0. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint64_t dropped_samples_gap. Owner: AudioInterface. Context: rig_stream_stats record context. Source: include/hamlib/rig.h:2262. */
        }
        attribute 'hamlib.struct.rig_stream_stats.dropped_samples_overrun' : Integer[0..1] {
            doc /* Meaning: rig_stream_stats.dropped_samples_overrun. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint64_t dropped_samples_overrun. Owner: AudioInterface. Context: rig_stream_stats record context. Source: include/hamlib/rig.h:2263. */
        }
        attribute 'hamlib.struct.rig_stream_stats.dropped_samples_link' : Integer[0..1] {
            doc /* Meaning: network client only. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint64_t dropped_samples_link. Owner: AudioInterface. Context: rig_stream_stats record context. Source: include/hamlib/rig.h:2264. */
        }
        attribute 'hamlib.struct.rig_stream_stats.codec_frames' : Integer[0..1] {
            doc /* Meaning: Codec streams: whole codec frames produced through the ring (equals the datagram count today â€” one frame per datagram â€” but counts frames, surviving any future packing). 0 on raw streams.. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint64_t codec_frames. Owner: AudioInterface. Context: rig_stream_stats record context. Source: include/hamlib/rig.h:2265. */
        }
    }
    attribute def HamlibRigStreamTimeAnchorProperties {
        attribute 'hamlib.struct.rig_stream_time_anchor.sample_index' : Integer[0..1] {
            doc /* Meaning: ring-buffer producer domain. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint64_t sample_index. Owner: AudioInterface. Context: rig_stream_time_anchor record context. Source: include/hamlib/rig.h:2196. */
        }
        attribute 'hamlib.struct.rig_stream_time_anchor.seconds' : Integer[0..1] {
            doc /* Meaning: UTC, Unix epoch. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int64_t seconds. Owner: AudioInterface. Context: rig_stream_time_anchor record context. Source: include/hamlib/rig.h:2197. */
        }
        attribute 'hamlib.struct.rig_stream_time_anchor.picoseconds' : Integer[0..1] {
            doc /* Meaning: 0..999,999,999,999. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint64_t picoseconds. Owner: AudioInterface. Context: rig_stream_time_anchor record context. Source: include/hamlib/rig.h:2198. */
        }
        attribute 'hamlib.struct.rig_stream_time_anchor.source' : Integer[0..1] {
            doc /* Meaning: enum rig_stream_time_source. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint8_t source. Owner: AudioInterface. Context: rig_stream_time_anchor record context. Source: include/hamlib/rig.h:2199. */
        }
        attribute 'hamlib.struct.rig_stream_time_anchor.flags' : Integer[0..1] {
            doc /* Meaning: RIG_STREAM_TIME_FLAG_*. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint8_t flags. Owner: AudioInterface. Context: rig_stream_time_anchor record context. Source: include/hamlib/rig.h:2200. */
        }
        attribute 'hamlib.struct.rig_stream_time_anchor.accuracy' : Integer[0..1] {
            doc /* Meaning: enum rig_stream_time_accuracy. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint8_t accuracy. Owner: AudioInterface. Context: rig_stream_time_anchor record context. Source: include/hamlib/rig.h:2201. */
        }
    }
    attribute def HamlibRigStreamWriteInfoProperties {
        attribute 'hamlib.struct.rig_stream_write_info.time_valid' : Integer[0..1] {
            doc /* Meaning: 0 = send immediately (no scheduling). Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int32_t time_valid. Owner: AudioInterface. Context: rig_stream_write_info record context. Source: include/hamlib/rig.h:2232. */
        }
        attribute 'hamlib.struct.rig_stream_write_info.seconds' : Integer[0..1] {
            doc /* Meaning: UTC target. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int64_t seconds. Owner: AudioInterface. Context: rig_stream_write_info record context. Source: include/hamlib/rig.h:2233. */
        }
        attribute 'hamlib.struct.rig_stream_write_info.picoseconds' : Integer[0..1] {
            doc /* Meaning: 0..999,999,999,999. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint64_t picoseconds. Owner: AudioInterface. Context: rig_stream_write_info record context. Source: include/hamlib/rig.h:2234. */
        }
        attribute 'hamlib.struct.rig_stream_write_info.flags' : Integer[0..1] {
            doc /* Meaning: SOB/EOB. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint8_t flags. Owner: AudioInterface. Context: rig_stream_write_info record context. Source: include/hamlib/rig.h:2235. */
        }
        attribute 'hamlib.struct.rig_stream_write_info.codec_frame_samples' : Integer[0..1] {
            doc /* Meaning: Codec streams: decoded duration of the * written codec frame in samples, declared * by the application (0 allowed = unknown; * timing features then degrade). Ignored * for raw streams. (Occupies former tail * padding; the reserved array below is * untouched.). Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint32_t codec_frame_samples. Owner: AudioInterface. Context: rig_stream_write_info record context. Source: include/hamlib/rig.h:2236. */
        }
    }
    attribute def HamlibRigStreamWriteStatusProperties {
        attribute 'hamlib.struct.rig_stream_write_status.event' : Integer[0..1] {
            doc /* Meaning: enum rig_stream_write_event. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint16_t event. Owner: AudioInterface. Context: rig_stream_write_status record context. Source: include/hamlib/rig.h:2294. */
        }
        attribute 'hamlib.struct.rig_stream_write_status.flags' : Integer[0..1] {
            doc /* Meaning: RIG_STREAM_WRITE_STATUS_*. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint16_t flags. Owner: AudioInterface. Context: rig_stream_write_status record context. Source: include/hamlib/rig.h:2295. */
        }
        attribute 'hamlib.struct.rig_stream_write_status.sample_index' : Integer[0..1] {
            doc /* Meaning: producer index the event refers to. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint64_t sample_index. Owner: AudioInterface. Context: rig_stream_write_status record context. Source: include/hamlib/rig.h:2296. */
        }
        attribute 'hamlib.struct.rig_stream_write_status.dropped_samples' : Integer[0..1] {
            doc /* Meaning: samples lost on UNDERRUN/OVERRUN; 0 if N/A. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint32_t dropped_samples. Owner: AudioInterface. Context: rig_stream_write_status record context. Source: include/hamlib/rig.h:2297. */
        }
        attribute 'hamlib.struct.rig_stream_write_status.lateness' : Integer[0..1] {
            doc /* Meaning: samples a timed burst was late (LATE); 0 if N/A. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int64_t lateness. Owner: AudioInterface. Context: rig_stream_write_status record context. Source: include/hamlib/rig.h:2298. */
        }
        attribute 'hamlib.struct.rig_stream_write_status.time_valid' : Integer[0..1] {
            doc /* Meaning: 1 if seconds/picoseconds are meaningful. Unit: s. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int32_t time_valid. Owner: AudioInterface. Context: rig_stream_write_status record context. Source: include/hamlib/rig.h:2299. */
        }
        attribute 'hamlib.struct.rig_stream_write_status.seconds' : Integer[0..1] {
            doc /* Meaning: UTC, Unix epoch. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: int64_t seconds. Owner: AudioInterface. Context: rig_stream_write_status record context. Source: include/hamlib/rig.h:2300. */
        }
        attribute 'hamlib.struct.rig_stream_write_status.picoseconds' : Integer[0..1] {
            doc /* Meaning: 0..999,999,999,999. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint64_t picoseconds. Owner: AudioInterface. Context: rig_stream_write_status record context. Source: include/hamlib/rig.h:2301. */
        }
        attribute 'hamlib.struct.rig_stream_write_status.time_source' : Integer[0..1] {
            doc /* Meaning: enum rig_stream_time_source. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint8_t time_source. Owner: AudioInterface. Context: rig_stream_write_status record context. Source: include/hamlib/rig.h:2302. */
        }
        attribute 'hamlib.struct.rig_stream_write_status.time_flags' : Integer[0..1] {
            doc /* Meaning: RIG_STREAM_TIME_FLAG_*. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint8_t time_flags. Owner: AudioInterface. Context: rig_stream_write_status record context. Source: include/hamlib/rig.h:2303. */
        }
        attribute 'hamlib.struct.rig_stream_write_status.time_accuracy' : Integer[0..1] {
            doc /* Meaning: enum rig_stream_time_accuracy. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: uint8_t time_accuracy. Owner: AudioInterface. Context: rig_stream_write_status record context. Source: include/hamlib/rig.h:2304. */
        }
    }
    attribute def HamlibTuningStepListProperties {
        attribute 'hamlib.struct.tuning_step_list.modes' : Integer[0..1] {
            doc /* Meaning: Bit field of RIG_MODE's. Unit: unspecified; do not infer units. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: rmode_t modes. Owner: physicalRadio/model definition. Context: tuning_step_list record context. Source: include/hamlib/rig.h:1569. */
        }
        attribute 'hamlib.struct.tuning_step_list.ts' : Integer[0..1] {
            doc /* Meaning: Tuning step in Hz. Unit: Hz. Access/role: record member; capability/configuration/state according to containing record.
                 Source type: shortfreq_t ts. Owner: physicalRadio/model definition. Context: tuning_step_list record context. Source: include/hamlib/rig.h:1570. */
        }
    }
    attribute def HamlibVendorProperties {
        attribute 'hamlib.extension.rigs/aor/ar7030p.c::ar7030p_ext_levels::TOK_EL_MAGICFUNC' : Boolean[0..1] {
            doc /* Meaning: Magic function, as an example. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio/vendor extension. Context: backend-defined; may be global or VFO. Source: rigs/aor/ar7030p.c:154. */
        }
        attribute 'hamlib.extension.rigs/aor/ar7030p.c::ar7030p_ext_levels::TOK_EL_MAGICLEVEL' : Real[0..1] {
            doc /* Meaning: Magic level, as an example. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio/vendor extension. Context: backend-defined; may be global or VFO. Source: rigs/aor/ar7030p.c:149. */
        }
        attribute 'hamlib.extension.rigs/aor/ar7030p.c::ar7030p_ext_levels::TOK_EL_MAGICOP' : RadioInteractionDefinition[0..1] {
            doc /* Meaning: Magic Op, as an example. Unit: unspecified; do not infer units. Access/role: action/button; not a persistent Boolean state.
                 Source type: RIG_CONF_BUTTON. Owner: physicalRadio/vendor extension. Context: backend-defined; may be global or VFO. Source: rigs/aor/ar7030p.c:159. */
        }
        attribute 'hamlib.extension.rigs/aor/ar7030p.c::ar7030p_ext_parms::TOK_EP_MAGICPARM' : Real[0..1] {
            doc /* Meaning: Magic parameter, as an example. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio/vendor extension. Context: backend-defined; may be global or VFO. Source: rigs/aor/ar7030p.c:169. */
        }
        attribute 'hamlib.extension.rigs/dummy/dummy.c::dummy_ext_funcs::TOK_EL_MAGICEXTFUNC' : Boolean[0..1] {
            doc /* Meaning: Magic ext function, as an example. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/dummy/dummy.c:80. */
        }
        attribute 'hamlib.extension.rigs/dummy/dummy.c::dummy_ext_levels::TOK_EL_MAGICCOMBO' : String[0..1] {
            doc /* Meaning: Magic combo, as an example. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/dummy/dummy.c:71. */
        }
        attribute 'hamlib.extension.rigs/dummy/dummy.c::dummy_ext_levels::TOK_EL_MAGICFUNC' : Boolean[0..1] {
            doc /* Meaning: Magic function, as an example. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/dummy/dummy.c:63. */
        }
        attribute 'hamlib.extension.rigs/dummy/dummy.c::dummy_ext_levels::TOK_EL_MAGICLEVEL' : Real[0..1] {
            doc /* Meaning: Magic level, as an example. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/dummy/dummy.c:59. */
        }
        attribute 'hamlib.extension.rigs/dummy/dummy.c::dummy_ext_levels::TOK_EL_MAGICOP' : RadioInteractionDefinition[0..1] {
            doc /* Meaning: Magic Op, as an example. Unit: unspecified; do not infer units. Access/role: action/button; not a persistent Boolean state.
                 Source type: RIG_CONF_BUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/dummy/dummy.c:67. */
        }
        attribute 'hamlib.extension.rigs/dummy/dummy.c::dummy_ext_parms::TOK_EP_MAGICPARM' : Real[0..1] {
            doc /* Meaning: Magic parameter, as an example. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/dummy/dummy.c:90. */
        }
        attribute 'hamlib.extension.rigs/dummy/flrig.c::flrig_ext_parms::TOK_FLRIG_VERIFY_FREQ' : Boolean[0..1] {
            doc /* Meaning: If true will verify set_freq otherwise is fire and forget. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: rig-global. Source: rigs/dummy/flrig.c:138. */
        }
        attribute 'hamlib.extension.rigs/dummy/flrig.c::flrig_ext_parms::TOK_FLRIG_VERIFY_PTT' : Boolean[0..1] {
            doc /* Meaning: If true will verify set_ptt otherwise set_ptt is fire and forget. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: rig-global. Source: rigs/dummy/flrig.c:141. */
        }
        attribute 'hamlib.extension.rigs/dummy/tci1x.c::tci1x_ext_parms::TOK_TCI1X_VERIFY_FREQ' : Boolean[0..1] {
            doc /* Meaning: If true will verify set_freq otherwise is fire and forget. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: rig-global. Source: rigs/dummy/tci1x.c:130. */
        }
        attribute 'hamlib.extension.rigs/dummy/tci1x.c::tci1x_ext_parms::TOK_TCI1X_VERIFY_PTT' : Boolean[0..1] {
            doc /* Meaning: If true will verify set_ptt otherwise set_ptt is fire and forget. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: rig-global. Source: rigs/dummy/tci1x.c:133. */
        }
        attribute 'hamlib.extension.rigs/icom/ic746.c::ic746pro_ext_parms::TOK_RTTY_FLTR' : String[0..1] {
            doc /* Meaning: Set/Read RTTY preset filter width. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: rig-global. Source: rigs/icom/ic746.c:381. */
        }
        attribute 'hamlib.extension.rigs/icom/ic746.c::ic746pro_ext_parms::TOK_SQLCTRL' : String[0..1] {
            doc /* Meaning: set RF/Squelch control. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: rig-global. Source: rigs/icom/ic746.c:377. */
        }
        attribute 'hamlib.extension.rigs/icom/ic746.c::ic746pro_ext_parms::TOK_SSBBASS' : Real[0..1] {
            doc /* Meaning: SSB Tx Tone (Bass). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/icom/ic746.c:373. */
        }
        attribute 'hamlib.extension.rigs/icom/ic756.c::ic756pro2_ext_parms::TOK_MEMNAME' : Boolean[0..1] {
            doc /* Meaning: Show memory name. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: rig-global. Source: rigs/icom/ic756.c:503. */
        }
        attribute 'hamlib.extension.rigs/icom/ic756.c::ic756pro2_ext_parms::TOK_MYCALL' : String[0..1] {
            doc /* Meaning: My call sign. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_STRING. Owner: physicalRadio. Context: rig-global. Source: rigs/icom/ic756.c:511. */
        }
        attribute 'hamlib.extension.rigs/icom/ic756.c::ic756pro2_ext_parms::TOK_RTTY_FLTR' : String[0..1] {
            doc /* Meaning: Set/Read RTTY preset filter width. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: rig-global. Source: rigs/icom/ic756.c:515. */
        }
        attribute 'hamlib.extension.rigs/icom/ic756.c::ic756pro2_ext_parms::TOK_SQLCTRL' : String[0..1] {
            doc /* Meaning: set RF/Squelch control. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: rig-global. Source: rigs/icom/ic756.c:507. */
        }
        attribute 'hamlib.extension.rigs/icom/ic756.c::ic756pro2_ext_parms::TOK_SSBBASS' : Real[0..1] {
            doc /* Meaning: SSB Tx Tone (Bass). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/icom/ic756.c:499. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_ext_funcs::TOK_DIGI_SEL_FUNC' : Boolean[0..1] {
            doc /* Meaning: DIGI-SEL enable. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/icom/icom.c:443. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_ext_funcs::TOK_DPP_FUNC' : Boolean[0..1] {
            doc /* Meaning: Digital Pre Distortion-SEL enable. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/icom/icom.c:446. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_ext_funcs::TOK_ICPW2_FUNC' : Boolean[0..1] {
            doc /* Meaning: Icom PW2 enable. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/icom/icom.c:447. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_ext_funcs::TOK_IPP_FUNC' : Boolean[0..1] {
            doc /* Meaning: IP Plus. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/icom/icom.c:444. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_ext_funcs::TOK_TX_INHIBIT_FUNC' : Boolean[0..1] {
            doc /* Meaning: TX Inhibit. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/icom/icom.c:445. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_ext_levels::TOK_DIGI_SEL_LEVEL' : Real[0..1] {
            doc /* Meaning: DIGI-SEL level. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/icom/icom.c:456. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_ext_levels::TOK_DRIVE_GAIN' : Real[0..1] {
            doc /* Meaning: Drive gain. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/icom/icom.c:457. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_ext_levels::TOK_SCOPE_CFQ' : String[0..1] {
            doc /* Meaning: Spectrum Scope Center Frequency Type. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/icom/icom.c:462. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_ext_levels::TOK_SCOPE_EDG' : String[0..1] {
            doc /* Meaning: Edge selection for fixed scope mode. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/icom/icom.c:460. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_ext_levels::TOK_SCOPE_MSS' : String[0..1] {
            doc /* Meaning: Spectrum Scope Main/Sub. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/icom/icom.c:458. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_ext_levels::TOK_SCOPE_RBW' : String[0..1] {
            doc /* Meaning: Resolution Band Width. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/icom/icom.c:464. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_ext_levels::TOK_SCOPE_SDS' : String[0..1] {
            doc /* Meaning: Spectrum Scope Single/Dual. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/icom/icom.c:459. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_ext_levels::TOK_SCOPE_STX' : Boolean[0..1] {
            doc /* Meaning: Spectrum Scope TX operation. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/icom/icom.c:461. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_ext_levels::TOK_SCOPE_VBW' : String[0..1] {
            doc /* Meaning: Video Band Width. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/icom/icom.c:463. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_ext_parms::TOK_DSTAR_CALL_SIGN' : Integer[*] {
            doc /* Meaning: D-STAR Call sign. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_BINARY. Owner: physicalRadio. Context: rig-global. Source: rigs/icom/icom.c:474. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_ext_parms::TOK_DSTAR_CODE' : Real[0..1] {
            doc /* Meaning: D-STAR CSQL Code. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/icom/icom.c:479. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_ext_parms::TOK_DSTAR_DSQL' : Boolean[0..1] {
            doc /* Meaning: D-STAR CSQL Status. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: rig-global. Source: rigs/icom/icom.c:473. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_ext_parms::TOK_DSTAR_GPS_DATA' : Integer[*] {
            doc /* Meaning: D-STAR GPS Data. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_BINARY. Owner: physicalRadio. Context: rig-global. Source: rigs/icom/icom.c:477. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_ext_parms::TOK_DSTAR_GPS_MESS' : String[0..1] {
            doc /* Meaning: D-STAR GPS Message. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_STRING. Owner: physicalRadio. Context: rig-global. Source: rigs/icom/icom.c:478. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_ext_parms::TOK_DSTAR_MESSAGE' : String[0..1] {
            doc /* Meaning: D-STAR Rx Message. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_STRING. Owner: physicalRadio. Context: rig-global. Source: rigs/icom/icom.c:475. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_ext_parms::TOK_DSTAR_MY_CS' : String[0..1] {
            doc /* Meaning: D-STAR MY Call Sign. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_STRING. Owner: physicalRadio. Context: rig-global. Source: rigs/icom/icom.c:481. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_ext_parms::TOK_DSTAR_STATUS' : Integer[*] {
            doc /* Meaning: D-STAR Rx Status. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_BINARY. Owner: physicalRadio. Context: rig-global. Source: rigs/icom/icom.c:476. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_ext_parms::TOK_DSTAR_TX_CS' : Integer[*] {
            doc /* Meaning: D-STAR Tx Call Sign. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_BINARY. Owner: physicalRadio. Context: rig-global. Source: rigs/icom/icom.c:482. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_ext_parms::TOK_DSTAR_TX_DATA' : Integer[*] {
            doc /* Meaning: D-STAR Tx Data. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_BINARY. Owner: physicalRadio. Context: rig-global. Source: rigs/icom/icom.c:480. */
        }
        attribute 'hamlib.extension.rigs/icom/icom.c::icom_ext_parms::TOK_DSTAR_TX_MESS' : String[0..1] {
            doc /* Meaning: D-STAR Tx Message. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_STRING. Owner: physicalRadio. Context: rig-global. Source: rigs/icom/icom.c:483. */
        }
        attribute 'hamlib.extension.rigs/icom/icr30.c::icr30_ext::TOK_ANL' : Boolean[0..1] {
            doc /* Meaning: Auto noise limiter. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/icom/icr30.c:59. */
        }
        attribute 'hamlib.extension.rigs/icom/icr30.c::icr30_ext::TOK_EAR' : Boolean[0..1] {
            doc /* Meaning: Earphone mode. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/icom/icr30.c:60. */
        }
        attribute 'hamlib.extension.rigs/icom/icr30.c::icr30_ext::TOK_REC' : Boolean[0..1] {
            doc /* Meaning: Recorder on/off. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/icom/icr30.c:61. */
        }
        attribute 'hamlib.extension.rigs/icom/optoscan.c::opto_ext_parms::TOK_5KHZWIN' : Boolean[0..1] {
            doc /* Meaning: Toggles 5kHz search window. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: rig-global. Source: rigs/icom/optoscan.c:46. */
        }
        attribute 'hamlib.extension.rigs/icom/optoscan.c::opto_ext_parms::TOK_AUDIO' : Boolean[0..1] {
            doc /* Meaning: Audio present. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: rig-global. Source: rigs/icom/optoscan.c:48. */
        }
        attribute 'hamlib.extension.rigs/icom/optoscan.c::opto_ext_parms::TOK_CTCSSACT' : Boolean[0..1] {
            doc /* Meaning: CTCSS Tone Active. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: rig-global. Source: rigs/icom/optoscan.c:51. */
        }
        attribute 'hamlib.extension.rigs/icom/optoscan.c::opto_ext_parms::TOK_DCSACT' : Boolean[0..1] {
            doc /* Meaning: DCS Code Active. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: rig-global. Source: rigs/icom/optoscan.c:52. */
        }
        attribute 'hamlib.extension.rigs/icom/optoscan.c::opto_ext_parms::TOK_DTMFOVRR' : Boolean[0..1] {
            doc /* Meaning: DTMF Buffer Overflow. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: rig-global. Source: rigs/icom/optoscan.c:50. */
        }
        attribute 'hamlib.extension.rigs/icom/optoscan.c::opto_ext_parms::TOK_DTMFPEND' : Boolean[0..1] {
            doc /* Meaning: DTMF Digit Pending. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: rig-global. Source: rigs/icom/optoscan.c:49. */
        }
        attribute 'hamlib.extension.rigs/icom/optoscan.c::opto_ext_parms::TOK_SPEAKER' : Boolean[0..1] {
            doc /* Meaning: Toggles speaker audio. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: rig-global. Source: rigs/icom/optoscan.c:47. */
        }
        attribute 'hamlib.extension.rigs/icom/optoscan.c::opto_ext_parms::TOK_TAPECNTL' : Boolean[0..1] {
            doc /* Meaning: Toggles built in tape switch. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: rig-global. Source: rigs/icom/optoscan.c:45. */
        }
        attribute 'hamlib.extension.rigs/kenwood/elecraft.c::elecraft_ext_levels::TOK_IF_FREQ' : Real[0..1] {
            doc /* Meaning: IF center frequency. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/elecraft.c:64. */
        }
        attribute 'hamlib.extension.rigs/kenwood/elecraft.c::elecraft_ext_levels::TOK_RIT_CLR' : RadioInteractionDefinition[0..1] {
            doc /* Meaning: RIT clear. Unit: unspecified; do not infer units. Access/role: action/button; not a persistent Boolean state.
                 Source type: RIG_CONF_BUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/elecraft.c:72. */
        }
        attribute 'hamlib.extension.rigs/kenwood/elecraft.c::elecraft_ext_levels::TOK_TX_STAT' : Boolean[0..1] {
            doc /* Meaning: TX status. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/elecraft.c:68. */
        }
        attribute 'hamlib.extension.rigs/kenwood/k3.c::k3_ext_levels::TOK_ESSB' : Boolean[0..1] {
            doc /* Meaning: Extended SSB frequency response. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/k3.c:92. */
        }
        attribute 'hamlib.extension.rigs/kenwood/k3.c::k3_ext_levels::TOK_IF_FREQ' : Real[0..1] {
            doc /* Meaning: IF center frequency. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/k3.c:80. */
        }
        attribute 'hamlib.extension.rigs/kenwood/k3.c::k3_ext_levels::TOK_IF_NB' : Real[0..1] {
            doc /* Meaning: IF noise blanker level. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/k3.c:108. */
        }
        attribute 'hamlib.extension.rigs/kenwood/k3.c::k3_ext_levels::TOK_LINK_VFOS' : Boolean[0..1] {
            doc /* Meaning: Link VFOs. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/k3.c:100. */
        }
        attribute 'hamlib.extension.rigs/kenwood/k3.c::k3_ext_levels::TOK_RIT_CLR' : RadioInteractionDefinition[0..1] {
            doc /* Meaning: RIT clear. Unit: unspecified; do not infer units. Access/role: action/button; not a persistent Boolean state.
                 Source type: RIG_CONF_BUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/k3.c:88. */
        }
        attribute 'hamlib.extension.rigs/kenwood/k3.c::k3_ext_levels::TOK_RX_ANT' : Boolean[0..1] {
            doc /* Meaning: RX antenna. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/k3.c:96. */
        }
        attribute 'hamlib.extension.rigs/kenwood/k3.c::k3_ext_levels::TOK_TX_METER' : String[0..1] {
            doc /* Meaning: Transmit meter mode. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/k3.c:104. */
        }
        attribute 'hamlib.extension.rigs/kenwood/k3.c::k3_ext_levels::TOK_TX_STAT' : Boolean[0..1] {
            doc /* Meaning: TX status. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/k3.c:84. */
        }
        attribute 'hamlib.extension.rigs/kenwood/k3.c::kx3_ext_levels::TOK_ESSB' : Boolean[0..1] {
            doc /* Meaning: Extended SSB frequency response. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/k3.c:131. */
        }
        attribute 'hamlib.extension.rigs/kenwood/k3.c::kx3_ext_levels::TOK_RIT_CLR' : RadioInteractionDefinition[0..1] {
            doc /* Meaning: RIT clear. Unit: unspecified; do not infer units. Access/role: action/button; not a persistent Boolean state.
                 Source type: RIG_CONF_BUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/k3.c:127. */
        }
        attribute 'hamlib.extension.rigs/kenwood/k3.c::kx3_ext_levels::TOK_TX_STAT' : Boolean[0..1] {
            doc /* Meaning: TX status. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/k3.c:123. */
        }
        attribute 'hamlib.extension.rigs/kenwood/kenwood.c::kenwood_cfg_params::TOK_FINE' : Boolean[0..1] {
            doc /* Meaning: Fine step mode. Unit: unspecified; do not infer units. Access/role: radio operating toggle via ext_parm API.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: rig-global. Source: rigs/kenwood/kenwood.c:214. */
        }
        attribute 'hamlib.extension.rigs/kenwood/kenwood.c::kenwood_cfg_params::TOK_RIT' : Boolean[0..1] {
            doc /* Meaning: RIT. Unit: unspecified; do not infer units. Access/role: radio operating toggle via ext_parm API.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: rig-global. Source: rigs/kenwood/kenwood.c:226. */
        }
        attribute 'hamlib.extension.rigs/kenwood/kenwood.c::kenwood_cfg_params::TOK_VOICE' : RadioInteractionDefinition[0..1] {
            doc /* Meaning: Voice recall. Unit: unspecified; do not infer units. Access/role: radio voice-announcement action via ext_parm API.
                 Source type: RIG_CONF_BUTTON. Owner: physicalRadio. Context: rig-global. Source: rigs/kenwood/kenwood.c:218. */
        }
        attribute 'hamlib.extension.rigs/kenwood/kenwood.c::kenwood_cfg_params::TOK_XIT' : Boolean[0..1] {
            doc /* Meaning: XIT. Unit: unspecified; do not infer units. Access/role: radio operating toggle via ext_parm API.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: rig-global. Source: rigs/kenwood/kenwood.c:222. */
        }
        attribute 'hamlib.extension.rigs/kenwood/tmd710.c::tmd710_ext_levels::TOK_LEVEL_EXT_DATA_BAND' : String[0..1] {
            doc /* Meaning: External data band. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/tmd710.c:248. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts2000.c::ts2000_ext_funcs::TOK_FUNC_NOISE_REDUCTION_2' : Boolean[0..1] {
            doc /* Meaning: Noise reduction 2. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts2000.c:130. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts2000.c::ts2000_ext_levels::TOK_LEVEL_BEEP_VOLUME' : Real[0..1] {
            doc /* Meaning: Beep volume. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts2000.c:151. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts2000.c::ts2000_ext_levels::TOK_LEVEL_DSP_RX_EQUALIZER' : String[0..1] {
            doc /* Meaning: DSP RX equalizer type. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts2000.c:139. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts2000.c::ts2000_ext_levels::TOK_LEVEL_DSP_TX_BANDWIDTH' : String[0..1] {
            doc /* Meaning: DSP TX bandwidth for SSB and AM. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts2000.c:147. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts2000.c::ts2000_ext_levels::TOK_LEVEL_DSP_TX_EQUALIZER' : String[0..1] {
            doc /* Meaning: DSP TX equalizer type. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts2000.c:143. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts2000.c::ts2000_ext_levels::TOK_LEVEL_TX_SIDETONE_VOLUME' : Real[0..1] {
            doc /* Meaning: TX sidetone volume. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts2000.c:155. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts450s.c::ts450_ext_parms::TOK_FINE' : Boolean[0..1] {
            doc /* Meaning: Fine step mode. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: rig-global. Source: rigs/kenwood/ts450s.c:58. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts450s.c::ts450_ext_parms::TOK_RIT' : Boolean[0..1] {
            doc /* Meaning: RIT. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: rig-global. Source: rigs/kenwood/ts450s.c:70. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts450s.c::ts450_ext_parms::TOK_VOICE' : RadioInteractionDefinition[0..1] {
            doc /* Meaning: Voice recall. Unit: unspecified; do not infer units. Access/role: action/button; not a persistent Boolean state.
                 Source type: RIG_CONF_BUTTON. Owner: physicalRadio. Context: rig-global. Source: rigs/kenwood/ts450s.c:62. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts450s.c::ts450_ext_parms::TOK_XIT' : Boolean[0..1] {
            doc /* Meaning: XIT. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: rig-global. Source: rigs/kenwood/ts450s.c:66. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts480.c::ts480_ext_funcs::TOK_FUNC_CW_IF_FOR_SSB_RX' : Boolean[0..1] {
            doc /* Meaning: Use CW IF filter for SSB reception. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts480.c:127. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts480.c::ts480_ext_funcs::TOK_FUNC_FILTER_WIDTH_DATA' : Boolean[0..1] {
            doc /* Meaning: Filter bandwidth for data communications. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts480.c:131. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts480.c::ts480_ext_funcs::TOK_FUNC_NOISE_REDUCTION_2' : Boolean[0..1] {
            doc /* Meaning: Noise reduction 2. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts480.c:123. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts480.c::ts480_ext_funcs::TOK_FUNC_TX_AUDIO_FROM_DATA_INPUT' : Boolean[0..1] {
            doc /* Meaning: Transmit with audio input from the data terminal. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts480.c:135. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts480.c::ts480_ext_levels::TOK_LEVEL_AF_INPUT_LEVEL' : Real[0..1] {
            doc /* Meaning: AF input level for data communications. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts480.c:168. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts480.c::ts480_ext_levels::TOK_LEVEL_AF_OUTPUT_LEVEL' : Real[0..1] {
            doc /* Meaning: AF output level for data communications. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts480.c:172. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts480.c::ts480_ext_levels::TOK_LEVEL_BEEP_VOLUME' : Real[0..1] {
            doc /* Meaning: Beep volume. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts480.c:160. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts480.c::ts480_ext_levels::TOK_LEVEL_DIGITAL_NOISE_LIMITER' : String[0..1] {
            doc /* Meaning: Digital Noise Limiter. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts480.c:144. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts480.c::ts480_ext_levels::TOK_LEVEL_DSP_RX_EQUALIZER' : String[0..1] {
            doc /* Meaning: DSP RX equalizer type. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts480.c:148. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts480.c::ts480_ext_levels::TOK_LEVEL_DSP_TX_BANDWIDTH' : String[0..1] {
            doc /* Meaning: DSP TX bandwidth for SSB and AM. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts480.c:156. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts480.c::ts480_ext_levels::TOK_LEVEL_DSP_TX_EQUALIZER' : String[0..1] {
            doc /* Meaning: DSP TX equalizer type. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts480.c:152. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts480.c::ts480_ext_levels::TOK_LEVEL_TX_SIDETONE_VOLUME' : Real[0..1] {
            doc /* Meaning: TX sidetone volume. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts480.c:164. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts590.c::ts590_ext_funcs::TOK_FUNC_NOISE_REDUCTION_2' : Boolean[0..1] {
            doc /* Meaning: Noise reduction 2. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts590.c:123. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts590.c::ts590_ext_levels::TOK_LEVEL_ACC2_AUDIO_INPUT_LEVEL' : Real[0..1] {
            doc /* Meaning: ACC2 audio input level. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts590.c:148. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts590.c::ts590_ext_levels::TOK_LEVEL_ACC2_AUDIO_OUTPUT_LEVEL' : Real[0..1] {
            doc /* Meaning: ACC2 audio output level. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts590.c:152. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts590.c::ts590_ext_levels::TOK_LEVEL_BEEP_VOLUME' : Real[0..1] {
            doc /* Meaning: Beep volume. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts590.c:140. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts590.c::ts590_ext_levels::TOK_LEVEL_DSP_RX_EQUALIZER' : String[0..1] {
            doc /* Meaning: DSP RX equalizer type. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts590.c:132. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts590.c::ts590_ext_levels::TOK_LEVEL_DSP_TX_EQUALIZER' : String[0..1] {
            doc /* Meaning: DSP TX equalizer type. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts590.c:136. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts590.c::ts590_ext_levels::TOK_LEVEL_DSP_TX_SSB_AM_HIGH_CUT_FILTER' : String[0..1] {
            doc /* Meaning: DSP TX high-cut filter for SSB and AM. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts590.c:168. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts590.c::ts590_ext_levels::TOK_LEVEL_DSP_TX_SSB_AM_LOW_CUT_FILTER' : String[0..1] {
            doc /* Meaning: DSP TX low-cut filter for SSB and AM. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts590.c:164. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts590.c::ts590_ext_levels::TOK_LEVEL_DSP_TX_SSB_DATA_HIGH_CUT_FILTER' : String[0..1] {
            doc /* Meaning: DSP TX high-cut filter for SSB data. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts590.c:176. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts590.c::ts590_ext_levels::TOK_LEVEL_DSP_TX_SSB_DATA_LOW_CUT_FILTER' : String[0..1] {
            doc /* Meaning: DSP TX low-cut filter for SSB data. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts590.c:172. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts590.c::ts590_ext_levels::TOK_LEVEL_TX_SIDETONE_VOLUME' : Real[0..1] {
            doc /* Meaning: TX sidetone volume. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts590.c:144. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts590.c::ts590_ext_levels::TOK_LEVEL_USB_AUDIO_INPUT_LEVEL' : Real[0..1] {
            doc /* Meaning: USB audio input level. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts590.c:156. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts590.c::ts590_ext_levels::TOK_LEVEL_USB_AUDIO_OUTPUT_LEVEL' : Real[0..1] {
            doc /* Meaning: USB audio output level. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kenwood/ts590.c:160. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts850.c::ts850_ext_parms::TOK_FINE' : Boolean[0..1] {
            doc /* Meaning: Fine step mode. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: rig-global. Source: rigs/kenwood/ts850.c:76. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts850.c::ts850_ext_parms::TOK_RIT' : Boolean[0..1] {
            doc /* Meaning: RIT. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: rig-global. Source: rigs/kenwood/ts850.c:88. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts850.c::ts850_ext_parms::TOK_VOICE' : RadioInteractionDefinition[0..1] {
            doc /* Meaning: Voice recall. Unit: unspecified; do not infer units. Access/role: action/button; not a persistent Boolean state.
                 Source type: RIG_CONF_BUTTON. Owner: physicalRadio. Context: rig-global. Source: rigs/kenwood/ts850.c:80. */
        }
        attribute 'hamlib.extension.rigs/kenwood/ts850.c::ts850_ext_parms::TOK_XIT' : Boolean[0..1] {
            doc /* Meaning: XIT. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: rig-global. Source: rigs/kenwood/ts850.c:84. */
        }
        attribute 'hamlib.extension.rigs/kit/fifisdr.c::fifisdr_ext_levels::TOK_LVL_FMCENTER' : Real[0..1] {
            doc /* Meaning: Center frequency deviation of FM signal. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/kit/fifisdr.c:106. */
        }
        attribute 'hamlib.extension.rigs/pcr/pcr100.c::pcr_ext_levels::TOK_EL_ANL' : Boolean[0..1] {
            doc /* Meaning: Auto Noise Limiter. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/pcr/pcr100.c:39. */
        }
        attribute 'hamlib.extension.rigs/pcr/pcr2500.c::pcr2500_ext_levels::TOK_EL_DIVERSITY' : Boolean[0..1] {
            doc /* Meaning: Antenna/tuner diversity. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/pcr/pcr2500.c:44. */
        }
        attribute 'hamlib.extension.rigs/simplecat/simplecat.c::simplecat_ext_parms::TOK_ABORT' : RadioInteractionDefinition[0..1] {
            doc /* Meaning: Abort transmission. Unit: unspecified; do not infer units. Access/role: action/button; not a persistent Boolean state.
                 Source type: RIG_CONF_BUTTON. Owner: physicalRadio. Context: rig-global. Source: rigs/simplecat/simplecat.c:1034. */
        }
        attribute 'hamlib.extension.rigs/simplecat/simplecat.c::simplecat_ext_parms::TOK_DIGMODE' : String[0..1] {
            doc /* Meaning: Digital Mode (FT8/FT4). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_STRING. Owner: physicalRadio. Context: rig-global. Source: rigs/simplecat/simplecat.c:1007. */
        }
        attribute 'hamlib.extension.rigs/simplecat/simplecat.c::simplecat_ext_parms::TOK_ITONE' : String[0..1] {
            doc /* Meaning: ITONE Symbol Data. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_STRING. Owner: physicalRadio. Context: rig-global. Source: rigs/simplecat/simplecat.c:1016. */
        }
        attribute 'hamlib.extension.rigs/simplecat/simplecat.c::simplecat_ext_parms::TOK_ITONEHASH' : String[0..1] {
            doc /* Meaning: ITONE Data MD5 Hash. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_STRING. Owner: physicalRadio. Context: rig-global. Source: rigs/simplecat/simplecat.c:1025. */
        }
        attribute 'hamlib.extension.rigs/simplecat/simplecat.c::simplecat_ext_parms::TOK_OFFSET' : Real[0..1] {
            doc /* Meaning: TX Offset frequency in Hz. Unit: Hz. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/simplecat/simplecat.c:998. */
        }
        attribute 'hamlib.extension.rigs/simplecat/simplecat.c::simplecat_ext_parms::TOK_VERSION' : String[0..1] {
            doc /* Meaning: Get firmware version string. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_STRING. Owner: physicalRadio. Context: rig-global. Source: rigs/simplecat/simplecat.c:1043. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft1200.c::ftdx1200_ext_levels::TOK_APF_FREQ' : Real[0..1] {
            doc /* Meaning: Audio peak filter frequency. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft1200.c:99. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft1200.c::ftdx1200_ext_levels::TOK_APF_WIDTH' : String[0..1] {
            doc /* Meaning: Audio peak filter width. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft1200.c:108. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft1200.c::ftdx1200_ext_levels::TOK_CONTOUR' : Boolean[0..1] {
            doc /* Meaning: Contour on/off. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft1200.c:117. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft1200.c::ftdx1200_ext_levels::TOK_CONTOUR_FREQ' : Real[0..1] {
            doc /* Meaning: Contour frequency. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft1200.c:125. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft1200.c::ftdx1200_ext_levels::TOK_CONTOUR_LEVEL' : Real[0..1] {
            doc /* Meaning: Contour level (dB). Unit: dB. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft1200.c:134. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft1200.c::ftdx1200_ext_levels::TOK_CONTOUR_WIDTH' : Real[0..1] {
            doc /* Meaning: Contour width. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft1200.c:143. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft1200.c::ftdx1200_ext_levels::TOK_KEYER' : Boolean[0..1] {
            doc /* Meaning: Keyer on/off. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft1200.c:91. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft1200.c::ftdx1200_ext_levels::TOK_ROOFING_FILTER' : String[0..1] {
            doc /* Meaning: Roofing filter. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft1200.c:74. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft2000.c::ft2000_ext_levels::TOK_CONTOUR' : Boolean[0..1] {
            doc /* Meaning: Contour on/off. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft2000.c:102. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft2000.c::ft2000_ext_levels::TOK_CONTOUR_FREQ' : Real[0..1] {
            doc /* Meaning: Contour frequency. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft2000.c:110. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft2000.c::ft2000_ext_levels::TOK_CONTOUR_LEVEL' : Real[0..1] {
            doc /* Meaning: Contour level (dB). Unit: dB. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft2000.c:119. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft2000.c::ft2000_ext_levels::TOK_CONTOUR_WIDTH' : Real[0..1] {
            doc /* Meaning: Contour width. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft2000.c:128. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft2000.c::ft2000_ext_levels::TOK_KEYER' : Boolean[0..1] {
            doc /* Meaning: Keyer on/off. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft2000.c:94. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft2000.c::ft2000_ext_levels::TOK_ROOFING_FILTER' : String[0..1] {
            doc /* Meaning: Roofing filter. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft2000.c:77. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft3000.c::ftdx3000_ext_levels::TOK_APF_FREQ' : Real[0..1] {
            doc /* Meaning: Audio peak filter frequency. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft3000.c:88. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft3000.c::ftdx3000_ext_levels::TOK_APF_WIDTH' : String[0..1] {
            doc /* Meaning: Audio peak filter width. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft3000.c:97. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft3000.c::ftdx3000_ext_levels::TOK_CONTOUR' : Boolean[0..1] {
            doc /* Meaning: Contour on/off. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft3000.c:106. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft3000.c::ftdx3000_ext_levels::TOK_CONTOUR_FREQ' : Real[0..1] {
            doc /* Meaning: Contour frequency. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft3000.c:114. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft3000.c::ftdx3000_ext_levels::TOK_CONTOUR_LEVEL' : Real[0..1] {
            doc /* Meaning: Contour level (dB). Unit: dB. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft3000.c:123. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft3000.c::ftdx3000_ext_levels::TOK_CONTOUR_WIDTH' : Real[0..1] {
            doc /* Meaning: Contour width. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft3000.c:132. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft3000.c::ftdx3000_ext_levels::TOK_KEYER' : Boolean[0..1] {
            doc /* Meaning: Keyer on/off. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft3000.c:80. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft3000.c::ftdx3000_ext_levels::TOK_ROOFING_FILTER' : String[0..1] {
            doc /* Meaning: Roofing filter. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft3000.c:63. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft5000.c::ftdx5000_ext_levels::TOK_APF_WIDTH' : String[0..1] {
            doc /* Meaning: Audio peak filter width. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft5000.c:94. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft5000.c::ftdx5000_ext_levels::TOK_CONTOUR' : Boolean[0..1] {
            doc /* Meaning: Contour on/off. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft5000.c:103. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft5000.c::ftdx5000_ext_levels::TOK_CONTOUR_FREQ' : Real[0..1] {
            doc /* Meaning: Contour frequency. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft5000.c:111. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft5000.c::ftdx5000_ext_levels::TOK_CONTOUR_LEVEL' : Real[0..1] {
            doc /* Meaning: Contour level (dB). Unit: dB. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft5000.c:120. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft5000.c::ftdx5000_ext_levels::TOK_CONTOUR_WIDTH' : Real[0..1] {
            doc /* Meaning: Contour width. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft5000.c:129. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft5000.c::ftdx5000_ext_levels::TOK_KEYER' : Boolean[0..1] {
            doc /* Meaning: Keyer on/off. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft5000.c:86. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft5000.c::ftdx5000_ext_levels::TOK_ROOFING_FILTER' : String[0..1] {
            doc /* Meaning: Roofing filter. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft5000.c:69. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft710.c::ft710_ext_levels::TOK_APF_FREQ' : Real[0..1] {
            doc /* Meaning: Audio peak filter frequency. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft710.c:56. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft710.c::ft710_ext_levels::TOK_APF_WIDTH' : String[0..1] {
            doc /* Meaning: Audio peak filter width. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft710.c:65. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft710.c::ft710_ext_levels::TOK_CONTOUR' : Boolean[0..1] {
            doc /* Meaning: Contour on/off. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft710.c:74. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft710.c::ft710_ext_levels::TOK_CONTOUR_FREQ' : Real[0..1] {
            doc /* Meaning: Contour frequency. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft710.c:82. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft710.c::ft710_ext_levels::TOK_CONTOUR_LEVEL' : Real[0..1] {
            doc /* Meaning: Contour level (dB). Unit: dB. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft710.c:91. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft710.c::ft710_ext_levels::TOK_CONTOUR_WIDTH' : Real[0..1] {
            doc /* Meaning: Contour width. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft710.c:100. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft710.c::ft710_ext_levels::TOK_KEYER' : Boolean[0..1] {
            doc /* Meaning: Keyer on/off. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft710.c:48. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft891.c::ft891_ext_levels::TOK_APF_FREQ' : Real[0..1] {
            doc /* Meaning: Audio peak filter frequency. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft891.c:64. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft891.c::ft891_ext_levels::TOK_APF_WIDTH' : String[0..1] {
            doc /* Meaning: Audio peak filter width. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft891.c:73. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft891.c::ft891_ext_levels::TOK_CONTOUR' : Boolean[0..1] {
            doc /* Meaning: Contour on/off. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft891.c:82. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft891.c::ft891_ext_levels::TOK_CONTOUR_FREQ' : Real[0..1] {
            doc /* Meaning: Contour frequency. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft891.c:90. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft891.c::ft891_ext_levels::TOK_CONTOUR_LEVEL' : Real[0..1] {
            doc /* Meaning: Contour level (dB). Unit: dB. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft891.c:99. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft891.c::ft891_ext_levels::TOK_CONTOUR_WIDTH' : Real[0..1] {
            doc /* Meaning: Contour width. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft891.c:108. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft891.c::ft891_ext_levels::TOK_KEYER' : Boolean[0..1] {
            doc /* Meaning: Keyer on/off. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft891.c:56. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft950.c::ft950_ext_levels::TOK_ROOFING_FILTER' : String[0..1] {
            doc /* Meaning: Roofing filter. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft950.c:71. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft991.c::ft991_ext_levels::TOK_APF_FREQ' : Real[0..1] {
            doc /* Meaning: Audio peak filter frequency. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft991.c:72. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft991.c::ft991_ext_levels::TOK_APF_WIDTH' : String[0..1] {
            doc /* Meaning: Audio peak filter width. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft991.c:81. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft991.c::ft991_ext_levels::TOK_CONTOUR' : Boolean[0..1] {
            doc /* Meaning: Contour on/off. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft991.c:90. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft991.c::ft991_ext_levels::TOK_CONTOUR_FREQ' : Real[0..1] {
            doc /* Meaning: Contour frequency. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft991.c:98. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft991.c::ft991_ext_levels::TOK_CONTOUR_LEVEL' : Real[0..1] {
            doc /* Meaning: Contour level (dB). Unit: dB. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft991.c:107. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft991.c::ft991_ext_levels::TOK_CONTOUR_WIDTH' : Real[0..1] {
            doc /* Meaning: Contour width. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft991.c:116. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft991.c::ft991_ext_levels::TOK_KEYER' : Boolean[0..1] {
            doc /* Meaning: Keyer on/off. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft991.c:64. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft991.c::ft991_ext_levels::TOK_MAXPOWER_6M' : Integer[0..1] {
            doc /* Meaning: Maxpower 6m. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_INT. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft991.c:134. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft991.c::ft991_ext_levels::TOK_MAXPOWER_HF' : Integer[0..1] {
            doc /* Meaning: Maxpower HF. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_INT. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft991.c:125. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft991.c::ft991_ext_levels::TOK_MAXPOWER_UHF' : Real[0..1] {
            doc /* Meaning: Maxpower UHF. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft991.c:152. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ft991.c::ft991_ext_levels::TOK_MAXPOWER_VHF' : Integer[0..1] {
            doc /* Meaning: Maxpower VHF. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_INT. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ft991.c:143. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftdx10.c::ftdx10_ext_levels::TOK_APF_FREQ' : Real[0..1] {
            doc /* Meaning: Audio peak filter frequency. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ftdx10.c:72. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftdx10.c::ftdx10_ext_levels::TOK_APF_WIDTH' : String[0..1] {
            doc /* Meaning: Audio peak filter width. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ftdx10.c:81. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftdx10.c::ftdx10_ext_levels::TOK_CONTOUR' : Boolean[0..1] {
            doc /* Meaning: Contour on/off. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ftdx10.c:90. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftdx10.c::ftdx10_ext_levels::TOK_CONTOUR_FREQ' : Real[0..1] {
            doc /* Meaning: Contour frequency. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ftdx10.c:98. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftdx10.c::ftdx10_ext_levels::TOK_CONTOUR_LEVEL' : Real[0..1] {
            doc /* Meaning: Contour level (dB). Unit: dB. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ftdx10.c:107. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftdx10.c::ftdx10_ext_levels::TOK_CONTOUR_WIDTH' : Real[0..1] {
            doc /* Meaning: Contour width. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ftdx10.c:116. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftdx10.c::ftdx10_ext_levels::TOK_KEYER' : Boolean[0..1] {
            doc /* Meaning: Keyer on/off. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ftdx10.c:64. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftdx10.c::ftdx10_ext_levels::TOK_ROOFING_FILTER' : String[0..1] {
            doc /* Meaning: Roofing filter. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ftdx10.c:55. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftdx101.c::ftdx101d_ext_levels::TOK_APF_FREQ' : Real[0..1] {
            doc /* Meaning: Audio peak filter frequency. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ftdx101.c:86. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftdx101.c::ftdx101d_ext_levels::TOK_APF_WIDTH' : String[0..1] {
            doc /* Meaning: Audio peak filter width. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ftdx101.c:95. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftdx101.c::ftdx101d_ext_levels::TOK_CONTOUR' : Boolean[0..1] {
            doc /* Meaning: Contour on/off. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ftdx101.c:104. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftdx101.c::ftdx101d_ext_levels::TOK_CONTOUR_FREQ' : Real[0..1] {
            doc /* Meaning: Contour frequency. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ftdx101.c:112. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftdx101.c::ftdx101d_ext_levels::TOK_CONTOUR_LEVEL' : Real[0..1] {
            doc /* Meaning: Contour level (dB). Unit: dB. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ftdx101.c:121. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftdx101.c::ftdx101d_ext_levels::TOK_CONTOUR_WIDTH' : Real[0..1] {
            doc /* Meaning: Contour width. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ftdx101.c:130. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftdx101.c::ftdx101d_ext_levels::TOK_KEYER' : Boolean[0..1] {
            doc /* Meaning: Keyer on/off. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_CHECKBUTTON. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ftdx101.c:78. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftdx101.c::ftdx101d_ext_levels::TOK_MAXPOWER_4M' : Integer[0..1] {
            doc /* Meaning: Maxpower 4m. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_INT. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ftdx101.c:157. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftdx101.c::ftdx101d_ext_levels::TOK_MAXPOWER_6M' : Integer[0..1] {
            doc /* Meaning: Maxpower 6m. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_INT. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ftdx101.c:148. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftdx101.c::ftdx101d_ext_levels::TOK_MAXPOWER_AM' : Real[0..1] {
            doc /* Meaning: Maxpower AM. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ftdx101.c:166. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftdx101.c::ftdx101d_ext_levels::TOK_MAXPOWER_HF' : Integer[0..1] {
            doc /* Meaning: Maxpower HF. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_INT. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ftdx101.c:139. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftdx101.c::ftdx101d_ext_levels::TOK_ROOFING_FILTER' : String[0..1] {
            doc /* Meaning: Roofing filter. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ftdx101.c:69. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftdx101mp.c::ftdx101mp_ext_levels::TOK_ROOFING_FILTER' : String[0..1] {
            doc /* Meaning: Roofing filter. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_COMBO. Owner: physicalRadio. Context: binding/context defined; per-model record identifies extension kind. Source: rigs/yaesu/ftdx101mp.c:56. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_AM_AGC_FAST' : Real[0..1] {
            doc /* Meaning: AM_AGC_FAST (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:182. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_AM_AGC_MID' : Real[0..1] {
            doc /* Meaning: AM_AGC_MID (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:183. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_AM_AGC_SLOW' : Real[0..1] {
            doc /* Meaning: AM_AGC_SLOW (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:184. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_AM_HCUT_FREQ' : Real[0..1] {
            doc /* Meaning: AM_HCUT_FREQ (0-67). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:187. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_AM_HCUT_SLOPE' : Real[0..1] {
            doc /* Meaning: AM_HCUT_SLOPE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:188. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_AM_LCUT_FREQ' : Real[0..1] {
            doc /* Meaning: AM_LCUT_FREQ (0-19). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:185. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_AM_LCUT_SLOPE' : Real[0..1] {
            doc /* Meaning: AM_LCUT_SLOPE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:186. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_AM_MOD_SOURCE' : Real[0..1] {
            doc /* Meaning: AM_MOD_SOURCE (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:191. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_AM_RPTT_SELECT' : Real[0..1] {
            doc /* Meaning: AM_RPTT_SELECT (0-2). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:193. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_AM_TX_BPF_SEL' : Real[0..1] {
            doc /* Meaning: AM_TX_BPF_SEL (0-4). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:190. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_AM_USB_MOD_GAIN' : Real[0..1] {
            doc /* Meaning: AM_USB_MOD_GAIN (0-100). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:192. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_AM_USB_OUT_LEVEL' : Real[0..1] {
            doc /* Meaning: AM_USB_OUT_LEVEL (0-100). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:189. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_APRS_AF_MUTE' : Real[0..1] {
            doc /* Meaning: APRS_AF_MUTE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:198. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_APRS_MODEM_SEL' : Real[0..1] {
            doc /* Meaning: APRS_MODEM_SEL (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:196. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_APRS_MODEM_TYPE' : Real[0..1] {
            doc /* Meaning: APRS_MODEM_TYPE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:197. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_APRS_MY_SYMBOL' : Real[0..1] {
            doc /* Meaning: APRS_MY_SYMBOL (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:200. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_APRS_PATH_SEL' : Real[0..1] {
            doc /* Meaning: APRS_PATH_SEL (0-2). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:201. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_APRS_TX_DELAY' : Real[0..1] {
            doc /* Meaning: APRS_TX_DELAY (0-6). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:199. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_ATAS_CTRL' : Real[0..1] {
            doc /* Meaning: ATAS control (write): 0=stop,1=up,2=down,3=start. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:576. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_BCN_ALTITUDE' : Real[0..1] {
            doc /* Meaning: BCN_ALTITUDE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:207. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_BCN_AUTO_LOW_SPD' : Real[0..1] {
            doc /* Meaning: BCN_AUTO_LOW_SPD (1-99). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:213. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_BCN_DECAY' : Real[0..1] {
            doc /* Meaning: BCN_DECAY (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:212. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_BCN_DELAY' : Real[0..1] {
            doc /* Meaning: BCN_DELAY (5-180). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:214. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_BCN_EMERGENCY' : Real[0..1] {
            doc /* Meaning: BCN_EMERGENCY (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:209. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_BCN_FREQ' : Real[0..1] {
            doc /* Meaning: BCN_FREQ (0-2). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:217. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_BCN_INFO_AMBIG' : Real[0..1] {
            doc /* Meaning: BCN_INFO_AMBIG (0-4). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:205. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_BCN_INTERVAL' : Real[0..1] {
            doc /* Meaning: BCN_INTERVAL (0-9). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:210. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_BCN_POS_COMMENT' : Real[0..1] {
            doc /* Meaning: BCN_POS_COMMENT (0-14). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:208. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_BCN_PROPORTIONAL' : Real[0..1] {
            doc /* Meaning: BCN_PROPORTIONAL (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:211. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_BCN_SPEED_COURSE' : Real[0..1] {
            doc /* Meaning: BCN_SPEED_COURSE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:206. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_BCN_TEXT_SEL' : Real[0..1] {
            doc /* Meaning: BCN_TEXT_SEL (0-5). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:215. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_BCN_TX_RATE' : Real[0..1] {
            doc /* Meaning: BCN_TX_RATE (0-7). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:216. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_BCN_TYPE' : Real[0..1] {
            doc /* Meaning: BCN_TYPE (0-2). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:204. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_BT_AUDIO' : Real[0..1] {
            doc /* Meaning: BT_AUDIO (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:221. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_BT_ENABLE' : Real[0..1] {
            doc /* Meaning: BT_ENABLE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:220. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_CW_AGC_FAST' : Real[0..1] {
            doc /* Meaning: CW_AGC_FAST (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:224. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_CW_AGC_MID' : Real[0..1] {
            doc /* Meaning: CW_AGC_MID (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:225. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_CW_AGC_SLOW' : Real[0..1] {
            doc /* Meaning: CW_AGC_SLOW (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:226. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_CW_BK_IN_TYPE' : Real[0..1] {
            doc /* Meaning: CW_BK_IN_TYPE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:235. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_CW_FREQ_DISPLAY' : Real[0..1] {
            doc /* Meaning: CW_FREQ_DISPLAY (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:236. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_CW_HCUT_FREQ' : Real[0..1] {
            doc /* Meaning: CW_HCUT_FREQ (0-67). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:229. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_CW_HCUT_SLOPE' : Real[0..1] {
            doc /* Meaning: CW_HCUT_SLOPE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:230. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_CW_INDICATOR' : Real[0..1] {
            doc /* Meaning: CW_INDICATOR (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:238. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_CW_LCUT_FREQ' : Real[0..1] {
            doc /* Meaning: CW_LCUT_FREQ (0-19). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:227. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_CW_LCUT_SLOPE' : Real[0..1] {
            doc /* Meaning: CW_LCUT_SLOPE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:228. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_CW_NAR_WIDTH' : Real[0..1] {
            doc /* Meaning: CW_NAR_WIDTH (0-20). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:233. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_CW_PC_KEYING' : Real[0..1] {
            doc /* Meaning: CW_PC_KEYING (0-2). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:234. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_CW_QSK_DELAY' : Real[0..1] {
            doc /* Meaning: CW_QSK_DELAY (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:237. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_CW_RPTT_SELECT' : Real[0..1] {
            doc /* Meaning: CW_RPTT_SELECT (0-2). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:232. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_CW_USB_OUT_LEVEL' : Real[0..1] {
            doc /* Meaning: CW_USB_OUT_LEVEL (0-100). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:231. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DATA_AGC_FAST' : Real[0..1] {
            doc /* Meaning: DATA_AGC_FAST (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:241. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DATA_AGC_MID' : Real[0..1] {
            doc /* Meaning: DATA_AGC_MID (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:242. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DATA_AGC_SLOW' : Real[0..1] {
            doc /* Meaning: DATA_AGC_SLOW (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:243. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DATA_HCUT_FREQ' : Real[0..1] {
            doc /* Meaning: DATA_HCUT_FREQ (0-67). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:246. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DATA_HCUT_SLOPE' : Real[0..1] {
            doc /* Meaning: DATA_HCUT_SLOPE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:247. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DATA_LCUT_FREQ' : Real[0..1] {
            doc /* Meaning: DATA_LCUT_FREQ (0-19). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:244. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DATA_LCUT_SLOPE' : Real[0..1] {
            doc /* Meaning: DATA_LCUT_SLOPE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:245. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DATA_MOD_SOURCE' : Real[0..1] {
            doc /* Meaning: DATA_MOD_SOURCE (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:250. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DATA_NAR_WIDTH' : Real[0..1] {
            doc /* Meaning: DATA_NAR_WIDTH (0-20). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:253. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DATA_PSK_TONE' : Real[0..1] {
            doc /* Meaning: DATA_PSK_TONE (0-2). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:254. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DATA_RPTT_SELECT' : Real[0..1] {
            doc /* Meaning: DATA_RPTT_SELECT (0-2). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:252. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DATA_SHIFT_SSB' : Real[0..1] {
            doc /* Meaning: DATA_SHIFT_SSB (0-3000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:255. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DATA_TX_BPF_SEL' : Real[0..1] {
            doc /* Meaning: DATA_TX_BPF_SEL (0-4). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:249. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DATA_USB_MOD_GAIN' : Real[0..1] {
            doc /* Meaning: DATA_USB_MOD_GAIN (0-100). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:251. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DATA_USB_OUT_LEVEL' : Real[0..1] {
            doc /* Meaning: DATA_USB_OUT_LEVEL (0-100). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:248. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DIAL_AM_CH_STEP' : Real[0..1] {
            doc /* Meaning: DIAL_AM_CH_STEP (0-5). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:261. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DIAL_CH_STEP' : Real[0..1] {
            doc /* Meaning: DIAL_CH_STEP (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:260. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DIAL_FM_CH_STEP' : Real[0..1] {
            doc /* Meaning: DIAL_FM_CH_STEP (0-5). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:262. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DIAL_FM_STEP' : Real[0..1] {
            doc /* Meaning: DIAL_FM_STEP (0-6). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:259. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DIAL_MAIN_STEPS' : Real[0..1] {
            doc /* Meaning: DIAL_MAIN_STEPS (0-2). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:263. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DIAL_MIC_DOWN' : Real[0..1] {
            doc /* Meaning: DIAL_MIC_DOWN (0-20). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:269. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DIAL_MIC_P1' : Real[0..1] {
            doc /* Meaning: DIAL_MIC_P1 (0-20). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:264. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DIAL_MIC_P2' : Real[0..1] {
            doc /* Meaning: DIAL_MIC_P2 (0-20). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:265. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DIAL_MIC_P3' : Real[0..1] {
            doc /* Meaning: DIAL_MIC_P3 (0-20). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:266. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DIAL_MIC_P4' : Real[0..1] {
            doc /* Meaning: DIAL_MIC_P4 (0-20). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:267. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DIAL_MIC_SCAN' : Real[0..1] {
            doc /* Meaning: DIAL_MIC_SCAN (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:270. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DIAL_MIC_UP' : Real[0..1] {
            doc /* Meaning: DIAL_MIC_UP (0-20). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:268. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DIAL_RTTY_PSK_STEP' : Real[0..1] {
            doc /* Meaning: DIAL_RTTY_PSK_STEP (0-2). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:258. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DIG_LOC_SERVICE' : Real[0..1] {
            doc /* Meaning: DIG_LOC_SERVICE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:274. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DIG_POPUP' : Real[0..1] {
            doc /* Meaning: DIG_POPUP (0-60). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:273. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DIG_STANDBY_BEEP' : Real[0..1] {
            doc /* Meaning: DIG_STANDBY_BEEP (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:275. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DISP_AUTO_PWR_OFF' : Real[0..1] {
            doc /* Meaning: DISP_AUTO_PWR_OFF (0-24). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:283. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DISP_MY_CALL_TIME' : Real[0..1] {
            doc /* Meaning: DISP_MY_CALL_TIME (0-5). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:278. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DISP_POPUP_TIME' : Real[0..1] {
            doc /* Meaning: DISP_POPUP_TIME (0-2). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:279. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DISP_SAVER_BAT' : Real[0..1] {
            doc /* Meaning: DISP_SAVER_BAT (0-6). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:281. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DISP_SAVER_TYPE' : Real[0..1] {
            doc /* Meaning: DISP_SAVER_TYPE (0-2). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:282. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DISP_SCREEN_SAVER' : Real[0..1] {
            doc /* Meaning: DISP_SCREEN_SAVER (0-6). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:280. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DSP_APF_WIDTH' : Real[0..1] {
            doc /* Meaning: DSP_APF_WIDTH (0-2). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:289. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DSP_CONTOUR_W' : Real[0..1] {
            doc /* Meaning: DSP_CONTOUR_W (1-11). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:290. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DSP_IF_NOTCH_W' : Real[0..1] {
            doc /* Meaning: DSP_IF_NOTCH_W (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:286. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DSP_NB_REJECTION' : Real[0..1] {
            doc /* Meaning: DSP_NB_REJECTION (0-2). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:287. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DSP_NB_WIDTH' : Real[0..1] {
            doc /* Meaning: DSP_NB_WIDTH (0-2). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:288. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DT_GPS_TIME_SET' : Real[0..1] {
            doc /* Meaning: DT_GPS_TIME_SET (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:293. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_DT_MY_POSITION' : Real[0..1] {
            doc /* Meaning: DT_MY_POSITION (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:294. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FILT_ALTNET' : Real[0..1] {
            doc /* Meaning: FILT_ALTNET (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:305. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FILT_ITEM' : Real[0..1] {
            doc /* Meaning: FILT_ITEM (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:302. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FILT_LIST_SORT' : Real[0..1] {
            doc /* Meaning: FILT_LIST_SORT (0-2). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:297. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FILT_MIC_E' : Real[0..1] {
            doc /* Meaning: FILT_MIC_E (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:298. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FILT_OBJECT' : Real[0..1] {
            doc /* Meaning: FILT_OBJECT (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:301. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FILT_OTHER' : Real[0..1] {
            doc /* Meaning: FILT_OTHER (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:304. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FILT_POPUP_BCN' : Real[0..1] {
            doc /* Meaning: FILT_POPUP_BCN (0-4). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:306. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FILT_POPUP_MSG' : Real[0..1] {
            doc /* Meaning: FILT_POPUP_MSG (0-4). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:307. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FILT_POPUP_MYPACKET' : Real[0..1] {
            doc /* Meaning: FILT_POPUP_MYPACKET (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:308. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FILT_POSITION' : Real[0..1] {
            doc /* Meaning: FILT_POSITION (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:299. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FILT_STATUS' : Real[0..1] {
            doc /* Meaning: FILT_STATUS (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:303. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FILT_WEATHER' : Real[0..1] {
            doc /* Meaning: FILT_WEATHER (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:300. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FM_AGC_FAST' : Real[0..1] {
            doc /* Meaning: FM_AGC_FAST (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:311. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FM_AGC_MID' : Real[0..1] {
            doc /* Meaning: FM_AGC_MID (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:312. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FM_AGC_SLOW' : Real[0..1] {
            doc /* Meaning: FM_AGC_SLOW (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:313. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FM_DCS_CODE' : Real[0..1] {
            doc /* Meaning: FM_DCS_CODE (0-103). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:329. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FM_DCS_RX_REV' : Real[0..1] {
            doc /* Meaning: FM_DCS_RX_REV (0-2). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:330. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FM_DCS_TX_REV' : Real[0..1] {
            doc /* Meaning: FM_DCS_TX_REV (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:331. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FM_DTMF_DELAY' : Real[0..1] {
            doc /* Meaning: FM_DTMF_DELAY (0-4). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:333. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FM_DTMF_SPEED' : Real[0..1] {
            doc /* Meaning: FM_DTMF_SPEED (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:334. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FM_HCUT_FREQ' : Real[0..1] {
            doc /* Meaning: FM_HCUT_FREQ (0-67). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:316. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FM_HCUT_SLOPE' : Real[0..1] {
            doc /* Meaning: FM_HCUT_SLOPE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:317. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FM_LCUT_FREQ' : Real[0..1] {
            doc /* Meaning: FM_LCUT_FREQ (0-19). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:314. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FM_LCUT_SLOPE' : Real[0..1] {
            doc /* Meaning: FM_LCUT_SLOPE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:315. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FM_MOD_SOURCE' : Real[0..1] {
            doc /* Meaning: FM_MOD_SOURCE (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:319. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FM_PR_FREQ' : Real[0..1] {
            doc /* Meaning: FM_PR_FREQ (300-3000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:332. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FM_RPTT_SELECT' : Real[0..1] {
            doc /* Meaning: FM_RPTT_SELECT (0-2). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:321. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FM_RPT_SHIFT' : Real[0..1] {
            doc /* Meaning: FM_RPT_SHIFT (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:322. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FM_RPT_SHIFT_144' : Real[0..1] {
            doc /* Meaning: FM_RPT_SHIFT_144 (0-100). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:325. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FM_RPT_SHIFT_28' : Real[0..1] {
            doc /* Meaning: FM_RPT_SHIFT_28 (0-1000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:323. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FM_RPT_SHIFT_430' : Real[0..1] {
            doc /* Meaning: FM_RPT_SHIFT_430 (0-100). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:326. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FM_RPT_SHIFT_50' : Real[0..1] {
            doc /* Meaning: FM_RPT_SHIFT_50 (0-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:324. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FM_SQL_TYPE' : Real[0..1] {
            doc /* Meaning: FM_SQL_TYPE (0-5). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:327. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FM_TONE_FREQ' : Real[0..1] {
            doc /* Meaning: FM_TONE_FREQ (0-49). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:328. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FM_USB_MOD_GAIN' : Real[0..1] {
            doc /* Meaning: FM_USB_MOD_GAIN (0-100). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:320. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_FM_USB_OUT_LEVEL' : Real[0..1] {
            doc /* Meaning: FM_USB_OUT_LEVEL (0-100). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:318. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_GEN_BEEP_LEVEL' : Real[0..1] {
            doc /* Meaning: GEN_BEEP_LEVEL (0-100). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:337. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_GEN_CAT1_RATE' : Real[0..1] {
            doc /* Meaning: GEN_CAT1_RATE (0-4). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:341. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_GEN_CAT1_STOP_BIT' : Real[0..1] {
            doc /* Meaning: GEN_CAT1_STOP_BIT (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:343. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_GEN_CAT1_TIMEOUT' : Real[0..1] {
            doc /* Meaning: GEN_CAT1_TIMEOUT (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:342. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_GEN_CAT2_RATE' : Real[0..1] {
            doc /* Meaning: GEN_CAT2_RATE (0-4). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:344. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_GEN_CAT2_TIMEOUT' : Real[0..1] {
            doc /* Meaning: GEN_CAT2_TIMEOUT (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:345. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_GEN_CAT3_RATE' : Real[0..1] {
            doc /* Meaning: GEN_CAT3_RATE (0-4). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:346. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_GEN_CAT3_TIMEOUT' : Real[0..1] {
            doc /* Meaning: GEN_CAT3_TIMEOUT (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:347. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_GEN_CHARGE_CTRL' : Real[0..1] {
            doc /* Meaning: GEN_CHARGE_CTRL (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:349. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_GEN_DITHER' : Real[0..1] {
            doc /* Meaning: GEN_DITHER (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:352. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_GEN_RF_SQL_VR' : Real[0..1] {
            doc /* Meaning: GEN_RF_SQL_VR (0-2). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:338. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_GEN_SPEAKER_SEL' : Real[0..1] {
            doc /* Meaning: GEN_SPEAKER_SEL (0-2). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:351. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_GEN_SUB_BAND_MUTE' : Real[0..1] {
            doc /* Meaning: GEN_SUB_BAND_MUTE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:350. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_GEN_TUNER_SELECT' : Real[0..1] {
            doc /* Meaning: General tuner select: 0=Option, 1=ATAS. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:340. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_GEN_TUN_LIN_PORT' : Real[0..1] {
            doc /* Meaning: GEN_TUN_LIN_PORT (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:339. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_GEN_TX_TIMEOUT' : Real[0..1] {
            doc /* Meaning: GEN_TX_TIMEOUT (0-30). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:348. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_KEYER_CONTEST_NUM' : Real[0..1] {
            doc /* Meaning: KEYER_CONTEST_NUM (1-9999). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:359. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_KEYER_CW_MEM1' : Real[0..1] {
            doc /* Meaning: KEYER_CW_MEM1 (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:360. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_KEYER_CW_MEM2' : Real[0..1] {
            doc /* Meaning: KEYER_CW_MEM2 (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:361. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_KEYER_CW_MEM3' : Real[0..1] {
            doc /* Meaning: KEYER_CW_MEM3 (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:362. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_KEYER_CW_MEM4' : Real[0..1] {
            doc /* Meaning: KEYER_CW_MEM4 (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:363. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_KEYER_CW_MEM5' : Real[0..1] {
            doc /* Meaning: KEYER_CW_MEM5 (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:364. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_KEYER_DOT_DASH' : Real[0..1] {
            doc /* Meaning: KEYER_DOT_DASH (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:356. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_KEYER_NUM_STYLE' : Real[0..1] {
            doc /* Meaning: KEYER_NUM_STYLE (0-6). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:358. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_KEYER_REPEAT_INT' : Real[0..1] {
            doc /* Meaning: KEYER_REPEAT_INT (1-60). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:365. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_KEYER_TYPE' : Real[0..1] {
            doc /* Meaning: KEYER_TYPE (0-5). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:355. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_KEYER_WEIGHT' : Real[0..1] {
            doc /* Meaning: KEYER_WEIGHT (0-20). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:357. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_OPT_144M_MAX_PWR' : Real[0..1] {
            doc /* Meaning: 144MHz max power 5-50W (SPA-1 only). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:566. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_OPT_430M_MAX_PWR' : Real[0..1] {
            doc /* Meaning: 430MHz max power 5-50W (SPA-1 only). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:567. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_OPT_50M_MAX_PWR' : Real[0..1] {
            doc /* Meaning: 50MHz max power 5-100W (SPA-1 only). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:564. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_OPT_70M_MAX_PWR' : Real[0..1] {
            doc /* Meaning: 70MHz max power 5-50W (SPA-1 only). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:565. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_OPT_AM_MAX_PWR' : Real[0..1] {
            doc /* Meaning: AM HF max power 5-25W (SPA-1 only). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:568. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_OPT_AM_VU_MAX_PWR' : Real[0..1] {
            doc /* Meaning: AM V/UHF max power 5-13W (SPA-1 only). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:569. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_OPT_ANT2_OP' : Real[0..1] {
            doc /* Meaning: ANT2 operation (0-2, SPA-1 only). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:561. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_OPT_GPS' : Real[0..1] {
            doc /* Meaning: GPS enable (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:571. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_OPT_GPS_BAUDRATE' : Real[0..1] {
            doc /* Meaning: GPS baudrate (0-4). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:573. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_OPT_GPS_PINNING' : Real[0..1] {
            doc /* Meaning: GPS pinning (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:572. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_OPT_HF_ANT_SEL' : Real[0..1] {
            doc /* Meaning: HF antenna select: 0=ANT1, 1=ANT2. Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:562. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_OPT_HF_MAX_PWR' : Real[0..1] {
            doc /* Meaning: HF max power 5-100W (SPA-1 only). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:563. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_OPT_TUNER_ANT1' : Real[0..1] {
            doc /* Meaning: Tuner type ANT1: 0=INT,1=INT_FAST,2=EXT,3=ATAS (INT needs SPA-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:559. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_OPT_TUNER_ANT2' : Real[0..1] {
            doc /* Meaning: Tuner type ANT2: 0=INT,1=INT_FAST,2=EXT,3=ATAS (INT needs SPA-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:560. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE1_AGC_FAST' : Real[0..1] {
            doc /* Meaning: PRE1_AGC_FAST (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:371. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE1_AGC_MID' : Real[0..1] {
            doc /* Meaning: PRE1_AGC_MID (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:372. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE1_AGC_SLOW' : Real[0..1] {
            doc /* Meaning: PRE1_AGC_SLOW (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:373. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE1_CAT1_RATE' : Real[0..1] {
            doc /* Meaning: PRE1_CAT1_RATE (0-4). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:368. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE1_CAT1_TIMEOUT' : Real[0..1] {
            doc /* Meaning: PRE1_CAT1_TIMEOUT (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:369. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE1_HCUT_FREQ' : Real[0..1] {
            doc /* Meaning: PRE1_HCUT_FREQ (0-67). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:376. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE1_HCUT_SLOPE' : Real[0..1] {
            doc /* Meaning: PRE1_HCUT_SLOPE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:377. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE1_LCUT_FREQ' : Real[0..1] {
            doc /* Meaning: PRE1_LCUT_FREQ (0-19). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:374. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE1_LCUT_SLOPE' : Real[0..1] {
            doc /* Meaning: PRE1_LCUT_SLOPE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:375. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE1_MOD_SOURCE' : Real[0..1] {
            doc /* Meaning: PRE1_MOD_SOURCE (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:380. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE1_RPTT_SELECT' : Real[0..1] {
            doc /* Meaning: PRE1_RPTT_SELECT (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:382. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE1_STOP_BIT' : Real[0..1] {
            doc /* Meaning: PRE1_STOP_BIT (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:370. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE1_TX_BPF' : Real[0..1] {
            doc /* Meaning: PRE1_TX_BPF (0-4). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:379. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE1_USB_MOD_GAIN' : Real[0..1] {
            doc /* Meaning: PRE1_USB_MOD_GAIN (0-100). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:381. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE1_USB_OUT_LVL' : Real[0..1] {
            doc /* Meaning: PRE1_USB_OUT_LVL (0-100). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:378. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE2_AGC_FAST' : Real[0..1] {
            doc /* Meaning: PRE2_AGC_FAST (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:388. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE2_AGC_MID' : Real[0..1] {
            doc /* Meaning: PRE2_AGC_MID (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:389. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE2_AGC_SLOW' : Real[0..1] {
            doc /* Meaning: PRE2_AGC_SLOW (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:390. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE2_CAT1_RATE' : Real[0..1] {
            doc /* Meaning: PRE2_CAT1_RATE (0-4). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:385. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE2_CAT1_TIMEOUT' : Real[0..1] {
            doc /* Meaning: PRE2_CAT1_TIMEOUT (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:386. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE2_HCUT_FREQ' : Real[0..1] {
            doc /* Meaning: PRE2_HCUT_FREQ (0-67). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:393. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE2_HCUT_SLOPE' : Real[0..1] {
            doc /* Meaning: PRE2_HCUT_SLOPE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:394. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE2_LCUT_FREQ' : Real[0..1] {
            doc /* Meaning: PRE2_LCUT_FREQ (0-19). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:391. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE2_LCUT_SLOPE' : Real[0..1] {
            doc /* Meaning: PRE2_LCUT_SLOPE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:392. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE2_MOD_SOURCE' : Real[0..1] {
            doc /* Meaning: PRE2_MOD_SOURCE (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:397. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE2_RPTT_SELECT' : Real[0..1] {
            doc /* Meaning: PRE2_RPTT_SELECT (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:399. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE2_STOP_BIT' : Real[0..1] {
            doc /* Meaning: PRE2_STOP_BIT (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:387. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE2_TX_BPF' : Real[0..1] {
            doc /* Meaning: PRE2_TX_BPF (0-4). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:396. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE2_USB_MOD_GAIN' : Real[0..1] {
            doc /* Meaning: PRE2_USB_MOD_GAIN (0-100). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:398. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE2_USB_OUT_LVL' : Real[0..1] {
            doc /* Meaning: PRE2_USB_OUT_LVL (0-100). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:395. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE3_AGC_FAST' : Real[0..1] {
            doc /* Meaning: PRE3_AGC_FAST (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:405. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE3_AGC_MID' : Real[0..1] {
            doc /* Meaning: PRE3_AGC_MID (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:406. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE3_AGC_SLOW' : Real[0..1] {
            doc /* Meaning: PRE3_AGC_SLOW (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:407. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE3_CAT1_RATE' : Real[0..1] {
            doc /* Meaning: PRE3_CAT1_RATE (0-4). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:402. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE3_CAT1_TIMEOUT' : Real[0..1] {
            doc /* Meaning: PRE3_CAT1_TIMEOUT (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:403. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE3_HCUT_FREQ' : Real[0..1] {
            doc /* Meaning: PRE3_HCUT_FREQ (0-67). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:410. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE3_HCUT_SLOPE' : Real[0..1] {
            doc /* Meaning: PRE3_HCUT_SLOPE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:411. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE3_LCUT_FREQ' : Real[0..1] {
            doc /* Meaning: PRE3_LCUT_FREQ (0-19). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:408. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE3_LCUT_SLOPE' : Real[0..1] {
            doc /* Meaning: PRE3_LCUT_SLOPE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:409. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE3_MOD_SOURCE' : Real[0..1] {
            doc /* Meaning: PRE3_MOD_SOURCE (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:414. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE3_RPTT_SELECT' : Real[0..1] {
            doc /* Meaning: PRE3_RPTT_SELECT (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:416. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE3_STOP_BIT' : Real[0..1] {
            doc /* Meaning: PRE3_STOP_BIT (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:404. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE3_TX_BPF' : Real[0..1] {
            doc /* Meaning: PRE3_TX_BPF (0-4). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:413. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE3_USB_MOD_GAIN' : Real[0..1] {
            doc /* Meaning: PRE3_USB_MOD_GAIN (0-100). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:415. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE3_USB_OUT_LVL' : Real[0..1] {
            doc /* Meaning: PRE3_USB_OUT_LVL (0-100). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:412. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE4_AGC_FAST' : Real[0..1] {
            doc /* Meaning: PRE4_AGC_FAST (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:422. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE4_AGC_MID' : Real[0..1] {
            doc /* Meaning: PRE4_AGC_MID (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:423. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE4_AGC_SLOW' : Real[0..1] {
            doc /* Meaning: PRE4_AGC_SLOW (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:424. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE4_CAT1_RATE' : Real[0..1] {
            doc /* Meaning: PRE4_CAT1_RATE (0-4). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:419. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE4_CAT1_TIMEOUT' : Real[0..1] {
            doc /* Meaning: PRE4_CAT1_TIMEOUT (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:420. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE4_HCUT_FREQ' : Real[0..1] {
            doc /* Meaning: PRE4_HCUT_FREQ (0-67). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:427. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE4_HCUT_SLOPE' : Real[0..1] {
            doc /* Meaning: PRE4_HCUT_SLOPE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:428. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE4_LCUT_FREQ' : Real[0..1] {
            doc /* Meaning: PRE4_LCUT_FREQ (0-19). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:425. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE4_LCUT_SLOPE' : Real[0..1] {
            doc /* Meaning: PRE4_LCUT_SLOPE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:426. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE4_MOD_SOURCE' : Real[0..1] {
            doc /* Meaning: PRE4_MOD_SOURCE (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:431. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE4_RPTT_SELECT' : Real[0..1] {
            doc /* Meaning: PRE4_RPTT_SELECT (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:433. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE4_STOP_BIT' : Real[0..1] {
            doc /* Meaning: PRE4_STOP_BIT (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:421. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE4_TX_BPF' : Real[0..1] {
            doc /* Meaning: PRE4_TX_BPF (0-4). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:430. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE4_USB_MOD_GAIN' : Real[0..1] {
            doc /* Meaning: PRE4_USB_MOD_GAIN (0-100). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:432. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE4_USB_OUT_LVL' : Real[0..1] {
            doc /* Meaning: PRE4_USB_OUT_LVL (0-100). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:429. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE5_AGC_FAST' : Real[0..1] {
            doc /* Meaning: PRE5_AGC_FAST (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:439. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE5_AGC_MID' : Real[0..1] {
            doc /* Meaning: PRE5_AGC_MID (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:440. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE5_AGC_SLOW' : Real[0..1] {
            doc /* Meaning: PRE5_AGC_SLOW (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:441. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE5_CAT1_RATE' : Real[0..1] {
            doc /* Meaning: PRE5_CAT1_RATE (0-4). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:436. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE5_CAT1_TIMEOUT' : Real[0..1] {
            doc /* Meaning: PRE5_CAT1_TIMEOUT (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:437. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE5_HCUT_FREQ' : Real[0..1] {
            doc /* Meaning: PRE5_HCUT_FREQ (0-67). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:444. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE5_HCUT_SLOPE' : Real[0..1] {
            doc /* Meaning: PRE5_HCUT_SLOPE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:445. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE5_LCUT_FREQ' : Real[0..1] {
            doc /* Meaning: PRE5_LCUT_FREQ (0-19). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:442. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE5_LCUT_SLOPE' : Real[0..1] {
            doc /* Meaning: PRE5_LCUT_SLOPE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:443. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE5_MOD_SOURCE' : Real[0..1] {
            doc /* Meaning: PRE5_MOD_SOURCE (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:448. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE5_RPTT_SELECT' : Real[0..1] {
            doc /* Meaning: PRE5_RPTT_SELECT (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:450. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE5_STOP_BIT' : Real[0..1] {
            doc /* Meaning: PRE5_STOP_BIT (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:438. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE5_TX_BPF' : Real[0..1] {
            doc /* Meaning: PRE5_TX_BPF (0-4). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:447. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE5_USB_MOD_GAIN' : Real[0..1] {
            doc /* Meaning: PRE5_USB_MOD_GAIN (0-100). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:449. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_PRE5_USB_OUT_LVL' : Real[0..1] {
            doc /* Meaning: PRE5_USB_OUT_LVL (0-100). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:446. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_RING_MY_PACKET' : Real[0..1] {
            doc /* Meaning: RING_MY_PACKET (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:457. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_RING_RX_BCN' : Real[0..1] {
            doc /* Meaning: RING_RX_BCN (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:454. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_RING_RX_MSG' : Real[0..1] {
            doc /* Meaning: RING_RX_MSG (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:456. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_RING_TX_BCN' : Real[0..1] {
            doc /* Meaning: RING_TX_BCN (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:453. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_RING_TX_MSG' : Real[0..1] {
            doc /* Meaning: RING_TX_MSG (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:455. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_RTTY_AGC_FAST' : Real[0..1] {
            doc /* Meaning: RTTY_AGC_FAST (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:460. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_RTTY_AGC_MID' : Real[0..1] {
            doc /* Meaning: RTTY_AGC_MID (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:461. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_RTTY_AGC_SLOW' : Real[0..1] {
            doc /* Meaning: RTTY_AGC_SLOW (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:462. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_RTTY_HCUT_FREQ' : Real[0..1] {
            doc /* Meaning: RTTY_HCUT_FREQ (0-67). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:465. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_RTTY_HCUT_SLOPE' : Real[0..1] {
            doc /* Meaning: RTTY_HCUT_SLOPE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:466. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_RTTY_LCUT_FREQ' : Real[0..1] {
            doc /* Meaning: RTTY_LCUT_FREQ (0-19). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:463. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_RTTY_LCUT_SLOPE' : Real[0..1] {
            doc /* Meaning: RTTY_LCUT_SLOPE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:464. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_RTTY_MARK_FREQ' : Real[0..1] {
            doc /* Meaning: RTTY_MARK_FREQ (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:470. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_RTTY_NAR_WIDTH' : Real[0..1] {
            doc /* Meaning: RTTY_NAR_WIDTH (0-20). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:469. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_RTTY_POLARITY_TX' : Real[0..1] {
            doc /* Meaning: RTTY_POLARITY_TX (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:472. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_RTTY_RPTT_SELECT' : Real[0..1] {
            doc /* Meaning: RTTY_RPTT_SELECT (0-2). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:468. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_RTTY_SHIFT_FREQ' : Real[0..1] {
            doc /* Meaning: RTTY_SHIFT_FREQ (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:471. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_RTTY_USB_OUT_LEVEL' : Real[0..1] {
            doc /* Meaning: RTTY_USB_OUT_LEVEL (0-100). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:467. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SCAN_BAND_EDGE' : Real[0..1] {
            doc /* Meaning: SCAN_BAND_EDGE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:477. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SCAN_BAND_STACK' : Real[0..1] {
            doc /* Meaning: SCAN_BAND_STACK (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:476. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SCAN_QMB_CH' : Real[0..1] {
            doc /* Meaning: SCAN_QMB_CH (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:475. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SCAN_RESUME' : Real[0..1] {
            doc /* Meaning: SCAN_RESUME (0-4). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:478. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SCOPE_2D_SENS' : Real[0..1] {
            doc /* Meaning: SCOPE_2D_SENS (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:483. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SCOPE_3DSS_SENS' : Real[0..1] {
            doc /* Meaning: SCOPE_3DSS_SENS (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:484. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SCOPE_AVERAGE' : Real[0..1] {
            doc /* Meaning: SCOPE_AVERAGE (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:485. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SCOPE_CTR' : Real[0..1] {
            doc /* Meaning: SCOPE_CTR (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:482. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SCOPE_RBW' : Real[0..1] {
            doc /* Meaning: SCOPE_RBW (0-2). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:481. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SMART_FAST_RATE' : Real[0..1] {
            doc /* Meaning: SMART_FAST_RATE (10-180). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:491. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SMART_HIGH_SPD' : Real[0..1] {
            doc /* Meaning: SMART_HIGH_SPD (3-90). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:489. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SMART_LOW_SPD' : Real[0..1] {
            doc /* Meaning: SMART_LOW_SPD (2-30). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:488. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SMART_SLOW_RATE' : Real[0..1] {
            doc /* Meaning: SMART_SLOW_RATE (1-100). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:490. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SMART_TURN_ANGLE' : Real[0..1] {
            doc /* Meaning: SMART_TURN_ANGLE (5-90). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:492. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SMART_TURN_SLOPE' : Real[0..1] {
            doc /* Meaning: SMART_TURN_SLOPE (1-255). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:493. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SMART_TURN_TIME' : Real[0..1] {
            doc /* Meaning: SMART_TURN_TIME (5-180). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:494. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SSB_AGC_FAST' : Real[0..1] {
            doc /* Meaning: SSB_AGC_FAST (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:497. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SSB_AGC_MID' : Real[0..1] {
            doc /* Meaning: SSB_AGC_MID (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:498. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SSB_AGC_SLOW' : Real[0..1] {
            doc /* Meaning: SSB_AGC_SLOW (20-4000). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:499. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SSB_CW_AUTO_MODE' : Real[0..1] {
            doc /* Meaning: SSB_CW_AUTO_MODE (0-2). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:510. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SSB_HCUT_FREQ' : Real[0..1] {
            doc /* Meaning: SSB_HCUT_FREQ (0-67). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:502. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SSB_HCUT_SLOPE' : Real[0..1] {
            doc /* Meaning: SSB_HCUT_SLOPE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:503. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SSB_LCUT_FREQ' : Real[0..1] {
            doc /* Meaning: SSB_LCUT_FREQ (0-19). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:500. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SSB_LCUT_SLOPE' : Real[0..1] {
            doc /* Meaning: SSB_LCUT_SLOPE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:501. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SSB_MOD_SOURCE' : Real[0..1] {
            doc /* Meaning: SSB_MOD_SOURCE (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:506. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SSB_NAR_WIDTH' : Real[0..1] {
            doc /* Meaning: SSB_NAR_WIDTH (0-22). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:509. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SSB_RPTT_SELECT' : Real[0..1] {
            doc /* Meaning: SSB_RPTT_SELECT (0-2). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:508. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SSB_TX_BPF_SEL' : Real[0..1] {
            doc /* Meaning: SSB_TX_BPF_SEL (0-4). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:505. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SSB_USB_MOD_GAIN' : Real[0..1] {
            doc /* Meaning: SSB_USB_MOD_GAIN (0-100). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:507. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_SSB_USB_OUT_LEVEL' : Real[0..1] {
            doc /* Meaning: SSB_USB_OUT_LEVEL (0-100). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:504. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_TXGEN_144M_MAX_PWR' : Real[0..1] {
            doc /* Meaning: TXGEN_144M_MAX_PWR (5-100). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:535. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_TXGEN_430M_MAX_PWR' : Real[0..1] {
            doc /* Meaning: TXGEN_430M_MAX_PWR (5-100). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:536. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_TXGEN_50M_MAX_PWR' : Real[0..1] {
            doc /* Meaning: TXGEN_50M_MAX_PWR (5-10). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:531. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_TXGEN_70M_MAX_PWR' : Real[0..1] {
            doc /* Meaning: TXGEN_70M_MAX_PWR (5-60). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:532. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_TXGEN_AM_HF_MAX' : Real[0..1] {
            doc /* Meaning: TXGEN_AM_HF_MAX (5-25). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:537. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_TXGEN_AM_VU_MAX' : Real[0..1] {
            doc /* Meaning: TXGEN_AM_VU_MAX (5-25). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:538. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_TXGEN_EMERG_TX' : Real[0..1] {
            doc /* Meaning: TXGEN_EMERG_TX (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:540. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_TXGEN_HF_MAX_PWR' : Real[0..1] {
            doc /* Meaning: TXGEN_HF_MAX_PWR (5-10). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:530. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_TXGEN_MAX_PWR_BAT' : Real[0..1] {
            doc /* Meaning: TXGEN_MAX_PWR_BAT (5-60). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:528. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_TXGEN_METER_DET' : Real[0..1] {
            doc /* Meaning: TXGEN_METER_DET (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:542. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_TXGEN_QRP_MODE' : Real[0..1] {
            doc /* Meaning: TXGEN_QRP_MODE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:529. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_TXGEN_TX_INHIBIT' : Real[0..1] {
            doc /* Meaning: TXGEN_TX_INHIBIT (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:541. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_TXGEN_VOX_SELECT' : Real[0..1] {
            doc /* Meaning: TXGEN_VOX_SELECT (0-2). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:539. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_TX_AMC_RELEASE' : Real[0..1] {
            doc /* Meaning: TX_AMC_RELEASE (0-2). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:513. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_TX_EQ1_BWTH' : Real[0..1] {
            doc /* Meaning: TX_EQ1_BWTH (0-10). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:515. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_TX_EQ1_FREQ' : Real[0..1] {
            doc /* Meaning: TX_EQ1_FREQ (0-7). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:514. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_TX_EQ2_BWTH' : Real[0..1] {
            doc /* Meaning: TX_EQ2_BWTH (0-10). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:517. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_TX_EQ2_FREQ' : Real[0..1] {
            doc /* Meaning: TX_EQ2_FREQ (0-9). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:516. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_TX_EQ3_BWTH' : Real[0..1] {
            doc /* Meaning: TX_EQ3_BWTH (0-10). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:519. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_TX_EQ3_FREQ' : Real[0..1] {
            doc /* Meaning: TX_EQ3_FREQ (0-18). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:518. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_TX_P_EQ1_BWTH' : Real[0..1] {
            doc /* Meaning: TX_P_EQ1_BWTH (0-10). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:521. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_TX_P_EQ1_FREQ' : Real[0..1] {
            doc /* Meaning: TX_P_EQ1_FREQ (0-7). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:520. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_TX_P_EQ2_BWTH' : Real[0..1] {
            doc /* Meaning: TX_P_EQ2_BWTH (0-10). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:523. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_TX_P_EQ2_FREQ' : Real[0..1] {
            doc /* Meaning: TX_P_EQ2_FREQ (0-9). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:522. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_TX_P_EQ3_BWTH' : Real[0..1] {
            doc /* Meaning: TX_P_EQ3_BWTH (0-10). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:525. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_TX_P_EQ3_FREQ' : Real[0..1] {
            doc /* Meaning: TX_P_EQ3_FREQ (0-18). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:524. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_UNIT_ALTITUDE' : Real[0..1] {
            doc /* Meaning: UNIT_ALTITUDE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:548. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_UNIT_DISTANCE' : Real[0..1] {
            doc /* Meaning: UNIT_DISTANCE (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:546. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_UNIT_POSITION' : Real[0..1] {
            doc /* Meaning: UNIT_POSITION (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:545. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_UNIT_RAIN' : Real[0..1] {
            doc /* Meaning: UNIT_RAIN (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:550. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_UNIT_SPEED' : Real[0..1] {
            doc /* Meaning: UNIT_SPEED (0-2). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:547. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_UNIT_TEMP' : Real[0..1] {
            doc /* Meaning: UNIT_TEMP (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:549. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_UNIT_WIND' : Real[0..1] {
            doc /* Meaning: UNIT_WIND (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:551. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_VMI_COLOR_CLAR' : Real[0..1] {
            doc /* Meaning: VMI_COLOR_CLAR (0-1). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:556. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_VMI_COLOR_MEM' : Real[0..1] {
            doc /* Meaning: VMI_COLOR_MEM (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:555. */
        }
        attribute 'hamlib.extension.rigs/yaesu/ftx1/ftx1.c::ftx1_ext_parms::TOK_VMI_COLOR_VFO' : Real[0..1] {
            doc /* Meaning: VMI_COLOR_VFO (0-3). Unit: unspecified; do not infer units. Access/role: model/context-specific; no universal read/write grant.
                 Source type: RIG_CONF_NUMERIC. Owner: physicalRadio. Context: rig-global. Source: rigs/yaesu/ftx1/ftx1.c:554. */
        }
    }
    attribute def HamlibConnectionBackendLifecycleInteractions {
        attribute 'hamlib.api.netrigctl_get_vfo_mode' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: connection_backend_lifecycle. Source: include/hamlib/rig.h:3099. Signature: extern HAMLIB_EXPORT(int) netrigctl_get_vfo_mode(RIG *rig);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_band_changed' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: connection_backend_lifecycle. Source: include/hamlib/rig.h:4112. Signature: extern HAMLIB_EXPORT(int) rig_band_changed(RIG *rig, hamlib_bandselect_t band);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_cleanup' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: connection_backend_lifecycle. Source: include/hamlib/rig.h:3377. Signature: extern HAMLIB_EXPORT(int) rig_cleanup(RIG *rig);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_close' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: connection_backend_lifecycle. Source: include/hamlib/rig.h:3374. Signature: extern HAMLIB_EXPORT(int) rig_close(RIG *rig);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_cm108_get_bit' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: connection_backend_lifecycle. Source: include/hamlib/rig.h:4110. Signature: extern HAMLIB_EXPORT(int) rig_cm108_get_bit(hamlib_port_t *p, enum GPIO gpio, int *bit);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_cm108_set_bit' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: connection_backend_lifecycle. Source: include/hamlib/rig.h:4111. Signature: extern HAMLIB_EXPORT(int) rig_cm108_set_bit(hamlib_port_t *p, enum GPIO gpio, int bit);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_cookie' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: connection_backend_lifecycle. Source: include/hamlib/rig.h:4082. Signature: extern HAMLIB_EXPORT(int) rig_cookie(RIG *rig, enum cookie_e cookie_cmd, char *cookie, int cookie_len);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_flush' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: connection_backend_lifecycle. Source: include/hamlib/rig.h:3031. Signature: extern HAMLIB_EXPORT(int) rig_flush(hamlib_port_t *port);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_flush_force' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: connection_backend_lifecycle. Source: include/hamlib/rig.h:3028. Signature: extern HAMLIB_EXPORT(int) rig_flush_force(hamlib_port_t *port, int flush_async_data);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_cache' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: connection_backend_lifecycle. Source: include/hamlib/rig.h:4073. Signature: extern HAMLIB_EXPORT(int) rig_get_cache(RIG *rig, vfo_t vfo, freq_t *freq, int * cache_ms_freq, rmode_t *mode, int *cache_ms_mode, pbwidth_t *width, int *cache_ms_width);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_cache_freq' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: connection_backend_lifecycle. Source: include/hamlib/rig.h:4074. Signature: extern HAMLIB_EXPORT(int) rig_get_cache_freq(RIG *rig, vfo_t vfo, freq_t *freq, int * cache_ms_freq);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_cache_timeout_ms' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: connection_backend_lifecycle. Source: include/hamlib/rig.h:4067. Signature: extern HAMLIB_EXPORT(int) rig_get_cache_timeout_ms(RIG *rig, hamlib_cache_t selection);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_conf' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: connection_backend_lifecycle. Source: include/hamlib/rig.h:3285. Signature: extern HAMLIB_EXPORT(int) rig_get_conf(RIG *rig, hamlib_token_t token, char *val);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_conf2' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: connection_backend_lifecycle. Source: include/hamlib/rig.h:3289. Signature: extern HAMLIB_EXPORT(int) rig_get_conf2(RIG *rig, hamlib_token_t token, char *val, int val_len);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_lock_mode' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: connection_backend_lifecycle. Source: include/hamlib/rig.h:4103. Signature: extern HAMLIB_EXPORT(int) rig_get_lock_mode(RIG *rig, int *lock);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_twiddle' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: connection_backend_lifecycle. Source: include/hamlib/rig.h:3902. Signature: extern HAMLIB_EXPORT(int) rig_get_twiddle(RIG *rig, int *seconds);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_init' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: connection_backend_lifecycle. Source: include/hamlib/rig.h:3020. Signature: extern HAMLIB_EXPORT(RIG *) rig_init(rig_model_t rig_model);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_lock' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: connection_backend_lifecycle. Source: include/hamlib/rig.h:3034. Signature: extern HAMLIB_EXPORT(void) rig_lock(RIG *rig, int lock);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_no_restore_ai' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: connection_backend_lifecycle. Source: include/hamlib/rig.h:4065. Signature: extern HAMLIB_EXPORT(void) rig_no_restore_ai(void);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_open' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: connection_backend_lifecycle. Source: include/hamlib/rig.h:3021. Signature: extern HAMLIB_EXPORT(int) rig_open(RIG *rig);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_password' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: connection_backend_lifecycle. Source: include/hamlib/rig.h:4084. Signature: extern HAMLIB_EXPORT(int) rig_password(RIG *rig, const char *key1);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_password_generate_secret' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: connection_backend_lifecycle. Source: include/hamlib/rig.h:4085. Signature: extern HAMLIB_EXPORT(void) rig_password_generate_secret(char *pass, char result[HAMLIB_SECRET_LENGTH + 1]);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_cache_timeout_ms' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: connection_backend_lifecycle. Source: include/hamlib/rig.h:4068. Signature: extern HAMLIB_EXPORT(int) rig_set_cache_timeout_ms(RIG *rig, hamlib_cache_t selection, int ms);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_conf' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: connection_backend_lifecycle. Source: include/hamlib/rig.h:3280. Signature: extern HAMLIB_EXPORT(int) rig_set_conf(RIG *rig, hamlib_token_t token, const char *val);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_lock_mode' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: connection_backend_lifecycle. Source: include/hamlib/rig.h:4102. Signature: extern HAMLIB_EXPORT(int) rig_set_lock_mode(RIG *rig, int lock);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_twiddle' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: connection_backend_lifecycle. Source: include/hamlib/rig.h:3898. Signature: extern HAMLIB_EXPORT(int) rig_set_twiddle(RIG *rig, int seconds);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_uplink' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: connection_backend_lifecycle. Source: include/hamlib/rig.h:3906. Signature: extern HAMLIB_EXPORT(int) rig_set_uplink(RIG *rig, int val);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_vfo_opt' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: connection_backend_lifecycle. Source: include/hamlib/rig.h:4070. Signature: extern HAMLIB_EXPORT(int) rig_set_vfo_opt(RIG *rig, int status);. API presence is not per-model success, Rust delivery or command permission. */
        }
    }
    attribute def HamlibEventSubscriptionInteractions {
        attribute 'hamlib.api.rig_set_dcd_callback' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: event_subscription. Source: include/hamlib/rig.h:3582. Signature: extern HAMLIB_EXPORT(int) rig_set_dcd_callback(RIG *, dcd_cb_t, rig_ptr_t);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_freq_callback' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: event_subscription. Source: include/hamlib/rig.h:3563. Signature: extern HAMLIB_EXPORT(int) rig_set_freq_callback(RIG *, freq_cb_t, rig_ptr_t);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_mode_callback' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: event_subscription. Source: include/hamlib/rig.h:3568. Signature: extern HAMLIB_EXPORT(int) rig_set_mode_callback(RIG *, mode_cb_t, rig_ptr_t);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_pltune_callback' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: event_subscription. Source: include/hamlib/rig.h:3587. Signature: extern HAMLIB_EXPORT(int) rig_set_pltune_callback(RIG *, pltune_cb_t, rig_ptr_t);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_ptt_callback' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: event_subscription. Source: include/hamlib/rig.h:3577. Signature: extern HAMLIB_EXPORT(int) rig_set_ptt_callback(RIG *, ptt_cb_t, rig_ptr_t);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_spectrum_callback' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: event_subscription. Source: include/hamlib/rig.h:3592. Signature: extern HAMLIB_EXPORT(int) rig_set_spectrum_callback(RIG *, spectrum_cb_t, rig_ptr_t);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_vfo_callback' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: event_subscription. Source: include/hamlib/rig.h:3572. Signature: extern HAMLIB_EXPORT(int) rig_set_vfo_callback(RIG *, vfo_cb_t, rig_ptr_t);. API presence is not per-model success, Rust delivery or command permission. */
        }
    }
    attribute def HamlibRadioCommandQueryInteractions {
        attribute 'hamlib.api.rig_get_ant' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3385. Signature: extern HAMLIB_EXPORT(int) rig_get_ant(RIG *rig, vfo_t vfo, ant_t ant, value_t *option, ant_t *ant_curr, ant_t *ant_tx, ant_t *ant_rx);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_chan_all' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3505. Signature: extern HAMLIB_EXPORT(int) rig_get_chan_all(RIG *rig, vfo_t vfo, channel_t chans[]);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_chan_all_cb' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3515. Signature: extern HAMLIB_EXPORT(int) rig_get_chan_all_cb(RIG *rig, vfo_t vfo, chan_cb_t chan_cb, rig_ptr_t);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_channel' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3495. Signature: extern HAMLIB_EXPORT(int) rig_get_channel(RIG *rig, vfo_t vfo, channel_t *chan, int read_only);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_clock' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:4077. Signature: extern HAMLIB_EXPORT(int) rig_get_clock(RIG *rig, int *year, int *month, int *day, int *hour, int *min, int *sec, double *msec, int *utc_offset);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_ctcss_sql' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3156. Signature: extern HAMLIB_EXPORT(int) rig_get_ctcss_sql(RIG *rig, vfo_t vfo, tone_t *tone);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_ctcss_tone' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3138. Signature: extern HAMLIB_EXPORT(int) rig_get_ctcss_tone(RIG *rig, vfo_t vfo, tone_t *tone);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_dcd' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3111. Signature: extern HAMLIB_EXPORT(int) rig_get_dcd(RIG *rig, vfo_t vfo, dcd_t *dcd);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_dcs_code' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3147. Signature: extern HAMLIB_EXPORT(int) rig_get_dcs_code(RIG *rig, vfo_t vfo, tone_t *code);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_dcs_sql' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3165. Signature: extern HAMLIB_EXPORT(int) rig_get_dcs_sql(RIG *rig, vfo_t vfo, tone_t *code);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_ext_func' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3322. Signature: extern HAMLIB_EXPORT(int) rig_get_ext_func(RIG *rig, vfo_t vfo, hamlib_token_t token, int *status);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_ext_level' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3311. Signature: extern HAMLIB_EXPORT(int) rig_get_ext_level(RIG *rig, vfo_t vfo, hamlib_token_t token, value_t *val);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_ext_parm' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3332. Signature: extern HAMLIB_EXPORT(int) rig_get_ext_parm(RIG *rig, hamlib_token_t token, value_t *val);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_freq' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3051. Signature: extern HAMLIB_EXPORT(int) rig_get_freq(RIG *rig, vfo_t vfo, freq_t *freq, const char*);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_func' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3420. Signature: extern HAMLIB_EXPORT(int) rig_get_func(RIG *rig, vfo_t vfo, setting_t func, int *status);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_info' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3910. Signature: extern HAMLIB_EXPORT(const char *) rig_get_info(RIG *rig);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_level' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3263. Signature: extern HAMLIB_EXPORT(int) rig_get_level(RIG *rig, vfo_t vfo, setting_t level, value_t *val);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_mem' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3467. Signature: extern HAMLIB_EXPORT(int) rig_get_mem(RIG *rig, vfo_t vfo, int *ch);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_mem_all' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3540. Signature: extern HAMLIB_EXPORT(int) rig_get_mem_all(RIG *rig, vfo_t vfo, channel_t *chan, const struct confparams *, value_t *);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_mem_all_cb' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3527. Signature: extern HAMLIB_EXPORT(int) rig_get_mem_all_cb(RIG *rig, vfo_t vfo, chan_cb_t chan_cb, confval_cb_t parm_cb, rig_ptr_t);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_mode' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3067. Signature: extern HAMLIB_EXPORT(int) rig_get_mode(RIG *rig, vfo_t vfo, rmode_t *mode, pbwidth_t *width);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_parm' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3275. Signature: extern HAMLIB_EXPORT(int) rig_get_parm(RIG *rig, setting_t parm, value_t *val);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_powerstat' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3298. Signature: extern HAMLIB_EXPORT(int) rig_get_powerstat(RIG *rig, powerstat_t *status);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_ptt' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3106. Signature: extern HAMLIB_EXPORT(int) rig_get_ptt(RIG *rig, vfo_t vfo, ptt_t *ptt);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_rig_info' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:4072. Signature: extern HAMLIB_EXPORT(int) rig_get_rig_info(RIG *rig, char *response, int max_response_len);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_rit' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3218. Signature: extern HAMLIB_EXPORT(int) rig_get_rit(RIG *rig, vfo_t vfo, shortfreq_t *rit);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_rptr_offs' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3129. Signature: extern HAMLIB_EXPORT(int) rig_get_rptr_offs(RIG *rig, vfo_t vfo, shortfreq_t *rptr_offs);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_rptr_shift' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3120. Signature: extern HAMLIB_EXPORT(int) rig_get_rptr_shift(RIG *rig, vfo_t vfo, rptr_shift_t *rptr_shift);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_split_freq' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3174. Signature: extern HAMLIB_EXPORT(int) rig_get_split_freq(RIG *rig, vfo_t vfo, freq_t *tx_freq);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_split_freq_mode' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3196. Signature: extern HAMLIB_EXPORT(int) rig_get_split_freq_mode(RIG *rig, vfo_t vfo, freq_t *tx_freq, rmode_t *tx_mode, pbwidth_t *tx_width);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_split_mode' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3184. Signature: extern HAMLIB_EXPORT(int) rig_get_split_mode(RIG *rig, vfo_t vfo, rmode_t *tx_mode, pbwidth_t *tx_width);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_split_vfo' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3208. Signature: extern HAMLIB_EXPORT(int) rig_get_split_vfo(RIG *rig, vfo_t rx_vfo, split_t *split, vfo_t *tx_vfo);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_trn' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3559. Signature: extern HAMLIB_EXPORT(int) rig_get_trn(RIG *rig, int *trn);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_ts' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3236. Signature: extern HAMLIB_EXPORT(int) rig_get_ts(RIG *rig, vfo_t vfo, shortfreq_t *ts);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_vfo' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3083. Signature: extern HAMLIB_EXPORT(int) rig_get_vfo(RIG *rig, vfo_t *vfo);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_vfo_info' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3087. Signature: extern HAMLIB_EXPORT(int) rig_get_vfo_info(RIG *rig, vfo_t vfo, freq_t *freq, rmode_t *mode, pbwidth_t *width, split_t *split, int *satmode);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_vfo_list' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3096. Signature: extern HAMLIB_EXPORT(int) rig_get_vfo_list(RIG *rig, char *buf, int buflen);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_xit' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3227. Signature: extern HAMLIB_EXPORT(int) rig_get_xit(RIG *rig, vfo_t vfo, shortfreq_t *xit);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_recv_dtmf' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3430. Signature: extern HAMLIB_EXPORT(int) rig_recv_dtmf(RIG *rig, vfo_t vfo, char *digits, int *length);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_reset' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3302. Signature: extern HAMLIB_EXPORT(int) rig_reset(RIG *rig, reset_t reset);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_scan' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3481. Signature: extern HAMLIB_EXPORT(int) rig_scan(RIG *rig, vfo_t vfo, scan_t scan, int ch);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_send_dtmf' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3426. Signature: extern HAMLIB_EXPORT(int) rig_send_dtmf(RIG *rig, vfo_t vfo, const char *digits);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_send_morse' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3436. Signature: extern HAMLIB_EXPORT(int) rig_send_morse(RIG *rig, vfo_t vfo, const char *msg);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_send_voice_mem' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3449. Signature: extern HAMLIB_EXPORT(int) rig_send_voice_mem(RIG *rig, vfo_t vfo, int ch);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_ant' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3380. Signature: extern HAMLIB_EXPORT(int) rig_set_ant(RIG *rig, vfo_t vfo, ant_t ant, value_t option);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_bank' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3458. Signature: extern HAMLIB_EXPORT(int) rig_set_bank(RIG *rig, vfo_t vfo, int bank);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_chan_all' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3501. Signature: extern HAMLIB_EXPORT(int) rig_set_chan_all(RIG *rig, vfo_t vfo, const channel_t chans[]);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_chan_all_cb' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3510. Signature: extern HAMLIB_EXPORT(int) rig_set_chan_all_cb(RIG *rig, vfo_t vfo, chan_cb_t chan_cb, rig_ptr_t);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_channel' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3491. Signature: extern HAMLIB_EXPORT(int) rig_set_channel(RIG *rig, vfo_t vfo, const channel_t *chan);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_clock' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:4076. Signature: extern HAMLIB_EXPORT(int) rig_set_clock(RIG *rig, int year, int month, int day, int hour, int min, int sec, double msec, int utc_offset);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_ctcss_sql' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3152. Signature: extern HAMLIB_EXPORT(int) rig_set_ctcss_sql(RIG *rig, vfo_t vfo, tone_t tone);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_ctcss_tone' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3134. Signature: extern HAMLIB_EXPORT(int) rig_set_ctcss_tone(RIG *rig, vfo_t vfo, tone_t tone);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_dcs_code' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3143. Signature: extern HAMLIB_EXPORT(int) rig_set_dcs_code(RIG *rig, vfo_t vfo, tone_t code);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_dcs_sql' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3161. Signature: extern HAMLIB_EXPORT(int) rig_set_dcs_sql(RIG *rig, vfo_t vfo, tone_t code);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_ext_func' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3317. Signature: extern HAMLIB_EXPORT(int) rig_set_ext_func(RIG *rig, vfo_t vfo, hamlib_token_t token, int status);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_ext_level' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3306. Signature: extern HAMLIB_EXPORT(int) rig_set_ext_level(RIG *rig, vfo_t vfo, hamlib_token_t token, value_t val);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_ext_parm' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3328. Signature: extern HAMLIB_EXPORT(int) rig_set_ext_parm(RIG *rig, hamlib_token_t token, value_t val);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_freq' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3039. Signature: extern HAMLIB_EXPORT(int) rig_set_freq(RIG *rig, vfo_t vfo, freq_t freq, const char*);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_func' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3415. Signature: extern HAMLIB_EXPORT(int) rig_set_func(RIG *rig, vfo_t vfo, setting_t func, int status);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_level' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3258. Signature: extern HAMLIB_EXPORT(int) rig_set_level(RIG *rig, vfo_t vfo, setting_t level, value_t val);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_mem' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3463. Signature: extern HAMLIB_EXPORT(int) rig_set_mem(RIG *rig, vfo_t vfo, int ch);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_mem_all' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3534. Signature: extern HAMLIB_EXPORT(int) rig_set_mem_all(RIG *rig, vfo_t vfo, const channel_t *chan, const struct confparams *, const value_t *);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_mem_all_cb' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3521. Signature: extern HAMLIB_EXPORT(int) rig_set_mem_all_cb(RIG *rig, vfo_t vfo, chan_cb_t chan_cb, confval_cb_t parm_cb, rig_ptr_t);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_mode' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3062. Signature: extern HAMLIB_EXPORT(int) rig_set_mode(RIG *rig, vfo_t vfo, rmode_t mode, pbwidth_t width);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_parm' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3271. Signature: extern HAMLIB_EXPORT(int) rig_set_parm(RIG *rig, setting_t parm, value_t val);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_powerstat' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3295. Signature: extern HAMLIB_EXPORT(int) rig_set_powerstat(RIG *rig, powerstat_t status);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_ptt' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3102. Signature: extern HAMLIB_EXPORT(int) rig_set_ptt(RIG *rig, vfo_t vfo, ptt_t ptt);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_rit' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3214. Signature: extern HAMLIB_EXPORT(int) rig_set_rit(RIG *rig, vfo_t vfo, shortfreq_t rit);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_rptr_offs' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3125. Signature: extern HAMLIB_EXPORT(int) rig_set_rptr_offs(RIG *rig, vfo_t vfo, shortfreq_t rptr_offs);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_rptr_shift' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3116. Signature: extern HAMLIB_EXPORT(int) rig_set_rptr_shift(RIG *rig, vfo_t vfo, rptr_shift_t rptr_shift);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_split_freq' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3170. Signature: extern HAMLIB_EXPORT(int) rig_set_split_freq(RIG *rig, vfo_t vfo, freq_t tx_freq);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_split_freq_mode' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3190. Signature: extern HAMLIB_EXPORT(int) rig_set_split_freq_mode(RIG *rig, vfo_t vfo, freq_t tx_freq, rmode_t tx_mode, pbwidth_t tx_width);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_split_mode' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3179. Signature: extern HAMLIB_EXPORT(int) rig_set_split_mode(RIG *rig, vfo_t vfo, rmode_t tx_mode, pbwidth_t tx_width);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_split_vfo' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3203. Signature: extern HAMLIB_EXPORT(int) rig_set_split_vfo(RIG *rig, vfo_t rx_vfo, split_t split, vfo_t tx_vfo);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_trn' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3555. Signature: extern HAMLIB_EXPORT(int) rig_set_trn(RIG *rig, int trn);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_ts' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3232. Signature: extern HAMLIB_EXPORT(int) rig_set_ts(RIG *rig, vfo_t vfo, shortfreq_t ts);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_vfo' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3075. Signature: extern HAMLIB_EXPORT(int) rig_set_vfo(RIG *rig, vfo_t vfo, const char *func);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_xit' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3223. Signature: extern HAMLIB_EXPORT(int) rig_set_xit(RIG *rig, vfo_t vfo, shortfreq_t xit);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_stop_morse' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3441. Signature: extern HAMLIB_EXPORT(int) rig_stop_morse(RIG *rig, vfo_t vfo);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_stop_voice_mem' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3454. Signature: extern HAMLIB_EXPORT(int) rig_stop_voice_mem(RIG *rig, vfo_t vfo);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_vfo_op' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3472. Signature: extern HAMLIB_EXPORT(int) rig_vfo_op(RIG *rig, vfo_t vfo, vfo_op_t op);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_wait_morse' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: radio_command_query. Source: include/hamlib/rig.h:3445. Signature: extern HAMLIB_EXPORT(int) rig_wait_morse(RIG *rig, vfo_t vfo);. API presence is not per-model success, Rust delivery or command permission. */
        }
    }
    attribute def HamlibRawVendorEscapeInteractions {
        attribute 'hamlib.api.rig_send_raw' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: raw_vendor_escape. Source: include/hamlib/rig.h:4087. Signature: extern HAMLIB_EXPORT(int) rig_send_raw(RIG *rig, const unsigned char* send, int send_len, unsigned char* reply, int reply_len, unsigned char *term);. API presence is not per-model success, Rust delivery or command permission. */
        }
    }
    attribute def HamlibReferenceDiscoveryInteractions {
        attribute 'hamlib.api.rig_check_backend' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:4015. Signature: extern HAMLIB_EXPORT(int) rig_check_backend(rig_model_t rig_model);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_confparam_lookup' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:3367. Signature: extern HAMLIB_EXPORT(const struct confparams *) rig_confparam_lookup(RIG *rig, const char *name);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_data_pointer' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:4114. Signature: extern HAMLIB_EXPORT(void *) rig_data_pointer(RIG *rig, rig_ptrx_t idx);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_ext_func_foreach' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:3337. Signature: extern HAMLIB_EXPORT(int) rig_ext_func_foreach(RIG *rig, int (*cfunc)(RIG *, const struct confparams *, rig_ptr_t), rig_ptr_t data);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_ext_level_foreach' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:3341. Signature: extern HAMLIB_EXPORT(int) rig_ext_level_foreach(RIG *rig, int (*cfunc)(RIG *, const struct confparams *, rig_ptr_t), rig_ptr_t data);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_ext_lookup' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:3350. Signature: extern HAMLIB_EXPORT(const struct confparams *) rig_ext_lookup(RIG *rig, const char *name);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_ext_lookup_tok' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:3354. Signature: extern HAMLIB_EXPORT(const struct confparams *) rig_ext_lookup_tok(RIG *rig, hamlib_token_t token);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_ext_parm_foreach' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:3345. Signature: extern HAMLIB_EXPORT(int) rig_ext_parm_foreach(RIG *rig, int (*cfunc)(RIG *, const struct confparams *, rig_ptr_t), rig_ptr_t data);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_ext_token_lookup' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:3357. Signature: extern HAMLIB_EXPORT(hamlib_token_t) rig_ext_token_lookup(RIG *rig, const char *name);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_caps' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:3913. Signature: extern HAMLIB_EXPORT(struct rig_caps *) rig_get_caps(rig_model_t rig_model);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_caps_cptr' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:2857. Signature: extern HAMLIB_EXPORT (const char *) rig_get_caps_cptr(rig_model_t rig_model, enum rig_caps_cptr_e rig_caps);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_caps_int' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:2851. Signature: extern HAMLIB_EXPORT (uint64_t) rig_get_caps_int(rig_model_t rig_model, enum rig_caps_int_e rig_caps);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_function_ptr' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:2824. Signature: extern HAMLIB_EXPORT (void *) rig_get_function_ptr(rig_model_t rig_model, enum rig_function_e rig_function);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_range' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:3916. Signature: extern HAMLIB_EXPORT(const freq_range_t *) rig_get_range(const freq_range_t *range_list, freq_t freq, rmode_t mode);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_resolution' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:3254. Signature: extern HAMLIB_EXPORT(shortfreq_t) rig_get_resolution(RIG *rig, rmode_t mode);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_has_get_func' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:3408. Signature: extern HAMLIB_EXPORT(setting_t) rig_has_get_func(RIG *rig, setting_t func);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_has_get_level' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:3394. Signature: extern HAMLIB_EXPORT(setting_t) rig_has_get_level(RIG *rig, setting_t level);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_has_get_parm' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:3401. Signature: extern HAMLIB_EXPORT(setting_t) rig_has_get_parm(RIG *rig, setting_t parm);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_has_scan' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:3487. Signature: extern HAMLIB_EXPORT(scan_t) rig_has_scan(RIG *rig, scan_t scan);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_has_set_func' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:3411. Signature: extern HAMLIB_EXPORT(setting_t) rig_has_set_func(RIG *rig, setting_t func);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_has_set_level' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:3397. Signature: extern HAMLIB_EXPORT(setting_t) rig_has_set_level(RIG *rig, setting_t level);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_has_set_parm' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:3404. Signature: extern HAMLIB_EXPORT(setting_t) rig_has_set_parm(RIG *rig, setting_t parm);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_has_vfo_op' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:3477. Signature: extern HAMLIB_EXPORT(vfo_op_t) rig_has_vfo_op(RIG *rig, vfo_op_t op);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_is_model' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:4105. Signature: extern HAMLIB_EXPORT(int) rig_is_model(RIG *rig, rig_model_t model);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_list_foreach' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:4004. Signature: extern HAMLIB_EXPORT(int) rig_list_foreach(int (*cfunc)(const struct rig_caps *, rig_ptr_t), rig_ptr_t data);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_list_foreach_model' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:4008. Signature: extern HAMLIB_EXPORT(int) rig_list_foreach_model(int (*cfunc)(const rig_model_t rig_model, rig_ptr_t), rig_ptr_t data);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_load_all_backends' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:4018. Signature: extern HAMLIB_EXPORT(int) rig_load_all_backends(void);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_load_backend' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:4012. Signature: extern HAMLIB_EXPORT(int) rig_load_backend(const char *be_name);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_lookup_mem_caps' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:3547. Signature: extern HAMLIB_EXPORT(const chan_t *) rig_lookup_mem_caps(RIG *rig, int ch);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_mem_count' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:3551. Signature: extern HAMLIB_EXPORT(int) rig_mem_count(RIG *rig);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_passband_narrow' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:3924. Signature: extern HAMLIB_EXPORT(pbwidth_t) rig_passband_narrow(RIG *rig, rmode_t mode);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_passband_normal' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:3921. Signature: extern HAMLIB_EXPORT(pbwidth_t) rig_passband_normal(RIG *rig, rmode_t mode);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_passband_wide' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:3927. Signature: extern HAMLIB_EXPORT(pbwidth_t) rig_passband_wide(RIG *rig, rmode_t mode);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_probe' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:4028. Signature: extern HAMLIB_EXPORT(rig_model_t) rig_probe(hamlib_port_t *p);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_probe_all' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:4023. Signature: extern HAMLIB_EXPORT(int) rig_probe_all(hamlib_port_t *p, rig_probe_func_t, rig_ptr_t);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_register' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:3998. Signature: extern HAMLIB_EXPORT(int) rig_register(struct rig_caps *caps);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_token_foreach' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:3362. Signature: extern HAMLIB_EXPORT(int) rig_token_foreach(RIG *rig, int (*cfunc)(const struct confparams *, rig_ptr_t), rig_ptr_t data);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_token_lookup' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:3370. Signature: extern HAMLIB_EXPORT(hamlib_token_t) rig_token_lookup(RIG *rig, const char *name);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_unregister' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: reference_discovery. Source: include/hamlib/rig.h:4001. Signature: extern HAMLIB_EXPORT(int) rig_unregister(rig_model_t rig_model);. API presence is not per-model success, Rust delivery or command permission. */
        }
    }
    attribute def HamlibSampleTransportInteractions {
        attribute 'hamlib.api.rig_stream_caps_at' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: sample_transport. Source: include/hamlib/rig.h:3624. Signature: extern HAMLIB_EXPORT(const struct rig_stream_caps *) rig_stream_caps_at(RIG *rig, int index);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_stream_caps_count' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: sample_transport. Source: include/hamlib/rig.h:3603. Signature: extern HAMLIB_EXPORT(int) rig_stream_caps_count(RIG *rig);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_stream_close' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: sample_transport. Source: include/hamlib/rig.h:3703. Signature: extern HAMLIB_EXPORT(int) rig_stream_close(RIG *rig, rig_stream_t *stream);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_stream_config_alloc' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: sample_transport. Source: include/hamlib/rig.h:3655. Signature: extern HAMLIB_EXPORT(struct rig_stream_config *) rig_stream_config_alloc(void);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_stream_config_free' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: sample_transport. Source: include/hamlib/rig.h:3664. Signature: extern HAMLIB_EXPORT(void) rig_stream_config_free(struct rig_stream_config *config);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_stream_drain' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: sample_transport. Source: include/hamlib/rig.h:3757. Signature: extern HAMLIB_EXPORT(int) rig_stream_drain(RIG *rig, rig_stream_t *stream, int timeout_ms);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_stream_get_conversions' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: sample_transport. Source: include/hamlib/rig.h:3638. Signature: extern HAMLIB_EXPORT(int) rig_stream_get_conversions(const rig_stream_t *stream);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_stream_get_hardware_time' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: sample_transport. Source: include/hamlib/rig.h:3831. Signature: extern HAMLIB_EXPORT(int) rig_stream_get_hardware_time(RIG *rig, rig_stream_t *stream, struct rig_stream_time_anchor *now);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_stream_get_id' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: sample_transport. Source: include/hamlib/rig.h:3848. Signature: extern HAMLIB_EXPORT(int) rig_stream_get_id(const rig_stream_t *stream);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_stream_get_max_payload' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: sample_transport. Source: include/hamlib/rig.h:3861. Signature: extern HAMLIB_EXPORT(int) rig_stream_get_max_payload(const rig_stream_t *stream);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_stream_get_samples_written' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: sample_transport. Source: include/hamlib/rig.h:3818. Signature: extern HAMLIB_EXPORT(uint64_t) rig_stream_get_samples_written(const rig_stream_t *stream);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_stream_get_stats' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: sample_transport. Source: include/hamlib/rig.h:3772. Signature: extern HAMLIB_EXPORT(int) rig_stream_get_stats(RIG *rig, rig_stream_t *stream, struct rig_stream_stats *stats);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_stream_get_time_anchor' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: sample_transport. Source: include/hamlib/rig.h:3806. Signature: extern HAMLIB_EXPORT(int) rig_stream_get_time_anchor(rig_stream_t *stream, struct rig_stream_time_anchor *anchor);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_stream_get_type' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: sample_transport. Source: include/hamlib/rig.h:3841. Signature: extern HAMLIB_EXPORT(rig_stream_type_t) rig_stream_get_type(const rig_stream_t *stream);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_stream_mute' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: sample_transport. Source: include/hamlib/rig.h:3877. Signature: extern HAMLIB_EXPORT(int) rig_stream_mute(RIG *rig, rig_stream_t *stream);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_stream_open' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: sample_transport. Source: include/hamlib/rig.h:3688. Signature: extern HAMLIB_EXPORT(int) rig_stream_open(RIG *rig, const struct rig_stream_config *config, rig_stream_t **stream);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_stream_pause' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: sample_transport. Source: include/hamlib/rig.h:3867. Signature: extern HAMLIB_EXPORT(int) rig_stream_pause(RIG *rig, rig_stream_t *stream);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_stream_read' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: sample_transport. Source: include/hamlib/rig.h:3719. Signature: extern HAMLIB_EXPORT(int) rig_stream_read(RIG *rig, rig_stream_t *stream, void *buffer, size_t buffer_size, size_t *bytes_read, int timeout_ms, struct rig_stream_read_info *info);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_stream_read_metadata' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: sample_transport. Source: include/hamlib/rig.h:3887. Signature: extern HAMLIB_EXPORT(int) rig_stream_read_metadata(RIG *rig, rig_stream_t *stream, struct rig_stream_metadata *meta);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_stream_resume' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: sample_transport. Source: include/hamlib/rig.h:3872. Signature: extern HAMLIB_EXPORT(int) rig_stream_resume(RIG *rig, rig_stream_t *stream);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_stream_unmute' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: sample_transport. Source: include/hamlib/rig.h:3882. Signature: extern HAMLIB_EXPORT(int) rig_stream_unmute(RIG *rig, rig_stream_t *stream);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_stream_wait_write_status' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: sample_transport. Source: include/hamlib/rig.h:3788. Signature: extern HAMLIB_EXPORT(int) rig_stream_wait_write_status(RIG *rig, rig_stream_t *stream, struct rig_stream_write_status *status, int timeout_ms);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_stream_write' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: sample_transport. Source: include/hamlib/rig.h:3740. Signature: extern HAMLIB_EXPORT(int) rig_stream_write(RIG *rig, rig_stream_t *stream, const void *buffer, size_t buffer_size, size_t *bytes_written, int timeout_ms, const struct rig_stream_write_info *info);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_stream_write_metadata' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: sample_transport. Source: include/hamlib/rig.h:3894. Signature: extern HAMLIB_EXPORT(int) rig_stream_write_metadata(RIG *rig, rig_stream_t *stream, const struct rig_stream_metadata *meta);. API presence is not per-model success, Rust delivery or command permission. */
        }
    }
    attribute def HamlibUtilityInteractions {
        attribute 'hamlib.api.add2debugmsgsave' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:3976. Signature: extern HAMLIB_EXPORT(void)add2debugmsgsave(const char *s);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.hl_usleep' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4080. Signature: extern HAMLIB_EXPORT(int) hl_usleep(rig_useconds_t msec);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.locator2longlat' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4095. Signature: extern HAMLIB_EXPORT(int) locator2longlat(double *longitude, double *latitude, const char *locator);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.longlat2locator' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4089. Signature: extern HAMLIB_EXPORT(int) longlat2locator(double longitude, double latitude, char *locator_res, int pair_count);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_copyright' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4063. Signature: extern HAMLIB_EXPORT(const char *) rig_copyright(void);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_date_strget' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4107. Signature: extern HAMLIB_EXPORT(char*) rig_date_strget(char *buf, int buflen, int localtime);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_debug' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:3971. Signature: extern HAMLIB_EXPORT(void) rig_debug(enum rig_debug_level_e debug_level, const char *fmt, ...) HAMLIB_ATTRIBUTE_FORMAT_PRINTF;. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_get_debug' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:3950. Signature: extern HAMLIB_EXPORT(void) rig_get_debug(enum rig_debug_level_e *debug_level);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_idx2setting' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:3941. Signature: extern HAMLIB_EXPORT(setting_t) rig_idx2setting(int i);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_levelagcstr' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4040. Signature: extern HAMLIB_EXPORT(enum agc_level_e) rig_levelagcstr (const char *agcString);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_levelagcvalue' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4041. Signature: extern HAMLIB_EXPORT(enum agc_level_e) rig_levelagcvalue (int agcValue);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_license' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4061. Signature: extern HAMLIB_EXPORT(const char *) rig_license(void);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_mW2power' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:3247. Signature: extern HAMLIB_EXPORT(int) rig_mW2power(RIG *rig, float *power, unsigned int mwpower, freq_t freq, rmode_t mode);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_make_md5' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4100. Signature: extern HAMLIB_EXPORT(char*) rig_make_md5(const char *pass);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_need_debug' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:3958. Signature: extern HAMLIB_EXPORT(int) rig_need_debug(enum rig_debug_level_e debug_level);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_parse_func' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4053. Signature: extern HAMLIB_EXPORT(setting_t) rig_parse_func(const char *s);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_parse_level' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4054. Signature: extern HAMLIB_EXPORT(setting_t) rig_parse_level(const char *s);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_parse_mode' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4051. Signature: extern HAMLIB_EXPORT(rmode_t) rig_parse_mode(const char *s);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_parse_mtype' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4059. Signature: extern HAMLIB_EXPORT(chan_type_t) rig_parse_mtype(const char *s);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_parse_parm' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4055. Signature: extern HAMLIB_EXPORT(setting_t) rig_parse_parm(const char *s);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_parse_rptr_shift' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4058. Signature: extern HAMLIB_EXPORT(rptr_shift_t) rig_parse_rptr_shift(const char *s);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_parse_scan' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4057. Signature: extern HAMLIB_EXPORT(scan_t) rig_parse_scan(const char *s);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_parse_vfo' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4052. Signature: extern HAMLIB_EXPORT(vfo_t) rig_parse_vfo(const char *s);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_parse_vfo_op' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4056. Signature: extern HAMLIB_EXPORT(vfo_op_t) rig_parse_vfo_op(const char *s);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_power2mW' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:3241. Signature: extern HAMLIB_EXPORT(int) rig_power2mW(RIG *rig, unsigned int *mwpower, float power, freq_t freq, rmode_t mode);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_debug' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:3947. Signature: extern HAMLIB_EXPORT(void) rig_set_debug(enum rig_debug_level_e debug_level);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_debug_callback' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:3991. Signature: extern HAMLIB_EXPORT(vprintf_cb_t) rig_set_debug_callback(vprintf_cb_t cb, rig_ptr_t arg);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_debug_file' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:3995. Signature: extern HAMLIB_EXPORT(FILE *) rig_set_debug_file(FILE *stream);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_set_debug_time_stamp' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:3953. Signature: extern HAMLIB_EXPORT(void) rig_set_debug_time_stamp(int flag);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_setting2idx' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:3936. Signature: extern HAMLIB_EXPORT(int) rig_setting2idx(setting_t s);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_stragclevel' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4039. Signature: extern HAMLIB_EXPORT(const char *) rig_stragclevel(enum agc_level_e level);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_strcommstatus' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4049. Signature: extern HAMLIB_EXPORT(const char *) rig_strcommstatus(rig_comm_status_t vfo);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_strfunc' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4036. Signature: extern HAMLIB_EXPORT(const char *) rig_strfunc(setting_t);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_strlevel' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4037. Signature: extern HAMLIB_EXPORT(const char *) rig_strlevel(setting_t);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_strmtype' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4047. Signature: extern HAMLIB_EXPORT(const char *) rig_strmtype(chan_type_t mtype);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_strparm' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4038. Signature: extern HAMLIB_EXPORT(const char *) rig_strparm(setting_t);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_strptrshift' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4043. Signature: extern HAMLIB_EXPORT(const char *) rig_strptrshift(rptr_shift_t);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_strrmode' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4033. Signature: extern HAMLIB_EXPORT(const char *) rig_strrmode(rmode_t mode);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_strrmodes' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4034. Signature: extern HAMLIB_EXPORT(int) rig_strrmodes(rmode_t modes, char *buf, int buflen);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_strscan' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4045. Signature: extern HAMLIB_EXPORT(const char *) rig_strscan(scan_t scan);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_strspectrummode' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4048. Signature: extern HAMLIB_EXPORT(const char *) rig_strspectrummode(enum rig_spectrum_mode_e mode);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_strstatus' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4046. Signature: extern HAMLIB_EXPORT(const char *) rig_strstatus(enum rig_status_e status);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_strvfo' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4035. Signature: extern HAMLIB_EXPORT(const char *) rig_strvfo(vfo_t vfo);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_strvfop' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4044. Signature: extern HAMLIB_EXPORT(const char *) rig_strvfop(vfo_op_t op);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_valueagclevel' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4042. Signature: extern HAMLIB_EXPORT(value_t) rig_valueagclevel (enum agc_level_e agcLevel);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rig_version' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:4062. Signature: extern HAMLIB_EXPORT(const char *) rig_version(void);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rigerror' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:3931. Signature: extern HAMLIB_EXPORT(const char *) rigerror(int errnum);. API presence is not per-model success, Rust delivery or command permission. */
        }
        attribute 'hamlib.api.rigerror2' : RadioInteractionDefinition[0..1] {
            doc /* Reference class: utility. Source: include/hamlib/rig.h:3933. Signature: extern HAMLIB_EXPORT(const char *) rigerror2(int errnum);. API presence is not per-model success, Rust delivery or command permission. */
        }
    }
    attribute def RadioPropertyDictionary {
        attribute revision : String = "hamlib-075b78cb0560e892c81bc73890d633cc11f23f59-research-v5";
        attribute hamlibBackendModelProperties : HamlibBackendModelProperties;
        attribute hamlibBackendVendorProperties : HamlibBackendVendorProperties;
        attribute hamlibCalTableFloatProperties : HamlibCalTableFloatProperties;
        attribute hamlibCalTableProperties : HamlibCalTableProperties;
        attribute hamlibChanListProperties : HamlibChanListProperties;
        attribute hamlibChannelCapProperties : HamlibChannelCapProperties;
        attribute hamlibChannelProperties : HamlibChannelProperties;
        attribute hamlibConnectionProperties : HamlibConnectionProperties;
        attribute hamlibExtListProperties : HamlibExtListProperties;
        attribute hamlibFilterListProperties : HamlibFilterListProperties;
        attribute hamlibFreqRangeListProperties : HamlibFreqRangeListProperties;
        attribute hamlibFunctionProperties : HamlibFunctionProperties;
        attribute hamlibGlobalParameterProperties : HamlibGlobalParameterProperties;
        attribute hamlibGranProperties : HamlibGranProperties;
        attribute hamlibHamlibPortProperties : HamlibHamlibPortProperties;
        attribute hamlibLevelProperties : HamlibLevelProperties;
        attribute hamlibModelCapabilityProperties : HamlibModelCapabilityProperties;
        attribute hamlibOperatingProperties : HamlibOperatingProperties;
        attribute hamlibRadioStreamModelProperties : HamlibRadioStreamModelProperties;
        attribute hamlibRigSpectrumAvgModeProperties : HamlibRigSpectrumAvgModeProperties;
        attribute hamlibRigSpectrumLineProperties : HamlibRigSpectrumLineProperties;
        attribute hamlibRigSpectrumScopeProperties : HamlibRigSpectrumScopeProperties;
        attribute hamlibRigStreamCapsProperties : HamlibRigStreamCapsProperties;
        attribute hamlibRigStreamConfigProperties : HamlibRigStreamConfigProperties;
        attribute hamlibRigStreamMetadataProperties : HamlibRigStreamMetadataProperties;
        attribute hamlibRigStreamReadInfoProperties : HamlibRigStreamReadInfoProperties;
        attribute hamlibRigStreamStatsProperties : HamlibRigStreamStatsProperties;
        attribute hamlibRigStreamTimeAnchorProperties : HamlibRigStreamTimeAnchorProperties;
        attribute hamlibRigStreamWriteInfoProperties : HamlibRigStreamWriteInfoProperties;
        attribute hamlibRigStreamWriteStatusProperties : HamlibRigStreamWriteStatusProperties;
        attribute hamlibTuningStepListProperties : HamlibTuningStepListProperties;
        attribute hamlibVendorProperties : HamlibVendorProperties;
        doc /* Consolidated typed property-column vocabulary in the part model,
             not a separately maintained external dictionary or live defaults. */
    }
    attribute def RadioPropertyValue {
        attribute dictionaryPropertyId : String;
        attribute context : RadioApplicabilityContext;
        attribute booleanValue : Boolean[0..1];
        attribute integerValue : Integer[0..1];
        attribute realValue : Real[0..1];
        attribute textValue : String[0..1];
        attribute elements : RadioPropertyValue[*];
        attribute bytes : Integer[*];
        doc /* Model-defined value shape, not a wire request. Exactly the selected
             property's scalar/enum/set/bitmask/list/record/bytes domain applies; bytes
             are 0..255, ordered elements retain order and record members retain IDs.
             Unknown/unavailable observations have no invented scalar/default value.
             When used as requested intent, the selected-model property must permit
             writing in its applicable context; read-only measurements are never
             setter requests. Intent still grants no command/implementation authority. */
    }
    attribute def RadioPropertyObservation {
        attribute propertyValue : RadioPropertyValue[0..1];
        attribute dictionaryPropertyId : String;
        attribute context : RadioApplicabilityContext;
        attribute observedAtMs : Integer[0..1];
        attribute current : Boolean;
        attribute provenance : String[0..1];
        attribute unavailableReason : String[0..1];
        doc /* Full intended observed-value vocabulary, separate from desired/requested
             values, catalogue domains and Rust coverage. Current is established by
             matching actual observations, not model selection or a default. Concrete
             wire representation for future properties remains unsettled. */
    }
    enum def RadioBehaviorStatus { enum formalized; enum partial; enum commented; enum unresolved; }
    enum def RadioEvidenceCoverage {
        enum indexed_behavior_pending; enum hand_reviewed_semantic_record;
    }
    attribute def RadioSourceArgument {
        attribute position : Integer;
        attribute sourceExpression : String;
        attribute meaning : String;
    }
    attribute def RadioSourceConditionContext {
        attribute kind : String;
        attribute predicateSource : String;
        attribute sourceEvidence : RadioBehaviorSource;
    }
    attribute def RadioSourceObservation {
        attribute kind : String;
        attribute sourceEvidence : RadioBehaviorSource;
        attribute lexicalOrder : Integer;
        attribute member : String[0..1];
        attribute assignmentOperator : String[0..1];
        attribute valueSource : String[0..1];
        attribute callee : String[0..1];
        attribute arguments : RadioSourceArgument[*];
        attribute conditionContext : RadioSourceConditionContext[*];
        attribute semantics : String;
        doc /* Source-ordered member-write/call/condition evidence, with concrete source
             arguments and lines. Lexical ordering is not proven runtime reachability,
             evaluated branch semantics, error propagation or physical confirmation. */
    }
    attribute def RadioFunctionEvidence {
        attribute id : String;
        attribute symbol : String;
        attribute sourceEvidence : RadioBehaviorSource;
        attribute status : RadioBehaviorStatus;
        attribute coverageStatus : RadioEvidenceCoverage;
        attribute orderedSourceObservations : RadioSourceObservation[*];
        attribute directCalleeReferences : String[*];
        attribute 'comment' : String;
        attribute analysisObligations : String[*];
        doc /* Function index and source observations are reference evidence. Most
             bodies are indexed_behavior_pending; only a separately reviewed semantic
             record supplies behavioral coverage. Neither indexing nor a source comment
             is a complete contract or a claim that the function was executed. */
    }
    attribute def RadioBehaviorInput {
        attribute name : String;
        attribute typeName : String;
        attribute unit : String[0..1];
        attribute domainDescription : String[0..1];
        attribute direction : String[0..1];
    }
    attribute def RadioBehaviorStep {
        attribute order : Integer;
        attribute semantics : String;
        doc /* Ordered rule/branch/conversion/transaction effect with source evidence
             in the containing contract; not executable source code or a command. */
    }
    attribute def RadioBehaviorSource {
        attribute path : String;
        attribute line : Integer;
        attribute commit : String;
        attribute url : String;
    }
    attribute def RadioBehaviorScalar {
        attribute integerValue : Integer[0..1];
        attribute realValue : Real[0..1];
        attribute textValue : String[0..1];
        attribute booleanValue : Boolean[0..1];
    }
    attribute def RadioBehaviorCondition {
        attribute field : String[0..1];
        attribute comparison : String[0..1];
        attribute value : RadioBehaviorScalar[0..1];
        attribute 'all' : RadioBehaviorCondition[*];
        attribute 'any' : RadioBehaviorCondition[*];
        attribute 'otherwise' : Boolean[0..1];
        doc /* Structured comparison/all/any/otherwise predicates in shared reference
             rules. Names designate source inputs/results, not expressions to execute. */
    }
    attribute def RadioBehaviorOutcome {
        attribute kind : String;
        attribute symbol : String;
    }
    attribute def RadioBehaviorResponseRule {
        attribute priority : Integer;
        attribute condition : RadioBehaviorCondition;
        attribute outcome : RadioBehaviorOutcome;
    }
    attribute def RadioWireField {
        attribute kind : String;
        attribute name : String[0..1];
        attribute constantBytes : Integer[*];
        attribute constantText : String[0..1];
        attribute byteCount : Integer[0..1];
        attribute byteCountExpression : String[0..1];
        attribute encoding : String[0..1];
        attribute absenceValue : Integer[0..1];
        attribute domain : String[*];
    }
    attribute def RadioWireFrame {
        attribute direction : String;
        attribute transport : String[0..1];
        attribute command : Integer[0..1];
        attribute subcommand : RadioBehaviorScalar[0..1];
        attribute fields : RadioWireField[*];
        attribute template : String[0..1];
        attribute conditions : String[*];
        attribute payloadBytes : Integer[0..1];
        doc /* Inert source-derived frame layout, including constants/optional fields,
             command/subcommand variants and symbolic lengths. Not a raw-send API. */
    }
    attribute def RadioBehaviorConversion {
        attribute name : String;
        attribute inputType : String[0..1];
        attribute outputType : String[0..1];
        attribute inputUnit : String[0..1];
        attribute outputUnit : String[0..1];
        attribute encoding : String[0..1];
        attribute formula : String[0..1];
        attribute scale : Real[0..1];
        attribute steps : String[*];
        attribute table : Real[*];
        attribute applicability : RadioApplicabilityContext[0..1];
        doc /* Explicit BCD/ASCII/scaling/rounding/table conversion knowledge with source
             context. Formula text is descriptive; this model executes no interpreter. */
    }
    attribute def RadioBehaviorModeMapping {
        attribute requested : String[0..1];
        attribute base : String;
        attribute dataFlag : Integer[0..1];
        attribute whenDataFlagNonzero : String[0..1];
    }
    attribute def RadioBehaviorFilterRule {
        attribute priority : Integer;
        attribute condition : String;
        attribute 'filter' : RadioBehaviorScalar;
        attribute overridesPrevious : Boolean[0..1];
    }
    attribute def RadioBehaviorRetryRule {
        attribute initialAttempts : Integer;
        attribute maximumAdditionalAttemptsSource : String;
        attribute assumesNonnegativeRetry : Boolean;
        attribute stopStatuses : String[*];
        attribute retryWaitMs : Integer;
        attribute replaysWrite : Boolean;
        doc /* Reference implementation retry rule only. This project's no-write-replay
             policy stays authoritative even where Hamlib retries a write. */
    }
    attribute def RadioBehaviorDelay {
        attribute 'after' : String;
        attribute value : Real;
        attribute unit : String;
    }
    attribute def RadioBehaviorVariant {
        attribute model : String[0..1];
        attribute firmwareVersionUpperInclusive : String[0..1];
        attribute condition : String[0..1];
        attribute behavior : String;
    }
    attribute def RadioBehaviorObservationPolicy {
        attribute writesCacheBeforeReadback : Boolean;
        attribute transactionReturnChecked : Boolean;
        attribute successImpliesPhysicalConfirmation : Boolean;
    }
    attribute def RadioBehaviorContextValue {
        attribute name : String;
        attribute value : RadioBehaviorScalar;
        attribute values : RadioBehaviorScalar[*];
        attribute unit : String[0..1];
        doc /* Source-specific handler parameters/variant facts, not independently
             observed hardware state, new profile settings or universal defaults. */
    }
    attribute def RadioBehaviorContract {
        attribute id : String;
        attribute handler : String;
        attribute status : RadioBehaviorStatus;
        attribute summary : String;
        attribute inputs : RadioBehaviorInput[*];
        attribute preconditions : String[*];
        attribute orderedSteps : RadioBehaviorStep[*];
        attribute responseSemantics : String[*];
        attribute failureSemantics : String[*];
        attribute stateEffects : String[*];
        attribute comments : String[*];
        attribute variantContext : RadioApplicabilityContext[0..1];
        attribute sourceEvidence : RadioBehaviorSource[*];
        attribute wireFrames : RadioWireFrame[*];
        attribute wireCommands : RadioWireFrame[*];
        attribute conversions : RadioBehaviorConversion[*];
        attribute modeMapping : RadioBehaviorModeMapping[*];
        attribute filterSelectionRules : RadioBehaviorFilterRule[*];
        attribute responseRules : RadioBehaviorResponseRule[*];
        attribute retryRule : RadioBehaviorRetryRule[0..1];
        attribute delays : RadioBehaviorDelay[*];
        attribute variants : RadioBehaviorVariant[*];
        attribute observationPolicy : RadioBehaviorObservationPolicy[0..1];
        attribute capabilityContextValues : RadioBehaviorContextValue[*];
        attribute appliesToModels : String[*];
        attribute helperBehaviorReferences : String[*];
        attribute functionReferences : String[*];
        attribute ownership : String;
        doc /* Source-derived behavioral contract: inputs/guards, ordered interactions
             and conversions, replies, errors, resulting state and variant context.
             Formalized applies only to the explicitly bounded record; partial/commented
             records retain source-based rules and unresolved decisions. A commented
             source index remains indexed_behavior_pending without a reviewed semantic
             record; a signature/function pointer alone is never behavior. The JSON companion
             owns shared rule records and model-operation links; no interpreter, Hamlib
             library execution or new radio command interface is introduced.
             Hamlib fallback/retry/cache rules describe that reference implementation.
             They MUST NOT replace this project's independent CAT readback, no-write-
             replay, operation identity, common authority and transmit safety contracts.
             Typed records and semantic validation do not execute/prove the behavior. */
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
        attribute behaviorReferences : String[*];
        attribute behaviorStatus : RadioBehaviorStatus;
        attribute evidenceCoverage : RadioEvidenceCoverage;
        attribute behaviorComment : String[0..1];
        attribute sourceHandler : String[0..1];
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
        attribute dataPath : String = "docs/sysml/data/hamlib-models.json";
        attribute revision : String;
        attribute dictionaryRevision : String;
        attribute sources : RadioReferenceSource[*];
        attribute models : RadioModelDefinition[*];
        attribute behaviorContracts : RadioBehaviorContract[*];
        attribute functionEvidence : RadioFunctionEvidence[*];
        attribute coverage : WstxRequirements::ImplementationState = WstxRequirements::ImplementationState::target;
        doc /* Second dataset: planned broad immutable/versioned Hamlib-derived model
             catalogue, stored as back-end data and consulted on selection/configuration/
             connection as needed. Its initial source-derived rows are present in
             data/hamlib-models.json; runtime ingestion/lookup remains planned.
             It references this model's typed columns, not an external dictionary. Not a service, periodic task, always-running Hamlib process,
             completed bulk import or additional physical command path. Source revisions/
             licences/context must be retained; ingestion/completeness remain unsettled.
             The implemented limited IC-7300 artifact is tracked separately below.
             WstxRadioIO::Limits::catalogueBytes bounds that selected/compiled driver's
             validated IC-7300 catalogue, not this larger passive source-reference file.
             Runtime reference lookup/loading/residency policy remains planned; this
             data artifact supplies no new parser budget or whole-database load promise. */
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
        attribute catalogueModelId : String[0..1];
        attribute coverage : WstxRequirements::ImplementationState;
        attribute interactionIds : String[*];
        attribute implementation : String;
        attribute 'verification' : String;
        doc /* Separate implementation tracking for the driver/model link: implemented,
             partial or target per interaction. Planned model capabilities stay normative
             even when this driver lacks them. catalogueModelId links the driver's
             model identity to its reference catalogue row, without merging namespaces.
             Current operation admission continues to
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

    verification RadioReferenceDataReview {
        subject deployment :> physicalStation;
        objective {
            verify ComponentPropertyOwnership;
            verify RadioModelReferenceSeparation;
        }
        doc /* Level 2 isolated independent source/data review on the development PC,
             no external device or command. Compare pinned Hamlib headers, capability
             records, configuration/extension declarations and actual handlers with
             Architecture's typed columns and data/hamlib-models.json. Independent
             expected union: 1064 unique property IDs (114 standard settings, 532 vendor
             extension, 105 connection, 80 capability, 25 operating, 208 structured
             members). Check exact ID-set coverage once, types/units/access and source
             contexts; integer/value_t.i is Integer, float/value_t.f Real, standard
             function statuses Integer with per-model legal domains, strings String,
             genuine opaque/action unions explicit. Publication mode retains all three
             source meanings (off/events/polling); finite calibration/level arrays retain
             source bounds32/64 and opaque elements. CHECKBUTTON remains Boolean.
             Exact symbol-token masks determine float/enum/string/read-only classes;
             e.g. AGC differs from AGC_TIME, NOTCHF from NOTCHF_RAW, and measured
             ALC/STRENGTH do not acquire setters. KEYLIGHT's source float/prose on-off
             discrepancy stays explicit rather than guessed.
             Expected 229 distinct classified API references: 82 radio command/query,
             24 sample transport, 7 event, 39 discovery, 28 lifecycle, 48 utility and
             one raw escape reference. Utility/lifecycle/raw references do not become
             physical commands. Check all catalogue property/interaction/source/model
             references resolve; 388 unique model rows distinguish 328 static model
             IDs, 60 identifier-only rows and two conditional declaration variants.
             Static declarations, masks, table membership and defaults are reference
             evidence, never runtime availability or hardware startup observations.
             Check structured source values/range/choice/step tables, sentinels, model
             token filters and unresolved expressions without executing source code.
             Compare source-derived behavior inputs/guards, ordered conversions and
             transactions, reply/error/poststate and variants against actual handler/
             helper branches. Follow model operation links to shared behavior records.
             A function name, signature, pointer or call graph alone MUST NOT count as
             formalized behavior. Complex partial/commented cases retain source-based
             explanations and uncertainty; formalized status covers only its stated
             bounded rule. Hamlib retry/cache/fallback must not weaken this product's
             independent readback/no-replay/authority safety policies.
             Name/type resolution and structural integrity are automated companions,
             not exhaustive source-equivalence or runtime proofs. Broad catalogue
             ingestion, unsupported radio interactions and physical acceptance remain
             planned unless their own canonical implementation/evidence says otherwise. */
        attribute method : String = "manual source-grounded type/access/behavior review and relational JSON/column/source reference checks";
        attribute executionStatus : String = "planned independent review; no runtime or formal proof verdict asserted";
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
        attribute operatingPropertyColumns : HamlibOperatingProperties;
        attribute levelPropertyColumns : HamlibLevelProperties;
        attribute functionPropertyColumns : HamlibFunctionProperties;
        attribute globalParameterColumns : HamlibGlobalParameterProperties;
        attribute vendorPropertyColumns : HamlibVendorProperties;
        attribute modelCapabilityColumns : HamlibModelCapabilityProperties;
        attribute memoryChannelColumns : HamlibChannelProperties;
        attribute spectrumScopeColumns : HamlibRigSpectrumLineProperties;
        attribute interactionReferences : HamlibRadioCommandQueryInteractions;
        doc /* These typed column groups define intended applicable radio properties;
             selected model cells supply domains/choices/context. They do not fill
             requested/observed values, universal defaults or current Rust support. */
        attribute physicalIdentity : String[0..1];
        attribute selectedModelDefinition : SelectedRadioModel[0..1];
        attribute observedProperties : WstxRadioIO::RadioObservation[0..1];
        attribute normalizedObservedState : NormalizedRadioState;
        attribute intendedPropertyObservations : RadioPropertyObservation[*];
        attribute radioSpectrumSpanHz : Real[0..1];
        attribute physicalReceiverBandwidthHz : Real[0..1];
        doc /* Selected model reference exposes its full applicable property/interaction
             definitions, independent of Rust coverage. Physical identity is not a
             station-count-derived radio number. Actual filter width remains unknown
             unless independently established for this radio/filter; FIL1..3, DSP
             passband and browser 0..3000Hz do not establish receiver bandwidth.
             radioSpectrumSpanHz describes the radio's own spectrum/scope span, a
             third independent property; no radio spectrum or filter default is inferred. */
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
        attribute intendedNativeAndEffectiveStreamColumns : HamlibRigStreamCapsProperties;
        attribute radioStreamModelColumns : HamlibRadioStreamModelProperties;
        attribute intendedStreamConfigurationColumns : HamlibRigStreamConfigProperties;
        attribute intendedStreamMetadataColumns : HamlibRigStreamMetadataProperties;
        attribute intendedStreamTimingColumns : HamlibRigStreamTimeAnchorProperties;
        attribute intendedStreamStatisticsColumns : HamlibRigStreamStatsProperties;
        attribute sampleTransportReferences : HamlibSampleTransportInteractions;
        doc /* Radio/backend audio and IQ stream vocabulary preserves native versus
             effective format/rate/channels, optional timing and statistics. It does
             not imply today's PC audio adapter implements all streams or native APIs. */
        attribute configuredIntent : WstxRadioIO::DeviceIntent;
        attribute observedState : WstxRadioIO::AudioState;
        attribute observedNativeFormat : WstxRadioIO::NativeFormat[0..1];
        attribute observedNativeRateHz : Integer[0..1];
        attribute observedNativeChannels : Integer[0..1];
        attribute observedNativeEndpointId : String[0..1];
        attribute observedSourceTiming : WstxRadioIO::SourceTiming[0..1];
        attribute deviceAndTimingLimits : WstxRadioIO::Limits;
        doc /* configuredIntent is a derived selected-profile view, not independent
             persistence. Endpoint/channel intent differs from actual open source,
             format/rate/channel/endpoint observations (views of NativePacket), device
             clock and failure state. Supported native packet
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
        attribute eventSubscriptionReferences : HamlibEventSubscriptionInteractions;
        attribute configuredIntent : WstxProfiles::ControlSelection;
        attribute intendedRequestedProperties : RadioPropertyValue[*];
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
        attribute connectionPropertyColumns : HamlibConnectionProperties;
        attribute backendModelColumns : HamlibBackendModelProperties;
        attribute backendVendorPolicyColumns : HamlibBackendVendorProperties;
        attribute portPropertyColumns : HamlibHamlibPortProperties;
        attribute discoveryReferences : HamlibReferenceDiscoveryInteractions;
        attribute lifecycleReferences : HamlibConnectionBackendLifecycleInteractions;
        attribute utilityReferences : HamlibUtilityInteractions;
        attribute rawEscapeReference : HamlibRawVendorEscapeInteractions;
        doc /* Backend lifecycle, discovery, utilities and documented raw escape are
             classified source references, not new physical commands or a callable
             raw-command facility. Existing typed receive-only driver remains guarded. */
        attribute parsedConfiguration : ParsedCatConfiguration[0..1];
        attribute observed : WstxRadioIO::RadioObservation[0..1];
        attribute implementationCoverage : RadioDriverCoverage[*];
        attribute currentIc7300Coverage : RadioDriverCoverage {
            attribute :>> modelId = "icom.ic7300";
            attribute :>> catalogueModelId = "RIG_MODEL_IC7300";
            attribute :>> coverage = WstxRequirements::ImplementationState::partial;
            attribute :>> implementation = "server/src/radio_control/mod.rs; server/src/radio_control/catalogue.rs; fixtures/radio/ic7300-catalogue.json";
            attribute :>> 'verification' = "WstxRequirements::TC-009-001; WstxRequirements::TC-009-003; server/tests/radio_control.rs";
        }
        doc /* Current IC-7300 compiled typed receive-control subset is delivery
             metadata, not a ceiling on RadioModelDefinition. The existing catalogue
             validates known command metadata and cannot install a driver/raw/TX action.
             Parsed endpoint, requested operation and actual observation stay separate. */
        port authorized : ~RadioControl;
        port radio : RadioControl;
    }
    abstract part def RadioBackend {
        attribute propertyDictionary : RadioPropertyDictionary;
        attribute referenceCatalogue : RadioReferenceCatalogue[0..1];
        doc /* Passive back-end reference data may be shared immutably across stations.
             SelectedRadioModel identifies one record by revision/model ID; catalogue
             typed property-column authority is Architecture.sysml; per-model values in
             data/hamlib-models.json stay separate from driver implementation
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
