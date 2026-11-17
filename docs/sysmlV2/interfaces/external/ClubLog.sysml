package WstxClubLog {
    private import ScalarValues::*;
    private import ModelNotes::FollowsSource;

    doc /* The exchange with the Club Log service: the station asks for the Most Wanted
         list, the ranks of the DXCC entities by how much they are wanted. */

    item def MostWantedQuery {
        doc /* Ask for the list: one GET over HTTPS for sourceUrl. The station names
             itself to the service as WSTX-Rust with its version and the address of its
             project, and accepts JSON. The certificate of the service is checked
             against the certificate roots of the operating system. */
        attribute sourceUrl : String = "https://clublog.org/mostwanted.php?api=1";
    }
    attribute def MostWantedRow {
        doc /* One entry of the list. */
        attribute rank : String { doc /* A positive whole number, as text. */ }
        attribute adifNumber : String {
            doc /* The ADIF number of a DXCC entity: a positive whole number below
                 10000, as text or as a number. */ }
    }
    item def MostWantedDownload {
        doc /* The answer: a JSON object with one member for each MostWantedRow, the
             rank as its name and the number as its value. Only an answer with the
             status 200 is a list. */
        attribute entriesMax : Integer = 1000;
        attribute attribution : String =
            "Club Log Most Wanted list, Club Log (c) Michael Wells G7VJR, clublog.org" {
            doc /* The source line the station shows with the list. */ }
        attribute rows : MostWantedRow[1..*] {
            doc /* At most entriesMax rows; no number stands twice. */ }
        @FollowsSource {
            reference = "The Club Log service, mostwanted.php with api=1: a JSON "
                + "object from rank to ADIF DXCC number";
        }
    }
    port def ClubLogPort {
        doc /* Written from the profile's side; the service has the conjugate. A
             MostWantedQuery is answered by one MostWantedDownload. */
        out item query : MostWantedQuery;
        in item mostWanted : MostWantedDownload;
    }
    interface def ClubLog {
        doc /* The profile, the settings function, and the Club Log service. */
        end profile : ClubLogPort;
        end service : ~ClubLogPort;
    }
}
