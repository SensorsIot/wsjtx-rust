package WstxClubLog {
    private import ScalarValues::*;
    private import ModelNotes::FollowsSource;

    port def ClubLogPort { in item mostWanted : MostWantedDownload; }
    attribute def MostWantedRow {
        attribute rank : String;
        attribute adifNumber : String;
        doc /* One entry of the download: the rank and the ADIF DXCC number, each a positive integer in text
             (the number may also be a JSON number). */
    }
    item def MostWantedDownload {
        attribute sourceUrl : String = "https://clublog.org/mostwanted.php?api=1";
        attribute rows : MostWantedRow[0..*];
        @FollowsSource {
            reference = "https://clublog.org/mostwanted.php?api=1: a JSON object {\"1\":\"344\", ...} from rank "
                + "to ADIF DXCC number (340 entries when read)";
        }
        doc /* The most-wanted list, fetched on request: the station fetches the source once on the operator's
             click, with the User-Agent of most_wanted::USER_AGENT naming this project. Club Log states no
             terms for it. */
    }
    interface def ClubLog {
        doc /* The ranking function and the Club Log most-wanted download. */
        end ranking : ClubLogPort;
        end service : ~ClubLogPort;
    }
}
