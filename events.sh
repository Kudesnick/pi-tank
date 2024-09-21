#!/bin/bash -e

export DEBUG=1

function dbg {
	test $DEBUG -ne 0 && echo $1
}

FILTER_ABS=(Y Z RX RY RZ HAT1X HAT2X HAT3X HAT0Y HAT1Y)
FILTER_BTN=(SELECT START)

# zero point
export ZP=128

MODE=0
ABS_Y=$ZP
ABS_Z=0
ABS_RY=$ZP
ABS_RZ=0

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
	local S=$(normal $ABS_Y)
	local T=$(normal $ABS_RX)

	bridge_drive "LEFT" $(calibr $(($S - $T)) )
	bridge_drive "RIGHT" $(calibr $(($S + $T)) )
}

function drive {
	[ $MODE -eq 0 ] && drive_single $1 $(normal $2) || drive_smart
}

function action_BTN_SELECT {
	MODE=$(($MODE ^ $BTN_SELECT))
	dbg "MODE=${MODE}"
}

function action_BTN_START {
	shutdown -h now
}

function action_ABS_Z {
	if [ $ABS_Z -eq 0 ]; then drive "LEFT" $ABS_Y; else brake "LEFT" $ABS_Z; fi
}

function action_ABS_RZ {
	if [ $ABS_RZ -eq 0 ]; then drive "RIGHT" $ABS_RY; else brake "RIGHT" $ABS_RZ; fi
}

function action_ABS_Y {
	if [ $ABS_Z -eq 0 ]; then drive "LEFT" $ABS_Y; fi
}

function action_ABS_RX {
	if [ $ABS_RZ -eq 0 ] && [ $MODE -ne 0 ]; then drive; fi
}

function action_ABS_RY {
	if [ $ABS_RZ -eq 0 ] && [ $MODE -eq 0 ]; then drive "RIGHT" $ABS_RY; fi
}

function action_ABS_HAT1X {
	if [ $ABS_HAT1X -eq 0 ]; then
		drive "LEFT" $ABS_Y
		drive "RIGHT" $ABS_RY
	else
		brake "LEFT" $(($ABS_HAT1X / 2))
		brake "RIGHT" $(($ABS_HAT1X / 2))
	fi
}

function action_ABS_HAT2X {
	ABS_Y=$(($ABS_HAT2X / 2))
	drive_smart
}

function action_ABS_HAT3X {
	ABS_Y=$((0 - $ABS_HAT2X / 2))
	drive_smart
}

function action_ABS_HAT0Y {
	ABS_RX=$((0 - $ABS_HAT0Y / 2))
	drive_smart
}

function action_ABS_HAT1Y {
	ABS_RX=$(($ABS_HAT0Y / 2))
	drive_smart
}

function action {
	while read -r DATA; do
		eval $DATA
		dbg $DATA
		action_${DATA%%=*} || true
	done
}

# run

GREP_CHAIN=""

for i in ${FILTER_ABS[*]}; do
	GREP_CHAIN="${GREP_CHAIN} -we ABS_${i}"
done

for i in ${FILTER_BTN[*]}; do
	GREP_CHAIN="${GREP_CHAIN} -we BTN_${i}"
done

bridge_export "LEFT"
bridge_export "RIGHT"

evtest /dev/input/event3 |\
	grep --line-buffered ${GREP_CHAIN} |\
        grep --line-buffered -o -P '\((ABS|BTN)_[A-Z0-9]+\), value [0-9]+$' |\
	sed -u -e "s/), value /=/" -e "s/(//" | action

bridge_unexport "LEFT"
bridge_unexport "RIGHT"
