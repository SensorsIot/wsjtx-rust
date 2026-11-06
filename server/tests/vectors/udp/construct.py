"""Hand construction of the WstxUdp NetworkMessage reference vectors (TC-012-001).

Every vector is written field by field from WSJT-X v3.3.0-beta5 Network/NetworkMessage.hpp
(SHA-256 b640a632f38b218f97b9c9cf5b5a09b183e1629c613c33d90f39635f9b3fdb3d) and, for the
QSO Logged trailing fields, Network/MessageClient.cpp::qso_logged (SHA-256
8cfa89debc2b916b39151975437619e7f9b28aefa698f05231fbdf2247cb9f35): Qt QDataStream
big-endian, utf8 = quint32 length + bytes (0xffffffff null), QTime = quint32 ms since
midnight, QDateTime = qint64 Julian day + quint32 ms + quint8 timespec (1 = UTC), float =
double of the single-precision value, QColor = qint8 spec + 5 x quint16 (alpha, r, g, b,
pad; component c is c * 257). Python's struct module packs the fields; nothing here uses
the Rust encoder. Exact byte equality is expected.

Rewrite the JSON files next to this script: python construct.py
"""
import datetime
import os
import json
import struct

SOURCE = ("WSJT-X v3.3.0-beta5 Network/NetworkMessage.hpp sha256 "
          "b640a632f38b218f97b9c9cf5b5a09b183e1629c613c33d90f39635f9b3fdb3d; "
          "MessageClient.cpp sha256 8cfa89debc2b916b39151975437619e7f9b28aefa698f05231fbdf2247cb9f35; "
          "constructed field by field by construct.py (Python struct), exact")
ID = "WSTX-Rust"


def u8(v): return struct.pack(">B", v)
def boolean(v): return u8(1 if v else 0)
def u16(v): return struct.pack(">H", v)
def u32(v): return struct.pack(">I", v)
def i32(v): return struct.pack(">i", v)
def u64(v): return struct.pack(">Q", v)
def i64(v): return struct.pack(">q", v)
def double(v): return struct.pack(">d", v)
def single_as_double(v): return double(struct.unpack(">f", struct.pack(">f", v))[0])
def utf8(s): return u32(len(s.encode())) + s.encode()
def null(): return u32(0xFFFFFFFF)
def qtime(h, m, s, ms=0): return u32(((h * 60 + m) * 60 + s) * 1000 + ms)
def qdatetime(y, mo, d, h, mi, s):
    julian = datetime.date(y, mo, d).toordinal() + 1721425  # QDate::toJulianDay
    return i64(julian) + qtime(h, mi, s) + u8(1)
def qcolor(rgb):
    if rgb is None:
        return struct.pack(">b", 0) + u16(0xFFFF) + u16(0) * 4
    r, g, b = rgb
    return struct.pack(">b", 1) + u16(0xFFFF) + u16(r * 257) + u16(g * 257) + u16(b * 257) + u16(0)
def header(kind, schema=2, ident=ID): return u32(0xADBCCBDA) + u32(schema) + u32(kind) + utf8(ident)


def vector(name, direction, data, fields=None, expect=None):
    v = {"source": SOURCE, "exact": True, "direction": direction, "hex": data.hex()}
    if fields is not None:
        v["input"] = fields
    if direction == "inbound":
        v["expect"] = expect
    with open(f"{name}.json", "w", newline="\n") as f:
        json.dump(v, f, indent=1)
        f.write("\n")


# ---------------------------------------------------------------- outbound
vector("heartbeat", "outbound",
       header(0) + u32(3) + utf8("0.1.0") + utf8(""),
       {"kind": "heartbeat", "schema": 2, "version": "0.1.0", "revision": ""})
vector("status", "outbound",
       header(1) + u64(14_074_000) + utf8("FT8") + utf8("K1ABC") + utf8("-12") + utf8("FT8")
       + boolean(True) + boolean(False) + boolean(True) + u32(1235) + u32(1500)
       + utf8("HB9BLA") + utf8("JN47AA") + utf8("FN42") + boolean(False) + utf8("")
       + boolean(False) + u8(0) + u32(0xFFFFFFFF) + u32(15) + utf8("HB9BLA station")
       + utf8("K1ABC HB9BLA JN47"),
       {"kind": "status", "schema": 2, "dial_hz": 14_074_000, "mode": "FT8", "dx_call": "K1ABC",
        "report": "-12", "tx_mode": "FT8", "tx_enabled": True, "transmitting": False,
        "decoding": True, "rx_df": 1235, "tx_df": 1500, "de_call": "HB9BLA",
        "de_grid": "JN47AA", "dx_grid": "FN42", "tx_watchdog": False, "sub_mode": "",
        "fast_mode": False, "special_operation": 0, "frequency_tolerance": 4294967295,
        "tr_period": 15, "configuration_name": "HB9BLA station",
        "tx_message": "K1ABC HB9BLA JN47"})
