// Canonical offline decode contract SHA256: ecc962d32c84b04eb40f4792d803afa6f86bd8b3ab73e8bd33faa53f9459a913
// Fingerprint covers canonical FSD; behavior slice4.4/6.4/12.7.
package WstxOfflineDecode {
    private import ScalarValues::*;
    doc /* Target implementation contract, NOT implemented decoder behavior or test results.
         Authority: docs/WSTX Rust FSD.md 4.4 CR7, 6.4 TC-004-001/002/003, 12.7.
         Protocol: https://wsjt.sourceforge.io/FT4_FT8_QEX.pdf sections2-5/AppendixA;
         current source boundaries and fixed vectors use the pinned beta4 reference manifest.
         No upstream decoder implementation is translated. Independent meaning/readiness
         review is required before production code; semantic parsing is not that review.
         Existing physical station/receive/modem/web/browser usages remain owners. */

    enum def Mode { enum ft4; enum ft8; }
    enum def FrameStatus { enum decoded; enum unsupported; enum invalid_payload; }
    enum def CallKind { enum call; enum token; enum hash; }
    enum def ExchangeKind { enum blank; enum grid; enum report; enum roger; }
    attribute def Limits {
        attribute rateHz : Integer = 12000;
        attribute historyFrames : Integer = 360000;
        attribute sourceBlocks : Integer = 2;
        attribute windowFrames : Integer = 360000;
        attribute advanceFrames : Integer = 180000;
        attribute workerBytes : Integer = 67108864;
        attribute processDeltaBytes : Integer = 100663296;
        attribute workersPerStation : Integer = 1;
        attribute pendingJobs : Integer = 0;
        attribute records : Integer = 2048;
        attribute encodedRecordStoreBytes : Integer = 2097152;
        attribute recordBytes : Integer = 1024;
        attribute pageBytes : Integer = 1536;
        attribute pageRecords : Integer = 1;
        attribute pollMs : Integer = 2000;
        attribute quantumMs : Integer = 50;
        attribute cancelReleaseMs : Integer = 250;
        attribute statusDisplayMs : Integer = 2000;
        attribute candidateCap : Integer = 256;
        attribute rawMaximumBound : Integer = 661758;
        attribute complexTransformBound : Integer = 838992;
        attribute phaseTimePoints : Integer = 5;
        attribute phaseFrequencyPoints : Integer = 9;
        attribute minBlockPhaseFraction : Real = 0.5;
        attribute ft4NeighborPairs : Integer = 16;
        attribute ft4LocalTemplates : Integer = 64;
        attribute recoveryInformationRank : Integer = 77;
        attribute fecIterations : Integer = 50;
        attribute recoveryTrials : Integer = 137;
        attribute subtractionPasses : Integer = 3;
        attribute subtractions : Integer = 32;
        attribute neighborRefinements : Integer = 2;
        attribute minFrequencyHz : Real = 200.0;
        attribute maxFrequencyHz : Real = 3500.0;
        attribute costasThreshold : Real = 2.7;
        attribute minMeanAbsLlr : Real = 1.0;
        attribute minCodewordPhaseFraction : Real = 0.5;
        attribute maxHardDisagreements : Integer = 24;
        attribute minSumAlpha : Real = 0.8;
        attribute llrBound : Real = 12.0;
    }
    attribute def ModeParameters {
        attribute mode : Mode;
        attribute symbolFrames : Integer;
        attribute hopFrames : Integer;
        attribute symbolCount : Integer;
        attribute syncCount : Integer;
        attribute gaussianBT : Integer;
        attribute timeToleranceFrames : Integer;
        attribute frequencyToleranceHz : Real;
        assert constraint exactParameters {
            (mode == Mode::ft8 and symbolFrames == 1920 and hopFrames == 480 and
             symbolCount == 79 and syncCount == 21 and gaussianBT == 2 and
             timeToleranceFrames == 240 and frequencyToleranceHz == 1.0) or
            (mode == Mode::ft4 and symbolFrames == 576 and hopFrames == 144 and
             symbolCount == 105 and syncCount == 16 and gaussianBT == 1 and
             timeToleranceFrames == 144 and frequencyToleranceHz == 3.0)
        }
    }
    attribute def Settings { attribute mode : Mode; }
    item def DecodeJob :> WstxRecordingReceive::ReceiveJob {
        attribute :>> kind = WstxRecordingReceive::ReceiveKind::decode;
        attribute settings : Settings;
        attribute available_count : Integer;
        attribute search_limited : Boolean;
        assert constraint boundedProgress {
            processed_frames >= 0 and processed_frames <= 1440000 and
            available_count >= 0 and available_count <= 2048
        }
        doc /* Existing station receive-job authority, kind=decode target extension.
             One import OR spectrum replay OR decode, immutable mode, fresh job/generation,
             no queue; error is null or stable recording/job code, never exception text.
             Fast offline advancement, no source pacing or automatic replay. */
    }
    attribute def CallValue {
        attribute kind : CallKind;
        attribute text : String[0..1];
        attribute hash_bits : Integer[0..1];
        attribute hash_value : Integer[0..1];
        doc /* Exact wire keys. call/token have text and null hash fields; hash has null
             text, width10/12/22 and unsigned value below2^width. Display hash as<...>.
             No inverse guessing/configured call/cache across profile/source/job. */
    }
    attribute def StandardExchange {
        attribute kind : ExchangeKind;
        attribute textValue : String[0..1];
        attribute numericValue : Integer[0..1];
        doc /* Semantic union, wire exactly{kind,value}: blank=>null, grid=>grid4,
             report=>integer-50..50, roger=>RRR/RR73/73. Internal semantic arm names
             are not extra wire fields; FSD12.7 exact JSON mapping is normative. */
    }
    attribute def PayloadFields;
    attribute def FreeTextFields :> PayloadFields {
        attribute 'type' : String = "free_text";
        attribute value : String;
        doc /* type=free_text; 1..13 base42 chars, nonblank, trim trailing padding only. */
    }
    attribute def TelemetryFields :> PayloadFields {
        attribute 'type' : String = "telemetry";
        attribute value : String;
        doc /* type=telemetry; exact18uppercasehex, leading0..7, zero allowed. */
    }
    attribute def StandardFields :> PayloadFields {
        attribute 'type' : String = "standard";
        attribute 'to' : CallValue;
        attribute 'from' : CallValue;
        attribute ack : Boolean;
        attribute exchange : StandardExchange;
        doc /* type=standard; i3=1/R or2/P. Exact c28/grid/report canonical maps in4.4;
             codes32400 and>32505 invalid, not fallback text. */
    }
    attribute def RttyFields :> PayloadFields {
        attribute 'type' : String = "rtty";
        attribute tu : Boolean;
        attribute 'to' : CallValue;
        attribute 'from' : CallValue;
        attribute ack : Boolean;
        attribute report : Integer;
        attribute exchangeKind : String;
        attribute serial : Integer[0..1];
        attribute stateToken : String[0..1];
        doc /* type=rtty; exact wire exchange{kind,value} chooses serial0..7999 or
             states8001..8065, reserved8000 invalid. report529..599 step10. Semantic
             union arm names are not extra JSON fields. */
    }
    attribute def DxpeditionFields :> PayloadFields {
        attribute 'type' : String = "dxpedition";
        attribute 'first' : CallValue;
        attribute 'second' : CallValue;
        attribute hashed : CallValue;
        attribute report : Integer;
        doc /* type=dxpedition,0.1; h10 exact, even report-30..32; firstRR73;secondhashreport. */
    }
    attribute def FieldDayFields :> PayloadFields {
        attribute 'type' : String = "field_day";
        attribute 'to' : CallValue;
        attribute 'from' : CallValue;
        attribute ack : Boolean;
        attribute transmitters : Integer;
        attribute 'class' : String;
        attribute section : String;
        doc /* type=field_day,0.3=>1..16,0.4=>17..32; classA..F, section1..84 inclusiveDX.
             S7=75WCF,76WI,0/>84 invalid; current83-line external file omitsDX. */
    }
    attribute def NonstandardFields :> PayloadFields {
        attribute 'type' : String = "nonstandard";
        attribute full_call : CallValue;
        attribute hashed_call : CallValue;
        attribute hash_second : Boolean;
        attribute cq : Boolean;
        attribute roger : String[0..1];
        doc /* type=nonstandard,i3=4; full call<=11base38 chars, h12 exact; r2blank/RRR/RR73/73.
             CQ ignores hash for display, preserves typed bits; empty/out-of-domain call invalid. */
    }
    attribute def VhfFields :> PayloadFields {
        attribute 'type' : String = "vhf";
        attribute 'to' : CallValue;
        attribute 'from' : CallValue;
        attribute ack : Boolean;
        attribute report : Integer;
        attribute serial : Integer;
        attribute grid : String;
        doc /* type=vhf,currenti3=5; hash12to/hash22from, report52..59, serial0..2047,
             mixed18,18,10,10,24,24 grid0..18662399=>AA00AA..RR99XX. */
    }
    item def ResultRecord :> WstxArchitecture::ProcessingResult {
        attribute sequence : Integer;
        attribute status : FrameStatus;
        attribute payload77 : String;
        attribute i3 : Integer;
        attribute n3 : Integer[0..1];
        attribute text : String[0..1];
        attribute fields : PayloadFields[0..1];
        attribute start_frame : Integer;
        attribute frequency_hz : Real;
        attribute snr_db : Real[0..1];
        assert constraint boundedRecord {
            sequence >= 0 and sequence < 2048 and i3 >= 0 and i3 <= 7 and
            start_frame >= 0 and start_frame < 1440000 and
            frequency_hz >= 200.0 and frequency_hz <= 3500.0
        }
        doc /* Exact wire keys,<=1024UTF8bytes. payload77 exactly77binarychars; n3 only
             ifi3=0; text<=80ASCII and matching fields only when decoded, otherwise null.
             Supported0.0/.1/.3/.4/.5,1/2/3/4/5;0.2/.6/.7,6/7 unsupported. BadCRC never
             published. start indexes canonical12k first ramp/sync, never native orUTC.
             SNR null orfinite[-60,60], bounds labeled; full identity is page envelope. */
    }
    item def DecoderSnapshot {
        attribute v : Integer = 1;
        attribute profile_id : String;
        attribute boot_id : String;
        attribute generation : Integer;
        attribute modes : Mode[2];
        item job : DecodeJob[0..1];
        doc /* Exact FSD12.7 snapshot<=1536bytes; modes[ft4,ft8], job wire projection
             id/source_id/generation/mode/state/processed_frames/available_count/error/
             search_limited only; current nondecodejob=>null, no wholesale serialization. */
    }
    item def ResultPage {
        attribute v : Integer = 1;
        attribute correlation : WstxRecordingReceive::Correlation;
        attribute mode : Mode;
        attribute 'state' : WstxRecordingReceive::ReceiveState;
        attribute error : WstxRecordingReceive::ErrorCode[0..1];
        attribute search_limited : Boolean;
        attribute available_count : Integer;
        attribute 'next' : Integer;
        attribute more : Boolean;
        item records : ResultRecord[0..1];
        assert constraint pageCursor { 'next' >= 0 and 'next' <= available_count and available_count <= 2048 }
        doc /* Wire correlation flattened to profile_id/boot_id/source_id/job_id/generation;
             exact other keys above. Body<=1536bytes,one<=1024byterecord, latestjobonly.
             afterN canonicalnonnegative decimal,default0,duplicate/unknown/>count400.
             Stable append cursor; emptyrunning distinct fromemptyterminal. */
    }
    calc def CostasRatio {
        in tones : Integer;
        in expectedPower : Real;
        in otherPower : Real;
        return ratio : Real = (tones - 1) * expectedPower / otherPower;
        doc /* Call onlywhenotherPower>0; bothzero rejects, positive/zero outranksfinite.
             Require>=2.7; zero-basedFT8sync0..6/36..42/72..78,FT4sync1..4/34..37/67..70/100..103.
             Localmaxhalf-symbol/half-tone, ties scoredesc/freqasc/timeasc. */
    }
    attribute def ComplexCoefficient {
        attribute re : Real;
        attribute im : Real;
        doc /* Runtime complex-f32, eight bytes, shared Fourier convention. */
    }
    item def SymbolTransformGrid {
        attribute coefficients : ComplexCoefficient[0..838992];
        doc /* Same1920/576 transforms and two shifted frequency grids retain complex values.
             Complete30swindow:747*1080FT8 or2497*336FT4 coefficients. Raw start/frequency
             grid <=435*1057FT8 or2081*318FT4=661758. Priority heap and suppression bitmap,
             checkpoint visits; no quadratic all-pairs suppression. All storage inside64MiB. */
    }
    calc def SyncBlockCoherence {
        in matchedMagnitudeSquared : Real;
        in observedEnergy : Real;
        in templateEnergy : Real;
        return fraction : Real = matchedMagnitudeSquared / (observedEnergy * templateEnergy);
        doc /* Positive denominators only, otherwise reject grid point. Five coefficient tables:
             Hj(dt)=sum_m h(jN+m-dt)*exp(-i2pi*tj*m/N), m0..N-1, outsideh=0.
             h is unit analytic sync-only GFSK, actual envelope, zero data/ramp tones.
             Zj is coarse coefficient at expected tone. matchedMagnitudeSquared equals
             abs(sum_j Zj*conj(Hj)*exp(-i2pi*(fbase+df)*jN/12000))^2 within ONE Costas block.
             observedEnergy=sumabsZj^2; templateEnergy=sumabsHj^2. EVERY repeated block
             needsfraction>=.5 at SAME complete/in-band5time*9frequency point. Block phase
             independent; no whole-frame phase lock or absolute/relative amplitude floor. */
    }
    attribute def ToneLikelihoodContext {
        attribute toneCount : Integer;
        attribute noiseVariance : Real;
        attribute targetEnergy : Real;
        attribute nuisanceEnergy : Real;
        attribute nuisanceOffset : Integer;
        attribute peerPresent : Boolean;
        assert constraint boundedVariance {
            (toneCount == 4 or toneCount == 8) and noiseVariance >= 0.00000000000000000001 and
            targetEnergy >= 0.0 and nuisanceEnergy >= 0.0
        }
        doc /* E=abs(local analytic quadrature z)^2/N; v=PSD*12000/2, floor1e-20.
             SignalS=N*(a^2+b^2)/4 from independent block-interior2x2Costas fits, trimN/2ends;
             subtractNv/blockFrames noise bias, clampnonnegative, median across3/4blocks.
             One strongest distinct phase-qualified overlapping peer, startdelta<=N/2,
             basefrequencydelta>=.75spacing, I>=v and I>=S/16, finite estimates only.
             d=floor((fpeer-fbase)/spacing+.5). Selection<=256^2 candidate comparisons. */
    }
    calc def MarginalToneLikelihood {
        in context : ToneLikelihoodContext;
        in energies : Real[4..8];
        in targetTone : Integer;
        return logLikelihood : Real;
        doc /* No peer:Et/v. Peer:j0..Q-1 mapsu=d+j, weight1/Q; out-of-band u addsno nuisance.
             V(k,t,u)=v+S*[k=t]+I*[k=u]. Returnlogsumexp_u(-sum_k(logV+Ek/V))-logQ.
             Subtract common terms BEFORE logsumexp, retaining finite low-noise differences.
             One peer only, <=Q^2 components/fixed-neighbor symbol, nosemantic/AP prior. */
    }
    calc def Ft4NeighborMarginalization {
        in context : ToneLikelihoodContext;
        in leftLogPrior : Real[4];
        in rightLogPrior : Real[4];
        return toneScores : Real[4];
        doc /* Enumerate4left*4target*4right local templates (64*576complex-f64=589824bytes).
             More distant neighbors fixed hard. For each target,logsumexp16pair likelihoods
             plusleft/right logpriors. Initial data uniform, knownsync/ramp delta priors.
             Atmosttwoobservationrefinements; finalFT4nopeer round usesFt4PairSequence
             instead of anotherlocalmarginal. Withpeer retainlocalmarginal. GraybitL clipped+-12,logP=-sumlog(1+exp(-sign(bit)*L)),
             sign0=+1/sign1=-1; normalize across4tones. FT8 hard-neighbor templates/two
             posterior refinements. No additional source, thread, encoder or AP hint. */
    }
    calc def Ft4PairMetric {
        in samples : Real[1152];
        in localTones : Integer[4];
        in baseFrequencyHz : Real;
        in noiseVariance : Real;
        return logFactor : Real;
        doc /* N576,256cachedcomplex-f64templates oflength2N;4,718,592bytes.
             L,T,U,R atrelative symbols-1,0,1,2. SharedreconstructionunitGaussianpulseBT1:
             p(t)=(erf(c*(t+.5))-erf(c*(t-.5)))/2,c=pi*sqrt(2/ln2).
             psi_a(k)=(2pi/N)*sum_m0..k p((m+.5)/N-a-.5),a=-1..2,k0..2N-1.
             h=exp(i*(Lpsi_-1+Tpsi_0+Upsi_1+Rpsi_2));otherslocaltoneszero.
             Eachpairindependentcomplexgain absorbsconstantprefixphase.
             Requirecomplete60480-frame supportin currentResidual atcandidateStart.
             x[j]=currentResidual[candidateStart+j],j0..60479.
             Bindthismetric'ssamples[k]=x[2gN+k],k0..1151.
             z=sum_k samples[k]*conj(h)*exp(-i2pi*f*k/12000), F=abs(z)^2/(2N*v).
             Sameanalytic-quadraturelikelihoodconventionaslocalpower; variancefloor1e-20.
             Index((L*4+T)*4+U)*4+R; subtractcommonmaxoverall256factors/pair. */
    }
    calc def Ft4PairSequence {
        in factorGroups : Integer;
        in pairFactors : Real[256..13312];
        in allowedTones : Boolean[12..420];
        return toneLogMarginals : Real[12..420];
        doc /* Purebounded16stateforward/backward. PhysicalFT4G52coverssymbols0..103;
             PairmetricsconsumeanchoredcurrentResidual[candidateStart..candidateStart+60480],
             each1152-sampleinput boundatcandidateStart+2gN asdefinedbyFt4PairMetric;
             exteriorz[-1]=0,finalramptonez[104]=0. GenericmathG1..52, exact2G+1masks,
             eachnonempty; finalmask[true,false,false,false]. Allfactorsfinite, exactG*256.
             Sync/ramp knownphysicaltonemasks; datauniform,noFECposterior/AP/messageprior.
             Firstpairramp'sfourtonesfixedbysync/ramp, so itsweightiscommonpathconstant.
             state(L,T)=4L+T. alpha0(L,T)=0ifL0elsenegInfinity.
             alpha_(g+1)(U,R)=LSE_(L,T)(alpha_g(L,T)+F_g(L,T,U,R)).
             betaG(U,R)=0ifR0elsenegInfinity;
             beta_g(L,T)=LSE_(U,R)(F_g(L,T,U,R)+beta_(g+1)(U,R)).
             OmittransitionsifT@2g/U@2g+1violatemasks,normalizefinitealphabeta rowsbymax.
             Transitionmass=alpha+F+beta; LSEoverLURgivesT,andLTRgivesU; normalizetones.
             Finalboundarylogmarginal[0,negInfinity,negInfinity,negInfinity].
             GrayLSE/clamp+-12 yields174channelLLRs forEXISTINGfinalFEC/OSDround.
             FinalFT4nopeeronly, replaceslastlocalround; earlyH+CRC/channelgatesmayfinish.
             Noadditionalround/candidate/source/worker, nouniversalphasebetweenseparatepairs.
             Invaliddimensions/nonfinitearithmetic/nofinitepathrejectobservation.
             <=52*256*1152=15335424complexsampleproducts,52*256factors,two53*16statearrays.
             Templates/factors/statesinsideexisting64MiB; checkpointsbeforeeachpairbank
             andbefore/afterboundedtrellis. */
    }
    action def QualifySynchronization {
        in grid : SymbolTransformGrid;
        out qualifiedCount : Integer;
        out searchLimited : Boolean;
        assert constraint boundedQualified { qualifiedCount >= 0 and qualifiedCount <= 256 }
        doc /* Costas>=2.7 first; local suppressionhalfsymbol ANDhalftone, scoredesc/freq/time.
             Per rawmax:<=5*9*Kexisting-coefficient products, NOT5*9*K*Nsample correlations.
             Requirephasefraction>=.5 in EVERY block atonepoint. A257thqualified candidate
             setssearchLimited. Fine sample Costas only at<=45phase-valid points/admitted
             candidate, tiesfrequency/time. No unbounded optimizer or amplitude earlystop. */
    }
    calc def EncodedGroupPhaseAgreement {
        in currentPassSamples : Real[0..360000];
        in refinedStartFrame : Integer;
        in mode : Mode;
        in groupExplainedEnergy : Real;
        in symbolExplainedEnergy : Real;
        return fraction : Real = groupExplainedEnergy / symbolExplainedEnergy;
        doc /* After bounded known-codeword time/frequency refinement and before publication
             OR subtraction, full unit real/sine GFSK u,w include the envelope.
             x is complete support atrefinedStartFrame in currentPassSamples: the SAME
             current subtraction-pass observation/residual that producedthecandidate.
             All79FT8/105FT4symbols INCLUDINGsyncandramps supply BOTH symbol/group energies.
             Per symbol:
             Gs=[[u.u,u.w],[u.w,w.w]],bs=[u.x,w.x],Es=bs^T*inverse(Gs)*bs.
             Consecutive groups7FT8/4FT4, finalshortgroup allowed; sumGs/bs then same
             2x2solvepergroup. Require sumEgroup/sumEs>=.5, positive denominator,
             finite fits, relativeGramdet>1e-12; otherwise rejectwaveform.
             Independent phase pergroup imposes no phase tie between groups; drift
             fixture acceptance remains mandatory, no whole-frame lock.
             Linear sample work, <=105symbol/27group solves, no new search/FEC/candidate;
             storage within existing64MiB. Unsupported/invalid sources still publish
             when their actual CRC-valid waveform passes, never status-based filtering. */
    }
    action def AdmitDecode {
        in source : WstxRecordingReceive::SourceDescriptor;
        in settings : Settings;
        out job : DecodeJob;
        doc /* Same strict mode/auth/Origin/body/schema/profile/boot/generation/source/busy
             validation order as12.6. GETdecoder before controls; POSTdecode exact6keys
             v/profile_id/boot_id/generation/recording_id/mode <=1024bytes. 202newUUID/gen.
             Existing storage/degraded state applies. Mode immutable, no persisted profile edit. */
    }
    doc /* Coarse search explicitly includes both200 and3500Hz even when off the uniform
         half-tone FFT grid. Evaluate exact off-grid endpoint power by direct quadrature;
         refine clipped to inclusive bounds. FT4mustnotround3500awayorrelax3Hzoracle. */
    action def AdvanceDecode {
        in block : WstxRecordingReceive::SampleBlock;
        in job : DecodeJob;
        out records : ResultRecord[0..2048];
        doc /* Pure canonical12k consumer, no WAV/device/network/UTC access or resampler.
             Detailed/Thin display keeps fixed0..3000Hz even for decoder3159/3337Hz results;
             display8192history and2048/4096plans are not universal decoder buffers.
             Copy into<=30shistory,two blocks,30swindow/15sadvance,complete supports only.
             FFT1920/576,hops480/144,two half-tone grids200..3500,quarter-symbol starts;
             localrefine5time*9freq points. SharedRustFFT6.4.1planned/scalar, checked worker
             buffers/scratch, no second provider/wrapper. <=50msquantum/cancelcheck, service
             pendingconversion/spectrumbetweenquanta; one worker/noqueue, no transmit authority.
             Phase qualification and likelihood calculations above own observation semantics.
             Graylogsumexp zero-minusone,clamp+-12,meanabs>=1,<=24CHANNELharddisagreements.
             ACRCword failing gates does notstop permitted refinements. <=50normalizedminsum
             iterations/round,alpha.8,initial+<=2observationrefinements.
             FinalFT4nopeerobservation usesFt4PairSequence insteadofanotherlocalmarginal;
             withpeer retainlocalnuisanceawareobservation. OnlyfinalroundOSD:
             77unitpayloads composedCRC14+published174,91generator formrank77subcode;
             GF2reliabilityordered77basis; <=137order0/1/2 trials among16least-reliable basis
             bits,lowestweightedCHANNELcost, finalzeroH+CRC+sourceclassification. CRCbits
             constrained, nofreeCRCinformation/AP; earlierminsum success mayfinish.
             EncodedGroupPhaseAgreement>=.5 beforepublication/subtraction,independent7/4symbol
             groupphases,<=105symbol/27group2x2solves, no extra search/FEC/candidates.
             <=3SICpasses/32validsubtractions/window,fit2x2GFSKquadratureamplitudes,immutable
             originals. One pure reconstruction kernel owned7/futurereuse9, independent
             fixture composer never productiondependency. No relative window-energy stop may
             hide a weaker signal; stop ifno new verifiedframe or3pass ceiling. All arrays
             inside64MiB, including complex grids and64FT4 templates.
             Dedup mode/payload/startwithinhalfsymbol, keep later repeated transmissions.
             Actual runtime/sensitivity/falsepositives remain unmeasured, no test verdict. */
    }
    action def MeasureFrame {
        in block : WstxRecordingReceive::SampleBlock;
        out record : ResultRecord;
        doc /* Start canonicalframe nearest first ramp/sync. Frequency lowesttoneaudioHz.
             LSsignalsteadyP=(a²+b²)/2,envelopeinsidefit. Noise poolednonoverlapping
             symbolperiodograms,PSD2absDFT²/(12000*N),excludeDC/acceptedbands+-2spacings.
             Median/ln2 over>=128eligiblebins/>=8windows, SNR2500=10log10(P/(PSD*2500)).
             Insufficient/nonfinite/relative2x2det<=1e-12/PSD<=1e-20=>null; elseclamp+-60.
             Error<=240frames/1HzFT8,144frames/3HzFT4,<=3dBisolatedAWGN>=-15/-10.
             Known-codeword fit3fixedgrids:df1=6000/waveformFrames; stage1time+-N/4stepN/16,
             freq+-spacing/2stepdf1 includingoffgridendpoints; stage2time+-N/16stepmax(1,floor(N/128)),
             freq+-df1/2stepdf1/8; stage3time+-max(1,floor(N/128))step1,frequencyfixed.
             Complete/in-band only,every4thsamptrimN/2ends. Actualstridedreal/quadratureGramG,
             b=[u.x,w.x],maximizeb^T*inverse(G)*b,tiesfreq/time. Rejectnonfiniteorrelative
             determinant<=1e-12; noquadratureorthogonalityassumptionnear1500/3000alias.
             finalamplitude/SNR/subtractionallsamples. No whole-frame phase rejection,
             ordinary+-2Hz/min drift andarbitraryinitialphase remaineligible.
             No UTC/dBFS/noiseless/crowded reference-SNR inference. */
    }
    action def PublishResults {
        in job : DecodeJob;
        in records : ResultRecord[0..2048];
        out page : ResultPage;
        doc /* Stationauthority rechecks fullidentity/generation beforeappend. Cancelinvalid
             beforeack, terminalonlyafterrelease<=250ms; failurewinsoverEOS. Partialretained
             oncancel/failure; newjob/source/restart clears, oldIDs404, browserclosecontinues.
             decode_limit onhistory/allocation/resultbyte/count ceiling; search_limited
             means requiredcorpuscompleteness fails. No silentloss/exceptionstrings.
             Browser onependingpage,>=2spollstarts,nobeginwhileexplicitstatuspending,
             loaded/count separatefromterminal, literaltext, staleIDs ignored, noretrymutations.
             Two maximum-pageclients <=3000accountedB/s/direction andstatus<=2s on32kbitTLS.
             Futurejoint8 optional spectrum<=1/2s,resultpoll<=1/4s independentlytested. */
    }
    action admitDecode : AdmitDecode;
    action advanceDecode : AdvanceDecode;
    action measureFrame : MeasureFrame;
    action publishResults : PublishResults;
    satisfy WstxRequirements::'CL-007-01' by admitDecode;
    satisfy WstxRequirements::'CL-007-02' by publishResults;
    satisfy WstxRequirements::'CL-007-03' by measureFrame;
    satisfy WstxRequirements::'CL-007-04' by advanceDecode;
    dependency admissionOwner from admitDecode to WstxArchitecture::physicalStation::controller::stations::receive;
    dependency calculationOwner from advanceDecode to WstxArchitecture::physicalStation::controller::stations::modes;
    dependency measurementOwner from measureFrame to WstxArchitecture::physicalStation::controller::stations::modes;
    dependency publicationOwner from publishResults to WstxArchitecture::physicalStation::controller::stations::web;
    dependency viewerOwner from publishResults to WstxArchitecture::physicalStation::viewer::browsers;
    package IndependentVerification {
        doc /* All planned/unimplemented companions, cost2 offlineWindowsPC, actualcandidate
             Rust/server/browser and independent fixtures/directmath/recordings/link model.
             No hardware/live service. Source and source_message are not decoded inversehashes.
             Missing/empty manifests fail. FSD6.4 remains original independent expectation.
             Corpus2286:2000noise+160AWGN+80overlap+40offset+6silence/mismatch/CRCnegative;
             fieldboundary and supportedfamily vectors additional. Actual execution not claimed. */
        verification ft4 {
            subject decoder : AdvanceDecode;
            objective { verify WstxRequirements::'CL-007-01'; verify WstxRequirements::'CL-007-03'; verify WstxRequirements::'CL-007-04'; }
            doc /* FT4exactpayload/CRC/H/105tones/GFSKallfamilies+boundaries; strong36/40@-10,
                 weak20/40@-13; overlapsboth18/20at2spacings,strong18/weak10at1spacing6dB;
                 official>=16/19matches notexhaustivetruth. Error144frames/3Hz,3dBstrongAWGN.
                 Pairsequence8scalarcasesG1..3: standaloneDecimal100completeenumeration,
                 uniform/asymmetric/knownmask/coupled/extremefactors,two+1000000shiftpairs.
                 Allvariable/boundarylogmarginalswithin1e-9absolute,impossibletonesnegInfinity;
                 dimensions/empty/nonfinite/badboundaryreject; full2286/14inputsunchanged.
                 SeparateCRCrecurrence/publishedtables/fixedvectors/independentsynthesis.
                 Stride4Gramoracle:60480frames,k288..60191step4;
                 phase=2pi*f*(k+1)/12000+.4sin(2pi*((k+1)/12000)/.048),x=.6u-.8w.
                 f1499/1499.9/1500/1500.1/1501/2999/3000/3001Hz; independentf64Gram
                 yieldscoefficients.6/-.8,explained=sumx*x; candidatef32relativeerror<=5e-7.
                 Planned Rust/decoderfixture suite bindings; no production encoder oracle. */
        }
        dependency ft4Case from ft4 to WstxRequirements::'TC-004-001';
        verification ft8 {
            subject decoder : AdvanceDecode;
            objective { verify WstxRequirements::'CL-007-01'; verify WstxRequirements::'CL-007-03'; verify WstxRequirements::'CL-007-04'; }
            doc /* FT8exactpayload/CRC/H/79tones/GFSKallfamilies+boundaries; strong36/40@-15,
                 weak20/40@-18; sameoverlapcounts; official>=12/14matches,22inheritedtexts
                 supplementaryonly. The shared known-wordfitkernel uses the SAME eight-frequency
                 Stride4Gramoracle defined by ft4 above, with identical60480-frame phase/x formulas,
                 expectedcoefficients.6/-.8 andexplained=sumx*x within5e-7f32relativeerror.
                 Error240frames/1Hz,3dBstrongAWGN. Valid/RandTUvectors
                 retainedpositivesdespitereferencenondetection; no qualityscopeweakening. */
        }
        dependency ft8Case from ft8 to WstxRequirements::'TC-004-002';
        verification rejectionLifecycleResources {
            subject decoder : AdvanceDecode;
            objective { verify WstxRequirements::'CL-007-02'; verify WstxRequirements::'CL-007-04'; }
            doc /* 1000noise/modefourRMSplusinvalid/wrongmode/silence/goodFECbadCRC require
                 zeropublishedframes. Unsupported/invalidonlyinjectedvalidCRCframes, nopanic.
                 Repeatpayloadmultiset,time<=1frame,freq<=.2HzFT8/.5HzFT4. Cancelallphases,
                 stale/restart/busy/limits/strictHTTP/realbrowser/twopeer32kbitlink<=2sstatus.
                 OneCPUworker:15sFT8<=5s,7.5sFT4<=3s,120s<=40s,cold+<=2s; tenruns+warmup,
                 actual5950XWindowsOS/build/power/hash/workload/min/median/p95/max/memory;
                 fourprofiles<=2xruntime,64MiBworker/96MiBprocessdelta,<=250msrelease.
                 Futurejoint48kcapture+FFT+decode provesfairness, notlargerringassumption.
                 PlannedRust/fixture/HTTP/browser/linkcompanions; no execution verdict. */
        }
        verification phaseLikelihoodAndScale {
            subject decoder : AdvanceDecode;
            objective { verify WstxRequirements::'CL-007-01'; verify WstxRequirements::'CL-007-03'; verify WstxRequirements::'CL-007-04'; }
            doc /* Independent additional recipes:phase.7/pi/2,drift+-1/30Hz/s,canonicalgains1e-4/8,
                 secondstation80dBbelowstronger with sub-PCM16-quantumamplitude andfloatrepeat;
                 retainbothmessages. Quantizationresiduals afterindependent best-fit subtraction:
                 q=round(x*32767)/32768,unitreal/90degreeu,w,fullsupport2x2Gramfit[a,b],
                 r=q-a*u-b*w beforegain/floatstorage. Innerproducts<=128epsilon64*sqrt(max(u.u,w.w)*q.q)
                 beforestorage,<=4epsilon32*sqrt(max(u.u,w.w)*rStored.rStored)afterward.
                 Finitecaserequireszeropublications,no search_limited,neverproductionhelpers.
                 All2286originalcases/thresholds/256cap remain. Verifyrecipe/composer/audiohashes,
                 per-blockphase,45*Kproducts/rawmax,256^2peercomparisons,rank77recovery,
                 recoveredcodewordgroup-phasefraction>=.5,linearfitwork,64MiBworkingstore.
                 No externaldecoder oracle or skipped case pass. */
        }
        dependency phaseLikelihoodCase from phaseLikelihoodAndScale to WstxRequirements::'TC-004-003';
        dependency rejectionCase from rejectionLifecycleResources to WstxRequirements::'TC-004-003';
    }
}
