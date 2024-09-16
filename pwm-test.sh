#!/bin/bash -e

PWM="/sys/class/pwm/pwmchip0"
PWM0="${PWM}/pwm0"
PWM1="${PWM}/pwm1"

gpioset --drive=push-pull 0 17=0 18=0 22=0 23=0

echo 0 > "${PWM}/export"
echo 50000000 > "${PWM0}/period"
echo 10000000 > "${PWM0}/duty_cycle"
echo 1 > "${PWM0}/enable"

echo 1 > "${PWM}/export"
echo 50000000 > "${PWM1}/period"
echo 10000000 > "${PWM1}/duty_cycle"
echo 1 > "${PWM1}/enable"

gpioset 0 17=0 18=1
sleep 5

gpioset 0 22=0 23=1
sleep 5

gpioset 0 17=1 18=0
sleep 5

gpioset 0 22=1 23=0
sleep 5

echo 25000000 > "${PWM0}/duty_cycle"
echo 25000000 > "${PWM1}/duty_cycle"
sleep 5

echo 50000000 > "${PWM0}/duty_cycle"
echo 50000000 > "${PWM1}/duty_cycle"
sleep 5

echo 0 > "${PWM0}/enable"
echo 0 > "${PWM1}/enable"
sleep 5

gpioset 0 17=0 18=0 22=0 23=0
