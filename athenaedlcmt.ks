// Mode / Stage Globals
DECLARE GLOBAL EDLMODE TO 1.
DECLARE GLOBAL EDLCOMP TO FALSE.

DECLARE GLOBAL CRUISESTAGE TO FALSE.
DECLARE GLOBAL PARACHUTE TO FALSE.
DECLARE GLOBAL HEATSHIELD TO FALSE.
DECLARE GLOBAL BACKSHELL TO FALSE.
DECLARE GLOBAL ENGINESTART TO FALSE.
DECLARE GLOBAL CONSTVELOCITY TO FALSE.
DECLARE GLOBAL CUTOFF TO FALSE.

// Flight Globals.
DECLARE GLOBAL REALALT TO 400000.
DECLARE GLOBAL TWR TO 1.0.
DECLARE GLOBAL THRUSTVAL TO 0.0.
DECLARE GLOBAL G TO 1.0.

// Flight mode change
DECLARE GLOBAL FUNCTION MODECHANGE {
    PARAMETER MODE IS EDLMODE + 1.
    SET EDLMODE TO MODE.
    PRINT EDLMODE AT(20,5).
}

// Flight state updater
DECLARE GLOBAL FUNCTION PRINTSTATE {
    PARAMETER STATE.
    PRINT "                   " AT(20,6).
    PRINT STATE AT(20,6).
}

// Engine throttle control
DECLARE GLOBAL FUNCTION SPEEDSET {
    PARAMETER SPEED.

    // Set TWR based on surface velocity and inputted speed.

    // Scale linearly changes precision of TWR depending on velocity. Lower precision for higher input speeds.
    SET OFFSET TO 0.2.
    SET SCALE TO 1/19*SPEED-59/38.
    SET TWR TO 2*(1/(1+CONSTANT:E^(SCALE*(SHIP:AIRSPEED-SPEED-OFFSET)))).

    // If velocity falls under input speed lower TWR to below 1.0.
    IF SHIP:AIRSPEED - SPEED < 0 {
        SET TWR TO 0.95.
    }
}

// Setup
LOCK THROTTLE TO THRUSTVAL.
LOCK STEERING TO SRFRETROGRADE.

RCS ON.
SAS OFF.

CLEARSCREEN.

// Screen overlay
PRINT "MODE: " AT(10, 5).
PRINT "STATE: " AT(10, 6).
PRINT "ALT: " AT(10, 7).
PRINT "VEL: " AT(10,8).

PRINT "m" AT(35,7).
PRINT "m/s" AT(35,8).
PRINTSTATE("WAIT FOR EDL").

