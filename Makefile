pi-tank: pi-tank.c
	gcc -o pi-tank pi-tank.c

install: pi-tank
	cp pi-tank /usr/bin/
	chmod 666 /usr/bin/pi-tank
	cp 99-tank.rules /usr/lib/udev/rules.d/

uninstall:
	rm -f /usr/bin/pi-tank /usr/lib/udev/rules.d/99-tank.rules
