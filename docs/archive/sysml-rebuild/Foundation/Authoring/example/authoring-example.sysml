package WritingExample {
    private import ScalarValues::*;
    private import ModelNotes::*;
    private import ModelBindings::*;

    part def Panel;
    part def Controller {
        @ImplementedIn { module = "src/controller"; }
        @DetailTests { tests = "src/controller/tests"; covers = "sampling and filtering"; }
        @NotStated { what = "how the controller obtains the tank level"; }

        attribute limits : TankLimits;
        action stopPump : StopPump;
    }
    part def Plant {
        part panel : Panel;
        part controller : Controller;
    }
    part plant : Plant;

    attribute def TankLimits {
        doc /* The tank's limits, which several functions of the controller share. */
        attribute fullPercent : Integer = 95;
        attribute samplePeriodSeconds : Integer = 2;
    }

    action def StopPump {
        doc /* Stops the pump when the level reaches TankLimits::fullPercent, and leaves a
             stopped pump stopped until the operator starts it again. */
        in levelPercent : Integer;
        out pumpRunning : Boolean;
    }

    requirement <'CL-012-03'> stopWhenFull {
        doc /* The controller MUST stop the pump when the tank level reaches
             TankLimits::fullPercent. */
        subject controller : Controller;
        @Status { build = BuildState::built; }
    }
    satisfy stopWhenFull by plant.controller;
    dependency stopWhenFullUsesLimit from stopWhenFull to TankLimits::fullPercent;

    requirement <'CL-012-04'> showFull {
        doc /* The panel MUST show the tank as full and refuse Start while the
             controller reports a full tank. */
        subject panel : Panel;
        @Status { build = BuildState::planned; }
    }
    satisfy showFull by plant.panel;

    verification <'TC-012-005'> pumpStopsAtLimit {
        doc /* Shows that the pump stops at the limit and not before. This defines a
             case, not an execution result.
             Setup: a controller with a simulated level sensor.
             (a) Level just below the limit: the pump runs.
             (b) Level at the limit: the pump stops.
             (c) Level falls again: the pump stays stopped. */
        subject tested : Controller;
        objective { verify stopWhenFull; }
        @TestedBy { test = "src/controller/tests::pump_stops_at_limit"; }
        @Automation { run = AutomationState::automated; }
        attribute level : Integer = 2;
        attribute location : String = "isolated project test environment";
    }
}
