#!/bin/bash -e

# pwm as sysfs

PWM="/sys/class/pwm/pwmchip0"

DEBUG=${DEBUG:-0}
PWM_DIMENSION=${ZP:-100}
PWM_SWAP=${PWM_SWAP:-0}

PWM_PERIOD=25000000
PWM_LEFT=$((0 ^ $PWM_SWAP))
PWM_RIGHT=$((1 ^ $PWM_SWAP))

function pwm_duty {
	echo $(( $PWM_PERIOD / $PWM_DIMENSION * $2 )) > "${PWM}/pwm$1/duty_cycle"
}

function pwm_export {
	test -d "${PWM}/pwm$1" || echo $1 > "${PWM}/export"
	echo ${PWM_PERIOD} > "${PWM}/pwm$1/period"
	pwm_duty $1 $2
	echo 1 > "${PWM}/pwm$1/enable"
}

function pwm_unexport {
	echo 0 > "${PWM}/pwm$1/enable"
	echo $1 > "${PWM}/unexport"
}

# gpio as sysfs

GPIO="/sys/class/gpio"
if [ $PWM_SWAP -eq 0 ]; then
	GPIO_LEFT_FORWARD=17
	GPIO_LEFT_BACK=18
	GPIO_RIGHT_FORWARD=22
	GPIO_RIGHT_BACK=23
else
	GPIO_LEFT_FORWARD=23
	GPIO_LEFT_BACK=22
	GPIO_RIGHT_FORWARD=18
	GPIO_RIGHT_BACK=17
fi
HI=1
LOW=0

function gpio_set {
	echo $HI > ${GPIO}/gpio$1/value
}

function gpio_reset {
	echo $LOW > ${GPIO}/gpio$1/value
}

function gpio_export {
	test -d "${GPIO}/gpio$1" || echo $1 > "${GPIO}/export"
	echo out > ${GPIO}/gpio$1/direction
	gpio_reset $1
}

function gpio_unexport {
	echo $1 > "${GPIO}/unexport"
}

# H-bridge

function bridge_export {
	pwm_export $(eval echo "\$PWM_$1") 0
	gpio_export $(eval echo "\$GPIO_$1_FORWARD")
	gpio_export $(eval echo "\$GPIO_$1_BACK")
}

function bridge_unexport {
	pwm_unexport $(eval echo "\$PWM_$1")
	gpio_unexport $(eval echo "\$GPIO_$1_FORWARD")
	gpio_unexport $(eval echo "\$GPIO_$1_BACK")
}

function bridge_stop {
	pwm_duty $(eval echo "\$PWM_$1") $2
	gpio_reset $(eval echo "\$GPIO_$1_FORWARD")
	gpio_reset $(eval echo "\$GPIO_$1_BACK")
}

function bridge_forward {
	gpio_set $(eval echo "\$GPIO_$1_FORWARD")
	gpio_reset $(eval echo "\$GPIO_$1_BACK")
	pwm_duty $(eval echo "\$PWM_$1") $2
}

function bridge_back {
	gpio_reset $(eval echo "\$GPIO_$1_FORWARD")
	gpio_set $(eval echo "\$GPIO_$1_BACK")
	pwm_duty $(eval echo "\$PWM_$1") $2
}

function bridge_drive {
	if [ $2 -eq 0 ]; then
		bridge_stop $1 0
	elif [ $2 -gt 0 ]; then
		bridge_forward $1 $2
	else
		bridge_back $1 $((0 - $2))
	fi
}

<< 'DEMO'

DELAY=4

bridge_export "LEFT"
bridge_export "RIGHT"

bridge_back "LEFT" 20
sleep ${DELAY}

bridge_back "RIGHT" 20
sleep ${DELAY}

bridge_forward "LEFT" 20
sleep ${DELAY}

bridge_forward "RIGHT" 20
sleep ${DELAY}

bridge_forward "LEFT" 50
bridge_forward "RIGHT" 50
sleep ${DELAY}

bridge_forward "LEFT" 100
bridge_forward "RIGHT" 100
sleep ${DELAY}

bridge_forward "LEFT" 20
bridge_forward "RIGHT" 20
sleep ${DELAY}

bridge_stop "LEFT" 50
bridge_stop "RIGHT" 50
sleep ${DELAY}

bridge_unexport "LEFT"
bridge_unexport "RIGHT"

DEMO
