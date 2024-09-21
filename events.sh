#!/bin/bash -e

export DEBUG=0

function dbg {
	[[ $DEBUG -ne 0 ]] && echo $1 || true
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

function action_BTN_START {
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

function action {
	while read -r DATA; do
		dbg $DATA
		if [ $DEBUG -eq 0 ]; then
			eval $DATA 2> /dev/null && action_${DATA%%=*} ${DATA%%=*} 2> /dev/null || true
		else
			eval $DATA && action_${DATA%%=*} ${DATA%%=*} || true
		fi
	done
}

# run

GREP_CHAIN=""

for i in ${FILTER_ABS[*]}; do
	GREP_CHAIN="${GREP_CHAIN} -we ABS_${i}"
	eval "ABS_${i}=0"
done

for i in ${FILTER_BTN[*]}; do
	GREP_CHAIN="${GREP_CHAIN} -we BTN_${i}"
	eval "BTN_${i}=0"
done

ABS_X=$ZP
ABS_Y=$ZP
ABS_RX=$ZP
ABS_RY=$ZP

bridge_export "LEFT"
bridge_export "RIGHT"

export LC_ALL=C

evtest /dev/input/event3 |\
    grep --line-buffered -oP '(AB|BT).+' |\
	sed -u "s/), value /=/" | action

#evtest /dev/input/event3 |\
#    grep --line-buffered -eoP '(ABS|BTN).+' |\
#	sed -u "s/), value /=/" | action

bridge_unexport "LEFT"
bridge_unexport "RIGHT"
