package WstxDecodes {
    private import ScalarValues::*;
    private import WstxModeProcessing::ProcessingResult;

    doc /* What receive publishes from the frames it has decoded: one record for each
         frame, and one view for the decodes of each period. */

    item def ResultRecord :> ProcessingResult {
        doc /* One decoded frame as receive publishes it: the frame the modes part
             returned, with its number, its period and its DT. */
        attribute sequence : Integer {
            doc /* The number of the record: 0 for the first record of a job, one higher
                 for each record after it. */ }
        attribute periodStartUtc : String[0..1] {
            doc /* The start of the period the frame belongs to: UTC as date and time
                 with seven decimals of a second. Absent while the stream is not tied
                 to station time. */ }
        attribute dtSeconds : Real[0..1] {
            doc /* The DT of the frame in station time. Absent while the stream is not
                 tied to station time. */ }
        assert constraint boundedRecord {
            sequence >= 0
        }
    }

    attribute def JobIdentity {
        doc /* The job something published by receive belongs to. A consumer drops what
             belongs to another job than the current one. */
        attribute sourceId : String;
        attribute jobId : String;
    }

    item def PeriodView {
        doc /* Which records are the decodes of one period. A consumer that shows one
             period shows the records from firstSequence up to, and not including,
             nextSequence. */
        attribute id : Integer {
            doc /* 1 for the first view of a job, one higher for each view of another
                 period. A view that is published again for its period keeps its id. */ }
        attribute job : JobIdentity {
            doc /* The job whose records the view spans. */ }
        attribute firstSequence : Integer;
        attribute nextSequence : Integer;
        attribute periodStartUtc : String[0..1] {
            doc /* The start of the period, as in ResultRecord. Absent while the stream
                 is not tied to station time; the view then spans the records of one
                 window. */ }
        attribute complete : Boolean {
            doc /* True when a window of the period was decoded to its end. */ }
        attribute transmitted : Boolean {
            doc /* True for a period the station transmitted in; such a view has no
                 record. */ }
        assert constraint ordered { id >= 1 and firstSequence <= nextSequence }
    }

    port def DecodesPort {
        doc /* Written from receive's side. */
        out item result : ResultRecord;
        out item periodView : PeriodView;
    }
    interface def Decodes {
        doc /* The decoded frames and the view of each period, from receive to a
             consumer. */
        end receive : DecodesPort;
        end consumer : ~DecodesPort;
    }
}
