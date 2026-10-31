package WstxRadioIO {
    private import ScalarValues::*;
    doc /* Canonical capture/CAT contract with partial native Windows and IC-7300 implementation;
         hardware matrix completion and physical acceptance remain separately declared.
         Contract: contract 4.5/12.8; recorded source and pure decoder contracts remain
         RecordingReceive/StationDecode. One physical architecture, no new deployment.
         Windows binding0.62.2 shared between WASAPI and overlapped serial I/O.
         Full normative operation, state, wire and oracle text follows this package. */
    enum def AudioState { enum closed; enum opening; enum running; enum closing; enum unavailable; }
    enum def CatState { enum closed; enum connecting; enum ready; enum closing; enum unavailable; }
    enum def NativeFormat { enum float32; enum pcm16; enum pcm24; enum pcm32; }
    enum def ReceiveMode { enum spectrum; enum ft4; enum ft8; }
    enum def CatOperation { enum read_frequency; enum read_mode; enum read_data; enum read_rx_tx; enum read_split; enum set_frequency; enum set_mode; enum set_data; enum receive_setup; }
    attribute def Limits {
        attribute canonicalHz : Integer = 12000;
        attribute blockFrames : Integer = 240;
        attribute nativeQueueMs : Integer = 500;
        attribute canonicalQueueFrames : Integer = 12000;
        attribute nativePacketFrames : Integer = 8192;
        attribute converterBytes : Integer = 4194304;
        attribute filterSupportNativeFrames : Integer = 1024;
        attribute converterDelayMs : Integer = 20;
        attribute cpuQuantumMs : Integer = 50;
        attribute softwareBacklogMs : Integer = 200;
        attribute cancelMs : Integer = 250;
        attribute catFrameBytes : Integer = 32;
        attribute catReadBytes : Integer = 256;
        attribute catExchangeBytes : Integer = 4096;
        attribute catExchangeFrames : Integer = 64;
        attribute catExchangeMs : Integer = 1000;
        attribute catCompositeMs : Integer = 5000;
        attribute catalogueBytes : Integer = 262144;
        attribute retainedRecords : Integer = 2048;
        attribute retainedBytes : Integer = 2097152;
        attribute correlatedClockUncertaintyNs : Integer = 2000000;
        attribute clockJumpMs : Integer = 20;
    }
    attribute def DeviceIntent {
        attribute audioEndpointId : String[0..1];
        attribute audioChannel : Integer = 0;
        attribute controlEndpoint : String[0..1];
        attribute pttDisabled : Boolean = true;
        doc /* Existing schema1 profile/audio/control shape and revision own persistence.
             Exact opaque audio ID, no default fallback. COMn compatibility or strict
             icom7300://COMn?baud=auto&radio=94&controller=E0 with contract 4.5 grammar.
             Catalogue/live observations are not persisted intent or permission. */
    }
    item def NativePacket {
        attribute endpointId : String;
        attribute deviceFrame : Integer;
        attribute packetQpc100ns : Integer;
        attribute frames : Integer;
        attribute channels : Integer;
        attribute rateHz : Integer;
        attribute format : NativeFormat;
        attribute bytes : Integer[0..65536];
        attribute silent : Boolean;
        attribute discontinuity : Boolean;
        attribute timestampError : Boolean;
        assert constraint packetBound { frames > 0 and frames <= 8192 and channels >= 1 and channels <= 2 and (rateHz == 44100 or rateHz == 48000) }
        doc /* Raw interleaved little-endian device packet. Byte values0..255. Capture
             pump copies/releases only; float normalization/conversion belongs worker.
             SILENT is known measured zero; timestamp-error/gap is not silence. */
    }
    attribute def SourceTiming {
        attribute sourceId : String;
        attribute segment : Integer;
        attribute nativeRate : Integer;
        attribute nativeAnchorFrame : Real;
        attribute canonicalAnchorFrame : Integer;
        attribute converterDelayNativeFrames : Real;
        attribute qpcAnchor100ns : Integer[0..1];
        attribute systemUtcAnchor : String[0..1];
        attribute uncertaintyNs : Integer[0..1];
        attribute correlated : Boolean;
        attribute externalAccuracy : String = "unknown";
        doc /* Exact rational12000/nativeRate mapping; group delay counted once.
             System-UTC/QPC bracket<=2ms; recheck1s, jump>20ms new timing segment.
             External clock accuracy is not inferred. No wall-time-derived sample count.
             Known gaps advance canonical count; unknown gaps/reopen new identity. */
    }
    attribute def EpochProposal {
        attribute proposalCounter : Integer;
        attribute reason : String;
        attribute nativeRate : Integer;
        attribute firstDeviceFrame : Integer;
        attribute packetQpc100ns : Integer[0..1];
        attribute converterDelayNativeFrames : Real;
        doc /* Identity-free proposal. Receive authority alone allocates new immutable
             descriptor/source/job/generation/timing and acknowledges current counter.
             Until acknowledgement producer returns Pending, exposes no descriptor and
             emits no block. Stale acknowledgement rejected; no old IDs reused. */
    }
    action def AcknowledgeEpoch {
        in proposal : EpochProposal;
        in descriptor : WstxRecordingReceive::SourceDescriptor;
        in timing : SourceTiming;
        out accepted : Boolean;
        doc /* acknowledge_epoch(proposalCounter,descriptor,timing) accepts only current
             source-local proposal. Capture I/O cannot invent station identities. */
    }
    item def LiveSampleBlock :> WstxRecordingReceive::SampleBlock {
        attribute timing : SourceTiming;
        doc /* Refines SAME immutable canonical12k SampleBlock, <=240frames here;
             descriptor.total_frames absent. No change to recordedPCM/32768 semantics.
             One converter only, no fake filter edges/silence, no gap-crossing window.
             Consumers retain<=2active references plus separately bounded FIFO. */
    }
    attribute def AnalysisOverrun {
        attribute first_frame : Integer;
        attribute end_frame : Integer;
        assert constraint boundedInterval { first_frame >= 0 and first_frame < end_frame and end_frame <= (900719925 * 10000000 + 4740991) }
        doc /* Latest abandoned analysis window's half-open support, not missing audio.
             end_frame<=capturedNextFrame. Null until overrun, replace on next,
             clear on newjob/sourceepoch. ExactGET/receive.job key last_overrun. */
    }
    attribute def RelativeDecodeTiming {
        attribute mode : ReceiveMode;
        attribute correlated : Boolean;
        attribute observedStartSeconds : Real;
        attribute periodStartSeconds : Real;
        attribute periodSeconds : Real;
        attribute nominalStartSeconds : Real;
        attribute dtSeconds : Real;
        attribute externalAccuracyKnown : Boolean = false;
        assert constraint modeTiming {
            (mode == ReceiveMode::ft8 and periodSeconds == 15.0 and nominalStartSeconds == 0.5) or
            (mode == ReceiveMode::ft4 and periodSeconds == 7.5 and nominalStartSeconds == 0.452)
        }
        assert constraint relativeOffset {
            dtSeconds == observedStartSeconds - periodStartSeconds - nominalStartSeconds and
            dtSeconds >= -periodSeconds / 2.0 and dtSeconds < periodSeconds / 2.0
        }
        doc /* contract 4.7.4/12.8. Used only with correlated source timing. Observed start
             comes from canonical frame/UTC anchor at12000Hz, not arrival/browser time.
             Nearest nominal UTC grid start; ties select later period. Positive late,
             negative early. External accuracy unknown does not suppress relative DT.
             Without correlation live wire period_start_utc and dt_seconds are null.
             FT4 includes leading576-frame ramp:0.5-576/12000=0.452s. */
    }
    attribute def LatestDecodePeriod {
        attribute id : Integer;
        attribute first_sequence : Integer;
        attribute next_sequence : Integer;
        attribute period_start_utc : String[0..1];
        attribute complete : Boolean;
        attribute abandoned : Boolean;
        attribute qualifiedWindow : Boolean;
        assert constraint safeIdentity { id > 0 and id <= (900719925 * 10000000 + 4740991) }
        assert constraint frozenRange { first_sequence >= 0 and next_sequence >= first_sequence and next_sequence <= (900719925 * 10000000 + 4740991) }
        assert constraint neverFalseComplete { abandoned implies not complete }
        doc /* Existing manager owns this nullable metadata and existing ring, no new
             endpoint/cache/modem. Publish atomically at finished/overrun attempt only.
             Select latest UTC period with nominal support wholly inside actual window;
             FT8 support12.64s/period15s/offset0.5, FT4 5.04s/7.5s/0.452.
             No qualified period => no publication; never move selected period backwards.
             Without correlation range is that attempt's newly published records, time null.
             Correlated range encloses matching retained records, empty => both equal
             frozen publication end. Job snapshot and result page expose same exact keys.
             Gap clears view without reusing IDs; epoch resets it/ID. Cancellation/failure
             cannot create complete empty view; last published output keeps truthful status.
             Existing evictions/410/caps remain authoritative. */
    }
    attribute def LiveResultWindow {
        attribute latest_decode : LatestDecodePeriod[0..1];
        attribute last_overrun : AnalysisOverrun[0..1];
        attribute first_sequence : Integer;
        attribute next_sequence : Integer;
        attribute available_count : Integer;
        attribute capturedNextFrame : Integer;
        assert constraint retained { first_sequence >= 0 and next_sequence >= first_sequence and available_count == next_sequence - first_sequence and available_count <= 2048 }
        assert constraint safeCounters { next_sequence <= (900719925 * 10000000 + 4740991) and capturedNextFrame >= 0 and capturedNextFrame <= (900719925 * 10000000 + 4740991) }
        doc /* Live ONLY: sequence/start_frame safe nonnegative integers below lifetime
             next_sequence/capturedNextFrame, using safe lifetime domains rather than finite fixture bounds.
             Oldest eviction advancesfirst_sequence,2048records/2MiB, no counter reuse.
             Counterexhaustion fails beforeoverflow. Exact live page keys12.8; cursor<first
             gives410cursor_expired, cursor>next400, cursor==nextempty/morefalse.
             first6/next2054/count2048,cursor7limit1=>record7,next8,moretrue;cursor5=>410.
             Tests2047/2048/2049 andsafeintboundaries; Live record domains use safe lifetime counters and actual captured bounds. */
    }
    attribute def RadioObservation {
        attribute frequencyHz : Integer[0..1];
        attribute mode : String[0..1];
        attribute 'filter' : Integer[0..1];
        attribute data : Boolean[0..1];
        attribute dataFilter : Integer[0..1];
        attribute split : Boolean[0..1];
        attribute rxTx : String[0..1];
        attribute observedAtMs : Integer;
        doc /* Only measured values, unknown is absent/null. Closed/stale observations
             are never current readiness. Unknown mode code is preserved explicitly. */
    }
    item def CatRequest :> WstxArchitecture::ControlRequest {
        attribute operation : CatOperation;
        attribute connectionGeneration : Integer;
        attribute frequencyHz : Integer[0..1];
        attribute mode : String[0..1];
        attribute 'filter' : Integer[0..1];
        attribute data : Boolean[0..1];
        attribute dataFilter : Integer[0..1];
        doc /* Compiled typed union exact per contract 12.8, not arbitrary optional combinations.
             Frequency30000..74800000; settersUSB/LSB/FIL1..3; DATAOFF00/00.
             No raw command, PTT/TX setter, VOX or tuner operation. */
    }
    item def CatResult :> WstxArchitecture::ControlOutcome {
        attribute connectionGeneration : Integer;
        attribute observation : RadioObservation;
        attribute error : String[0..1];
        doc /* ACK requires independent matching readback; mismatch/failure indeterminate.
             No retry, replay or invented rollback. Independent from receive generation. */
    }
    action def CaptureAudio {
        in intent : DeviceIntent;
        out packet : NativePacket;
        doc /* WASAPIshared/event-driven, exact inputID, no fallback. Bounded preallocated
             I/O pump releases packets before heavy work. NativeFIFO500ms; no disk spool.
             1/2/4/8s same-endpoint reopen only while capture desired; new epoch each open.
             Actual close before readiness/release; independent CAT remains responsive. */
    }
    action def ConvertAndReceive {
        in packet : NativePacket;
        out block : LiveSampleBlock;
        doc /* Single DSP owner fans out to existing FFT and pure decoder. FIR passband
             0..3500Hz +-0.1dB, stop>=5500Hz >=60dB, exact rational output count and
             partition invariance2e-5; delay<=20ms/<=1024native support. No second
             conversion or AGC. Known gaps reset FIR/FFT/decoder without invented samples.
             FT8trailing30s/advance15s, FT4trailing15s/advance7.5s; no queued analyses.
             Missed boundary drops outstanding future and records latest abandoned
             window support in last_overrun; partials retained, no fabricated audio gap.
             Newest supported window replaces obsolete work, never claims complete history.
             Existing receive owner mutually excludes imports/file jobs/live; CPU50ms
             quanta service conversion/spectrum. Software backlog<=200ms, normalcancel250ms.
             Retain2048records/2MiB; livefirst_sequence eviction and410cursor_expired.
             Fixed0..3000display does not change decoder200..3500search. */
    }
    action def ExecuteCat {
        in request : CatRequest;
        out result : CatResult;
        doc /* Samephysicalresource retainedlock+exclusive serial0, overlappedWin32IO,
             CancelIoEx/8N1/nohandshake/DTRRTSdisabled afterverifiedreceive-onlyprecondition.
             One lease/noqueue, frame32/read256/exchange4096+64frames/deadline1s,
             setup5s/poll<=1cycle/s/IOcancel50ms. Echo/foreign/broadcastnotcompletion,
             malformedexpectedreplyerror, deadlinesneverrenew. Auto-baudconnectionphase
             [9600,19200,4800,115200,57600,38400],one03/rate500ms+100msquiet,total5s;
             explicitrateone1sprobe. Noaddressscan or write replay. No retry of an
             issued exchange. Target CL-022-03/04 alone permits new read-only
             connection attempts after confirmed release, under persisted matching
             grant/commissioning, bounded backoff and failed-close quarantine.
             This supersedes only the former runtime-automatic-retry prohibition;
             it creates no second owner and never retries a setter or resumes audio.
             Validateimmutableboundedcatalogue separately fromcompiledoperations/state.
             Failed close retains owner. No guarantee of no initial USB-line glitch:
             physicalUSB SEND/CW/RTTY OFF or independentlyverifiedinhibit beforeopen. */
    }
    action capture : CaptureAudio;
    action convertReceive : ConvertAndReceive;
    action execute : ExecuteCat;
    satisfy WstxRequirements::'CL-008-01' by capture;
    satisfy WstxRequirements::'CL-008-02' by convertReceive;
    satisfy WstxRequirements::'CL-008-03' by convertReceive;
    satisfy WstxRequirements::'CL-008-04' by execute;
    satisfy WstxRequirements::'CL-008-05' by capture;
    satisfy WstxRequirements::'CL-008-06' by execute;
    dependency captureOwner from capture to WstxArchitecture::physicalStation::backend::stations::audio;
    dependency conversionOwner from convertReceive to WstxArchitecture::physicalStation::backend::stations::receive;
    dependency controlOwner from execute to WstxArchitecture::physicalStation::backend::stations::radioControl;
    package Verification {
        doc /* Planned Cost2Windows actual candidate adapters/services/browser and independent
             native-clock/device/serial/decoder-step fixtures, no hardware. Physicalcase
             onlyCost4 receive-onlytarget afterverifiedUSBkeyinginhibit. Exact cases and
             complete normative contracts are the source text in this package below. */
        verification audio { subject candidate : ConvertAndReceive; objective { verify WstxRequirements::'CL-008-02'; } }
        verification cat { subject candidate : ExecuteCat; objective { verify WstxRequirements::'CL-008-06'; } }
        verification independent { subject candidate : CaptureAudio; objective { verify WstxRequirements::'CL-008-05'; } }
        dependency audioCase from audio to WstxRequirements::'TC-002-001';
        dependency catCase from cat to WstxRequirements::'TC-009-001';
        dependency independenceCase from independent to WstxRequirements::'TC-002-003';
        dependency catIndependenceCase from cat to WstxRequirements::'TC-009-003';
        dependency combinedCase from independent to WstxRequirements::'TC-009-004';
        dependency physicalCase from cat to WstxRequirements::'TC-009-002';
        dependency physicalIndependenceCase from independent to WstxRequirements::'TC-009-002';
    }
    doc /* Canonical detailed behavior and verification
### 4.5 Separate audio and radio-control functions — target FR-002/FR-009

Audio and CAT are independent station-owned interfaces. Either works while the other
is closed, disabled or unavailable. The shared receive service consumes audio; the
radio-control service reports and applies only its typed supported operations. Neither
interface owns a second profile store, receive job authority, decoder or transmit path.

| Clause | Requirements | Promise | Verification |
|---|---|---|---|
| CL-008-01 | FR-001, FR-002, FR-009, FR-022 | Persist independently selected audio and typed IC-7300 control intent through the existing profile revision/atomic-store boundary; settings never assert device availability. | TC-002-001; TC-009-001 |
| CL-008-02 | FR-002, FR-003, FR-004 | Deliver immutable canonical 12 kHz mono samples and explicit timing/gaps through one common converter to the existing spectrum/decoder worker, without fabricating samples or UTC accuracy. | TC-002-001; TC-002-003; TC-009-002 |
| CL-008-03 | FR-002, FR-009, FR-019, FR-021 | Publish independently truthful audio/control states, bounded live results and explicit loss/recovery while preserving worker, cancellation and thin-link bounds. | TC-002-001; TC-009-001; TC-009-004 |
| CL-008-04 | FR-002, FR-009 | Support the Windows shared-audio and IC-7300 receive-control matrix below, with independently verified receive-only physical acceptance. | TC-009-001; TC-009-002 |
| CL-008-05 | FR-002, FR-009 | Audio never requires CAT; CAT never opens audio. Unsupported operations fail before device bytes; independent failure never creates false readiness. | TC-002-003; TC-009-003; TC-009-004; TC-009-002 |
| CL-008-06 | FR-009 | Separate a versioned factual radio catalogue, compiled typed operations and bounded protocol execution. Catalogue data cannot authorize raw or transmit commands. | TC-009-001; TC-009-003 |

**Ownership and implementation boundary.** The station `recording` receive owner
keeps its single source/job/generation lifecycle for recorded spectrum or
live receive; these are mutually exclusive per profile with no pending-job queue.
The #7 pure `decoder` functions own source decoding, FEC, waveform reconstruction and
mode analysis. The #8 `audio` module owns capture and the only native-to-canonical
converter; `radio_control` owns catalogue validation, CI-V encoding and serial execution.
The existing station/web/profile services own admission, cancellation, persistence and
publication. One integration owner changes shared manifests/bootstrap/browser wiring.
Reuse RustFFT6.4.1 and the existing immutable `SampleBlock`; no second FFT provider,
resampler, sample reader, job manager or configuration database. The shared source
boundary is `SampleSource::descriptor()` plus nonblocking `poll()` returning Pending,
Block(SampleBlock), EpochChanged(EpochProposal), End or Failed(code). An epoch proposal
contains only a source-local proposal counter, reason, native rate/first frame/QPC and
converter delay; it contains no station/source/job identity. Pending is never EOS; only
finite files return End. The file adapter keeps its existing reader; the live adapter
normalizes/converts raw native packets on that same DSP worker. Before any replacement
block, the receive authority invalidates the old tuple and allocates the new descriptor,
source/job/generation and SourceTiming. It calls
`acknowledge_epoch(proposal_counter,SourceDescriptor,SourceTiming)`; the producer accepts
only its current proposal and thereafter stamps immutable blocks with that supplied
context. Until acknowledged, descriptor is absent and poll returns Pending (or a newer
proposal/failure), never an old or producer-invented identity. Stale acknowledgement is
rejected. No other consumer allocates identities. Normal polling/checkpoint work is
bounded by50ms.
The shared Windows API
binding is target-Windows `windows =0.62.2`; capture and CAT share this dependency.
macOS/Linux adapter implementations retain these contracts but are separate releases.

**Configuration and device identity.** Profile document/schema1 and its existing
GET/PUT shape remain unchanged. `audio.input_device` stores an exact opaque
IMMDevice endpoint ID; the UI displays its separately enumerated friendly name.
Unknown, missing or ambiguous input is unavailable, never a default/camera fallback.
The baseline selects channel0; capture accepts mono/stereo 44100/48000 Hz shared mix
formats float32 or signed PCM16/24/32. Preserve finite float values; integer divisors
are 32768/8388608/2147483648. SILENT packets are known zero. Reject nonfinite values,
bad frame alignment, unsupported channel/rate/format and format changes explicitly.
The current target IC-7300 uses its USB Audio CODEC input, independently of COM3.
`audio.output_device` is persisted but receive never opens playback.

`control.mode=cat` selects IC-7300; legacy endpoint `COMn` means model IC-7300,
baud auto, radio address94 and controllerE0. The strict expanded form is
`icom7300://COMn?baud=auto&radio=94&controller=E0`: COMn is COM1..COM256,
baud is auto/4800/9600/19200/38400/57600/115200 and addresses are exactly two hex
digits. Require all three unique keys in that order, no unknown keys, fragments,
escaping or credentials; radio/controller addresses must differ and be01..EF.
The UI exposes model, port, baud and addresses rather than asking an operator to edit
the stored URI. Resolve the selected port to its stable physical USB/serial identity;
never substitute another port/friendly-name match. Independent profile instances use
the existing retained-lock pattern for that physical radio identity and exclusive
CreateFile sharing0; aliases to one radio conflict. Other applications owning the port
produce resource_in_use. `ptt=disabled` is required for this receive slice.

**Capture, conversion and timing.** Use event-driven WASAPI shared capture, with its
actual mix format and packet device-frame/QPC positions. A dedicated capture I/O pump
only copies complete packets to preallocated bounded storage and releases the device
buffer. It never performs FFT, conversion, decoding, disk spooling or network work.
The native packet FIFO holds at most500 ms; packets over8192 native frames are rejected
as an explicit loss. The canonical FIFO holds at most12000 frames; blocks contain
at most240 canonical frames and active consumers retain at most two block references.
The single DSP worker converts/fans out immutable blocks, checking cancellation and
servicing conversion/spectrum between decoder CPU quanta of at most50 ms. Converter
working storage is at most4 MiB; #7's64 MiB modem ceiling remains separate.

Use one bounded rational bandlimited sinc FIR conversion from44100/48000 to12000;
the design may choose its taps within at most1024 native-frame support and20 ms delay.
No AGC, time-stretching or second OS/library conversion. The mathematical response must
have gain within0.1 dB over0..3500 Hz and rejection at least60 dB from5500 Hz to native
Nyquist. Output count/phase follows the exact rational12000/native_rate clock,
independent of callback partition. Account for group delay exactly once in the native
to canonical timestamp mapping. Initial/reset filter support is unobserved: discard
unsupported edges, never label zero-padding as captured samples. Existing canonical
12 kHz recordings bypass this converter unchanged.

Each live source has immutable profile/boot/source/job/generation identity and a timing
sidecar: native rate, native device-frame anchor, canonical-frame anchor, segment,
converter delay, correlated packet-QPC/system-UTC anchor and uncertainty. Frame counters
are monotonic safe integers, never derived from wall time. Known missing native intervals
advance the exact rational canonical counter and mark the next block discontinuous;
they are not inserted as silence. Reset converter, spectrum and decoder windows at a gap.
Unknown loss/timestamp-error, format change or device reopen starts a new source epoch,
generation and frame origin; old samples/results cannot append. A known SILENT packet
remains a real measured interval. No decode waveform may bridge a discontinuity.

Bracket GetSystemTimePreciseAsFileTime with two QPC reads, use midpoint correlation
and record half-bracket uncertainty; at most2 ms permits a correlated system-UTC anchor.
Recheck once/second. A change exceeding20 ms invalidates that timing segment rather
than warping sample indices. QPC/system correlation does not prove externally accurate
UTC: label this basis system_utc with external_accuracy_unknown. Internal numerical fixtures and
live spectrum/decoding work without UTC; correlated system time supports relative DT
under4.7.4 while external accuracy/transmit readiness are not inferred.

**Live lifecycle and results.** Explicit start selects spectrum-only/FT4/FT8 and owns
one continuous receive job until stop or failure. Incomplete initial waveform support
is not a decode. Analyze trailing up-to30 s windows every15 s for FT8 and trailing
up-to15 s windows every7.5 s for FT4, including initial shorter complete supports.
Reuse #7 kernels/records, preserving global canonical start_frame across known gaps.
No queued analysis windows: if processing misses the next boundary, report overrun and
the skipped interval, abandon obsolete work and use the latest supported window.
The reported last_overrun interval is the half-open support of the most recently
abandoned analysis window. It reports skipped analysis, not missing audio or fabricated
source gaps. Retain clearly partial verified results from that window.
No unbounded backlog or claimed complete history after loss. Retain at most2048 results
and2 MiB encoded content; live eviction advances first_sequence explicitly, with
cursor_expired instead of silently claiming reliable complete delivery. Finite numerical fixtures retain their test-context limits; production uses bounded live modem history. The spectrum uses existing fixed
0..3000 Hz wire products and rendering, independently of the decoder's200..3500 Hz search.

Audio states are closed/opening/running/closing/unavailable. Explicit stop invalidates
publication before acknowledgement, wakes capture waits and normally releases within
250 ms. A failed OS close stays closing/unavailable and retains ownership, rather than
claiming release. Device loss closes that input and reports its own error while CAT
and status remain usable. Automatic reopen attempts only the selected input with
1/2/4/8 s backoff capped at8 s, each with new identity/history; explicit stop cancels
reopen. Counter exhaustion or unsupported format fails until explicit correction.
Browser closure does not stop accepted capture. Restart does not automatically start
capture or CAT and creates a new boot identity.

**Radio catalogue and CI-V execution.** One immutable schema1 JSON catalogue records
revision, model/protocol IDs, units/domains, capabilities and source/licence provenance.
Initial bounds are256 KiB,32 models and128 command definitions; malformed schema,
duplicates or cross-references disable only CAT. Current compiled support is IC-7300;
Hamlib075b78cb0560e892c81bc73890d633cc11f23f59 supplies attributed factual cross-references,
and Icom manual A7292-4EX-12a supplies independently recorded wire facts. Preserve
source provenance; no upstream driver algorithms or wholesale catalogue are translated.
Catalogue intent, configured parameters, our verified operations and live observations
are separate. Only compiled typed operations can emit bytes.

| Operation | Request command/data | Completion |
|---|---|---|
| read_frequency |03|addressed03 +5 BCD bytes, least decimal pair first, integer Hz|
| read_mode |04|addressed04 +mode/filter|
| read_data |1A06|addressed1A06 +DATA/filter|
| read_rx_tx |1C00, no data|addressed1C00 +00RX/01TX; query only|
| read_split |0F, no data|addressed0F +00off/01on; query only|
| set_frequency |05 +5 BCD bytes|FB then independent03 exact readback|
| set_mode |06 +mode/filter|FB then independent04 exact readback|
| set_data |1A06 +DATA/filter|FB then independent1A06 exact readback|

Set mode accepts only USB01/LSB00 and FIL1..3. DATA OFF is00 00; DATA ON is01 plus
FIL1..3. Receive frequency is integer30000..74800000 Hz; e.g14074000 is00 40 07 14 00.
Read modes preserve unknown codes as unsupported observations, never substitute USB.
Frames are FE FE destination source command/data FD; FB is ACK and FA is NG. Echo,
foreign addresses and transceive broadcasts never complete a solicited request.
ACK alone is not confirmed state. Setters always read back; mismatch/failure reports
actual observations and indeterminate state without invented physical rollback.

One operation lease, no queue. Limits:32 bytes/frame,256 bytes/read chunk,
4096 bytes/64 frames per exchange,1 s absolute exchange deadline,5 s composite receive
setup deadline and at most50 ms I/O cancellation slices. Invalid/foreign traffic cannot
extend deadlines. A receive_setup workflow holds one lease for mode/DATA/frequency
changes and final readback; manual radio tuning can still intervene. Poll a complete
read cycle at most once/second and never while an explicit operation holds the lease.
No automatic retry of an issued query/setter exchange. The target automatic
connection lifecycle is exclusively CL-022-03/04: after confirmed failed-attempt
release it may start a new read-only connection attempt using the prescribed
1/2/4/8-second capped delays and grant/commissioning checks. Failed close retains
ownership and forbids timed reopen. Timeout/cancel/partial write closes the
connection generation before another owner; reconnect never replays a write. CI-V has
no transaction ID, so local generation tags cannot prove a late identical reply belongs
to a new request. Draining/closing and explicit state prevent stronger unsupported claims.

Connect with an explicit baud performs one1 s frequency probe. Auto holds one exclusive
handle and probes [9600,19200,4800,115200,57600,38400], one03 request/rate with500 ms
absolute response and100 ms bounded drain/quiet between attempts,5 s overall. Success
requires an addressed valid BCD frequency response; effective baud is an observation,
not a rewrite of intent. Addresses are never scanned. Use overlapped Win32 I/O,
CancelIoEx,8N1, no handshaking and disabled DTR/RTS; verify DCB/timeouts before ready.

CAT states are closed/connecting/ready/closing/unavailable, independent of audio.
Before physical opening, USB SEND/CW/RTTY keying must be independently confirmed OFF
or equivalent receive inhibit verified: post-open DCB settings cannot promise no initial
control-line glitch. Hardware acceptance reads original state, compares front-panel
indications, applies only reversible receive settings and restores them by readback.
No PTT setter, keying, tuner, VOX or split/TX setter is reachable in this slice; #9 owns
transmit authority and halt. Optional native FlexRadio remains the later #13 adapter.

#### Interface verification

| Test | Promises | Inputs/actions | Expected result/oracle | Level / where it runs |
|---|---|---|---|---|
| TC-002-001 — Canonical live audio | CL-008-01, CL-008-02, CL-008-03 | Inject independently timed mono/stereo native float/PCM packets, silence flags, arbitrary splits, exact queue limits/one-over, gaps, timestamp errors, missing devices and cancellation into actual capture/converter boundaries. Generate analytic tones/impulses and rational frame maps independently. | Channel0/normalization/finite-value rules, exact rational counts and block partition invariance within2e-5, group-delay alignment within one canonical frame, passband0.1dB/stopband60dB, bounded storage and no gap-crossing/fake silence. Canonical recordings unchanged. Cancel release<=250ms except explicit failed-close state; capture never invokes CAT. | 2 — Isolated automated tests; Windows development PC, actual candidate modules and independent device/clock fixtures. |
| TC-009-001 — Typed radio control | CL-008-01, CL-008-03, CL-008-04, CL-008-06 | Feed manually derived CI-V query/set/ACK/NG/readback bytes through fragmented, malformed, echoed, foreign, stale, flooded and boundary-sized transport fixtures. Test auto-baud order/deadlines, invalid catalogue/URI, physical alias conflicts and cancellation before/after send. | Exact bytes/readback semantics; no bytes for invalid/raw/TX requests; no deadline renewal/in-flight exchange retry/write replay; one owner/no queue; every cap and one-over; missing/busy/failed-close state truthful; two processes cannot own the same physical resource. | 2 — Isolated automated tests; Windows development PC, compiled control service and independent protocol/serial emulator. |
| TC-009-002 — Controlled IC-7300 receive station | CL-008-02, CL-008-04, CL-008-05 | On the designated Windows IC-7300 PC, verify receive inhibit/keying settings, selected USB input and COM3 identity; inspect readback against radio indications, capture known on-air/reference receive signals, restore original receive settings. Compare decoded payloads with simultaneous reference receive observations. | Correct physical input/port, no transmission, authoritative CAT observations, visible live spectrum/decodes and independent source timing/error records. Loss/reconnect and clock-quality labels agree with actual state. Reference counts alone are not exhaustive decoder truth. | 4 — Controlled live tests; HB9BLA radio PC and development browser, physical IC-7300, operator-authorized receive-only setup. |
| TC-002-003 — Audio without CAT | CL-008-02, CL-008-05 | Stream known packets with CAT disabled/unavailable and inject audio loss; exercise live spectrum and decoder fixture consumer. | Correct samples/spectrum/results without any CAT bytes; own errors/reopen/epochs visible; no default-device substitution or audio archiving. | 2 — Isolated automated tests; Windows PC, actual receive service and independent device/control fixtures. |
| TC-009-003 — Control without audio | CL-008-05, CL-008-06 | Exercise every supported query and receive setter while audio is closed/unavailable. | Exact control/status and capability failures without activating any audio endpoint; catalogue cannot enable raw/TX operations. | 2 — Isolated automated tests; Windows PC, actual Rust control module and serial emulator. |
| TC-009-004 — Independent failure and shared worker | CL-008-03, CL-008-05 | Lose either interface, overrun/stop/reopen capture, stall CAT and combine native48k conversion, display and bounded decoder quanta for four profiles; seed live result counters2047/2048/2049, eviction/cursor and safe-integer boundaries; simulate later TX/halt ownership. | Independent availability, no false ready state, no cross-profile samples/results, conversion service<=50ms quanta and native-to-canonical software backlog<=200ms under the declared workload, <=250ms normal cancel, <=2s status over the combined32kbit link; failed close retains ownership. No real RF transmission. | 2 — Isolated automated tests; Windows PC, actual services/browser/link model, independently scripted device/control and decoder-step fixtures. |


### 12.8. Live audio and CAT extension — target interface

These endpoints use the existing HTTP/TLS authentication, exact Origin checks, body
limit1024 bytes, JSON media rules and structured error envelope. Unknown/duplicate
keys, unsupported versions, invalid enums/ranges and stale identities fail before
device activity. Displaying or saving settings does not open a device. Responses are
literal data; clients never evaluate endpoint names, catalogue strings or radio text.

`GET /audio/devices` returns exactly `{v,profile_id,boot_id,devices}`; devices is at
most64 exact `{id,name}` objects, nonempty strings at most256 UTF-8 bytes, total encoded
response at most16384 bytes. A missing selected input remains visibly unavailable.
Enumeration overflow returns device_limit rather than silently dropping entries.

`GET /receive` returns exactly `{v,profile_id,boot_id,generation,audio,source,job,clock}`.
Audio is `{state,device_id,device_name,error,retry_after_ms}` with the4.5 states,
nullable strings and retry integer0..8000/null. Source is null or
`{id,kind,sample_rate,channels,next_frame,segment}`, kind live, rate12000,channels1,
UUID id and nonnegative safe counters. Job is null or
`{id,mode,state,error,processed_frames,first_sequence,next_sequence,available_count,last_overrun,latest_decode}` with UUID id,
mode spectrum/ft4/ft8, existing receive states and safe counters. available_count is
next_sequence-first_sequence (0..2048 retained records), not lifetime publication count.
last_overrun is null or the latest abandoned analysis half-open
`{first_frame,end_frame}`, safe counters and end<=capturednext; cleared on newcontext.
Clock is
`{basis,correlated,utc_anchor,canonical_anchor_frame,uncertainty_ns,external_accuracy}`:
basis system_utc, correlated boolean, UTC string/null, safe canonical frame/null,
nonnegative integer uncertainty/null and external_accuracy unknown. Snapshot<=8192 bytes.

latest_decode is null until an attempt publishes a view, otherwise exactly
`{id,first_sequence,next_sequence,period_start_utc,complete}`. id is a positive safe
integer increasing per publication within the source/job epoch. Sequence bounds are
nonnegative safe integers, first_sequence<=next_sequence<=the publication-end counter
frozen with this descriptor. Correlated period_start_utc is the selected mode's UTC
period start string; bounds enclose retained records matching that period, or both
equal the frozen publication end when empty. Uncorrelated period_start_utc is null and
bounds identify newly published records of that attempt. complete is boolean, true
only for a normally finished attempt. Snapshot/page read the descriptor atomically
with their own result counters. Known gaps clear it without reusing IDs; new jobs/source
epochs reset it and the ID. Retention/cursor expiry remains authoritative after eviction.

Live records extend12.7 with exactly period_start_utc and dt_seconds, both null without
station clock correlation. Otherwise period_start_utc identifies the nearest nominal
period and dt_seconds is finite in[-7.5,7.5) for FT8 or[-3.75,3.75) for FT4 under4.7.4.
The native numerical Decode shape is unchanged. These extra live fields remain inside
the2048-byte live record cap; existing1024-byte modem-history accounting is unchanged.

`POST /receive/start` requires exactly `{v,profile_id,boot_id,generation,profile_revision,mode}`;
mode spectrum/ft4/ft8. Admission uses the current immutable settings and existing single
receive owner; busy/import/replay/decode cannot start another capture. Success202 returns
the new snapshot. `POST /receive/stop` requires exactly
`{v,profile_id,boot_id,generation,job_id}` and returns202/current snapshot after publication
invalidation; terminal state follows actual release. IDs and generation are not caller
selected. Initialstart allocatesjob/gen and firstsourceACK reusesthatjob/gen. Subsequent
unknown epoch invalidates oldpublication/ring, allocatesfreshsource/job/gen beforeACK,
retainingcontinuousintent. Older stop/DELETE and callbacks cannot affect newcontext.
Knownmarkedgaps keepcontext/globalframes but resetanalysis/private modem state.

`GET /receive/results` requires source_id,job_id,generation,cursor and optional limit1..16
(default16) query keys; mode must be ft4/ft8. Exact page keys are
`{v,profile_id,boot_id,source_id,job_id,generation,mode,state,error,search_limited,first_sequence,next_sequence,available_count,next,more,records,latest_decode}`.
UUID identities, mode, state, error, search_limited and shared record
payload/field/text/SNR/frequency shapes follow12.7. Live counter/retained domains follow12.8.

For live pages, first_sequence and next_sequence are nonnegative safe integers up to
9007199254740991. first_sequence is the oldest retained sequence; next_sequence is
one past the lifetime latest publication. available_count=next_sequence-first_sequence
is retained count0..2048, also bounded by2 MiB encoded records. Eviction removes oldest
records and advances first_sequence; sequence never wraps or restarts within an epoch.
Live record sequence and start_frame are nonnegative safe integers; sequence is below
next_sequence and start_frame below the actually captured canonical next_frame, not a
finite source_frames value. Before incrementing any counter beyond the safe maximum,
fail counter_exhausted visibly and invalidate publication; never reuse an old sequence.

Pages contain at most16 records/16384 encoded bytes, at most2048 encoded bytes/record.
next is the first unreturned continuation cursor and more=(next<next_sequence), with
an immutable counter/window snapshot per response. Cursor=next_sequence returns an empty
page, next unchanged, more false. Cursor below first returns410 exactly
`{v:1,error:{code:"cursor_expired",message:"Result history expired"},first_sequence,next_sequence}`;
client visibly marks incomplete history before fetching the available oldest record.
Cursor above next_sequence is400. Replaced source/job is404, never a different stream.
For example first6/next2054/count2048 accepts cursor7,limit1 and returns record7,next8,
more true; cursor5 returns410 with first6/next2054. Tests cover sequence2047/2048/2049,
empty/one/full retained windows, byte-driven eviction and safe-counter exhaustion using
seeded state rather than waiting for a physical stream to reach the boundary.

A live job uses shared kind live; GET /recording retains the imported-file metadata
and reports that active live job without relabeling live samples as file data.
Admission for import/replay/decode still sees busy through the single receive owner.

Live spectrum reuses the exact12.6 frame messages and subscriptions, with the live
source/job identity; no native PCM crosses the browser link. For a live source the
receiver checks safe monotonically increasing canonical frame counters and nominal
row duration instead of a finite recording length. New receive.state identity/state
events cause snapshot refresh; their exact data is
`{profile_id,boot_id,generation,source_id,job_id,state}`, nullable IDs/state when idle.
They carry no samples or result records. Changing between live/file sources resets
browser history/readouts without changing the fixed0..3000 Hz axis or local sliders.

The combined Thin live mode emits at most one optional spectrum row/2 s; each browser
has one result request pending, requests limit1 and starts at most once/4 s, waiting
behind explicit status/control. Its result page is at most3072 encoded bytes.
Detailed remains an explicit fast-link option; Off disables optional spectrum only.
The two-browser32kbit/s acceptance accounts all headers/TLS/transport: <=3000 B/s mean
in each direction and <=2 s visible status response. Read requests may retry after
explicit stale/error handling; mutations are never automatically replayed.

`GET /radio` returns exactly
`{v,profile_id,boot_id,connection_generation,state,error,device_id,effective_baud,observation}`.
State/error use4.5; device_id is the stable physical identity/null; effective_baud is a
supported integer/null. Observation is null or exactly
`{frequency_hz,mode,filter,data,data_filter,split,rx_tx,observed_at_ms}`, each value nullable
until measured, time a nonnegative monotonic millisecond counter. Unknown received mode
is an uppercase two-hex-digit code, not a guessed supported mode. Closed/stale state
never presents its retained observation as current readiness. Snapshot<=2048 bytes.

Target issue22 deprecates manual CAT lifecycle operations. `POST /radio/connect`
retains exactly `{v,profile_id,boot_id,profile_revision,receive_only_verified}` and
`POST /radio/disconnect` retains exactly
`{v,profile_id,boot_id,connection_generation}` for strict validation/refusal only.
After unchanged authentication, exact Origin, schema, identity and size checks,
a valid request returns409 `automatic_lifecycle` in the existing error envelope,
with zero CAT open/query/close/setter/PTT I/O. Neither route succeeds200 or creates
a connection owner. Normal UI has no Connect/Disconnect CAT buttons. Only the
CL-022-03/04 automatic read-only lifecycle may open/retry under its matching durable
grant and receive-only commissioning; capability/PTT guards, physical inhibit,
resource ownership and acknowledged release remain mandatory.
`POST /radio/operation` adds exactly
operation and parameters to that disconnect identity envelope. Operations are the eight
4.5 names or receive_setup. Query parameters are `{}`; set_frequency uses `{frequency_hz}`;
set_mode `{mode,filter}`; set_data `{enabled,filter}`; receive_setup
`{frequency_hz,mode,filter,data,data_filter}` with the4.5 bounds. Only a successful
`/radio/operation` returns synchronous200, not either deprecated lifecycle route. It
returns `{v,profile_id,boot_id,connection_generation,operation,observation}` after readback.
Failure uses the existing error envelope; a request timeout cannot justify retrying a
setter. Connection generation is independent of receive generation, so audio lifecycle
changes do not invalidate an in-progress control operation. CAT never opens audio.


    */
    doc /* contract 4.7.5/12.8.1 coordinated operating selection is modeled by
         WstxOperatingReceive. This companion retains the unchanged legacy strict
         receive/radio/result shapes and owner/cancellation/source contracts, with
         only the explicit target manual-route refusal/retry amendment above.
         New selection uses the same authority, explicit actual release before
         setters/new capture and a fresh context, not a second pipeline or actor. */
}
