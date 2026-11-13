package WstxHttpContentCoding {
    private import ScalarValues::*;


    enum def HttpCodingSelection { identity; gzip; noAcceptable; }
    attribute def NegotiationOracleVector {
        attribute caseId : Integer;
        attribute orderedRawHeaderFieldsJson : String;
        attribute expected : HttpCodingSelection;
        doc /* JSON encodes separate raw Accept-Encoding fields in insertion order;
             [] is absent, not one empty field. Parse only to supply raw test input,
             never as production negotiation or an expected value derived from it. */
    }
    attribute negotiationSourceVersion : String = "tower-http0.7.1 content_encoding.rs";
    attribute negotiationSourceSha256 : String = "329bf57ef2a989f3128d96b845c4064dbda01a595b7e2fa1a594de77c18b9e56";
    attribute originalVectorArtifactSha256 : String = "d8da8bdb86485cc8691e2ad4f37afcbbaf84969c5b1a145f3a187a86d114a3c9";
    doc /* Original independent source/vector artifact digests are provenance, not
         a digest of this model serialization. Negotiation semantics below are
         established-library compatibility, not a claim conflicting duplicates have
         a unique interpretation mandated by HTTP. The complete ordered oracle is
         these49 typed cases, independent of candidate output. */
    attribute negotiation01 : NegotiationOracleVector {
        attribute :>> caseId = 1;
        attribute :>> orderedRawHeaderFieldsJson = "[]";
        attribute :>> expected = HttpCodingSelection::identity;
    }
    attribute negotiation02 : NegotiationOracleVector {
        attribute :>> caseId = 2;
        attribute :>> orderedRawHeaderFieldsJson = "[\"\"]";
        attribute :>> expected = HttpCodingSelection::identity;
    }
    attribute negotiation03 : NegotiationOracleVector {
        attribute :>> caseId = 3;
        attribute :>> orderedRawHeaderFieldsJson = "[\"identity\"]";
        attribute :>> expected = HttpCodingSelection::identity;
    }
    attribute negotiation04 : NegotiationOracleVector {
        attribute :>> caseId = 4;
        attribute :>> orderedRawHeaderFieldsJson = "[\"gzip\"]";
        attribute :>> expected = HttpCodingSelection::gzip;
    }
    attribute negotiation05 : NegotiationOracleVector {
        attribute :>> caseId = 5;
        attribute :>> orderedRawHeaderFieldsJson = "[\"GZip\"]";
        attribute :>> expected = HttpCodingSelection::gzip;
    }
    attribute negotiation06 : NegotiationOracleVector {
        attribute :>> caseId = 6;
        attribute :>> orderedRawHeaderFieldsJson = "[\"x-gzip\"]";
        attribute :>> expected = HttpCodingSelection::gzip;
    }
    attribute negotiation07 : NegotiationOracleVector {
        attribute :>> caseId = 7;
        attribute :>> orderedRawHeaderFieldsJson = "[\"gzip;q=0\"]";
        attribute :>> expected = HttpCodingSelection::identity;
    }
    attribute negotiation08 : NegotiationOracleVector {
        attribute :>> caseId = 8;
        attribute :>> orderedRawHeaderFieldsJson = "[\"gzip;q=0,identity;q=0\"]";
        attribute :>> expected = HttpCodingSelection::noAcceptable;
    }
    attribute negotiation09 : NegotiationOracleVector {
        attribute :>> caseId = 9;
        attribute :>> orderedRawHeaderFieldsJson = "[\"identity;q=0,gzip;q=bad\"]";
        attribute :>> expected = HttpCodingSelection::noAcceptable;
    }
    attribute negotiation10 : NegotiationOracleVector {
        attribute :>> caseId = 10;
        attribute :>> orderedRawHeaderFieldsJson = "[\"gzip;q=bad\"]";
        attribute :>> expected = HttpCodingSelection::identity;
    }
    attribute negotiation11 : NegotiationOracleVector {
        attribute :>> caseId = 11;
        attribute :>> orderedRawHeaderFieldsJson = "[\"br\"]";
        attribute :>> expected = HttpCodingSelection::identity;
    }
    attribute negotiation12 : NegotiationOracleVector {
        attribute :>> caseId = 12;
        attribute :>> orderedRawHeaderFieldsJson = "[\"br,identity;q=0\"]";
        attribute :>> expected = HttpCodingSelection::noAcceptable;
    }
    attribute negotiation13 : NegotiationOracleVector {
        attribute :>> caseId = 13;
        attribute :>> orderedRawHeaderFieldsJson = "[\"gzip;q=0.5\"]";
        attribute :>> expected = HttpCodingSelection::gzip;
    }
    attribute negotiation14 : NegotiationOracleVector {
        attribute :>> caseId = 14;
        attribute :>> orderedRawHeaderFieldsJson = "[\"gzip;q=0.5,identity;q=1\"]";
        attribute :>> expected = HttpCodingSelection::identity;
    }
    attribute negotiation15 : NegotiationOracleVector {
        attribute :>> caseId = 15;
        attribute :>> orderedRawHeaderFieldsJson = "[\"gzip;q=0.5,identity;q=0.5\"]";
        attribute :>> expected = HttpCodingSelection::gzip;
    }
    attribute negotiation16 : NegotiationOracleVector {
        attribute :>> caseId = 16;
        attribute :>> orderedRawHeaderFieldsJson = "[\"identity;q=0,gzip\"]";
        attribute :>> expected = HttpCodingSelection::gzip;
    }
    attribute negotiation17 : NegotiationOracleVector {
        attribute :>> caseId = 17;
        attribute :>> orderedRawHeaderFieldsJson = "[\"gzip;q=0.\"]";
        attribute :>> expected = HttpCodingSelection::identity;
    }
    attribute negotiation18 : NegotiationOracleVector {
        attribute :>> caseId = 18;
        attribute :>> orderedRawHeaderFieldsJson = "[\"gzip;q=1.\"]";
        attribute :>> expected = HttpCodingSelection::gzip;
    }
    attribute negotiation19 : NegotiationOracleVector {
        attribute :>> caseId = 19;
        attribute :>> orderedRawHeaderFieldsJson = "[\"gzip;Q=0.500\"]";
        attribute :>> expected = HttpCodingSelection::gzip;
    }
    attribute negotiation20 : NegotiationOracleVector {
        attribute :>> caseId = 20;
        attribute :>> orderedRawHeaderFieldsJson = "[\" gzip\\t; q=0.5 \"]";
        attribute :>> expected = HttpCodingSelection::gzip;
    }
    attribute negotiation21 : NegotiationOracleVector {
        attribute :>> caseId = 21;
        attribute :>> orderedRawHeaderFieldsJson = "[\"gzip;q =0.5\"]";
        attribute :>> expected = HttpCodingSelection::identity;
    }
    attribute negotiation22 : NegotiationOracleVector {
        attribute :>> caseId = 22;
        attribute :>> orderedRawHeaderFieldsJson = "[\"gzip;q= 0.5\"]";
        attribute :>> expected = HttpCodingSelection::identity;
    }
    attribute negotiation23 : NegotiationOracleVector {
        attribute :>> caseId = 23;
        attribute :>> orderedRawHeaderFieldsJson = "[\"gzip;q=.5\"]";
        attribute :>> expected = HttpCodingSelection::identity;
    }
    attribute negotiation24 : NegotiationOracleVector {
        attribute :>> caseId = 24;
        attribute :>> orderedRawHeaderFieldsJson = "[\"gzip;q=00.5\"]";
        attribute :>> expected = HttpCodingSelection::identity;
    }
    attribute negotiation25 : NegotiationOracleVector {
        attribute :>> caseId = 25;
        attribute :>> orderedRawHeaderFieldsJson = "[\"gzip;q=0.5000\"]";
        attribute :>> expected = HttpCodingSelection::identity;
    }
    attribute negotiation26 : NegotiationOracleVector {
        attribute :>> caseId = 26;
        attribute :>> orderedRawHeaderFieldsJson = "[\"gzip;q=1.001\"]";
        attribute :>> expected = HttpCodingSelection::identity;
    }
    attribute negotiation27 : NegotiationOracleVector {
        attribute :>> caseId = 27;
        attribute :>> orderedRawHeaderFieldsJson = "[\"gzip;q=-0.1\"]";
        attribute :>> expected = HttpCodingSelection::identity;
    }
    attribute negotiation28 : NegotiationOracleVector {
        attribute :>> caseId = 28;
        attribute :>> orderedRawHeaderFieldsJson = "[\"gzip;q=0.5;foo=bar\"]";
        attribute :>> expected = HttpCodingSelection::identity;
    }
    attribute negotiation29 : NegotiationOracleVector {
        attribute :>> caseId = 29;
        attribute :>> orderedRawHeaderFieldsJson = "[\"*\"]";
        attribute :>> expected = HttpCodingSelection::gzip;
    }
    attribute negotiation30 : NegotiationOracleVector {
        attribute :>> caseId = 30;
        attribute :>> orderedRawHeaderFieldsJson = "[\"*;q=0\"]";
        attribute :>> expected = HttpCodingSelection::noAcceptable;
    }
    attribute negotiation31 : NegotiationOracleVector {
        attribute :>> caseId = 31;
        attribute :>> orderedRawHeaderFieldsJson = "[\"*;q=0.5\"]";
        attribute :>> expected = HttpCodingSelection::gzip;
    }
    attribute negotiation32 : NegotiationOracleVector {
        attribute :>> caseId = 32;
        attribute :>> orderedRawHeaderFieldsJson = "[\"*;q=0,gzip;q=0.5\"]";
        attribute :>> expected = HttpCodingSelection::gzip;
    }
    attribute negotiation33 : NegotiationOracleVector {
        attribute :>> caseId = 33;
        attribute :>> orderedRawHeaderFieldsJson = "[\"*;q=1,gzip;q=0\"]";
        attribute :>> expected = HttpCodingSelection::identity;
    }
    attribute negotiation34 : NegotiationOracleVector {
        attribute :>> caseId = 34;
        attribute :>> orderedRawHeaderFieldsJson = "[\"*;q=1,identity;q=0\"]";
        attribute :>> expected = HttpCodingSelection::gzip;
    }
    attribute negotiation35 : NegotiationOracleVector {
        attribute :>> caseId = 35;
        attribute :>> orderedRawHeaderFieldsJson = "[\"*;q=0,identity;q=1\"]";
        attribute :>> expected = HttpCodingSelection::identity;
    }
    attribute negotiation36 : NegotiationOracleVector {
        attribute :>> caseId = 36;
        attribute :>> orderedRawHeaderFieldsJson = "[\"*;q=bad\"]";
        attribute :>> expected = HttpCodingSelection::identity;
    }
    attribute negotiation37 : NegotiationOracleVector {
        attribute :>> caseId = 37;
        attribute :>> orderedRawHeaderFieldsJson = "[\"*;q=bad,identity;q=0\"]";
        attribute :>> expected = HttpCodingSelection::noAcceptable;
    }
    attribute negotiation38 : NegotiationOracleVector {
        attribute :>> caseId = 38;
        attribute :>> orderedRawHeaderFieldsJson = "[\"gzip;q=0,gzip;q=1\"]";
        attribute :>> expected = HttpCodingSelection::gzip;
    }
    attribute negotiation39 : NegotiationOracleVector {
        attribute :>> caseId = 39;
        attribute :>> orderedRawHeaderFieldsJson = "[\"gzip;q=1,gzip;q=0\"]";
        attribute :>> expected = HttpCodingSelection::gzip;
    }
    attribute negotiation40 : NegotiationOracleVector {
        attribute :>> caseId = 40;
        attribute :>> orderedRawHeaderFieldsJson = "[\"gzip;q=0,gzip;q=1,*;q=0\"]";
        attribute :>> expected = HttpCodingSelection::noAcceptable;
    }
    attribute negotiation41 : NegotiationOracleVector {
        attribute :>> caseId = 41;
        attribute :>> orderedRawHeaderFieldsJson = "[\"gzip;q=1,gzip;q=0,*;q=0\"]";
        attribute :>> expected = HttpCodingSelection::gzip;
    }
    attribute negotiation42 : NegotiationOracleVector {
        attribute :>> caseId = 42;
        attribute :>> orderedRawHeaderFieldsJson = "[\"*;q=0,*;q=1\"]";
        attribute :>> expected = HttpCodingSelection::noAcceptable;
    }
    attribute negotiation43 : NegotiationOracleVector {
        attribute :>> caseId = 43;
        attribute :>> orderedRawHeaderFieldsJson = "[\"*;q=1,*;q=0\"]";
        attribute :>> expected = HttpCodingSelection::gzip;
    }
    attribute negotiation44 : NegotiationOracleVector {
        attribute :>> caseId = 44;
        attribute :>> orderedRawHeaderFieldsJson = "[\"*;q=bad,*;q=1\"]";
        attribute :>> expected = HttpCodingSelection::gzip;
    }
    attribute negotiation45 : NegotiationOracleVector {
        attribute :>> caseId = 45;
        attribute :>> orderedRawHeaderFieldsJson = "[\"gzip;q=0\", \"gzip;q=1\"]";
        attribute :>> expected = HttpCodingSelection::gzip;
    }
    attribute negotiation46 : NegotiationOracleVector {
        attribute :>> caseId = 46;
        attribute :>> orderedRawHeaderFieldsJson = "[\"gzip;q=0\", \"gzip;q=1,*;q=0\"]";
        attribute :>> expected = HttpCodingSelection::noAcceptable;
    }
    attribute negotiation47 : NegotiationOracleVector {
        attribute :>> caseId = 47;
        attribute :>> orderedRawHeaderFieldsJson = "[\"br;q=1\", \"gzip;q=0.4\"]";
        attribute :>> expected = HttpCodingSelection::gzip;
    }
    attribute negotiation48 : NegotiationOracleVector {
        attribute :>> caseId = 48;
        attribute :>> orderedRawHeaderFieldsJson = "[\"identity;q=0\", \"gzip;q=bad\"]";
        attribute :>> expected = HttpCodingSelection::noAcceptable;
    }
    attribute negotiation49 : NegotiationOracleVector {
        attribute :>> caseId = 49;
        attribute :>> orderedRawHeaderFieldsJson = "[\"gzip;q=bad,gzip;q=0.7\"]";
        attribute :>> expected = HttpCodingSelection::gzip;
    }
    calc def ExactCompressedGetRoute {
        in method : String;
        in path : String;
        return allowed : Boolean = method == "GET" and
            (path == "/receive/selection" or path == "/receive" or path == "/receive/results" or
             path == "/profile" or path == "/radio" or path == "/recording");
        doc /* Exact URI path only; valid /receive/results query remains unchanged.
             This is the complete six-route allowlist, not prefix matching. The #10
             contact routes (/contact, /contact/*, /contacts, /contacts/*) and
             /transmit/halt are deliberately excluded and stay identity-coded
             (WstxContact::ContactSnapshot); this allowlist is unchanged. */
    }
    calc def UncompressedGetLogicalCap {
        in path : String;
        return bytes : Integer = if path == "/receive/selection" ? 3072 else
            if path == "/radio" ? 2048 else if path == "/receive/results" ? 16384 else
            if path == "/profile" or path == "/recording" or path == "/receive" ? 8192 else 0;
        doc /* Zero denotes an excluded route, never admission for an empty JSON body.
             Logical UTF-8 representation caps apply before compression or negotiation. */
    }
    enum def SnapshotCodingAdmission { enum original; enum snapshotLimit; enum negotiate; }
    calc def SnapshotBeforeNegotiation {
        in exactAllowedGet : Boolean;
        in authenticatedSuccessfulJson : Boolean;
        in hasCredentials : Boolean;
        in headOrNoBody : Boolean;
        in alreadyEncodedOrRanged : Boolean;
        in exactSizeKnown : Boolean;
        in exactSize : Integer;
        in routeCap : Integer;
        return admission : SnapshotCodingAdmission = if not exactAllowedGet or
            not authenticatedSuccessfulJson or hasCredentials or headOrNoBody or
            alreadyEncodedOrRanged ? SnapshotCodingAdmission::original else
            if not exactSizeKnown or exactSize <= 0 or exactSize > routeCap ?
                SnapshotCodingAdmission::snapshotLimit else SnapshotCodingAdmission::negotiate;
        doc /* Evaluate existing handler exactly ONCE. Auth/original errors and excluded
             responses bypass negotiation entirely, even when all encodings are forbidden.
             An otherwise eligible success must have exact nonempty serialized size.
             Unknown/empty/excess size=>503 with exactly{error:{code:snapshot_limit,field:null}}
             before negotiation, retaining cache/security headers, with no body polling,
             buffering, second handler/auth/actor dispatch or redispatch. Only after
             this admission can noAcceptable produce406. A predicate evaluated by a
             library after negotiation is insufficient to preserve this ordering. */
    }
    requirement NegotiatedContentCoding {
        doc /* Transfer representation only; decompressed JSON fields/nulls/types,
             timestamps/query provenance/ownership/error semantics and logical caps
             remain unchanged. A successful authenticated allowlisted nonempty JSON
             GET selected as gzip MUST be gzip, even the2-byte{} body below library
             minimum-size defaults. Cookie/Authorization request headers used for
             authentication are not disqualifying; credentials never enter eligible JSON.
             With no wildcard select highest positive explicit supported q, gzip on
             tie; only if none remains use identity unless valididentity;q=0 rejects it.
             Do not inject implicitidentityq=1 into explicit competition. With wildcard,
             use FIRST valid explicitq per supported encoding else FIRST valid wildcardq,
             highest positiveq/gzip tie. Ignore invalidtokens/q, not positive acceptance;
             a later validduplicate may select encoding. Identityfallback is ONLY that
             permitted by this pinned algorithm; identity;q=0,gzip;q=bad=>406.
             Unsupported algorithms are never selected; malformed wire headers retain
             HTTP-stack refusal. No customAccept-Encoding parser or request decompression.
             /session, all nonGET including PUTprofile/POSToperations, /ws handshake or
             messages, auth/error/credential/authority responses are excluded. HEAD,
             no-body, existingContent-Encoding andContent-Range preserve original semantics.
             Static / is excluded. Static /app.js,/authorization.js,/recording.js,/logbook.js,/contact.js,
             /style.css,/recording.css (public, no secret or reflected input, so no
             BREACH exposure) are gzip only when the pinned algorithm positively selects
             gzip; every other negotiation, including all encodings forbidden, returns
             the exact identity bytes, never406 (issue22 supervisor decision).
             No lossy application codec, changed clocks, cached facts or blanket future
             TX/QSO/MCP compression permission. Re-review allowlist when responses gain secrets. */
    }
    requirement EncodedResponseHeaders {
        doc /* Encoded response hasContent-Encoding:gzip and original correct Content-Type.
             Merge exact comma-delimited case-insensitive Accept-Encoding token across ALL
             Vary fields, trimmingOWS and preserving unrelated values. X-Accept-Encoding-Other
             is NOT the token. Vary:* dominates and remains; otherwise append the exact
             token only when absent. No upstream substring match or overwrite. Remove stale
             uncompressedContent-Length; supplied encodedlength must be accurate, else
             normal streaming/chunked framing. Identitylength stays correct. Do not reuse
             a strongvalidator across unequal encoded bytes; no new ETag/conditional-cache
             promise. Preserve Cache-Control/security/CORS/auth headers; Vary never grants
             public/shared cacheability. No shared compressed-body cache or stale snapshots;
             context fresh per response, not shared across requests/users. */
    }
    part def HttpContentCodingBoundary {
        doc /* Six current GET routes have fixed serialized JSON. Each own logical cap
             and exact nonempty size precede negotiation. Unknown/excess is existing
             bounded503snapshot_limit {error:{code:"snapshot_limit",field:null}}, even
             all encodings forbidden; no polling/buffering/redispatch; retain security/cache. */
        attribute exactAllowedGet : Boolean;
        attribute authenticated : Boolean;
        attribute successfulJson : Boolean;
        attribute containsCredentials : Boolean;
        attribute logicalCapsSatisfied : Boolean;
        attribute nonempty : Boolean;
        attribute headOrNoBody : Boolean;
        attribute alreadyEncoded : Boolean;
        attribute contentRange : Boolean;
        attribute eligible : Boolean;
        attribute selection : HttpCodingSelection;
        attribute compressed : Boolean;
        attribute status406 : Boolean;
        constraint eligibility { eligible ==
            (exactAllowedGet and authenticated and successfulJson and
             not containsCredentials and logicalCapsSatisfied and nonempty and
             not headOrNoBody and not alreadyEncoded and not contentRange) }
        constraint exactCompression { compressed ==
            (eligible and selection == HttpCodingSelection::gzip) }
        constraint exactRefusal { status406 ==
            (eligible and selection == HttpCodingSelection::noAcceptable) }
        constraint excludedPreservation { not eligible implies
            (not compressed and not status406) }
        // HttpCodingSelection comes from pinned tower-http0.7.1, NegotiationOracleVector instances; no custom parser.
        // ALL eligible nonempty selected-gzip JSON encoded even <32bytes.
        // Ineligible responses preserve original status/bytes/headers before negotiation.
        // Vary exact-token merge BEFORE library; no substring comparison.
        // Logical schemas/caps/provenance/owner and WS/request representations unchanged.
    }
    verification def HttpNegotiationAndIdentity { doc /* TC009005case8 A/B: every pinned
       NegotiationOracleVector instances incl field order, duplicate/wildcard/malformed q; identity
       only when selected; noAcceptable406. Raw gzip/independent decoder, exact JSON,
       tiny2bytebody, correct Vary token merge and framing. */ }
    verification def HttpExcludedAndCaps { doc /* case8 C: HEAD/no-body/already-encoded/range,
       auth/errors/secrets/mutations bypass BEFORE negotiation, even all-encodings-forbidden;
       no duplicate effects, per-route logical caps/exact size before compression, unknown/excess503snapshot_limit before negotiation, no body polling/buffering/redispatch, no request decompression. */ }
    verification def HttpActualCombinedTls { doc /* case8 D: real two-browser native/CAT75s
       Thin and75sOff, unchanged TLS accounting/status/cadences/oracles; no estimated PASS. */ }
}
