#USE_LIBFTDI = 1

CFLAGS = -Wall -W -Os -g
TARGET = bootmii
OBJS = gecko.o main.o
LIBS =

NOMAPFILE = 1

ifeq ($(USE_LIBFTDI),1)
CFLAGS += -DUSE_LIBFTDI
LIBS += -lftdi
endif

include ../common.mk

install: all
	install -m 755 $(TARGET) $(WIIDEV)/bin

