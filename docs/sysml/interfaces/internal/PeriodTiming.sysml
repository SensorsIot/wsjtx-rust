package WstxPeriodTiming {
    private import ScalarValues::*;
    port def PeriodTimingPort { out item boundaries : PeriodBoundaries; }
    item def PeriodBoundaries { doc /* The corrected UTC and the period boundaries. */ }
    interface def PeriodTiming {
        doc /* The clock's corrected UTC and period boundaries to a function that keeps time. */
        end clock : PeriodTimingPort;
        end consumer : ~PeriodTimingPort;
    }
    port def ClockStatusPort { out item quality : ClockQuality; }
    item def ClockQuality { doc /* The clock quality, the comparison with the time source. */ }
    interface def ClockStatus {
        doc /* The clock's quality to the station service. */
        end clock : ClockStatusPort;
        end station : ~ClockStatusPort;
    }
    enum def PeriodParity { enum even; enum odd; }
}
