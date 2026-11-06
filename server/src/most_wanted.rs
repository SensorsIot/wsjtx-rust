#![forbid(unsafe_code)]
//! WstxStrategy::MostWantedList (#39): the Club Log Most Wanted list (rank -> ADIF DXCC
//! number), its validation and the table from cty.dat entity names to ADIF numbers.
//! No automatic refresh and no bundled copy until the operator rules on the terms (D12).
use serde_json::{Value, json};
use std::collections::HashMap;
use std::sync::OnceLock;

pub const FILE_NAME: &str = "most_wanted.json";
pub const FILE_BYTES_MAX: u64 = 262_144;
pub const ENTRIES_MAX: usize = 1000;
pub const SOURCE_URL: &str = "https://clublog.org/mostwanted.php?api=1";
pub const USER_AGENT: &str = concat!(
    "WSTX-Rust/",
    env!("CARGO_PKG_VERSION"),
    " (+https://github.com/SensorsIot/wsjtx-rust)"
);
pub const ATTRIBUTION: &str =
    "Club Log Most Wanted list, Club Log (c) Michael Wells G7VJR, clublog.org";

/// A validated list: rank per ADIF number, with its status.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct List {
    ranks: HashMap<u16, u32>,
    pub date: String,
    pub source: String,
    pub unmapped: usize,
}
impl List {
    /// Parses list JSON text exactly (MostWantedList); `None` refuses it.
    pub fn parse(text: &str, date: &str, source: &str) -> Option<Self> {
        let v: Value = serde_json::from_str(text).ok()?;
        Self::from_value(&v, date, source)
    }
    pub fn from_value(v: &Value, date: &str, source: &str) -> Option<Self> {
        let o = v.as_object()?;
        if o.is_empty() || o.len() > ENTRIES_MAX {
            return None;
        }
        let mut ranks = HashMap::new();
        for (rank, number) in o {
            let rank: u32 = rank.parse().ok().filter(|r| *r > 0)?;
            let number = match number {
                Value::String(s) => s.parse::<u16>().ok()?,
                n => u16::try_from(n.as_u64()?).ok()?,
            };
            if !(1..10_000).contains(&number) || ranks.insert(number, rank).is_some() {
                return None;
            }
        }
        let known = known_numbers();
        let unmapped = ranks.keys().filter(|n| !known.contains(n)).count();
        Some(Self {
            ranks,
            date: date.to_owned(),
            source: source.to_owned(),
            unmapped,
        })
    }
    pub fn entries(&self) -> usize {
        self.ranks.len()
    }
    /// The rank of a cty.dat entity by its full name (None: not on the list).
    pub fn rank(&self, entity: &str) -> Option<u32> {
        self.ranks.get(&adif_number(entity)?).copied()
    }
    /// The list as the source writes it, for the store.
    pub fn list_json(&self) -> Value {
        Value::Object(
            self.ranks
                .iter()
                .map(|(number, rank)| (rank.to_string(), json!(number.to_string())))
                .collect(),
        )
    }
    pub fn status(&self) -> Value {
        json!({"date":self.date,"source":self.source,"entries":self.entries(),"unmapped":self.unmapped})
    }
}
fn table() -> &'static HashMap<&'static str, u16> {
    static TABLE: OnceLock<HashMap<&'static str, u16>> = OnceLock::new();
    TABLE.get_or_init(|| ENTITIES.iter().copied().collect())
}
fn known_numbers() -> std::collections::HashSet<u16> {
    ENTITIES.iter().map(|e| e.1).collect()
}
/// The ADIF DXCC number of a cty.dat entity full name.
pub fn adif_number(entity: &str) -> Option<u16> {
    table().get(entity).copied()
}
/// #39 Download now, once on the operator's click: the list text of SOURCE_URL.
pub fn fetch() -> Result<String, String> {
    fetch_url(SOURCE_URL)
}

