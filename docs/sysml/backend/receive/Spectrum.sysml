package WstxReceiveSpectrum {
    private import ScalarValues::*;
    private import WstxModeProcessing::ReceiveJob;
    private import WstxRecordingReceive::StartReplayBody;
    private import WstxAudio::SampleBlock;
    private import WstxDisplayData::DetailedSpectrumFrame;
    private import WstxDisplayData::SpectrumFrame;

    item def RecordedDetailedSpectrumFrame :> DetailedSpectrumFrame {
        assert constraint recordedSequence { sequence < 600 }
        doc /* Same wire shape. Finite recording-only bound; live uses safe common
             frame domain and actual capture counters, not this finite subtype. */
    }
    action def ReplaySpectrum {
        in request : StartReplayBody;
        out job : ReceiveJob;
        out frames : SpectrumFrame[*];
        out detailedFrames : RecordedDetailedSpectrumFrame[*];
        doc /* **Receive lifecycle.** One active import OR replay per station, one CPU worker,
             no pending job queue; concurrent start gets `busy`. State owner transitions and token
             checks serialize; CPU/file work does not hold the state owner or profile-settings lock.
             A replay job has schema 1, profile/boot/source/job UUIDs, station generation (`u64`,
             wire-safe 0..9,007,199,254,740,991), kind `spectrum`, immutable settings, processed frame
             count and cooperative cancellation. #7 adds a separately approved decode settings kind
             using the same receive lifecycle. States are `running`, `cancelling`, `completed`,
             `cancelled`, `failed`; terminal progress remains in the snapshot until another job starts.
             Starting an import or replay allocates a fresh station generation; starting replay also
             allocates a fresh job UUID. Cancellation invalidates publication before returning its
             acknowledgement; every receive terminal transition follows worker release. For a
             current running job with no accepted cancellation, a processing failure remains
             nonterminal while the worker is held, then transitions to failed after release;
             it cannot become completed even if source EOS/completion is also observed. Completion
             requires source completion, worker release and absence of processing failure. These
             rules preserve the existing serialized cancellation/state ownership, rather than adding
             another cancellation priority policy. Do not reuse a generation
             on wrap; refuse new work with `generation_exhausted`. Every publication matches current
             profile/boot/source/job/generation. A prior job's completion/frames cannot replace the
             current snapshot. Source UUID is the persistent recording UUID, not a replay identity.
             Receive cancellation does not govern transmit authority or delay #9 halt.

             Spectrum replay in #6 is explicit, server-paced at source time (1x) for inspection,
             not speaker playback and not a radio operation. This pacing applies only to spectrum
             jobs; #7 must settle its offline decode pacing/runtime and bounded modem working history
             independently, using the same immutable source/sample and receive job identities. Completion occurs within1s after the source duration on the stated Windows workload,
             including final processing. Another browser may observe/cancel the same station-owned job. Browser
             closure/link loss removes its subscription; it does not cancel an accepted replay.
             Cancellation checks are at most 50 ms apart and worker release/terminal state occurs
             within 250 ms after cancellation is accepted, measured on the recorded Windows test PC
             with four profile processes and one active worker each. No hardware/global CPU-count
             auto-allocation is introduced. The UI reports the one-worker-per-station budget. */
    }
    action def CalculateSpectrum {
        in samples : SampleBlock[*];
        out rows : SpectrumFrame[*];
        out detailedRows : DetailedSpectrumFrame[*];
        doc /* **Independent display definition (Thin, unchanged).** For 12 kHz input, use 2,048 real samples per
             window, hop 256 source frames, periodic Hann `w[n]=(1-cos(2*pi*n/2048))/2`; windows start
             at source frames 0,256,... while their start is before EOS. Right-pad the final partial
             windows with zeros, retaining actual source end in metadata. DFT convention is
             `X[k]=sum(x[n]*w[n]*exp(-i*2*pi*k*n/2048))`. Peak amplitude is `2*abs(X[k])/sum(w)` for
             positive interior bins and `abs(X[0])/sum(w)` for DC. Level is
             `20*log10(max(amplitude,10^(-120/20)))`, clipped to [-120,0] dBFS. This is calibrated
             peak-amplitude dBFS, not power density, SNR or receiver RF power. FFT output must agree
             with this independent definition regardless of the jointly selected provider. The joint
             technical selection is RustFFT **6.4.1** for both #6/#7: complex unnormalized
             forward negative-sign/inverse positive-sign transforms, DC-first ordering and caller-owned
             scaling. Use CPU `FftPlanner<f32>` for the normal path; retain an independently checked
             `FftPlannerScalar<f32>` portable path. A worker copies/window-converts source data into
             its own complex buffer, obtains `get_inplace_scratch_len()` for the plan and reuses
             worker-owned scratch with `process_with_scratch`; neither mutable buffer aliases the
             original immutable samples. #6 uses N=2048 for Thin and N=4096 for Detailed; #7 owns its supported transform sizes and
             bounded modem working history. Plan once per needed size/worker, never per display row;
             check lengths before processing so invalid input cannot reach a panic precondition.
             No generic FFT wrapper or additional RealFFT dependency is needed. This is the central
             owned dependency contract; the implementation declares RustFFT once in the server crate.
             The independent math/oracles remain this definition, rather than library output. Normative primary API: [RustFFT6.4.1 normalization/output order](https://docs.rs/rustfft/6.4.1/rustfft/),
             [`Fft` scratch/buffer contract](https://docs.rs/rustfft/6.4.1/rustfft/trait.Fft.html) and
             [`FftPlannerScalar`](https://docs.rs/rustfft/6.4.1/rustfft/struct.FftPlannerScalar.html).
             The explicit DFT formula above fixes sign/scaling independently of the provider.

             Expose 128 groups over [0,3000) Hz: group b is bins 4b..4b+3, each original bin separated
             by 12000/2048 Hz; group interval is [b*23.4375,(b+1)*23.4375) Hz. Retain maximum amplitude
             before converting to dBFS. One waterfall row covers each one-second source interval
             [j,j+1), shortened at EOS, taking maxima of windows whose start falls in that interval.
             Consequently window support can extend into the next interval; this smoothing is part
             of the time oracle. The spectrum is the same row's one-second peak hold. Quantize level
             as `floor(clipped_dBFS+120+0.5)` to integer 0..120; decoded level is q-120 dBFS with at
             most 0.5 dB quantization error. A 0.5-amplitude coherent tone has approximately -6.0206
             dBFS before PCM quantization, not a code-generated golden value. Silence is -120 dBFS.
             Label frequency in Hz, time relative to recording start in seconds and level in dBFS.
             Show gaps on skipped row sequences; never interpolate a missing row as observed signal.
             Browser retains at most 120 rows of 128 values; replacing the source/job clears history.

             **Detailed display definition.** Detailed is a fast-link profile with 1,024 native
             frequency bins, not a sharpened/resampled Thin image. For 12 kHz input use N=4096,
             hop480 (40ms), periodic Hann with denominator4096 and the same DFT sign, amplitude/DC rule,
             dBFS floor/clipping and integer quantization as Thin with N substituted throughout.
             Expose k=0..1023 at center frequency k*2.9296875 Hz, covering [0,3000) Hz without
             frequency pooling. The displayed bin's frequency cell is [k*2.9296875,(k+1)*2.9296875)
             Hz; this is display geometry, not a claim that the Hann response has rectangular support.
             A row j covers source frames [2400*j,min(2400*(j+1),source_frames)); use global
             window starts0,480,... strictly before EOS. Every nonempty row includes its start2400*j,
             so a full row has exactly five windows and a partial final row has one through five.
             For each bin k, let A[m,k] be each window's calibrated peak-amplitude estimate above;
             compute P[k]=sum(A[m,k]^2)/M over the M actual window starts in this row, then
             L[k]=clamp(10*log10(max(P[k],1e-12)),-120,0) and q=floor(L[k]+120+0.5).
             There is no frequency pooling, logarithmic averaging or maximum hold in Detailed.
             For source_frames2401, row1=[2400,2401) includes only start2400: the lone sample
             multiplies Hann w[0]=0 and the row is legitimately silence, not missing/fabricated data.
             Right-pad partial windows at EOS; window support is 4096/12000 seconds, can cross row
             boundaries and MUST be stated in the legend alongside 2.9296875 Hz bins and 0.2 s rows.
             The spectrum shows the latest row's levels. Row sequence starts0 and advances even
             when output is skipped; send at most5 rows/s/peer, paced against the source clock.
             Thin continues its exact N2048/four-bin/one-second definition and event schema.

             One replay/source reader and one existing station-owned worker produce both profiles
             concurrently; selecting Detailed never starts another job or reparses/reloads the file.
             Reuse RustFFT6.4.1 with one plan/buffer/scratch per needed size, the existing sample
             parser/immutable boundary, identities and cancellation checks. Keep at most two source
             blocks plus at most8192 f32 samples in a common bounded history, the two bounded FFT
             workspaces (2048 and4096 complex elements plus their plan-reported scratch), per-profile
             row accumulators (128 maxima for Thin,1024 power sums and a window count for Detailed) and one latest immutable frame per profile in station state. No
             subscriber-specific FFT or unbounded queue. Process the two independent start schedules
             against this same forward-only SourceFile reader. Release common history before the
             minimum next needed start; read only when space remains and retain lookahead only for
             those windows. Pad outside EOS without increasing actual source positions/progress;
             no second source file/parser, whole-recording float array or additional sample backlog. Starting/replacing/cancelling clears both
             latest frames; publication checks the existing complete current job tuple. Browser keeps
             at most600 Detailed rows (120s, 614400 level bytes), or120 Thin rows (15360 level bytes),
             including explicit gap slots, and one pending repaint. These are application retention
             bounds, not total RSS promises.

             **Crisp canvas geometry.** Render every frequency/time cell using integer device-pixel
             edges with a DPR-sized backing bitmap, image smoothing disabled and pixelated CSS image
             rendering; no blur/filter or interpolation of measured values. The whole fixed[0,3000)Hz span always fits the plot width; frequency mapping is f/3000*W,
             0Hz at left and3000Hz at right. Resize/DPR/zoom changes geometry only, not frequency
             span, FFT dimensions or native data. No horizontal frequency scrolling or minimum1024
             pixel canvas width. Let B be1024 Detailed or128 Thin and W the integer backing width.
             When W>=B, bin k spans[floor(k*W/B),floor((k+1)*W/B)) device pixels. When W<B,
             assign every native bin k to column floor(k*W/B); that column displays the maximum
             original q of its assigned bins, exactly once each, with no interpolation, frequency
             resampling of the retained array or skipped zero-width cells. This display-only maximum
             projection preserves narrow strong signals; it cannot show1024 separate bins in fewer
             than1024 physical columns. The complete original native array remains unchanged.
             Readout names the projected column's native-bin range and its maximum, and separately
             identifies the nearest native bin to the pointer frequency (clamped, ties upward) or the
             exact keyboard-selected bin. Native keyboard stepping never edits/aggregates the data.
             Axis labels/controls stay reachable with no horizontal page or frequency plot overflow.
             A pointer/focusable readout exposes selected
             native bin index, center Hz, original q-120 dBFS and row source interval; keyboard Left/Right moves one
             bin and Up/Down one retained row, clamped to available data. Gaps report no measurement.

             **Waterfall space and Speed.** The canvas fills its entire allotted box. New
             observed rows enter at the top and advance older rows downward at a fixed source-time
             scale; accumulated history is never stretched to fill the canvas. The Speed slider is
             v=0.5..8 in0.5 steps, default2, with numeric output 10*v CSS pixels per source second and
             Slow/Fast ends. Set p=10*v CSSpx/s. Detailed advances 2*v CSSpx per full0.2s row;
             Thin advances10*v CSSpx per full1s row. This changes only local presentation, never
             source replay, decoder, network cadence, sample clock or retained values.
             Round finite speed input to the nearest half-step with floor(2*value+0.5)/2,
             then clamp to[0.5,8]; nonfinite/unparseable input leaves speed unchanged.

             Let C be the actual CSS waterfall height, H=round(C*DPR) its backing height (minimum1),
             and T the newest accepted row's end_frame/12000. A row with source interval[a,b)
             occupies downward integer device-pixel edges
             [floor((T-b)*p*H/C),floor((T-a)*p*H/C)), clipped to[0,H).
             Thus the latest row starts at0; each new accepted source interval shifts existing
             history by its source-time duration times p, independent of retained row count N.
             Older rows leave through the bottom without sticking, stretching, wrapping or repeating.
             A shortened final row uses its actual interval. Paint absent/unobserved history dark
             RGB(0,0,12), including the part below a short recording; it is not a measurement.
             Explicit missing sequence slots remain grey RGB(96,96,96), never noise or repeated data.
             Zero-height rows, if any after integer rounding, contribute to pixel floor((T-b)*p*H/C).
             When several rows contribute to one pixel, use their per-bin maximum and mark the group
             unknown grey if any contributor is a gap. Native arrays remain unchanged.

             The visible source-time capacity is C/p seconds, independent of N. Display this
             capacity and the actual observed source interval separately. Retain the existing
             bounded history so reducing speed can expose earlier observations; never fabricate
             measurements for time outside retained observations. Time advances only on accepted
             source rows. Completed, cancelled, disconnected or stalled input freezes its last
             history; resizing or local controls may repaint but do not advance time. Replay is
             explicit and resets its job/history normally, without automatic looping.

             Pointer selection uses the exact source intervals contributing to its integer pixel.
             For measured pixels, choose the newest contributing native row as initial selection;
             Up/Down steps one visible native row, clamped. The readout separates the selected
             native bin/row value and interval from the projected native-bin/time ranges and maximum.
             For a gap, report unknown; for an unobserved pixel, report no measurement, without
             clamping it to the oldest measured row. Left/Right still steps native frequency bins.
             Speed or geometry changes recompute visible rows/readouts without mutating native data.

                          Keep spectrum above the fixed0..3000Hz ruler and waterfall. #54: the spectrum line is shown
             only with the per-browser option Show spectrum line (default off); hidden, the waterfall
             takes its height. Shown, its vertical scale is [E,0] dBFS, so no level clips at the top.
             The default signal height is 330 CSS px (splitter), at most 560. Allocate the remaining plot
             budget after headings/rulers/legend approximately1:5 to spectrum:waterfall, using explicit
             zero flex bases and min-height0 so intrinsic canvas bitmap heights cannot feed back into
             layout. Each backing bitmap is round(its actual CSS box * DPR), minimum1, and each
             canvas fills its allotted box exactly after drag, resize and zoom. Plot areas therefore
             use approximately17%/83% of their combined height, subject only to integer rounding.
             Headers, rulers and controls remain reachable at the existing pane minima and360px.
             No horizontal page/frequency scrolling or changed frequency span.

             Frequency ruler retains major500Hz/minor100Hz ticks with positions f/3000*W. Time ruler
             labels T at the top and source time t every5s within the viewport,
             at y=floor((T-t)*p*H/C)/DPR, omitting negative source times and colliding labels less
             than16CSSpx apart. The time scale and native/projected readouts use this same mapping;
             labels do not imply observations in unmeasured areas. Label elapsed source seconds, never synthetic UTC/RF frequency/dBm.
             A run of Tx rows (#61 CL-061-05) takes one band of 4 CSSpx instead of its source time; every other row keeps p, and the mapping and labels of times beyond the band stay exact: T-t counts without the run's source time, plus the band.
             Profile changes still clear browser history/old-profile frames; existing bounded history,
             source identities and one pending repaint remain unchanged.

             **Display levels and palette.** The display is a local presentation of calibrated
             levels, independent of source samples, FFT/averaging, wire quantization, Thin bandwidth
             and future decoding (#54, CL-054-02). The waterfall corner holds labelled keyboard-operable
             Sensitivity (WSJT-X Zero), Range (WSJT-X Gain) and Speed range sliders, each with an
             adjacent numeric output, repainting on every input event; Settings > General > Display
             holds Flatten and Show spectrum line. DisplayLevels gives the values and the fixed
             mapping: there is no Black level input, no Auto black and no noise estimate, and a new
             source, job or display profile changes no level. Sensitivity and Range change
             waterfall colours only; the legend shows both effective ends in dBFS. Inputs are rounded
             with floor(value+0.5) and clamped; nonfinite values leave settings unchanged. Clipping
             affects presentation only; the native values remain available. Repaint all retained
             rows when presentation controls change; samples/wire data never change or restart.

             For an original quantized level q, t=clamp(((q-120)-E)/R,0,1). Map t to this project's
             own RGB anchors, interpolating each channel linearly between adjacent anchors and
             rounding with floor(channel+0.5): t=0:(0,0,12), .15:(0,0,80), .35:(0,80,220),
             .50:(0,220,240), .65:(30,230,80), .80:(255,235,0), .95:(255,40,0),1:(255,0,0).
             Saturated/above-range signal is exactly RGB(255,0,0), never white. Below-floor/no-signal
             is RGB(0,0,12); gaps are RGB(96,96,96) and appear only for a real gap (#54: rows the station did not send within its retained window, a source or job change, an unknown-loss source epoch of the same receive as one row between the kept rows (CL-061-01); one or two live Thin rows paced out between two sent rows are drawn with the next row, not as a gap; live Thin sends keep a fixed 2 s grid from the previous deadline, restarted at a send more than 1 s late, so sends stay at least 1 s apart). This continuous level-to-color
             mapping does not interpolate spatial bins/rows: each rendered cell has one exact RGB
             color, fully opaque. Spectrum trace is RGB(180,245,220). Ruler/grid/text overlays stay
             outside waterfall measured cell interiors. A narrow labeled color legend uses these exact same anchors, positions and linear RGB
             channel interpolation/rounding, ending in the same saturated red; it displays the
             effective waterfall range. Rainbow hue progression does not assert monotonic luminance. Flatten is the optional per-row passband equalisation of DisplayLevels; no palette editor, gain normalization over time or new framework.

             Conventional presentation references, consulted2026-10-25: [WSJT-X User Guide9.2/14.7](https://wsjt.sourceforge.io/wsjtx-main_en.html#_wide_graph) describes spectral averaging,
             bin visibility and display level controls; [FlexRadio SmartSDR User Guide, Waterfall](https://edge.flexradio.com/www/offload/20260423063240/SmartSDR-Software-User-Guide.pdf)
             describes noise-floor black level and display range. These inform the operator's visual
             expectation, not numerical conformance or copied assets/code. The exact formulas,
             geometry and original palette above are authoritative for this implementation. A real
             busy FT8 recording MUST show multiple recognizable narrow time-varying transmissions
             against a dark noise floor with distinguishable brighter signals, reviewed at desktop
             and360px alongside these reference images; analytical tones alone do not meet visual
             acceptance. Readout remains calibrated dBFS rather than implying receiver RF power. */
    }
    action replaySpectrum : ReplaySpectrum;
    action spectrum : CalculateSpectrum;
    satisfy WstxRecordingReceive::'CL-006-02' by replaySpectrum;
    satisfy WstxRecordingReceive::'CL-006-03' by spectrum;
    dependency receiveOwner from replaySpectrum to WstxArchitecture::physicalStation::backend::stations::receive;
    dependency spectrumOwner from spectrum to WstxArchitecture::physicalStation::backend::stations::receive;
}
