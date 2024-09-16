#!/bin/bash -e

# pwm as sysfs

PWM="/sys/class/pwm/pwmchip0"

PWM_PERIOD=50000000
PWM_LEFT=0
PWM_RIGHT=1

pwm_duty {
    echo $(${PWM_PERIOD} / 100 * $2) > "${PWM}/pwm$1/duty_cycle"
}

pwm_export {
    test -d "${PWM}/pwm$1" || echo $1 > "${PWM}/export"
    echo ${PWM_PERIOD} > "${PWM}/pwm$1/period"
    pwm_duty $1 $2
    echo 1 > "${PWM}/pwm$1/enable"
}

pwm_unexport {
    echo 0 > "${PWM}/pwm$1/enable"
    echo $1 > "${PWM}/unexport"
}

# gpio as sysfs

GPIO="/sys/class/gpio"
GPIO_L_FORWARD=17
GPIO_L_BACK=18
GPIO_R_FORWARD=22
GPIO_R_BACK=23
HI=1
LOW=0

gpio_set {
    echo ${HI} > ${GPIO}/gpio$1/value
}

gpio_reset {
    echo ${LOW} > ${GPIO}/gpio$1/value
}

gpio_export {
    test -d "${GPIO}/gpio$1" || echo $1 > "${GPIO}/export"
    echo out > ${GPIO}/gpio$1/direction
    gpio_reset $1
}

gpio_unexport {
    echo $1 > "${GPIO}/unexport"
}

# main

DELAY=4

gpio_export $GPIO_L_FORWARD
gpio_export $GPIO_L_BACK
gpio_export $GPIO_R_FORWARD
gpio_export $GPIO_R_BACK

pwm_export $PWM_LEFT 20
pwm_export $PWM_RIGHT 20

gpio_set $GPIO_L_FORWARD
sleep ${DELAY}

gpio_set $GPIO_R_FORWARD
sleep ${DELAY}

gpio_reset $GPIO_L_FORWARD
gpio_set $GPIO_L_BACK
sleep ${DELAY}

gpio_reset $GPIO_R_FORWARD
gpio_set $GPIO_R_BACK
sleep ${DELAY}

pwm_duty $PWM_LEFT 50
pwm_duty $PWM_RIGHT 50
sleep ${DELAY}

pwm_duty $PWM_LEFT 100
pwm_duty $PWM_RIGHT 100
sleep ${DELAY}

pwm_duty $PWM_LEFT 0
pwm_duty $PWM_RIGHT 0
sleep ${DELAY}

gpio_unexport $GPIO_L_FORWARD
gpio_unexport $GPIO_L_BACK
gpio_unexport $GPIO_R_FORWARD
gpio_unexport $GPIO_R_BACK

pwm_unexport $PWM_LEFT
pwm_unexport $PWM_RIGHT
