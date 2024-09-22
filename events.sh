#!/bin/bash -e

export DEBUG=0

function dbg {
	if [ $DEBUG -ne 0 ]; then echo $1; fi
}

FILTER_ABS=(Y Z RX RY RZ HAT1X HAT2X HAT3X HAT0Y HAT1Y)
FILTER_BTN=(SELECT START)

# zero point
export ZP=128

MODE=1

source ./pwm.sh

function brake {
	dbg "stop $1 $(( $2 / 2 + 1))"
	bridge_stop "$1" $(( $2 / 2 + 1))
}

function drive_single {
	dbg "bridge_drive $1 $2"
	bridge_drive $1 $2
}

function normal {
	echo $(($ZP - $1))
}

function calibr {
	if [ $1 -lt $((0 - $ZP)) ]; then echo $((0 - $ZP))
	elif [ $1 -gt $ZP ]; then echo $ZP
	else echo $1; fi
}

function drive_smart {
	local S=$(($(normal $ABS_Y) + $ABS_HAT2X / 2 - $ABS_HAT3X / 2))
	local T=$(($(normal $ABS_RX) + $ABS_HAT1Y / 2 - $ABS_HAT0Y / 2))
	drive_single "LEFT" $(calibr $(($S - $T)) )
	drive_single "RIGHT" $(calibr $(($S + $T)) )
}

function drive {
	[ $MODE -eq 0 ] && drive_single $1 $(normal $2) || drive_smart
}

function action_BTN_SELECT {
	MODE=$(($MODE ^ $BTN_SELECT))
	dbg "MODE=${MODE}"
}

function action__BTN_START {
	shutdown -h now
}

function action_ABS_Z {
	[[ $1 -eq 0 ]] && drive "LEFT" $ABS_Y || brake "LEFT" $1
}

function action_ABS_RZ {
	[[ $1 -eq 0 ]] && drive "RIGHT" $ABS_RY || brake "RIGHT" $1
}

function action_ABS_Y {
	if [ $ABS_Z -eq 0 ]; then drive "LEFT" $1; fi
}

function action_ABS_RX {
	if [ $ABS_RZ -eq 0 ] && [ $MODE -ne 0 ]; then drive; fi
}

function action_ABS_RY {
	if [ $ABS_RZ -eq 0 ] && [ $MODE -eq 0 ]; then drive "RIGHT" $1; fi
}

function action_ABS_HAT1X {
	if [[ $1 -eq 0 ]]; then
		drive "LEFT" $ABS_Y
		drive "RIGHT" $ABS_RY
	else
		brake "LEFT" $1
		brake "RIGHT" $1
	fi
}

function action_ABS_HAT2X {
	drive_smart
}

function action_ABS_HAT3X {
	drive_smart
}

function action_ABS_HAT0Y {
	drive_smart
}

function action_ABS_HAT1Y {
	drive_smart
}

# run

for i in ${FILTER_ABS[*]}; do eval "ABS_${i}=0"; done
for i in ${FILTER_BTN[*]}; do eval "BTN_${i}=0"; done

ABS_X=$ZP
ABS_Y=$ZP
ABS_RX=$ZP
ABS_RY=$ZP

bridge_export "LEFT"
bridge_export "RIGHT"

while read -r DATA; do
	dbg $DATA
	DATA=($DATA)
	if [ "${DATA[9]}" == "value" ]; then
		K=${DATA[8]:1:-2}
		V=${DATA[10]}
		if [ $DEBUG -eq 0 ]; then
			eval "$K=$V" 2> /dev/null && action_${K} ${V} 2> /dev/null || true
		else
			eval "$K=$V" && action_${K} ${V} || true
		fi
	fi
done < <(evtest /dev/input/event3)

bridge_unexport "LEFT"
bridge_unexport "RIGHT"
