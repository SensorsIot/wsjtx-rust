package WstxCountryFile {
    private import ScalarValues::*;

    // ---------------------------------------------------------------- country data (#55)
    attribute def CountryFile {
        attribute bytesMax : Integer = 1048576;
        doc /* #55 (CL-055-01, CL-055-03). The DXCC country table is Jim Reisert AD1C's
             cty.dat as WSJT-X ships it: server/third-party/cty/cty.dat, copied unchanged
             from WSJT-X 3.3.0-beta5 (version VER20250115, 346 entities; source, SHA-256
             and the MIT-style permission notice in NOTICE.md and LICENSE beside it).
             It is embedded in the station. An uploaded file replaces it per station
             profile as cty.dat beside contacts.adi (written to a temporary file, flushed,
             renamed under the publication gate); a stored upload that cannot be read or
             parsed leaves the bundled table in use, is reported and is never
             overwritten. Nothing is downloaded automatically.
             Format (AD1CCty load_cty): an entity line "name: cq: itu: continent: lat:
             lon: utc: primary prefix:" (lon positive West; a leading * marks a WAE-only
             entity) followed by comma-separated entries up to ";"; "=" marks an exact
             call; an entry may carry (cq) [itu] <lat/lon> {continent} ~utc~ overrides.
             Lines that are no entity line are skipped; an invalid number, a CQ zone
             above 40 or ITU zone above 90 (also as an override), an unknown continent, a
             shown name (EntityOfCall) that is not 1..40 printable ASCII characters, a
             missing ";" or a file without entities is refused with the 1-based line, so
             every accepted file gives values the browser accepts. A key listed twice keeps its first entry. "=VERyyyymmdd" is
             the version. */
    }
    calc def EntityOfCall {
        in call : String;
        return entity : String[0..1];
        doc /* #55 (CL-055-01) as WSJT-X AD1CCty::lookup and Radio::effective_prefix: the
             call upper case; ending /MM or /AM: no entity. Operating suffixes are
             removed from the right while they are a digit, A, M, P, Q, R, QRP, FD, FF,
             AM, MM, LH, LT or LGT; of a remaining compound call the shorter side is the
             effective prefix (the left one when the right side is at least as long).
             When that differs from the call, an exact entry for the whole call wins.
             Otherwise the longest entry that starts the effective prefix, where an exact
             entry matches only the whole call. A KG4 call of length other than 3 or 5 is
             the United States entity (with that entry's overrides). The result is the
             entity with the entry's overrides: full name, primary prefix, continent, CQ
             and ITU zone, position. Shown name: WSJT-X abbreviated_entity_name, then the
             WAE entities shown as their DXCC (Bear Is., Shetland Is., AF Italy, Sicily,
             Vienna Intl Ctr, AF/EU Turkey), as with "Include extra WAE entities" off. */
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
             strategy's filter is WstxStrategy::NewNeeded, #97). The worked set
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
