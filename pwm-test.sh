#!/bin/bash -e

# pwm as sysfs

PWM="/sys/class/pwm/pwmchip0"

PWM_PERIOD=50000000
PWM_LEFT=0
PWM_RIGHT=1

function pwm_duty {
    echo $(( ${PWM_PERIOD} / 100 * $2 )) > "${PWM}/pwm$1/duty_cycle"
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
GPIO_LEFT_FORWARD=17
GPIO_LEFT_BACK=18
GPIO_RIGHT_FORWARD=22
GPIO_RIGHT_BACK=23
HI=1
LOW=0

function gpio_set {
    echo ${HI} > ${GPIO}/gpio$1/value
}

function gpio_reset {
    echo ${LOW} > ${GPIO}/gpio$1/value
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

H_LEFT="LEFT"
H_RIGHT="RIGHT"

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
    pwm_duty $(eval echo "\$PWM_$1") 0
    gpio_reset $(eval echo "\$GPIO_$1_FORWARD")
    gpio_reset $(eval echo "\$GPIO_$1_BACK")
    pwm_duty $(eval echo "\$PWM_$1") $2
}

function bridge_forward {
    pwm_duty $(eval echo "\$PWM_$1") 0
    gpio_set $(eval echo "\$GPIO_$1_FORWARD")
    gpio_reset $(eval echo "\$GPIO_$1_BACK")
    pwm_duty $(eval echo "\$PWM_$1") $2
}

function bridge_back {
    pwm_duty $(eval echo "\$PWM_$1") 0
    gpio_reset $(eval echo "\$GPIO_$1_FORWARD")
    gpio_set $(eval echo "\$GPIO_$1_BACK")
    pwm_duty $(eval echo "\$PWM_$1") $2
}

# main

DELAY=4

bridge_export ${H_LEFT}
bridge_export ${H_RIGHT}

bridge_back ${H_LEFT} 20
sleep ${DELAY}

bridge_back ${H_RIGHT} 20
sleep ${DELAY}

bridge_forward ${H_LEFT} 20
sleep ${DELAY}

bridge_forward ${H_RIGHT} 20
sleep ${DELAY}

bridge_forward ${H_LEFT} 50
bridge_forward ${H_RIGHT} 50
sleep ${DELAY}

bridge_forward ${H_LEFT} 100
bridge_forward ${H_RIGHT} 100
sleep ${DELAY}

bridge_forward ${H_LEFT} 20
bridge_forward ${H_RIGHT} 20
sleep ${DELAY}

bridge_stop ${H_LEFT} 50
bridge_stop ${H_RIGHT} 50
sleep ${DELAY}

bridge_unexport ${H_LEFT}
bridge_unexport ${H_RIGHT}
