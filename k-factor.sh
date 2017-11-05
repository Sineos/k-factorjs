#!/bin/sh

# Test generator for K-Factor calibration
# By Andre Ruiz (aka Token47), andre (dot) ruiz (at) gmail (dot) com


set -u

## SETTINGS ##
## Change to match your needs ##

FILAMENT_DIAMETER="1.75" # in mm
NOZZLE_DIAMETER="0.4" # in mm
NOZZLE_TEMP="205" # C degrees
BED_TEMP="60" # C degrees
SLOW_SPEED="1200" # mm/min
FAST_SPEED="4200" # mm/min
MOVE_SPEED="7200" # mm/min
USE_UBL="0" # Set to 1 to use automated bed levelling
RETRACTION="1.000" # mm
BEDSIZE_X="200" # mm
BEDSIZE_Y="200" # mm
LAYER_HEIGHT="0.200" # mm 
K_START="0" # Starting value of the K-Factor for the Pattern
K_END="100" # Ending value of the K-Factor for the Pattern
K_STEPPING="5" # Stepping of the K-FACTOR for the pattern. Needs to be an exact divisor of K_END minus K_START
EXTRUSION_MULT="1.0" # arbitraty multiplier, just for testing, should be 1.0 normally
NOZZLE_LINE_RATIO="1.2" # Ratio between nozzle size and line width. Should be between 1.05 and 1.2

## SETTINGS END ##

## Check if K-Factor Range can be cleanly divided
K_RANGE=$((K_END-K_START))
K_MODULO=$(awk -v krange="$K_RANGE" -v kstep="$K_STEPPING" 'BEGIN {print krange%kstep}')
if [ ${K_MODULO} -ne 0 ]; then
	echo "Your K-Factor range cannot be cleanly divided. Check Start / End / Steps for the K-Factor"
	exit
fi

## Check if test pattern fits to the print bed
PRINT_SIZE_Y=$(awk -v krange="$K_RANGE" -v kstep="$K_STEPPING" 'BEGIN {printf "%.2f", krange /  kstep * 5 + 25}')
if [ $(awk -v printsizey="$PRINT_SIZE_Y" -v bedy="$BEDSIZE_Y" 'BEGIN { if (printsizey > bedy - 20) {print 1}}') ]; then
	echo "Your K-Factor settings exceed your Y bed size. Check Start / End / Steps for the K-Factor"
	exit
fi

## Calculate some start values
START_X=$(awk -v var="$BEDSIZE_X" 'BEGIN {print (var - 80) / 2}')
START_Y=$(awk -v bedy="$BEDSIZE_Y" -v printsizey="$PRINT_SIZE_Y" 'BEGIN {printf "%.2f", (bedy - printsizey) / 2 }')
PRIME_Y2=$(awk -v var="$START_Y" 'BEGIN {print var + 100}')

## Calculate extrusion parameters
EXTRUSION_RATIO=$(awk -v nozdia="$NOZZLE_DIAMETER" -v nozlineratio="$NOZZLE_LINE_RATIO" -v layheight="$LAYER_HEIGHT" -v fildia="$FILAMENT_DIAMETER" 'BEGIN {
						printf "%f", nozdia * nozlineratio * layheight / ((fildia / 2)^2 * atan2(0, -1))}')
EXT_20=$(awk -v extratio="$EXTRUSION_RATIO" -v extmulti="$EXTRUSION_MULT" 'BEGIN {printf "%.5f", extratio * extmulti * 20}')
EXT_40=$(awk -v extratio="$EXTRUSION_RATIO" -v extmulti="$EXTRUSION_MULT" 'BEGIN {printf "%.5f", extratio * extmulti * 40}')

## Start gcode generation
cat <<EOF
; K-FACTOR TEST
;
; Created: $(date +"%Y-%m-%d_%H-%M-%S")
; Settings:
; Filament Diameter,${FILAMENT_DIAMETER}
; Nozzle Diameter,${NOZZLE_DIAMETER}
; Nozzle Temperature,${NOZZLE_TEMP}
; Nozzle / Line Ratio,${NOZZLE_LINE_RATIO}
; Bed Temperature,${BED_TEMP}
; Slow Printing Speed,${SLOW_SPEED}
; Fast Printing Speed,${FAST_SPEED}
; Movement Speed,${MOVE_SPEED}
; Use UBL,${USE_UBL}
; Retraction Distance,${RETRACTION}
; Bed Size X,${BEDSIZE_X}
; Bed Size Y,${BEDSIZE_Y}
; Layer Height,${LAYER_HEIGHT}
; Extrusion Multiplier,${EXTRUSION_MULT}
; Starting Value K-Factor,${K_START}
; Ending value K-Factor,${K_END}
; K-Factor Stepping,${K_STEPPING}
;
G28 ; home all axes
M190 S${BED_TEMP} ; set and wait for bed temp
M104 S${NOZZLE_TEMP} ; set nozzle temp and continue
EOF

if [ "$USE_UBL" -eq "1" ]; then
	echo "G29 ; execute bed automatic leveling compensation"
fi

cat <<EOF
M109 S${NOZZLE_TEMP} ; block waiting for nozzle temp
G21 ; set units to millimeters
M204 S500 ; lower acceleration to 500mm/s2 during the test
M83 ; use relative distances for extrusion
G90 ; use absolute coordinates
;
; go to layer height and prime nozzle on a line to the left
;
G1 X20 Y${START_Y} F${MOVE_SPEED}
G1 Z${LAYER_HEIGHT} F${SLOW_SPEED}
G1 X20 Y${PRIME_Y2} E10 F${SLOW_SPEED} ; extrude some to start clean
G1 E-${RETRACTION}
;
; start the test (all values are relative coordinates)
;
G1 X${START_X} Y${START_Y} F${MOVE_SPEED} ; move to pattern start
G91 ; use relative coordinates
EOF

## Loop over all chosen K-Factors
cnt=$(awk -v krange="$K_RANGE" -v kstep="$K_STEPPING" 'BEGIN {print krange/kstep}')
i=0
while [ ${i} -le ${cnt} ]; do
	cat << EOF
M900 K$(awk -v kstart="$K_START" -v kstep="$K_STEPPING" -v num="$i" 'BEGIN {print kstep * num + kstart}') ; set K-factor
G1 E${RETRACTION}
G1 X20 Y0 E${EXT_20} F${SLOW_SPEED}
G1 X40 Y0 E${EXT_40} F${FAST_SPEED}
G1 X20 Y0 E${EXT_20} F${SLOW_SPEED}
G1 E-${RETRACTION}
G1 X-80 Y5 F${MOVE_SPEED}
EOF
	i=$((i+1))
	done

cat << EOF
;
; mark the test area for reference
;
G1 X20 Y0 F${MOVE_SPEED}
G1 E${RETRACTION}
G1 X0 Y20 E${EXT_20} F${SLOW_SPEED}
G1 E-${RETRACTION}
G1 X40 Y-20 F${MOVE_SPEED}
G1 E${RETRACTION}
G1 X0 Y20 E${EXT_20} F${SLOW_SPEED}
G1 E-${RETRACTION}
;
; finish
;
G4 ; wait
M104 S0 ; turn off hotend
M140 S0 ; turn off bed
G90 ; use absolute coordinates
G1 Z30 Y200 F${MOVE_SPEED} ; move away from the print
M84 ; disable motors
M502 ; resets parameters from ROM (for those who do not have an EEPROM)
M501 ; resets parameters from EEPROM (preferably)
;
EOF
