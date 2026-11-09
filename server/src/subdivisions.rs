#![forbid(unsafe_code)]
//! WstxContest::Subdivisions (#98, CL-098-03): one table of US states and DC, VE provinces,
//! the older VE codes and the other values of the RTTY Roundup list, and the ARRL and RAC
//! sections with the states or provinces each covers. Bundled with the station, not part of
//! the uploadable contest file; #97's US-state list reads it.
use std::sync::OnceLock;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Kind {
    UsState,
    VeProvince,
    VeAlias,
    NlProvince,
    RttyNumber,
    ArrlSection,
    RacSection,
    Dx,
}
impl Kind {
    pub(crate) fn name(self) -> &'static str {
        match self {
            Kind::UsState => "us_state",
            Kind::VeProvince => "ve_province",
            Kind::VeAlias => "ve_alias",
            Kind::NlProvince => "nl_province",
            Kind::RttyNumber => "rtty_number",
            Kind::ArrlSection => "arrl_section",
            Kind::RacSection => "rac_section",
            Kind::Dx => "dx",
        }
    }
}
/// One row {kind, code, name, maps_to, rtty_ru, fd}.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Row {
    pub kind: Kind,
    pub code: String,
    pub name: String,
    pub maps_to: Vec<String>,
    pub rtty_ru: bool,
    pub fd: bool,
}
const US_STATES: &[(&str, &str)] = &[
    ("AL", "Alabama"),
    ("AK", "Alaska"),
    ("AZ", "Arizona"),
    ("AR", "Arkansas"),
    ("CA", "California"),
    ("CO", "Colorado"),
    ("CT", "Connecticut"),
    ("DE", "Delaware"),
    ("DC", "District of Columbia"),
    ("FL", "Florida"),
    ("GA", "Georgia"),
    ("HI", "Hawaii"),
    ("ID", "Idaho"),
    ("IL", "Illinois"),
    ("IN", "Indiana"),
    ("IA", "Iowa"),
    ("KS", "Kansas"),
    ("KY", "Kentucky"),
    ("LA", "Louisiana"),
    ("ME", "Maine"),
    ("MD", "Maryland"),
    ("MA", "Massachusetts"),
    ("MI", "Michigan"),
    ("MN", "Minnesota"),
    ("MS", "Mississippi"),
    ("MO", "Missouri"),
    ("MT", "Montana"),
    ("NE", "Nebraska"),
    ("NV", "Nevada"),
    ("NH", "New Hampshire"),
    ("NJ", "New Jersey"),
    ("NM", "New Mexico"),
    ("NY", "New York"),
    ("NC", "North Carolina"),
    ("ND", "North Dakota"),
    ("OH", "Ohio"),
    ("OK", "Oklahoma"),
    ("OR", "Oregon"),
    ("PA", "Pennsylvania"),
    ("RI", "Rhode Island"),
    ("SC", "South Carolina"),
    ("SD", "South Dakota"),
    ("TN", "Tennessee"),
    ("TX", "Texas"),
    ("UT", "Utah"),
    ("VT", "Vermont"),
    ("VA", "Virginia"),
    ("WA", "Washington"),
    ("WV", "West Virginia"),
    ("WI", "Wisconsin"),
    ("WY", "Wyoming"),
];
const VE_PROVINCES: &[(&str, &str)] = &[
    ("AB", "Alberta"),
    ("BC", "British Columbia"),
    ("MB", "Manitoba"),
    ("NB", "New Brunswick"),
    ("NL", "Newfoundland and Labrador"),
    ("NS", "Nova Scotia"),
    ("NT", "Northwest Territories"),
    ("NU", "Nunavut"),
    ("ON", "Ontario"),
    ("PE", "Prince Edward Island"),
    ("QC", "Quebec"),
    ("SK", "Saskatchewan"),
    ("YT", "Yukon"),
];
/// The provinces whose codes are in the RTTY Roundup list as they are.
const VE_RTTY: &[&str] = &["AB", "BC", "MB", "NB", "NS", "QC", "ON", "SK", "NU", "YT"];
const VE_ALIASES: &[(&str, &str, &str)] = &[
    ("NWT", "Northwest Territories (old code)", "NT"),
    ("NF", "Newfoundland (old code)", "NL"),
    ("LB", "Labrador (old code)", "NL"),
    ("PEI", "Prince Edward Island (old code)", "PE"),
];
const NL_PROVINCES: &[(&str, &str)] = &[
    ("DR", "Drenthe"),
    ("FR", "Friesland"),
    ("GD", "Gelderland"),
    ("GR", "Groningen"),
    ("OV", "Overijssel"),
    ("ZH", "Zuid-Holland"),
    ("ZL", "Zeeland"),
];
const ARRL_SECTIONS: &[(&str, &str, &[&str])] = &[
    ("AK", "Alaska", &["AK"]),
    ("AL", "Alabama", &["AL"]),
    ("AR", "Arkansas", &["AR"]),
    ("AZ", "Arizona", &["AZ"]),
    ("CO", "Colorado", &["CO"]),
    ("CT", "Connecticut", &["CT"]),
    ("DE", "Delaware", &["DE"]),
    ("EB", "East Bay", &["CA"]),
    ("EMA", "Eastern Massachusetts", &["MA"]),
    ("ENY", "Eastern New York", &["NY"]),
    ("EPA", "Eastern Pennsylvania", &["PA"]),
    ("EWA", "Eastern Washington", &["WA"]),
    ("GA", "Georgia", &["GA"]),
    ("IA", "Iowa", &["IA"]),
    ("ID", "Idaho", &["ID"]),
    ("IL", "Illinois", &["IL"]),
    ("IN", "Indiana", &["IN"]),
    ("KS", "Kansas", &["KS"]),
    ("KY", "Kentucky", &["KY"]),
    ("LA", "Louisiana", &["LA"]),
    ("LAX", "Los Angeles", &["CA"]),
    ("MDC", "Maryland-DC", &["MD", "DC"]),
    ("ME", "Maine", &["ME"]),
    ("MI", "Michigan", &["MI"]),
    ("MN", "Minnesota", &["MN"]),
    ("MO", "Missouri", &["MO"]),
    ("MS", "Mississippi", &["MS"]),
    ("MT", "Montana", &["MT"]),
    ("NC", "North Carolina", &["NC"]),
    ("ND", "North Dakota", &["ND"]),
    ("NE", "Nebraska", &["NE"]),
    ("NFL", "Northern Florida", &["FL"]),
    ("NH", "New Hampshire", &["NH"]),
    ("NLI", "New York City and Long Island", &["NY"]),
    ("NM", "New Mexico", &["NM"]),
    ("NNJ", "Northern New Jersey", &["NJ"]),
    ("NNY", "Northern New York", &["NY"]),
    ("NTX", "North Texas", &["TX"]),
    ("NV", "Nevada", &["NV"]),
    ("OH", "Ohio", &["OH"]),
    ("OK", "Oklahoma", &["OK"]),
    ("OR", "Oregon", &["OR"]),
    ("ORG", "Orange", &["CA"]),
    ("PAC", "Pacific", &["HI"]),
    ("PR", "Puerto Rico", &[]),
    ("RI", "Rhode Island", &["RI"]),
    ("SB", "Santa Barbara", &["CA"]),
    ("SC", "South Carolina", &["SC"]),
    ("SCV", "Santa Clara Valley", &["CA"]),
    ("SD", "South Dakota", &["SD"]),
    ("SDG", "San Diego", &["CA"]),
    ("SF", "San Francisco", &["CA"]),
    ("SFL", "Southern Florida", &["FL"]),
    ("SJV", "San Joaquin Valley", &["CA"]),
    ("SNJ", "Southern New Jersey", &["NJ"]),
    ("STX", "South Texas", &["TX"]),
    ("SV", "Sacramento Valley", &["CA"]),
    ("TN", "Tennessee", &["TN"]),
    ("UT", "Utah", &["UT"]),
    ("VA", "Virginia", &["VA"]),
    ("VI", "Virgin Islands", &[]),
    ("VT", "Vermont", &["VT"]),
    ("WCF", "West Central Florida", &["FL"]),
    ("WI", "Wisconsin", &["WI"]),
    ("WMA", "Western Massachusetts", &["MA"]),
    ("WNY", "Western New York", &["NY"]),
    ("WPA", "Western Pennsylvania", &["PA"]),
    ("WTX", "West Texas", &["TX"]),
    ("WV", "West Virginia", &["WV"]),
    ("WWA", "Western Washington", &["WA"]),
    ("WY", "Wyoming", &["WY"]),
];
const RAC_SECTIONS: &[(&str, &str, &[&str])] = &[
    ("AB", "Alberta", &["AB"]),
    ("BC", "British Columbia", &["BC"]),
    ("GH", "Golden Horseshoe", &["ON"]),
    ("MB", "Manitoba", &["MB"]),
    ("NB", "New Brunswick", &["NB"]),
    ("NL", "Newfoundland and Labrador", &["NL"]),
    ("NS", "Nova Scotia", &["NS"]),
    ("ONE", "Ontario East", &["ON"]),
    ("ONN", "Ontario North", &["ON"]),
    ("ONS", "Ontario South", &["ON"]),
    ("PE", "Prince Edward Island", &["PE"]),
    ("QC", "Quebec", &["QC"]),
    ("SK", "Saskatchewan", &["SK"]),
    ("TER", "Territories", &["NT", "NU", "YT"]),
];
fn row(kind: Kind, code: &str, name: &str, maps_to: &[&str], rtty_ru: bool, fd: bool) -> Row {
    Row {
        kind,
        code: code.to_owned(),
        name: name.to_owned(),
        maps_to: maps_to.iter().map(|s| (*s).to_owned()).collect(),
        rtty_ru,
        fd,
    }
}
/// The table, in kind order.
pub(crate) fn table() -> &'static [Row] {
    static T: OnceLock<Vec<Row>> = OnceLock::new();
    T.get_or_init(|| {
        let mut t = Vec::new();
        for (c, n) in US_STATES {
            t.push(row(Kind::UsState, c, n, &[c], true, false));
        }
        for (c, n) in VE_PROVINCES {
            t.push(row(Kind::VeProvince, c, n, &[c], VE_RTTY.contains(c), false));
        }
        for (c, n, to) in VE_ALIASES {
            t.push(row(Kind::VeAlias, c, n, &[to], true, false));
        }
        for (c, n) in NL_PROVINCES {
            t.push(row(Kind::NlProvince, c, n, &[c], true, false));
        }
        for i in 1..=99 {
            let c = format!("X{i:02}");
            t.push(row(
                Kind::RttyNumber,
                &c,
                &format!("RTTY Roundup number {i}"),
                &[],
                true,
                false,
            ));
        }
        for (c, n, to) in ARRL_SECTIONS {
            t.push(row(Kind::ArrlSection, c, n, to, false, true));
        }
        for (c, n, to) in RAC_SECTIONS {
            t.push(row(Kind::RacSection, c, n, to, false, true));
        }
        t.push(row(Kind::Dx, "DX", "DX (outside W/VE)", &[], false, true));
        t
    })
}
/// The rows of a code (a code may be a state and a section, e.g. AK or OH).
pub(crate) fn rows(code: &str) -> impl Iterator<Item = &'static Row> + '_ {
    table().iter().filter(move |r| r.code == code)
}
/// The single US state or VE province a received Field Day section gives (None: several,
/// none, or not a section).
pub(crate) fn section_state(section: &str) -> Option<&'static str> {
    let r = rows(section).find(|r| r.fd)?;
    (r.maps_to.len() == 1).then(|| r.maps_to[0].as_str())
}
/// The single US state or VE province a received RTTY Roundup value gives.
pub(crate) fn rtty_state(value: &str) -> Option<&'static str> {
    let r = rows(value).find(|r| r.rtty_ru)?;
    let to = (r.maps_to.len() == 1).then(|| r.maps_to[0].as_str())?;
    rows(to)
        .any(|x| matches!(x.kind, Kind::UsState | Kind::VeProvince))
        .then_some(to)
}
