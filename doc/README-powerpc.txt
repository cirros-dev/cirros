
CirrOS PowerPC images
=====================

 * Use the build-release script w/ daily option
   $ export ARCHES="ppc64le powerpc ppc64"; ./bin/build-release daily

   This will build rootfs, grab kernels and grub, install grub w/ modules on
   prep partition, and bundle image. The *-disk.img is a qcow2 bootable image
   and contains a grub2 installed on a PreP Boot partition.

 * Quick test
   $ img=cirros-{YYMMDD}-ppc64le-disk.img;
   $ { echo '#!/bin/sh'; echo 'echo HELLO WORLD'; } > user-data
   $ cloud-localds seed.img user-data
   $ qemu-system-ppc64le -echr 0x05 \
       -machine pseries-2.5,accel=kvm,usb=off -cpu host -m 512 \
       -display none -nographic \
       -net nic -net user \
       -drive "file=$img" -drive "file=$seed.img"

 * Add the image to OpenStack
   $ openstack image create --disk-format qcow2 --container-format bare \
     --public --property os_command_line="console=hvc0 console=tty0" \
     --property arch=ppc64le --property hypervisor_type=kvm \
     --property hw_disk_bus=scsi --property hw_scsi_model=virtio-scsi \
     --property hw_cdrom_bus=scsi cirros_qcow2 \
     < "$img"

 NOTE: ppc64le/ppc64 images have been tested extensively on the OpenStack CI
 using the daily builds - http://download.cirros-cloud.net/daily/ - and works
 well with virtio drivers (network and disk).

Currently known working on PowerKVM:

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

Historical NOTE(smoser) about virtio:
What is not working is virtio.  I have not successfully gotten virtio network
or virtio disk working.
