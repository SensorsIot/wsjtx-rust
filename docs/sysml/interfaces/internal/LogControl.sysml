package WstxLogControl {
    private import ScalarValues::*;
    port def LogControlPort {
        out item command : LogCommand;
        in item 'state' : LogState;
    }
    item def LogCommand { doc /* Export, import, edits, the contest scoring rules. */ }
    item def LogState { doc /* The log state. */ }
    interface def LogControl {
        doc /* The station service commands the log function; log reports its state. */
        end station : LogControlPort;
        end log : ~LogControlPort;
    }
    attribute def DecodedEntity {
        doc /* #55 (CL-055-02). GET /receive/results adds to each decoded record whose
             sender call resolves the optional keys below; other records are unchanged. The
             sender call is the 'from' call, also a filled-in hash; of a nonstandard (i3=4)
             message its full call, or its filled-in hash when that comes second; of a
             DXpedition message its hashed call, for dxcc only because Band Activity names
             no sender for that form. A hash nobody heard ("<...>") and a free text have
             none. The keys:
             dxcc {name (shown name), cont, cq, itu, km (only with a profile locator:
             great circle in whole km to the entity position)} when the sender has an
             entity; flags {name: true ...} holding only the flags that are true, omitted
             when none is or the log is unreadable: new_call (the call, case-insensitive)
             and new_grid (the 4-character square of the message grid; none without a
             grid) not in the log; new_dxcc (entity full name, WAE entities by their own
             name as in WSJT-X), new_continent, new_cq_zone, new_itu_zone not in the log
             (from EntityOfCall of each logged call; a logged call without an entity
             counts for nothing); each with its _band form: not on this band in any mode
             (WSJT-X LogBook::match with highlight by mode off, its default; the
             strategy's filter is WstxValueOrder::NewNeeded, #97). The worked set
             is rebuilt only when the log or the country table changes; the annotation
             runs off the async runtime. Band: the CAT dial
             band, else the operating selection band; without a band no _band flag is
             set. worked_status (notWorked as not_worked, workedOtherBandOrMode as
             worked_other_band_or_mode, workedThisBandAndMode as worked_this_band_and_mode,
             WorkedBeforeQuery of that band and the job's mode) on a standard message whose
             'from' is a concrete call, not a hash, when a band is known. The browser accepts exactly these optional keys and values; any other
             key or value refuses the page like any invalid record. */
    }
    attribute def CountryFileHttp {
        doc /* #55 (CL-055-03). GET /dxcc (read): {v:1, profile_id, boot_id, source
             "bundled"|"uploaded", version (the =VER marker or null), entities,
             upload_unreadable}; with ?call=<1..13 of A-Z 0-9 /, unencoded> also entity (the dxcc
             object of DecodedEntity or null), any other query 400 invalid_request call.
             PUT /dxcc {v, profile_id, boot_id, text} with exactly these keys, body at
             most 2 MiB: text null removes the upload (bundled again); a string of at most
             CountryFile::bytesMax bytes replaces it when it parses, else 400
             {error:{code:invalid_cty, field:text, line}}; other text 400 invalid_request
             text. Profile, boot, Origin and authorization checks as the log routes
             (wrong Origin 403, stale boot 409 state_conflict, revoked grant 401);
             a refusal changes neither the file nor the table. 200 is the new view.
             Environment-only mode: 404. */
    }
}
