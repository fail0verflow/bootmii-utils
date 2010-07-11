#!/bin/sh

# Copyright (C) 2007 Segher Boessenkool <segher@kernel.crashing.org>
# Copyright (C) 2009 Hector Martin "marcan" <hector@marcansoft.com>
# Copyright (C) 2009 Andre Heider "dhewg" <dhewg@wiibrew.org>

# Released under the terms of the GNU GPL, version 2
SCRIPTDIR=`dirname $PWD/$0`

BINUTILS_VER=2.20
BINUTILS_DIR="binutils-$BINUTILS_VER"
BINUTILS_TARBALL="binutils-$BINUTILS_VER.tar.bz2"
BINUTILS_URI="http://ftp.gnu.org/gnu/binutils/$BINUTILS_TARBALL"

GMP_VER=5.0.1
GMP_DIR="gmp-$GMP_VER"
GMP_TARBALL="gmp-$GMP_VER.tar.bz2"
GMP_URI="http://ftp.gnu.org/gnu/gmp/$GMP_TARBALL"

MPFR_VER=3.0.0
MPFR_DIR="mpfr-$MPFR_VER"
MPFR_TARBALL="mpfr-$MPFR_VER.tar.bz2"
MPFR_URI="http://www.mpfr.org/mpfr-current/$MPFR_TARBALL"

GCC_VER=4.4.4
GCC_DIR="gcc-$GCC_VER"
GCC_CORE_TARBALL="gcc-core-$GCC_VER.tar.bz2"
GCC_CORE_URI="http://ftp.gnu.org/gnu/gcc/gcc-$GCC_VER/$GCC_CORE_TARBALL"

BUILDTYPE=$1

ARM_TARGET=armeb-eabi
POWERPC_TARGET=powerpc-elf

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

export PATH=$WIIDEV/bin:$PATH

die() {
	echo $@
	exit 1
}

cleansrc() {
	[ -e $WIIDEV/$BINUTILS_DIR ] && rm -rf $WIIDEV/$BINUTILS_DIR
	[ -e $WIIDEV/$GCC_DIR ] && rm -rf $WIIDEV/$GCC_DIR
}

cleanbuild() {
	[ -e $WIIDEV/build_binutils ] && rm -rf $WIIDEV/build_binutils
	[ -e $WIIDEV/build_gcc ] && rm -rf $WIIDEV/build_gcc
}

download() {
	DL=1
	if [ -f "$WIIDEV/$2" ]; then
		echo "Testing $2..."
		tar tjf "$WIIDEV/$2" >/dev/null 2>&1 && DL=0
	fi

	if [ $DL -eq 1 ]; then
		echo "Downloading $2..."
		wget "$1" -c -O "$WIIDEV/$2" || die "Could not download $2"
	fi
}

extract() {
	echo "Extracting $1..."
	tar xjf "$WIIDEV/$1" -C "$2" || die "Error unpacking $1"
}

makedirs() {
	mkdir -p $WIIDEV/build_binutils || die "Error making binutils build directory $WIIDEV/build_binutils"
	mkdir -p $WIIDEV/build_gcc || die "Error making gcc build directory $WIIDEV/build_gcc"
}

buildbinutils() {
	TARGET=$1
	(
		cd $WIIDEV/build_binutils && \
		$WIIDEV/$BINUTILS_DIR/configure --target=$TARGET \
			--prefix=$WIIDEV --disable-werror --disable-multilib && \
		nice $MAKE $MAKEOPTS && \
		$MAKE install
	) || die "Error building binutils for target $TARGET"
}

buildgcc() {
	TARGET=$1
	(
		cd $WIIDEV/build_gcc && \
		$WIIDEV/$GCC_DIR/configure --target=$TARGET --enable-targets=all \
			--prefix=$WIIDEV --disable-multilib \
			--enable-languages=c --without-headers \
			--disable-nls --disable-threads --disable-shared \
			--disable-libmudflap --disable-libssp --disable-libgomp \
			--disable-decimal-float \
			--enable-checking=release && \
		nice $MAKE $MAKEOPTS && \
		$MAKE install
	) || die "Error building binutils for target $TARGET"
}

buildarm() {
	cleanbuild
	makedirs
	echo "******* Building ARM binutils"
	buildbinutils $ARM_TARGET
	echo "******* Building ARM GCC"
	buildgcc $ARM_TARGET
	echo "******* ARM toolchain built and installed"
}

buildpowerpc() {
	cleanbuild
	makedirs
	echo "******* Building PowerPC binutils"
	buildbinutils $POWERPC_TARGET
	echo "******* Building PowerPC GCC"
	buildgcc $POWERPC_TARGET
	echo "******* PowerPC toolchain built and installed"
}

if [ -z "$WIIDEV" ]; then
	die "Please set WIIDEV in your environment."
fi

case $BUILDTYPE in
	arm|powerpc|both|clean)	;;
	"")
		die "Please specify build type (arm/powerpc/both/clean)"
		;;
	*)
		die "Unknown build type $BUILDTYPE"
		;;
esac

if [ "$BUILDTYPE" = "clean" ]; then
	cleanbuild
	cleansrc
	exit 0
fi

download "$BINUTILS_URI" "$BINUTILS_TARBALL"
download "$GMP_URI" "$GMP_TARBALL"
download "$MPFR_URI" "$MPFR_TARBALL"
download "$GCC_CORE_URI" "$GCC_CORE_TARBALL"

cleansrc

extract "$BINUTILS_TARBALL" "$WIIDEV"
extract "$GCC_CORE_TARBALL" "$WIIDEV"
extract "$GMP_TARBALL" "$WIIDEV/$GCC_DIR"
extract "$MPFR_TARBALL" "$WIIDEV/$GCC_DIR"

# in-tree gmp and mpfr
mv "$WIIDEV/$GCC_DIR/$GMP_DIR" "$WIIDEV/$GCC_DIR/gmp" || die "Error renaming $GMP_DIR -> gmp"
mv "$WIIDEV/$GCC_DIR/$MPFR_DIR" "$WIIDEV/$GCC_DIR/mpfr" || die "Error renaming $MPFR_DIR -> mpfr"

# http://gcc.gnu.org/bugzilla/show_bug.cgi?id=42424
# http://gcc.gnu.org/bugzilla/show_bug.cgi?id=44455
patch -d $WIIDEV/$GCC_DIR -u -i $SCRIPTDIR/gcc.patch || die "Error applying gcc patch"

case $BUILDTYPE in
	arm)		buildarm ;;
	powerpc)	buildpowerpc ;;
	both)		buildarm ; buildpowerpc; cleanbuild; cleansrc ;;
esac

