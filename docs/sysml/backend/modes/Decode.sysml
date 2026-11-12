package WstxModemDecode {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::AutomationState;
    private import WstxRequirements::'FR-003';
    private import WstxRequirements::'FR-004';
    private import WstxRequirements::'FR-018';
    private import WstxRequirements::'FR-019';
    private import WstxRequirements::'FR-021';
    private import WstxRequirements::'CL-007-01';
    private import WstxRequirements::'CL-007-02';
    private import WstxRequirements::'TC-004-004';
    private import WstxOfflineDecode::Mode;
    private import WstxOfflineDecode::ResultRecord;
    private import WstxRecordingReceive::DecodeJob;

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
        attribute recoveryInformationRank : Integer = 91;
        attribute fecIterations : Integer = 30;
        attribute recoverySums : Integer = 2;
        attribute subtractionPasses : Integer = 3;
        attribute subtractions : Integer = 200;
        attribute minFrequencyHz : Real = 200.0;
        attribute maxFrequencyHz : Real = 3500.0;
        attribute costasThreshold : Real = 2.0;
        attribute maxHardDisagreements : Integer = 36;
        attribute ft8PadBeforeFrames : Integer = 24000;
        attribute ft8PadAfterFrames : Integer = 7680;
        attribute weakSnrDb : Real = -25.0;
        attribute weakSnrMaxCostasHits : Integer = 10;
        attribute duplicateSubtractionSeparationHz : Real = 50.0;
        attribute dataPointSteps : Integer = 2;
        attribute dataPointTweakHz : Real = 0.5;
        attribute retrySeparationHz : Real = 50.0;
        doc /* maxHardDisagreements applies to FT8 only (ft8b); FT4 (ft4_decode) has none.
             #56 slice 3: costasThreshold 2.0 (was 2.7; jt9 sync8 syncmin 1.3 relative to its
             40th-percentile baseline admits these frames), subtractions 200 per window (was 32;
             jt9 subtracts every decode, MAX_EARLY 200). ft8Pad*, weakSnr* and
             duplicateSubtractionSeparationHz: see Ft8PaddedResidual and the aggregate.
             #56 slice 4: dataPoint* see Ft8DataPoint; retrySeparationHz see the aggregate
             (Ft8RetryOverlapped). */
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
             Require>=costasThreshold (2.0); zero-basedFT8sync0..6/36..42/72..78,FT4sync1..4/34..37/67..70/100..103.
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
             No gaps fabricated; the only padding is Ft8PaddedResidual's private zeros (#56).
             Allhistory/windows/residuals/FFTs inside64MiB. */
    }
    action def Ft8PaddedResidual {
        in source : ModemSampleWindow;
        out residual : Real[0..360000];
        doc /* #56 slice 3, after jt9 sync8 (lags -62..+62, DT -2.5..+2.5 s) and ft8b, which
             read symbols outside the buffer as zero. When L+24000+7680<=360000 the FT8
             worker-owned residual is 24000 zero frames (2.0 s), the L window frames, then
             7680 zero frames (0.64 s); otherwise no padding. Search, band limit, fine
             synchronization, metrics, channel decode, known-word fit and subtraction run on
             these padded coordinates exactly as on an unpadded window, so a frame that runs
             past either window edge (its missing symbols zero) is found, verified and
             subtracted like any other. It is published only when it starts no earlier than
             half a symbol (960 frames) before the window and ends no later than half a symbol
             after it; its reported canonical start is window origin + padded start - 24000,
             floored at 0, and its SNR is measured on the window frames at max(start, window
             start). A frame outside that tolerance is subtraction-only: never published,
             never a record. The padding is reset to zero after each pass's subtractions, so
             it never carries residual energy; the original window stays immutable. FT4 has
             no padding. */
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
        attribute channelIterationsPerFamily : Integer = 30;
        attribute recoverySumsPerFamily : Integer = 2;
        attribute hardDisagreementMax : Integer = 36;
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
             Actualmixedcenter=i0*df; everytrial/reportaccountsforit. L is the
             Ft8PaddedResidual length; frames may extend into its zero padding (#56), never
             beyond it. Sharedplanned/scalarRustFFT6.4.1,
             sameconventions/cacheowner; real/complex64transform/metric/convolutionsums
             overcanonicalfloat32input, finalLLRfloat32; allstoragewithin64MiB. */
    }
    action def Ft8FineSynchronization {
        in source : ModemSampleWindow;
        in coarseStartFrame : Integer;
        in coarseCarrierHz : Real;
        out fine : PhysicalFinePoint[0..1];
        doc /* CoarseCostasratio>=costasThreshold (2.0)/currentgrid/suppression/order unchanged.
             UseFt8BandLimit; P(b,d)=sumover21Costassymbolsabs(sumj0..31
             z[b+32*s+j]*exp(-i2pi*(tone_s/32+d/200)*j))Squared.
             Independentsymbolphases. Firstb=round(coarseStart/60)+[-10..10],d0;
             thenfrequencytweaks[-2.5..2.5]step.5atbestb; rebuildatbestcarrier;
             finalb=bestb+[-4..4],d0. Descendingpower,tiesascendingfrequency/start.
             Everypointcomplete151680framesinsidethe Ft8PaddedResidual/carrier200..3500inclusive.
             Outputcanonicalstart60*b includesramp,notGUI DT/UTC.
             FFT32eachsymbol,hardtone=largestabsbin0..7,tieslower;>=9/21Costashits.
             QualifyBEFORE256cap,257th=>searchLimited. Post-refinementcanonicalstarts:
             b=floor(s/60+.5),nonnegativehalftiesUP;clamp0..floor((L-151680)/60).
             RechecktoneevidenceatnearestCOMPLETEbasebandorigin/finalcarrier (zeros of Ft8PaddedResidual count as evidence of no tone).
             PRESERVEreportedcanonicalstart s; mappingonlyphysicalguardbeforepublication/SIC.
             NOcrosssymbol/blockfractiongateforFT8. */
    }
    action def Ft8DataPoint {
        in source : ModemSampleWindow;
        in fine : PhysicalFinePoint;
        out alternative : PhysicalFinePoint[0..1];
        doc /* #56 slice 4. Used only when no metric family (unassisted or CQ a-priori) of
             the fine point yields an accepted word. Over carriers fine+{-0.5,0,+0.5} Hz
             (dataPointTweakHz) and baseband origins b=fine/60+[-2..2] (dataPointSteps, 5 ms),
             each point complete inside the Ft8PaddedResidual and carrier 200..3500: Ft8BandLimit
             rows as for the metric families; energy = sum over the 79 symbols of the Costas
             symbol's known-tone power, or the data symbol's largest tone power. The highest
             energy wins; ties keep the first point in carrier-then-origin order. If it differs
             from the fine point, Ft8ObserveMetricFamilies runs once more there, physical gate
             included, and an accepted word continues from that point (known-word refinement,
             physical check, SNR, subtraction) exactly as a word of the fine point would.
             Rationale: the Costas-only sync power sees 21 of 79 symbols; next to an
             interferer it can settle just outside the region where the word decodes. ft8b
             has no such step; it only adds words, each under every later check. */
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
             No callsign/contact/semanticprior here; the only a-priori bits are the
             APrioriHypotheses passes. No currentFT4neighborlikelihoodapplies. */
    }
    item def APrioriContext {
        attribute myCall : Integer[0..29];
        attribute dxCall : Integer[0..29];
        attribute qsoProgress : Integer;
        attribute rxHz : Real;
        attribute txHz : Real;
        attribute cqOnly : Boolean;
        attribute apWidthHz : Real = 50.0;
        attribute lowConfidenceQuality : Real = 0.17;
        attribute cqOnlyAfterSeconds : Integer = 300;
        doc /* #56 slice 5. The station's a-priori context of one live decode window, set on
             the modem state before the window like its period start, so the decode set
             depends only on the window and this context (CL-057-02 in-order replay holds).
             myCall = payload bits 0..28 (c28 and /R flag) and dxCall = bits 29..57 of the
             standard message "MyCall DxCall RRR" packed from the selected profile callsign
             and the current contact's dx_call (WSJT-X ft8apset: i3=1 and an exact round
             trip required, else neither; without a DxCall the dummy KA1ABC packs MyCall and
             dxCall is absent). Deliberate departure: a nonstandard (compound) MyCall that
             ft8apset would pack hashed as <MyCall> gives no myCall here (types 1 only). qsoProgress = WSJT-X nQSOProgress from the contact state:
             calling/idle/cancelled 0, replying 1, report 2, roger_report 3, rogers 4,
             signoff/completed 5. rxHz/txHz = the contact Rx/Tx audio frequencies.
             cqOnly (lapcqonly) = for the last 300 s no contact tick saw the station
             transmitting, tuning or with Enable Tx on (WSJT-X m_dateTimeLastTX, refreshed
             while m_transmitting, m_auto or m_tune); true from start until then. A file decode has no
             myCall/dxCall (CQ hypothesis only). */
    }
    action def APrioriHypotheses {
        in context : APrioriContext;
        in families : PhysicalLlrFamily[0..5];
        in carrierHz : Real;
        out hypotheses : PhysicalLlrFamily[0..8];
        doc /* #56 slice 5, WSJT-X 3.3.0-beta5 ft8b/ft4_decode, ncontest=0. Tried only after
             every unassisted family of a candidate failed. Types: 1 CQ ??? ???, 2 MyCall ??? ???,
             3 MyCall DxCall ???, 4/5/6 MyCall DxCall RRR/73/RR73 (tails ir=0, grid 32402/
             32404/32403, i3=1). Types per qsoProgress (naptypes): FT8 0:[1,2] 1,2:[2,3]
             3,4:[3,4,5,6] 5:[3,1,2]; FT4 0:[1,2] 1,2:[2,3] 3,4:[3,6] 5:[3,1,2]; cqOnly:[1].
             Skipped: type>=2 without myCall; type>=3 without dxCall or when the carrier is
             more than apWidthHz from rxHz and (FT8 only) from txHz. Fixed bits: type1 bits
             0..28 = CQ token (c28=2, ipa=0); type2 0..28 = myCall; type3 0..57 = myCall,
             dxCall; types 4..6 all 77. FT8 types 1..3 also fix 74..76 to i3=1; FT4's do
             not, and FT4 fixed bits are scrambled with ft4XorMask. FT8: each type on the
             single then the triple family, fixed at 1.1 times that family's largest |LLR|;
             FT4: each type once on the quadruple family, fixed at 1.1 times the single
             family's largest |LLR|. Each through Ft8ChannelDecode with those bits fixed;
             first accepted wins. Acceptance: not all-zero, hard disagreements<=36 (both
             modes), a payload that unpacks with status decoded (WSJT-X drops an a-priori word
             that does not unpack and tries the next pass), and, for every type except FT8
             type 1, WSJT-X's confidence
             qual = 1-(nharderrors+dmin)/60 >= lowConfidenceQuality, dmin = sum of |LLR|
             over the bits the word disagrees with. Deliberate departure: WSJT-X publishes a
             low-confidence a-priori word marked '?' (and FT4 any hard-error count); the
             station acts on decoded rows, so it does not publish one. FT8 type 1 keeps the
             slice-2 acceptance (hard disagreements<=36). The published record carries the
             type as a_priori (WSJT-X aN); an unassisted word has no a_priori key. */
    }
    action def Ft8DecodeMetricFamilies {
        in families : PhysicalLlrFamily[5];
        out accepted : Boolean;
        out channelWord : Integer[174];
        out payload77 : Integer[77];
        doc /* Fiveorderedfamilies, each through Ft8ChannelDecode. Accept a word with
             hard disagreements (nharderrors)<=36 that is not the all-zero codeword (ft8b,
             #56); publishedH+CRCmandatory. Avalidwordfailingacceptance
             DOESNOTstoplaterfamilies. Firstacceptedwordwins. Only when all five fail, two
             the APrioriHypotheses passes of the window's APrioriContext run (#56 slices 2 and 5);
             no further fallback decode. An a-priori word's record carries a_priori (1..6);
             UDP Low confidence stays false because a low-confidence a-priori word is never
             published.
             Unsupported/invalidsourceinterpretationremainstypedobservation,notdropfilter.
             Sameworker,cancel/servicecheckpoints<=50ms,terminalrelease<=250ms. */
    }
    action def Ft8ChannelDecode {
        in llrZeroPositive : Real[174];
        out channelWord : Integer[174];
        out hardDisagreements : Integer;
        doc /* Adapted WSJT-X decode174_91 (maxosd=2, norder=2) and osd174_91 (Keff=91,
             ndeep=2), shared by FT8 and FT4 (#56). Sum-product belief propagation, flooding
             schedule: check message 2*platanh(product of tanh(extrinsic/2)), WSJT-X
             piecewise-linear platanh saturating at 7. Iterations 0..30; a word whose syndrome and CRC are zero ends it;
             stop early after iteration>=10 when unsatisfied checks>15 did not decrease for 5
             iterations. Keep the cumulative bit sums of iterations 1 and 2. On BP failure
             run ordered statistics on each kept sum in turn: order the 174 bits by
             decreasing |sum| (ties in reverse index order), Gaussian-eliminate the systematic
             (174,91) generator with whole-row operations (CRC bits free; the pivot of
             position id is searched in positions id..110, i.e. within the first k+20), re-encode the hard decisions of
             the 91 most reliable bits, then try every single (pair) flip of them whose
             re-encoded first 40 parity bits differ from the hard decisions in at most 9 (8)
             places; keep the candidate of least reliability-weighted distance. The result
             must pass H and CRC. hardDisagreements counts bits that disagree with the
             channel LLR signs (BP word) or with the kept sum's hard decisions (OSD word).
             Deliberate deviations: tanh by a rational approximant within 1e-4; an OSD word
             with zero disagreements is accepted (decode174_91 requires >0); every word
             must pass H and CRC (WSJT-X checks CRC only).
             A-priori (fixed) bits keep their channel LLR in BP and are never flipped.
             Cancellation is checked every BP iteration and every OSD flip position. */
    }
    action def Ft8SubtractVerifiedFrame {
        in source : ModemSampleWindow;
        in point : PhysicalFinePoint;
        in reference : ComplexBasebandCoefficient[151680];
        out residual : ModemSampleWindow;
        doc /* Adaptedsubtractft8, boundedCENTEREDzerobasedproductdefinition:
             c[k]=x[start+k]*conj(reference[k]),zerooutsideframe;
             h[j]=cos(pi*j/4000)^2/sum[a=-2000..2000]cos(pi*a/4000)^2,j=-2000..2000.
             y[k]=sumj h[j]*c[k-j], exact linear (zero outside frame): with
             h~(1+cos(pi*j/2000))/2, y = constant plus two cosine-modulated window
             sums of exact prefix sums, O(frame) per subtraction, no FFT padding (#47).
             One sweep keeps the prefix sums 2000+1 frames ahead in a ring of at least
             2*2000+2 entries; every window sum uses the same exact prefix values (#57).
             Atedge-distancea0..2000 dividebyavailableweight sumj[-2000..a]h[j].
             Subtract2*Re(reference[k]*y[k])ONLYwithinframe; originalsourceimmutable.
             <=3passes/200verifiedsubtractions, invalidatepassFFTafterresidualchanges.
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
             Threeorderedfamilies, each through Ft8ChannelDecode; accept any word that is
             not the all-zero codeword (ft4_decode has no hard-disagreement cap), H+CRC.
             Failedwordcontinues;
             no4thfallback except the APrioriHypotheses passes (#56 slice 5).
             Sourceunsupported/invalidstatusretained, no semanticprior. */
    }
    action def Ft4SubtractVerifiedFrame {
        in source : ModemSampleWindow;
        in point : PhysicalFinePoint;
        in reference : ComplexBasebandCoefficient[60480];
        out residual : ModemSampleWindow;
        doc /* Sameboundedcomplex-envelopeoperationasFt8SubtractVerifiedFrame,
             h[j]=cos(pi*j/1400)^2/sum[-700..700]cos(pi*j/1400)^2,j[-700..700],1401taps.
             Centeredlinearconvolution (same exact prefix-sum window sums, R700),
             NOedgeavailabilitycorrection.
             Referenceincludesramp,alreadycanonicalorigin,NOsecond-576frameadjustment.
             Originalsamplesimmutable,3passes/200verifiedsubtractions,passFFTinvalidated.
             Sharedpurewaveform/measurement/FFT/cancelownership,within64MiB. */
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
             The modem reads no UTC.
             FT8coarseN1920/hop480/half-tone200..3500inclusive/endpoints;FT4N576/hop144
             noisegridseparatefromFt4FrequencyCandidates/Ft4BandLimitAndFineSync.
             FT8BandLimit/FineSynchronization/ObserveMetricFamilies/DecodeMetricFamilies;
             FT4BandLimitAndFineSync/ObserveMetricFamilies. Qualifiedcap256,257=>limited.
             FiveFT8orthreeFT4families; each Ft8ChannelDecode (BP<=30 + OSD ndeep2 on
             2 sums, rank91). FT8 hard disagreements<=36; never all-zero; H+CRC mandatory.
             APrioriHypotheses passes only (CQ, MyCall/DxCall per QSO state), no other hints/semanticdrop; physicalsyncguardsatfinalreportedcoordinates.
             Sharedfullrateknownword3gridmeasurement,mode-specificcomplexenvelopeSIC,
             <=3passes/200verifiedsubtractions; originalsimmutable/no weakrelativeenergystop.
             The last pass's verified frames are not subtracted: no later pass reads that
             residual (#57).
             SharedFFT/bandlimit/finesync/bitmetrics/channel/convolutionboundary,modeparameters;
             onecurrentmode/windowplan/scratchcache andcurrentpassFFT,droponepochreset;
             no globalmutablecommonblocks; residualchangeinvalidatesFFT.
             SharedRustFFT6.4.1planned/scalar/oneworker(itsparallelstagethreads:CL-057-02)/noqueue/source/cancelquanta<=50ms,
             serviceconversion/spectrum betweenquanta,release<=250ms. Allplans/grids/scratch
             within64MiB. Onepurewaveformowner7/futurereuse9,noTXauthority.
             Displayfixed0..3000Hzindependentofdecode200..3500; no sharedmodem/displayFFTplan.
             Dedupmode/payload/startwithinhalfsymbol,retainlaterrepeatedtransmissions.
             Within a window (#56 slice 3) a verified word whose payload and start (within half
             a symbol) repeat an earlier word of the window is skipped when its carrier is
             within 50 Hz of that word's; on a carrier more than 50 Hz away it is subtracted
             like ft8b (which subtracts before ft8_decode drops the duplicate message) but
             publication still follows the history dedup above, so it is not published twice.
             ft8b weak-word guard (nsync<=10 and xsnr<-25): an FT8 word whose final point has
             at most 10 of 21 hard Costas hits and whose unfloored MeasureFrame SNR is below
             -25 dB is rejected before the window's duplicate record, publication and
             subtraction. Deliberate deviation: ft8b subtracts such a word before rejecting
             it; the station does not. The guard needs a measured SNR, so it does not apply
             to a subtraction-only partial frame or a word without an SNR (carrier outside
             the baseline band, no baseline). FT8 frames run on Ft8PaddedResidual coordinates.
             Ft8RetryOverlapped (#56 slice 4): an FT8 candidate of a pass whose verification
             yields no word (Ft8DataPoint included) and which a frame subtracted in that pass
             overlaps (carriers within retrySeparationHz 50 Hz, starts less than one frame
             apart) is qualified again (Ft8FineSynchronization from its fine point) on the next
             pass's residual and, if it qualifies and no candidate of that pass lies within
             1 Hz and 120 frames of it, appended in order after the pass's own candidates; the
             256 cap counts it. Requalification runs in parallel and is replayed in order, so
             the decode set stays independent of the thread count (CL-057-02).
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
             SNR on the WSJT-X 2500 Hz scale (#52), whole dB (round half away from zero).
             FT8 = ft8b xsnr2 as WSJT-X first reports it, from its early period buffer: the
             frame's period starts at the UTC period start when the receive clock
             establishes it (finite decodes: frame 0 + k*180000), else 0.5 s before the
             frame on a 0.5 s window grid; only that period's first 41*3456 frames are
             seen, later ones as zero. One baseline per period and pass serves its frames.
             xsig = sum over the 79 symbols of |1920-frame DFT at the decoded tone|^2/60
             (ft8_downsample's 32-point power); xbase = 1e-4 * the sync8 baseline at bin
             round(f/3.125 Hz): sum of the 92 Nuttall 3840-frame power spectra stepped 1920
             (window scaled to sum 12.8), in dB, quartic fit to the 10th-percentile lower
             envelope of 10 segments over 200..4000 Hz, +0.65 dB. SNR = 10log10(a)-27 with
             a = xsig/xbase/3e6-1 when > 0.1, else 0.001; floor -25.
             FT4 = ft4_decode: the pass's getcandidates4 contrast c (15-bin mean of the
             average spectrum over its ft4_baseline) at the largest of the 3 bins nearest
             decoded frequency+31.25 Hz, parabola-interpolated when a local maximum;
             10log10(c-1)-14.8, -21 when c <= 1, floor -21.
             No baseline or nonfinite => null; ceiling +60.
             Error<=240frames/1HzFT8,144frames/3HzFT4,<=3dBisolatedAWGN>=-15/-10.
             Known-codeword fit3fixedgrids:df1=6000/waveformFrames; stage1time+-N/4stepN/16,
             freq+-spacing/2stepdf1 includingoffgridendpoints; stage2time+-N/16stepmax(1,floor(N/128)),
             freq+-df1/2stepdf1/8; stage3time+-max(1,floor(N/128))step1,frequencyfixed.
             Complete/in-band only,EVERYsamptrimN/2ends. Actualfullratereal/quadratureGramG,
             b=[u.x,w.x],maximizeb^T*inverse(G)*b,tiesfreq/time. Rejectnonfiniteorrelative
             determinant<=1e-12; noquadratureorthogonalityassumption. Nounfilteredsubsampling:
              unrelatedcarriersmustnotaliasintocandidatequadratures. Samegridcoordinates/order
              andcandidate/pass/subtraction/FECcaps.
             Grid pruning (#47): each stage ranks its grid points by the decimated
             correlation with the current-pass candidate baseband (the band-limited
             transform of physical sync: carriers outside the band are filtered, never
             aliased), and scores only the 6/3/2 best-ranked points of stages 1/2/3 with
             the full-rate Gram above; the result is the full-rate maximum among them under
             the same tie rule. Without a candidate band every grid point is scored.
             finalamplitude/subtractionallsamples. No whole-frame phase rejection,
             ordinary+-2Hz/min drift andarbitraryinitialphase remaineligible.
             No dBFS/noiseless/crowded reference-SNR inference. */
    }
    action advanceDecode : AdvanceDecode;
    action measureFrame : MeasureFrame;
    satisfy 'CL-007-03' by measureFrame;
    satisfy 'CL-007-04' by advanceDecode;
    dependency calculationOwner from advanceDecode to WstxArchitecture::physicalStation::backend::stations::modes;
    dependency measurementOwner from measureFrame to WstxArchitecture::physicalStation::backend::stations::modes;
    package IndependentVerification {
        doc /* Verification intent; executable coverage is declared in WstxRequirements metadata. Cost2
             offlineWindowsPC, actualcandidate
             Rust/server/browser and independent fixtures/directmath/recordings/link model.
             No hardware/live service. Source and source_message are not decoded inversehashes.
             Missing/empty manifests fail. WstxRequirements retains the independent case expectations.
             Corpus2286:2000noise+160AWGN+80overlap+40offset+6silence/mismatch/CRCnegative;
             fieldboundary and supportedfamily vectors additional. Actual execution not claimed. */
        verification ft4 {
            subject decoder : AdvanceDecode;
            objective { verify WstxRequirements::'CL-007-01'; verify 'CL-007-03'; verify 'CL-007-04'; }
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
                 Rust/decoderfixture bindings are declared in WstxRequirements; no production encoder oracle. */
        }
        dependency ft4Case from ft4 to 'TC-004-001';
        verification ft8 {
            subject decoder : AdvanceDecode;
            objective { verify WstxRequirements::'CL-007-01'; verify 'CL-007-03'; verify 'CL-007-04'; }
            doc /* FT8exactpayload/CRC/H/79tones/GFSKallfamilies+boundaries; strong36/40@-15,
                 weak20/40@-18; sameoverlapcounts; official>=12/14matches,22inheritedtexts
                 supplementaryonly. The shared known-wordfitkernel uses the SAME eight-frequency
                 FullrateGramoracle defined by ft4 above, with identical60480-frame phase/x formulas,
                 expectedcoefficients.6/-.8 andexplained=sumx*x within5e-7f32relativeerror.
                 Error240frames/1Hz,3dBstrongAWGN. Valid/RandTUvectors
                 retainedpositivesdespitereferencenondetection; no qualityscopeweakening. */
        }
        dependency ft8Case from ft8 to 'TC-004-002';
        verification rejectionLifecycleResources {
            subject decoder : AdvanceDecode;
            objective { verify WstxRequirements::'CL-007-02'; verify 'CL-007-04'; }
            doc /* 1000noise/modefourRMSplusinvalid/wrongmode/silence/goodFECbadCRC require
                 zeropublishedframes. Unsupported/invalidonlyinjectedvalidCRCframes, nopanic.
                 Repeatpayloadmultiset,time<=1frame,freq<=.2HzFT8/.5HzFT4. Cancelallphases,
                 stale/restart/busy/limits/strictHTTP/realbrowser/twopeer<=2sstatus (no 32 kbit/s link, #80).
                 OneCPUworker(onedecodethread;defaultthreadcount:CL-057-02):15sFT8<=5s,7.5sFT4<=3s,120s<=40s,cold+<=2s; tenruns+warmup,
                 actualreferencePC HB9BLA(AMDRyzen9 3900X,32GB,Windows11)
                 OS/build/power/hash/workload/min/median/p95/max/memory;
                 fourprofiles<=2xruntime,64MiBworker/96MiBprocessdelta,<=250msrelease.
                 Futurejoint48kcapture+FFT+decode provesfairness, notlargerringassumption.
                 Rust/fixture/HTTP/browser/link bindings are declared in WstxRequirements; no execution verdict. */
        }
        verification phaseLikelihoodAndScale {
            subject decoder : AdvanceDecode;
            objective { verify WstxRequirements::'CL-007-01'; verify 'CL-007-03'; verify 'CL-007-04'; }
            doc /* Independent additional recipes:phase.7/pi/2,drift+-1/30Hz/s,canonicalgains1e-4/8,
                 secondstation80dBbelowstronger with sub-PCM16-quantumamplitude andfloatrepeat;
                 retainbothmessages. Quantizationresiduals afterindependent best-fit subtraction:
                 q=round(x*32767)/32768,unitreal/90degreeu,w,fullsupport2x2Gramfit[a,b],
                 r=q-a*u-b*w beforegain/floatstorage. Innerproducts<=128epsilon64*sqrt(max(u.u,w.w)*q.q)
                 beforestorage,<=4epsilon32*sqrt(max(u.u,w.w)*rStored.rStored)afterward.
                 Finitecaserequireszeropublications,no search_limited,neverproductionhelpers.
                 All2286originalcases/thresholds/256cap remain. Verifyrecipe/composer/audiohashes,
                 FT4bandlimitedblocksync/threemetrics andFT8bandlimitedsymbolsync/fivemetrics;
                 physicalhits/complexenvelopeSIC/rank91/64MiB.
                 No externaldecoder oracle or skipped case pass. */
        }
        dependency phaseLikelihoodCase from phaseLikelihoodAndScale to 'TC-004-003';
        dependency rejectionCase from rejectionLifecycleResources to 'TC-004-003';
    }
    verification ft8ArbitraryCarrierOffsets {
        subject decoder : AdvanceDecode;
        objective { verify WstxRequirements::'CL-007-01'; verify 'CL-007-04'; }
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
        to 'TC-004-002';
    verification ft8PhysicalOracles {
        subject decoder : AdvanceDecode;
        objective { verify 'CL-007-03'; verify 'CL-007-04'; }
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
    dependency ft8PhysicalCase from ft8PhysicalOracles to 'TC-004-002';
    dependency ft8PhysicalRejectionCase from ft8PhysicalOracles to 'TC-004-003';

    verification ft4PhysicalOracles {
        subject decoder : AdvanceDecode;
        objective { verify 'CL-007-03'; verify 'CL-007-04'; }
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
    dependency ft4PhysicalCase from ft4PhysicalOracles to 'TC-004-001';
    dependency ft4PhysicalRejectionCase from ft4PhysicalOracles to 'TC-004-003';

    package SimulatedReferenceFixtures {
        attribute def SimulatorFixture {
            attribute identity : String;
            attribute finalWavFilename : String;
            attribute mode : String;
            attribute scenario : String;
            attribute messageText : String;
            attribute carrierHz : Real;
            attribute nominalDtSeconds : Real = 0.125;
            attribute sampleRateHz : Integer = 12000;
            attribute channels : Integer = 1;
            attribute pcmBits : Integer = 16;
            attribute frames : Integer;
            attribute snrArgumentDb2500 : Real;
            attribute fadingSpreadHz : Real;
            attribute pathDelayMs : Real;
            attribute exposesSeedControl : Boolean = false;
            attribute freezesGeneratedBytes : Boolean = true;
        }
        attribute sim18_ft8_clean : SimulatorFixture {
            :>> identity = "SIM18-FT8-CLEAN";
            :>> finalWavFilename = "SIM18-FT8-CLEAN.wav";
            :>> mode = "ft8";
            :>> scenario = "clean";
            :>> messageText = "CQ K1ABC FN42";
            :>> carrierHz = 1000.3;
            :>> frames = 180000;
            :>> snrArgumentDb2500 = 99.0;
            :>> fadingSpreadHz = 0.0;
            :>> pathDelayMs = 0.0;
        }
        attribute sim18_ft8_weak : SimulatorFixture {
            :>> identity = "SIM18-FT8-WEAK";
            :>> finalWavFilename = "SIM18-FT8-WEAK.wav";
            :>> mode = "ft8";
            :>> scenario = "weak";
            :>> messageText = "CQ W1AW FN31";
            :>> carrierHz = 1499.7;
            :>> frames = 180000;
            :>> snrArgumentDb2500 = -15.0;
            :>> fadingSpreadHz = 0.0;
            :>> pathDelayMs = 0.0;
        }
        attribute sim18_ft8_fading : SimulatorFixture {
            :>> identity = "SIM18-FT8-FADING";
            :>> finalWavFilename = "SIM18-FT8-FADING.wav";
            :>> mode = "ft8";
            :>> scenario = "fading";
            :>> messageText = "K1ABC W9XYZ -10";
            :>> carrierHz = 1800.5;
            :>> frames = 180000;
            :>> snrArgumentDb2500 = -10.0;
            :>> fadingSpreadHz = 0.5;
            :>> pathDelayMs = 1.0;
        }
        attribute sim18_ft8_overlap : SimulatorFixture {
            :>> identity = "SIM18-FT8-OVERLAP";
            :>> finalWavFilename = "SIM18-FT8-OVERLAP.wav";
            :>> mode = "ft8";
            :>> scenario = "overlap";
            :>> messageText = "CQ K1ABC FN42";
            :>> carrierHz = 1000.3;
            :>> frames = 180000;
            :>> snrArgumentDb2500 = 99.0;
            :>> fadingSpreadHz = 0.0;
            :>> pathDelayMs = 0.0;
            attribute overlapDetails : ControlledOverlap {
                :>> secondCarrierHz = 1006.55;
            }
        }
        attribute sim18_ft4_clean : SimulatorFixture {
            :>> identity = "SIM18-FT4-CLEAN";
            :>> finalWavFilename = "SIM18-FT4-CLEAN.wav";
            :>> mode = "ft4";
            :>> scenario = "clean";
            :>> messageText = "CQ K1ABC FN42";
            :>> carrierHz = 1000.3;
            :>> frames = 72576;
            :>> snrArgumentDb2500 = 99.0;
            :>> fadingSpreadHz = 0.0;
            :>> pathDelayMs = 0.0;
        }
        attribute sim18_ft4_weak : SimulatorFixture {
            :>> identity = "SIM18-FT4-WEAK";
            :>> finalWavFilename = "SIM18-FT4-WEAK.wav";
            :>> mode = "ft4";
            :>> scenario = "weak";
            :>> messageText = "CQ W1AW FN31";
            :>> carrierHz = 1499.7;
            :>> frames = 72576;
            :>> snrArgumentDb2500 = -10.0;
            :>> fadingSpreadHz = 0.0;
            :>> pathDelayMs = 0.0;
        }
        attribute sim18_ft4_fading : SimulatorFixture {
            :>> identity = "SIM18-FT4-FADING";
            :>> finalWavFilename = "SIM18-FT4-FADING.wav";
            :>> mode = "ft4";
            :>> scenario = "fading";
            :>> messageText = "K1ABC W9XYZ -10";
            :>> carrierHz = 1800.5;
            :>> frames = 72576;
            :>> snrArgumentDb2500 = -5.0;
            :>> fadingSpreadHz = 0.5;
            :>> pathDelayMs = 1.0;
        }
        attribute sim18_ft4_overlap : SimulatorFixture {
            :>> identity = "SIM18-FT4-OVERLAP";
            :>> finalWavFilename = "SIM18-FT4-OVERLAP.wav";
            :>> mode = "ft4";
            :>> scenario = "overlap";
            :>> messageText = "CQ K1ABC FN42";
            :>> carrierHz = 1000.3;
            :>> frames = 72576;
            :>> snrArgumentDb2500 = 99.0;
            :>> fadingSpreadHz = 0.0;
            :>> pathDelayMs = 0.0;
            attribute overlapDetails : ControlledOverlap {
                :>> secondCarrierHz = 1021.1333333333333;
            }
        }
        attribute def ControlledOverlap {
            attribute secondCarrierHz : Real;
            attribute secondMessage : String = "CQ W1AW FN31";
            attribute strongGain : Real = 0.25;
            attribute weakGain : Real = 0.12529680840681806;
            attribute gainDifferenceDb : Real = 6.0;
            attribute rejectsClipping : Boolean = true;
            attribute saturates : Boolean = false;
            doc /* Mix two emitted noise-free PCM16 components in float64 after
                 division by32768, y=.25*x1+weakGain*x2, then
                 q=round_ties_even(32768*y). Rejectq outside[-32768,32767]; write
                 admittedq as signedlittle-endianPCM16. Retain component
                 and final hashes. Strong/weak labels describe selected gain ratio,
                 not a measured RF SNR. Preserve complete original supports. */
        }
        action def AdmitFinalWavFilename {
            in declaredFixture : SimulatorFixture;
            in suppliedFilename : String;
            out admitted : Boolean;
            assert constraint exactDeclaredFilename {
                admitted == (suppliedFilename == declaredFixture.finalWavFilename)
            }
            doc /* CL-007-03; TC-004-003. declaredFixture is selected only after
                 immutable mode declaration identity/settings validation. Each fixed
                 finalWavFilename is identity followed by literal .wav. Compare the
                 supplied string literally before reading the final WAV; do not
                 resolve or normalize an alternate spelling into admission. False
                 yields ValueError and no final-WAV read. Absolute and ../ names
                 remain false even when their target PCM/hash/metadata is valid.
                 Manifest/declaration/oracle reads are distinct from final-WAV reads.
                 Historical command/cwd provenance never authorizes another input. */
        }
        verification simulatorFixtureIntegrity {
            subject decoder : AdvanceDecode;
            objective { verify 'CL-007-03'; }
            doc /* Existing TC-004-001/002 simulator subcases: eight admitted
                 12k mono PCM16 files, exact lengths/hashes, declared-vs-emitted
                 message/canonical77bits/79or103tones independently checked. Retain
                 FT4 legacy emitted scrambled77 separately; canonical77 is obtained
                 with the pinned FT4 XOR mask, not relabeled as emitted. Unknown PRNG
                 seed stays unknown; immutable bytes define each retained realization.
                 DT argument is NOT raw ramp origin or GUI DT. Inspect circular-shift
                 boundary artifacts and reject clipping; do not trim/pad/normalize.
                 Clean single-station messages recover exactly; weak/fading/overlap
                 misses and extras remain observations, never replacement goldens.
                 APoff FT8 and FT4 Fast reference, search200..3500, exact same PCM.
                 Cost2 Windows PC, no radio; hosted simulator build only if needed. */
        }
        verification simulatorFixtureRefusals {
            subject decoder : AdvanceDecode;
            objective { verify 'CL-007-03'; verify 'CL-007-04'; }
            doc /* TC-004-003: independently malformed/hash-mismatched/truncated
                 metadata, invalid format/length, nonfinite mixture and clipping
                 are refused. In a disposable valid copied mode dataset, keep all
                 metadata/hash/bytes fixed and change only one final-WAV filename:
                 the declared SIM18-FT8-CLEAN.wav or SIM18-FT4-CLEAN.wav is admitted;
                 an absolute path to the valid WAV and ../ plus that basename with
                 a byte-identical parent file both yield ValueError before any
                 final-WAV reader call. A reader spy distinguishes refusal from
                 missing-file/hash/format failure. Expected results come from the
                 literal filename contract, never decoder output. Automated cost 2
                 on Windows PC, no radio; clean only disposable test copies. Wrong expected content is not repaired from Rust
                 output. Existing quality/noise/runtime/cancel limits are unchanged. */
        }
        verification simulatorFixtureProvenance {
            subject decoder : AdvanceDecode;
            objective { verify 'CL-007-03'; }
            doc /* TC-004-002 provenance subcase, cost 2 offline artifact review on
                 Windows PC. Compare supplied package inventory with provenance:
                 FT8 includes build-ft8sim.log, cmake-version.txt,
                 gfortran-version.txt, source-revision.txt, COPYING and AUTHORS.
                 Do not claim absent header/source/CMake source files accompany
                 the FT8 directory. Pinned corresponding-source URLs remain links,
                 not evidence that bytes are bundled. Repair wording only; preserve
                 generation inputs, frozen PCM, manifest truth and comparisons. */
        }
        dependency simulatorProvenanceCase from simulatorFixtureProvenance to 'TC-004-002';
        dependency ft4SimulatorCases from simulatorFixtureIntegrity to 'TC-004-001';
        dependency ft8SimulatorCases from simulatorFixtureIntegrity to 'TC-004-002';
        dependency simulatorRefusalCases from simulatorFixtureRefusals to 'TC-004-003';
    }

    requirement 'CL-007-03' {
        doc /* Each mode MUST satisfy independent payload/channel/waveform oracles; reference decoder output alone MUST NOT define exhaustive truth or make a hash reversible. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/decoder/mod.rs; server/src/receive.rs; client/recording.js";
    }
    dependency CL_007_03_to_FR_003 from 'CL-007-03' to 'FR-003';
    dependency CL_007_03_to_FR_004 from 'CL-007-03' to 'FR-004';
    dependency CL_007_03_to_FR_018 from 'CL-007-03' to 'FR-018';
    requirement 'CL-007-04' {
        doc /* CPU-only decoding MUST meet the per-mode quality, rejection, runtime, memory, repeatability, cancellation and link budgets below, with explicit bounded-work failure. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/decoder/mod.rs; server/src/receive.rs; client/recording.js";
    }
    dependency CL_007_04_to_FR_003 from 'CL-007-04' to 'FR-003';
    dependency CL_007_04_to_FR_004 from 'CL-007-04' to 'FR-004';
    dependency CL_007_04_to_FR_019 from 'CL-007-04' to 'FR-019';
    dependency CL_007_04_to_FR_021 from 'CL-007-04' to 'FR-021';
    verification 'TC-004-001' {
        doc /* TC-004-001 — Offline FT4
             FR-003, FR-004, FR-018; CL-007-01, CL-007-02, CL-007-03, CL-007-04
             Load independently labelled FT4 recordings, select FT4 and run the candidate decoder. Include the selected message variants and controlled signal conditions.
             Decoded fields agree with the independently established expected results; misses, incorrect decodes and runtime meet the agreed FT4 budgets.
             SNR (#52): every decoded observation of the pinned modern FT4 recording reports a whole-dB SNR within 1 dB of the pinned reference jt9 report in recording-baselines.json; every corpus SNR is a whole dB at or above -21.
             A-priori decoding (#56 slice 5, WstxModemDecode::APrioriHypotheses): in FT4 a weak CQ decodes through type 1 without context and a weak HB9BLA K1ABC RR73 through type 6 only with the right calls.
             2 — Isolated automated tests; Windows PC, offline fixtures and real candidate server/browser. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-007-01';
            verify 'CL-007-02';
            verify 'CL-007-03';
            verify 'CL-007-04';
            verify 'FR-003';
            verify 'FR-004';
            verify 'FR-018';
        }
        attribute executable : String = "server/tests/decoder_signal.rs::independent_waveforms_decode; server/tests/decoder_signal.rs::quality_corpus; server/tests/decoder_signal.rs::official_modern_recording_baselines; server/src/decoder/search_test.rs::ft4_a_priori_recovers_weak_cq_and_qso_words";
    }
    verification 'TC-004-002' {
        doc /* TC-004-002 — Offline FT8
             FR-003, FR-004, FR-018; CL-007-01, CL-007-02, CL-007-03, CL-007-04
             Load independently labelled FT8 recordings, select FT8 and run the candidate decoder under the selected signal conditions.
             Decoded fields agree with the independently established expected results; misses, incorrect decodes and runtime meet the agreed FT8 budgets.
             Recorded corpus (22 FT8 recordings, the official FT8 and the modern FT4 recording, #56): the decoder finds at least the pinned number of the 409 complete-frame decodes of WSJT-X 3.3.0-beta5 jt9 -8/-5 -d 3 (fixtures/decoder/jt9-deep-reference.json; same text, carrier within 5 Hz, or, for the one pinned case PA3EPP SP8NFO KN09 in 191111_110615, the same text on another carrier of the period: the station publishes the +23 dB 906 Hz signal, jt9 its 1056 Hz image, each publishing a message once per period, the first copy its own order verifies); jt9 is a lower bound, not exhaustive truth. A strong FT8 frame that began before the window, or runs past its end, masks a weak complete frame on the same carrier: the weak frame decodes and the partial frame is never published; a frame starting at most half a symbol before the window is published at start 0, one starting earlier is not (#56 Ft8PaddedResidual). The same word on a carrier more than 50 Hz away is published once and subtracted, so a weak frame under the second copy decodes. The weak-word guard rejects exactly an FT8 word with at most 10 Costas hits and a measured SNR below -25 dB. A weak word that fails at its fine point decodes at the nearby data point (#56 slice 4 Ft8DataPoint). A failed FT8 candidate overlapped by a frame subtracted in the same pass is qualified again on the next pass (Ft8RetryOverlapped); its evidence is the parity count (WA2FZW DL5AXX RR73 in the official recording is found only through it), not a dedicated synthetic test. A-priori decoding (#56 slice 5, WstxModemDecode::APrioriHypotheses): the type table per QSO state, lapcqonly, MyCall/DxCall availability and the 50 Hz Rx/Tx width match WSJT-X; the fixed bits are the packed message bits (FT4 scrambled); in FT8 a weak synthetic HB9BLA K1ABC FN42 (report state, type 3 at its true point) and HB9BLA K1ABC RR73 (rogers state, type 6 at its true point) below the unassisted limit decode only with the right MyCall, DxCall, state and Rx/Tx, and the full decode publishes them with an a_priori type of the state (2..the expected one); a wrong DxCall in every state, FT8 and FT4, over many seeds and levels never yields a word other than the transmitted one, and noise none; an a-priori word is published only with a decoded payload and at WSJT-X confidence qual >= 0.17 (except FT8 type 1); the live station sets MyCall, DxCall, state and Rx/Tx from the profile and the current contact, and cq-only until Enable Tx is on and again 300 s after it went off. The mode-independent evidence, the confidence boundary (server/src/decoder/apriori_test.rs::low_confidence_boundary) and the live station context (server/src/contact_http_tests.rs::a_priori_context_follows_profile_and_contact), is traced by its Proves tags, not bound here (CL-007-03: each mode case binds only tests that select its mode).
             SNR (#52): every decoded observation of the pinned official FT8 recording reports a whole-dB SNR within 1 dB of the pinned reference jt9 report in recording-baselines.json; every corpus SNR is a whole dB at or above -25. Through the live worker with a correlated UTC clock, the published SNR of a synthetic FT8 period (louder noise in its first 0.25 s and before it) equals the file decode of the same period-aligned audio.
             2 — Isolated automated tests; Windows PC, offline fixtures and real candidate server/browser. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-007-01';
            verify 'CL-007-02';
            verify 'CL-007-03';
            verify 'CL-007-04';
            verify 'FR-003';
            verify 'FR-004';
            verify 'FR-018';
        }
        attribute executable : String = "server/tests/decoder_signal.rs::quality_corpus; server/tests/decoder_signal.rs::independent_waveforms_decode; server/tests/decoder_signal.rs::crc_valid_unsupported_and_invalid_payloads_are_retained; server/tests/decoder_signal.rs::official_modern_recording_baselines; server/src/recording_tests.rs::live_ft8_snr_measures_from_the_utc_period_start; server/tests/decoder_signal.rs::recorded_corpus_reaches_jt9_deep_decodes; server/src/decoder/bitmetrics_test.rs::cq_a_priori_bits_recover_a_buried_cq_word; server/src/decoder/search_test.rs::partial_frame_interferer_is_subtracted_not_published; server/src/decoder/search_test.rs::frame_past_the_window_end_is_subtracted_not_published; server/src/decoder/search_test.rs::half_symbol_publication_boundary; server/src/decoder/search_test.rs::duplicate_on_a_distant_carrier_is_subtracted_and_published_once; server/src/decoder/search_test.rs::weak_word_guard_boundaries; server/src/decoder/search_test.rs::failed_fine_point_retries_at_the_data_point; server/src/decoder/apriori_test.rs::a_priori_types_follow_the_wsjtx_state_table; server/src/decoder/apriori_test.rs::a_priori_bits_are_the_packed_message_bits; server/src/decoder/bitmetrics_test.rs::a_priori_words_need_a_decoded_payload_and_confidence; server/src/decoder/search_test.rs::weak_qso_words_decode_only_with_the_right_calls; server/src/decoder/search_test.rs::wrong_dx_call_never_yields_a_false_word; server/tests/audio_receive.rs::live_native_provider_decodes_independent_ft8_callsign";
    }
    verification 'TC-004-003' {
        doc /* TC-004-003 — Invalid and nonmatching input
             FR-003, FR-004, FR-018; CL-007-01, CL-007-02, CL-007-03, CL-007-04
             Exercise unsupported/truncated audio, silence/noise, an explicit mode mismatch and a second offline run.
             Invalid input is reported without corrupting station state; false decodes meet the agreed rejection criteria; replay produces equivalent results within defined tolerances. Use hand-specified errors and independent reference fixtures.
             Runtime matrix qualification (#36 decision): a poll whose wall time exceeds 50 ms leaves that configuration's 50 ms CPU quantum unmeasured, which is neither a pass nor a violation. The configuration is re-measured, at most three attempts; the runtime (including the four-worker 2x bound), cold-start and 64 MiB budgets bind every attempt, and any exceedance is a failure. A configuration still unmeasured after the third attempt makes the matrix inconclusive. The ordinary push gate keeps the matrix as a regression detector: an inconclusive matrix exits with the harness NOT RUN code 77, so the gate lists the suite as not run, records it as not-run, never memoises it as passed and does not block the push; such a run is never a pass and never CL-007-04 evidence. CL-007-04 runtime evidence comes only from the strict exclusive-window run on the reference PC, which refuses an inconclusive matrix.
             Station process case (#71): receive_http_tests::resource_station_process_delta_and_owner_release (private-commit delta at most 96 MiB over idle, receive-owner release at most 250 ms after Stop, FT8 and FT4, after a decode and during a busy window) runs in the release timing suite live-station-latency, alone, as a regression detector. A gate run of it is never CL-007-04 evidence; that evidence comes only from the strict exclusive-window run on the reference PC.
             2 — Isolated automated tests; Windows PC with disposable recordings, no radio or live service. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-007-01';
            verify 'CL-007-02';
            verify 'CL-007-03';
            verify 'CL-007-04';
            verify 'FR-003';
            verify 'FR-004';
            verify 'FR-018';
        }
        attribute executable : String = "server/tests/decoder_signal.rs::quality_corpus; server/tests/decoder_signal.rs::independent_waveforms_decode; server/tests/decoder_signal.rs::crc_valid_unsupported_and_invalid_payloads_are_retained; server/tests/decoder_signal.rs::unmodulated_sources_are_not_frames; server/tests/decoder_signal.rs::physical_noise_reproduction_has_no_frame; server/tests/decoder_signal.rs::physical_wrong_mode_reproduction_has_no_frame_or_search_error; server/tests/decoder_signal.rs::release_runtime_and_overlapping_window_history; server/src/receive_http_tests.rs::resource_station_process_delta_and_owner_release";
    }
    dependency CL_007_03_verified_by_TC_004_001 from 'CL-007-03' to 'TC-004-001';
    dependency CL_007_03_verified_by_TC_004_002 from 'CL-007-03' to 'TC-004-002';
    dependency CL_007_03_verified_by_TC_004_003 from 'CL-007-03' to 'TC-004-003';
    dependency CL_007_04_verified_by_TC_004_001 from 'CL-007-04' to 'TC-004-001';
    dependency CL_007_04_verified_by_TC_004_002 from 'CL-007-04' to 'TC-004-002';
    dependency CL_007_04_verified_by_TC_004_003 from 'CL-007-04' to 'TC-004-003';
    dependency CL_007_04_verified_by_TC_004_004 from 'CL-007-04' to 'TC-004-004';
}