// Flight loop
UNTIL EDLCOMP {

    // Update local gravitational acceleration every flight tick
    SET G TO BODY:MU / ((ALTITUDE + BODY:RADIUS)^2).

    // Switch to radar altitude once below 1500 meters, otherwise use terrain approximate.
    IF (ALT:RADAR <= 1500) {
        SET REALALT TO ALT:RADAR.
    } ELSE {
        SET REALALT TO ALTITUDE - SHIP:GEOPOSITION:TERRAINHEIGHT.
    }

    // Update flight state
    PRINT EDLMODE AT(20,5).
    PRINT "              " AT(20,7).
    PRINT ROUND(REALALT, 2) AT(20,7).
    PRINT "              " AT(20,8).
    PRINT ROUND(ABS(SHIP:AIRSPEED),2) AT(20,8).

    // Mode 1, ditch cruise stage once below 190 km above the surface
    IF EDLMODE = 1 {
        IF REALALT < 190000 AND NOT CRUISESTAGE {
            SET CRUISESTAGE TO TRUE.
            STAGE.
            PRINTSTATE("WAIT FOR ENTRY").
            MODECHANGE().
        }
    }

    // Mode 2, guide vehicle through the atmosphere until 20 km above the surface
    IF EDLMODE = 2 {
        IF REALALT < 125000 AND REALALT > 80000 {
            PRINTSTATE("ENTRY INTERFACE").
        }
        IF REALALT < 80000 AND REALALT > 20000 {
            PRINTSTATE("GUIDED ENTRY").
        }
        IF REALALT < 20000 {
            PRINTSTATE("SUFR").
            MODECHANGE().
        }
    }

    // Final unpowered descent mode.
    IF EDLMODE = 3 {
        IF REALALT < 10000 AND REALALT > 8000 {
            PRINTSTATE("WAIT FOR PARACHUTE").
        }

        // Once velocity below Mach 2 and altitude below 8 km trigger parachute deploy
        IF REALALT < 8000 AND SHIP:AIRSPEED < 750 AND NOT PARACHUTE {
            SET PARACHUTE TO TRUE.
            PRINTSTATE("PARACHUTE DEPLOY").
            STAGE.
        }

        // Once velocity drops below 200 m/s, ditch the heatshield if not done already.
        IF SHIP:AIRSPEED < 200 AND NOT HEATSHIELD {
            SET HEATSHIELD TO TRUE.
            PRINTSTATE("HEATSHIELD SEP").
            STAGE.
        }

        // Once airspeed is below 100 m/s, prepare for powered flight
        IF SHIP:AIRSPEED < 100 AND HEATSHIELD {
            PRINTSTATE("WAIT FOR SEP").
            MODECHANGE().
        }
    }

    // Powered descent/landing mode.
    IF EDLMODE = 4 {

        // Once below 1.5 km, deploy landing gear
        IF REALALT < 1500 AND NOT BACKSHELL {
            GEAR ON.
        }

        // At 1.4 km, transition to Radar for altitude info and separate from the backshell
        IF REALALT < 1400 AND NOT BACKSHELL {
            PRINTSTATE("BACKSHELL SEP").
            SET BACKSHELL TO TRUE.
            STAGE.
        }

        // Ignite landing motors and perform 60 degree divert manuever
        IF BACKSHELL AND NOT ENGINESTART {
            LOCK STEERING TO HEADING(0,60).

            IF REALALT < 1375 AND NOT ENGINESTART {
                PRINTSTATE("LANDING START").
                SET ENGINESTART TO TRUE.
                STAGE.
            }
        }
        IF ENGINESTART {
            IF REALALT > 950 AND REALALT < 1300 {
                PRINTSTATE("PERFORMING DIVERT").
            }

            // Lock throttle values to commanded TWR
            SET THRUSTVAL TO TWR * SHIP:MASS * G / SHIP:AVAILABLETHRUST.
            LOCK THROTTLE TO THRUSTVAL.
            
            // Landing logic
            IF REALALT < 950 {

                // Phase I landing sequence

                IF REALALT > 80 {

                    // In Phase I, decelerate to 20 m/s and hold
                    SPEEDSET(20).
                    PRINTSTATE("VERTICAL DESCENT").
                    IF SHIP:GROUNDSPEED > 0.1 {
                        LOCK STEERING TO SRFRETROGRADE.
                    } ELSE {
                        LOCK STEERING TO HEADING(0,90).
                    }
                } ELSE {

                    // Phase II landing sequence

                    // Decelerate to 1 m/s and hold if the vehicle isn't in final freefall
                    IF NOT CUTOFF {
                        SPEEDSET(1).
                        
                        IF NOT CONSTVELOCITY {
                            PRINTSTATE("PERFORMING SLOWDOWN").
                        }


                        // If horizontal velocity exceeds 0.2 m/s, point prograde. Otherwise maintain vertical orientation

                        IF SHIP:AIRSPEED < 1.1 {
                            PRINTSTATE("CONST VELOCITY").
                            SET CONSTVELOCITY TO TRUE.
                        }
                    }

                    // Once below 1 meter, cut engine power. Once speed drops below 50 cm/s, end EDL script
                    IF REALALT < 1.0 {
                        SET TWR TO 0.0.
                        SET CUTOFF TO TRUE.
                        PRINTSTATE("CUTOFF").

                        IF SHIP:AIRSPEED < 0.5 {
                            PRINTSTATE("EDL COMPLETE").
                            RCS OFF.
                            SET EDLCOMP TO TRUE.
                        }
                    }
                }
            }
        }
    }
}
