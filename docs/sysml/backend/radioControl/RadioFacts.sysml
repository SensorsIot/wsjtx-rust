package WstxRadioFacts {
    private import ScalarValues::*;
    attribute def RadioFacts {
        attribute frequencyHz : Integer[0..1];
        attribute usb : Boolean[0..1];
        attribute dataOn : Boolean[0..1];
        attribute filterNumber : Integer[0..1];
        attribute frequencyConfirmed : Boolean;
        attribute modeConfirmed : Boolean;
        attribute dataConfirmed : Boolean;
        attribute operationContext : String;
        doc /* contract 4.7.5: requested/committednominal versus physical facts separate.
             Each current fact has matching successful query provenance; aggregate
             observed_at cannot freshen cached unqueried fields. FIL1 not numeric
             width3000Hz. Partial failure never implies rollback or target success. */
    }
    enum def QueryKind { enum frequency; enum mode; enum data; enum rx_tx; enum split; }
    attribute maxSafe : Integer = (900719925 * 10000000 + 4740991);
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
    action def RadioFactPublication {
        doc /* S6 existingactor/executorreportsquerycompletionkind/value/provenance
             tostationalreadyownedstateoutsideI/Olocks. Possiblytouchedfieldsstale
             onpartialwrite;successupdatesonlyqueriedfact. Genericdirectsettercannot
             bypasssameRFcontextorchestration;keepunsupporteduntilbarrierbound.
             /radioexistingaggregatev1shapeunchanged,newfactsinselectionendpointonly. */
    }
}
