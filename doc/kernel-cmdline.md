# Cirros Kernel Command line

Cirros supports customization from the kernel command line.
Kernel command line values override defaults in the image or initramfs.

## Parameters

 * `root=` - string, default="LABEL=cirros-rootfs"

    The default behavior is to search for a filesystem with a label 'cirros-rootfs' and use it for the root filesystem. Other supported values:

     * `root=LABEL=<name>` - search for filesystem with a label '<name>'
     * `root=UUID=<uuid>` - search for filesystem with a uuid '<uuid>'
     * `root=ramdisk` | `root=none` - run entirely out of the initramfs.

 * `init=<PROGRAM>` - string, default=/sbin/init. PROGRAM will be executed as init.

 * `dslist=ds1[,ds2[,ds3...]]` - string, default="".  Search through the listed datasources.  If value is empty (default) then read `/etc/cirros-init/config` for the list.

   Useful value is `dslist=none` which will use the 'none' datasource.

 * `debug-initramfs` - boolean, default=false.  Drop into a shell to debug initramfs early in the initramfs.
 * `verbose` or `verbose=INT`.  increase verbosity / debut output of init.
