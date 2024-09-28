#include <stdio.h>
#include <stdint.h>

#include <linux/input.h>

#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <dirent.h>
#include <errno.h>
#include <getopt.h>
#include <ctype.h>
#include <signal.h>
#include <sys/time.h>
#include <sys/types.h>
#include <unistd.h>

#include <sys/stat.h>

static int debug_flag = 0;
static volatile sig_atomic_t stop = 0;

#define dbg(format,args...) if (debug_flag) fprintf(stderr, format, ## args)

static void swap(int *a, int *b)
{
	*a = *a ^ *b;
	*b = *a ^ *b;
	*a = *a ^ *b;
}

static int open_try(const char *filename, int flags)
{
	int fd;

	// if the file was just created then the udev-rules have not yet been applied to it
	for(int try = (getuid() != 0) ? 10 : 1; try > 0; try--){
		if ((fd = open(filename, flags)) >= 0) return fd;
		if (errno == EACCES && getuid() != 0) usleep(100000);
	}

	perror("pi-tank");
	if (errno == EACCES && getuid() != 0)
		fprintf(stderr,
			"You do not have access to %s. Try running as root instead.\n",
			filename);
	else
		fprintf(stderr,
			"You do not have access to %s. Undefined error.\n",
			filename);

	return fd;
}

static int dir_exists(const char *pathname) {
	struct stat sb;

	return (stat(pathname, &sb) == 0 && S_ISDIR(sb.st_mode)) ? 0 : 1;
}

static int writestr(const char *filename, const char *str) {
	int fd;

	if (((fd = open_try(filename, O_WRONLY)) >= 0)){
		if (write(fd, str, strlen(str)) < 0){
			fprintf(stderr,
				"You do not have write string '%s' to %s. Try running as root instead.\n",
				str, filename);
		}
		close(fd);
	}

	return fd;
}

static int writeint(const char *filename, const int val) {
	char str[16];

	snprintf(str, sizeof(str), "%d", val);
	return writestr(filename, str);
}

static int writeint_fd(const int fd, const int val) {
	char str[16];
	int len;

	len = snprintf(str, sizeof(str), "%d", val);
	if (write(fd, str, len) < 0){
		fprintf(stderr,
			"You do not have write string '%s' to file description %d.\n",
			str, fd);
	}else{
		fsync(fd);
	}

	return fd;
}

/* === H-BRIDGE === */

enum side_t {
	LEFT,
	RIGHT,
};

enum route {
	FORWARD,
	BACK,
	STOP,
	BRAKE,
};

enum active {
	HI,
	LOW,
};

char *pwm_class_path = "/sys/class/pwm/pwmchip0";
char *gpio_class_path = "/sys/class/gpio";
int pwm_dimension = 128;
int pwm_swap = 0;
int pwm_period = 25000000;

struct pwm_t {
	int state, ch, fd;
} pwm[2] = {
	[LEFT]  = {STOP, 0, -1},
	[RIGHT] = {STOP, 1, -1},
};

struct gpio_t {
	int pin, fd;
} gpio[2][2] = {
	[LEFT] = {
		[FORWARD] = {17, -1},
		[BACK]    = {18, -1},
	},
	[RIGHT] = {
		[FORWARD] = {22, -1},
		[BACK]    = {23, -1},
	},
};

int level[2] = {
	[HI] = 1,
	[LOW] = 0,
};

/* pwm */

int pwm_duty_set(const struct pwm_t *pwm, const int duty)
{
	return writeint_fd(pwm->fd, pwm_period / pwm_dimension * duty);
}

int pwm_export(struct pwm_t *pwm)
{
	int fd;
	char filename[64];
	char data[16];

	snprintf(filename, sizeof(filename), "%s/pwm%d/", pwm_class_path, pwm->ch);
	if(dir_exists(filename) != 0){
		snprintf(filename, sizeof(filename), "%s/export", pwm_class_path);
		if (((fd = writeint(filename, pwm->ch)) < 0)) return fd;
	};

	snprintf(filename, sizeof(filename), "%s/pwm%d/period", pwm_class_path, pwm->ch);	
	if (((fd = writeint(filename, pwm_period)) < 0)) return fd;

	snprintf(filename, sizeof(filename), "%s/pwm%d/enable", pwm_class_path, pwm->ch);	
	if (((fd = writeint(filename, 1)) < 0)) return fd;

	snprintf(filename, sizeof(filename), "%s/pwm%d/duty_cycle", pwm_class_path, pwm->ch);
	pwm->fd = open_try(filename, O_WRONLY);
	return pwm_duty_set(pwm, 0);
}

