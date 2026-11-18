package WstxRadioProperties {
    private import ScalarValues::*;

    doc /* The transceiver as the station sees it: the properties the station reads from a
         radio or sets on it. Each is a value of the radio itself. How a value is written
         on the link to the radio is the link's (WstxCat::Cat). */

    part def Radio {
        doc /* A transceiver. It is an outside thing: the station knows of it what the
             radio answers and nothing else. */
        attribute model : String[0..1] {
            doc /* The model the radio answered with; absent until it answered. */ }
    }

    enum def Sideband {
        doc /* The sideband of the voice mode the station sets. */
        enum lsb;
        enum usb;
    }
    attribute def ModeValue {
        doc /* The operating mode of the radio with its filter. */
        attribute sideband : Sideband[0..1] {
            doc /* Absent when the radio is in a mode that is neither LSB nor USB. */ }
        attribute modeCode : String[0..1] {
            doc /* The radio's own code of such a mode, two hexadecimal digits; absent
                 for LSB and USB. */ }
        attribute filterNumber : Integer { doc /* 1, 2 or 3. */ }
    }
    attribute def DataValue {
        doc /* The data mode of the radio: with it the transmit audio comes from the
             connector the radio's menu names for data. */
        attribute enabled : Boolean;
        attribute filterNumber : Integer {
            doc /* 1, 2 or 3 with the data mode on; 0 with it off. */ }
    }

    enum def Agc {
        doc /* The time constant of the receiver's automatic gain control. */
        enum fast;
        enum mid;
        enum slow;
    }
    enum def Setting {
        doc /* The menu items of an IC-7300 the station reads, and of which it sets some.
             usbModLevel: the level of the transmit audio from USB, 0 to 255.
             dataOffMod: the connector the transmit audio comes from with the data mode
             off (MIC, ACC, MIC/ACC, USB, MIC/USB).
             dataMod: the same with the data mode on.
             civTransceive: whether the radio reports changes on the link unasked.
             usbSend: the serial line that keys the transmitter (OFF, DTR, RTS).
             usbKeyingCw: the serial line that keys CW (OFF, DTR, RTS).
             usbKeyingRtty: the serial line that keys RTTY (OFF, DTR, RTS). */
        enum usbModLevel;
        enum dataOffMod;
        enum dataMod;
        enum civTransceive;
        enum usbSend;
        enum usbKeyingCw;
        enum usbKeyingRtty;
    }

    enum def Meter {
        doc /* alc: the automatic level control.
             po: the output power.
             swr: the standing wave ratio. */
        enum alc;
        enum po;
        enum swr;
    }
    attribute def MeterReadings {
        doc /* The three meters. A meter the radio refuses to give is absent. */
        attribute alc : Integer[0..1] {
            doc /* In percent of the radio's ALC zone, rounded to a whole percent: 0
                 where the ALC begins to act, 100 at the end of the zone the radio's
                 meter marks; above 100 where the meter reads past it. */ }
        attribute poPct : Integer[0..1] {
            doc /* The output power in percent of the radio's full power. */ }
        attribute swrTimesTen : Integer[0..1] {
            doc /* Ten times the standing wave ratio; 10 is a ratio of 1.0. */ }
    }
}
