package WstxClubLog {
    private import ScalarValues::*;

    port def ClubLogPort { in item mostWanted : MostWantedDownload; }
    item def MostWantedDownload { doc /* The most-wanted list, fetched on request. */ }
    interface def ClubLog {
        doc /* The ranking function and the Club Log most-wanted download. */
        end ranking : ClubLogPort;
        end service : ~ClubLogPort;
    }
}
