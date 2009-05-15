CFLAGS = -Wall -W -Os -g
TARGET = bootmii
OBJS = gecko.o main.o

NOMAPFILE = 1

include ../common.mk

install: all
	install -m 755 $(TARGET) $(WIIDEV)/bin