int pwm_unexport(const struct pwm_t *pwm)
{
	int fd;
	char filename[64];

	snprintf(filename, sizeof(filename), "%s/pwm%d/", pwm_class_path, pwm->ch);
	if(dir_exists(filename) != 0) {
		snprintf(filename, sizeof(filename), "%s/pwm%d/enable", pwm_class_path, pwm->ch);	
		if (((fd = writeint(filename, 0)) < 0)) return fd;
	}

	if (pwm->fd > 0) close(pwm->fd);

	snprintf(filename, sizeof(filename), "%s/unexport", pwm_class_path);
	if (((fd = writeint(filename, pwm->ch)) < 0)) return fd;

	return fd;
}

/* gpio */

int gpio_set(const struct gpio_t *gpio, const enum active val)
{
	return writeint_fd(gpio->fd, level[val]);
}

int gpio_export(struct gpio_t *gpio)
{
	int fd;
	char filename[64];

	snprintf(filename, sizeof(filename), "%s/gpio%d/", gpio_class_path, gpio->pin);
	if(dir_exists(filename) != 0){
		snprintf(filename, sizeof(filename), "%s/export", gpio_class_path);
		if (((fd = writeint(filename, gpio->pin)) < 0)) return fd;
	};

	snprintf(filename, sizeof(filename), "%s/gpio%d/direction", gpio_class_path, gpio->pin);
	if (((fd = writestr(filename, "out")) < 0)) return fd;

	snprintf(filename, sizeof(filename), "%s/gpio%d/value", gpio_class_path, gpio->pin);
	gpio->fd = open_try(filename, O_WRONLY);
	return gpio_set(gpio, LOW);
}

int gpio_unexport(const struct gpio_t *gpio)
{
	char filename[64];

	if (gpio->fd > 0) close(gpio->fd);

	snprintf(filename, sizeof(filename), "%s/unexport", gpio_class_path);
	return writeint(filename, gpio->pin);
}

/* bridge */

void h_bridge_export(const enum side_t side)
{
	pwm_export(&pwm[side]);
	gpio_export(&gpio[side][FORWARD]);
	gpio_export(&gpio[side][BACK]);
	pwm[side].state = STOP;
}

void h_bridge_unexport(const enum side_t side)
{
	pwm_unexport(&pwm[side]);
	gpio_unexport(&gpio[side][FORWARD]);
	gpio_unexport(&gpio[side][BACK]);
}

void h_bridge_drive(const enum side_t side, const int val)
{
	enum route new_route = (val > 0) ? FORWARD : (val < 0) ? BACK : STOP;

	if (pwm[side].state != new_route) {
		pwm_duty_set(&pwm[side], 0);
		switch(new_route) {
			case FORWARD:
				gpio_set(&gpio[side][FORWARD], HI);
				gpio_set(&gpio[side][BACK], LOW);
				break;
			case BACK:
				gpio_set(&gpio[side][FORWARD], LOW);
				gpio_set(&gpio[side][BACK], HI);
				break;
			default:
				gpio_set(&gpio[side][FORWARD], LOW);
				gpio_set(&gpio[side][BACK], LOW);
				break;
		}
		pwm[side].state = new_route;
	}

	pwm_duty_set(&pwm[side], abs(val));
}

void h_bridge_brake(const enum side_t side, const int val)
{
	if (pwm[side].state != BRAKE) {
		pwm_duty_set(&pwm[side], 0);
		gpio_set(&gpio[side][FORWARD], LOW);
		gpio_set(&gpio[side][BACK], LOW);

		pwm[side].state = BRAKE;
	}

	pwm_duty_set(&pwm[side], abs(val));
}

