currently known working on PowerKVM:

$ { echo '#!/bin/sh'; echo 'echo HELLO WORLD'; } > user-data
$ cloud-localds seed.img user-data

## usb=off is required
## -net nic and -drive get default (ibmveth and ibmvscsi) drivers
$ qemu-system-ppc64 -machine pseries,accel=kvm,usb=off -m 1G \
   -name foo -M pseries \
   -device spapr-vscsi \
   -net nic -net user \
   -display none -nographic \
   -drive file=disk1.img \
   -kernel "$1" ${2:+-initrd "$2"} \
   -append "root=/dev/sda console=hvc0"

Also known working is adding 'blank.img' as a '-drive'.


What is not working is virtio.  I have not successfully gotten virtio network
or virtio disk working.
