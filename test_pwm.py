import RPi.GPIO as GPIO
import time

GPIO_PWM_0 = 12 # 12 or 18
GPIO_PWM_1 = 13 # 13 or 19
WORK_TIME = 10
DUTY_CYCLE = 50
FREQUENCY = 50

print('Start')

GPIO.setmode(GPIO.BCM)
GPIO.setup(GPIO_PWM_0, GPIO.OUT)
GPIO.setup(GPIO_PWM_1, GPIO.OUT)

pwmOutput_0 = GPIO.PWM(GPIO_PWM_0, FREQUENCY)
pwmOutput_1 = GPIO.PWM(GPIO_PWM_1, FREQUENCY)

# pwmOutput_0.start(DUTY_CYCLE)
# pwmOutput_1.start(DUTY_CYCLE)

time.sleep(WORK_TIME)

pwmOutput_0.stop()
pwmOutput_1.stop()

GPIO.cleanup()

print('end')
