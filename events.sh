#!/bin/bash -e

DEBUG=0

function dbg {
	test $DEBUG -ne 0 && echo $1
}

FILTER_ABS=(Y Z RX RY RZ)
FILTER_BTN=(SELECT START)

MODE=0
ABS_Y=128
ABS_Z=0
ABS_RY=128
ABS_RZ=0

source ./pwm.sh

function brake {
		dbg "stop $1 $(( $2 / 2 + 1))"
		bridge_stop "$1" $(( $2 / 2 + 1))
}

function drive_single {
	if [ $2 -eq 128 ]; then
		dbg "stop $1 0"
		bridge_stop "$1" 0
	elif [ $2 -gt 128 ]; then
		dbg "back $1 $(( $2 - 127 ))"
		bridge_back "$1" $(( $2 - 127 ))
	else
		dbg "forward $1 $(( 128 - $2 ))"
		bridge_forward "$1" $(( 128 - $2 ))
	fi
}

function drive_smart {
	if [ $ABS_RX -ne 128 ]; then
		drive_single "LEFT" $(( $ABS_RX - 127 ))
		drive_single "RIGHT" $(( 128 - $ABS_RX ))
	fi
}

function drive {
	if [ $MODE -eq 0 ]; then drive_single $1 $2; else drive_smart: fi
}

function action_BTN_SELECT {
	MODE=$(( $MODE ^ 1 ))
	dbg "MODE=${MODE}"
}

function action_BTN_START {
	shutdown -h now
}

function action_ABS_Z {
	if [ $ABS_Z -eq 0 ]; then action_ABS_Y; else brake "LEFT" $ABS_Z; fi
}

function action_ABS_RZ {
	if [ $ABS_RZ -eq 0 ]; then action_ABS_RY; else brake "RIGHT" $ABS_RZ; fi
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

evtest /dev/input/event2 |\
	grep --line-buffered ${GREP_CHAIN} |\
        grep --line-buffered -o -P '\((ABS|BTN)_[A-Z0-9]+\), value [0-9]+$' |\
	sed -u -e "s/), value /=/" -e "s/(//" | action

bridge_unexport "LEFT"
bridge_unexport "RIGHT"
