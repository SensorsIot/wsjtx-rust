// DCB bit layout (winbase.h): fDtrControl bits 4-5, fRtsControl
// bits 12-13, fOutxCtsFlow 2, fOutxDsrFlow 3; all zero means both lines disabled.
#[test]
fn opened_ports_hold_dtr_and_rts_disabled() {
    for baud in [9600, 19200, 38400, 115200] {
        let dcb = super::line_safe_dcb(baud);
        assert_eq!(dcb._bitfield & 0x3030, 0, "DTR/RTS control disabled");
        assert_eq!(
            dcb._bitfield & 0x000c,
            0,
            "no hardware handshake raising lines"
        );
        assert_eq!(dcb.BaudRate, baud);
    }
}
