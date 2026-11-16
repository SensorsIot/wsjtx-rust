package WstxStationTime {
    private import ScalarValues::*;

    enum def StationTimeState {
        doc /* Whether station time agrees with the stations heard. */
        enum synchronized;
        enum unsynchronized;
    }
    enum def ClockState {
        doc /* Whether the PC clock agrees with the time server. */
        enum synchronized;
        enum unsynchronized;
        enum unknown;
    }

    item def StationTime {
        doc /* Station time at the moment it is read. */
        attribute utcMs : Integer {
            doc /* Milliseconds of UTC: the PC clock plus the clock's correction. */ }
        attribute timeState : StationTimeState;
    }
    port def StationTimePort { out item time : StationTime; }
    interface def StationTimeLink {
        doc /* Written from the clock's side: the clock gives station time to a function
             that keeps time. */
        end clock : StationTimePort;
        end consumer : ~StationTimePort;
    }

    item def StationHeard {
        doc /* One decoded frame whose message names its sender. */
        attribute call : String { doc /* The sending call. */ }
        attribute dtMs : Integer {
            doc /* The DT of the frame against the PC clock, without the clock's
                 correction. */ }
        attribute snrDb : Real[0..1] { doc /* Absent when the frame has none. */ }
    }
    item def WindowDone {
        doc /* Receive has finished the decoding of a window. */
        attribute periodMs : Integer {
            doc /* The period length of the mode that was decoded. */ }
    }
    port def StationsHeardPort {
        out item heard : StationHeard;
        out item done : WindowDone;
    }
    interface def StationsHeard {
        doc /* Written from receive's side: receive gives the clock the stations it hears,
             from which the clock estimates how far station time is off. */
        end receive : StationsHeardPort;
        end clock : ~StationsHeardPort;
    }

    enum def ClockWarning {
        doc /* What the operator should know about the clock. At most one holds at a time. */
        enum pcClockOff;
        enum ntpUnreachable;
        enum stationsOff;
    }
    enum def WindowsTimeState {
        doc /* The state of the Windows time service, as read without administrator rights. */
        enum running;
        enum stopped;
        enum disabled;
        enum unknown;
    }
    attribute def TimeServerReading {
        doc /* The latest valid answer of a time server. */
        attribute server : String;
        attribute offsetMs : Integer { doc /* The PC clock against the server. */ }
        attribute roundTripMs : Integer;
        attribute ageMs : Integer;
    }
    attribute def AirEstimate {
        doc /* The latest estimate from the stations heard. */
        attribute medianDtMs : Integer { doc /* The middle of the stations' DT. */ }
        attribute stations : Integer { doc /* The stations that voted. */ }
        attribute plus : Integer { doc /* The votes later than station time. */ }
        attribute minus : Integer { doc /* The votes earlier than station time. */ }
        attribute ageMs : Integer;
    }
    item def ClockQuality {
        doc /* How well station time is known, and why, at the moment it is read. */
        attribute timeState : StationTimeState { doc /* As StationTime::timeState. */ }
        attribute correctionMs : Integer {
            doc /* What the clock adds to the PC clock. */ }
        attribute warning : ClockWarning[0..1] { doc /* Absent while none holds. */ }
        attribute timeServerState : ClockState {
            doc /* The PC clock against the time server; unknown without a reading. */ }
        attribute timeServer : TimeServerReading[0..1] {
            doc /* Absent before the first valid answer. */ }
        attribute windowsTime : WindowsTimeState;
        attribute air : AirEstimate[0..1] { doc /* Absent before the first estimate. */ }
    }
    port def ClockStatusPort { out item quality : ClockQuality; }
    interface def ClockStatus {
        doc /* Written from the clock's side: the clock gives its quality to the station
             service. */
        end clock : ClockStatusPort;
        end station : ~ClockStatusPort;
    }
}