/// cty.dat entity full name -> ADIF DXCC number, from AD1C's cty.csv of 2026-11 (its third
/// column). WAE-only entities carry their DXCC parent's number; where the bundled cty.dat of
/// 2025 and the current file name an entity differently both names are listed.
pub const ENTITIES: &[(&str, u16)] = &[
    ("Afghanistan", 3),
    ("African Italy", 248),
    ("Agalega & St. Brandon", 4),
    ("Aland Islands", 5),
    ("Alaska", 6),
    ("Albania", 7),
    ("Algeria", 400),
    ("American Samoa", 9),
    ("Amsterdam & St. Paul Is.", 10),
    ("Andaman & Nicobar Is.", 11),
    ("Andorra", 203),
    ("Angola", 401),
    ("Anguilla", 12),
    ("Annobon Island", 195),
    ("Antarctica", 13),
    ("Antigua & Barbuda", 94),
    ("Argentina", 100),
    ("Armenia", 14),
    ("Aruba", 91),
    ("Ascension Island", 205),
    ("Asiatic Russia", 15),
    ("Asiatic Turkey", 390),
    ("Austral Islands", 508),
    ("Australia", 150),
    ("Austria", 206),
    ("Aves Island", 17),
    ("Azerbaijan", 18),
    ("Azores", 149),
    ("Bahamas", 60),
    ("Bahrain", 304),
    ("Baker & Howland Islands", 20),
    ("Balearic Islands", 21),
    ("Banaba Island", 490),
    ("Bangladesh", 305),
    ("Barbados", 62),
    ("Bear Island", 259),
    ("Belarus", 27),
    ("Belgium", 209),
    ("Belize", 66),
    ("Benin", 416),
    ("Bermuda", 64),
    ("Bhutan", 306),
    ("Bolivia", 104),
    ("Bonaire", 520),
    ("Bosnia-Herzegovina", 501),
    ("Botswana", 402),
    ("Bouvet", 24),
    ("Brazil", 108),
    ("British Virgin Islands", 65),
    ("Brunei Darussalam", 345),
    ("Bulgaria", 212),
    ("Burkina Faso", 480),
    ("Burundi", 404),
    ("Cabo Verde", 409),
    ("Cambodia", 312),
    ("Cameroon", 406),
    ("Canada", 1),
    ("Canary Islands", 29),
    ("Cape Verde", 409),
    ("Cayman Islands", 69),
    ("Central African Republic", 408),
    ("Central Kiribati", 31),
    ("Ceuta & Melilla", 32),
    ("Chad", 410),
    ("Chagos Islands", 33),
    ("Chatham Islands", 34),
    ("Chesterfield Islands", 512),
    ("Chile", 112),
    ("China", 318),
    ("Christmas Island", 35),
    ("Clipperton Island", 36),
    ("Cocos (Keeling) Islands", 38),
    ("Cocos Island", 37),
    ("Colombia", 116),
    ("Comoros", 411),
    ("Conway Reef", 489),
    ("Corsica", 214),
    ("Costa Rica", 308),
    ("Cote d'Ivoire", 428),
    ("Crete", 40),
    ("Croatia", 497),
    ("Crozet Island", 41),
    ("Cuba", 70),
    ("Curacao", 517),
    ("Cyprus", 215),
    ("Czech Republic", 503),
    ("DPR of Korea", 344),
    ("Dem. Rep. of the Congo", 414),
    ("Denmark", 221),
    ("Desecheo Island", 43),
    ("Djibouti", 382),
    ("Dodecanese", 45),
    ("Dominica", 95),
    ("Dominican Republic", 72),
    ("Ducie Island", 513),
    ("East Malaysia", 46),
    ("Easter Island", 47),
    ("Eastern Kiribati", 48),
    ("Ecuador", 120),
    ("Egypt", 478),
    ("El Salvador", 74),
    ("England", 223),
    ("Equatorial Guinea", 49),
    ("Eritrea", 51),
    ("Estonia", 52),
    ("Ethiopia", 53),
    ("European Russia", 54),
    ("European Turkey", 390),
    ("Falkland Islands", 141),
    ("Faroe Islands", 222),
    ("Fed. Rep. of Germany", 230),
    ("Fernando de Noronha", 56),
    ("Fiji", 176),
    ("Finland", 224),
    ("France", 227),
    ("Franz Josef Land", 61),
    ("French Guiana", 63),
    ("French Polynesia", 175),
    ("Gabon", 420),
    ("Galapagos Islands", 71),
    ("Georgia", 75),
    ("Ghana", 424),
    ("Gibraltar", 233),
    ("Glorioso Islands", 99),
    ("Greece", 236),
    ("Greenland", 237),
    ("Grenada", 77),
    ("Guadeloupe", 79),
    ("Guam", 103),
    ("Guantanamo Bay", 105),
    ("Guatemala", 76),
    ("Guernsey", 106),
    ("Guinea", 107),
    ("Guinea-Bissau", 109),
    ("Guyana", 129),
    ("Haiti", 78),
    ("Hawaii", 110),
    ("Heard Island", 111),
    ("Honduras", 80),
    ("Hong Kong", 321),
    ("Hungary", 239),
    ("ITU HQ", 117),
    ("Iceland", 242),
    ("India", 324),
    ("Indonesia", 327),
    ("Iran", 330),
    ("Iraq", 333),
    ("Ireland", 245),
    ("Isle of Man", 114),
    ("Israel", 336),
    ("Italy", 248),
    ("Jamaica", 82),
    ("Jan Mayen", 118),
    ("Japan", 339),
    ("Jersey", 122),
    ("Johnston Island", 123),
    ("Jordan", 342),
    ("Juan Fernandez Islands", 125),
    ("Juan de Nova & Europa", 124),
    ("Juan de Nova, Europa", 124),
    ("Kaliningrad", 126),
    ("Kazakhstan", 130),
    ("Kenya", 430),
    ("Kerguelen Islands", 131),
    ("Kermadec Islands", 133),
    ("Kingdom of Eswatini", 468),
    ("Kure Island", 138),
    ("Kuwait", 348),
    ("Kyrgyzstan", 135),
    ("Lakshadweep Islands", 142),
    ("Laos", 143),
    ("Latvia", 145),
    ("Lebanon", 354),
    ("Lesotho", 432),
    ("Liberia", 434),
    ("Libya", 436),
    ("Liechtenstein", 251),
    ("Lithuania", 146),
    ("Lord Howe Island", 147),
    ("Luxembourg", 254),
    ("Macao", 152),
    ("Macquarie Island", 153),
    ("Madagascar", 438),
    ("Madeira Islands", 256),
    ("Malawi", 440),
    ("Maldives", 159),
    ("Mali", 442),
    ("Malpelo Island", 161),
    ("Malta", 257),
    ("Mariana Islands", 166),
    ("Market Reef", 167),
    ("Marquesas Islands", 509),
    ("Marshall Islands", 168),
    ("Martinique", 84),
    ("Mauritania", 444),
    ("Mauritius", 165),
    ("Mayotte", 169),
    ("Mellish Reef", 171),
    ("Mexico", 50),
    ("Micronesia", 173),
    ("Midway Island", 174),
    ("Minami Torishima", 177),
    ("Moldova", 179),
    ("Monaco", 260),
    ("Mongolia", 363),
    ("Montenegro", 514),
    ("Montserrat", 96),
    ("Morocco", 446),
    ("Mount Athos", 180),
    ("Mozambique", 181),
    ("Myanmar", 309),
    ("N.Z. Subantarctic Is.", 16),
    ("Namibia", 464),
    ("Nauru", 157),
    ("Navassa Island", 182),
    ("Nepal", 369),
    ("Netherlands", 263),
    ("New Caledonia", 162),
    ("New Zealand", 170),
    ("Nicaragua", 86),
    ("Niger", 187),
    ("Nigeria", 450),
    ("Niue", 188),
    ("Norfolk Island", 189),
    ("North Cook Islands", 191),
    ("North Macedonia", 502),
    ("Northern Ireland", 265),
    ("Norway", 266),
    ("Ogasawara", 192),
    ("Oman", 370),
    ("Pakistan", 372),
    ("Palau", 22),
    ("Palestine", 510),
    ("Palmyra & Jarvis Islands", 197),
    ("Panama", 88),
    ("Papua New Guinea", 163),
    ("Paraguay", 132),
    ("Peru", 136),
    ("Peter 1 Island", 199),
    ("Philippines", 375),
    ("Pitcairn Island", 172),
    ("Poland", 269),
    ("Portugal", 272),
    ("Pr. Edward & Marion Is.", 201),
    ("Pratas Island", 505),
    ("Puerto Rico", 202),
    ("Qatar", 376),
    ("Republic of Korea", 137),
    ("Republic of Kosovo", 522),
    ("Republic of South Sudan", 521),
    ("Republic of the Congo", 412),
    ("Reunion Island", 453),
    ("Revillagigedo", 204),
    ("Rodriguez Island", 207),
    ("Romania", 275),
    ("Rotuma Island", 460),
    ("Rwanda", 454),
    ("Saba & St. Eustatius", 519),
    ("Sable Island", 211),
    ("Samoa", 190),
    ("San Andres & Providencia", 216),
    ("San Felix & San Ambrosio", 217),
    ("San Marino", 278),
    ("Sao Tome & Principe", 219),
    ("Sardinia", 225),
    ("Saudi Arabia", 378),
    ("Scarborough Reef", 506),
    ("Scotland", 279),
    ("Senegal", 456),
    ("Serbia", 296),
    ("Seychelles", 379),
    ("Shetland Islands", 279),
    ("Sicily", 248),
    ("Sierra Leone", 458),
    ("Singapore", 381),
    ("Sint Maarten", 518),
    ("Slovak Republic", 504),
    ("Slovenia", 499),
    ("Solomon Islands", 185),
    ("Somalia", 232),
    ("South Africa", 462),
    ("South Cook Islands", 234),
    ("South Georgia Island", 235),
    ("South Orkney Islands", 238),
    ("South Sandwich Islands", 240),
    ("South Shetland Islands", 241),
    ("Sov Mil Order of Malta", 246),
    ("Spain", 281),
    ("Spratly Islands", 247),
    ("Sri Lanka", 315),
    ("St. Barthelemy", 516),
    ("St. Helena", 250),
    ("St. Kitts & Nevis", 249),
    ("St. Lucia", 97),
    ("St. Martin", 213),
    ("St. Paul Island", 252),
    ("St. Peter & St. Paul", 253),
    ("St. Pierre & Miquelon", 277),
    ("St. Vincent", 98),
    ("Sudan", 466),
    ("Suriname", 140),
    ("Svalbard", 259),
    ("Swains Island", 515),
    ("Sweden", 284),
    ("Switzerland", 287),
    ("Syria", 384),
    ("Taiwan", 386),
    ("Tajikistan", 262),
    ("Tanzania", 470),
    ("Temotu Province", 507),
    ("Thailand", 387),
    ("The Gambia", 422),
    ("Timor - Leste", 511),
    ("Togo", 483),
    ("Tokelau Islands", 270),
    ("Tonga", 160),
    ("Trindade & Martim Vaz", 273),
    ("Trinidad & Tobago", 90),
    ("Tristan da Cunha & Gough", 274),
    ("Tristan da Cunha & Gough Islands", 274),
    ("Tromelin Island", 276),
    ("Tunisia", 474),
    ("Turkmenistan", 280),
    ("Turks & Caicos Islands", 89),
    ("Tuvalu", 282),
    ("UK Base Areas on Cyprus", 283),
    ("US Virgin Islands", 285),
    ("Uganda", 286),
    ("Ukraine", 288),
    ("United Arab Emirates", 391),
    ("United Nations HQ", 289),
    ("United States", 291),
    ("Uruguay", 144),
    ("Uzbekistan", 292),
    ("Vanuatu", 158),
    ("Vatican City", 295),
    ("Venezuela", 148),
    ("Vienna Intl Ctr", 206),
    ("Vietnam", 293),
    ("Wake Island", 297),
    ("Wales", 294),
    ("Wallis & Futuna Islands", 298),
    ("West Malaysia", 299),
    ("Western Kiribati", 301),
    ("Western Sahara", 302),
    ("Willis Island", 303),
    ("Yemen", 492),
    ("Zambia", 482),
    ("Zimbabwe", 452),
];

