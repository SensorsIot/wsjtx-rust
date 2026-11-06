use super::*;

// Proves: TC-023-002. Slice status frequencies are exact integers in hertz.
#[test]
fn megahertz_text_round_trips_exact_hertz() {
    assert_eq!(megahertz("14.074000"), Some(14_074_000));
    assert_eq!(megahertz("7.0475"), Some(7_047_500));
    assert_eq!(megahertz("50.313"), Some(50_313_000));
    assert_eq!(megahertz_text(14_074_000), "14.074000");
    for bad in ["", ".5", "14,074", "-1.0", "1.0000000000"] {
        assert_eq!(megahertz(bad), None, "{bad}");
    }
}

// Proves: TC-023-002. A slice's ownership and liveness follow the latest status;
// removal and another client's handle are visible to the reconciler.
#[test]
fn view_tracks_ownership_and_removal_from_status_lines() {
    let mut view = View::default();
    let status = |text: &str| wire::parse_status(text).unwrap();
    view.apply(&status("slice 2 in_use=1 client_handle=0x10 RF_frequency=14.074000 rxant=ANT1 dax=1 index_letter=A"));
    view.apply(&status("slice 5 in_use=1 client_handle=0x20 dax=2"));
    assert_eq!(view.slices[&2].client_handle, Some(0x10));
    assert_eq!(view.slices[&5].dax, Some(2));
    view.apply(&status("slice 2 in_use=0"));
    assert!(!view.slices.contains_key(&2));
    view.apply(&status(
        "stream 0x04000008 type=dax_rx dax_channel=2 client_handle=0x20",
    ));
    assert_eq!(view.streams[&0x0400_0008].client_handle, Some(0x20));
    view.apply(&status("stream 0x04000008 removed"));
    assert!(view.streams.is_empty());
    view.apply(&status("client 0x20 connected client_id=AB program=X"));
    assert_eq!(view.clients[&0x20].client_id.as_deref(), Some("AB"));
    view.apply(&status("client 0x20 disconnected forced=0"));
    assert!(view.clients.is_empty());
    for i in 0..200 {
        view.apply(&status(&format!("stream 0x{i:x} type=dax_rx")));
    }
    assert!(view.streams.len() <= MAX_TRACKED);
}

#[test]
fn intent_domains() {
    let valid = Intent {
        client_id: "72e8c7f3-5766-4ade-9286-ebf2f525c77a".into(),
        rx_antenna: "ANT1".into(),
    };
    assert!(valid.valid());
    for bad in [
        Intent {
            rx_antenna: String::new(),
            ..valid.clone()
        },
        Intent {
            rx_antenna: "ant1".into(),
            ..valid.clone()
        },
        Intent {
            client_id: "x".into(),
            ..valid.clone()
        },
    ] {
        assert!(!bad.valid());
    }
}
