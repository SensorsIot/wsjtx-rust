package WstxQsoPart {
    private import ScalarValues::*;
    private import WstxProfileAccess::ProfileAccess;
    private import WstxStationCommands::StationOperations;
    part def QsoAndLogging {
        doc /* Own exchange/completion/cancel and durable contacts; never bypass transmit authority or another profile storage. Stable completion identity and explicit persisted/unsaved outcome prevent silent duplicate contacts when completion replays. Concrete log schema/compatibility remains a target decision. */
        port operations : ~StationOperations;
        port contacts : ProfileAccess;
        port transmit : StationOperations;
        doc /* transmit carries contact transmissions only to TransmitService (WstxContact);
             no PTT, audio or radio port exists here. */
    }
}
