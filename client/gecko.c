/*
 *  Copyright (C) 2008 dhewg, #wiidev efnet
 *
 *  this file is part of wiifuse
 *  http://wiibrew.org/index.php?title=Wiifuse
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

#ifdef USE_LIBFTDI
#include "ftdi.h"
#else
#ifndef __WIN32__
#include <termios.h>
#else
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif
#endif

#include "gecko.h"

#define FTDI_PACKET_SIZE 3968

#ifdef USE_LIBFTDI
#define DEFAULT_FTDI_VID 0x0403
#define DEFAULT_FTDI_PID 0x6001

struct ftdi_context ftdi_ctx;
#else
#ifndef __WIN32__
static int fd_gecko = -1;
#else
static HANDLE handle_gecko = NULL;
#endif
#endif

int gecko_open(const char *dev) {
#ifdef USE_LIBFTDI
	(void) dev;

	int err;

	ftdi_init(&ftdi_ctx);

	err = ftdi_usb_open(&ftdi_ctx, DEFAULT_FTDI_VID, DEFAULT_FTDI_PID);
	if (err < 0) {
		fprintf(stderr, "ftdi_usb_open_desc failed: %d (%s)\n",
				err, ftdi_get_error_string(&ftdi_ctx));
		return 1;
	}
#else
#ifndef __WIN32__
	struct termios newtio;

	fd_gecko = open(dev, O_RDWR | O_NOCTTY | O_SYNC | O_NONBLOCK);

	if (fd_gecko == -1) {
		perror("gecko_open");
		return 1;
	}

	if (fcntl(fd_gecko, F_SETFL, 0)) {
		perror("F_SETFL on serial port");
		return 1;
	}

	if (tcgetattr(fd_gecko, &newtio)) {
		perror("tcgetattr");
		return 1;
	}

	cfmakeraw(&newtio);

	newtio.c_cflag |= CRTSCTS | CS8 | CLOCAL | CREAD;

	if (tcsetattr(fd_gecko, TCSANOW, &newtio)) {
		perror("tcsetattr");
		return 1;
	}
#else
	COMMTIMEOUTS timeouts;

	handle_gecko = CreateFile(dev, GENERIC_READ | GENERIC_WRITE, 0, 0,
								OPEN_EXISTING, 0, 0);

	GetCommTimeouts(handle_gecko, &timeouts);

	timeouts.ReadIntervalTimeout = MAXDWORD; 
	timeouts.ReadTotalTimeoutMultiplier = 0;
	timeouts.ReadTotalTimeoutConstant = 0;
	timeouts.WriteTotalTimeoutMultiplier = 0;
	timeouts.WriteTotalTimeoutConstant = 0;

	if (!SetCommTimeouts(handle_gecko, &timeouts)) {
		fprintf(stderr, "error setting timeouts on port\n");
		return 1;
	}

	if (!SetCommMask(handle_gecko, 0)) {
		fprintf(stderr, "error setting communications event mask\n");
		return 1;
	}
#endif
#endif

	gecko_flush();

	return 0;
}

void gecko_close() {
#ifdef USE_LIBFTDI
	ftdi_usb_close(&ftdi_ctx);
#else
#ifndef __WIN32__
	if (fd_gecko > 0)
		close(fd_gecko);
#else
	CloseHandle(handle_gecko);
#endif
#endif
}

void gecko_flush() {
#ifdef USE_LIBFTDI
	ftdi_usb_purge_buffers(&ftdi_ctx);
#else
#ifndef __WIN32__
	tcflush(fd_gecko, TCIOFLUSH);
#else
	PurgeComm(handle_gecko, PURGE_RXCLEAR | PURGE_TXCLEAR |
				PURGE_TXABORT | PURGE_RXABORT);
#endif
#endif
}

int gecko_read(void *buf, size_t count) {
	size_t left, chunk;
#ifndef __WIN32__
	ssize_t res;
#else
	DWORD res;
#endif

	left = count;
	while (left) {
		chunk = left;
		if (chunk > FTDI_PACKET_SIZE)
			chunk = FTDI_PACKET_SIZE;
#ifdef USE_LIBFTDI
		res = ftdi_read_data(&ftdi_ctx, buf, chunk);
		if (res < 1) {
			fprintf(stderr, "ftdi_read_data failed: %d (%s)\n",
					(int) res, ftdi_get_error_string(&ftdi_ctx));
			return 1;
		}
#else
#ifndef __WIN32__
		res = read(fd_gecko, buf, chunk);
		if (res < 1) {
			perror("gecko_read");
			return 1;
		}
#else
		if (!ReadFile(handle_gecko, buf, chunk, &res, NULL)) {
			fprintf(stderr, "gecko_read\n");
			return 1;
		}
#endif
#endif

		left -= res;
		buf += res;
	}

	return 0;
}

int gecko_write(const void *buf, size_t count) {
	size_t left, chunk;
#ifndef __WIN32__
	ssize_t res;
#else
	DWORD res;
#endif

	left = count;

	while (left) {
		chunk = left;
		if (chunk > FTDI_PACKET_SIZE)
			chunk = FTDI_PACKET_SIZE;

#ifdef USE_LIBFTDI
		res = ftdi_write_data(&ftdi_ctx, (unsigned char *)buf, chunk);
		if (res < 1) {
			fprintf(stderr, "ftdi_write_data failed: %d (%s)\n",
					(int) res, ftdi_get_error_string(&ftdi_ctx));
			return 1;
		}
#else
#ifndef __WIN32__
		res = write(fd_gecko, buf, count);
		if (res < 1) {
			perror("gecko_write");
			return 1;
		}
#else
		if (!WriteFile(handle_gecko, buf, chunk, &res, NULL)) {
			fprintf (stderr, "gecko_write\n");
			return 1;
		}
#endif
#endif

		left -= res;
		buf += res;

#if !defined(__WIN32__) && !defined(USE_LIBFTDI)
		// does this work with ftdi-sio?
		if (tcdrain(fd_gecko)) {
			perror ("gecko_drain");
			return 1;
		}
#endif
	}

	return 0;
}

