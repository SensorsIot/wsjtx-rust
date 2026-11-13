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
}
