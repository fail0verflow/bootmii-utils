#!/bin/sh

# Copyright (C) 2007 Segher Boessenkool <segher@kernel.crashing.org>
# Copyright (C) 2009 Hector Martin "marcan" <hector@marcansoft.com>
# Copyright (C) 2009 Andre Heider "dhewg" <dhewg@wiibrew.org>
# Copyright (C) 2022 Shiz <hi@shiz.me>

# Released under the terms of the GNU GPL, version 2
SCRIPTDIR=`dirname $PWD/$0`

BINUTILS_VER=2.39
BINUTILS_DIR="binutils-$BINUTILS_VER"
BINUTILS_TARBALL="binutils-${BINUTILS_VER}.tar.bz2"
BINUTILS_URI="http://ftp.gnu.org/gnu/binutils/$BINUTILS_TARBALL"

GMP_VER=6.2.1
GMP_DIR="gmp-$GMP_VER"
GMP_TARBALL="gmp-$GMP_VER.tar.bz2"
GMP_URI="http://ftp.gnu.org/gnu/gmp/$GMP_TARBALL"

MPFR_VER=4.1.0
MPFR_DIR="mpfr-$MPFR_VER"
MPFR_TARBALL="mpfr-$MPFR_VER.tar.bz2"
MPFR_URI="http://ftp.gnu.org/gnu/mpfr/$MPFR_TARBALL"

MPC_VER=1.2.1
MPC_DIR=mpc-$MPC_VER
MPC_TARBALL="mpc-$MPC_VER.tar.gz"
MPC_URI="http://ftp.gnu.org/gnu/mpc/$MPC_TARBALL"

GCC_VER=11.3.0
GCC_DIR="gcc-$GCC_VER"
GCC_TARBALL="gcc-$GCC_VER.tar.gz"
GCC_URI="http://ftp.gnu.org/gnu/gcc/gcc-$GCC_VER/$GCC_TARBALL"

ARM_TARGET=armeb-none-eabi
POWERPC_TARGET=powerpc-none-elf

if [ -z $MAKEOPTS ]; then
	MAKEOPTS=-j3
fi

# End of configuration section.

case `uname -s` in
	*BSD*)
		MAKE=gmake
		;;
	*)
		MAKE=make
esac

die() {
	echo "$@"
	exit 1
}

download() {
	DL=1
	if [ -f "$1" ]; then
		echo "Testing $1..."
		tar tf "$1" >/dev/null 2>&1 && DL=0
	fi

	if [ $DL -eq 1 ]; then
		echo "Downloading $2..."
		if command -v wget >/dev/null 2>&1; then
			wget "$2" -c -O "$1" || die "Could not download $2 using wget"
		elif command -v curl >/dev/null 2>&1; then
			curl -o "$1" -fL "$2" || die "Could not download $2 using cURL"
		else
			die "Could not download $2 (no wget or cURL)"
		fi
	fi
}

extract() {
	echo "Extracting $2..."
	tar xf "$2" -C "$1" || die "Could not unpack $2"
}


cleansrc() {
	[ -e "$1/src/$BINUTILS_DIR" ] && rm -rf "$1/src/$BINUTILS_DIR"
	[ -e "$1/src/$GCC_DIR" ] && rm -rf "$1/src/$GCC_DIR"
}

cleanbuild() {
	[ -e "$(printf "%s\n" "$1/var/build/$BINUTILS_DIR"-* | head -n 1)" ] && rm -rf "$1/var/build/$BINUTILS_DIR"-*
	[ -e "$(printf "%s\n" "$1/var/build/$GCC_DIR"-* | head -n 1)" ] && rm -rf "$1/var/build/$GCC_DIR"-*
}

