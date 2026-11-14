package WstxTimeSource {
    private import ScalarValues::*;

    port def TimeSourcePort;
    item def TimeSourceItem { doc /* What the clock and a time server exchange. */ }
    interface def TimeSource {
        doc /* The clock and an SNTP time server. */
        end clock : TimeSourcePort;
        end server : ~TimeSourcePort;
        item exchange : TimeSourceItem;
    }
}