const FETCH_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(20);
/// One GET over TLS (the rustls ring provider, the operating system's root certificates),
/// HTTP/1.0 so that the body is plain and ends at the connection's end.
fn fetch_url(url: &str) -> Result<String, String> {
    use std::io::{Read, Write};
    use std::net::ToSocketAddrs;
    use std::sync::Arc;
    let rest = url.strip_prefix("https://").ok_or("not https")?;
    let (host, path) = rest.split_once('/').ok_or("no path")?;
    let mut roots = rustls::RootCertStore::empty();
    let native = rustls_native_certs::load_native_certs();
    let _ = roots.add_parsable_certificates(native.certs);
    let config = rustls::ClientConfig::builder_with_provider(Arc::new(
        rustls::crypto::ring::default_provider(),
    ))
    .with_safe_default_protocol_versions()
    .map_err(|e| e.to_string())?
    .with_root_certificates(roots)
    .with_no_client_auth();
    let name =
        rustls::pki_types::ServerName::try_from(host.to_owned()).map_err(|e| e.to_string())?;
    let session =
        rustls::ClientConnection::new(Arc::new(config), name).map_err(|e| e.to_string())?;
    let address = (host, 443)
        .to_socket_addrs()
        .map_err(|e| e.to_string())?
        .next()
        .ok_or("no address")?;
    let socket =
        std::net::TcpStream::connect_timeout(&address, FETCH_TIMEOUT).map_err(|e| e.to_string())?;
    socket
        .set_read_timeout(Some(FETCH_TIMEOUT))
        .and_then(|()| socket.set_write_timeout(Some(FETCH_TIMEOUT)))
        .map_err(|e| e.to_string())?;
    let mut stream = rustls::StreamOwned::new(session, socket);
    let request = format!(
        "GET /{path} HTTP/1.0\r\nHost: {host}\r\nUser-Agent: {USER_AGENT}\r\nAccept: application/json\r\nConnection: close\r\n\r\n"
    );
    stream
        .write_all(request.as_bytes())
        .map_err(|e| e.to_string())?;
    let mut reply = Vec::new();
    // A server may end without close_notify: the body is validated by List::parse anyway.
    let read = (&mut stream)
        .take(FILE_BYTES_MAX + 4096)
        .read_to_end(&mut reply);
    if let Err(e) = read
        && e.kind() != std::io::ErrorKind::UnexpectedEof
    {
        return Err(e.to_string());
    }
    response_body(&reply)
}
/// The body of a 200 reply (an HTTP/1.x status line, headers, a blank line).
fn response_body(reply: &[u8]) -> Result<String, String> {
    let text = String::from_utf8_lossy(reply);
    let (head, body) = text.split_once("\r\n\r\n").ok_or("no response")?;
    let status = head
        .lines()
        .next()
        .and_then(|l| l.split(' ').nth(1))
        .ok_or("no status")?;
    if status != "200" {
        return Err(format!("status {status}"));
    }
    Ok(body.to_owned())
}

