// Canonical FSD slices SHA256: 471b0e1074e0cbfc529f5f39fa9279d32754743cf56afb7b1d2d108f14ae66c6
package WstxOfflineDecode {
    private import ScalarValues::*;
    doc /* Target implementation contract, NOT implemented decoder behavior or test results.
         Authority: docs/WSTX Rust FSD.md 4.4 CR7, 6.4 TC-004-001/002/003, 12.7.
         Protocol: https://wsjt.sourceforge.io/FT4_FT8_QEX.pdf sections2-5/AppendixA;
         current source boundaries and fixed vectors use the pinned beta4 reference manifest.
         Pinned GPL-compatible physical routines may be adapted with source provenance/attribution. Independent meaning/readiness
         review is required before production code; semantic parsing is not that review.
         Existing physical station/receive/modem/web/browser usages remain owners. */

    enum def Mode { enum ft4; enum ft8; }
    enum def FrameStatus { enum decoded; enum unsupported; enum invalid_payload; }
    enum def CallKind { enum call; enum token; enum hash; }
    enum def ExchangeKind { enum blank; enum grid; enum report; enum roger; }
    attribute def ModemPublicationKey {
        attribute payload77 : String;
        attribute startFrame : Integer;
        attribute frequencyHz : Real;
        attribute reservedBytes : Integer;
    }
    item def ModemHistoryState {
        attribute mode : Mode;
        attribute liveHistory : Boolean;
        attribute lastWindowOrigin : Integer[0..1];
        attribute keys : ModemPublicationKey[0..2048];
        attribute retainedBytes : Integer;
        assert constraint boundedBytes { retainedBytes >= 0 and retainedBytes <= 2097152 }
        doc /* Puremodemcontext,nosource/jobidentity/result-ring/wiresequenceauthority.
             DecodeState::new(mode)=finite numericaltestutility,lifetimekey/bytecaps.
             DecodeState::new_live(mode)=continuousreceive,boundedactivehistory.
             Mode/policyimmutable; available_count()=retainedkeys,encoded_bytes()=storedcharges.
             Livegettersnevermanagerwirecount/cursor. SharedwindowAPI/result/errortypesunchanged.
             EachkeyretainsitsoriginalcompactNumberedJSONcharge; livechargeuses
             sequence9007199254740991(16digits),finiteutilityusespublicationordinal.
             Record<=1024bytes,keys<=2048,totalcharges<=2MiB; managerownsactualsafesequence
             andindependent2048/2MiBpublicring. Callernewcontextonjob/source/gap/historyreset. */
    }
    action def PrepareModemWindow {
        in history : ModemHistoryState;
        in sourceWindowOrigin : Integer;
        out preparedHistory : ModemHistoryState;
        doc /* UpdatesSAMEcaller-ownedinstance,noadditionalcache/worker/source.
             Afterwindowinputvalidation, liveorigin<lastacceptedorigin=>InvalidSamples
             withoutstatechange; equaloriginallowed. Otherwise STRICTLYretirekey.startFrame
             <max(0,sourceWindowOrigin-symbolFrames/2),subtractexactstoredreservedBytes,
             thenrecordlastWindowOrigin. Retainboundarykeysforhalf-symboloverlapdedupe/SIC.
             Finiteutilityperformsnoretirementandkeepslifetime2048/2MiBbehavior.
             Allhistoryinsideexisting64MiB; callbackpartialsretainedonlaterDecodeLimit. */
    }
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
        attribute recoveryInformationRank : Integer = 77;
        attribute fecIterations : Integer = 50;
        attribute recoveryTrials : Integer = 137;
        attribute subtractionPasses : Integer = 3;
        attribute subtractions : Integer = 32;
        attribute minFrequencyHz : Real = 200.0;
        attribute maxFrequencyHz : Real = 3500.0;
        attribute costasThreshold : Real = 2.7;
        attribute minMeanAbsLlr : Real = 1.0;
        attribute maxHardDisagreements : Integer = 24;
        attribute minSumAlpha : Real = 0.8;
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
        attribute :>> kind = WstxRecordingReceive::ReceiveKind::live;
        attribute settings : Settings;
        attribute available_count : Integer;
        attribute search_limited : Boolean;
        assert constraint boundedProgress {
            processed_frames >= 0 and processed_frames <= (900719925 * 10000000 + 4740991) and
            available_count >= 0 and available_count <= 2048
        }
        doc /* Existing station receive-job authority, kind=live with immutable mode.
             One import OR recorded spectrum OR continuous receive; no queue.
             Source-relative FT8/FT4 windows, reliable live ring and epoch rules12.8.
             Numerical recorded fixtures have no production receive operation. */
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
            sequence >= 0 and sequence <= (900719925 * 10000000 + 4740991) and i3 >= 0 and i3 <= 7 and
            start_frame >= 0 and start_frame <= (900719925 * 10000000 + 4740991) and
            frequency_hz >= 200.0 and frequency_hz <= 3500.0
        }
        doc /* Exact shared live wire keys,<=2048UTF8bytes. payload77 exactly77binarychars; n3 only
             ifi3=0; text<=80ASCII and matching fields only when decoded, otherwise null.
             Supported0.0/.1/.3/.4/.5,1/2/3/4/5;0.2/.6/.7,6/7 unsupported. BadCRC never
             published. start indexes canonical12k first ramp/sync, never native orUTC.
             SNR null orfinite[-60,60], bounds labeled; full identity is page envelope. */
    }
    item def ResultPage {
        attribute v : Integer = 1;
        attribute correlation : WstxRecordingReceive::Correlation;
        attribute mode : Mode;
        attribute 'state' : WstxRecordingReceive::ReceiveState;
        attribute error : WstxRecordingReceive::ErrorCode[0..1];
        attribute search_limited : Boolean;
        attribute first_sequence : Integer;
        attribute next_sequence : Integer;
        attribute available_count : Integer;
        attribute 'next' : Integer;
        attribute more : Boolean;
        item records : ResultRecord[0..16];
        assert constraint pageCursor { first_sequence >= 0 and next_sequence >= first_sequence and next_sequence <= (900719925 * 10000000 + 4740991) and available_count == next_sequence - first_sequence and available_count <= 2048 and 'next' >= first_sequence and 'next' <= next_sequence }
        doc /* Exact12.8 live envelope<=16384bytes,record<=2048bytes; Thinlimit1/page3072.
             Each record sequence<next_sequence,start_frame<actually captured next_frame.
             cursor<first=>410cursor_expired,cursor>next=>400,cursor==next=>empty.
             No file decode operation/snapshot/page endpoint. */
    }
    attribute def Ft8CarrierSearchPolicy {
        attribute minimumCarrierHz : Real = 200.0;
        attribute maximumCarrierHz : Real = 3500.0;
        attribute internalToneSpacingHz : Real = 6.25;
        attribute requiresKnownCarrier : Boolean = false;
        attribute requiresKnownStartTime : Boolean = false;
        attribute requiresCarrierOnToneGrid : Boolean = false;
        attribute retainsPerCandidateFrequencyAndTiming : Boolean = true;
        attribute refinementHalfRangeHz : Real = 2.5;
        attribute refinementStepHz : Real = 0.5;
        doc /* Search each station independently within the inclusive carrier band.
             The internal6.25Hz tone spacing does not fix a station's lowest-tone
             offset to multiples of6.25Hz or a shared transmitter-frequency grid.
             Finite receiver search steps approximate arbitrary carrier offsets;
             existing selection bounds and1Hz/240-frame FT8 tolerances remain.
             Ft8FineSynchronization defines finer carrier/time search;
             SymbolTransformGrid defines the coarse search. */
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
             grid <=435*1057FT8 or2081*318FT4=661758.
             ThisgridisFT8coarse/rectangularSNR; FT4detectioninsteadusesFt4FrequencyCandidates
             andone4162*9timinggrid/frequency. ItsrectangulargridisSNR-only. Priority heap and suppression bitmap,
             checkpoint visits; no quadratic all-pairs suppression. All storage inside64MiB. */
    }

    item def ModemSampleWindow {
        attribute mode : Mode;
        attribute sourceWindowOriginFrame : Integer;
        attribute samples : Real[0..360000];
        attribute subtractionPass : Integer;
        assert constraint windowPosition { sourceWindowOriginFrame >= 0 and sourceWindowOriginFrame <= (900719925 * 10000000 + 4740991) }
        assert constraint passRange { subtractionPass >= 0 and subtractionPass <= 2 }
        doc /* PRIVATEboundedcanonicalf32window,NOTa4096-framecaptureSampleBlock/newsource.
             Sharedreceiveowneraccumulatesvalidatedcanonicalblocksandprovidesthiswindow;
             origin/modepreserved,source/job/boot/generationauthorityremainoutsidepuremodem.
             Originalwindowimmutable; worker-ownedresidualcopyhasSAMEorigin/mode/length.
             L=samplescount. LiveFT8<=360000frames/FT4<=180000;finiteutility<=360000.
             No gaps/paddingfabricated. Allhistory/windows/residuals/FFTs inside64MiB. */
    }
    attribute def Ft8PhysicalLimits {
        attribute inputRate : Integer = 12000;
        attribute maxInputFrames : Integer = 360000;
        attribute longFftUnit : Integer = 192000;
        attribute longFftMax : Integer = 384000;
        attribute downsample : Integer = 60;
        attribute shortFftMax : Integer = 6400;
        attribute basebandRate : Integer = 200;
        attribute samplesPerSymbol : Integer = 32;
        attribute firstTimePoints : Integer = 21;
        attribute firstTimeRadius : Integer = 10;
        attribute frequencyPoints : Integer = 11;
        attribute frequencyStepHz : Real = 0.5;
        attribute finalTimePoints : Integer = 9;
        attribute finalTimeRadius : Integer = 4;
        attribute requiredCostasHits : Integer = 9;
        attribute totalCostasSymbols : Integer = 21;
        attribute metricFamilies : Integer = 5;
        attribute metricScale : Real = 2.83;
        attribute channelIterationsPerFamily : Integer = 50;
        attribute channelTrialsPerFamily : Integer = 137;
        attribute hardDisagreementMax : Integer = 24;
        attribute meanAbsLlrMin : Real = 1.0;
        attribute filterRadius : Integer = 2000;
        attribute filterTaps : Integer = 4001;
    }
    item def ComplexBasebandCoefficient { attribute realPart : Real; attribute imaginaryPart : Real; }
    enum def PhysicalMetricFamily { enum single; enum pair; enum triple; enum normalizedSingle; enum strongest; enum quadruple; }
    item def PhysicalLlrFamily { attribute family : PhysicalMetricFamily; attribute llrZeroPositive : Real[174]; }
    item def PhysicalFinePoint {
        attribute sourceStartFrame : Integer;
        attribute carrierHz : Real;
        attribute syncPower : Real;
        attribute hardCostasHits : Integer;
    }
    calc def Ft8MetricDifference {
        in maxBitOne : Real;
        in maxBitZero : Real;
        return raw : Real = maxBitOne - maxBitZero;
    }
    calc def Ft8ChannelPolarity {
        in raw : Real;
        in populationSigma : Real;
        return llrZeroPositive : Real = -2.83 * raw / populationSigma;
        doc /* Sigma strictlypositive/finite. Perfamily m=sumraw/174,q=sumrawSquared/174;
             sigma=sqrt(q-m*m) ifpositive,else sqrt(q). NOmean subtraction.
             Zerowidth/nonfinitefamily suppliesnoword; no duplicateFEC afterfamily5. */
    }
    action def Ft8BandLimit {
        in source : ModemSampleWindow;
        in currentPass : Integer;
        in carrierHz : Real;
        out baseband : ComplexBasebandCoefficient[0..6400];
        out centerBinHz : Real;
        doc /* Pinned0f7d592 ft8_downsample adaptation. L=currentpassframes;
             N1=192000*ceil(L/180000)<=384000,N2=N1/60,df=12000/N1.
             i0=round(f0/df),ib=max(1,round((f0-9.375)/df)),it=min(N1/2,round((f0+53.125)/df)).
             Sharedcachednegative-signunnormalizedlongFFT rebuiltwhenresidualchanges.
             Maporiginalbin i to(i-i0)modN2. T=round(6.25/df),K=it-ib+1,j=i-ib.
             Lowtaperj0..T:.5*(1+cos(pi*(T-j)/T));hightaperjK-1-T..K-1:
             .5*(1+cos(pi*(j-(K-1-T))/T));interior1.
             UnnormalizedpositiveinverseFFT,scale1/sqrt(N1*N2),200complexsamples/s.
             Actualmixedcenter=i0*df; everytrial/reportaccountsforit. Paddingisprivate,
             cannotadmitincomplete151680frames. Sharedplanned/scalarRustFFT6.4.1,
             sameconventions/cacheowner; real/complex64transform/metric/convolutionsums
             overcanonicalfloat32input, finalLLRfloat32; allstoragewithin64MiB. */
    }
    action def Ft8FineSynchronization {
        in source : ModemSampleWindow;
        in coarseStartFrame : Integer;
        in coarseCarrierHz : Real;
        out fine : PhysicalFinePoint[0..1];
        doc /* CoarseCostasratio>=2.7/currentgrid/suppression/order unchanged.
             UseFt8BandLimit; P(b,d)=sumover21Costassymbolsabs(sumj0..31
             z[b+32*s+j]*exp(-i2pi*(tone_s/32+d/200)*j))Squared.
             Independentsymbolphases. Firstb=round(coarseStart/60)+[-10..10],d0;
             thenfrequencytweaks[-2.5..2.5]step.5atbestb; rebuildatbestcarrier;
             finalb=bestb+[-4..4],d0. Descendingpower,tiesascendingfrequency/start.
             EverypointcompleteORIGINAL151680frames/carrier200..3500inclusive.
             Outputcanonicalstart60*b includesramp,notGUI DT/UTC.
             FFT32eachsymbol,hardtone=largestabsbin0..7,tieslower;>=9/21Costashits.
             QualifyBEFORE256cap,257th=>searchLimited. Post-refinementcanonicalstarts:
             b=floor(s/60+.5),nonnegativehalftiesUP;clamp0..floor((L-151680)/60).
             RechecktoneevidenceatnearestCOMPLETEbasebandorigin/finalcarrier,notpadding.
             PRESERVEreportedcanonicalstart s; mappingonlyphysicalguardbeforepublication/SIC.
             NOcrosssymbol/blockfractiongateforFT8. */
    }
    action def Ft8ObserveMetricFamilies {
        in source : ModemSampleWindow;
        in point : PhysicalFinePoint;
        out families : PhysicalLlrFamily[5];
        doc /* Pinnedft8b unassistedimetric1. C[k,t]=FFT32symbol[k][t]/1000,t0..7.
             Gray[0,1,3,2,5,6,4,7],MSBfirst. Each29datahalfstarts7/43(zerobased).
             n1/2/3,k0,n,2n..<29; v0..8^n-1 selectsnGraytones; S=abs(sumCselected).
             EndgroupsKEEPactualfollowingsynccoefficient. Bitindexhalf*87+3*k+bit,
             storeonlyindex<174; secondhalfoverwritesitsownpositions.
             A/B/C=Ft8MetricDifferenceperbitforsingle/pair/triple. D=A/max8S,zeroifmax0.
             E=largestabsoluteRAW A/B/Cperbit,tiesA/B/C. FormEbeforeanynormalization.
             Normalizeeach174elementfamilyasFt8ChannelPolarity,NOmean subtraction.
             NoAP/callsign/contact/semanticprior. No currentFT4neighborlikelihoodapplies. */
    }
    action def Ft8DecodeMetricFamilies {
        in families : PhysicalLlrFamily[5];
        out accepted : Boolean;
        out channelWord : Integer[174];
        out payload77 : Integer[77];
        doc /* Fiveorderedfamilies,each<=50minsumalpha.8and<=137rank77order0/1/2recovery
             trials/16least-reliablebasisbits. CRCbitsconstrained; publishedH+CRCmandatory.
             RequiremeanabsLLR>=1/hardCHANNELdisagreements<=24. Avalidwordfailinggates
             DOESNOTstoplaterfamilies. Firstallgatesacceptedwordwins; no6thfallbackdecode.
             Unsupported/invalidsourceinterpretationremainstypedobservation,notdropfilter.
             Sameworker,cancel/servicecheckpoints<=50ms,terminalrelease<=250ms. */
    }
    action def Ft8SubtractVerifiedFrame {
        in source : ModemSampleWindow;
        in point : PhysicalFinePoint;
        in reference : ComplexBasebandCoefficient[151680];
        out residual : ModemSampleWindow;
        doc /* Adaptedsubtractft8, boundedCENTEREDzerobasedproductdefinition:
             c[k]=x[start+k]*conj(reference[k]),zerooutsideframe;
             h[j]=cos(pi*j/4000)^2/sum[a=-2000..2000]cos(pi*a/4000)^2,j=-2000..2000.
             y[k]=sumj h[j]*c[k-j],linearFFTpadding>=151680+4000.
             Atedge-distancea0..2000 dividebyavailableweight sumj[-2000..a]h[j].
             Subtract2*Re(reference[k]*y[k])ONLYwithinframe; originalsourceimmutable.
             <=3passes/32verifiedsubtractions, invalidatepassFFTafterresidualchanges.
             Directscalarconvolution/edgesareindependentoracle; no circularwrap.
             No additionalowner/provider/job/source orTXauthority. */
    }

    attribute def Ft4PhysicalLimits {
        attribute longFftUnit : Integer = 72576;
        attribute longFftMax : Integer = 435456;
        attribute downsample : Integer = 18;
        attribute basebandMax : Integer = 24192;
        attribute samplesPerSymbol : Integer = 32;
        attribute shapedSymbols : Integer = 105;
        attribute observedSymbols : Integer = 103;
        attribute firstFrequencyPoints : Integer = 9;
        attribute firstFrequencyStepHz : Integer = 3;
        attribute firstTimePoints : Integer = 4162;
        attribute firstTimeStep : Integer = 4;
        attribute frequencyFft : Integer = 2304;
        attribute frequencyHop : Integer = 576;
        attribute smoothBins : Integer = 15;
        attribute baselineSegments : Integer = 10;
        attribute baselinePercentile : Integer = 10;
        attribute baselineDegree : Integer = 4;
        attribute baselineLiftDb : Real = 0.65;
        attribute minFrequencyContrast : Real = 1.18;
        attribute finalFrequencyPoints : Integer = 9;
        attribute finalTimePoints : Integer = 11;
        attribute requiredToneHits : Integer = 8;
        attribute requiredSyncBits : Integer = 20;
        attribute minSyncMagnitude : Real = 1.2;
        attribute metricFamilies : Integer = 3;
        attribute rawBits : Integer = 206;
        attribute filterTaps : Integer = 1401;
    }
    item def PhysicalFrequencyPeak { attribute carrierHz : Real; attribute contrast : Real; }
    action def Ft4FrequencyCandidates {
        in source : ModemSampleWindow;
        out frequencies : PhysicalFrequencyPeak[0..1152];
        doc /* Pinnedgetcandidates4/ft4_baseline/nuttal_window/pctile/polyfit adaptation.
             FFT2304/hop576overEVERYcompleteORIGINALwindow,inputx*window/300.
             Periodicwindowj0..2303:.3635819-.4891775cos(2pi*j/2304)
             +.1365995cos(4pi*j/2304)-.0106411cos(6pi*j/2304).
             Averagepositive-binLINEARpowers, smooth15bins; retainedlinearbeforedbfit.
             df12000/2304,ia=round(200/df),ib=round((3500+31.25)/df).
             10integerfloorsegments,remainderexcludedfromfit. Percentile1basedindex
             clamp(floor(.10*segmentLength+.5),1,n),includealltiedvalues<=cutoff.
             BaselineinputUNSMOOTHEDaveragedpowers; <=1000lower-envelopepoints,
             equalweightquarticleastsquares,finitefullrank5;
             affinexscalingallowedasSAMEpolynomialspace. Baseline=10^((fitdb+.65)/10).
             Allzero/insufficient/singular/nonfinite/nonpositivebaseline=>nofrequencies.
             Individualzerobinsuseminpositivedb-120forfitonly; positivepowersneverfloored.
             ratio=original15-binmean/baseline;interiorlocalmaxratio>=1.18.
             delta=.5*(left-right)/(left-2center+right),0ifden0;
             carrier=(bin+delta)*df-31.25,contrast=center-.25*(left-right)*delta.
             Retain200..3500inclusive. Endpointe200/3500:u=(e+31.25)/df,j=flooru,a=u-j;
             interpolateAFTERdivision rEnd=ratio[j]+a*(ratio[j+1]-ratio[j]);a0=>ratio[j]only.
             Exactendpointtrialiff rEnd>=1.18; no polynomial/rawpowerinterpolation.
             Ordercontrastdesc/carrierasc; noQSO/semanticpriority. Nocandidatemadefrompadding.
             Sharedworker/FFTdependency/scratch,<=50msquantum/64MiB. */
    }
    action def Ft4BandLimitAndFineSync {
        in source : ModemSampleWindow;
        in coarseCarrierHz : Real;
        in priorFine : PhysicalFinePoint[0..256];
        out fine : PhysicalFinePoint[0..256];
        out searchLimited : Boolean;
        doc /* The outputfinecontainsADDITIONALpoints only. DedupagainstpriorFineAND
             currentfinebeforecounting; size(priorFine)+size(fine)<=256 globally.
             Nextdistinctqualifiedpointwouldexceedcap=>searchLimited,notperfrequencyreset.
             Multipletemporalframesare retained inthispluraloutput.
             Pinned0f7d592 ft4_downsample/sync4d/driver boundedlocaladaptation.
             N1=72576*ceil(L/72576)<=435456,N2=N1/18,df=12000/N1,baud=12000/576.
             T=floor(.5baud/df),F=floor(4baud/df),S=floor(baud/df),i0=round(f0/df).
             PeriodicW[j]:j0..<T .5*(1+cos(pi*(T-1-j)/T));jT..<T+F 1;
             jT+F..<2T+F .5*(1+cos(pi*(j-T-F)/T));else0.
             Signedbinb mapspositiveoriginali0+b if0..N1/2,weightW[(b+S)modN2]/N2.
             Positiveunnormalizedinverse,normalizewindowbypositivefiniteRMS.
             Actualcenteri0*df explicitlyaccounted;666.666...Hz/32samplespersymbol.
             Ft4FrequencyCandidates suppliesONLYcarrierconfidence,notcoarsetimeprior.
             FirstCostasoriginb=32..floor((L-60480)/18)+32 step4,includeoffgridlastendpoint.
             Scorefourblocksatb+{0,33,66,99}*32;each64EVERYSECOND FILTEREDsamples
             correlatesrectangularCostas4tonepattern/frequencytweak,sum4magnitudes/64,
             independentblockphases. Firstd[-12..12]step3 atALLcompleteoriginpositions.
             Visit3x3localmaxima>=1.2descendingpower,tiesfrequency/time,suppresshalfsymbol
             ANDhalftoneforRAWgridpoints. ThenbestD+[-4..4]step1,bestB+[-5..5]step1.
             AFTERrefinementANDphysical8tone/20bitqualification,suppresscompeting
             completewaveforms iff abs(startDifference)<60480 ANDabs(carrierDifference)<=12000/576/2.
             Halfopensupports:exactlyadjacent60480remaineligible. Firstqualifiedpoint
             inexistingfrequencycontrast/carrierthenpower/carrier/startvisitorderwins.
             FailedphysicalqualificationcreatesNOexclusion;comparepriorFine+currentfine
             acrossALLfrequencycandidatesbeforeglobalcount. FEC/payloaddoesnotinfluence
             selection; retainedpointkeepssupporteveniflaterFECfails. Resetallthese
             exclusionsatnewresidualpass. Explicitblind-windowstrongest-timingadaptation,
             notUTC/source-originpartitions,notliteralupstream3fixedsegments.
             Atmost4162time*9frequencycells/frequencycandidate,releasedbeforenext;
             precomputedtemplates/boundedservicecheckpoints. NoUTC/slot/time-powerprior.
             CompleteORIGINAL60480frames/carrier200..3500; outputstart18*(b-32)inclramp.
             FFT32at103symbolsstartinground(start/18)+32:>=8/16hardtonehits and>=20/32
             Grayhardbits,max1-max0,ties1. Physicalqualificationbefore256cap/257=>limited,
             andatfinalfullrateknown-wordmeasurementbeforepublication/subtraction:
             firstCostasb=floor(s/18+.5)+32,nonnegativehalftiesUP,preservereporteds;
             guardspansinsideORIGINALsupport. NOcross-block/groupfractiongate, no duplicateworker/cache/provider. */
    }
    action def Ft4ObserveMetricFamilies {
        in source : ModemSampleWindow;
        in point : PhysicalFinePoint;
        out families : PhysicalLlrFamily[3];
        doc /* Pinnedget_ft4_bitmetrics,103complexFFT32symbols,fourtones,Gray[0,1,3,2].
             Families=single/pair/quadruple; n1/2/4,k0,n,2n...<=103-n;
             enumerate4^n coherentmagnitudes;max1-max0
             MSB-first2bits/tone,206rawbits/family. Pairbits204..205=single;
             fourbits200..203=pair,204..205=single (zerobased).
             NormalizeFULL206populationasFT8(no meansubtraction),thenextractinclusive
             ranges8..65/74..131/140..197=>174data,scale2.83/negateONCE.
             Threeorderedfamilies,each50minsumalpha.8/137rank77boundedrecovery,
             meanabs>=1/hardCHANNELdisagreements<=24/H+CRC. Failedwordcontinues;
             no4thfallback. Sourceunsupported/invalidstatusretained, noAP/semanticprior. */
    }
    action def Ft4SubtractVerifiedFrame {
        in source : ModemSampleWindow;
        in point : PhysicalFinePoint;
        in reference : ComplexBasebandCoefficient[60480];
        out residual : ModemSampleWindow;
        doc /* Sameboundedcomplex-envelopeoperationasFt8SubtractVerifiedFrame,
             h[j]=cos(pi*j/1400)^2/sum[-700..700]cos(pi*j/1400)^2,j[-700..700],1401taps.
             Centeredlinearconvolution,FFTpad>=60480+1400,NOedgeavailabilitycorrection.
             Referenceincludesramp,alreadycanonicalorigin,NOsecond-576frameadjustment.
             Originalsamplesimmutable,3passes/32verifiedsubtractions,passFFTinvalidated.
             Sharedpurewaveform/measurement/FFT/cancelownership,within64MiB. */
    }
    action def AdmitDecode {
        in source : WstxRecordingReceive::SourceDescriptor[0..1];
        in settings : Settings;
        out job : DecodeJob;
        doc /* Production12.8 live start only; selected-profile auth/Origin/schema,
             boot/generation/profile-revision and shared receive admission precede capture.
             Mode immutable. Source absent during opening before first provider ACK;
             no publication until acknowledged full tuple. Initialstart freshjob/gen,
             firstsourceACK samejob/gen;
             subsequent unknownepoch freshsource/job/gen beforeproviderACK and ring reset.
             Recorded waveforms are internal numerical/integration fixtures, no file API. */
    }
    doc /* Coarse search explicitly includes both200 and3500Hz even when off the uniform
         half-tone FFT grid. Evaluate exact off-grid endpoint power by direct quadrature;
         refine clipped to inclusive bounds. FT4mustnotround3500awayorrelax3Hzoracle. */
    action def AdvanceDecode {
        in block : WstxRecordingReceive::SampleBlock;
        in job : DecodeJob;
        out records : ResultRecord[0..2048];
        doc /* SharedreceiveownerassemblesModemSampleWindowfromcanonicalSampleBlocks;
             physicalalgorithmsconsumeTHATprivatewindow,notone4096-framecaptureblock.
             Purecanonical12kconsumer,noWAV/device/network/UTCaccess. LiveFT8<=30s/15sadvance,
             FT4<=15s/7.5sadvance;finiteinternaltestutilitywindow/historyunchanged.
             FT8coarseN1920/hop480/half-tone200..3500inclusive/endpoints;FT4N576/hop144
             noisegridseparatefromFt4FrequencyCandidates/Ft4BandLimitAndFineSync.
             FT8BandLimit/FineSynchronization/ObserveMetricFamilies/DecodeMetricFamilies;
             FT4BandLimitAndFineSync/ObserveMetricFamilies. Qualifiedcap256,257=>limited.
             FiveFT8orthreeFT4families; each<=50minsumalpha.8/<=137rank77recovery among16
             leastreliablebasisbits,CRCconstrained. Meanabs1/hard24/H+CRCmandatory.
             NoAP/hints/semanticdrop; physicalsyncguardsatfinalreportedcoordinates.
             Sharedfullrateknownword3gridmeasurement,mode-specificcomplexenvelopeSIC,
             <=3passes/32verifiedsubtractions; originalsimmutable/no weakrelativeenergystop.
             SharedFFT/bandlimit/finesync/bitmetrics/channel/convolutionboundary,modeparameters;
             onecurrentmode/windowplan/scratchcache andcurrentpassFFT,droponepochreset;
             no globalmutablecommonblocks; residualchangeinvalidatesFFT.
             SharedRustFFT6.4.1planned/scalar/oneworker/noqueue/source/cancelquanta<=50ms,
             serviceconversion/spectrum betweenquanta,release<=250ms. Allplans/grids/scratch
             within64MiB. Onepurewaveformowner7/futurereuse9,noTXauthority.
             Displayfixed0..3000Hzindependentofdecode200..3500; no sharedmodem/displayFFTplan.
             Dedupmode/payload/startwithinhalfsymbol,retainlaterrepeatedtransmissions.
             Schema/history/source/job/epoch/resultauthorityunchanged; modelisnottestverdict. */
    }
    action def ReconstructGfskReference {
        in mode : Mode;
        in tones : Integer[79..105];
        in carrierHz : Real;
        out reference : ComplexBasebandCoefficient[60480..151680];
        doc /* Sharedpureprimitive:N1920/576,BT2/1,F=N*symbols,spacing12000/N.
             p(t)=(erf(c*(t+.5))-erf(c*(t-.5)))/2,c=pi*BT*sqrt(2/ln2),p0outsideabs(t)<2.
             offset[k]=sum_s tone_s*spacing*p((k+.5-(s+.5)*N)/N),exteriortones0.
             phi[k]=sum_m0..k 2pi*(carrier+offset[m])/12000,ADVANCEbeforeemission.
             R240/576,amp[k]=(1-cos(pi*k/R))/2 forfirstR,mirrorF-1-kforlastR,else1.
             Referenceamp*(cosphi+i*sinphi),samefitting/SICkernel,independentwaveformoracle.
             No TXauthority/extra encoderdependency/semanticprior. */
    }
    action def MeasureFrame {
        in block : ModemSampleWindow;
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
             Complete/in-band only,EVERYsamptrimN/2ends. Actualfullratereal/quadratureGramG,
             b=[u.x,w.x],maximizeb^T*inverse(G)*b,tiesfreq/time. Rejectnonfiniteorrelative
             determinant<=1e-12; noquadratureorthogonalityassumption. Nounfilteredsubsampling:
              unrelatedcarriersmustnotaliasintocandidatequadratures. Samegridcoordinates/order
              andcandidate/pass/subtraction/FECcaps.
             finalamplitude/SNR/subtractionallsamples. No whole-frame phase rejection,
             ordinary+-2Hz/min drift andarbitraryinitialphase remaineligible.
             No UTC/dBFS/noiseless/crowded reference-SNR inference. */
    }
    action def PublishResults {
        in job : DecodeJob;
        in records : ResultRecord[0..2048];
        out page : ResultPage;
        doc /* Stationauthority rechecks fullidentity/generation beforeappend. Cancelinvalid
             beforeack; terminalonlyafterrelease<=250ms; retain marked partials onstop/failure.
             Newjob/source/restart invalidates oldpages/callbacks. Reliable2048/2MiB live ring;
             evictionadvancesfirst_sequence, lifetime safecountersneverreset within an epoch.
             SearchLimited=>failed/decode_limit+search_limited=true,acceptedpartialsretained;
             accepted cancellation has priority. No invented calls/exception strings.
             Browser onependingpage,Thinlimit1/starts>=4sbehindexplicitstatus; optional
             spectrum<=1/2s; two32kbitclients<=3000accountedB/s/direction,status<=2s.
             No automaticmutationreplay or browsermodem/clockauthority. */
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
        doc /* Verification intent; executable coverage is declared in FSD metadata. Cost2
             offlineWindowsPC, actualcandidate
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
                 Continuoushistorybothmodes:>2048lifetimeverifiedcallbackswithadvancingorigins,
                 exacthalf-symbolboundarydedupe,strictolderretirement/exactstoredcharges,
                 equaloriginsallowed,backwardsrejectunchanged,newcontextgapreset;
                 privatekeys/bytesboundedandmanagerwirecursorsindependent.
                 Finitetestutilityunchangedlifetimecaps/partials.
                 SeparateCRCrecurrence/publishedtables/fixedvectors/independentsynthesis.
                 FullrateGramoracle:60480frames,k288..60191EVERYsample;
                 phase=2pi*f*(k+1)/12000+.4sin(2pi*((k+1)/12000)/.048),x=.6u-.8w.
                 f1499/1499.9/1500/1500.1/1501/2999/3000/3001Hz; independentf64Gram
                 yieldscoefficients.6/-.8,explained=sumx*x; candidatef32relativeerror<=5e-7.
                 Unrelatedcarrieroracle:same60480frames/trimmedsupport,f400/1000Hz,
                 t=(k+1)/12000,psi=.4sin(2pi*t/.048),u=cos(2pi*f*t+psi),w=sin(2pi*f*t+psi).
                 x=cos(2pi*(3000-f)*t-psi+.7),repeatwithx+.25u-.5w; float32storage.
                 Independentfullratescalar2x2Gramenergy; candidateerror<=5e-7*totalxenergy.
                 Unrelatedonlyfullratefraction<.001,stride4diagnostic>.999; latterMUSTNOT
                 determinegridordering. Mixedcoefficients/energyfollowindependentfullrateoracle.
                 Unfilteredstride4scoringnegativecontrolmustfail; unchangedgrids/caps/2286/14/recording/runtime/
                 cancellation/64MiBthresholds. Sameoracleappliestobothmodes' sharedfitkernel.
                 Planned Rust/decoderfixture suite bindings; no production encoder oracle. */
        }
        dependency ft4Case from ft4 to WstxRequirements::'TC-004-001';
        verification ft8 {
            subject decoder : AdvanceDecode;
            objective { verify WstxRequirements::'CL-007-01'; verify WstxRequirements::'CL-007-03'; verify WstxRequirements::'CL-007-04'; }
            doc /* FT8exactpayload/CRC/H/79tones/GFSKallfamilies+boundaries; strong36/40@-15,
                 weak20/40@-18; sameoverlapcounts; official>=12/14matches,22inheritedtexts
                 supplementaryonly. The shared known-wordfitkernel uses the SAME eight-frequency
                 FullrateGramoracle defined by ft4 above, with identical60480-frame phase/x formulas,
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
                 FT4bandlimitedblocksync/threemetrics andFT8bandlimitedsymbolsync/fivemetrics;
                 physicalhits/complexenvelopeSIC/rank77/64MiB.
                 No externaldecoder oracle or skipped case pass. */
        }
        dependency phaseLikelihoodCase from phaseLikelihoodAndScale to WstxRequirements::'TC-004-003';
        dependency rejectionCase from rejectionLifecycleResources to WstxRequirements::'TC-004-003';
    }
    verification ft8ArbitraryCarrierOffsets {
        subject decoder : AdvanceDecode;
        objective { verify WstxRequirements::'CL-007-01'; verify WstxRequirements::'CL-007-04'; }
        doc /* TC-004-002 uses the existing twenty independent frequency/start
             combinations, including lowest-tone carriers200.5/1000.3/3499Hz.
             These offsets need not be multiples of6.25Hz. Exact injected payloads
             and starts are the oracle; carrier error<=1Hz,start error<=240frames.
             No operator-supplied station frequency/start or new fixture is required.
             Executable trace:server/tests/decoder_signal.rs quality_corpus and
             fixtures/decoder/quality-cases.json Ft8/offset cases. No test verdict
             follows from this model or its semantic validation. */
    }
    dependency ft8ArbitraryCarrierCase from ft8ArbitraryCarrierOffsets
        to WstxRequirements::'TC-004-002';
    verification ft8PhysicalOracles {
        subject decoder : AdvanceDecode;
        objective { verify WstxRequirements::'CL-007-03'; verify WstxRequirements::'CL-007-04'; }
        doc /* Cost2WindowsPC, independentdirectDFTselectedbins,15/30sFFTdimensions,
             bandedges/centerbin/scaling/400Hzcandidate+2600Hzunrelatedcarrier.
             DFTerror<=1e-9*max(1,sumabsinput); basebandsample<=1e-8*max(1,inputRMS).
             Enumerate8/64/512tonechoicesusingindependentDecimal80coefficienttables,
             completeendgroups/sync/halfboundaries/GrayMSB; allfivefamilies/ties.
             Metric/normalizationerror<=1e-9*max(1,absexpected),finalf32LLR<=1ULP
             fromindependentlyroundedvalues. Zero/constant/nonfinitesigma/polaritycases.
             Directscalar4001tapconvolution/impulses/edges,selectedf32residualerror
             <=1e-7*max(1,sourcePeak); no circularwrap/outsideframewrites.
             HardCostas8/9,qualified256/257,failed-earlierword=>latermetric,atmost5FEC.
             Finalstarts29/30/31/89/90/91=>0/1/1/1/2/2basebandorigins,supportallowing;
             L=151680+31,s31=>clampedb0,no paddingclaim/canonicalstartstill31.
             All2286/38/14inputs/thresholdsunchanged; unsupportedtypedchannelvalidframes
             preserved. OfficialFT8>=12/14, no inventedgoldens. ActualFortranreference
             comparedwithfixedPCM/sourceSHA/settings/APprofile, everyextra/missingreported.
             No localFortrancompiler; source-builtreferenceartifactcomesfromGitHubActions.
             Thisverificationdefinitionisnotanexecutionverdict. */
    }
    dependency ft8PhysicalCase from ft8PhysicalOracles to WstxRequirements::'TC-004-002';
    dependency ft8PhysicalRejectionCase from ft8PhysicalOracles to WstxRequirements::'TC-004-003';

    verification ft4PhysicalOracles {
        subject decoder : AdvanceDecode;
        objective { verify WstxRequirements::'CL-007-03'; verify WstxRequirements::'CL-007-04'; }
        doc /* Cost2WindowsPC: independentdirectDFT/asymmetrictaper/bincenter/RMS,
             all4/16/256sequenceenumerations,206normalization/174extraction/Gray/polarity,
             last-familybitcopies; hardtone7/8 andhardsync19/20; first-ramp0/1/incomplete;Nuttall/scalarDFT/knownquartic/constant/zero/singular
             baselines/percentilehalfties/endpointslinear-after-division1.18andneighborbounds;
             TWOcompleteframespersamefrequencyreturnedthroughpluralfineinterface;
             qualifiedsupportoverlap60479/60480/60481,half-toneinclusiveedge,
             failedphysicalpointcannotexclude,strongerFECinvalidqualifiedpointstillholds
             exclusion,perpassreset,duplicatefinepoints,andfixedFT8asFT4wrongmode;
             trueframesmustnotdependontime-powermaxima;
             finalstarts8/9/10=>firstCostas32/33/33,reportedstartunchanged.
             SameexplicitFT8DFT/metric/f32tolerances; direct1401tapconvolution/no wrap/no
             secondrampoffset. Unchanged2286/38/14inputs andoriginalFT4quality/performance/
             falsepublication/cancel/typedpayloadthresholds. SourcebuiltFortrancomparison
             separatewithPCM/settings/depth/APidentity. No candidate-generatedgoldens. */
    }
    dependency ft4PhysicalCase from ft4PhysicalOracles to WstxRequirements::'TC-004-001';
    dependency ft4PhysicalRejectionCase from ft4PhysicalOracles to WstxRequirements::'TC-004-003';

}
