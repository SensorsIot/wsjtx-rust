package WstxCat {
    private import ScalarValues::*;

    port def CatPort;
    item def CatItem { doc /* What the CAT adapter and the transceiver exchange. */ }
    interface def Cat {
        doc /* The CAT adapter and the transceiver's serial link. */
        end catAdapter : CatPort;
        end radio : ~CatPort;
        item exchange : CatItem;
    }
}