#[cfg(test)]
mod tests {
    // Proves: TC-039-011. Hand-written list text and replies; no network.
    use super::*;
    #[test]
    fn tc_039_011_parser_refuses_all_but_the_exact_list() {
        let ok = List::parse(r#"{"1":"344","2":123,"3":"9999"}"#, "2026-11-06", "upload").unwrap();
        assert_eq!(ok.entries(), 3);
        assert_eq!(ok.unmapped, 1, "9999 has no entity");
        assert_eq!(ok.rank("Fed. Rep. of Germany"), None, "230 is not listed");
        assert_eq!(ok.rank("DPR of Korea"), Some(1), "ADIF 344");
        for bad in [
            "",
            "[]",
            "{}",
            r#"{"x":"344"}"#,
            r#"{"0":"344"}"#,
            r#"{"1":"x"}"#,
            r#"{"1":"0"}"#,
            r#"{"1":"10000"}"#,
            r#"{"1":"344","2":"344"}"#,
            r#"{"1":null}"#,
        ] {
            assert_eq!(List::parse(bad, "d", "upload"), None, "{bad}");
        }
        let many: serde_json::Map<String, Value> = (1..=1001)
            .map(|i| (i.to_string(), json!(i.to_string())))
            .collect();
        assert_eq!(List::from_value(&Value::Object(many), "d", "upload"), None);
    }
    #[test]
    fn tc_039_011_every_bundled_entity_has_its_adif_number() {
        let table = crate::dxcc::Table::default();
        for name in table.cty.entity_names() {
            assert!(adif_number(name).is_some(), "{name}");
        }
        // The 340 current DXCC entities (the Club Log list of 2026-11-06 has 340 too).
        assert_eq!(known_numbers().len(), 340);
        // Known answers from the ADIF specification's DXCC table.
        for (name, number) in [
            ("Switzerland", 287),
            ("United States", 291),
            ("Fed. Rep. of Germany", 230),
            ("Japan", 339),
            ("DPR of Korea", 344),
            ("Sicily", 248),
            ("Italy", 248),
            ("Shetland Islands", 279),
            ("Scotland", 279),
            ("Cape Verde", 409),
            ("Cabo Verde", 409),
        ] {
            assert_eq!(adif_number(name), Some(number), "{name}");
        }
    }
    #[test]
    fn tc_039_011_response_body() {
        assert_eq!(
            response_body(b"HTTP/1.1 200 OK\r\nServer: x\r\n\r\n{\"1\":\"344\"}"),
            Ok("{\"1\":\"344\"}".to_owned())
        );
        assert_eq!(
            response_body(b"HTTP/1.1 503 Busy\r\n\r\nno"),
            Err("status 503".to_owned())
        );
        assert_eq!(response_body(b"junk"), Err("no response".to_owned()));
    }
}