void bridge_test()
{
	int DELAY = 4;

	h_bridge_export(LEFT);
	h_bridge_export(RIGHT);

	h_bridge_drive(LEFT, -20);
	sleep(DELAY);

	h_bridge_drive(RIGHT, -20);
	sleep(DELAY);

	h_bridge_drive(LEFT, 20);
	sleep(DELAY);

	h_bridge_drive(RIGHT, 20);
	sleep(DELAY);

	h_bridge_drive(LEFT, 50);
	h_bridge_drive(RIGHT, 50);
	sleep(DELAY);

	h_bridge_drive(LEFT, 100);
	h_bridge_drive(RIGHT, 100);
	sleep(DELAY);

	h_bridge_drive(LEFT, 20);
	h_bridge_drive(RIGHT, 20);
	sleep(DELAY);

	h_bridge_drive(LEFT, -20);
	h_bridge_drive(RIGHT, -20);
	sleep(DELAY);

	h_bridge_drive(LEFT, 100);
	h_bridge_drive(RIGHT, 100);
	sleep(DELAY);

	h_bridge_brake(LEFT, 50);
	h_bridge_brake(RIGHT, 50);
	sleep(DELAY);

	h_bridge_unexport(LEFT);
	h_bridge_unexport(RIGHT);
}

/* === TANK === */

enum mode_t {
	EASY,
	SMART,
};

enum mode_t mode = EASY;

int speed_shift = 0;

struct ctl_t {
	int code, val, side;
	void(*func)(const enum side_t side, const int val);
};

static struct ctl_t *get_ctl(const int code);

int normal(const int val) {
	return (128 - val);
}

int calibr(const int val) {
	return (val < -128) ? -128 : (val > 128) ? 128 : val;
}

void brake(const enum side_t side, const int val)
{
	h_bridge_brake(side, val / 2);
}

void drive_single(const enum side_t side, const int val)
{
	h_bridge_drive(side, val >> speed_shift);
}

void drive_smart(const enum side_t side, const int val) {
	int S = normal(get_ctl(ABS_Y)->val) + get_ctl(ABS_HAT2X)->val / 2 - get_ctl(ABS_HAT3X)->val / 2;
	int T = normal(get_ctl(ABS_RX)->val) - get_ctl(ABS_HAT0Y)->val / 2 + get_ctl(ABS_HAT1Y)->val / 2;

	if (S >= 0){
		drive_single(LEFT, calibr(S - T));
		drive_single(RIGHT, calibr(S + T));
	}else{
		drive_single(LEFT, calibr(S + T));
		drive_single(RIGHT, calibr(S - T));
	}
}

void drive(const enum side_t side, const int val)
{
	switch (mode) {
		case EASY:
			drive_single(side, normal(val));
			break;
		case SMART: drive_smart(side, val); break;
	}
}

void action_BTN_SELECT(const enum side_t side, const int val)
{
	if (val == 0) mode ^= 1;
}

void action_BTN_START(const enum side_t side, const int val)
{
	if (val == 0) stop = 1;
}

void action_BTN_NORTH(const enum side_t side, const int val)
{
	if (val == 0 && ++speed_shift > 1) speed_shift = 0;
}

void action_ABS_Z(const enum side_t side, const int val)
{
	if (val != 0){
		brake(side, val);
	}else{
		drive(side, get_ctl((side == LEFT) ? ABS_Y : ABS_RY)->val);
	}
}

void action_ABS_Y(const enum side_t side, const int val)
{
	drive(side, val);
}

void action_ABS_RX(const enum side_t side, const int val)
{
	if (mode == SMART) drive(side, val);
}

void action_ABS_HAT1X(const enum side_t side, const int val)
{
	action_ABS_Z(LEFT, val);
	action_ABS_Z(RIGHT, val);
}

static struct ctl_t ctl[] = {
	{ABS_X     , 128, 0    , NULL             },
	{ABS_Y     , 128, LEFT , action_ABS_Y     },
	{ABS_Z     , 0  , LEFT , action_ABS_Z     },
	{ABS_RX    , 128, 0    , action_ABS_RX    },
	{ABS_RY    , 128, RIGHT, action_ABS_Y     },
	{ABS_RZ    , 0  , RIGHT, action_ABS_Z     },
	{ABS_HAT1X , 0  , 0    , action_ABS_HAT1X },
	{ABS_HAT2X , 0  , 0    , drive_smart      },
	{ABS_HAT3X , 0  , 0    , drive_smart      },
	{ABS_HAT0Y , 0  , 0    , drive_smart      },
	{ABS_HAT1Y , 0  , 0    , drive_smart      },
	{BTN_SELECT, 0  , 0    , action_BTN_SELECT},
	{BTN_START , 0  , 0    , action_BTN_START },
	{BTN_NORTH , 0  , 0    , action_BTN_NORTH },
	{0, 0, 0, NULL}
};

