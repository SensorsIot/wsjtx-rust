// Canonical FSD slices SHA256: bb770b27c4dc6763319008a5ea5558acc659cd61eb0d116d1305a9c0eb5c95ad
package WstxOperatingReceive {
    private import ScalarValues::*;


    enum def HttpCodingSelection { identity; gzip; noAcceptable; }
    part def HttpContentCodingBoundary {
        attribute exactAllowedGet : Boolean;
        attribute authenticated : Boolean;
        attribute successfulJson : Boolean;
        attribute containsCredentials : Boolean;
        attribute logicalCapsSatisfied : Boolean;
        attribute nonempty : Boolean;
        attribute headOrNoBody : Boolean;
        attribute alreadyEncoded : Boolean;
        attribute contentRange : Boolean;
        attribute eligible : Boolean;
        attribute selection : HttpCodingSelection;
        attribute compressed : Boolean;
        attribute status406 : Boolean;
        constraint eligibility { eligible ==
            (exactAllowedGet and authenticated and successfulJson and
             not containsCredentials and logicalCapsSatisfied and nonempty and
             not headOrNoBody and not alreadyEncoded and not contentRange) }
        constraint exactCompression { compressed ==
            (eligible and selection == HttpCodingSelection::gzip) }
        constraint exactRefusal { status406 ==
            (eligible and selection == HttpCodingSelection::noAcceptable) }
        constraint excludedPreservation { not eligible implies
            (not compressed and not status406) }
        // HttpCodingSelection comes from pinned tower-http0.7.1, FSD12.1.1 ordered table; no custom parser.
        // ALL eligible nonempty selected-gzip JSON encoded even <32bytes.
        // Ineligible responses preserve original status/bytes/headers before negotiation.
        // Vary exact-token merge BEFORE library; no substring comparison.
        // Logical schemas/caps/provenance/owner and WS/request representations unchanged.
    }
    verification def HttpNegotiationAndIdentity { doc /* TC009005case8 A/B: every pinned
       FSD12.1.1 ordered table vector incl field order, duplicate/wildcard/malformed q; identity
       only when selected; noAcceptable406. Raw gzip/independent decoder, exact JSON,
       tiny2bytebody, correct Vary token merge and framing. */ }
    verification def HttpExcludedAndCaps { doc /* case8 C: HEAD/no-body/already-encoded/range,
       auth/errors/secrets/mutations bypass BEFORE negotiation, even all-encodings-forbidden;
       no duplicate effects, logical caps before compression, no request decompression. */ }
    verification def HttpActualCombinedTls { doc /* case8 D: real two-browser native/CAT75s
       Thin and75sOff, unchanged TLS accounting/status/cadences/oracles; no estimated PASS. */ }

    doc /* Target implementation contract for FSD4.7.5/6.6 TC009005/12.8.1.
         Markdown remains authoritative; no execution or implementation verdict.
         One existing station/receive authority and one typed radio Actor are reused.
         Ordinary preferred defaults and Monitor-start behavior follow pinned
         beta4 source plus actual receive-only observations. TX/QSO/log/custom or
         alternate-frequency behavior is outside this bounded slice. */
    enum def Mode { enum ft4; enum ft8; }
    enum def ControlKind { enum manual; enum configuredCat; }
    enum def Phase { enum idle; enum releasing; enum applying; enum restarting; enum applied; enum failed; enum releaseBlocked; enum cancelled; }
    enum def Event { enum accepted; enum releaseConfirmed; enum releaseFailed; enum setupConfirmed; enum setupFailed; enum audioStarted; enum audioFailed; enum stop; enum revisionChanged; enum none; }
    attribute def Selection {
        attribute mode : Mode;
        attribute nominalHz : Integer;
        attribute operatingRevision : Integer;
        assert constraint nativeRange { nominalHz >= 30000 and nominalHz <= 74800000 }
        doc /* FSD4.7.5: pinned ALLregion default table; currentband preferred else
             nearest sameband. Ordinary20mFT8=14074000/FT4=14080000;
             40mFT8=7074000/FT4=7047500. Absent preferred-entry subcase explicitly
             unsupported initialslice, no invented standard fallback. */
    }
    attribute def RadioFacts {
        attribute frequencyHz : Integer[0..1];
        attribute usb : Boolean[0..1];
        attribute dataOn : Boolean[0..1];
        attribute filterNumber : Integer[0..1];
        attribute frequencyConfirmed : Boolean;
        attribute modeConfirmed : Boolean;
        attribute dataConfirmed : Boolean;
        attribute operationContext : String;
        doc /* FSD4.7.5: requested/committednominal versus physical facts separate.
             Each current fact has matching successful query provenance; aggregate
             observed_at cannot freshen cached unqueried fields. FIL1 not numeric
             width3000Hz. Partial failure never implies rollback or target success. */
    }
    calc def DesiredMonitorAfterOrdinarySelection {
        in originalMonitor : Boolean;
        in ordinarySelectionCommitted : Boolean;
        return desired : Boolean = originalMonitor or ordinarySelectionCommitted;
        doc /* FSD4.7.5: actual22:02UTC MonitorOFF+band20->ON14.074,OFF+FT4->ON7.0475;
             alreadyON staysdesiredON. Rejectedbeforecommit preservesoriginalintent.
             Existing old NextReceive selector remains nextjob-only/no device start. */
    }
    calc def MayStartApplying {
        in currentContextValidated : Boolean;
        in transitionTokenCurrent : Boolean;
        in oldPublicationInvalid : Boolean;
        in workerReleased : Boolean;
        in audioOwnerReleased : Boolean;
        in stopRequested : Boolean;
        return allowed : Boolean = currentContextValidated and transitionTokenCurrent and
            oldPublicationInvalid and workerReleased and audioOwnerReleased and not stopRequested;
        doc /* FSD4.7.5: bounded ordinaryrelease<=250ms is not timerpermission;failed
             close retainsowner and blocksCATsetter/newinput. No profile lock held. */
    }
    calc def MayRestart {
        in currentContextValidated : Boolean;
        in tokenCurrent : Boolean;
        in revisionMatches : Boolean;
        in desiredMonitor : Boolean;
        in selectionCommitted : Boolean;
        in oldOwnersReleased : Boolean;
        in stopRequested : Boolean;
        return allowed : Boolean = currentContextValidated and tokenCurrent and
            revisionMatches and desiredMonitor and selectionCommitted and
            oldOwnersReleased and not stopRequested;
        doc /* FSD4.7.5: restart same stationmanager, saved exactendpoint refreshed
             generation;no oldcallbacks/pages or unknownmutation clearsnewintent. */
    }
    state def ModeBandTransition {
        attribute acceptedEvent : Event;
        attribute currentToken : Boolean;
        attribute releaseGuard : Boolean;
        attribute restartGuard : Boolean;
        attribute monitorWanted : Boolean;
        entry; then idle;
        state idle; state releasing; state applying; state restarting;
        state applied; state failed; state releaseBlocked; state cancelled;
        transition begin first idle if acceptedEvent == Event::accepted and currentToken then releasing;
        transition released first releasing if acceptedEvent == Event::releaseConfirmed and releaseGuard and currentToken then applying;
        transition blocked first releasing if acceptedEvent == Event::releaseFailed then releaseBlocked;
        transition restart first applying if acceptedEvent == Event::setupConfirmed and monitorWanted and restartGuard and currentToken then restarting;
        transition applyStopped first applying if acceptedEvent == Event::setupConfirmed and not monitorWanted and currentToken then applied;
        transition stopApplied first applied if acceptedEvent == Event::stop then cancelled;
        transition stopBlocked first releaseBlocked if acceptedEvent == Event::stop then cancelled;
        transition setupFailure first applying if acceptedEvent == Event::setupFailed then failed;
        transition running first restarting if acceptedEvent == Event::audioStarted and currentToken then applied;
        transition captureFailure first restarting if acceptedEvent == Event::audioFailed then failed;
        transition stopRelease first releasing if acceptedEvent == Event::stop then cancelled;
        transition reviseRelease first releasing if acceptedEvent == Event::revisionChanged then failed;
        transition stopApply first applying if acceptedEvent == Event::stop then cancelled;
        transition reviseApply first applying if acceptedEvent == Event::revisionChanged then failed;
        transition stopRestart first restarting if acceptedEvent == Event::stop then cancelled;
        transition reviseRestart first restarting if acceptedEvent == Event::revisionChanged then failed;
        doc /* FSD4.7.5: accept invalidatesoldpublication/startsactualcancel before
             releasing. Eventaccept invalidcontext never admitted. Oneordinarycommand
             noqueue;Stop synchronously invalidatestoken/clearsresume. Failed state
             never means resourcesreleased:keepsrealowner until actualcleanup. Partial
             sentCATwrites may remain;no fake rollback. CATapplied+audiofailed retains
             correctcommittedselection+actualfacts withreceiveerror. Normalcompletion
             no automaticreplay. Terminaloperation record doesnot replace receive state. */
    }
    action def ResolveOrdinaryTarget {
        doc /* FSD4.7.5: region/mode/timefilteredpinnedtable; onlyadmittedpreferredsameband; tiebreak firstsortedrow. Nominalfrequency usedforlookup,
             not claiming physicalreadback. Initialunsupportedsubcases stayexplicit. */
    }
    action def ManualSelection {
        doc /* FSD4.7.5: explicitcontrol-disabled performsnominal/decodertransitionwith
             zerobytes/serialopen;actualrigunconfirmed. ConfiguredCATfailure cannot
             silentlybecomeManualsuccess. Existing audioMonitor independent. */
    }
    action def ApplyTypedReceiveSetup {
        doc /* FSD4.7.5: sameActorphysicalidentity/onelease; freshReadRxTxRX before
             setters; existingUSB/FIL1,DATAon/FIL1,frequencyfinalexactreadback<=5s,
             individualexchange1s/cancel50ms,explicitcanonicalconnectonly; selectionneveropensCAT. NoPTT/raw
             serial/width/notch/PBTchange. Requestedmode/nominalpendinguntilconfirmation.
             Freshness trackedperquery;manualretuneafterobservationisnottransactionlock. */
    }
    action def SwitchReceiveContext {
        doc /* FSD4.7.5: invalidateoldtuple,existingstop/waitactualrelease,noCAT/new
             capturefirst. ReuseexistingStart withsavedendpoint/currentrevision,new
             source/job/generation;resetconverter/spectrum/modem atRFtransition.
             DesiredMonitorON can showSwitching,not fictitiousseamlesssamples. */
    }
    action def ReconcilePartialFailure {
        doc /* FSD4.7.5: preservelastcommittednominal,requestederror,actualknown
             partialfacts;readonlyqueriesrefreshonlyqueriedfields. No automatic
             restoringwrites,retryorreceive restart. Explicitnewoperationrequired.
             12.8.1 matchingrecord/newerrevisionorfence resolvesunknownoutcome barrier;
             preintent/oldcontextread cannot undoStop or triggerrestart. */
    }
    verification def TableDefaults { doc /* TC009005case2 pinned32facts/preferred/nearest/missing/range; source independently expected. */ }
    verification def ActualFlow { doc /* TC009005case2 actualnativefixture->soledecoder->HTTP/browser, manualzeroCAT, desiredMonitordefault and oldNextselectorseparate. */ }
    verification def TypedReadback { doc /* TC009005case3 independentCI-V and perfieldprovenance,partialsettererrors,authority/deadlinecaps. */ }
    verification def ContextAndFailure { doc /* TC009005cases4/5/6 actualcancel/release/newidentity,failedclose/Stop/profileedit/staleinterleavings;no fakehardwaretruth or secondowner. */ }
    verification def PhysicalReceive { doc /* TC009002 authorizedcost4 actualIC7300 readback+actualbrowser,notordinarygate/noTX. */ }
    enum def ReceiveMode { enum spectrum; enum ft4; enum ft8; }
    enum def ReceiveState { enum stopped; enum running; enum cancelling; enum failed; }
    enum def MutationState { enum idle; enum pending; enum outcomeUnknown; }
    enum def ReceiveIntent { enum monitor; enum stop; enum chooseNextMode; }
    enum def ExistingOperation { enum none; enum start; enum stop; }
    calc def MapToolbarIntent {
        in intent : ReceiveIntent;
        in current : ReceiveState;
        in mutation : MutationState;
        in receiveCapability : Boolean;
        in currentContextValidated : Boolean;
        in previousOwnershipReleased : Boolean;
        return operation : ExistingOperation =
            if not receiveCapability or not currentContextValidated or mutation != MutationState::idle ? ExistingOperation::none else
            if intent == ReceiveIntent::chooseNextMode ? ExistingOperation::none else
            if intent == ReceiveIntent::stop and current == ReceiveState::running ? ExistingOperation::stop else
            if intent == ReceiveIntent::monitor and current == ReceiveState::running ? ExistingOperation::stop else
            if intent == ReceiveIntent::monitor and previousOwnershipReleased and (current == ReceiveState::stopped or current == ReceiveState::failed) ? ExistingOperation::start else
            ExistingOperation::none;
        doc /* FSD4.7.51/2/3/4/6. Existing server guards still decide admission; none does
             not claim success. Observed Monitor-off and Stop share receive-only stopped indications
             and retained texts; Receiving may remain green transitionally. Hidden
             loop/wait/TX effects and native release are unobserved. Abstract stopped
             maps absent/completed/cancelled job. Failed job does not prove ownership
             released. previousOwnershipReleased is confirmed prior-owner release;
             currentContextValidated includes validated current station/profile/boot
             snapshot even if job absent. No first/stale snapshot request permitted. No PTT, disarm, QSO cancellation or CAT. */
    }
    attribute def ReceivePresentation {
        attribute activeMode : ReceiveMode;
        attribute nextMode : ReceiveMode;
        attribute receive : ReceiveState;
        attribute mutation : MutationState;
        attribute currentTupleValidated : Boolean;
        attribute canMutate : Boolean;
        assert constraint mutationAuthority {
            canMutate implies (currentTupleValidated and mutation == MutationState::idle and receive != ReceiveState::cancelling)
        }
        doc /* Existing profile/boot/source/job/generation and revision are retained,
             not replaced with a new ownership scheme. Next selection starts no device
             and never changes activeMode. Active mode and running/released state come
             from authoritative receive snapshot. Partial results remain explicit. */
    }
    enum def MutationEvent {
        enum submitted; enum confirmed; enum rejected; enum responseLost;
        enum laterAuthoritativeReconciliation;
    }
    state def ExistingMutationBarrier {
        attribute acceptedEvent : MutationEvent;
        entry; then idle;
        state idle; state pending; state outcomeUnknown;
        transition submit first idle if acceptedEvent == MutationEvent::submitted then pending;
        transition complete first pending if acceptedEvent == MutationEvent::confirmed or acceptedEvent == MutationEvent::rejected then idle;
        transition uncertain first pending if acceptedEvent == MutationEvent::responseLost then outcomeUnknown;
        transition reconcile first outcomeUnknown if acceptedEvent == MutationEvent::laterAuthoritativeReconciliation then idle;
        doc /* FSD4.7.54. Old/pre-intent reads never emit laterAuthoritativeReconciliation.
             This names the legacy Start/Stop browser barrier only; coordinated selection
             uses MayClearUnknown and explicit12.8.1 fencing; it adds no mutation queue/retry.
             Reconciliation determines real state, not automatic desired success. */
    }
    action def StartWithExistingReceiveAPI {
        in nextMode : ReceiveMode;
        doc /* FSD4.7.51/3: POST /receive/start with unchanged FSD12.8 exact shape,
             saved input/current revision/current context. One receive owner and
             actual decoder; no audio selection fallback or radio command. */
    }
    action def StopWithExistingReceiveAPI {
        doc /* FSD4.7.52/5: exact current-job Stop, publication invalid before ACK;
             existing cancellation/release bounds and failure ownership preserved.
             Verified partial results remain; stale callbacks cannot publish. */
    }
    enum def Action { enum mode; enum band; enum cancel; }
    enum def NominalOrigin { enum unknown; enum manual; enum cat_readback; }
    enum def OperationResult { enum pending; enum success; enum failed; enum cancelled; }
    enum def CancelResult { enum cancelled; enum fenced; enum already_cancelled; }
    enum def QueryKind { enum frequency; enum mode; enum data; enum rx_tx; enum split; }
    enum def SelectionPhase { enum releasing; enum applying; enum restarting; enum applied; enum failed; enum release_blocked; enum cancelled; }
    attribute maxSafe : Integer = (900719925 * 10000000 + 4740991);
    attribute def WireSelection {
        attribute mode : Mode;
        attribute band : String[0..1];
        attribute nominalHz : Integer[0..1];
        attribute origin : NominalOrigin = NominalOrigin::unknown;
        attribute confirmedCommandId : String[0..1];
        doc /* S1a/S4: band andnominal bothabsent atfreshboot, mode canbeFT8/current
             jobmode; no0/20m invented. If known values mustsameadmittedtableentry.
             Resolved Selection range isonlyresolvedselection, notstartuprepresentation. */
    }
    calc def MayResolveMode {
        in committedBandKnown : Boolean;
        in exactReadbackBandUnique : Boolean;
        in readbackCurrent : Boolean;
        return allowed : Boolean = committedBandKnown or
            (exactReadbackBandUnique and readbackCurrent);
        doc /* S1a: otherwise409select_band_first beforeanydevice/start/stop/revision
             change. Explicitband selectsitsentry. Noapproximate/defaultbandguess. */
    }
    attribute def NormalSelectionRequest {
        attribute version : Integer = 1;
        attribute profileId : String;
        attribute bootId : String;
        attribute commandId : String;
        attribute requestAction : Action;
        attribute profileRevision : Integer;
        attribute generation : Integer;
        attribute operatingRevision : Integer;
        attribute targetMode : Mode[0..1];
        attribute targetBand : String[0..1];
        doc /* S2/S3: JSON exactcommonv/profile_id/boot_id/command_id/action/
             profile_revision/generation/operating_revision;modeactionone modefield,
             bandactionone bandfield. <=1024bytes,existingUUID/safecounter/strictJSON/
             Origin/auth/envelope. Unknown/doubled/missingkeysfailbeforeeffects.
             targetradio/device/PTT/rawparameters notpartofrequest. */
    }
    attribute def CancelSelectionRequest {
        attribute version : Integer = 1;
        attribute profileId : String;
        attribute bootId : String;
        attribute commandId : String;
        attribute operatingRevision : Integer;
        attribute targetCommandId : String;
        doc /* ExactS3 cancelunion, no callerjob/generation guessing. Targetsone
             currentbootoperation. Differentlateroperation cannotbe cancelledbyoldID. */
    }
    calc def MayAdmitNormal {
        in authenticatedContext : Boolean;
        in profileMatches : Boolean;
        in generationMatches : Boolean;
        in revisionMatches : Boolean;
        in activeOperation : Boolean;
        in targetResolved : Boolean;
        in controlReadyOrManual : Boolean;
        in counterAvailable : Boolean;
        return admitted : Boolean = authenticatedContext and profileMatches and
            generationMatches and revisionMatches and not activeOperation and
            targetResolved and controlReadyOrManual and counterAvailable;
        doc /* S1/S2: configuredCATmustalreadyreadyviacanonicalexplicitconnect
             withreceive_only_verifiedprecondition;neverimplicitconnectproof.
             Admissionatomicallyincrementsrevision,invalidatesoldreceivepublication.
             Oneoperation/noqueue;activequerybusycannotbecomenewrawserialconnection. */
    }
    attribute def CancelReceipt {
        attribute phase : SelectionPhase = SelectionPhase::cancelled;
        attribute result : CancelResult;
        attribute normalOperationCreated : Boolean = false;
        assert constraint exactCancelReceipt {
            phase == SelectionPhase::cancelled and not normalOperationCreated
        }
        doc /* S3/S5: EVERY successfulcancel/fence receipt uses phasecancelled.
             This is cancellation acknowledgement, not normaloperationlifecycle.
             Fenced unseencommand createsNOoperation;preserveprioroperation/null.
             Snapshotcancellation.resultdistinguishesfenced/cancelled/already_cancelled.
             TC009005case6 independentlychecksreceipt+snapshotabsence,nophantomoperation. */
    }
    calc def MayFenceUnseen {
        in authenticatedCurrentBoot : Boolean;
        in expectedRevision : Integer;
        in currentRevision : Integer;
        in targetSeen : Boolean;
        in differentActiveOperation : Boolean;
        in counterAvailable : Boolean;
        return allowed : Boolean = authenticatedCurrentBoot and
            expectedRevision == currentRevision and not targetSeen and
            not differentActiveOperation and counterAvailable;
        doc /* S5caseA: incrementcurrentrevision and recordfenced beforeACK;
             delayedoldPOSTbasecannotadmit. CancelReceiptphasecancelledwithresultfenced;
             no normaloperationcreated/replaced. NoCAT/start/stopunrelatedcurrentjob. */
    }
    calc def MayCancelTarget {
        in authenticatedCurrentBoot : Boolean;
        in targetMatchesLastOperation : Boolean;
        in expectedRevision : Integer;
        in baseRevision : Integer;
        in operationRevision : Integer;
        in currentRevision : Integer;
        in counterAvailable : Boolean;
        return allowed : Boolean = authenticatedCurrentBoot and targetMatchesLastOperation and
            currentRevision == operationRevision and counterAvailable and
            (expectedRevision == currentRevision or expectedRevision == baseRevision);
        doc /* S5caseB: synchronouslycancel/resumefalse,newfencerevision;onlytarget's
             currentnewjobtuplecanbestopped. Samecancelreceiptduplicateisread-only
             idempotentcase,bypassesnot-reexecutesthisguard. Superseded409zeroeffects. */
    }
    calc def MayClearUnknown {
        in readStartedAfterUnknown : Boolean;
        in sameBoot : Boolean;
        in originalBase : Integer;
        in snapshotRevision : Integer;
        in matchingOperationRecord : Boolean;
        return clearable : Boolean = readStartedAfterUnknown and sameBoot and
            (matchingOperationRecord or snapshotRevision > originalBase);
        doc /* S5: equalrevision+absentcommandcannotprovePOSTnotstillinflight;
             explicitcancel/fence needed. Clearunknownclassification doesnot clear
             activeoperationbusystate. OldreadcannotundoStop/newintent. */
    }
    attribute def QueryCompletion {
        attribute connectionGeneration : Integer;
        attribute querySequence : Integer;
        attribute kind : QueryKind;
        attribute observedAtMs : Integer;
        assert constraint counters {
            connectionGeneration > 0 and connectionGeneration <= maxSafe and
            querySequence > 0 and querySequence <= maxSafe and
            observedAtMs >= 0 and observedAtMs <= maxSafe
        }
        doc /* S6: sameexistingactor/typedquery,eventonlyaftervalidaddressedreply,
             typeddecodedvalueattached. ACK/broadcast/echo/setterisnotcompletion.
             Onefactupdatedperquery;perconnectionclearbeforefirstnewquery. */
    }
    attribute def FactProvenance {
        attribute querySequence : Integer[0..1];
        attribute observedAtMs : Integer[0..1];
        attribute confirmed : Boolean = false;
        doc /* S4/S6: pairedvalueofthatfactalsooptional;unknownallnull+false.
             Lastknownvalue/timestampretainedifstale,confirmedfalse. Neverfreshen
             fromanotherqueryoraggregateobserved_at. timestamp<=snapshotmonotonic.
             Wholefinalsetupsuccessrequiresmatchingcurrentmode/DATA/frequencyfacts. */
    }
    attribute def OperationRecord {
        attribute commandId : String;
        attribute baseRevision : Integer;
        attribute admissionRevision : Integer;
        attribute phase : SelectionPhase;
        attribute result : OperationResult;
        attribute monitorBefore : Boolean;
        attribute monitorWanted : Boolean;
        attribute oldJobId : String[0..1];
        attribute newJobId : String[0..1];
        doc /* Exactrequestedselection/erroralsoinS4JSON. Retainonlylastnormalrecord;
             cancelrecordseparate. Profilechangeinvalidateswithoutundopersistedconfig.
             Appliednominal+audiofailurestayscommittedandfailed,notfabricatedrollback. */
    }
    attribute def WireLimits {
        attribute requestBytes : Integer = 1024;
        attribute receiptBytes : Integer = 384;
        attribute snapshotBytes : Integer = 3072;
        attribute metadataBytes : Integer = 4096;
        attribute thinOffPassiveMs : Integer = 8000;
        attribute thinOffPendingMs : Integer = 4000;
        attribute detailedPassiveMs : Integer = 2000;
        attribute detailedPendingMs : Integer = 500;
        attribute pendingReads : Integer = 1;
        attribute pendingOrdinaryMutations : Integer = 1;
        doc /* S7: Targetengineeringbounds;existing32kbitTLS/status<=2s tests
             mustincludeactualallowedpolls+mode/bandtraffic,notbodyestimatesonly.
             NoWS/statusschemaextension,oldstrictv1routesunchanged. */
    }
    action def RadioFactPublication {
        doc /* S6 existingactor/executorreportsquerycompletionkind/value/provenance
             tostationalreadyownedstateoutsideI/Olocks. Possiblytouchedfieldsstale
             onpartialwrite;successupdatesonlyqueriedfact. Genericdirectsettercannot
             bypasssameRFcontextorchestration;keepunsupporteduntilbarrierbound.
             /radioexistingaggregatev1shapeunchanged,newfactsinselectionendpointonly. */
    }
    action def ExistingReceiveStop {
        doc /* S1/S5: matchingold/currenttupleStopalsoclearsowningtransitionresume;
             staleoldtuplestillrefuses/cannotcancelnewjob. Newtargetcancelhandles
             unknown/nojobtransitionwithoutweakenedgenerationguard. */
    }
    verification def ColdUnknownNominal { doc /* TC009005case2 manual/configuredCATfreshboot409select_band_first,zeroeffects;nullablemode/nominalshape;exactreadbackonly. */ }
    verification def WireBarriers { doc /* TC009005case5 allunions/bytes/auth/Origin/identity/safecounters/limits;strictnegativesbeforeeffects. */ }
    verification def DelayedAdmissionFence { doc /* TC009005case6 originalPOSTarrivesafteremptyGET+cancel;oldbaseinvalid;twoclients/profileedits/repeat/supersededtargets. */ }
    verification def PerFieldTruth { doc /* TC009005case3 independentqueryfacts/ACK/echo/partialfailedwrites/connectionreplacement;nofreshnessfromunrelatedcache. */ }
    verification def CompatibilityAndBudget { doc /* TC009005case7 old/newclients/unsupporteddiscovery/oldNextReceive,oneowner/Stopidentity,totalThinOffTLScontrol/status. */ }

    attribute def PreferredEntry {
        attribute band : String;
        attribute mode : Mode;
        attribute frequencyHz : Integer;
        doc /* Exact immutable preferred table and unsupported cells are FSD4.7.5.
             ALL/default includes R1 4m FT8.160m/4m FT4 have no entry. Backend range
             filters before admission. Unknown band/nominal are optional in WireSelection;
             resolved values must name the same admitted row, never a guessed band. */
    }
    attribute def SnapshotIdentity {
        attribute profileId : String;
        attribute bootId : String;
        attribute profileRevision : Integer;
        attribute receiveGeneration : Integer;
        attribute operatingRevision : Integer;
        attribute snapshotSequence : Integer;
        attribute monotonicMs : Integer;
        doc /* Exact snapshot JSON/object cardinalities/errors are FSD12.8.1 S2..S4.
             Atomically captured station state; no lock across I/O. Revision changes on
             admission, fence and profile revision, never fact polling. One normal record
             plus one cancellation record <=4096bytes. Read has no device/mutation effect.
             Snapshot sequence advances material changes, not heartbeat-age alone. */
    }
    action def ExistingAuthorityCoordination {
        doc /* One Recording receive state owns coordination identity/token/lease.
             Same station context owns the existing typed Actor handle. Capture profile/
             receive/operating revisions, release locks, await actual worker/native release
             and CAT, then CAS current token+revisions before commit/restart. No serial
             bytes or actor callbacks under profile/Recording locks, no nested owner or
             alternate converter/modem. Direct setters remain unsupported until they use
             the same RF-context barrier; queries/connect/disconnect retain12.8 contract. */
    }
    verification def CoherentReceiveControls {
        objective {
            verify WstxRequirements::'CL-008-07';
            verify WstxRequirements::'CL-008-03';
            verify WstxRequirements::'CL-008-05';
            verify WstxRequirements::'CL-010-05';
            verify WstxRequirements::'CL-010-07';
            verify WstxRequirements::'CL-010-08';
        }
        doc /* TC009005 cases1..7 cost2 isolated Windows real services/Chromium,
             independent typed CI-V/native packet/frozen payload and TLS link fixtures.
             Monitor/Stop/legacy-next distinction, all preferred rows+missing/range,
             unknown initial nominal, release/failed-close, partial writes/readback,
             profile edits, Stop/late callback/CAS/fencing and exact strict barriers.
             Old/new client compatibility,384/3072/4096/1024 byte maxima+one-over,
             all safe counters and zero-effect refusals; no candidate-generated oracle.
             Actual8s/4s Thin/Off selection traffic + mode/band controls preserve existing
             two-browser32kbit mean<=3000B/s eachway and visible status<=2s.
             Detailed2s/500ms fast-link is separate. Keyboard360px/200percent.
             TC009002 separate authorizedcost4 physical IC7300/USB/CAT/browser;
             actual frequency/USB/DATA/FIL, width/notch/PBT and restore independently
             observed, no TX or quiet-band fabricated decoding. Verification not run. */
    }
    doc /* Normative wire serialization and producer/consumer meanings, FSD12.8.1:
#### 12.8.1 Coordinated receive operating selection — target extension

This target interface implements4.7.5/CL-008-07 through the same station owner and
typed radio actor. TC-009-005 defines independent verification. It specifies required
behavior, not an implementation or physical acceptance claim. S1–S7 are local interface
anchors, not separate requirement identifiers.

**S1. Compatibility and explicit admission.** Existing `/receive`, `/receive/start`,
`/receive/stop`, `/receive/results`, `/audio/devices` and the canonical target `/radio`,
`/radio/connect`, `/radio/disconnect`, `/radio/operation` retain their exact version1
shapes, bounds, authentication, Origin and error semantics. Do not add fields to their
strict objects. Explicit CAT connection still requires `receive_only_verified=true`
after4.5's physical precondition; selection never opens a closed configured connection.
Configured but unready CAT returns radio_unavailable before disturbing receive. Manual,
control-disabled operation remains CAT-independent.

Add `GET /receive/selection` and `POST /receive/select` through the existing station
owner for ordinary preferred mode/band selection and targeted cancellation. Keep legacy
**Next receive mode** next-job-only; separate **Operating mode** uses the new route and
is the primary digital mode control when supported. Legacy Start during a transition
returns busy. Matching legacy Stop also clears the owning transition's resume intent;
stale old-tuple Stop still refuses. Targeted cancel covers no-job/unknown-transition
cases without weakening legacy Stop identity.

At startup, selection mode may be FT8 or the current digital job mode while band and
nominal frequency are null. Unknown is neither0 nor guessed20m. Mode action requires
a committed admitted band or fresh current exact typed readback equal to a uniquely
band-labelled preferred entry. Otherwise409select_band_first precedes any stop/start,
device bytes, connection or revision change. A band action supplies its band. Fresh
readback can resolve that explicit action but does not automatically commit selection
on a GET. No approximate band classifier or digital-mode inference from RF alone.

**S2. Validation and authority.** These new routes exist only in selected-profile mode;
environment-only mode returns404not_found. Validation order is route/method, exact
Origin (GET may omit; mutations require; duplicates/mismatch403), TLS/session401,
body-size/media/syntax, version/enums/UUID/safe integers, profile403, boot/revisions/
generation409, capability and current owner admission. Requests are at most1024UTF-8
bytes with exact keys, duplicate rejection and JSON media under12.8. Version is1; UUIDs
use the existing profile grammar; counters are0..9007199254740991 without wrapping.
Errors contain bounded codes, never credentials, raw device strings or native exceptions.

The station owns `operating_revision`, initially0 per boot. Increment once on normal
admission and once per accepted cancellation/fence. A successful profile revision change
invalidates captured operations and advances it unless already exhausted; at exhaustion
keep the terminal counter, invalidate the token and refuse new selections, without
undoing or blocking the existing successful profile edit. Fact polling does not. Refuse any
mutation needing another revision if exhausted, before new IDs or effects. Compare
this revision, profile revision and receive generation atomically at admission. The
caller UUID is correlation, not authority. Retain only one normal operation and one
cancel receipt, at most4096encoded metadata bytes total. No command queue. An active
ordinary operation blocks ordinary commands but never its targeted cancellation/Stop.

**S3. Exact requests and receipts.** `POST /receive/select` has three exact alternatives
(listed names are JSON keys; all are required):

- Mode: `{v,profile_id,boot_id,command_id,action,profile_revision,generation,operating_revision,mode}`,
  action=`mode`, mode=`ft4|ft8`.
- Band: `{v,profile_id,boot_id,command_id,action,profile_revision,generation,operating_revision,band}`,
  action=`band`, band one of`160m,80m,60m,40m,30m,20m,17m,15m,12m,10m,6m,4m`.
  Require a preferred entry for the current mode/backend; otherwise409selection_unavailable.
- Cancel: `{v,profile_id,boot_id,command_id,action,operating_revision,target_command_id}`,
  action=`cancel`. It targets one current-boot operation, not whichever later job exists.
  No caller device/PTT fields or guessed job identity; see S5.

Normal admission returns202 exact
`{v:1,profile_id,boot_id,command_id,operating_revision,accepted:true,phase}`, at most384
encoded bytes. Its phase is the retained operation phase. Every successful cancel/fence
receipt uses exactly `phase:cancelled`, an acknowledgement of cancellation/fencing,
not a phantom normal operation. Identical retained cancel ID+target may return200 with
the same receipt/revision and no repeated effect. A different body using that retained
ID returns409state_conflict. Never automatically replay a normal mutation.

Admission means accepted/old publication invalidated, not physical tuning or running
audio. Post-admission failure is retained in the operation, not converted to invented
success. All failures use exact `{error:{code,field:null}}`. The additional catalogue is
400invalid_request/unsupported_version;403forbidden_origin/wrong_profile;
401unauthorized;404not_found;413request_too_large;415unsupported_media_type;
409state_conflict/busy/counter_exhausted/select_band_first/selection_unavailable/
radio_unavailable/receive_only_unverified/operation_superseded. Snapshot overflow uses
503snapshot_limit. Pre-admission refusal emits no bytes or source invalidation.
Operation error also permits audio_unavailable, audio_unconfigured, release_failed,
readback_mismatch, radio_rejected, radio_timeout, radio_failed_close and cancelled;
map other actual device errors to bounded existing safe enum codes, not exception text.

**S4. Exact snapshot and provenance.** `GET /receive/selection` returns200 exact
`{v:1,profile_id,boot_id,profile_revision,generation,operating_revision,snapshot_sequence,monotonic_ms,control,selection,available_bands,operation,cancellation,receive,radio}`.
Atomically capture station state without holding locks across audio/serial waits.
`snapshot_sequence` is a safe counter advancing on material selection/operation/receive
identity or published radio fact changes, not heartbeat-age-only changes.
`monotonic_ms` is safe boot-relative station milliseconds, not browser time. GET has no
connect/capture/reconcile mutation. Encoded response is at most3072UTF-8bytes; overflow
returns503snapshot_limit without truncation. Verify the maximum valid shape before
admitting a candidate; truncating entries is not a size policy.

`control` is exactly `manual|cat` from current saved settings, independent of availability.
`selection` is exactly `{mode,band,nominal_hz,origin,confirmed_command_id}`: mode ft4|ft8;
band nullable admitted enum; nominal_hz nullable integer30000..74800000; band/nominal
are both null or both known and name the same admitted row for that mode. Origin is
unknown|manual|cat_readback. confirmed_command_id is UUID/null for the last successful
nominal commit, not a claim that the physical dial remains locked. Current digital job
mode may populate mode without a frequency claim. At startup, fresh readback may resolve
an explicit action but does not populate committed band/nominal merely from polling.

`available_bands` is a unique array in the12-band strip order of S3 containing only
preferred entries admitted for selection.mode/backend. Manual uses the same initial
table capability. Its nonempty value does not authorize a mode action with unknown band.
No raw table import is accepted through these routes.

`operation` is null until normal admission, else exactly
`{command_id,base_revision,revision,action,requested,phase,result,error,monitor_before,monitor_wanted,old_job_id,new_job_id}`.
Action is mode|band; requested is exact `{mode,band,nominal_hz}` resolved before admission.
Phase is releasing|applying|restarting|applied|failed|release_blocked|cancelled; result
pending|success|failed|cancelled; error bounded code/null; monitor fields booleans;
job fields UUID/null. Applied/success requires nominal commit plus actual Start
admission when wanted, not running audio. CAT committed/audio Start failed preserves
that committed selection with failed result. Retain the last normal operation until
the next normal admission or boot. Its base/admission revisions never change on cancel.
A completed operation's recorded new job may be stopped only while the current full
tuple still belongs to it. Historical job IDs are not current-job authority.

`cancellation` is null or exactly `{command_id,target_command_id,revision,result}`,
result cancelled|fenced|already_cancelled. It is separate from the normal operation.
`receive` is exactly `{job_id,mode,state,audio_state,owner_released}`: job UUID/null;
mode spectrum|ft4|ft8|null; state null|running|cancelling|completed|cancelled|failed;
audio_state closed|opening|running|closing|unavailable. `owner_released` is actual joined
worker/native-owner release, never a failed state or deadline. Generation is the
top-level receive generation. Complete source/result/clock objects remain on `/receive`.

`radio` is exactly `{connection_generation,state,error,observations}`. Generation is
safe integer0 before connection, positive for an actual connection; state is
closed|connecting|ready|closing|unavailable; error bounded mapped code/null. Observations
is exactly `{frequency,mode,data,rx_tx,split}`. Each fact is exactly
`{value,query_sequence,observed_at_ms,confirmed}`. Unknown has all three nullable fields
null and confirmed=false. Known frequency is integer30000..74800000; mode value exact
`{mode,filter}` with mode USB|LSB|uppercase two-hex unknown and filter0..255 (only1..3
admitted for requested readiness); data exact `{enabled,filter}`, boolean/0..3;
rx_tx RX|TX; split boolean. Query sequence is a positive safe integer per connection;
observed_at_ms is boot-relative integer0..snapshot.monotonic_ms. Clear facts before any
new connection's query. Closed/closing/unavailable marks retained facts unconfirmed,
preserving their dated value/query provenance. Cached values do not establish readiness.

**S5. Cancellation, unknown outcomes and fencing.** Atomically distinguish:

- Unseen command: expected operating revision equals current, target unseen, no different
  active operation. Increment revision, retain result=fenced and acknowledge phase=cancelled.
  Do not create/replace a normal operation or stop an unrelated job. A delayed original
  POST using its old base then returns409state_conflict before effects. Empty GET alone
  cannot prove an original POST will never arrive; explicit fencing resolves that case.
- Last normal command: target matches it; expected revision equals current OR its base;
  current still equals its admission revision, with no intervening operation/profile
  edit/fence. Clear resume and invalidate token synchronously, advance revision and
  cancel pending typed work/its own current job only. Sent writes may remain applied;
  no restoring writes. Retained normal phase/result becomes cancelled, monitor_wanted=false,
  original admission revision retained; cancel receipt carries the new revision. Every
  callback checks the live token, not just admission revision.
- Superseded target: another operation/profile edit/fence advanced revision. Return
  409operation_superseded without effects on the later job. A fresh GET showing a newer
  revision proves the old base cannot admit. Exact retained cancel duplicates are
  idempotent and do not advance a revision, resend bytes or cancel another generation.

A read initiated after an unknown outcome may clear its barrier when it shows the
matching operation or revision greater than the original base. Same revision/absent
command keeps it blocked until an explicit fence succeeds. A pre-intent read cannot
clear the barrier even if delivered late. Changed boot invalidates old POST; discard
old context and fetch current profile/receive before control. No automatic mutation
replay or Stop/Start loop. Matching legacy Stop clears owning-transition resume as well
as its job; stale tuple refuses. When no matching job exists during a transition, the
operating Stop targets that command through cancel. Successful profile PUT keeps its
own persistence contract but invalidates the operation before later write/restart and
advances operating revision. Explicit normal selections desire Monitor ON; cancel OFF.

**S6. Same actor, per-query truth.** The aggregate `Observation.observed_at` cannot
freshen unqueried cached fields. Extend the existing actor/executor's safe completion
boundary with connection generation, positive query sequence, typed query kind, typed
decoded value and monotonic observation time. Emit only after a valid addressed reply
consumed by that query; ACK, echo, broadcast or setter completion is not a fresh fact.
Each query updates only its fact. On failed setter/timeout, mark every field possibly
touched by the composite unconfirmed immediately, retaining original dated values.
Successful final ReceiveSetup ReadMode/ReadData/ReadFrequency confirms those three
actual facts and selection only if all match this operation. It never freshens RX/split.

The serial actor alone owns physical identity/bytes/connection generation; the existing
Recording receive state owns operation token, captured profile/receive/operating identity,
lease, cancellation and publication. The station context retains the same actor handle.
Capture identity under its locks, release them, await actual release/CAT, then compare
token/revisions before commit/restart. Never execute bytes or callbacks while holding
profile/Recording locks; no owner calls another while holding its own I/O lock.
Existing read-only refresh remains at most1Hz and does not retry setters. `/radio`
keeps its dated aggregate version1 shape; per-field facts are on this new endpoint.
The existing actor lease plus transition lease returns busy to conflicting operations,
without a queue. Direct setters must use the same RF-context invalidation/release
barrier; keep those generic bindings unsupported until it exists. The initial UI
exposes mode/band only through coordinated selection, with no raw setter bypass.

**S7. Discovery, scheduling and measured traffic.** After authenticated current profile/
status/receive, discover with GET selection.404not_found,400unsupported_version or a
well-formed unsupported version disables new operating controls with an explanation;
legacy Start/Stop/Next receive and signal controls continue. Invalid schema or identity
is stale/error, not silent manual fallback. No existing status/WebSocket envelope
changes or unsolicited stream. Polling never opens devices or asks for permission.

At most one selection read and one ordinary mutation are pending in the browser,
sharing existing HTTP priority. Status/control precede optional visualization/results;
no added result parallelism. Thin/Off passive selection polling is no faster than8s,
pending-operation polling4s; Detailed fast-link passive2s/pending500ms. One explicit
reconciliation read is allowed when needed, not a retry loop. A stalled read prevents
further optional polling; Stop is not held behind a result read. No audio/fixture data
is transported. Existing32kbit/s Thin/Off <=3000B/s mean each direction and <=2s visible
status acceptance must include actual allowed selection polls and mode/band traffic,
all TLS/headers/transport, on the exact candidate. Body arithmetic is not bandwidth
proof. Fast-link cadence is not a32kbit/s promise.
Negotiated HTTP snapshot content coding is limited to12.1.1. The combined32kbit/s
proof uses real browsers negotiating supported gzip and records actual response
Content-Encoding; identity remains correct but has no identical-workload bandwidth
PASS without separate measurement. Existing caps refer to logical uncompressed JSON.
All previous14 suite registrations/assertions and the additive selection suite remain
required; no Cold/status10s,75s Thin/Off,4s/8s polling or other oracle is relaxed.


    */
}
