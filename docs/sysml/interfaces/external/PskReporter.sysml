package WstxPskReporter {
    private import ScalarValues::*;

    port def PskReporterPort { in item heard : HeardSpots; }
    item def HeardSpots {
        doc /* Who hears me now. Reception reporting is FR-012's and is not part of this
             interface. */
    }
    interface def PskReporter {
        doc /* The spots function and the PSK Reporter broker, subscribe-only. */
        end spots : PskReporterPort;
        end broker : ~PskReporterPort;
    }
}
