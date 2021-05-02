DECLARE GLOBAL EDLMODE TO 1.
DECLARE GLOBAL EDLCOMP TO FALSE.

DECLARE GLOBAL CRUISESTAGE TO FALSE.
DECLARE GLOBAL PARACHUTE TO FALSE.
DECLARE GLOBAL HEATSHIELD TO FALSE.
DECLARE GLOBAL BACKSHELL TO FALSE.
DECLARE GLOBAL ENGINESTART TO FALSE.
DECLARE GLOBAL CONSTVELOCITY TO FALSE.

DECLARE GLOBAL REALALT TO 400000.
DECLARE GLOBAL TWR TO 1.0.
DECLARE GLOBAL THRUSTVAL TO 0.0.
DECLARE GLOBAL G TO 1.0.

DECLARE GLOBAL FUNCTION MODECHANGE {
    PARAMETER MODE IS EDLMODE + 1.
    SET EDLMODE TO MODE.
    PRINT EDLMODE AT(20,5).
}

DECLARE GLOBAL FUNCTION PRINTSTATE {
    PARAMETER STATE.
    PRINT "                   " AT(20,6).
    PRINT STATE AT(20,6).
}

LOCK THROTTLE TO THRUSTVAL.
LOCK STEERING TO SRFRETROGRADE.

RCS ON.
SAS OFF.

CLEARSCREEN.

PRINT "MODE: " AT(10, 5).
PRINT "STATE: " AT(10, 6).
PRINT "ALT: " AT(10, 7).
PRINT "VEL: " AT(10,8).

PRINT "m" AT(35,7).
PRINT "m/s" AT(35,8).
PRINTSTATE("WAIT FOR EDL").

UNTIL EDLCOMP {

    SET G TO BODY:MU / ((ALTITUDE + BODY:RADIUS)^2).

    IF (ALT:RADAR <= 1500) {
        SET REALALT TO ALT:RADAR.
    } ELSE {
        SET REALALT TO ALTITUDE - SHIP:GEOPOSITION:TERRAINHEIGHT.
    }

    PRINT EDLMODE AT(20,5).
    PRINT "              " AT(20,7).
    PRINT ROUND(REALALT, 2) AT(20,7).
    PRINT "              " AT(20,8).
    PRINT ROUND(ABS(SHIP:AIRSPEED),2) AT(20,8).
    IF EDLMODE = 1 {
        IF REALALT < 190000 AND NOT CRUISESTAGE {
            SET CRUISESTAGE TO TRUE.
            STAGE.
            PRINTSTATE("WAIT FOR ENTRY").
            MODECHANGE().
        }
    }
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

    IF EDLMODE = 3 {
        IF REALALT < 10000 AND REALALT > 8000 {
            PRINTSTATE("WAIT FOR PARACHUTE").
        }
        IF REALALT < 8000 AND SHIP:AIRSPEED < 750 AND NOT PARACHUTE {
            SET PARACHUTE TO TRUE.
            PRINTSTATE("PARACHUTE DEPLOY").
            STAGE.
        }
        IF SHIP:AIRSPEED < 200 AND NOT HEATSHIELD {
            SET HEATSHIELD TO TRUE.
            PRINTSTATE("HEATSHIELD SEP").
            STAGE.
        }
        IF SHIP:AIRSPEED < 100 AND HEATSHIELD {
            PRINTSTATE("WAIT FOR SEP").
            MODECHANGE().
        }
    }

    IF EDLMODE = 4 {

        IF REALALT < 1500 AND NOT BACKSHELL {
            GEAR ON.
        }

        IF REALALT < 1400 AND NOT BACKSHELL {
            PRINTSTATE("BACKSHELL SEP").
            SET BACKSHELL TO TRUE.
            STAGE.
        }

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

            SET THRUSTVAL TO TWR * SHIP:MASS * G / SHIP:AVAILABLETHRUST.
            LOCK THROTTLE TO THRUSTVAL.
            
            IF REALALT < 950 {
                IF REALALT > 80 {
                    IF SHIP:AIRSPEED > 20 {
                        SET TWR TO 2*(1/(1+CONSTANT:E^(-0.5*(SHIP:AIRSPEED-20)))).
                    } ELSE {
                        SET TWR TO 0.9.
                    }
                    PRINTSTATE("VERTICAL DESCENT").
                    LOCK STEERING TO SRFRETROGRADE.
                } ELSE {
                    IF SHIP:AIRSPEED > 1 {
                        SET TWR TO 2*(1/(1+CONSTANT:E^(-0.5*(SHIP:AIRSPEED-1)))).
                        IF NOT CONSTVELOCITY {
                            PRINTSTATE("PERFORMING SLOWDOWN").
                        }
                    } ELSE {
                        IF SHIP:GROUNDSPEED > 0.2 {
                            LOCK STEERING TO SRFRETROGRADE.
                        } ELSE {
                            LOCK STEERING TO HEADING(0,90).
                        }
                        IF SHIP:VERTICALSPEED <= 1 {
                            SET TWR TO 0.9.
                        }
                        PRINTSTATE("CONST VELOCITY").
                        SET CONSTVELOCITY TO TRUE.
                    }
                    IF REALALT < 1.0 {
                        SET TWR TO 0.0.
                        IF SHIP:AIRSPEED <= 0.5 {
                            PRINTSTATE("EDL COMPLETE").
                            SET EDLCOMP TO TRUE.
                        }
                    }
                }
            }
        }
    }
}
