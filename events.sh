#!/bin/bash -e

FILTER_ABS=(Y Z RY RZ)
FILTER_BTN=(SELECT START)

MODE=0
ABS_Y=128
ABS_Z=0
ABS_RY=128
ABS_RZ=0

source ./pwm.sh

function action_ABS_Z {
	echo "ABS_Z=${ABS_Z}"
	if [ $ABS_Z -eq 0 ]; then
		action_ABS_Y
	else
		echo "stop LEFT $(( $ABS_Z / 2 + 1))"
		bridge_stop "LEFT" $(( $ABS_Z / 2 + 1))
	fi
}

function action_ABS_RZ {
	echo "ABS_RZ=${ABS_RZ}"
	if [ $ABS_RZ -eq 0 ]; then
		action_ABS_RY
	else
		echo "stop RIGHT $(( $ABS_RZ / 2 + 1))"
		bridge_stop "RIGHT" $(( $ABS_RZ / 2 + 1))
	fi
}

function action_ABS_Y {
	echo "ABS_Y=${ABS_Y}"
	test $ABS_Z -ne 0 && return 
	if [ $ABS_Y -eq 128 ]; then
		echo "stop LEFT 0"
		bridge_stop "LEFT" 0
	elif [ $ABS_Y -gt 128 ]; then
		echo "back LEFT $(( $ABS_Y - 127 ))"
		bridge_back "LEFT" $(( $ABS_Y - 127 ))
	else
		echo "forward LEFT $(( 128 - $ABS_Y ))"
		bridge_forward "LEFT" $(( 128 - $ABS_Y ))
	fi
}

function action_ABS_RY {
	echo "ABS_RY=${ABS_RY}"
	test $ABS_RZ -ne 0 && return
	if [ $ABS_RY -eq 128 ]; then
		echo "stop RIGHT 0"
		bridge_stop "RIGHT" 0
	elif [ $ABS_RY -gt 128 ]; then
		echo "back RIGHT $(( $ABS_RY - 127 ))"
		bridge_back "RIGHT" $(( $ABS_RY - 127 ))
	else
		echo "forward RIGHT $(( 128 - $ABS_RY ))"
		bridge_forward "RIGHT" $(( 128 - $ABS_RY ))
	fi
}

function action_BTN_START {
	echo "BTN_START=${BTN_START}"
	exit 0
}

function action {
	while read -r DATA; do
		eval $DATA
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