prepsrc() {
	mkdir -p "$1/var/cache" || die "Could not create cache directory $1/var/cache"

	download "$1/var/cache/$BINUTILS_TARBALL" "$BINUTILS_URI"
	download "$1/var/cache/$GMP_TARBALL" "$GMP_URI"
	download "$1/var/cache/$MPFR_TARBALL" "$MPFR_URI"
	download "$1/var/cache/$MPC_TARBALL" "$MPC_URI"
	download "$1/var/cache/$GCC_TARBALL" "$GCC_URI"

	cleansrc "$1"

	mkdir -p "$1/src" || die "Could not create source directory $1/src"

	extract "$1/src" "$1/var/cache/$BINUTILS_TARBALL"
	extract "$1/src" "$1/var/cache/$GCC_TARBALL"
	patch -d "$1"/src/gcc-* -u -p1 -i $SCRIPTDIR/gcc-11.3.0.patch || die "Error applying GCC patch"

	extract "$1/src/$GCC_DIR" "$1/var/cache/$GMP_TARBALL"
	mv "$1/src/$GCC_DIR/$GMP_DIR" "$1/src/$GCC_DIR/gmp" || die "Error renaming $GMP_DIR -> gmp"
	extract "$1/src/$GCC_DIR" "$1/var/cache/$MPFR_TARBALL"
	mv "$1/src/$GCC_DIR/$MPFR_DIR" "$1/src/$GCC_DIR/mpfr" || die "Error renaming $MPFR_DIR -> mpfr"
	extract "$1/src/$GCC_DIR" "$1/var/cache/$MPC_TARBALL"
	mv "$1/src/$GCC_DIR/$MPC_DIR" "$1/src/$GCC_DIR/mpc" || die "Error renaming $MPC_DIR -> mpc"
}

buildbinutils() {
	(
		export PATH="$1/bin:$PATH"
		mkdir -p "$1/var/build/$BINUTILS_DIR-$2"
		cd "$1/var/build/$BINUTILS_DIR-$2" && \
		"$1/src/$BINUTILS_DIR/configure" --target="$2" \
			--prefix=$WIIDEV --disable-nls --disable-werror \
			--disable-multilib && \
		nice $MAKE $MAKEOPTS && \
		$MAKE install
	) || die "Error building binutils for target $2"
}

buildgcc() {
	(
		export PATH="$1/bin:$PATH"
		mkdir -p "$1/var/build/$GCC_DIR-$2"
		cd "$1/var/build/$GCC_DIR-$2" && \
		"$1/src/$GCC_DIR/configure" --target="$2" --enable-targets=all \
			--prefix=$WIIDEV --disable-multilib \
			--enable-languages=c --without-headers \
			--disable-nls --disable-threads --disable-shared \
			--disable-libmudflap --disable-libssp --disable-libgomp \
			--disable-decimal-float \
			--enable-checking=release \
			CFLAGS='-fgnu89-inline -g -O2' && \
		nice $MAKE $MAKEOPTS && \
		$MAKE install
	) || die "Error building gcc for target $2"
}


build() {
	cleanbuild "$1"
	echo "******* Building $2 binutils"
	[ -f "$1/bin/$2-ld" ] || buildbinutils "$1" "$2"
	echo "******* Building $2 GCC"
	[ -f "$1/bin/$2-gcc" ] || buildgcc "$1" "$2"
	echo "******* $2 toolchain built and installed"
}

if [ -z "$WIIDEV" ]; then
	die "Please set WIIDEV in your environment."
fi

BUILDTYPE="$1"
case $BUILDTYPE in
	arm)
		prepsrc "$WIIDEV"
		build "$WIIDEV" $ARM_TARGET
		;;
	powerpc)
		prepsrc "$WIIDEV"
		build "$WIIDEV" $POWERPC_TARGET
		;;
	both)
		prepsrc "$WIIDEV"
		build "$WIIDEV" $ARM_TARGET
		build "$WIIDEV" $POWERPC_TARGET
		cleanbuild "$WIIDEV"
		cleansrc "$WIIDEV"
		;;
	clean)
		cleanbuild "$WIIDEV"
		cleansrc "$WIIDEV"
		;;
	"")
		die "Please specify build type (arm/powerpc/both/clean)"
		;;
	*)
		die "Unknown build type $BUILDTYPE"
		;;
esac
