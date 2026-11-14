package WstxHearing {
    private import ScalarValues::*;
    port def HearingPort { out item report : HearingReport; }
    item def HearingReport {
        doc /* Who hears me, and on which frequencies the target decodes. */
    }
    interface def Hearing {
        doc /* Who hears the station, from spots to a function that uses it. */
        end spots : HearingPort;
        end consumer : ~HearingPort;
    }
}
