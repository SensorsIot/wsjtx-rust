package WstxFlexApi {
    private import ScalarValues::*;

    port def FlexApiPort;
    item def FlexApiItem { doc /* What the Flex adapter and the FlexRadio exchange. */ }
    interface def FlexApi {
        doc /* The Flex adapter and a FlexRadio's native API. */
        end flexAdapter : FlexApiPort;
        end radio : ~FlexApiPort;
        item exchange : FlexApiItem;
    }
}
