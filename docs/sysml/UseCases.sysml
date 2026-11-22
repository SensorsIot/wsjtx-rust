package WstxUseCases {
    private import WstxShack::Shack;
    private import WstxContext::context;

    doc /* The end-to-end processes of the actors with the shack, each from its trigger to
         an outcome that can be checked. A step subsets the clauses that carry it. */

    use case def SetUpFirstStation {
        doc /* The operator sets up the first station of a new shack. */
        subject shack : Shack;
        actor operator :> context.operator;
        actor radio :> context.catRadio;
        actor sound :> context.soundDevice;
        actor logger :> context.udpPeer;
        actor countryFiles :> context.countryFiles;
        objective {
            doc /* Receive runs on a band of the operator's choice, with the logbook, the
                 logging program and the country file in place. */ }
        action startStation {
            doc /* The operator starts the station with a new profile; it opens its app
                 window. */
            requirement :> WstxStartup::'CL-005-09';
            requirement :> WstxProfileDocument::'CL-005-04';
            requirement :> WstxProfileDocument::'CL-005-05';
            requirement :> WstxProfileDocument::'CL-005-01';
            requirement :> WstxOperatingScreen::'CL-103-01';
            requirement :> WstxOperatingScreen::'CL-010-16';
        }
        then action setIdentity {
            doc /* The operator sets the call sign, the locator and the continent of the
                 shack in the settings. */
            requirement :> WstxSettings::'CL-227-01';
            requirement :> WstxSettings::'CL-073-01';
            requirement :> WstxProfileDocument::'CL-005-07';
            requirement :> WstxProfileDocument::'CL-005-02';
            requirement :> WstxStationAuthority::'CL-005-08';
        }
        then action setRadio {
            doc /* The operator detects the radio, takes the proposed control and applies
                 the recommended settings; the station connects the radio. */
            requirement :> WstxSettings::'CL-044-06';
            requirement :> WstxRadioSetup::'CL-044-01';
            requirement :> WstxRadioSetup::'CL-044-02';
            requirement :> WstxRadioSetup::'CL-044-03';
            requirement :> WstxRadioSetup::'CL-044-04';
            requirement :> WstxRadioSetup::'CL-044-19';
            requirement :> WstxCatLifecycle::'CL-022-03';
            requirement :> WstxCatControl::'CL-008-04';
            requirement :> WstxCatControl::'CL-008-06';
            requirement :> WstxRadioFacts::'CL-008-05';
        }
        then action setAudio {
            doc /* The operator chooses the input and the output by name. */
            requirement :> WstxSettings::'CL-044-08';
            requirement :> WstxEndpoints::'CL-044-07';
            requirement :> WstxProfileDocument::'CL-044-05';
            requirement :> WstxAudioDevice::'CL-008-08';
            requirement :> WstxCapture::'CL-008-02';
        }
        then action importLogbook {
            doc /* The operator updates the logbook from the ADIF file of the logging
                 program, so that what is worked and confirmed is known from the first
                 decode. */
            requirement :> WstxLogbook::'CL-010-18';
        }
        then action connectLogger {
            doc /* The operator adds the logging program as a UDP target; the station sends
                 it the decodes, the status and each logged contact, and takes its
                 heartbeat. */
            requirement :> WstxUdpSender::'CL-040-02';
            requirement :> WstxUdp::'CL-040-03';
            requirement :> WstxUdp::'CL-040-06';
        }
        then action updateCountryFile {
            doc /* The operator fetches the newest country file, which the log uses from
                 then on. */
            requirement :> WstxProfileDocument::'CL-055-06';
            requirement :> WstxCountryFile::'CL-055-03';
        }
        then action selectBand {
            doc /* The operator selects a band; receive starts and the waterfall shows the
                 band. */
            requirement :> WstxOperatingSelection::'CL-008-07';
            requirement :> WstxOperatingSelection::'CL-011-02';
            requirement :> WstxOperatingSelection::'CL-008-11';
            requirement :> WstxReceiveJob::'CL-006-02';
            requirement :> WstxReceiveJob::'CL-006-04';
            requirement :> WstxLiveReceive::'CL-007-01';
            requirement :> WstxSignalArea::'CL-006-08';
        }
        then action checkSettings {
            doc /* The operator runs the settings check (SettingsCheck). */
            requirement :> WstxSettingsCheck::'CL-001-01';
            requirement :> WstxSettings::'CL-001-02';
        }
        action exportLogbook {
            doc /* Variant: the operator gives the logbook out as an ADIF file. */
            requirement :> WstxLogbook::'CL-010-18';
        }
    }

    use case def AddStation {
        doc /* The operator adds a station for another radio, or another slice of a
             FlexRadio, to the shack. */
        subject shack : Shack;
        actor operator :> context.operator;
        actor radio :> context.catRadio;
        actor flex :> context.flexRadio;
        objective {
            doc /* A second station runs with its own profile, sharing the shack's settings,
                 strategies and logbook. */ }
        action startStation {
            doc /* The operator starts another station process with a profile of its own;
                 the station finds its radio. */
            requirement :> WstxStartup::'CL-005-09';
            requirement :> WstxProfileDocument::'CL-005-01';
            requirement :> WstxRadioSetup::'CL-044-15';
        }
        then action shareSettings {
            doc /* The station reads the shack's settings, strategies and logbook, and
                 changes a shared file only under its lock and revision. */
            requirement :> WstxProfileDocument::'CL-005-07';
            requirement :> WstxProfileDocument::'CL-039-01';
        }
        then action nameStation {
            doc /* The operator gives the station a name no other station of the shack has;
                 its UDP datagrams carry an instance name of its own. */
            requirement :> WstxSettings::'CL-227-01';
            requirement :> WstxUdpSender::'CL-112-01';
        }
        action flexSlice {
            doc /* Variant: for a FlexRadio the station holds a session on the radio's
                 network API, with a slice and a receive stream of its own. */
            requirement :> WstxProfileDocument::'CL-013-08';
            requirement :> WstxFlexSession::'CL-013-01';
            requirement :> WstxFlexSession::'CL-013-02';
            requirement :> WstxFlexSession::'CL-013-03';
            requirement :> WstxFlexSession::'CL-013-04';
            requirement :> WstxFlexSession::'CL-013-05';
            requirement :> WstxFlexSession::'CL-013-06';
            requirement :> WstxFlexSession::'CL-013-07';
        }
    }

    use case def SetOutputPower {
        doc /* The operator sets the output power of a band and the station drives the
             radio without splatter. */
        subject shack : Shack;
        actor operator :> context.operator;
        actor radio :> context.catRadio;
        objective {
            doc /* The radio transmits at the power set for the band, with the ALC at
                 rest. */ }
        action setPower {
            doc /* The operator sets the output power of the band; radio control sets it on
                 the radio and reads it back. */
            requirement :> WstxSettings::'CL-227-01';
            requirement :> WstxRadioSetup::'CL-044-18';
            requirement :> WstxCatControl::'CL-044-09';
            requirement :> WstxRadioSetup::'CL-044-10';
            requirement :> WstxRadioSetup::'CL-044-11';
        }
        then action tune {
            doc /* The operator presses Tune; the station finds the audio drive below the
                 ALC and stores it for the band. */
            requirement :> WstxQsoPane::'CL-037-06';
            requirement :> WstxTransmitState::'CL-111-06';
            requirement :> WstxTxLevel::'CL-044-12';
            requirement :> WstxPlayback::'CL-009-06';
        }
        then action supervise {
            doc /* In every transmission the station reads the meters, corrects the drive,
                 warns of trouble that lasts and halts on an SWR fault. */
            requirement :> WstxTxLevel::'CL-044-14';
            requirement :> WstxSignalArea::'CL-068-01';
            requirement :> WstxLowerPanel::'CL-037-02';
            requirement :> WstxStationAuthority::'CL-044-17';
        }
        action lacking {
            doc /* Variant: a rig that cannot set its power or read its ALC shows that
                 control greyed out, with the reason on hover. */
            requirement :> WstxOperatingScreen::'CL-017-01';
        }
    }

    use case def AnswerCq {
        doc /* The operator watches the band and answers a station calling CQ. */
        subject shack : Shack;
        actor operator :> context.operator;
        actor radio :> context.catRadio;
        actor sound :> context.soundDevice;
        actor logger :> context.udpPeer;
        actor reporter :> context.pskReporter;
        objective { doc /* The contact is complete, logged and given to the logging programs. */ }
        action watch {
            doc /* Receive decodes each period; the waterfall and Band Activity show the
                 stations by their value. */
            requirement :> WstxSpectrum::'CL-006-03';
            requirement :> WstxSignalArea::'CL-054-01';
            requirement :> WstxSignalArea::'CL-054-02';
            requirement :> WstxSignalArea::'CL-050-07';
            requirement :> WstxLiveReceive::'CL-007-05';
            requirement :> WstxReceiveJob::'CL-008-03';
            requirement :> WstxDecode::'CL-007-03';
            requirement :> WstxDecode::'CL-007-06';
            requirement :> WstxDecode::'CL-007-07';
            requirement :> WstxDecode::'CL-007-08';
            requirement :> WstxDecode::'CL-007-04';
            requirement :> WstxDecode::'CL-057-02';
            requirement :> WstxMessagePayload::'CL-007-09';
            requirement :> WstxMessagePayload::'CL-024-01';
            requirement :> WstxCountryFile::'CL-055-01';
            requirement :> WstxValueOrder::'CL-055-02';
            requirement :> WstxValueOrder::'CL-042-01';
            requirement :> WstxLogbook::'CL-010-13';
            requirement :> WstxBandActivityPane::'CL-010-09';
            requirement :> WstxBandActivityPane::'CL-057-01';
            requirement :> WstxBandActivityPane::'CL-057-03';
            requirement :> WstxBandActivityPane::'CL-055-04';
            requirement :> WstxBandActivityPane::'CL-050-02';
            requirement :> WstxBandActivityPane::'CL-050-08';
            requirement :> WstxBandActivityPane::'CL-055-05';
            requirement :> WstxOperatingScreen::'CL-010-14';
        }
        then action pick {
            doc /* The operator double-clicks a CQ; the station prepares the contact and
                 sets the offsets. */
            requirement :> WstxBandActivityPane::'CL-037-05';
            requirement :> WstxStandardQso::'CL-010-01';
            requirement :> WstxStandardQso::'CL-039-24';
            requirement :> WstxValueOrder::'CL-039-03';
            requirement :> WstxHoldTx::'CL-010-11';
            requirement :> WstxHoldTx::'CL-039-09';
            requirement :> WstxHoldTx::'CL-065-01';
            requirement :> WstxSignalArea::'CL-065-02';
            requirement :> WstxSignalArea::'CL-050-01';
            requirement :> WstxLowerPanel::'CL-037-01';
        }
        then action sequence {
            doc /* The station sends Tx1 to 73 in the right periods as the partner answers;
                 the QSO pane shows the dialogue and what goes next. */
            requirement :> WstxQsoTransmit::'CL-111-02';
            requirement :> WstxStandardQso::'CL-010-02';
            requirement :> WstxStandardQso::'CL-050-06';
            requirement :> WstxStandardQso::'CL-011-03';
            requirement :> WstxMessageChoice::'CL-010-12';
            requirement :> WstxMessageChoice::'CL-024-05';
            requirement :> WstxDecode::'CL-007-10';
            requirement :> WstxTransmitState::'CL-111-01';
            requirement :> WstxTransmitState::'CL-009-03';
            requirement :> WstxSchedule::'CL-009-02';
            requirement :> WstxMessageEncode::'CL-009-01';
            requirement :> WstxMessageEncode::'CL-011-01';
            requirement :> WstxCatControl::'CL-008-09';
            requirement :> WstxCatControl::'CL-008-13';
            requirement :> WstxTransmitState::'CL-009-07';
            requirement :> WstxLiveReceive::'CL-061-04';
            requirement :> WstxSignalArea::'CL-061-05';
            requirement :> WstxBandActivityPane::'CL-061-03';
            requirement :> WstxQsoPane::'CL-037-04';
            requirement :> WstxQsoPane::'CL-060-01';
            requirement :> WstxQsoPane::'CL-050-05';
            requirement :> WstxQsoPane::'CL-050-03';
            requirement :> WstxQsoPane::'CL-111-09';
            requirement :> WstxOperatingScreen::'CL-111-04';
        }
        then action log {
            doc /* The completed contact is logged, kept in the heard file and given to the
                 logging programs; the decodes go to PSK Reporter. */
            requirement :> WstxStandardQso::'CL-085-02';
            requirement :> WstxLogbook::'CL-010-04';
            requirement :> WstxLogbook::'CL-085-01';
            requirement :> WstxLogbook::'CL-010-20';
            requirement :> WstxUdp::'CL-040-01';
            requirement :> WstxUdp::'CL-112-05';
            requirement :> WstxUdp::'CL-040-04';
            requirement :> WstxUdp::'CL-112-03';
            requirement :> WstxUdp::'CL-040-07';
            requirement :> WstxUdp::'CL-112-02';
            requirement :> WstxSpotsReporting::'CL-039-28';
        }
        action confirmByHand {
            doc /* Variant: with Log automatically off, the contact waits until the operator
                 logs or discards it. */
            requirement :> WstxStandardQso::'CL-085-04';
        }
        action noAnswer {
            doc /* Variant: the partner does not answer; the station stops at the
                 repetition limit, and the operator may start the count anew. */
            requirement :> WstxQsoTransmit::'CL-039-06';
            requirement :> WstxQsoTransmit::'CL-111-08';
            requirement :> WstxStandardQso::'CL-097-06';
        }
        action stop {
            doc /* Variant: the operator presses HALT or Abort QSO; the transmitter is off at
                 once and the contact ends or stays. */
            requirement :> WstxOperatingScreen::'CL-037-03';
            requirement :> WstxTransmitState::'CL-009-04';
            requirement :> WstxTransmitState::'CL-111-03';
            requirement :> WstxQsoTransmit::'CL-010-03';
        }
        action deviceLost {
            doc /* Variant: the radio or the sound device is lost while the station
                 transmits; the contact stays, and the operator goes on with it or ends
                 it. */
            requirement :> WstxQsoTransmit::'CL-010-22';
        }
        action reopen {
            doc /* Variant: the partner asks again after the contact completed; the operator
                 chooses a message and the contact is taken up again. */
            requirement :> WstxStandardQso::'CL-109-01';
        }
        action resend {
            doc /* Variant: the operator presses Log QSO to give the newest record to the
                 logging programs again. */
            requirement :> WstxLogbook::'CL-010-19';
        }
    }

    use case def CallCq {
        doc /* The operator calls CQ and works the station that answers. */
        subject shack : Shack;
        actor operator :> context.operator;
        actor radio :> context.catRadio;
        actor logger :> context.udpPeer;
        objective { doc /* The contact with the caller is complete and logged. */ }
        action findSpace {
            doc /* The station places Tx in the best quiet space, away from the partner's
                 signal. */
            requirement :> WstxHoldTx::'CL-039-09';
            requirement :> WstxHoldTx::'CL-039-29';
            requirement :> WstxHoldTx::'CL-039-08';
        }
        then action callCq {
            doc /* The operator presses CQ; the station calls each period. */
            requirement :> WstxQsoPane::'CL-037-06';
            requirement :> WstxQsoTransmit::'CL-111-05';
        }
        then action answerCaller {
            doc /* The station answers the first caller and works the contact as in
                 AnswerCq; other callers wait. */
            requirement :> WstxStandardQso::'CL-010-17';
            requirement :> WstxStandardQso::'CL-050-04';
            requirement :> WstxStandardQso::'CL-010-02';
        }
        then action log {
            doc /* The contact is logged as in AnswerCq. */
            requirement :> WstxStandardQso::'CL-085-02';
            requirement :> WstxLogbook::'CL-010-04';
        }
    }

    use case def AnswerDirectCall {
        doc /* A station calls the operator unasked: while idle, after a contact, or during
             another one. */
        subject shack : Shack;
        actor operator :> context.operator;
        objective { doc /* The caller is answered and the contact logged. */ }
        action ring {
            doc /* The call is marked in Band Activity and rings in the browser. */
            requirement :> WstxBandActivityPane::'CL-050-08';
            requirement :> WstxSettings::'CL-042-08';
        }
        then action answer {
            doc /* The operator answers the caller; a contact in progress is replaced
                 without the transmitter going off. */
            requirement :> WstxBandActivityPane::'CL-037-05';
            requirement :> WstxStandardQso::'CL-010-01';
            requirement :> WstxStandardQso::'CL-050-04';
        }
        then action log {
            doc /* The contact is logged as in AnswerCq. */
            requirement :> WstxStandardQso::'CL-085-02';
        }
        action underAuto {
            doc /* Variant: with Auto on, the caller does not interrupt Auto's contact and
                 the operator's commands for the contact are refused until Auto is off. */
            requirement :> WstxLeave::'CL-119-04';
            requirement :> WstxStationAuthority::'CL-119-09';
        }
    }

    use case def MoveBandOrMode {
        doc /* The operator moves the station to another band or mode. */
        subject shack : Shack;
        actor operator :> context.operator;
        actor radio :> context.catRadio;
        objective { doc /* Receive runs on the new band and mode, and the radio is set for it. */ }
        action select {
            doc /* The operator picks a working frequency or a mode; the station sets the
                 radio, its AGC and its output power, and restarts receive. */
            requirement :> WstxOperatingSelection::'CL-008-07';
            requirement :> WstxOperatingSelection::'CL-044-16';
            requirement :> WstxOperatingSelection::'CL-011-02';
            requirement :> WstxOperatingSelection::'CL-008-11';
            requirement :> WstxRadioSetup::'CL-044-10';
            requirement :> WstxRadioSetup::'CL-044-18';
            requirement :> WstxReceiveJob::'CL-006-02';
            requirement :> WstxUdp::'CL-112-04';
        }
        then action endContact {
            doc /* A contact of another mode ends. */
            requirement :> WstxStandardQso::'CL-011-04';
        }
        action byDial {
            doc /* Variant: the operator tunes the radio; the station follows its dial. */
            requirement :> WstxOperatingSelection::'CL-008-12';
            requirement :> WstxRadioFacts::'CL-008-05';
        }
        action cancel {
            doc /* Variant: the operator cancels a selection that has not been carried out. */
            requirement :> WstxOperatingSelection::'CL-008-10';
        }
    }

    use case def HuntWithStrategy {
        doc /* The operator lets Auto work the stations a strategy wants. */
        subject shack : Shack;
        actor operator :> context.operator;
        actor reporter :> context.pskReporter;
        actor clubLog :> context.clubLog;
        objective {
            doc /* The stations the strategy ranks are worked and logged one after another
                 until Auto goes off. */ }
        action chooseStrategy {
            doc /* The operator chooses or edits a strategy; Band Activity shows only what it
                 ranks. */
            requirement :> WstxBandActivityPane::'CL-039-04';
            requirement :> WstxBandActivityPane::'CL-107-02';
            requirement :> WstxBandActivityPane::'CL-107-03';
            requirement :> WstxStrategySelection::'CL-063-03';
            requirement :> WstxStrategySelection::'CL-039-11';
            requirement :> WstxStrategySelection::'CL-097-10';
            requirement :> WstxSettings::'CL-097-12';
            requirement :> WstxProfileDocument::'CL-097-01';
            requirement :> WstxProfileDocument::'CL-039-01';
        }
        then action rank {
            doc /* Ranking orders the decodes by the strategy, the Most Wanted list, the
                 wanted list and the ignore list. */
            requirement :> WstxValueOrder::'CL-039-02';
            requirement :> WstxValueOrder::'CL-097-02';
            requirement :> WstxValueOrder::'CL-097-03';
            requirement :> WstxValueOrder::'CL-107-01';
            requirement :> WstxMostWanted::'CL-039-10';
            requirement :> WstxSettings::'CL-039-25';
            requirement :> WstxProfileDocument::'CL-039-30';
            requirement :> WstxIgnoreLists::'CL-042-02';
            requirement :> WstxBandActivityPane::'CL-042-06';
            requirement :> WstxWantedList::'CL-124-02';
            requirement :> WstxWantedList::'CL-124-03';
        }
        then action switchOn {
            doc /* The operator switches Auto on. */
            requirement :> WstxQsoPane::'CL-039-31';
            requirement :> WstxAutoMode::'CL-039-22';
        }
        then action work {
            doc /* Auto calls the most valuable station, moves its Tx by what PSK Reporter
                 says, and leaves a station by the strategy's rules; the strategy's alert
                 sounds for a new station. */
            requirement :> WstxTargetChoice::'CL-039-05';
            requirement :> WstxTargetChoice::'CL-119-08';
            requirement :> WstxTargetChoice::'CL-119-06';
            requirement :> WstxTxSlot::'CL-097-05';
            requirement :> WstxHearingFeed::'CL-039-20';
            requirement :> WstxHearingFeed::'CL-039-26';
            requirement :> WstxPskReporter::'CL-039-27';
            requirement :> WstxLeave::'CL-097-04';
            requirement :> WstxLeave::'CL-119-04';
            requirement :> WstxQsoTransmit::'CL-039-21';
            requirement :> WstxAlert::'CL-042-04';
            requirement :> WstxSettings::'CL-042-07';
            requirement :> WstxStationAuthority::'CL-119-09';
        }
        then action log {
            doc /* Each completed contact is logged at once. */
            requirement :> WstxStandardQso::'CL-085-02';
            requirement :> WstxLogbook::'CL-010-04';
        }
        then action switchOff {
            doc /* Auto goes off by the operator, the strategy, a halt or a lost radio; a
                 started QSO of its own finishes. */
            requirement :> WstxAutoMode::'CL-119-05';
            requirement :> WstxAutoMode::'CL-081-01';
        }
        action cqWhenIdle {
            doc /* Variant: with nothing to call, Auto calls CQ and answers its callers,
                 and pauses its CQ after an unanswered one. */
            requirement :> WstxCqWhenIdle::'CL-097-08';
            requirement :> WstxCqWhenIdle::'CL-097-11';
        }
    }

    use case def OperateContest {
        doc /* The operator takes part in a contest. */
        subject shack : Shack;
        actor operator :> context.operator;
        objective {
            doc /* The contest's QSOs are logged with their exchanges and given out as a
                 Cabrillo file. */ }
        action chooseContest {
            doc /* The operator chooses a contest and its period; Band Activity shows the
                 stations the contest can work. */
            requirement :> WstxStrategySelection::'CL-063-01';
            requirement :> WstxStrategySelection::'CL-063-03';
            requirement :> WstxBandActivityPane::'CL-063-08';
            requirement :> WstxAutoMode::'CL-039-22';
        }
        then action work {
            doc /* The station ranks by the contest, sends the exchange and the serial, and
                 counts the score. */
            requirement :> WstxContestRanking::'CL-063-02';
            requirement :> WstxContestRanking::'CL-063-04';
            requirement :> WstxContestRanking::'CL-063-09';
            requirement :> WstxSpecialActivities::'CL-085-03';
            requirement :> WstxSpecialActivities::'CL-024-03';
        }
        then action export {
            doc /* After the period the operator exports the Cabrillo file. */
            requirement :> WstxLogbook::'CL-010-21';
        }
    }

    use case def OperateSpecialActivity {
        doc /* The operator works stations under a special activity. */
        subject shack : Shack;
        actor operator :> context.operator;
        objective {
            doc /* The contacts carry the activity's messages and are logged with its
                 fields. */ }
        action chooseActivity {
            doc /* The operator chooses the activity in the QSO pane. */
            requirement :> WstxQsoPane::'CL-111-09';
        }
        then action work {
            doc /* The station runs the contact with the activity's exchange. */
            requirement :> WstxSpecialActivities::'CL-024-02';
            requirement :> WstxSpecialActivities::'CL-024-03';
            requirement :> WstxSpecialActivities::'CL-099-02';
            requirement :> WstxSpecialActivities::'CL-024-04';
            requirement :> WstxSpecialActivities::'CL-111-10';
        }
    }

    use case def AgentOperates {
        doc /* An agent operates the shack's stations through their MCP servers. */
        subject shack : Shack;
        actor agent :> context.agent;
        objective {
            doc /* The agent reads and commands each station as the operator's screen does. */ }
        action reachServer {
            doc /* The agent connects to a station's MCP server. */
            requirement :> WstxMcpEndpoint::'CL-012-01';
        }
        then action operate {
            doc /* The agent reads the views and gives commands; the supervisor passes them
                 like the operator's. */
            requirement :> WstxMcpEndpoint::'CL-012-02';
            requirement :> WstxStationAuthority::'CL-006-07';
        }
        action swrFault {
            doc /* Variant: after an SWR fault the agent cannot transmit until the operator
                 has acted. */
            requirement :> WstxStationAuthority::'CL-044-17';
        }
    }

    use case def RestartStation {
        doc /* The station is stopped and started again. */
        subject shack : Shack;
        actor operator :> context.operator;
        actor logger :> context.udpPeer;
        objective {
            doc /* The station runs again on its band and mode, with nothing keyed. */ }
        action stop {
            doc /* The station process ends; the radio is released and the UDP targets are
                 told. */
            requirement :> WstxStartup::'CL-005-09';
            requirement :> WstxTransmitState::'CL-009-04';
            requirement :> WstxUdp::'CL-112-06';
            requirement :> WstxProfileDocument::'CL-005-06';
        }
        then action startAgain {
            doc /* The station starts with transmit off and resumes the remembered receive;
                 the browser follows the new start. */
            requirement :> WstxTransmitState::'CL-111-01';
            requirement :> WstxStartup::'CL-045-01';
            requirement :> WstxStartup::'CL-045-02';
            requirement :> WstxStartup::'CL-045-03';
            requirement :> WstxOperatingScreen::'CL-074-01';
        }
    }

    use case def LoseRadio {
        doc /* The station loses its radio or its audio and gets it back. */
        subject shack : Shack;
        actor radio :> context.catRadio;
        actor sound :> context.soundDevice;
        objective { doc /* Operating goes on once the radio and the audio are back. */ }
        action lose {
            doc /* The CAT link or the sound device is lost; the radio is released and the
                 loss is shown. */
            requirement :> WstxTransmitState::'CL-009-04';
            requirement :> WstxRadioFacts::'CL-008-05';
            requirement :> WstxOperatingScreen::'CL-010-07';
            requirement :> WstxLowerPanel::'CL-037-02';
            requirement :> WstxBandActivityPane::'CL-061-01';
        }
        then action regain {
            doc /* The station connects again by itself; receive goes on under a new job. */
            requirement :> WstxCatLifecycle::'CL-022-04';
            requirement :> WstxAudioDevice::'CL-008-08';
            requirement :> WstxReceiveJob::'CL-008-03';
        }
    }

    use case def ClockOutOfStep {
        doc /* The PC clock is off from the time of the band. */
        subject shack : Shack;
        actor time :> context.timeServer;
        objective { doc /* Transmit waits until the station's time is right again. */ }
        action measure {
            doc /* The clock measures the PC clock and the stations heard, and corrects
                 station time. */
            requirement :> WstxStationClock::'CL-043-01';
            requirement :> WstxStationClock::'CL-043-02';
            requirement :> WstxStationClock::'CL-043-03';
            requirement :> WstxCapture::'CL-007-11';
        }
        then action warn {
            doc /* The clock warns, and a start that cannot transmit is refused with the
                 reason. */
            requirement :> WstxStationClock::'CL-009-05';
            requirement :> WstxQsoTransmit::'CL-111-07';
            requirement :> WstxLowerPanel::'CL-037-02';
        }
    }

    use case def OperateFromAnotherScreen {
        doc /* The operator opens the station on another screen of the local network. */
        subject shack : Shack;
        actor operator :> context.operator;
        objective {
            doc /* The other screen shows and commands the station as the first one
                 does. */ }
        action open {
            doc /* The browser reaches the station over TLS and loads the app. */
            requirement :> WstxListener::'CL-003-07';
            requirement :> WstxListener::'CL-003-01';
            requirement :> WstxListener::'CL-051-01';
            requirement :> WstxListener::'CL-033-01';
            requirement :> WstxContentCoding::'CL-003-09';
            requirement :> WstxOperatingScreen::'CL-010-08';
        }
        then action operate {
            doc /* The screen keeps its link and its views; a command sent twice has one
                 effect. */
            requirement :> WstxListener::'CL-003-02';
            requirement :> WstxListener::'CL-003-03';
            requirement :> WstxListener::'CL-003-08';
            requirement :> WstxListener::'CL-003-06';
            requirement :> WstxListener::'CL-003-05';
            requirement :> WstxOperatingScreen::'CL-003-04';
            requirement :> WstxOperatingScreen::'CL-051-02';
            requirement :> WstxOperatingScreen::'CL-051-03';
            requirement :> WstxStationAuthority::'CL-006-07';
            requirement :> WstxStationLink::'CL-003-10';
        }
    }

    use case def SettingsCheck {
        doc /* The operator checks all the station's settings at once. */
        subject shack : Shack;
        actor operator :> context.operator;
        actor radio :> context.catRadio;
        actor sound :> context.soundDevice;
        actor time :> context.timeServer;
        actor logger :> context.udpPeer;
        actor reporter :> context.pskReporter;
        objective {
            doc /* The station is ready to operate, or every failure is shown with its reason
                 and where to change it. */ }
        action begin {
            doc /* The operator starts the check, and allows or refuses the Tune tone. */
            requirement :> WstxSettings::'CL-001-02';
            requirement :> WstxSettingsCheck::'CL-001-01';
        }
        then action check {
            doc /* The station checks the shack's identity, the radio, the output power and
                 the audio drive, the audio, the clock, the operating values, the files and
                 the destinations. */
            requirement :> WstxProfileDocument::'CL-005-07';
            requirement :> WstxRadioFacts::'CL-008-05';
            requirement :> WstxRadioSetup::'CL-044-18';
            requirement :> WstxTxLevel::'CL-044-12';
            requirement :> WstxAudioDevice::'CL-008-08';
            requirement :> WstxStationClock::'CL-009-05';
            requirement :> WstxLogbook::'CL-010-04';
            requirement :> WstxCountryFile::'CL-055-03';
            requirement :> WstxUdpSender::'CL-040-02';
            requirement :> WstxHearingFeed::'CL-039-26';
        }
    }
}
