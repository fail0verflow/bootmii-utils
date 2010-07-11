/*
 *  Copyright (C) 2008 dhewg, #wiidev efnet
 *
 *  this file is part of geckoloader
 *  http://wiibrew.org/index.php?title=Geckoloader
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

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

#include "gecko.h"

#ifndef O_BINARY
#define O_BINARY 0
#endif

#define BOOTMII_CLIENT_VERSION "v0.1"
#define MAX_BINARY_SIZE (20 * 1024 *1024)

#define CMD_NONE 0
#define CMD_UPLOAD_ARM 1
#define CMD_UPLOAD_PPC 2

const char *envvar = "USBGECKODEVICE";

#ifndef __WIN32__
#ifdef __APPLE__
char *default_tty = "/dev/tty.usbserial-GECKUSB0";
#else
char *default_tty = "/dev/ttyUSB0";
#endif
#else
char *default_tty = NULL;
#endif

void usage(const char *appname) {
	fprintf(stderr, "usage: %s <command> <file>\n", appname);
	fprintf(stderr, "commands: -a: upload ARM binary\n");
	fprintf(stderr, "          -p: upload PPC binary\n");
	exit(EXIT_FAILURE);
}

int main(int argc, char **argv) {
	int cmd, fd;
	struct stat st;
	char *tty = NULL;
	unsigned char buf4[4];
	unsigned char *buf, *p;
	off_t fsize, block;

	printf("bootmii client " BOOTMII_CLIENT_VERSION "\n"
			"coded by dhewg, #wiidev efnet\n\n");

	if (argc < 2)
		usage(argv[0]);

	cmd = CMD_NONE;
	if (!strcmp(argv[1], "-a"))
		cmd = CMD_UPLOAD_ARM;
	else if (!strcmp(argv[1], "-p"))
		cmd = CMD_UPLOAD_PPC;

	if (cmd == CMD_NONE)
		usage(argv[0]);
	
#ifndef USE_LIBFTDI
	tty = getenv(envvar);
	if (!tty)
		tty = default_tty;

	if (tty && stat(tty, &st))
		tty = NULL;

	if (!tty) {
		fprintf(stderr, "please set the environment variable %s to "
				"your usbgecko "
#ifndef __WIN32__
				"tty device (eg \"/dev/ttyUSB0\")"
#else
				"COM port (eg \"COM3\")"
#endif
				"\n", envvar);
		exit(EXIT_FAILURE);
	}

	printf("using %s\n", tty);
#endif

	fd = open(argv[2], O_RDONLY | O_BINARY);
	if (fd < 0) {
		perror("error opening the device");
		exit(EXIT_FAILURE);
	}

	if (fstat(fd, &st)) {
		close(fd);
		perror("error stat'ing the file");
		exit(EXIT_FAILURE);
	}
	fsize = st.st_size;

	if (fsize < 1 || fsize > MAX_BINARY_SIZE) {
		close(fd);
		fprintf(stderr, "error: invalid file size\n");
		exit(EXIT_FAILURE);
	}

	buf = malloc(fsize);
	if (!buf) {
		close(fd);
		fprintf(stderr, "out of memory\n");
		exit(EXIT_FAILURE);
	}

	if (read(fd, buf, fsize) != fsize) {
		close(fd);
		free(buf);
		perror("error reading the file");
		exit(EXIT_FAILURE);
	}
	close (fd);

	if (gecko_open(tty)) {
		free(buf);
		fprintf(stderr, "unable to open the device\n");
		exit(EXIT_FAILURE);
	}

	switch (cmd) {
	case CMD_UPLOAD_ARM:
		printf("sending ARM upload request\n");
		buf4[0] = 'B';
		buf4[1] = 'A';
		buf4[2] = 'R';
		buf4[3] = 'M';
		break;
	case CMD_UPLOAD_PPC:
		printf("sending PPC upload request\n");
		buf4[0] = 'B';
		buf4[1] = 'P';
		buf4[2] = 'P';
		buf4[3] = 'C';
		break;
	default:
		free(buf);
		fprintf(stderr, "internal error\n");
		exit(EXIT_FAILURE);
	}

	if (gecko_write(buf4, 4)) {
		free(buf);
		gecko_close();
		exit(EXIT_FAILURE);
	}

	buf4[0] = (fsize >> 24) & 0xff;
	buf4[1] = (fsize >> 16) & 0xff;
	buf4[2] = (fsize >> 8) & 0xff;
	buf4[3] = fsize & 0xff;

	printf("sending file size (%u bytes)\n", (unsigned int) fsize);

	if (gecko_write(buf4, 4)) {
		free(buf);
		gecko_close();
		fprintf(stderr, "error sending data\n");
		exit(EXIT_FAILURE);
	}

	printf("sending data");
	fflush(stdout);

	p = buf;
	while (fsize > 0) {
		block = fsize;
		if (block > 63488)
			block = 63488;
		fsize -= block;

		if (gecko_write(p, block)) {
			fprintf(stderr, "error sending block\n");
			break;
		}
		p += block;

		printf(".");
		fflush(stdout);

		if (fsize == 0)
			printf("\n");
	}

	printf("done.\n");

	free(buf);
	gecko_close();

	return 0;
}

