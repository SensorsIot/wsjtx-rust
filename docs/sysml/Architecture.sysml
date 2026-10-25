// Canonical architecture SHA256: dc8fc50115252f384bb3bb510b2ff3f0afda178e25c619922742d6de74bee293
package WstxArchitecture {
    doc /* Manually modeled projection of docs/ARCHITECTURE.md. Markdown is authoritative.
         This is target structure, not a claim that Rust modules or radio support exist.
         Dependencies express design/trace relationships, not behavioral satisfaction. */

    part def PersistedProfile {
        doc /* Target: one explicitly selected profile per station process; stable identity,
             exclusive ownership and isolated storage. Persistence schema belongs to its CR. */
    }
    part def StationService {
        doc /* Target: authoritative state, validated operations, jobs and operation authority.
             HTTP and MCP do not own independent state or bypass this service. */
    }
    part def WebAdapter;
    part def BrowserClient;
    part def McpAdapter;
    part def ReceivePipeline;
    part def ModeFunctions {
        doc /* Target: pure protocol calculations, independent of hardware/network/wall clock. */
    }
    part def TransmitService {
        doc /* Target: coordinates audio and radio/PTT, timing and priority halt. */
    }
    part def QsoAndLogging;

    part def AudioInterface {
        doc /* Target: sample movement, device/rate/timing metadata and audio failures.
             Does not issue CAT/PTT commands; usable with radio control disabled. */
    }
    part def RadioControlInterface {
        doc /* Target: selected radio capabilities, frequency/mode/status, PTT and failures.
             Does not move samples or open audio devices. Rust drivers cover only the
             application's required subset; no complete Hamlib port or C ABI is promised. */
    }
    part def StandardAudio :> AudioInterface;
    part def RustRadioDrivers :> RadioControlInterface;
    part def NativeFlexAudio :> AudioInterface;
    part def NativeFlexControl :> RadioControlInterface;
    part def NativeFlexSession {
        doc /* Optional target: native control/sample implementations may share a managed
             radio session; they retain separate station-facing responsibilities. */
    }
    part def SharedRadioCoordinator {
        doc /* Optional target: one effective cross-process authority for shared radio
             resources. Independent per-process mutexes are insufficient. Placement and
             leases are settled against actual API/hardware limits before implementation. */
    }
    dependency flexAudioSession from NativeFlexAudio to NativeFlexSession;
    dependency flexControlSession from NativeFlexControl to NativeFlexSession;
    dependency sharedAuthority from SharedRadioCoordinator to NativeFlexSession;

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
    }
    part stationProcesses[*] : StationProcess;
    part browserWindows[*] : BrowserClient;
    part optionalSharedCoordinator[0..1] : SharedRadioCoordinator;

    dependency browserOperations from BrowserClient to WebAdapter;
    dependency webOperations from WebAdapter to StationService;
    dependency mcpOperations from McpAdapter to StationService;
    dependency profileContext from StationService to PersistedProfile;
    dependency receiveJobs from StationService to ReceivePipeline;
    dependency receiveSamples from ReceivePipeline to AudioInterface;
    dependency modeProcessing from ReceivePipeline to ModeFunctions;
    dependency transmitAudio from TransmitService to AudioInterface;
    dependency transmitControl from TransmitService to RadioControlInterface;
    dependency qsoOperations from QsoAndLogging to StationService;
    dependency audioPromise from AudioInterface to WstxRequirements::'FR-002';
    dependency controlPromise from RadioControlInterface to WstxRequirements::'FR-009';
    dependency profilesPromise from PersistedProfile to WstxRequirements::'FR-022';
    dependency flexPromise from NativeFlexSession to WstxRequirements::'FR-023';

    package ImplementedStatusSlice {
        doc /* Current subset: server/src/main.rs serves the embedded client and the
             status/TLS protocol. This does not instantiate the target radio architecture. */
        part def StatusServer;
        part server : StatusServer;
        part browser : BrowserClient;
        dependency statusScope from StatusServer to WstxRequirements::'CL-003-01';
        dependency statusProtocol from StatusServer to WstxRequirements::'CL-003-02';
    }
}