static struct ctl_t *get_ctl(const int code)
{
	struct ctl_t *ptr = ctl;
	for(; (ptr->code != code) && (ptr < &ctl[sizeof(ctl) / sizeof(struct ctl_t) - 1]); ptr++);
	return ptr;
}

void action(const int code, const int val)
{
	struct ctl_t *ptr = get_ctl(code);

	if (ptr->func != NULL)
	{
		ptr->val = val;
		ptr->func(ptr->side, val);
	}
}

/* === GAMEPAD === */

static void interrupt_handler(int sig)
{
	stop = 1;
}

static int usage(void)
{
	printf("pi-tank [--rot] [--mirr] [--smart] /dev/input/eventX\n");
	return EXIT_FAILURE;
}

static int print_events(int fd)
{
	struct input_event ev[64];
	int i, rd;
	fd_set rdfs;

	FD_ZERO(&rdfs);
	FD_SET(fd, &rdfs);

	h_bridge_export(LEFT);
	h_bridge_export(RIGHT);

	while (!stop) {
		select(fd + 1, &rdfs, NULL, NULL, NULL);
		if (stop)
			break;
		rd = read(fd, ev, sizeof(ev));

		if (rd < (int) sizeof(struct input_event)) {
			printf("expected %d bytes, got %d\n", (int) sizeof(struct input_event), rd);
			perror("\npi-tank: error reading");
			return 1;
		}

		for (i = 0; i < rd / sizeof(struct input_event); i++) {
			int type = ev[i].type;
			int code = ev[i].code;
			int value = ev[i].value;

			if (type == EV_ABS || type == EV_KEY){

				if (debug_flag) {
					if (type == EV_ABS) {
						printf("ABS %d=%d\n", code, value);
					}
					if (type == EV_KEY) {
						printf("KEY %d=%d\n", code, value);
					}
					fflush(stdout);
				}

				action(code, value);
			}
		}

	}

	h_bridge_unexport(LEFT);
	h_bridge_unexport(RIGHT);

	ioctl(fd, EVIOCGRAB, (void*)0);
	return EXIT_SUCCESS;
}

static int do_capture(const char *device)
{
	int fd;

	if (!device) {
		return usage();
	}

	if ((fd = open_try(device, O_RDONLY)) < 0) {
		return EXIT_FAILURE;
	}

	signal(SIGINT, interrupt_handler);
	signal(SIGTERM, interrupt_handler);

	return print_events(fd);
}

enum flags {
	F_DEBUG,
	F_SMART,
	F_ROT,
	F_MIRR,
	F_NEG,
};

static const struct option long_options[] = {
	{"debug", no_argument, &debug_flag , 1     },
	{"smart", no_argument, (int *)&mode, SMART },
	{"rot"  , no_argument, NULL        , F_ROT },
	{"mirr" , no_argument, NULL        , F_MIRR},
	{"neg"  , no_argument, NULL        , F_NEG },
	{0, },
};

int main (int argc, char **argv)
{
	const char *device = NULL;
	const char *keyname;
	const char *event_type;

	while (1) {
		int option_index = 0;
		int c = getopt_long(argc, argv, "", long_options, &option_index);
		if (c == -1)
			break;
		switch (c) {
		case 0:
			break;
		case F_ROT:
			swap(&pwm[LEFT].ch, &pwm[RIGHT].ch);
			swap(&gpio[LEFT][FORWARD].pin, &gpio[RIGHT][BACK].pin);
			swap(&gpio[LEFT][BACK].pin, &gpio[RIGHT][FORWARD].pin);
			break;
		case F_MIRR:
			swap(&pwm[LEFT].ch, &pwm[RIGHT].ch);
			break;
		case F_NEG:
			swap(&level[HI], &level[LOW]);
			break;
		default:
			return usage();
		}
	}

	if (optind < argc)
		device = argv[optind++];

	return do_capture(device);
}
