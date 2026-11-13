package WstxRadioProperties {
    private import ScalarValues::*;
    private import WstxArchitecture::Radio;
    private import WstxRadioControl::RadioStateOutcome;
    private import WstxRadioControl::RadioSettingsOutcome;

    doc /* Physical radio values are structured data attributes (OMG SysML 2.0 section7.7),
         not new components. Each property/context has ONE current observable value below.
         Separate capabilities describe domains/access; they are not another current value.
         Optional value absence means unknown, never zero/false/unsupported. Contextual
         records distinguish VFO/receiver/slice, mode/filter, antenna, scope and region.
         Capability support/access evidence may change with model/firmware/options/context;
         it does not grant execution authority. Observations are adapter-owned and callers
         cannot assign them. Temporary action inputs are intent, never confirmed state.
         Stale/failed reads retain explicit freshness metadata and cannot imply a new read.
         These data types do not prescribe Rust storage, cache, protocol or update layout. */
    enum def RadioPttState { enum off; enum on; enum microphoneOnly; enum dataOnly; }
    enum def RadioPowerState { enum off; enum on; enum standby; }
    enum def RepeaterShift { enum simplex; enum negative; enum positive; }
    enum def BreakInMode { enum off; enum semi; enum full; }
    enum def RadioResultStatus { enum confirmed; enum unavailable; enum unsupported; enum rejected; enum failed; }
    enum def RadioObservationQuality { enum unknown; enum current; enum stale; enum unavailable; }
    enum def RadioDirection { enum receive; enum transmit; }
    attribute def HertzValue :> ISQSpaceTime::FrequencyValue { :>> mRef = SI::Hz; }
    attribute def WattValue :> ISQMechanics::PowerValue { :>> mRef = SI::W; }
    attribute def SecondsValue :> ISQBase::DurationValue { :>> mRef = SI::s; }
    attribute radioMillisecond : ISQBase::DurationUnit { :>> unitConversion : MeasurementReferences::ConversionByPrefix { :>> prefix = SI::milli; :>> referenceUnit = SI::s; } }
    attribute def MillisecondsValue :> ISQBase::DurationValue { :>> mRef = radioMillisecond; }
    attribute def MinutesValue :> ISQBase::DurationValue { :>> mRef = SI::min; }
    attribute def AmpereValue :> ISQBase::ElectricCurrentValue { :>> mRef = SI::A; }
    attribute def VoltValue :> ISQElectromagnetism::ElectricPotentialValue { :>> mRef = SI::V; }
    attribute def FrequencyRange { attribute lowerHz : HertzValue; attribute upperHz : HertzValue; }
    attribute def VfoSelection { attribute role : String[0..1]; attribute selector : String[0..1]; }
    attribute def SplitSelection {
        attribute enabled : Boolean[0..1];
        attribute receiveVfo : VfoSelection[0..1];
        attribute transmitVfo : VfoSelection[0..1];
    }
    attribute def AntennaSelection { attribute receiveAntenna : String[0..1]; attribute transmitAntenna : String[0..1]; }
    attribute def RadioPropertyContext {
        attribute modelId : String[0..1]; attribute firmware : String[0..1];
        attribute options : String[*]; attribute vfo : VfoSelection[0..1];
        attribute receiver : String[0..1]; attribute slice : String[0..1];
        attribute rfMode : String[0..1]; attribute filterSelection : String[0..1];
        attribute antenna : String[0..1]; attribute region : String[0..1];
        attribute direction : RadioDirection[0..1]; attribute scope : String[0..1];
        attribute memoryChannel : Integer[0..1]; attribute memoryType : String[0..1];
        attribute band : String[0..1]; attribute preset : String[0..1];
        doc /* Matching a metadata context to an operating context is required before
             domain/access use. Missing evidence is unknown, not universal applicability.
             Domain alternatives are conditional records, never a Cartesian product. */
    }
    attribute def RadioObservationEvidence {
        attribute quality : RadioObservationQuality;
        attribute context : RadioPropertyContext;
        attribute propertyName : String;
        attribute observedAtSeconds : SecondsValue[0..1];
        attribute connectionGeneration : Integer[0..1];
        doc /* Metadata identifies the named value in its owning contextual group;
             no measured scalar is copied here. Unknown/failed/stale reads do not
             make retained values current. This is not an update or transport schema. */
    }
    attribute def ReadAccessDescription {
        attribute context : RadioPropertyContext;
        attribute supported : Boolean[0..1]; attribute readable : Boolean[0..1];
        doc /* For each field, absence means unknown. supported=false means known
             unsupported; readable=false denies read access, not feature support. */
    }
    attribute def ControlAccessDescription :> ReadAccessDescription {
        attribute writable : Boolean[0..1];
        doc /* writable=false denies writing; unknown writable does not permit a write.
             Availability never substitutes for RadioAuthority or transmit guards. */
    }
    attribute def RealDomain {
        attribute context : RadioPropertyContext;
        attribute choices : Real[*];
        attribute minimum : Real[0..1]; attribute maximum : Real[0..1]; attribute step : Real[0..1];
    }
    attribute def RealCapability :> ControlAccessDescription { attribute domains : RealDomain[*]; }
    attribute def ReadOnlyRealCapability :> ReadAccessDescription { attribute domains : RealDomain[*]; }
    attribute def IntegerDomain {
        attribute context : RadioPropertyContext;
        attribute choices : Integer[*];
        attribute minimum : Integer[0..1]; attribute maximum : Integer[0..1]; attribute step : Integer[0..1];
    }
    attribute def IntegerCapability :> ControlAccessDescription { attribute domains : IntegerDomain[*]; }
    attribute def ReadOnlyIntegerCapability :> ReadAccessDescription { attribute domains : IntegerDomain[*]; }
    attribute def StringDomain {
        attribute context : RadioPropertyContext;
        attribute choices : String[*];
    }
    attribute def StringCapability :> ControlAccessDescription { attribute domains : StringDomain[*]; }
    attribute def ReadOnlyStringCapability :> ReadAccessDescription { attribute domains : StringDomain[*]; }
    attribute def BooleanDomain {
        attribute context : RadioPropertyContext;
        attribute choices : Boolean[*];
    }
    attribute def BooleanCapability :> ControlAccessDescription { attribute domains : BooleanDomain[*]; }
    attribute def ReadOnlyBooleanCapability :> ReadAccessDescription { attribute domains : BooleanDomain[*]; }
    attribute def HertzValueDomain {
        attribute context : RadioPropertyContext;
        attribute choices : HertzValue[*];
        attribute minimum : HertzValue[0..1]; attribute maximum : HertzValue[0..1]; attribute step : HertzValue[0..1];
        attribute associatedMinimumPower : WattValue[0..1]; attribute associatedMaximumPower : WattValue[0..1];
        attribute continuous : Boolean[0..1]; attribute filterOrder : String[0..1];
    }
    attribute def HertzValueCapability :> ControlAccessDescription { attribute domains : HertzValueDomain[*]; }
    attribute def ReadOnlyHertzValueCapability :> ReadAccessDescription { attribute domains : HertzValueDomain[*]; }
    attribute def WattValueDomain {
        attribute context : RadioPropertyContext;
        attribute choices : WattValue[*];
        attribute minimum : WattValue[0..1]; attribute maximum : WattValue[0..1]; attribute step : WattValue[0..1];
    }
    attribute def WattValueCapability :> ControlAccessDescription { attribute domains : WattValueDomain[*]; }
    attribute def ReadOnlyWattValueCapability :> ReadAccessDescription { attribute domains : WattValueDomain[*]; }
    attribute def SecondsValueDomain {
        attribute context : RadioPropertyContext;
        attribute choices : SecondsValue[*];
        attribute minimum : SecondsValue[0..1]; attribute maximum : SecondsValue[0..1]; attribute step : SecondsValue[0..1];
    }
    attribute def SecondsValueCapability :> ControlAccessDescription { attribute domains : SecondsValueDomain[*]; }
    attribute def ReadOnlySecondsValueCapability :> ReadAccessDescription { attribute domains : SecondsValueDomain[*]; }
    attribute def MillisecondsValueDomain {
        attribute context : RadioPropertyContext;
        attribute choices : MillisecondsValue[*];
        attribute minimum : MillisecondsValue[0..1]; attribute maximum : MillisecondsValue[0..1]; attribute step : MillisecondsValue[0..1];
    }
    attribute def MillisecondsValueCapability :> ControlAccessDescription { attribute domains : MillisecondsValueDomain[*]; }
    attribute def ReadOnlyMillisecondsValueCapability :> ReadAccessDescription { attribute domains : MillisecondsValueDomain[*]; }
    attribute def MinutesValueDomain {
        attribute context : RadioPropertyContext;
        attribute choices : MinutesValue[*];
        attribute minimum : MinutesValue[0..1]; attribute maximum : MinutesValue[0..1]; attribute step : MinutesValue[0..1];
    }
    attribute def MinutesValueCapability :> ControlAccessDescription { attribute domains : MinutesValueDomain[*]; }
    attribute def ReadOnlyMinutesValueCapability :> ReadAccessDescription { attribute domains : MinutesValueDomain[*]; }
    attribute def AmpereValueDomain {
        attribute context : RadioPropertyContext;
        attribute choices : AmpereValue[*];
        attribute minimum : AmpereValue[0..1]; attribute maximum : AmpereValue[0..1]; attribute step : AmpereValue[0..1];
    }
    attribute def AmpereValueCapability :> ControlAccessDescription { attribute domains : AmpereValueDomain[*]; }
    attribute def ReadOnlyAmpereValueCapability :> ReadAccessDescription { attribute domains : AmpereValueDomain[*]; }
    attribute def VoltValueDomain {
        attribute context : RadioPropertyContext;
        attribute choices : VoltValue[*];
        attribute minimum : VoltValue[0..1]; attribute maximum : VoltValue[0..1]; attribute step : VoltValue[0..1];
    }
    attribute def VoltValueCapability :> ControlAccessDescription { attribute domains : VoltValueDomain[*]; }
    attribute def ReadOnlyVoltValueCapability :> ReadAccessDescription { attribute domains : VoltValueDomain[*]; }
    attribute def RadioPttStateDomain {
        attribute context : RadioPropertyContext;
        attribute choices : RadioPttState[*];
    }
    attribute def RadioPttStateCapability :> ControlAccessDescription { attribute domains : RadioPttStateDomain[*]; }
    attribute def ReadOnlyRadioPttStateCapability :> ReadAccessDescription { attribute domains : RadioPttStateDomain[*]; }
    attribute def RadioPowerStateDomain {
        attribute context : RadioPropertyContext;
        attribute choices : RadioPowerState[*];
    }
    attribute def RadioPowerStateCapability :> ControlAccessDescription { attribute domains : RadioPowerStateDomain[*]; }
    attribute def ReadOnlyRadioPowerStateCapability :> ReadAccessDescription { attribute domains : RadioPowerStateDomain[*]; }
    attribute def RepeaterShiftDomain {
        attribute context : RadioPropertyContext;
        attribute choices : RepeaterShift[*];
    }
    attribute def RepeaterShiftCapability :> ControlAccessDescription { attribute domains : RepeaterShiftDomain[*]; }
    attribute def ReadOnlyRepeaterShiftCapability :> ReadAccessDescription { attribute domains : RepeaterShiftDomain[*]; }
    attribute def BreakInModeDomain {
        attribute context : RadioPropertyContext;
        attribute choices : BreakInMode[*];
    }
    attribute def BreakInModeCapability :> ControlAccessDescription { attribute domains : BreakInModeDomain[*]; }
    attribute def ReadOnlyBreakInModeCapability :> ReadAccessDescription { attribute domains : BreakInModeDomain[*]; }
    attribute def VfoSelectionDomain {
        attribute context : RadioPropertyContext;
        attribute choices : VfoSelection[*];
    }
    attribute def VfoSelectionCapability :> ControlAccessDescription { attribute domains : VfoSelectionDomain[*]; }
    attribute def ReadOnlyVfoSelectionCapability :> ReadAccessDescription { attribute domains : VfoSelectionDomain[*]; }
    attribute def SplitSelectionDomain {
        attribute context : RadioPropertyContext;
        attribute choices : SplitSelection[*];
    }
    attribute def SplitSelectionCapability :> ControlAccessDescription { attribute domains : SplitSelectionDomain[*]; }
    attribute def ReadOnlySplitSelectionCapability :> ReadAccessDescription { attribute domains : SplitSelectionDomain[*]; }
    attribute def AntennaSelectionDomain {
        attribute context : RadioPropertyContext;
        attribute choices : AntennaSelection[*];
    }
    attribute def AntennaSelectionCapability :> ControlAccessDescription { attribute domains : AntennaSelectionDomain[*]; }
    attribute def ReadOnlyAntennaSelectionCapability :> ReadAccessDescription { attribute domains : AntennaSelectionDomain[*]; }
    attribute def FrequencyRangeDomain {
        attribute context : RadioPropertyContext;
        attribute choices : FrequencyRange[*];
    }
    attribute def FrequencyRangeCapability :> ControlAccessDescription { attribute domains : FrequencyRangeDomain[*]; }
    attribute def ReadOnlyFrequencyRangeCapability :> ReadAccessDescription { attribute domains : FrequencyRangeDomain[*]; }
    attribute def RadioVfoValues {
        attribute context : RadioPropertyContext;
        attribute evidence : RadioObservationEvidence[*];
        attribute vfo : VfoSelection[0..1];
        attribute frequency : HertzValue[0..1];
        attribute rfMode : String[0..1];
        attribute receiverFilterHz : HertzValue[0..1];
        attribute filterSelection : String[0..1];
        attribute tuningStepHz : HertzValue[0..1];
        attribute split : SplitSelection[0..1];
        attribute transmitFrequencyHz : HertzValue[0..1];
        attribute transmitRfMode : String[0..1];
        attribute transmitFilterHz : HertzValue[0..1];
        attribute ritEnabled : Boolean[0..1];
        attribute ritOffsetHz : HertzValue[0..1];
        attribute xitEnabled : Boolean[0..1];
        attribute xitOffsetHz : HertzValue[0..1];
        attribute repeaterShift : RepeaterShift[0..1];
        attribute repeaterOffsetHz : HertzValue[0..1];
        attribute antennas : AntennaSelection[0..1];
        attribute tuningLocked : Boolean[0..1];
        attribute satelliteMode : Boolean[0..1];
        attribute dualWatch : Boolean[0..1];
        attribute diversity : Boolean[0..1];
        attribute band : String[0..1];
        attribute selectedSlice : String[0..1];
        attribute automaticRepeaterOffset : Boolean[0..1];
        attribute reverseRxTx : Boolean[0..1];
        attribute automaticBandMode : Boolean[0..1];
        attribute vfoSynchronization : Boolean[0..1];
        attribute fineTuning : Boolean[0..1];
        attribute vfoLinking : Boolean[0..1];
        attribute transmitOffsetHz : HertzValue[0..1];
    }
    attribute def RadioTuningCapabilities {
        attribute vfoDomain : VfoSelectionCapability[*];
        attribute frequencyDomain : HertzValueCapability[*];
        attribute rfModeDomain : StringCapability[*];
        attribute receiverFilterHzDomain : HertzValueCapability[*];
        attribute filterSelectionDomain : StringCapability[*];
        attribute tuningStepHzDomain : HertzValueCapability[*];
        attribute splitDomain : SplitSelectionCapability[*];
        attribute transmitFrequencyHzDomain : HertzValueCapability[*];
        attribute transmitRfModeDomain : StringCapability[*];
        attribute transmitFilterHzDomain : HertzValueCapability[*];
        attribute ritEnabledDomain : BooleanCapability[*];
        attribute ritOffsetHzDomain : HertzValueCapability[*];
        attribute xitEnabledDomain : BooleanCapability[*];
        attribute xitOffsetHzDomain : HertzValueCapability[*];
        attribute repeaterShiftDomain : RepeaterShiftCapability[*];
        attribute repeaterOffsetHzDomain : HertzValueCapability[*];
        attribute antennasDomain : AntennaSelectionCapability[*];
        attribute tuningLockedDomain : BooleanCapability[*];
        attribute satelliteModeDomain : BooleanCapability[*];
        attribute dualWatchDomain : BooleanCapability[*];
        attribute diversityDomain : BooleanCapability[*];
        attribute bandDomain : StringCapability[*];
        attribute selectedSliceDomain : StringCapability[*];
        attribute automaticRepeaterOffsetDomain : BooleanCapability[*];
        attribute reverseRxTxDomain : BooleanCapability[*];
        attribute automaticBandModeDomain : BooleanCapability[*];
        attribute vfoSynchronizationDomain : BooleanCapability[*];
        attribute fineTuningDomain : BooleanCapability[*];
        attribute vfoLinkingDomain : BooleanCapability[*];
        attribute transmitOffsetHzDomain : HertzValueCapability[*];
    }
    dependency tuning_vfo_metadata_owner from RadioTuningCapabilities::vfoDomain to RadioVfoValues::vfo;
    dependency tuning_frequency_metadata_owner from RadioTuningCapabilities::frequencyDomain to RadioVfoValues::frequency;
    dependency tuning_rfMode_metadata_owner from RadioTuningCapabilities::rfModeDomain to RadioVfoValues::rfMode;
    dependency tuning_receiverFilterHz_metadata_owner from RadioTuningCapabilities::receiverFilterHzDomain to RadioVfoValues::receiverFilterHz;
    dependency tuning_filterSelection_metadata_owner from RadioTuningCapabilities::filterSelectionDomain to RadioVfoValues::filterSelection;
    dependency tuning_tuningStepHz_metadata_owner from RadioTuningCapabilities::tuningStepHzDomain to RadioVfoValues::tuningStepHz;
    dependency tuning_split_metadata_owner from RadioTuningCapabilities::splitDomain to RadioVfoValues::split;
    dependency tuning_transmitFrequencyHz_metadata_owner from RadioTuningCapabilities::transmitFrequencyHzDomain to RadioVfoValues::transmitFrequencyHz;
    dependency tuning_transmitRfMode_metadata_owner from RadioTuningCapabilities::transmitRfModeDomain to RadioVfoValues::transmitRfMode;
    dependency tuning_transmitFilterHz_metadata_owner from RadioTuningCapabilities::transmitFilterHzDomain to RadioVfoValues::transmitFilterHz;
    dependency tuning_ritEnabled_metadata_owner from RadioTuningCapabilities::ritEnabledDomain to RadioVfoValues::ritEnabled;
    dependency tuning_ritOffsetHz_metadata_owner from RadioTuningCapabilities::ritOffsetHzDomain to RadioVfoValues::ritOffsetHz;
    dependency tuning_xitEnabled_metadata_owner from RadioTuningCapabilities::xitEnabledDomain to RadioVfoValues::xitEnabled;
    dependency tuning_xitOffsetHz_metadata_owner from RadioTuningCapabilities::xitOffsetHzDomain to RadioVfoValues::xitOffsetHz;
    dependency tuning_repeaterShift_metadata_owner from RadioTuningCapabilities::repeaterShiftDomain to RadioVfoValues::repeaterShift;
    dependency tuning_repeaterOffsetHz_metadata_owner from RadioTuningCapabilities::repeaterOffsetHzDomain to RadioVfoValues::repeaterOffsetHz;
    dependency tuning_antennas_metadata_owner from RadioTuningCapabilities::antennasDomain to RadioVfoValues::antennas;
    dependency tuning_tuningLocked_metadata_owner from RadioTuningCapabilities::tuningLockedDomain to RadioVfoValues::tuningLocked;
    dependency tuning_satelliteMode_metadata_owner from RadioTuningCapabilities::satelliteModeDomain to RadioVfoValues::satelliteMode;
    dependency tuning_dualWatch_metadata_owner from RadioTuningCapabilities::dualWatchDomain to RadioVfoValues::dualWatch;
    dependency tuning_diversity_metadata_owner from RadioTuningCapabilities::diversityDomain to RadioVfoValues::diversity;
    dependency tuning_band_metadata_owner from RadioTuningCapabilities::bandDomain to RadioVfoValues::band;
    dependency tuning_selectedSlice_metadata_owner from RadioTuningCapabilities::selectedSliceDomain to RadioVfoValues::selectedSlice;
    dependency tuning_automaticRepeaterOffset_metadata_owner from RadioTuningCapabilities::automaticRepeaterOffsetDomain to RadioVfoValues::automaticRepeaterOffset;
    dependency tuning_reverseRxTx_metadata_owner from RadioTuningCapabilities::reverseRxTxDomain to RadioVfoValues::reverseRxTx;
    dependency tuning_automaticBandMode_metadata_owner from RadioTuningCapabilities::automaticBandModeDomain to RadioVfoValues::automaticBandMode;
    dependency tuning_vfoSynchronization_metadata_owner from RadioTuningCapabilities::vfoSynchronizationDomain to RadioVfoValues::vfoSynchronization;
    dependency tuning_fineTuning_metadata_owner from RadioTuningCapabilities::fineTuningDomain to RadioVfoValues::fineTuning;
    dependency tuning_vfoLinking_metadata_owner from RadioTuningCapabilities::vfoLinkingDomain to RadioVfoValues::vfoLinking;
    dependency tuning_transmitOffsetHz_metadata_owner from RadioTuningCapabilities::transmitOffsetHzDomain to RadioVfoValues::transmitOffsetHz;
    attribute def RadioTransmitterSettings {
        attribute context : RadioPropertyContext;
        attribute evidence : RadioObservationEvidence[*];
        attribute ptt : RadioPttState[0..1];
        attribute powerState : RadioPowerState[0..1];
        attribute outputPowerW : WattValue[0..1];
        attribute outputPowerFraction : Real[0..1];
        attribute microphoneGainFraction : Real[0..1];
        attribute compressionEnabled : Boolean[0..1];
        attribute compressionFraction : Real[0..1];
        attribute voxEnabled : Boolean[0..1];
        attribute voxGainFraction : Real[0..1];
        attribute antiVoxFraction : Real[0..1];
        attribute voxDelaySeconds : SecondsValue[0..1];
        attribute tunerEnabled : Boolean[0..1];
        attribute inhibited : Boolean[0..1];
        attribute digitalPredistortion : Boolean[0..1];
        attribute externalAmplifierEnabled : Boolean[0..1];
        attribute driveGainLevel : Real[0..1];
        attribute bassLevel : Real[0..1];
        attribute extendedSsb : Boolean[0..1];
        attribute equalizerPreset : String[0..1];
        attribute dspBandwidthHz : HertzValue[0..1];
        attribute lowCutoffHz : HertzValue[0..1];
        attribute highCutoffHz : HertzValue[0..1];
        attribute dataTerminalSource : String[0..1];
        attribute maximumPowerW : WattValue[0..1];
        attribute remotePttSource : String[0..1];
        attribute timeoutSeconds : SecondsValue[0..1];
    }
    attribute def RadioTransmitterCapabilities {
        attribute pttDomain : RadioPttStateCapability[*];
        attribute powerStateDomain : RadioPowerStateCapability[*];
        attribute outputPowerWDomain : WattValueCapability[*];
        attribute outputPowerFractionDomain : RealCapability[*];
        attribute microphoneGainFractionDomain : RealCapability[*];
        attribute compressionEnabledDomain : BooleanCapability[*];
        attribute compressionFractionDomain : RealCapability[*];
        attribute voxEnabledDomain : BooleanCapability[*];
        attribute voxGainFractionDomain : RealCapability[*];
        attribute antiVoxFractionDomain : RealCapability[*];
        attribute voxDelaySecondsDomain : SecondsValueCapability[*];
        attribute tunerEnabledDomain : BooleanCapability[*];
        attribute inhibitedDomain : BooleanCapability[*];
        attribute digitalPredistortionDomain : BooleanCapability[*];
        attribute externalAmplifierEnabledDomain : BooleanCapability[*];
        attribute driveGainLevelDomain : RealCapability[*];
        attribute bassLevelDomain : RealCapability[*];
        attribute extendedSsbDomain : BooleanCapability[*];
        attribute equalizerPresetDomain : StringCapability[*];
        attribute dspBandwidthHzDomain : HertzValueCapability[*];
        attribute lowCutoffHzDomain : HertzValueCapability[*];
        attribute highCutoffHzDomain : HertzValueCapability[*];
        attribute dataTerminalSourceDomain : StringCapability[*];
        attribute maximumPowerWDomain : WattValueCapability[*];
        attribute remotePttSourceDomain : StringCapability[*];
        attribute timeoutSecondsDomain : SecondsValueCapability[*];
    }
    dependency transmitter_ptt_metadata_owner from RadioTransmitterCapabilities::pttDomain to RadioTransmitterSettings::ptt;
    dependency transmitter_powerState_metadata_owner from RadioTransmitterCapabilities::powerStateDomain to RadioTransmitterSettings::powerState;
    dependency transmitter_outputPowerW_metadata_owner from RadioTransmitterCapabilities::outputPowerWDomain to RadioTransmitterSettings::outputPowerW;
    dependency transmitter_outputPowerFraction_metadata_owner from RadioTransmitterCapabilities::outputPowerFractionDomain to RadioTransmitterSettings::outputPowerFraction;
    dependency transmitter_microphoneGainFraction_metadata_owner from RadioTransmitterCapabilities::microphoneGainFractionDomain to RadioTransmitterSettings::microphoneGainFraction;
    dependency transmitter_compressionEnabled_metadata_owner from RadioTransmitterCapabilities::compressionEnabledDomain to RadioTransmitterSettings::compressionEnabled;
    dependency transmitter_compressionFraction_metadata_owner from RadioTransmitterCapabilities::compressionFractionDomain to RadioTransmitterSettings::compressionFraction;
    dependency transmitter_voxEnabled_metadata_owner from RadioTransmitterCapabilities::voxEnabledDomain to RadioTransmitterSettings::voxEnabled;
    dependency transmitter_voxGainFraction_metadata_owner from RadioTransmitterCapabilities::voxGainFractionDomain to RadioTransmitterSettings::voxGainFraction;
    dependency transmitter_antiVoxFraction_metadata_owner from RadioTransmitterCapabilities::antiVoxFractionDomain to RadioTransmitterSettings::antiVoxFraction;
    dependency transmitter_voxDelaySeconds_metadata_owner from RadioTransmitterCapabilities::voxDelaySecondsDomain to RadioTransmitterSettings::voxDelaySeconds;
    dependency transmitter_tunerEnabled_metadata_owner from RadioTransmitterCapabilities::tunerEnabledDomain to RadioTransmitterSettings::tunerEnabled;
    dependency transmitter_inhibited_metadata_owner from RadioTransmitterCapabilities::inhibitedDomain to RadioTransmitterSettings::inhibited;
    dependency transmitter_digitalPredistortion_metadata_owner from RadioTransmitterCapabilities::digitalPredistortionDomain to RadioTransmitterSettings::digitalPredistortion;
    dependency transmitter_externalAmplifierEnabled_metadata_owner from RadioTransmitterCapabilities::externalAmplifierEnabledDomain to RadioTransmitterSettings::externalAmplifierEnabled;
    dependency transmitter_driveGainLevel_metadata_owner from RadioTransmitterCapabilities::driveGainLevelDomain to RadioTransmitterSettings::driveGainLevel;
    dependency transmitter_bassLevel_metadata_owner from RadioTransmitterCapabilities::bassLevelDomain to RadioTransmitterSettings::bassLevel;
    dependency transmitter_extendedSsb_metadata_owner from RadioTransmitterCapabilities::extendedSsbDomain to RadioTransmitterSettings::extendedSsb;
    dependency transmitter_equalizerPreset_metadata_owner from RadioTransmitterCapabilities::equalizerPresetDomain to RadioTransmitterSettings::equalizerPreset;
    dependency transmitter_dspBandwidthHz_metadata_owner from RadioTransmitterCapabilities::dspBandwidthHzDomain to RadioTransmitterSettings::dspBandwidthHz;
    dependency transmitter_lowCutoffHz_metadata_owner from RadioTransmitterCapabilities::lowCutoffHzDomain to RadioTransmitterSettings::lowCutoffHz;
    dependency transmitter_highCutoffHz_metadata_owner from RadioTransmitterCapabilities::highCutoffHzDomain to RadioTransmitterSettings::highCutoffHz;
    dependency transmitter_dataTerminalSource_metadata_owner from RadioTransmitterCapabilities::dataTerminalSourceDomain to RadioTransmitterSettings::dataTerminalSource;
    dependency transmitter_maximumPowerW_metadata_owner from RadioTransmitterCapabilities::maximumPowerWDomain to RadioTransmitterSettings::maximumPowerW;
    dependency transmitter_remotePttSource_metadata_owner from RadioTransmitterCapabilities::remotePttSourceDomain to RadioTransmitterSettings::remotePttSource;
    dependency transmitter_timeoutSeconds_metadata_owner from RadioTransmitterCapabilities::timeoutSecondsDomain to RadioTransmitterSettings::timeoutSeconds;
    attribute def RadioReceiverSettings {
        attribute context : RadioPropertyContext;
        attribute evidence : RadioObservationEvidence[*];
        attribute rfGainFraction : Real[0..1];
        attribute squelchFraction : Real[0..1];
        attribute squelchEnabled : Boolean[0..1];
        attribute preamplifierDb : Real[0..1];
        attribute attenuationDb : Real[0..1];
        attribute agcMode : String[0..1];
        attribute agcTimeSeconds : SecondsValue[0..1];
        attribute noiseBlankerMode : String[0..1];
        attribute noiseBlankerFraction : Real[0..1];
        attribute noiseReductionMode : String[0..1];
        attribute noiseReductionFraction : Real[0..1];
        attribute automaticNotchEnabled : Boolean[0..1];
        attribute manualNotchEnabled : Boolean[0..1];
        attribute notchFrequencyHz : HertzValue[0..1];
        attribute ifShiftHz : HertzValue[0..1];
        attribute passbandInnerFraction : Real[0..1];
        attribute passbandOuterFraction : Real[0..1];
        attribute filterLowCutoffHz : HertzValue[0..1];
        attribute filterHighCutoffHz : HertzValue[0..1];
        attribute audioPeakFilterEnabled : Boolean[0..1];
        attribute audioPeakFilterFraction : Real[0..1];
        attribute automaticFrequencyControl : Boolean[0..1];
        attribute fastAgc : Boolean[0..1];
        attribute preampBypass : Boolean[0..1];
        attribute rttyFilter : Boolean[0..1];
        attribute secondNoiseBlanker : Boolean[0..1];
        attribute beatCancellerMode : String[0..1];
        attribute manualBeatCanceller : Boolean[0..1];
        attribute secondBeatCanceller : Boolean[0..1];
        attribute audioFilter : Boolean[0..1];
        attribute noiseLimiter : Boolean[0..1];
        attribute digitalSquelch : Boolean[0..1];
        attribute squelchMonitorEnabled : Boolean[0..1];
        attribute notchPositionFraction : Real[0..1];
        attribute preselectorEnabled : Boolean[0..1];
        attribute preselectorLevel : Real[0..1];
        attribute ipPlus : Boolean[0..1];
        attribute ifCenterFrequencyHz : HertzValue[0..1];
        attribute receiveAntennaEnabled : Boolean[0..1];
        attribute ifNoiseBlankerLevel : Real[0..1];
        attribute equalizerPreset : String[0..1];
        attribute digitalNoiseLimiter : Boolean[0..1];
        attribute cwIfFilterForSsb : Boolean[0..1];
        attribute dataWidthFilter : Boolean[0..1];
        attribute roofingFilter : String[0..1];
        attribute audioPeakFilterOffset : Real[0..1];
        attribute audioPeakFilterWidth : String[0..1];
        attribute contourEnabled : Boolean[0..1];
        attribute contourFrequencyHz : HertzValue[0..1];
        attribute contourLevel : Real[0..1];
        attribute contourWidth : Real[0..1];
        attribute fmCenterDeviationHz : HertzValue[0..1];
        doc /* filterLowCutoffHz/filterHighCutoffHz correct former slope String labels.
             notchPositionFraction is normalized, distinct from notchFrequencyHz.
             Fractions/model scales have no inferred Hz/dB conversion. Roofing filter
             depends on installed hardware. APF offset/contour width model scales remain
             unresolved where source gives no physical unit. */
    }
    attribute def RadioReceiverCapabilities {
        attribute rfGainFractionDomain : RealCapability[*];
        attribute squelchFractionDomain : RealCapability[*];
        attribute squelchEnabledDomain : BooleanCapability[*];
        attribute preamplifierDbDomain : RealCapability[*];
        attribute attenuationDbDomain : RealCapability[*];
        attribute agcModeDomain : StringCapability[*];
        attribute agcTimeSecondsDomain : SecondsValueCapability[*];
        attribute noiseBlankerModeDomain : StringCapability[*];
        attribute noiseBlankerFractionDomain : RealCapability[*];
        attribute noiseReductionModeDomain : StringCapability[*];
        attribute noiseReductionFractionDomain : RealCapability[*];
        attribute automaticNotchEnabledDomain : BooleanCapability[*];
        attribute manualNotchEnabledDomain : BooleanCapability[*];
        attribute notchFrequencyHzDomain : HertzValueCapability[*];
        attribute ifShiftHzDomain : HertzValueCapability[*];
        attribute passbandInnerFractionDomain : RealCapability[*];
        attribute passbandOuterFractionDomain : RealCapability[*];
        attribute filterLowCutoffHzDomain : HertzValueCapability[*];
        attribute filterHighCutoffHzDomain : HertzValueCapability[*];
        attribute audioPeakFilterEnabledDomain : BooleanCapability[*];
        attribute audioPeakFilterFractionDomain : RealCapability[*];
        attribute automaticFrequencyControlDomain : BooleanCapability[*];
        attribute fastAgcDomain : BooleanCapability[*];
        attribute preampBypassDomain : BooleanCapability[*];
        attribute rttyFilterDomain : BooleanCapability[*];
        attribute secondNoiseBlankerDomain : BooleanCapability[*];
        attribute beatCancellerModeDomain : StringCapability[*];
        attribute manualBeatCancellerDomain : BooleanCapability[*];
        attribute secondBeatCancellerDomain : BooleanCapability[*];
        attribute audioFilterDomain : BooleanCapability[*];
        attribute noiseLimiterDomain : BooleanCapability[*];
        attribute digitalSquelchDomain : BooleanCapability[*];
        attribute squelchMonitorEnabledDomain : BooleanCapability[*];
        attribute notchPositionFractionDomain : RealCapability[*];
        attribute preselectorEnabledDomain : BooleanCapability[*];
        attribute preselectorLevelDomain : RealCapability[*];
        attribute ipPlusDomain : BooleanCapability[*];
        attribute ifCenterFrequencyHzDomain : HertzValueCapability[*];
        attribute receiveAntennaEnabledDomain : BooleanCapability[*];
        attribute ifNoiseBlankerLevelDomain : RealCapability[*];
        attribute equalizerPresetDomain : StringCapability[*];
        attribute digitalNoiseLimiterDomain : BooleanCapability[*];
        attribute cwIfFilterForSsbDomain : BooleanCapability[*];
        attribute dataWidthFilterDomain : BooleanCapability[*];
        attribute roofingFilterDomain : StringCapability[*];
        attribute audioPeakFilterOffsetDomain : RealCapability[*];
        attribute audioPeakFilterWidthDomain : StringCapability[*];
        attribute contourEnabledDomain : BooleanCapability[*];
        attribute contourFrequencyHzDomain : HertzValueCapability[*];
        attribute contourLevelDomain : RealCapability[*];
        attribute contourWidthDomain : RealCapability[*];
        attribute fmCenterDeviationHzDomain : ReadOnlyHertzValueCapability[*];
    }
    dependency receiver_rfGainFraction_metadata_owner from RadioReceiverCapabilities::rfGainFractionDomain to RadioReceiverSettings::rfGainFraction;
    dependency receiver_squelchFraction_metadata_owner from RadioReceiverCapabilities::squelchFractionDomain to RadioReceiverSettings::squelchFraction;
    dependency receiver_squelchEnabled_metadata_owner from RadioReceiverCapabilities::squelchEnabledDomain to RadioReceiverSettings::squelchEnabled;
    dependency receiver_preamplifierDb_metadata_owner from RadioReceiverCapabilities::preamplifierDbDomain to RadioReceiverSettings::preamplifierDb;
    dependency receiver_attenuationDb_metadata_owner from RadioReceiverCapabilities::attenuationDbDomain to RadioReceiverSettings::attenuationDb;
    dependency receiver_agcMode_metadata_owner from RadioReceiverCapabilities::agcModeDomain to RadioReceiverSettings::agcMode;
    dependency receiver_agcTimeSeconds_metadata_owner from RadioReceiverCapabilities::agcTimeSecondsDomain to RadioReceiverSettings::agcTimeSeconds;
    dependency receiver_noiseBlankerMode_metadata_owner from RadioReceiverCapabilities::noiseBlankerModeDomain to RadioReceiverSettings::noiseBlankerMode;
    dependency receiver_noiseBlankerFraction_metadata_owner from RadioReceiverCapabilities::noiseBlankerFractionDomain to RadioReceiverSettings::noiseBlankerFraction;
    dependency receiver_noiseReductionMode_metadata_owner from RadioReceiverCapabilities::noiseReductionModeDomain to RadioReceiverSettings::noiseReductionMode;
    dependency receiver_noiseReductionFraction_metadata_owner from RadioReceiverCapabilities::noiseReductionFractionDomain to RadioReceiverSettings::noiseReductionFraction;
    dependency receiver_automaticNotchEnabled_metadata_owner from RadioReceiverCapabilities::automaticNotchEnabledDomain to RadioReceiverSettings::automaticNotchEnabled;
    dependency receiver_manualNotchEnabled_metadata_owner from RadioReceiverCapabilities::manualNotchEnabledDomain to RadioReceiverSettings::manualNotchEnabled;
    dependency receiver_notchFrequencyHz_metadata_owner from RadioReceiverCapabilities::notchFrequencyHzDomain to RadioReceiverSettings::notchFrequencyHz;
    dependency receiver_ifShiftHz_metadata_owner from RadioReceiverCapabilities::ifShiftHzDomain to RadioReceiverSettings::ifShiftHz;
    dependency receiver_passbandInnerFraction_metadata_owner from RadioReceiverCapabilities::passbandInnerFractionDomain to RadioReceiverSettings::passbandInnerFraction;
    dependency receiver_passbandOuterFraction_metadata_owner from RadioReceiverCapabilities::passbandOuterFractionDomain to RadioReceiverSettings::passbandOuterFraction;
    dependency receiver_filterLowCutoffHz_metadata_owner from RadioReceiverCapabilities::filterLowCutoffHzDomain to RadioReceiverSettings::filterLowCutoffHz;
    dependency receiver_filterHighCutoffHz_metadata_owner from RadioReceiverCapabilities::filterHighCutoffHzDomain to RadioReceiverSettings::filterHighCutoffHz;
    dependency receiver_audioPeakFilterEnabled_metadata_owner from RadioReceiverCapabilities::audioPeakFilterEnabledDomain to RadioReceiverSettings::audioPeakFilterEnabled;
    dependency receiver_audioPeakFilterFraction_metadata_owner from RadioReceiverCapabilities::audioPeakFilterFractionDomain to RadioReceiverSettings::audioPeakFilterFraction;
    dependency receiver_automaticFrequencyControl_metadata_owner from RadioReceiverCapabilities::automaticFrequencyControlDomain to RadioReceiverSettings::automaticFrequencyControl;
    dependency receiver_fastAgc_metadata_owner from RadioReceiverCapabilities::fastAgcDomain to RadioReceiverSettings::fastAgc;
    dependency receiver_preampBypass_metadata_owner from RadioReceiverCapabilities::preampBypassDomain to RadioReceiverSettings::preampBypass;
    dependency receiver_rttyFilter_metadata_owner from RadioReceiverCapabilities::rttyFilterDomain to RadioReceiverSettings::rttyFilter;
    dependency receiver_secondNoiseBlanker_metadata_owner from RadioReceiverCapabilities::secondNoiseBlankerDomain to RadioReceiverSettings::secondNoiseBlanker;
    dependency receiver_beatCancellerMode_metadata_owner from RadioReceiverCapabilities::beatCancellerModeDomain to RadioReceiverSettings::beatCancellerMode;
    dependency receiver_manualBeatCanceller_metadata_owner from RadioReceiverCapabilities::manualBeatCancellerDomain to RadioReceiverSettings::manualBeatCanceller;
    dependency receiver_secondBeatCanceller_metadata_owner from RadioReceiverCapabilities::secondBeatCancellerDomain to RadioReceiverSettings::secondBeatCanceller;
    dependency receiver_audioFilter_metadata_owner from RadioReceiverCapabilities::audioFilterDomain to RadioReceiverSettings::audioFilter;
    dependency receiver_noiseLimiter_metadata_owner from RadioReceiverCapabilities::noiseLimiterDomain to RadioReceiverSettings::noiseLimiter;
    dependency receiver_digitalSquelch_metadata_owner from RadioReceiverCapabilities::digitalSquelchDomain to RadioReceiverSettings::digitalSquelch;
    dependency receiver_squelchMonitorEnabled_metadata_owner from RadioReceiverCapabilities::squelchMonitorEnabledDomain to RadioReceiverSettings::squelchMonitorEnabled;
    dependency receiver_notchPositionFraction_metadata_owner from RadioReceiverCapabilities::notchPositionFractionDomain to RadioReceiverSettings::notchPositionFraction;
    dependency receiver_preselectorEnabled_metadata_owner from RadioReceiverCapabilities::preselectorEnabledDomain to RadioReceiverSettings::preselectorEnabled;
    dependency receiver_preselectorLevel_metadata_owner from RadioReceiverCapabilities::preselectorLevelDomain to RadioReceiverSettings::preselectorLevel;
    dependency receiver_ipPlus_metadata_owner from RadioReceiverCapabilities::ipPlusDomain to RadioReceiverSettings::ipPlus;
    dependency receiver_ifCenterFrequencyHz_metadata_owner from RadioReceiverCapabilities::ifCenterFrequencyHzDomain to RadioReceiverSettings::ifCenterFrequencyHz;
    dependency receiver_receiveAntennaEnabled_metadata_owner from RadioReceiverCapabilities::receiveAntennaEnabledDomain to RadioReceiverSettings::receiveAntennaEnabled;
    dependency receiver_ifNoiseBlankerLevel_metadata_owner from RadioReceiverCapabilities::ifNoiseBlankerLevelDomain to RadioReceiverSettings::ifNoiseBlankerLevel;
    dependency receiver_equalizerPreset_metadata_owner from RadioReceiverCapabilities::equalizerPresetDomain to RadioReceiverSettings::equalizerPreset;
    dependency receiver_digitalNoiseLimiter_metadata_owner from RadioReceiverCapabilities::digitalNoiseLimiterDomain to RadioReceiverSettings::digitalNoiseLimiter;
    dependency receiver_cwIfFilterForSsb_metadata_owner from RadioReceiverCapabilities::cwIfFilterForSsbDomain to RadioReceiverSettings::cwIfFilterForSsb;
    dependency receiver_dataWidthFilter_metadata_owner from RadioReceiverCapabilities::dataWidthFilterDomain to RadioReceiverSettings::dataWidthFilter;
    dependency receiver_roofingFilter_metadata_owner from RadioReceiverCapabilities::roofingFilterDomain to RadioReceiverSettings::roofingFilter;
    dependency receiver_audioPeakFilterOffset_metadata_owner from RadioReceiverCapabilities::audioPeakFilterOffsetDomain to RadioReceiverSettings::audioPeakFilterOffset;
    dependency receiver_audioPeakFilterWidth_metadata_owner from RadioReceiverCapabilities::audioPeakFilterWidthDomain to RadioReceiverSettings::audioPeakFilterWidth;
    dependency receiver_contourEnabled_metadata_owner from RadioReceiverCapabilities::contourEnabledDomain to RadioReceiverSettings::contourEnabled;
    dependency receiver_contourFrequencyHz_metadata_owner from RadioReceiverCapabilities::contourFrequencyHzDomain to RadioReceiverSettings::contourFrequencyHz;
    dependency receiver_contourLevel_metadata_owner from RadioReceiverCapabilities::contourLevelDomain to RadioReceiverSettings::contourLevel;
    dependency receiver_contourWidth_metadata_owner from RadioReceiverCapabilities::contourWidthDomain to RadioReceiverSettings::contourWidth;
    dependency receiver_fmCenterDeviationHz_metadata_owner from RadioReceiverCapabilities::fmCenterDeviationHzDomain to RadioReceiverSettings::fmCenterDeviationHz;
    attribute def RadioAudioSettings {
        attribute context : RadioPropertyContext;
        attribute evidence : RadioObservationEvidence[*];
        attribute afGainFraction : Real[0..1];
        attribute balanceFraction : Real[0..1];
        attribute muted : Boolean[0..1];
        attribute monitorEnabled : Boolean[0..1];
        attribute monitorGainFraction : Real[0..1];
        attribute usbOutputGainFraction : Real[0..1];
        attribute usbInputGainFraction : Real[0..1];
        attribute inputSource : String[0..1];
        attribute outputSource : String[0..1];
        attribute accUsbOutputGainFraction : Real[0..1];
        attribute accUsbInputGainFraction : Real[0..1];
        attribute usbSignalSource : String[0..1];
        attribute lanSignalSource : String[0..1];
        attribute wlanSignalSource : String[0..1];
        attribute accSignalSource : String[0..1];
        attribute earphoneMode : String[0..1];
        attribute recorderEnabled : Boolean[0..1];
        attribute tapeSwitch : Boolean[0..1];
        attribute speakerEnabled : Boolean[0..1];
        attribute audioPresent : Boolean[0..1];
        attribute beepLevel : Real[0..1];
        attribute sidetoneLevel : Real[0..1];
        attribute accInputLevel : Real[0..1];
        attribute accOutputLevel : Real[0..1];
        attribute usbInputLevel : Real[0..1];
        attribute usbOutputLevel : Real[0..1];
        attribute dataInputLevel : Real[0..1];
        attribute dataOutputLevel : Real[0..1];
        attribute bluetoothEnabled : Boolean[0..1];
        attribute bluetoothAudioRoute : String[0..1];
        attribute subbandMuted : Boolean[0..1];
        doc /* Radio audio routing only. ACC/USB source differs from USB-only
             output where independently known; legacy usbOutputGainFraction remains
             that narrower meaning. Extension ACC/USB levels are model scales, not
             normalized fractions without evidence. PC audio authority stays separate. */
    }
    attribute def RadioAudioCapabilities {
        attribute afGainFractionDomain : RealCapability[*];
        attribute balanceFractionDomain : RealCapability[*];
        attribute mutedDomain : BooleanCapability[*];
        attribute monitorEnabledDomain : BooleanCapability[*];
        attribute monitorGainFractionDomain : RealCapability[*];
        attribute usbOutputGainFractionDomain : RealCapability[*];
        attribute usbInputGainFractionDomain : RealCapability[*];
        attribute inputSourceDomain : StringCapability[*];
        attribute outputSourceDomain : StringCapability[*];
        attribute accUsbOutputGainFractionDomain : RealCapability[*];
        attribute accUsbInputGainFractionDomain : RealCapability[*];
        attribute usbSignalSourceDomain : StringCapability[*];
        attribute lanSignalSourceDomain : StringCapability[*];
        attribute wlanSignalSourceDomain : StringCapability[*];
        attribute accSignalSourceDomain : StringCapability[*];
        attribute earphoneModeDomain : StringCapability[*];
        attribute recorderEnabledDomain : BooleanCapability[*];
        attribute tapeSwitchDomain : BooleanCapability[*];
        attribute speakerEnabledDomain : BooleanCapability[*];
        attribute audioPresentDomain : ReadOnlyBooleanCapability[*];
        attribute beepLevelDomain : RealCapability[*];
        attribute sidetoneLevelDomain : RealCapability[*];
        attribute accInputLevelDomain : RealCapability[*];
        attribute accOutputLevelDomain : RealCapability[*];
        attribute usbInputLevelDomain : RealCapability[*];
        attribute usbOutputLevelDomain : RealCapability[*];
        attribute dataInputLevelDomain : RealCapability[*];
        attribute dataOutputLevelDomain : RealCapability[*];
        attribute bluetoothEnabledDomain : BooleanCapability[*];
        attribute bluetoothAudioRouteDomain : StringCapability[*];
        attribute subbandMutedDomain : BooleanCapability[*];
    }
    dependency audio_afGainFraction_metadata_owner from RadioAudioCapabilities::afGainFractionDomain to RadioAudioSettings::afGainFraction;
    dependency audio_balanceFraction_metadata_owner from RadioAudioCapabilities::balanceFractionDomain to RadioAudioSettings::balanceFraction;
    dependency audio_muted_metadata_owner from RadioAudioCapabilities::mutedDomain to RadioAudioSettings::muted;
    dependency audio_monitorEnabled_metadata_owner from RadioAudioCapabilities::monitorEnabledDomain to RadioAudioSettings::monitorEnabled;
    dependency audio_monitorGainFraction_metadata_owner from RadioAudioCapabilities::monitorGainFractionDomain to RadioAudioSettings::monitorGainFraction;
    dependency audio_usbOutputGainFraction_metadata_owner from RadioAudioCapabilities::usbOutputGainFractionDomain to RadioAudioSettings::usbOutputGainFraction;
    dependency audio_usbInputGainFraction_metadata_owner from RadioAudioCapabilities::usbInputGainFractionDomain to RadioAudioSettings::usbInputGainFraction;
    dependency audio_inputSource_metadata_owner from RadioAudioCapabilities::inputSourceDomain to RadioAudioSettings::inputSource;
    dependency audio_outputSource_metadata_owner from RadioAudioCapabilities::outputSourceDomain to RadioAudioSettings::outputSource;
    dependency audio_accUsbInputGainFraction_metadata_owner from RadioAudioCapabilities::accUsbInputGainFractionDomain to RadioAudioSettings::accUsbInputGainFraction;
    dependency audio_accUsbOutputGainFraction_metadata_owner from RadioAudioCapabilities::accUsbOutputGainFractionDomain to RadioAudioSettings::accUsbOutputGainFraction;
    dependency audio_usbSignalSource_metadata_owner from RadioAudioCapabilities::usbSignalSourceDomain to RadioAudioSettings::usbSignalSource;
    dependency audio_lanSignalSource_metadata_owner from RadioAudioCapabilities::lanSignalSourceDomain to RadioAudioSettings::lanSignalSource;
    dependency audio_wlanSignalSource_metadata_owner from RadioAudioCapabilities::wlanSignalSourceDomain to RadioAudioSettings::wlanSignalSource;
    dependency audio_accSignalSource_metadata_owner from RadioAudioCapabilities::accSignalSourceDomain to RadioAudioSettings::accSignalSource;
    dependency audio_earphoneMode_metadata_owner from RadioAudioCapabilities::earphoneModeDomain to RadioAudioSettings::earphoneMode;
    dependency audio_recorderEnabled_metadata_owner from RadioAudioCapabilities::recorderEnabledDomain to RadioAudioSettings::recorderEnabled;
    dependency audio_tapeSwitch_metadata_owner from RadioAudioCapabilities::tapeSwitchDomain to RadioAudioSettings::tapeSwitch;
    dependency audio_speakerEnabled_metadata_owner from RadioAudioCapabilities::speakerEnabledDomain to RadioAudioSettings::speakerEnabled;
    dependency audio_audioPresent_metadata_owner from RadioAudioCapabilities::audioPresentDomain to RadioAudioSettings::audioPresent;
    dependency audio_beepLevel_metadata_owner from RadioAudioCapabilities::beepLevelDomain to RadioAudioSettings::beepLevel;
    dependency audio_sidetoneLevel_metadata_owner from RadioAudioCapabilities::sidetoneLevelDomain to RadioAudioSettings::sidetoneLevel;
    dependency audio_accInputLevel_metadata_owner from RadioAudioCapabilities::accInputLevelDomain to RadioAudioSettings::accInputLevel;
    dependency audio_accOutputLevel_metadata_owner from RadioAudioCapabilities::accOutputLevelDomain to RadioAudioSettings::accOutputLevel;
    dependency audio_usbInputLevel_metadata_owner from RadioAudioCapabilities::usbInputLevelDomain to RadioAudioSettings::usbInputLevel;
    dependency audio_usbOutputLevel_metadata_owner from RadioAudioCapabilities::usbOutputLevelDomain to RadioAudioSettings::usbOutputLevel;
    dependency audio_dataInputLevel_metadata_owner from RadioAudioCapabilities::dataInputLevelDomain to RadioAudioSettings::dataInputLevel;
    dependency audio_dataOutputLevel_metadata_owner from RadioAudioCapabilities::dataOutputLevelDomain to RadioAudioSettings::dataOutputLevel;
    dependency audio_bluetoothEnabled_metadata_owner from RadioAudioCapabilities::bluetoothEnabledDomain to RadioAudioSettings::bluetoothEnabled;
    dependency audio_bluetoothAudioRoute_metadata_owner from RadioAudioCapabilities::bluetoothAudioRouteDomain to RadioAudioSettings::bluetoothAudioRoute;
    dependency audio_subbandMuted_metadata_owner from RadioAudioCapabilities::subbandMutedDomain to RadioAudioSettings::subbandMuted;
    attribute def RadioKeyerSettings {
        attribute context : RadioPropertyContext;
        attribute evidence : RadioObservationEvidence[*];
        attribute speedWordsPerMinute : Real[0..1];
        attribute pitchHz : HertzValue[0..1];
        attribute keyerType : String[0..1];
        attribute breakIn : BreakInMode[0..1];
        attribute breakInDelaySeconds : SecondsValue[0..1];
        attribute breakInDelayTenthsOfDot : Real[0..1];
        attribute breakInDelayMilliseconds : MillisecondsValue[0..1];
        attribute enabled : Boolean[0..1];
        attribute weighting : Real[0..1];
        attribute polarity : String[0..1];
        attribute numberFormat : String[0..1];
        attribute repeatIntervalSeconds : SecondsValue[0..1];
        attribute qskDelayMilliseconds : MillisecondsValue[0..1];
        doc /* breakInDelayTenthsOfDot (BKINDL), milliseconds (BKIN_DLYMS) and
             independently evidenced seconds remain distinct; no inferred conversion. */
    }
    attribute def RadioKeyerCapabilities {
        attribute speedWordsPerMinuteDomain : RealCapability[*];
        attribute pitchHzDomain : HertzValueCapability[*];
        attribute keyerTypeDomain : StringCapability[*];
        attribute breakInDomain : BreakInModeCapability[*];
        attribute breakInDelaySecondsDomain : SecondsValueCapability[*];
        attribute breakInDelayTenthsOfDotDomain : RealCapability[*];
        attribute breakInDelayMillisecondsDomain : MillisecondsValueCapability[*];
        attribute enabledDomain : BooleanCapability[*];
        attribute weightingDomain : RealCapability[*];
        attribute polarityDomain : StringCapability[*];
        attribute numberFormatDomain : StringCapability[*];
        attribute repeatIntervalSecondsDomain : SecondsValueCapability[*];
        attribute qskDelayMillisecondsDomain : MillisecondsValueCapability[*];
    }
    dependency keyer_speedWordsPerMinute_metadata_owner from RadioKeyerCapabilities::speedWordsPerMinuteDomain to RadioKeyerSettings::speedWordsPerMinute;
    dependency keyer_pitchHz_metadata_owner from RadioKeyerCapabilities::pitchHzDomain to RadioKeyerSettings::pitchHz;
    dependency keyer_keyerType_metadata_owner from RadioKeyerCapabilities::keyerTypeDomain to RadioKeyerSettings::keyerType;
    dependency keyer_breakIn_metadata_owner from RadioKeyerCapabilities::breakInDomain to RadioKeyerSettings::breakIn;
    dependency keyer_breakInDelaySeconds_metadata_owner from RadioKeyerCapabilities::breakInDelaySecondsDomain to RadioKeyerSettings::breakInDelaySeconds;
    dependency keyer_breakInDelayTenthsOfDot_metadata_owner from RadioKeyerCapabilities::breakInDelayTenthsOfDotDomain to RadioKeyerSettings::breakInDelayTenthsOfDot;
    dependency keyer_breakInDelayMilliseconds_metadata_owner from RadioKeyerCapabilities::breakInDelayMillisecondsDomain to RadioKeyerSettings::breakInDelayMilliseconds;
    dependency keyer_enabled_metadata_owner from RadioKeyerCapabilities::enabledDomain to RadioKeyerSettings::enabled;
    dependency keyer_weighting_metadata_owner from RadioKeyerCapabilities::weightingDomain to RadioKeyerSettings::weighting;
    dependency keyer_polarity_metadata_owner from RadioKeyerCapabilities::polarityDomain to RadioKeyerSettings::polarity;
    dependency keyer_numberFormat_metadata_owner from RadioKeyerCapabilities::numberFormatDomain to RadioKeyerSettings::numberFormat;
    dependency keyer_repeatIntervalSeconds_metadata_owner from RadioKeyerCapabilities::repeatIntervalSecondsDomain to RadioKeyerSettings::repeatIntervalSeconds;
    dependency keyer_qskDelayMilliseconds_metadata_owner from RadioKeyerCapabilities::qskDelayMillisecondsDomain to RadioKeyerSettings::qskDelayMilliseconds;
    attribute def RadioToneSettings {
        attribute context : RadioPropertyContext;
        attribute evidence : RadioObservationEvidence[*];
        attribute ctcssToneHz : HertzValue[0..1];
        attribute ctcssSquelchToneHz : HertzValue[0..1];
        attribute ctcssEnabled : Boolean[0..1];
        attribute ctcssSquelchEnabled : Boolean[0..1];
        attribute dcsCode : String[0..1];
        attribute dcsSquelchCode : String[0..1];
        attribute dcsEnabled : Boolean[0..1];
        attribute dcsSquelchEnabled : Boolean[0..1];
        attribute toneBurstEnabled : Boolean[0..1];
        attribute ctcssDetected : Boolean[0..1];
        attribute dcsDetected : Boolean[0..1];
        attribute detectedCtcssHz : HertzValue[0..1];
        attribute detectedDcsCode : String[0..1];
        attribute dtmfPending : Boolean[0..1];
        attribute dtmfOverflow : Boolean[0..1];
        attribute dtmfToneDurationMilliseconds : MillisecondsValue[0..1];
        attribute dtmfPauseMilliseconds : MillisecondsValue[0..1];
        attribute dcsPolarity : String[0..1];
        attribute rttyToneHz : HertzValue[0..1];
        attribute rttyShiftHz : HertzValue[0..1];
        attribute rttyPolarity : String[0..1];
    }
    attribute def RadioTonesCapabilities {
        attribute ctcssToneHzDomain : HertzValueCapability[*];
        attribute ctcssSquelchToneHzDomain : HertzValueCapability[*];
        attribute ctcssEnabledDomain : BooleanCapability[*];
        attribute ctcssSquelchEnabledDomain : BooleanCapability[*];
        attribute dcsCodeDomain : StringCapability[*];
        attribute dcsSquelchCodeDomain : StringCapability[*];
        attribute dcsEnabledDomain : BooleanCapability[*];
        attribute dcsSquelchEnabledDomain : BooleanCapability[*];
        attribute toneBurstEnabledDomain : BooleanCapability[*];
        attribute ctcssDetectedDomain : ReadOnlyBooleanCapability[*];
        attribute dcsDetectedDomain : ReadOnlyBooleanCapability[*];
        attribute detectedCtcssHzDomain : ReadOnlyHertzValueCapability[*];
        attribute detectedDcsCodeDomain : ReadOnlyStringCapability[*];
        attribute dtmfPendingDomain : ReadOnlyBooleanCapability[*];
        attribute dtmfOverflowDomain : ReadOnlyBooleanCapability[*];
        attribute dtmfToneDurationMillisecondsDomain : MillisecondsValueCapability[*];
        attribute dtmfPauseMillisecondsDomain : MillisecondsValueCapability[*];
        attribute dcsPolarityDomain : StringCapability[*];
        attribute rttyToneHzDomain : HertzValueCapability[*];
        attribute rttyShiftHzDomain : HertzValueCapability[*];
        attribute rttyPolarityDomain : StringCapability[*];
    }
    dependency tones_ctcssToneHz_metadata_owner from RadioTonesCapabilities::ctcssToneHzDomain to RadioToneSettings::ctcssToneHz;
    dependency tones_ctcssSquelchToneHz_metadata_owner from RadioTonesCapabilities::ctcssSquelchToneHzDomain to RadioToneSettings::ctcssSquelchToneHz;
    dependency tones_ctcssEnabled_metadata_owner from RadioTonesCapabilities::ctcssEnabledDomain to RadioToneSettings::ctcssEnabled;
    dependency tones_ctcssSquelchEnabled_metadata_owner from RadioTonesCapabilities::ctcssSquelchEnabledDomain to RadioToneSettings::ctcssSquelchEnabled;
    dependency tones_dcsCode_metadata_owner from RadioTonesCapabilities::dcsCodeDomain to RadioToneSettings::dcsCode;
    dependency tones_dcsSquelchCode_metadata_owner from RadioTonesCapabilities::dcsSquelchCodeDomain to RadioToneSettings::dcsSquelchCode;
    dependency tones_dcsEnabled_metadata_owner from RadioTonesCapabilities::dcsEnabledDomain to RadioToneSettings::dcsEnabled;
    dependency tones_dcsSquelchEnabled_metadata_owner from RadioTonesCapabilities::dcsSquelchEnabledDomain to RadioToneSettings::dcsSquelchEnabled;
    dependency tones_toneBurstEnabled_metadata_owner from RadioTonesCapabilities::toneBurstEnabledDomain to RadioToneSettings::toneBurstEnabled;
    dependency tones_ctcssDetected_metadata_owner from RadioTonesCapabilities::ctcssDetectedDomain to RadioToneSettings::ctcssDetected;
    dependency tones_dcsDetected_metadata_owner from RadioTonesCapabilities::dcsDetectedDomain to RadioToneSettings::dcsDetected;
    dependency tones_detectedCtcssHz_metadata_owner from RadioTonesCapabilities::detectedCtcssHzDomain to RadioToneSettings::detectedCtcssHz;
    dependency tones_detectedDcsCode_metadata_owner from RadioTonesCapabilities::detectedDcsCodeDomain to RadioToneSettings::detectedDcsCode;
    dependency tones_dtmfPending_metadata_owner from RadioTonesCapabilities::dtmfPendingDomain to RadioToneSettings::dtmfPending;
    dependency tones_dtmfOverflow_metadata_owner from RadioTonesCapabilities::dtmfOverflowDomain to RadioToneSettings::dtmfOverflow;
    dependency tones_dtmfToneDurationMilliseconds_metadata_owner from RadioTonesCapabilities::dtmfToneDurationMillisecondsDomain to RadioToneSettings::dtmfToneDurationMilliseconds;
    dependency tones_dtmfPauseMilliseconds_metadata_owner from RadioTonesCapabilities::dtmfPauseMillisecondsDomain to RadioToneSettings::dtmfPauseMilliseconds;
    dependency tones_dcsPolarity_metadata_owner from RadioTonesCapabilities::dcsPolarityDomain to RadioToneSettings::dcsPolarity;
    dependency tones_rttyToneHz_metadata_owner from RadioTonesCapabilities::rttyToneHzDomain to RadioToneSettings::rttyToneHz;
    dependency tones_rttyShiftHz_metadata_owner from RadioTonesCapabilities::rttyShiftHzDomain to RadioToneSettings::rttyShiftHz;
    dependency tones_rttyPolarity_metadata_owner from RadioTonesCapabilities::rttyPolarityDomain to RadioToneSettings::rttyPolarity;
    attribute def RadioScopeSettings {
        attribute context : RadioPropertyContext;
        attribute evidence : RadioObservationEvidence[*];
        attribute scopeId : String[0..1];
        attribute enabled : Boolean[0..1];
        attribute held : Boolean[0..1];
        attribute mode : String[0..1];
        attribute radioScopeHz : FrequencyRange[0..1];
        attribute spanHz : HertzValue[0..1];
        attribute referenceLevelDb : Real[0..1];
        attribute attenuationDb : Real[0..1];
        attribute averagingMode : String[0..1];
        attribute speed : String[0..1];
        attribute spectrumEnabled : Boolean[0..1];
        attribute receiverSelection : String[0..1];
        attribute dualScope : Boolean[0..1];
        attribute fixedEdgePreset : String[0..1];
        attribute onTransmit : Boolean[0..1];
        attribute centerReference : String[0..1];
        attribute videoBandwidth : String[0..1];
        attribute resolutionBandwidth : String[0..1];
        doc /* Physical radio spectrum range/span differs from receive filter
             bandwidth and frontend waterfall span. A filter name supplies no width. */
    }
    attribute def RadioScopeCapabilities {
        attribute scopeIdDomain : StringCapability[*];
        attribute enabledDomain : BooleanCapability[*];
        attribute heldDomain : BooleanCapability[*];
        attribute modeDomain : StringCapability[*];
        attribute radioScopeHzDomain : FrequencyRangeCapability[*];
        attribute spanHzDomain : HertzValueCapability[*];
        attribute referenceLevelDbDomain : RealCapability[*];
        attribute attenuationDbDomain : RealCapability[*];
        attribute averagingModeDomain : StringCapability[*];
        attribute speedDomain : StringCapability[*];
        attribute spectrumEnabledDomain : BooleanCapability[*];
        attribute receiverSelectionDomain : StringCapability[*];
        attribute dualScopeDomain : BooleanCapability[*];
        attribute fixedEdgePresetDomain : StringCapability[*];
        attribute onTransmitDomain : BooleanCapability[*];
        attribute centerReferenceDomain : StringCapability[*];
        attribute videoBandwidthDomain : StringCapability[*];
        attribute resolutionBandwidthDomain : StringCapability[*];
    }
    dependency scope_scopeId_metadata_owner from RadioScopeCapabilities::scopeIdDomain to RadioScopeSettings::scopeId;
    dependency scope_enabled_metadata_owner from RadioScopeCapabilities::enabledDomain to RadioScopeSettings::enabled;
    dependency scope_held_metadata_owner from RadioScopeCapabilities::heldDomain to RadioScopeSettings::held;
    dependency scope_mode_metadata_owner from RadioScopeCapabilities::modeDomain to RadioScopeSettings::mode;
    dependency scope_radioScopeHz_metadata_owner from RadioScopeCapabilities::radioScopeHzDomain to RadioScopeSettings::radioScopeHz;
    dependency scope_spanHz_metadata_owner from RadioScopeCapabilities::spanHzDomain to RadioScopeSettings::spanHz;
    dependency scope_referenceLevelDb_metadata_owner from RadioScopeCapabilities::referenceLevelDbDomain to RadioScopeSettings::referenceLevelDb;
    dependency scope_attenuationDb_metadata_owner from RadioScopeCapabilities::attenuationDbDomain to RadioScopeSettings::attenuationDb;
    dependency scope_averagingMode_metadata_owner from RadioScopeCapabilities::averagingModeDomain to RadioScopeSettings::averagingMode;
    dependency scope_speed_metadata_owner from RadioScopeCapabilities::speedDomain to RadioScopeSettings::speed;
    dependency scope_spectrumEnabled_metadata_owner from RadioScopeCapabilities::spectrumEnabledDomain to RadioScopeSettings::spectrumEnabled;
    dependency scope_receiverSelection_metadata_owner from RadioScopeCapabilities::receiverSelectionDomain to RadioScopeSettings::receiverSelection;
    dependency scope_dualScope_metadata_owner from RadioScopeCapabilities::dualScopeDomain to RadioScopeSettings::dualScope;
    dependency scope_fixedEdgePreset_metadata_owner from RadioScopeCapabilities::fixedEdgePresetDomain to RadioScopeSettings::fixedEdgePreset;
    dependency scope_onTransmit_metadata_owner from RadioScopeCapabilities::onTransmitDomain to RadioScopeSettings::onTransmit;
    dependency scope_centerReference_metadata_owner from RadioScopeCapabilities::centerReferenceDomain to RadioScopeSettings::centerReference;
    dependency scope_videoBandwidth_metadata_owner from RadioScopeCapabilities::videoBandwidthDomain to RadioScopeSettings::videoBandwidth;
    dependency scope_resolutionBandwidth_metadata_owner from RadioScopeCapabilities::resolutionBandwidthDomain to RadioScopeSettings::resolutionBandwidth;
    attribute def RadioMeters {
        attribute context : RadioPropertyContext;
        attribute evidence : RadioObservationEvidence[*];
        attribute signalStrengthDbm : Real[0..1];
        attribute signalStrengthDbRelativeS9 : Real[0..1];
        attribute standingWaveRatio : Real[0..1];
        attribute alcFraction : Real[0..1];
        attribute compressionDb : Real[0..1];
        attribute forwardPowerW : WattValue[0..1];
        attribute reflectedPowerW : WattValue[0..1];
        attribute drainCurrentA : AmpereValue[0..1];
        attribute supplyVoltageV : VoltValue[0..1];
        attribute temperatureCelsius : Real[0..1];
        attribute batteryFraction : Real[0..1];
        attribute carrierDetected : Boolean[0..1];
        attribute overflowDetected : Boolean[0..1];
        attribute signalStrengthRawCount : Integer[0..1];
        attribute outputPowerFraction : Real[0..1];
        doc /* All measurements are read-only. signalStrengthRawCount is physical
             A/D count, not protocol state. Relative-S9 dB and absolute dBm remain
             distinct; no calibration invented. Celsius fields are numerical Celsius,
             never Kelvin; fractions are dimensionless, not watts. */
    }
    attribute def RadioMetersCapabilities {
        attribute signalStrengthDbmDomain : ReadOnlyRealCapability[*];
        attribute signalStrengthDbRelativeS9Domain : ReadOnlyRealCapability[*];
        attribute standingWaveRatioDomain : ReadOnlyRealCapability[*];
        attribute alcFractionDomain : ReadOnlyRealCapability[*];
        attribute compressionDbDomain : ReadOnlyRealCapability[*];
        attribute forwardPowerWDomain : ReadOnlyWattValueCapability[*];
        attribute reflectedPowerWDomain : ReadOnlyWattValueCapability[*];
        attribute drainCurrentADomain : ReadOnlyAmpereValueCapability[*];
        attribute supplyVoltageVDomain : ReadOnlyVoltValueCapability[*];
        attribute temperatureCelsiusDomain : ReadOnlyRealCapability[*];
        attribute batteryFractionDomain : ReadOnlyRealCapability[*];
        attribute carrierDetectedDomain : ReadOnlyBooleanCapability[*];
        attribute overflowDetectedDomain : ReadOnlyBooleanCapability[*];
        attribute signalStrengthRawCountDomain : ReadOnlyIntegerCapability[*];
        attribute outputPowerFractionDomain : ReadOnlyRealCapability[*];
    }
    dependency meters_signalStrengthDbm_metadata_owner from RadioMetersCapabilities::signalStrengthDbmDomain to RadioMeters::signalStrengthDbm;
    dependency meters_signalStrengthDbRelativeS9_metadata_owner from RadioMetersCapabilities::signalStrengthDbRelativeS9Domain to RadioMeters::signalStrengthDbRelativeS9;
    dependency meters_standingWaveRatio_metadata_owner from RadioMetersCapabilities::standingWaveRatioDomain to RadioMeters::standingWaveRatio;
    dependency meters_alcFraction_metadata_owner from RadioMetersCapabilities::alcFractionDomain to RadioMeters::alcFraction;
    dependency meters_compressionDb_metadata_owner from RadioMetersCapabilities::compressionDbDomain to RadioMeters::compressionDb;
    dependency meters_forwardPowerW_metadata_owner from RadioMetersCapabilities::forwardPowerWDomain to RadioMeters::forwardPowerW;
    dependency meters_reflectedPowerW_metadata_owner from RadioMetersCapabilities::reflectedPowerWDomain to RadioMeters::reflectedPowerW;
    dependency meters_drainCurrentA_metadata_owner from RadioMetersCapabilities::drainCurrentADomain to RadioMeters::drainCurrentA;
    dependency meters_supplyVoltageV_metadata_owner from RadioMetersCapabilities::supplyVoltageVDomain to RadioMeters::supplyVoltageV;
    dependency meters_temperatureCelsius_metadata_owner from RadioMetersCapabilities::temperatureCelsiusDomain to RadioMeters::temperatureCelsius;
    dependency meters_batteryFraction_metadata_owner from RadioMetersCapabilities::batteryFractionDomain to RadioMeters::batteryFraction;
    dependency meters_carrierDetected_metadata_owner from RadioMetersCapabilities::carrierDetectedDomain to RadioMeters::carrierDetected;
    dependency meters_overflowDetected_metadata_owner from RadioMetersCapabilities::overflowDetectedDomain to RadioMeters::overflowDetected;
    dependency meters_signalStrengthRawCount_metadata_owner from RadioMetersCapabilities::signalStrengthRawCountDomain to RadioMeters::signalStrengthRawCount;
    dependency meters_outputPowerFraction_metadata_owner from RadioMetersCapabilities::outputPowerFractionDomain to RadioMeters::outputPowerFraction;
    attribute def RadioFrontPanelValues {
        attribute context : RadioPropertyContext;
        attribute evidence : RadioObservationEvidence[*];
        attribute announcement : String[0..1];
        attribute autoPowerOffMinutes : MinutesValue[0..1];
        attribute lcdBrightnessFraction : Real[0..1];
        attribute keyBeep : Boolean[0..1];
        attribute clockSecondsAfterMidnight : SecondsValue[0..1];
        attribute screenSaverTimeout : Real[0..1];
        attribute selectedMeter : String[0..1];
        attribute transmitMeter : String[0..1];
        attribute scramblerEnabled : Boolean[0..1];
        attribute transceiveEnabled : Boolean[0..1];
        attribute rfSquelchKnobRole : String[0..1];
        attribute memoryNameDisplay : Boolean[0..1];
        attribute firmwareIdentity : String[0..1];
        attribute displayColor : String[0..1];
        attribute displayUnits : String[0..1];
        attribute microphoneKeyAssignment : String[0..1];
        attribute tuningKeyAssignment : String[0..1];
    }
    attribute def RadioFrontPanelCapabilities {
        attribute announcementDomain : StringCapability[*];
        attribute autoPowerOffMinutesDomain : MinutesValueCapability[*];
        attribute lcdBrightnessFractionDomain : RealCapability[*];
        attribute keyBeepDomain : BooleanCapability[*];
        attribute clockSecondsAfterMidnightDomain : SecondsValueCapability[*];
        attribute screenSaverTimeoutDomain : RealCapability[*];
        attribute selectedMeterDomain : StringCapability[*];
        attribute transmitMeterDomain : StringCapability[*];
        attribute scramblerEnabledDomain : BooleanCapability[*];
        attribute transceiveEnabledDomain : BooleanCapability[*];
        attribute rfSquelchKnobRoleDomain : StringCapability[*];
        attribute memoryNameDisplayDomain : BooleanCapability[*];
        attribute firmwareIdentityDomain : ReadOnlyStringCapability[*];
        attribute displayColorDomain : StringCapability[*];
        attribute displayUnitsDomain : StringCapability[*];
        attribute microphoneKeyAssignmentDomain : StringCapability[*];
        attribute tuningKeyAssignmentDomain : StringCapability[*];
        doc /* KEYLIGHT has contradictory Boolean prose/float generic representation
             in pinned source: observed button-light type remains unresolved; no fake value. */
    }
    dependency frontPanel_announcement_metadata_owner from RadioFrontPanelCapabilities::announcementDomain to RadioFrontPanelValues::announcement;
    dependency frontPanel_autoPowerOffMinutes_metadata_owner from RadioFrontPanelCapabilities::autoPowerOffMinutesDomain to RadioFrontPanelValues::autoPowerOffMinutes;
    dependency frontPanel_lcdBrightnessFraction_metadata_owner from RadioFrontPanelCapabilities::lcdBrightnessFractionDomain to RadioFrontPanelValues::lcdBrightnessFraction;
    dependency frontPanel_keyBeep_metadata_owner from RadioFrontPanelCapabilities::keyBeepDomain to RadioFrontPanelValues::keyBeep;
    dependency frontPanel_clockSecondsAfterMidnight_metadata_owner from RadioFrontPanelCapabilities::clockSecondsAfterMidnightDomain to RadioFrontPanelValues::clockSecondsAfterMidnight;
    dependency frontPanel_screenSaverTimeout_metadata_owner from RadioFrontPanelCapabilities::screenSaverTimeoutDomain to RadioFrontPanelValues::screenSaverTimeout;
    dependency frontPanel_selectedMeter_metadata_owner from RadioFrontPanelCapabilities::selectedMeterDomain to RadioFrontPanelValues::selectedMeter;
    dependency frontPanel_transmitMeter_metadata_owner from RadioFrontPanelCapabilities::transmitMeterDomain to RadioFrontPanelValues::transmitMeter;
    dependency frontPanel_scramblerEnabled_metadata_owner from RadioFrontPanelCapabilities::scramblerEnabledDomain to RadioFrontPanelValues::scramblerEnabled;
    dependency frontPanel_transceiveEnabled_metadata_owner from RadioFrontPanelCapabilities::transceiveEnabledDomain to RadioFrontPanelValues::transceiveEnabled;
    dependency frontPanel_rfSquelchKnobRole_metadata_owner from RadioFrontPanelCapabilities::rfSquelchKnobRoleDomain to RadioFrontPanelValues::rfSquelchKnobRole;
    dependency frontPanel_memoryNameDisplay_metadata_owner from RadioFrontPanelCapabilities::memoryNameDisplayDomain to RadioFrontPanelValues::memoryNameDisplay;
    dependency frontPanel_firmwareIdentity_metadata_owner from RadioFrontPanelCapabilities::firmwareIdentityDomain to RadioFrontPanelValues::firmwareIdentity;
    dependency frontPanel_displayColor_metadata_owner from RadioFrontPanelCapabilities::displayColorDomain to RadioFrontPanelValues::displayColor;
    dependency frontPanel_displayUnits_metadata_owner from RadioFrontPanelCapabilities::displayUnitsDomain to RadioFrontPanelValues::displayUnits;
    dependency frontPanel_microphoneKeyAssignment_metadata_owner from RadioFrontPanelCapabilities::microphoneKeyAssignmentDomain to RadioFrontPanelValues::microphoneKeyAssignment;
    dependency frontPanel_tuningKeyAssignment_metadata_owner from RadioFrontPanelCapabilities::tuningKeyAssignmentDomain to RadioFrontPanelValues::tuningKeyAssignment;
    attribute def RadioScanningValues {
        attribute context : RadioPropertyContext;
        attribute evidence : RadioObservationEvidence[*];
        attribute voiceScanEnabled : Boolean[0..1];
        attribute autoResume : Boolean[0..1];
        attribute searchWindow : String[0..1];
        attribute priorityFrequencyHz : HertzValue[0..1];
    }
    attribute def RadioScanningCapabilities {
        attribute voiceScanEnabledDomain : BooleanCapability[*];
        attribute autoResumeDomain : BooleanCapability[*];
        attribute searchWindowDomain : StringCapability[*];
        attribute priorityFrequencyHzDomain : HertzValueCapability[*];
    }
    dependency scanning_voiceScanEnabled_metadata_owner from RadioScanningCapabilities::voiceScanEnabledDomain to RadioScanningValues::voiceScanEnabled;
    dependency scanning_autoResume_metadata_owner from RadioScanningCapabilities::autoResumeDomain to RadioScanningValues::autoResume;
    dependency scanning_searchWindow_metadata_owner from RadioScanningCapabilities::searchWindowDomain to RadioScanningValues::searchWindow;
    dependency scanning_priorityFrequencyHz_metadata_owner from RadioScanningCapabilities::priorityFrequencyHzDomain to RadioScanningValues::priorityFrequencyHz;
    attribute def RadioDigitalValues {
        attribute context : RadioPropertyContext;
        attribute evidence : RadioObservationEvidence[*];
        attribute dstarSquelchMode : String[0..1];
        attribute dstarCode : String[0..1];
        attribute ownCallsign : String[0..1];
        attribute transmitCallsign : String[0..1];
        attribute receiveCallsign : String[0..1];
        attribute transmitMessage : String[0..1];
        attribute receiveMessage : String[0..1];
        attribute gpsMessage : String[0..1];
        attribute dataBand : String[0..1];
        attribute aprsModemEnabled : Boolean[0..1];
        attribute aprsBeaconMode : String[0..1];
        attribute aprsReceiveFilter : String[0..1];
        attribute smartBeaconMode : String[0..1];
        attribute gpsEnabled : Boolean[0..1];
        attribute positionLatitudeDegrees : Real[0..1];
        attribute positionLongitudeDegrees : Real[0..1];
    }
    attribute def RadioDigitalCapabilities {
        attribute dstarSquelchModeDomain : StringCapability[*];
        attribute dstarCodeDomain : StringCapability[*];
        attribute ownCallsignDomain : StringCapability[*];
        attribute transmitCallsignDomain : StringCapability[*];
        attribute receiveCallsignDomain : ReadOnlyStringCapability[*];
        attribute transmitMessageDomain : StringCapability[*];
        attribute receiveMessageDomain : ReadOnlyStringCapability[*];
        attribute gpsMessageDomain : StringCapability[*];
        attribute dataBandDomain : StringCapability[*];
        attribute aprsModemEnabledDomain : BooleanCapability[*];
        attribute aprsBeaconModeDomain : StringCapability[*];
        attribute aprsReceiveFilterDomain : StringCapability[*];
        attribute smartBeaconModeDomain : StringCapability[*];
        attribute gpsEnabledDomain : BooleanCapability[*];
        attribute positionLatitudeDegreesDomain : RealCapability[*];
        attribute positionLongitudeDegreesDomain : RealCapability[*];
    }
    dependency digital_dstarSquelchMode_metadata_owner from RadioDigitalCapabilities::dstarSquelchModeDomain to RadioDigitalValues::dstarSquelchMode;
    dependency digital_dstarCode_metadata_owner from RadioDigitalCapabilities::dstarCodeDomain to RadioDigitalValues::dstarCode;
    dependency digital_ownCallsign_metadata_owner from RadioDigitalCapabilities::ownCallsignDomain to RadioDigitalValues::ownCallsign;
    dependency digital_transmitCallsign_metadata_owner from RadioDigitalCapabilities::transmitCallsignDomain to RadioDigitalValues::transmitCallsign;
    dependency digital_receiveCallsign_metadata_owner from RadioDigitalCapabilities::receiveCallsignDomain to RadioDigitalValues::receiveCallsign;
    dependency digital_transmitMessage_metadata_owner from RadioDigitalCapabilities::transmitMessageDomain to RadioDigitalValues::transmitMessage;
    dependency digital_receiveMessage_metadata_owner from RadioDigitalCapabilities::receiveMessageDomain to RadioDigitalValues::receiveMessage;
    dependency digital_gpsMessage_metadata_owner from RadioDigitalCapabilities::gpsMessageDomain to RadioDigitalValues::gpsMessage;
    dependency digital_dataBand_metadata_owner from RadioDigitalCapabilities::dataBandDomain to RadioDigitalValues::dataBand;
    dependency digital_aprsModemEnabled_metadata_owner from RadioDigitalCapabilities::aprsModemEnabledDomain to RadioDigitalValues::aprsModemEnabled;
    dependency digital_aprsBeaconMode_metadata_owner from RadioDigitalCapabilities::aprsBeaconModeDomain to RadioDigitalValues::aprsBeaconMode;
    dependency digital_aprsReceiveFilter_metadata_owner from RadioDigitalCapabilities::aprsReceiveFilterDomain to RadioDigitalValues::aprsReceiveFilter;
    dependency digital_smartBeaconMode_metadata_owner from RadioDigitalCapabilities::smartBeaconModeDomain to RadioDigitalValues::smartBeaconMode;
    dependency digital_gpsEnabled_metadata_owner from RadioDigitalCapabilities::gpsEnabledDomain to RadioDigitalValues::gpsEnabled;
    dependency digital_positionLatitudeDegrees_metadata_owner from RadioDigitalCapabilities::positionLatitudeDegreesDomain to RadioDigitalValues::positionLatitudeDegrees;
    dependency digital_positionLongitudeDegrees_metadata_owner from RadioDigitalCapabilities::positionLongitudeDegreesDomain to RadioDigitalValues::positionLongitudeDegrees;
    attribute def RadioTuningValues { attribute vfos : RadioVfoValues[*]; }
    attribute def RadioSpectrum {
        attribute scopeId : String; attribute frequenciesHz : HertzValue[*];
        attribute levels : Real[*]; attribute levelUnit : String;
        doc /* Physical spectrum samples paired by position, radio-supplied level unit;
             no universal calibration or transport buffer/frame layout. */
    }
    enum def MemoryChannelType {
        enum regular; enum scanEdge; enum call; enum pad; enum satellite;
        enum vfoBand; enum priority; enum voice; enum morse; enum split;
    }
    enum def MemoryChannelFlag { enum skipped; enum data; enum prioritySkip; }
    attribute def MemoryStorageMemberCapabilities :> ControlAccessDescription {
        attribute member : String;
        doc /* Member is an exact StoredMemoryChannel attribute name, or a named nested
             storedFunctions/storedLevels property. Storage access is not live command
             permission; no raw function masks, level arrays or extension tokens. */
    }
    attribute def MemoryChannelRange {
        attribute firstChannel : Integer; attribute lastChannel : Integer;
        attribute channelType : MemoryChannelType;
        attribute members : MemoryStorageMemberCapabilities[*];
    }
    attribute def MemoryCapacity {
        attribute bankCount : Integer[0..1]; attribute descriptionLength : Integer[0..1];
        attribute ranges : MemoryChannelRange[*];
        doc /* Unknown capacity is absent. A range/type and its storage members stay
             associated. Voice/Morse memory does not imply observable audio/text payload. */
    }
    attribute def StoredMemoryChannel {
        attribute number : Integer; attribute bank : Integer[0..1];
        attribute channelType : MemoryChannelType[0..1];
        attribute vfo : VfoSelection[0..1]; attribute antennas : AntennaSelection[0..1];
        attribute receiveFrequencyHz : HertzValue[0..1]; attribute receiveMode : String[0..1];
        attribute receiveFilterHz : HertzValue[0..1]; attribute transmitFrequencyHz : HertzValue[0..1];
        attribute transmitMode : String[0..1]; attribute transmitFilterHz : HertzValue[0..1];
        attribute split : SplitSelection[0..1]; attribute repeaterShift : RepeaterShift[0..1];
        attribute repeaterOffsetHz : HertzValue[0..1]; attribute tuningStepHz : HertzValue[0..1];
        attribute ritOffsetHz : HertzValue[0..1]; attribute xitOffsetHz : HertzValue[0..1];
        attribute storedFunctions : StoredRadioFunctions[0..1];
        attribute storedLevels : StoredRadioLevels[0..1];
        attribute ctcssToneHz : HertzValue[0..1]; attribute ctcssSquelchToneHz : HertzValue[0..1];
        attribute dcsCode : String[0..1]; attribute dcsSquelchCode : String[0..1];
        attribute scanGroup : Integer[0..1]; attribute flags : MemoryChannelFlag[*];
        attribute description : String[0..1]; attribute extensionSettings : StoredRadioExtensions[0..1];
        attribute tag : String[0..1];
        doc /* Observed stored contents, not operating values. Split includes transmitVfo.
             Optional members reflect storage capability and actual returned evidence.
             Scan-edge entries need not contain ordinary channel members; flag combinations
             are not universally supported. DCS preserves leading zeroes. */
    }
    attribute def StoredRadioFunctions {
        attribute tuning : RadioVfoValues[0..1]; attribute receiver : RadioReceiverSettings[0..1];
        attribute transmitter : RadioTransmitterSettings[0..1]; attribute audio : RadioAudioSettings[0..1];
        attribute keyer : RadioKeyerSettings[0..1]; attribute tones : RadioToneSettings[0..1];
        doc /* Only Boolean/named function members explicitly supported for storage;
             these are stored contents, never another current operating context. */
        attribute scope : RadioScopeSettings[0..1];
        attribute meters : RadioMeters[0..1];
        attribute frontPanel : RadioFrontPanelValues[0..1];
        attribute scanning : RadioScanningValues[0..1];
        attribute digital : RadioDigitalValues[0..1];
        doc /* Shared complete named vocabulary; only members evidenced for this
             storage family and channel type may be present. Functions, levels and
             extensions are separate supported storage subsets, never independent
             current values or permission to write read-only operating measurements. */
    }
    attribute def StoredRadioLevels {
        attribute tuning : RadioVfoValues[0..1]; attribute receiver : RadioReceiverSettings[0..1];
        attribute transmitter : RadioTransmitterSettings[0..1]; attribute audio : RadioAudioSettings[0..1];
        attribute keyer : RadioKeyerSettings[0..1]; attribute scope : RadioScopeSettings[0..1];
        doc /* Only separately supported numeric/named level members for storage. */
        attribute tones : RadioToneSettings[0..1];
        attribute meters : RadioMeters[0..1];
        attribute frontPanel : RadioFrontPanelValues[0..1];
        attribute scanning : RadioScanningValues[0..1];
        attribute digital : RadioDigitalValues[0..1];
        doc /* Shared complete named vocabulary; only members evidenced for this
             storage family and channel type may be present. Functions, levels and
             extensions are separate supported storage subsets, never independent
             current values or permission to write read-only operating measurements. */
    }
    attribute def StoredRadioExtensions {
        attribute receiver : RadioReceiverSettings[0..1]; attribute transmitter : RadioTransmitterSettings[0..1];
        attribute audio : RadioAudioSettings[0..1]; attribute digital : RadioDigitalValues[0..1];
        doc /* Resolved named extension meanings only; no token-number/value arrays. */
        attribute tuning : RadioVfoValues[0..1];
        attribute keyer : RadioKeyerSettings[0..1];
        attribute tones : RadioToneSettings[0..1];
        attribute scope : RadioScopeSettings[0..1];
        attribute meters : RadioMeters[0..1];
        attribute frontPanel : RadioFrontPanelValues[0..1];
        attribute scanning : RadioScanningValues[0..1];
        doc /* Shared complete named vocabulary; only members evidenced for this
             storage family and channel type may be present. Functions, levels and
             extensions are separate supported storage subsets, never independent
             current values or permission to write read-only operating measurements. */
    }
    attribute def RadioMemoryValues {
        attribute selectedChannel : Integer[0..1]; attribute channels : StoredMemoryChannel[*];
        attribute context : RadioPropertyContext; attribute evidence : RadioObservationEvidence[*];
        doc /* Selected channel is separate from capacity and contents. No current bank
             read API is inferred from set-bank or stored bank-number support. */
    }
    attribute def OperationAvailability {
        attribute context : RadioPropertyContext; attribute supported : Boolean[0..1];
        doc /* Capability description of an action at the existing RadioControl boundary,
             not Boolean current state or execution permission. Operations use RadioAuthority;
             future workflow implementation remains planned and separately accepted. */
    }
    attribute def RadioMemoryCapabilities {
        attribute capacity : MemoryCapacity[0..1];
        attribute selectedChannel : IntegerCapability[*];
        attribute selectBank : OperationAvailability[*]; attribute readChannel : OperationAvailability[*];
        attribute writeChannel : OperationAvailability[*]; attribute sendVoiceMemory : OperationAvailability[*];
    }
    attribute def RadioOperationCapabilities {
        attribute sendMorse : OperationAvailability[*]; attribute clearRit : OperationAvailability[*];
        attribute scan : OperationAvailability[*]; attribute stopScan : OperationAvailability[*];
        attribute moveTuningAntenna : OperationAvailability[*]; attribute abort : OperationAvailability[*];
    }
    attribute def RadioCapabilities {
        attribute tuning : RadioTuningCapabilities[0..1];
        attribute transmitter : RadioTransmitterCapabilities[0..1];
        attribute receiver : RadioReceiverCapabilities[0..1];
        attribute audio : RadioAudioCapabilities[0..1];
        attribute keyer : RadioKeyerCapabilities[0..1];
        attribute tones : RadioTonesCapabilities[0..1];
        attribute scope : RadioScopeCapabilities[0..1];
        attribute meters : RadioMetersCapabilities[0..1];
        attribute frontPanel : RadioFrontPanelCapabilities[0..1];
        attribute scanning : RadioScanningCapabilities[0..1];
        attribute digital : RadioDigitalCapabilities[0..1];
        attribute memories : RadioMemoryCapabilities[0..1];
        attribute operations : RadioOperationCapabilities[0..1];
        doc /* Description only: no current or requested settings. Every typed feature
             is linked by native dependency to its single owning value feature below.
             This replaces detached global choice lists: e.g receiveRangesHz and transmitRangesHz
             become tuning.frequencyDomain and tuning.transmitFrequencyHzDomain contextual domains;
             rfModes/filterNames/widths/steps/antenna choices attach their named owners.
             Model/firmware/option evidence must not imply current adapter implementation.
             VOXDELAY tenths of seconds convert exactly to seconds; source granularity
             is scaled with that conversion, never guessed. Hamlib gran all-zero means
             undefined; continuous markers are domain evidence, not literal zero choices.
             Continuous/unknown domains are not literal zero choices or universal bounds. */
    }
    dependency memorySelectionMetadataOwner from RadioMemoryCapabilities::selectedChannel to RadioMemoryValues::selectedChannel;
    attribute def RadioTuningSettings :> RadioVfoValues {
        doc /* Temporary request/outcome projection. frequency is the same property as
             Radio.tuning.vfos[*].frequency; context selects its VFO. No persistent requested
             frequency property exists. All supplied fields are subject to access/authority. */
    }
    attribute def RadioSettings {
        attribute tuning : RadioTuningSettings[0..1];
        attribute transmitter : RadioTransmitterSettings[0..1];
        attribute receiver : RadioReceiverSettings[0..1];
        attribute audio : RadioAudioSettings[0..1];
        attribute keyer : RadioKeyerSettings[0..1];
        attribute tones : RadioToneSettings[0..1];
        attribute scope : RadioScopeSettings[0..1];
        attribute frontPanel : RadioFrontPanelValues[0..1];
        attribute scanning : RadioScanningValues[0..1];
        attribute digital : RadioDigitalValues[0..1];
        doc /* Projection ownership: each member maps by identical name to
             Radio.<group>[*].<member> (audio maps to audioControls); tuning maps to Radio.tuning.vfos[*].<member>.
             Scope radioScopeHz is physical range, not filter/browser span. This is a
             temporary operation input/output, not stored or independently authoritative.
             Absent request members mean no change. Read-only/unsupported/context-invalid
             members MUST be rejected before activity. Meters/spectrum are never inputs. */
    }
    attribute def RadioState {
        attribute controls : RadioSettings[0..1]; attribute meters : RadioMeters[*];
        attribute spectrum : RadioSpectrum[*]; attribute memories : RadioMemoryValues[0..1];
        doc /* Temporary query/result projection of the SAME Radio group values/context;
             no second current-value authority. controls uses exact Settings ownership map.
             Meter/spectrum/memory members map by identical names to owning Radio groups.
             No data returned means unknown; failure cannot refresh retained observations. */
    }
    constraint def FrequencyWithinApplicableRange {
        in attribute requested : HertzValue;
        in attribute lower : HertzValue;
        in attribute upper : HertzValue;
        doc /* Apply only after selecting an applicable conditional frequency domain
             for the SAME model/VFO/mode/filter/antenna/region/direction context. Multiple
             alternatives are OR, not intersection. This checks requested frequency,
             not a claim every observation must lie in currently known ranges. */
        requested >= lower and requested <= upper
    }
    action def QueryRadioFrequency {
        in ref part radio : Radio;
        in attribute context : RadioPropertyContext;
        out attribute status : RadioResultStatus;
        out attribute actualHz : HertzValue[0..1];
        doc /* Planned action contract at RadioControl through the existing binding and
             RadioAuthority. Query the single radio.tuning.vfos[*].frequency selected by
             context. actualHz is a temporary observation of that same property only on
             independent successful measurement; missing/failed reads cannot fabricate a
             value or refresh stale evidence. No radio or audio implementation is claimed. */
    }
    action def SetRadioFrequency {
        in ref part radio : Radio;
        in attribute context : RadioPropertyContext;
        in attribute requestedHz : HertzValue;
        out attribute status : RadioResultStatus;
        out attribute actualHz : HertzValue[0..1];
        doc /* Planned action contract. The temporary requestedHz is intent for the SAME
             radio.tuning.vfos[*].frequency. Match contextual support/writability/domain,
             including FrequencyWithinApplicableRange, then admit through RadioAuthority
             and existing safety/resource guards before any activity. ACK alone is not
             confirmation: independent readback must agree. Failure/mismatch reports only
             actual measured state, never copies requestedHz into frequency, invents rollback
             or implies retained state was freshly read. No retry/replay permission added. */
    }
    action def QueryRadioProperties {
        in ref part radio : Radio;
        in attribute context : RadioPropertyContext;
        out item result : RadioStateOutcome;
        doc /* Planned typed query contract; same ControlOutcome request/resource identity,
             authority and contextual ownership mapping as ReadRadioState. Optional result
             fields express available measurements, not fabricated complete snapshots. */
    }
    action def ApplyRadioProperties {
        in ref part radio : Radio;
        in attribute context : RadioPropertyContext;
        in attribute requested : RadioSettings;
        out item result : RadioSettingsOutcome;
        doc /* Planned typed apply contract through existing ApplyRadioSettings boundary.
             The supplied-member mask is the optional typed request fields; no raw keyword
             command dispatch. Reject unsupported/read-only/unknown-access/context-invalid
             requests before activity. Meters/spectrum have no writable request member.
             Confirmation/failure/current-state rules are those of SetRadioFrequency and
             the owning WstxRadioIO/WstxProductScope safety and authority contracts. */
    }
    dependency frequencyQueryOwner from QueryRadioFrequency to RadioVfoValues::frequency;
    dependency frequencySetOwner from SetRadioFrequency to RadioVfoValues::frequency;
    dependency frequencyConstraintOwner from FrequencyWithinApplicableRange to RadioTuningCapabilities::frequencyDomain;
    doc /* Source coverage boundary: Hamlib075b78cb0560e892c81bc73890d633cc11f23f59,
         include/hamlib/rig.h standard114entries, public channel28members/channel_cap and
         contextual frequency/filter/step lists. Known named extension meanings in Icom,
         Kenwood, Yaesu, Optoscan, FiFiSDR and SimpleCAT map to groups above. Their source
         tables describe possible meanings, not support for every model. Icom scope VBW/RBW
         are named bandwidth choices without evidenced Hz; driveGainLevel is a model
         scale (source0..255), not normalized without a documented conversion. Optoscan
         CTCSS/DCS active flags do not imply decoded tone frequency or DCS code. Numeric vendor
         codes with undecoded semantics remain unresolved: FTX1 APRS receive filters,
         smart-beacon thresholds, GPS/location/display/color/tuning-key options, charger,
         dither, DSP/EQ stages and battery-conditioned max-power controls require source
         decoding before concrete choices/units. Icom binary call/status/GPS content needs
         decoding before structured payload semantics. APF offset/contour width retain
         model scales where physical units are not established. KEYLIGHT observation type
         is unresolved (Boolean prose conflicts generic float), not guessed. No claim of
         complete vendor-extension coverage, no raw vendor/API/driver inventory. Action-like
         SEND_MORSE/SEND_VOICE_MEM are operation availability, never observed Boolean state.
         Future actions/workflows need implementation/acceptance; this model is no verdict. */
}