vector("decode", "outbound",
       header(2) + boolean(True) + qtime(12, 34, 30) + i32(-12) + single_as_double(0.1)
       + u32(1235) + utf8("~") + utf8("CQ K1ABC FN42") + boolean(False) + boolean(False),
       {"kind": "decode", "schema": 2, "new": True, "time_ms": 45_270_000, "snr": -12,
        "delta_time": 0.1, "delta_frequency": 1235, "mode": "~", "message": "CQ K1ABC FN42"})
vector("decode-replay-schema3", "outbound",
       header(2, schema=3) + boolean(False) + qtime(23, 59, 52, 500) + i32(5)
       + single_as_double(-0.3) + u32(900) + utf8("+") + utf8("HB9BLA W9XYZ R-09")
       + boolean(False) + boolean(False),
       {"kind": "decode", "schema": 3, "new": False, "time_ms": 86_392_500, "snr": 5,
        "delta_time": -0.3, "delta_frequency": 900, "mode": "+",
        "message": "HB9BLA W9XYZ R-09"})
vector("clear", "outbound", header(3), {"kind": "clear", "schema": 2})
vector("close", "outbound", header(6), {"kind": "close", "schema": 2})
vector("qso-logged", "outbound",
       header(5) + qdatetime(2026, 11, 1, 12, 36, 15) + utf8("K1ABC") + utf8("FN42")
       + u64(14_075_500) + utf8("FT8") + utf8("-12") + utf8("-09") + utf8("") + utf8("")
       + utf8("") + qdatetime(2026, 11, 1, 12, 34, 30) + utf8("") + utf8("HB9BLA")
       + utf8("JN47AA") + utf8("") + utf8("") + utf8("") + utf8("") + utf8("") + utf8(""),
       {"kind": "qso_logged", "schema": 2, "time_off_ms": 1_793_536_575_000,
        "dx_call": "K1ABC", "dx_grid": "FN42", "tx_frequency_hz": 14_075_500, "mode": "FT8",
        "report_sent": "-12", "report_received": "-09", "tx_power": "", "comments": "",
        "name": "", "time_on_ms": 1_793_536_470_000, "operator_call": "", "my_call": "HB9BLA",
        "my_grid": "JN47AA"})
vector("logged-adif", "outbound",
       header(12) + utf8("\n<adif_ver:5>3.1.8\n<programid:9>WSTX-Rust\n<EOH>\n<call:5>K1ABC <EOR>"),
       {"kind": "logged_adif", "schema": 2,
        "adif": "\n<adif_ver:5>3.1.8\n<programid:9>WSTX-Rust\n<EOH>\n<call:5>K1ABC <EOR>"})

# ---------------------------------------------------------------- inbound
# Send-only (issue #40, operator 2026-11-06): a target's Heartbeat header is all the station
# reads. Every other message type, the former commands first, is refused by that read.
vector("in-heartbeat", "inbound", header(0, 3) + u32(3) + utf8("1.24") + utf8("r1"),
       expect={"schema": 3, "id": ID})
vector("in-heartbeat-old", "inbound", header(0, 2, "JTAlert"),
       expect={"schema": 2, "id": "JTAlert"})
vector("in-heartbeat-trailing", "inbound", header(0, 3) + b"\x01\x02\x03",
       expect={"schema": 3, "id": ID})
vector("refused-clear", "inbound", header(3) + u8(2))
vector("refused-reply", "inbound",
       header(4) + qtime(12, 34, 30) + i32(-12) + single_as_double(0.1) + u32(1235)
       + utf8("~") + utf8("CQ K1ABC FN42") + boolean(False) + u8(0))
vector("refused-close", "inbound", header(6))
vector("refused-replay", "inbound", header(7))
vector("refused-halt", "inbound", header(8) + boolean(False))
vector("refused-free-text", "inbound", header(9) + utf8("K1ABC HB9BLA 73") + boolean(True))
vector("refused-location", "inbound", header(11) + utf8("JN47"))
vector("refused-highlight", "inbound",
       header(13) + utf8("K1ABC") + qcolor((255, 0, 0)) + qcolor(None) + boolean(False))
vector("refused-switch-configuration", "inbound", header(14) + utf8("Default"))
vector("refused-configure", "inbound", header(15) + utf8("Default"))
vector("refused-unknown-type", "inbound", header(18) + utf8("x"))
vector("refused-magic", "inbound", u32(0xADBCCBDB) + u32(2) + u32(0) + utf8(ID))
vector("refused-schema1", "inbound", header(0, 1))
vector("refused-schema4", "inbound", header(0, 4))
vector("refused-utf8-truncated", "inbound", u32(0xADBCCBDA) + u32(2) + u32(0) + u32(20) + b"WSTX")
vector("refused-null-id", "inbound", u32(0xADBCCBDA) + u32(2) + u32(0) + null())
vector("refused-oversize", "inbound", header(0) + b"\x00" * (4097 - len(header(0))))
vector("refused-invalid-utf8", "inbound", u32(0xADBCCBDA) + u32(2) + u32(0) + u32(2) + b"\xff\xfe")
