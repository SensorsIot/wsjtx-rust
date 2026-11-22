package WstxExternalPort {
    private import WstxModelNotes::CodeDiffers;
    enum def Availability {
        doc /* Whether the interface behind a boundary port can be used now. */
        enum notUsable { @CodeDiffers { what = "No code states availability yet."; } }
        enum usable { @CodeDiffers { what = "No code states availability yet."; } }
    }
    abstract item def InterfaceStatus {
        doc /* The status of an interface that crosses a process, device or network
             boundary. Each interface specializes it with its own reason. */
        attribute availability : Availability;
    }
    abstract port def ExternalPort {
        doc /* A port whose interface crosses a process, device or network boundary, written
             from the side of the part that hosts the interface. A port definition
             specializes it only where something reacts to the status of its interface.
             Availability has two literals; the reason is an attribute of the specialized
             status, and a transition guard reads the availability only, never the reason.
             The hosting part exhibits the availability state, which enters notUsable, and
             an absent status counts as notUsable. status is out on the hosting side only,
             and no other part redefines or derives it. */
        out item status : InterfaceStatus;
    }
}
