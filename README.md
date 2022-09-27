The CirrOS project provides linux disk and kernel/initramfs images.
The images are well suited for testing as they are small and boot
quickly.  Please note that:

 * **Images are provided for test only**.  They should not be used in production.
 * **Images have well known login information**.  Users can log in with 'cirros:letsgocubs' locally or remotely and have passwordless sudo access to root.

CirrOS images have useful tools and function for debugging or developing cloud infrastructure. Supported architectures are:

 * aarch64 (64-bit Armv8 often called arm64)
 * arm (32-bit Armv7)
 * ppc64le (64-bit Power little endian)
 * x86_64 (64-bit x86 often called amd64)

Resulting images can be booted using QEMU. Several ways of booting are provided:

 * UEFI (aarch64, arm, x86_64)
 * BIOS (x86_64)
 * OpenFirmware (ppc64le)
 * direct kernel + initrd (all architectures)

# Build instructions

The following works on Ubuntu 22.04 LTS, running on x86_64. Native building for other architectures is not recommended. Support for building under other distributions is limited and not tested.

## Clone sources

 * git clone https://github.com/cirros-dev/cirros.git
   or
 * git clone git@github.com:cirros-dev/cirros.git

## Install required software

To get build going we need some packages installed. If you use Ubuntu 22.04 LTS then all you need to do is:

 * cd cirros

 * get the build dependencies:
```bash
   $ ./bin/system-setup
```

If you use other distribution then please check what script does and install required components using methods preferred by your distribution.


## Short version

Once you fetched source code all you have to do something like:

 * cd cirros
 * bin/build-release daily

If you want to build for only a subset of supported architectures, use
the ARCHES variable like:

* ARCHES=aarch64,x86_64,arm bin/build-release daily

Resulting images will be present in ../build-dYYMMDD/release directory.


## Long, detailed version

To use it, you would do something like:

 * download buildroot and setup environment
```bash
   $ br_ver="2022.02.4"
   $ mkdir -p ../download
   $ ln -snf ../download download
   $ ( cd download && wget http://buildroot.uclibc.org/downloads/buildroot-${br_ver}.tar.gz )
   $ tar -xvf download/buildroot-${br_ver}.tar.gz
   $ ln -snf buildroot-${br_ver} buildroot
```      

 * optionally update src/etc/ssl/certs/ca-certificates.crt file. This is not required, but can be done to make sure its up to date.

```bash
   $ wget https://github.com/mozilla/gecko-dev/raw/master/security/nss/lib/ckfw/builtins/certdata.txt -O certdata.txt
   $ ./bin/mkcabundle <certdata.txt > src/etc/ssl/certs/ca-certificates.crt
```      

 * apply any local cirros patches to buildroot
```bash
   ( cd buildroot && QUILT_PATCHES=$PWD/../patches-buildroot quilt push -a )
```      

 * download the buildroot sources
```bash
   $ ARCH=x86_64
   $ make ARCH=$ARCH br-source
```      

 * Build buildroot for a given arch (ARCH should be set to 'x86_64', 'arm', 'aarch64' or 'ppc64le')
```bash
   $ make ARCH=$ARCH OUT_D=$PWD/output/$ARCH
```      

This will do a full buildroot build, which will take a while. The output that CirrOS is interested in is output/i386/rootfs.tar. That file is the full buildroot filesystem, and is used as input for subsequent steps here.

 * Download a kernel to use. The kernel input to bundle must be in deb format. The ubuntu '-virtual'  kernel is used as a starting point. Version can be taken from https://launchpad.net/ubuntu/+source/linux page.

```bash
   $ kver="5.15.0-48.54"
   $ ./bin/grab-kernels "$kver" $ARCH
```      

 * Download EFI grub to use (aarch64, arm, x86_64 only). The grub-efi input to bundle will be in tar.gz format. Version can be taken from https://launchpad.net/ubuntu/+source/grub2 page.
```bash
   $ gver="2.06-2ubuntu7"
   $ ./bin/grab-grub-efi "$gver" $ARCH
```      

 * build disk images using bin/bundle
```bash
   $ sudo ./bin/bundle -v --arch=$ARCH output/$ARCH/rootfs.tar \
      download/kernel-$ARCH.tar.gz download/grub-efi-$ARCH.tar.gz output/$ARCH/images
```      

## testing images

We provide simple script to test resulting image. You run it this way:

```bash
   $ RELEASE_DIR=$PWD/../build-*/release IMG=$PWD/../build-*/release/cirros-*-x86_64-disk.img bin/test-boot
```      

Note: "RELEASE_DIR" variable is required only for aarch64 and arm images.

Once image boots you can login with 'cirros' user using 'gocubsgo' as password. Root access is granted with 'sudo' call.
