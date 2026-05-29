# CirrOS From Scratch: Developer Guide

This guide explains how the CirrOS project builds its images and how the
repository is organized for contributors.  It is written for readers who know
Linux in general, but who may be new to Buildroot, CirrOS's image assembly
scripts, or the small runtime that handles cloud metadata and user-data
(similar to, but much simpler than, cloud-init) included in the image.

The intended direction is similar to a small project-specific reference manual:
concepts are introduced before they are used, the build is explained from
scratch, and the CirrOS-specific programs and overlays are documented as part of
the system rather than treated as incidental scripts.

This is not a complete replacement for the Buildroot manual, the QEMU manual, or
cloud platform documentation.  When this guide describes Buildroot concepts, it
focuses on the subset needed to understand how CirrOS uses Buildroot.


## How to read this guide

The document is long because it is both a learning path and a reference.  New
contributors should read Parts I through IV first, then skim Part V before
making runtime or filesystem changes.  Parts VI through XI are more reference
oriented and can be read as needed.

```text
Part I      Orientation and mental model
Part II     Build host preparation and quick starts
Part III    Buildroot concepts used by CirrOS
Part IV     Full build-from-scratch walkthrough
Part V      CirrOS filesystem and boot/runtime flow
Part VI     CirrOS runtime program reference
Part VII    Image assembly and boot artifact reference
Part VIII   Architecture support reference
Part IX     Testing, CI, and release workflow
Part X      Maintenance workflows
Part XI     Troubleshooting and quick reference
```

Headings are intentionally not manually numbered.  Use the Markdown outline or
search for the referenced heading name when following cross-references.

Current repository caveats, including known stale documentation and support
status differences, are collected near the end in `Known inconsistencies and
stale areas`.  Read that section before broad cleanup or release work.

A practical first pass for new contributors is:

1. Read Parts I through IV to understand the build model.
2. Build x86_64 with the quick-start command in `Quick start build`.
3. Boot-test the result with `bin/test-boot` from `Quick start boot test`.
4. Read `bin/build-release` from top to bottom.
5. Read the top-level `Makefile`.
6. Inspect `conf/buildroot-x86_64.config` and `conf/busybox.config`.
7. Read Part V and then browse `src/etc/init.d/`, `src/sbin/`, and
   `src/lib/cirros/`.
8. Read `bin/bundle` and `bin/part2disk` when you need image assembly details;
   use `Image Assembly and Boot Artifacts` as the reference map.
9. Read `doc/cirros-init.txt` and `doc/kernel-cmdline.md` when working on boot
   or datasource behavior.
10. Read architecture-specific scripts and configs before touching multi-arch
    behavior.

CirrOS is small enough that reading the shell scripts is often the fastest way
to answer a question.  The main challenge is knowing which layer you are looking
at: Buildroot rootfs generation, CirrOS filesystem overlay, kernel/grub download
and repack, image bundling, boot testing, or release publication.

Existing focused docs remain useful as source material:

```text
README.md                  project overview and quick public entry point
doc/TESTING                historical release smoke-test categories
doc/cirros-init.txt        init/runtime details
doc/kernel-cmdline.md      kernel command-line options
doc/create-release.txt     historical publishing workflow
doc/RELEASE.txt            historical release artifact meanings
doc/README-powerpc.txt     historical PowerPC notes
doc/lxc-cli.txt            historical LXC recipe
doc/buildroot-upgrade.txt  Buildroot upgrade notes
doc/misc.txt               low-level iteration notes
```

Prefer this guide for current contributor workflow.  Use the older docs for
focused context, then verify commands against current scripts before treating
them as canonical.


# Part I - Orientation


## What CirrOS is

CirrOS provides small Linux disk images and kernel/initramfs artifacts for
cloud and virtualization testing.  The images are designed to boot quickly,
consume little space, and provide enough tools to debug cloud infrastructure.
They are useful for testing image upload, scheduling, networking, metadata
services, config-drive behavior, SSH access, and basic guest lifecycle
operations.

CirrOS is not intended to be a general-purpose Linux distribution.  It is not a
production image and should not be treated like one.

Important security properties:

- CirrOS images are for test use only.
- The default user and password are well known.
- The default user has passwordless `sudo` access.

Current image login information, based on the image files in this repository:

```text
user:     cirros
password: gocubsgo
```

The password is visible to users in `src/etc/issue`.  The `cirros` account is
created in `src/etc/passwd`, and the password hash in `src/etc/shadow` matches
`gocubsgo`.  If another document says a different password, treat that as stale
unless the image contents are changed too.


## The core mental model

A CirrOS image is built by combining four major inputs:

1. a small Buildroot-generated userspace root filesystem,
2. CirrOS-owned overlay files from `src/`,
3. externally downloaded Ubuntu kernel packages,
4. externally downloaded grub packages.

The terminology section below defines names such as Buildroot, BusyBox, rootfs
tarball, overlay, stage directory, release directory, and datasource.  The short
version is that Buildroot creates the base userspace, BusyBox supplies many core
utilities, and CirrOS overlays project-owned boot and cloud behavior on top.

The high-level flow is:

```text
Buildroot configuration + BusyBox configuration
        |
        v
Buildroot rootfs.tar
        |
        v
CirrOS src/ overlay + makedevs.list + fixup-fs
        |
        v
staged filesystem
        |
        +--> container rootfs artifacts
        |
        +--> kernel + selected modules + initramfs artifacts
        |
        +--> ext4 root partition image
                 |
                 v
             bootable qcow2 disk image
```

A common mistake is to think of CirrOS as a normal distribution packaging
workflow.  It is not.  Most normal software in the image comes from Buildroot
package selections.  CirrOS-specific behavior comes from the `src/` overlay and
shell scripts.  The kernel and bootloader are not built by Buildroot in this
repository; they are downloaded from Ubuntu packages and repacked by helper
scripts.

The most important build orchestration layers are:

```text
bin/build-release        full release-style orchestration
Makefile                 per-architecture Buildroot wrapper
bin/bundle               rootfs + overlay + kernel + grub image assembly
bin/part2disk            partition image -> bootable disk image
bin/test-boot            QEMU smoke test
```


## Repository map

High-level layout:

```text
.
├── bin/                  build, bundle, release, test, and helper scripts
├── conf/                 per-architecture Buildroot configs and BusyBox config
├── doc/                  older project notes and detailed reference material
├── lxd-meta/             LXD metadata template
├── patches-buildroot/    quilt patches applied to the unpacked Buildroot tree
├── src/                  filesystem overlay copied into the image
├── Makefile              per-architecture Buildroot driver
└── README.md             high-level user build instructions
```

Important generated or local working directories:

```text
download/     downloaded Buildroot, kernel, grub, and package sources
ccache/       compiler cache used by Buildroot builds
output/       default output for direct `make ARCH=...` builds
../build-*    default output location for `bin/build-release`
build-ci/     output location when `CI_BUILD=true`
```

Generated directories are useful when debugging, but they are not source of
truth.  Persistent project decisions normally live in:

```text
bin/
conf/
src/
patches-buildroot/
lxd-meta/
Makefile
.github/workflows/
```


## Terminology used in this guide

`ARCH`
: The CirrOS architecture name used by the build scripts, such as `x86_64`,
  `aarch64`, `arm`, `ppc64le`, or experimental `riscv64`.

Buildroot
: An embedded Linux build system that uses Kconfig-style configuration to select
  packages, build a small userspace, and emit root filesystem images.

Buildroot source tree
: The unpacked Buildroot release, for example `buildroot-2022.02.4/`, with a
  `buildroot` symlink pointing to it.

Buildroot output tree
: The per-build output directory passed to Buildroot with `O=...`.  It contains
  generated `.config`, build directories, target rootfs content, and image
  outputs.

BusyBox
: A compact implementation of many common Unix commands.  CirrOS uses BusyBox
  for `/bin/sh`, init, and many small utilities.

Skeleton
: The base filesystem layout Buildroot can use before packages are installed.
  Current CirrOS configs use Buildroot's default skeleton; the project-owned
  `src/` overlay is applied later by `bin/bundle`.

Rootfs tarball
: The Buildroot-produced tar archive of the target root filesystem.  CirrOS uses
  this as an intermediate artifact.

Overlay
: Files owned by CirrOS that are copied on top of the Buildroot rootfs.  In
  this repository, the main overlay is `src/`.

Stage directory
: The per-architecture directory where `bin/bundle` writes intermediate and
  bundle outputs before `bin/build-release` copies/compresses them into the
  final release directory.

Release directory
: The directory containing final user-facing artifacts for a build.

Datasource
: A source of instance metadata and user-data, such as NoCloud, OpenStack
  config-drive, or EC2-style metadata service.

NoCloud
: A local datasource format that reads metadata and user-data from a seed disk
  or seed directory, commonly used for QEMU smoke tests.

`cloud-localds`
: A `cloud-utils` command that creates NoCloud-compatible seed images.

UEC
: Ubuntu Enterprise Cloud, a historical OpenStack image packaging format still
  reflected in `*-uec.tar.gz` artifact names.

rc3 / runlevel 3
: The SysV-style BusyBox init runlevel used by CirrOS startup scripts.  Scripts
  named `S*` under `src/etc/rc3.d/` run at startup in lexical order.

PReP
: PowerPC Reference Platform, used here for the PowerPC boot partition type.

IEEE1275
: The OpenFirmware standard used by the PowerPC grub path.


With the project overview and vocabulary in place, Part II covers build host
setup and quick-start commands.


# Part II - Preparing for the Build


## Build host assumptions

The documented and tested build host is Ubuntu 22.04 LTS on x86_64.  Native
building on other architectures is not recommended.  Other Linux distributions
may work, but they are not the primary supported development path.

Install the standard build dependencies with:

```bash
./bin/system-setup
```

`bin/system-setup` is Ubuntu-oriented.  It installs tools such as compilers,
Buildroot dependencies, filesystem tools, grub tooling, QEMU image utilities,
`quilt` (a patch-management tool used for `patches-buildroot/`), `rsync`,
`wget`, compression tools, and GNU `parallel`.

Some boot-test dependencies are installed separately in CI and are also useful
locally:

```bash
sudo apt-get install cloud-utils qemu-system openbios-ppc
```

Why root privileges are needed:

- `bin/bundle` creates and mounts loopback filesystem images.
- `bin/build-release` therefore invokes `sudo ./bin/bundle` during the bundle
  stage.
- The Buildroot userspace build itself should not require root.


## External inputs

A full CirrOS build fetches several classes of external input:

```text
Buildroot release tarball       downloaded by bin/build-release
Buildroot package sources       downloaded by Buildroot into BR2_DL_DIR
Ubuntu Linux kernel packages    downloaded by bin/grab-kernels
Ubuntu grub packages            downloaded by bin/grab-grub-efi or bin/grab-grub-ieee
Mozilla CA certificate data     optionally converted by bin/mkcabundle
```

The build scripts keep downloaded content under `download/` by default.
Buildroot calls this shared source-cache location `BR2_DL_DIR`; CirrOS maps that
variable to `download/`.  CI also caches `download/` to avoid repeated
downloads.

The current top-level build defaults are in `bin/build-release`:

```bash
BR_VER="2022.02.4"
ARCHES="x86_64 arm aarch64 ppc64le riscv64"
KVER="5.15.0-117.127"
KVER_riscv64="5.15.0-1028.32"
GVER="2.06-2ubuntu7.1"
GVER_UNSIGNED="2.06-2ubuntu14.1"
```

For this guide, `riscv64` is considered experimental/work-in-progress even
though it appears in current build and CI defaults.


## Quick start build

For a first contributor build, build only x86_64:

```bash
./bin/system-setup
ARCHES="x86_64" bin/build-release daily
```

The `daily` argument creates a date-based version in `dYYMMDD` format.  For
example, on 2026-05-28 it creates `d260528`.  In normal non-CI mode, output is
written outside the repository under a directory like:

```text
../build-dYYMMDD/release/
```

The release directory contains final images and related artifacts.  Exact file
sets can change as the project evolves, but examples include:

```text
cirros-dYYMMDD-x86_64-minimal.qcow2
cirros-dYYMMDD-x86_64-full.qcow2
cirros-dYYMMDD-x86_64-rootfs.img.gz
cirros-dYYMMDD-x86_64-kernel
cirros-dYYMMDD-x86_64-initramfs
cirros-dYYMMDD-x86_64-lxc.tar.xz
cirros-dYYMMDD-x86_64-lxd.tar.xz
cirros-dYYMMDD-x86_64-uec.tar.gz
MD5SUMS
```

`uec.tar.gz` is UEC-style packaging; UEC means Ubuntu Enterprise Cloud, a
historical OpenStack image packaging format.  The complete canonical artifact
list is in `Artifact layout`.

Use whitespace-separated architecture lists:

```bash
ARCHES="x86_64 aarch64 arm" bin/build-release daily
```

The current scripts iterate over shell words in `ARCHES`.  Do not use a
comma-separated list unless the scripts are changed to support it.


## Quick start boot test

After building an image, use `bin/test-boot` for a QEMU smoke test.

From the repository checkout, run this x86_64 example, replacing `dYYMMDD` with
the version produced by your build, such as `d260528`:

```bash
repo=$PWD
scratch=$(mktemp -d)
cd "$scratch"
RELEASE_DIR="$repo/../build-d260528/release" \
IMG="$repo/../build-d260528/release/cirros-d260528-x86_64-full.qcow2" \
"$repo/bin/test-boot"
```

For a noninteractive CI-style test that powers off from inside the guest:

```bash
repo=$PWD
scratch=$(mktemp -d)
cd "$scratch"
POWEROFF=true \
RELEASE_DIR="$repo/../build-d260528/release" \
IMG="$repo/../build-d260528/release/cirros-d260528-x86_64-full.qcow2" \
"$repo/bin/test-boot"
```

The examples run `bin/test-boot` from a scratch directory using an absolute path
because the script writes transient `meta-data`, `user-data`, `seed.img`, and
`disk1.img` files in the current directory.

`bin/test-boot` is more than a generic QEMU command.  It also demonstrates a
minimal NoCloud datasource test via `cloud-localds`:

- writes `meta-data`,
- writes `user-data`,
- creates a seed image with `cloud-localds`,
- creates a qcow2 overlay on the disk image under test,
- attaches the seed as a second virtio drive,
- boots with serial console output.

When `POWEROFF=true`, the generated user-data installs an `/etc/rc.local` that
prints a message and powers the guest off.  That makes the script suitable for
CI smoke testing.  See `bin/test-boot behavior` for the full script behavior and
architecture-specific paths.


The quick start produces a working image.  Part III explains the Buildroot
layer so you can make changes with confidence.


# Part III - Buildroot Foundation


## Buildroot primer for CirrOS contributors

Buildroot is an embedded Linux build system.  It uses a Kconfig configuration
model, similar in style to the Linux kernel configuration system.  A Buildroot
configuration selects:

- target architecture,
- CPU and ABI details,
- toolchain mode and libc,
- packages,
- system options,
- root filesystem image formats.

CirrOS uses Buildroot as the engine that creates a small userspace root
filesystem.  Buildroot does not define all CirrOS behavior.  CirrOS-specific
boot, datasource, user-data, status, and cloud testing behavior is mostly in
`src/`.

A useful division of responsibility is:

```text
Buildroot config              selects normal packages and target system shape
BusyBox config                selects BusyBox applets and BusyBox behavior
src/ overlay                  adds CirrOS-specific files and scripts
makedevs.list                 fixes ownership, modes, and device nodes
fixup-fs                      adjusts final rootfs layout
Ubuntu kernel packages        provide kernel image and modules
Ubuntu grub packages          provide bootloader payloads
bin/bundle + bin/part2disk    assemble bootable artifacts
```


## Out-of-tree Buildroot builds

Buildroot supports out-of-tree builds with:

```bash
make O=<output-dir>
```

This keeps generated build state separate from the Buildroot source tree.  CirrOS
uses this pattern so the downloaded/unpacked Buildroot tree can remain mostly a
source input while each architecture gets its own output tree.

The top-level `Makefile` builds a command conceptually like:

```bash
cd buildroot && make \
  O="$BR_OUT_D" \
  BR2_DL_DIR="$DL_D" \
  BR2_CONFIG="$BR_OUT_D/.config" \
  BUSYBOX_CONFIG_FILE="$BR_OUT_D/busybox.config" \
  BR2_CCACHE_DIR="$BR2_CCACHE_DIR"
```

Important variables from the CirrOS `Makefile`:

```text
ARCH        CirrOS architecture name
BR_D        buildroot symlink/source directory
OUT_D       per-architecture CirrOS output directory
BR_OUT_D    Buildroot output tree under OUT_D
CONF_D      repository config directory
DL_D        shared download directory
SKEL_D      generated skeleton directory
```


## Buildroot configuration files

CirrOS stores full Buildroot configuration files under `conf/`:

```text
conf/buildroot-x86_64.config
conf/buildroot-arm.config
conf/buildroot-aarch64.config
conf/buildroot-ppc64le.config
conf/buildroot-riscv64.config
```

The shared BusyBox config is:

```text
conf/busybox.config
```

The `Makefile` maps `ARCH` to `conf/buildroot-$ARCH.config`.  For example:

```bash
make ARCH=x86_64 OUT_D="$PWD/output/x86_64"
```

uses:

```text
conf/buildroot-x86_64.config
```

Useful configuration targets:

```bash
# Edit the per-architecture Buildroot config and copy it back to conf/
make ARCH=x86_64 br-menuconfig

# Edit the shared BusyBox config and copy it back to conf/
make ARCH=x86_64 br-busybox-menuconfig
```

Prefer Buildroot's menuconfig flow for non-trivial package changes.  Buildroot
may select dependencies, remove unavailable options, or normalize symbol values.
Hand-editing config files can be useful for small, obvious changes, but always
build and inspect the resulting diff.


## Toolchains and libc choices

Buildroot can either build its own cross-compilation toolchain or use an
external toolchain.  CirrOS's current Buildroot configs use Buildroot-managed
toolchains.

This matters because toolchain and libc choices affect:

- available packages,
- binary compatibility,
- image size,
- architecture support,
- build time,
- subtle runtime behavior.

Most current CirrOS architecture configs use uClibc.  `ppc64le` uses musl.
Both uClibc and musl are lightweight C standard libraries used in embedded or
small-system builds; they are alternatives to the larger glibc used by many
general-purpose Linux distributions.  Do not assume all architectures have
identical libc behavior or package support.

When updating Buildroot, enabling packages, or adding architecture support,
check the relevant `conf/buildroot-$ARCH.config` rather than assuming x86_64
behavior generalizes.


## Package selection principles

A package addition normally belongs in `conf/buildroot-$ARCH.config`, not in
`src/`.  Use `src/` for CirrOS-owned scripts, configuration, and static files.

CirrOS deliberately contains a small package set.  The image should remain
small, quick to boot, and predictable.  Packages should serve cloud and
virtualization testing use cases rather than turning CirrOS into a general
purpose distribution.

Examples of package categories present in the Buildroot configs include:

- BusyBox and basic shell utilities,
- SSH server support via dropbear,
- DHCP client support,
- TLS and HTTP tools such as OpenSSL and curl,
- filesystem tools such as e2fsprogs and resize utilities,
- networking diagnostics such as ping, traceroute, tcpdump, and related tools,
- `sudo`,
- selected util-linux components,
- selected performance or debugging tools where supported.

Before adding a package, ask:

- Does it help test or debug cloud infrastructure?
- Is it needed on every architecture?
- What is the size impact?
- Does BusyBox already provide enough functionality?
- Does it depend on kernel, libc, or toolchain features that vary by
  architecture?
- Does it affect boot time or guest startup behavior?

## Buildroot rootfs.tar as an intermediate artifact

The primary Buildroot artifact CirrOS consumes is a root filesystem tarball.
The top-level `Makefile` copies Buildroot's `images/rootfs.tar` to:

```text
$OUT_D/rootfs.tar
```

This tarball is not the final CirrOS image.  It is an intermediate base
filesystem.  `bin/bundle` later combines it with the CirrOS overlay, kernel
modules, bootloader files, and image layout.

This separation is important for debugging:

- If a normal Buildroot package is missing, inspect the Buildroot config and the
  Buildroot rootfs tarball.
- If a CirrOS script or config file is missing, inspect `src/`, the overlay
  creation step, `makedevs.list`, and `fixup-fs`.
- If the disk image does not boot, inspect bundling, kernel, grub, initramfs,
  and `bin/part2disk`.


With the Buildroot foundation in place, Part IV walks through the full
`bin/build-release` run.


# Part IV - Building CirrOS from Scratch


## Full build walkthrough

This section walks through what happens when you run:

```bash
ARCHES="x86_64" bin/build-release daily
```

The same stages apply to multi-architecture builds; the per-architecture stages
repeat for each architecture in `ARCHES`.  The walkthrough headings are stage
numbers, not section numbers: Stage 1 is version setup, Stage 7 is bundling,
and Stage 9 is optional boot testing.


## Stage 1: version and output setup

`bin/build-release` requires a version argument.  The special argument `daily`
turns into a date-based version:

```text
dYYMMDD
```

For non-daily builds, the script expects the requested version to correspond to
a git tag.  This prevents accidental release builds from untagged source.

Output location depends on CI mode:

```text
normal build:  ../build-$VERSION
CI build:      $PWD/$CI_BUILD_OUT
```

The script writes timing and stage messages to:

```text
$OUT/date.txt
```

For quiet per-architecture builds, logs are written under the output directory,
for example:

```text
$OUT/build-x86_64.log
```


## Stage 2: download and unpack Buildroot

The build downloads:

```text
buildroot-$BR_VER.tar.gz
```

into `download/`, unpacks it into:

```text
buildroot-$BR_VER/
```

and creates or updates the symlink:

```text
buildroot -> buildroot-$BR_VER
```

If `patches-buildroot/series` exists, the script applies local patches with
`quilt` from inside the Buildroot tree.  Current local patches are stored under:

```text
patches-buildroot/
```

These patches are project-specific changes to upstream Buildroot behavior.  When
updating Buildroot, always verify that these patches still apply and still make
sense.

The script also writes `src/etc/os-release` for the build version.  That file is
generated as part of the release build, so avoid treating a locally generated
copy as a persistent source edit unless you intentionally changed the workflow.


## Stage 3: fetch Buildroot package sources

Before building all architectures, `bin/build-release` runs a Buildroot source
fetch step.  The lower-level form is:

```bash
make ARCH=x86_64 OUT_D="$PWD/output/x86_64" br-source
```

Buildroot downloads upstream package source archives into `BR2_DL_DIR`, which
CirrOS maps to `download/`.  Reusing `download/` avoids repeated network fetches
across builds.

Common failure causes:

- missing host dependencies,
- network failure,
- upstream package URL changes,
- stale Buildroot package metadata,
- invalid local patches,
- corrupted cached downloads.

Useful places to inspect:

```text
download/
$OUT/build-$ARCH.log
$OUT/build/$ARCH/buildroot/
```


## Stage 4: build the Buildroot rootfs

For each architecture, `bin/build-release` runs the top-level `Makefile` with an
architecture and output directory:

```bash
make ARCH=x86_64 OUT_D="$OUT/build/x86_64"
```

The Makefile:

1. copies `conf/buildroot-x86_64.config` into the Buildroot output tree,
2. copies `conf/busybox.config` into the Buildroot output tree,
3. invokes Buildroot out-of-tree,
4. copies Buildroot's rootfs tar output to `$OUT/build/x86_64/rootfs.tar`.

Current Buildroot configs use Buildroot's default skeleton rather than a custom
skeleton path, so contributors should not assume `src/` is incorporated into the
Buildroot `rootfs.tar` by this stage.  The Makefile still has a rule that can
create an `output/$ARCH/skeleton` tree from Buildroot's skeleton plus `src/`,
but in current builds the meaningful CirrOS overlay application happens later
in `bin/bundle`.

The output of this stage is a Buildroot root filesystem tarball, not a bootable
CirrOS disk image.


## Stage 5: download and repack kernels

CirrOS uses Ubuntu kernel packages rather than asking Buildroot to build a
kernel.  `bin/grab-kernels` downloads architecture-specific Ubuntu `.deb`
packages and repacks the relevant contents into:

```text
download/kernel-$ARCH.tar.gz
```

Architecture names differ between CirrOS, Buildroot, Ubuntu package names,
and QEMU.  Part VIII is the canonical architecture reference; this stage only
needs the reminder that `bin/grab-kernels` owns the CirrOS-to-Ubuntu kernel
package mapping.

The script knows about image packages, module packages, signed/unsigned naming,
and architecture differences.  Kernel package naming can change between Ubuntu
series, so kernel updates often require inspecting `bin/grab-kernels` rather
than only changing a version variable.


## Stage 6: download and prepare grub

CirrOS uses grub payloads from Ubuntu packages.

EFI architectures use:

```text
bin/grab-grub-efi
```

PowerPC/OpenFirmware uses:

```text
bin/grab-grub-ieee
```

The PReP and IEEE1275 terms are defined in `Terminology used in this guide`.

`bin/build-release` chooses grub format by architecture:

```text
ppc*        -> ieee
all others  -> efi
```

It also chooses the grub package version variable.  `x86_64` and `aarch64` use
`GVER_UNSIGNED`; other architectures use `GVER`.  Here, `unsigned` refers to
Ubuntu grub EFI binaries that are not signed for UEFI Secure Boot, not to a
generic integrity check on the CirrOS build.

The prepared grub tarball is later passed to `bin/bundle`.


## Stage 7: bundle the image

For each architecture, `bin/build-release` calls `bin/bundle` with root
privileges:

```bash
sudo ./bin/bundle -v --arch="$ARCH" \
  "$OUT/build/$ARCH/rootfs.tar" \
  ./download/kernel-$ARCH.tar.gz \
  ./download/grub-$FORMAT-$ARCH.tar.gz \
  "$OUT/stage/$ARCH"
```

`bin/bundle` is the main image assembly script.  It has four practical
sub-phases.

Input preparation and root partition setup:

- prepares grub helper data,
- creates an ext4 partition image labeled `cirros-rootfs`,
- copies that empty formatted partition to `blank.img` for UEC-style packaging,
- extracts and analyzes the kernel package so selected modules can be collected.

Overlay and filesystem finalization:

- builds a CirrOS overlay from `src/`,
- applies `makedevs.list` for ownership, modes, and device nodes; see
  `makedevs.list`,
- extracts the Buildroot rootfs and CirrOS overlay into a staging tree,
- runs `fixup-fs` for post-combine filesystem layout cleanup; see `fixup-fs`.

Container and kernel artifacts:

- creates container-oriented filesystem tarballs from the staged userspace before
  kernel, module, initramfs, and bootloader payloads are added,
- adds selected kernel files, modules, and bootloader files to the staging tree,
- creates the direct-boot initramfs and the initrd used by disk images.

Disk image output:

- populates a minimal ext4 partition image with kernel and initramfs boot
  payloads,
- populates a second full partition image with the assembled root filesystem,
- calls `bin/part2disk` to wrap each partition image in a bootable disk layout,
- converts the raw disks to compressed qcow2.

`bin/bundle` writes staged outputs under:

```text
$OUT/stage/$ARCH/
```


## Stage 8: release directory population

After bundling, `bin/build-release` creates release-facing names and copies or
compresses selected artifacts into:

```text
$OUT/release/
```

This stage is mostly naming, copying, compression, and checksum generation.  The
files under `$OUT/stage/$ARCH/` have build-internal names such as
`disk-minimal.qcow2`, `disk-full.qcow2`, `part.img`, `kernel`, and
`initramfs`; the release directory gives them stable user-facing names such as
`cirros-$VER-$ARCH-minimal.qcow2` and `cirros-$VER-$ARCH-full.qcow2`.

A successful release directory should contain checksums in `MD5SUMS` and the
expected artifact families for the architecture you built: disk image, rootfs
partition image, direct kernel/initramfs files, container tarballs, and UEC/LXD
packaging where applicable.  The complete artifact list is in `Artifact layout`;
for the walkthrough, remember the flow:

```text
$OUT/build/$ARCH/rootfs.tar -> bin/bundle -> $OUT/stage/$ARCH -> $OUT/release
```


## Stage 9: optional boot tests

If `BOOTTEST=true`, `bin/build-release` invokes `bin/test-boot` after producing
release artifacts:

```bash
ARCHES="x86_64" BOOTTEST=true bin/build-release daily
```

CI runs `bin/test-boot` as a separate workflow step rather than relying on the
`BOOTTEST=true` path, but both paths exercise the same script.  See
`bin/test-boot behavior` for the full behavior, transient files, and
architecture-specific QEMU choices.


With the build pipeline understood end to end, Part V documents the filesystem
overlay and runtime boot behavior that distinguish CirrOS from a plain
Buildroot image.


# Part V - CirrOS Filesystem and Runtime


## The src/ overlay

The `src/` directory contains files that are copied into the image filesystem.
This is where most CirrOS-specific runtime behavior lives.

Important paths include:

```text
src/init
src/etc/inittab
src/etc/init.d/
src/etc/rc3.d/
src/etc/cirros-init/
src/etc/modules
src/lib/cirros/
src/sbin/
src/bin/
src/usr/bin/
src/home/cirros/
src/usr/share/cirros/logo
```

The overlay provides:

- the initramfs entry point,
- init scripts,
- datasource discovery and application,
- network setup hooks,
- user-data handling,
- status reporting,
- default user files,
- module selection,
- CirrOS shell libraries and helper commands,
- image identity files such as `/etc/issue` and `/etc/os-release`.


## Filesystem finalization order

This section focuses on filesystem-specific finalization.  The full bundle
sequence is described in Stage 7 and the artifact reference is in Part VII.

`src/` is not copied directly into the mounted image exactly as it appears in
your checkout.  `bin/bundle` first builds an overlay tree, changes ownership to
root, optionally creates generated symlinks, applies `makedevs.list`, archives
the overlay, and extracts it over the Buildroot rootfs staging directory.

Permission-sensitive changes belong in one of three places:

```text
ordinary file content/path       src/
ownership, modes, device nodes   makedevs.list
post-combine layout cleanup      fixup-fs
```

Do not rely on local checkout ownership to survive bundling.


## makedevs.list

`makedevs.list` records filesystem modes, ownership, and device nodes that must
exist in the generated image.  It is applied during bundling with `xmakedevs`, a
Buildroot utility for applying device-node and permission rules.

It covers things such as:

- executable bits for init scripts,
- sudoers file permissions,
- `/init`,
- `/dev/console`, tty devices, random devices,
- `/home/cirros` ownership,
- sticky `/tmp`,
- `/run`.

If you add a permission-sensitive file, add or verify a `makedevs.list` rule.
Representative entries include:

```text
/etc/init.d/cirros-*                    f 0755  0  0  -  - - - -
/etc/sudoers.d/*                        f 0440  0  0  -  - - - -
/dev/console                            c 0600  0  0  5  1 - - -
/home/cirros                            d 0755  1000 1000 - - - - -
```

The fields are path, type, mode, uid, gid, and device metadata for special
files.  Examples include sudoers files, executable init scripts, device nodes,
or files that must be owned by the `cirros` user.


## fixup-fs

`fixup-fs` runs after the Buildroot rootfs and CirrOS overlay are combined.  It
adjusts the rootfs layout to match CirrOS expectations.

Examples of its current responsibilities:

- remove unwanted default files,
- adjust Buildroot's `/var` symlink layout,
- create runtime-oriented `/run` and `/var` paths,
- make `/etc/resolv.conf` point at runtime-managed resolver state.

Use `fixup-fs` for final layout corrections that require seeing the combined
Buildroot rootfs plus CirrOS overlay.  Do not use it as a substitute for normal
Buildroot package selection or for ordinary overlay files.


## Runtime boot sequence

The runtime has two init phases:

1. initramfs `/init`,
2. BusyBox init inside the real root filesystem.

High-level flow:

```text
kernel + initramfs
  -> /init
     -> mount /dev, /proc, /sys
     -> parse kernel command line
     -> load early modules
     -> find root=, default LABEL=cirros-rootfs
     -> optional debug-initramfs shell
     -> switch_root to /sbin/init
  -> BusyBox init
     -> /etc/inittab
     -> /etc/init.d/rc.sysinit
        -> executable /etc/rc3.d/S* scripts in lexical order
```

### Initramfs phase (`/init`)

The `src/init` script is the initramfs entry point.  It parses kernel command
line settings through `/lib/cirros/shlib`, loads modules, searches for the root
filesystem, and either switches to the real root or runs from the initramfs when
requested (`root=ramdisk` or `root=none`) or when no usable root is found.

The default root lookup is:

```text
LABEL=cirros-rootfs
```

Use `debug-initramfs` to stop in this phase for a shell, and see
`Kernel command-line parameters` for the full kernel command-line reference.

### Real-root init: BusyBox init and `rc.sysinit`

The BusyBox init configuration is in `src/etc/inittab`.  Its sysinit action runs
`/etc/init.d/rc.sysinit`, which mounts runtime filesystems and runs the rc3
scripts.  CirrOS uses SysV-style runlevel naming here: scripts prefixed with `S`
run at startup in lexical order, so the numeric prefix controls sequencing
relative to other scripts.

### rc3 startup ordering

Current rc3 ordering includes normal system setup plus the CirrOS cloud flow.
The cloud-relevant sequence is:

```text
S35-cirros-ds-local      local datasource discovery
S36-cirros-apply-local   local datasource apply phase
S40-network              network startup
S45-cirros-net-ds        network datasource discovery
S46-cirros-apply-net     network datasource apply phase
S47-cirros-check-version version availability check
S50-dropbear             SSH server startup
S55-resizefs             root filesystem resize workflow
S95-cirros-userdata      user-data execution
S98-cirros-status        status output
S99-logo                 logo/login banner
```

Earlier rc3 scripts also handle syslog, module loading, urandom seeding, and
ACPI.

### Datasource ordering

The relative datasource ordering is the important part: local datasources such
as NoCloud and config-drive are searched before networking, while EC2-style
metadata is searched after networking is up.  If a local datasource succeeds,
the network datasource script skips rediscovery because a datasource is already
selected.

### Container boot differences

In containers, `rc.sysinit` detects the container environment, writes
`/bin/lxc-is-container`, skips devtmpfs mounting, and adjusts getty/securetty
handling for LXC-style consoles.  Container boot therefore uses the same
rootfs/runtime scripts but not the initramfs `/init` path used by disk and
direct-kernel boots.


## Kernel command-line parameters

`doc/kernel-cmdline.md` documents supported kernel command-line parameters.
Important ones include:

```text
root=LABEL=cirros-rootfs
root=UUID=<uuid>
root=ramdisk
root=none
init=<program>
dslist=<comma-separated datasource list>
debug-initramfs
verbose
```

Use cases:

- `debug-initramfs` drops into a shell during early initramfs boot.
- `root=none` or `root=ramdisk` runs from the initramfs.
- `rdroot` is also accepted by the current parser as a ramdisk-root shortcut,
  but prefer `root=ramdisk` or `root=none` in new docs and tests.
- `init=/bin/sh` can be useful for debugging the real root filesystem.
- `dslist=none` disables normal datasource search and uses the none datasource
  if included in the list.
- `verbose` increases boot-time debug output.


## Module loading

The module list is in:

```text
src/etc/modules
```

The parser is in:

```text
src/etc/init.d/load-modules
```

The same module list matters in two places:

1. `src/init` uses `load-modules start` early in the initramfs.
2. `bin/bundle` uses `load-modules parse_modules` to decide which kernel module
   files and dependencies to include in the image artifacts.

Lines can include architecture filters:

```text
ne2k-pci     # arch=x86
qemu_fw_cfg  # arch=x86,aarch64
```

When changing storage, network, virtio, filesystem, config-drive, or boot
behavior, inspect both `src/etc/modules` and the kernel packages being used.


Part V showed when the runtime scripts execute.  Part VI documents the
individual CirrOS programs and shared runtime state they use.


# Part VI - CirrOS Runtime Program Reference


## Runtime overview: state paths and program index

The shell library `src/lib/cirros/shlib_cirros` defines common datasource and
state paths.  The important runtime concepts are:

```text
/lib/cirros/ds/              datasource implementation scripts
/run/cirros/datasource       selected datasource results
/run/cirros                  runtime state
```

The exact variables are defined in the shell libraries, so when in doubt read:

```text
src/lib/cirros/shlib
src/lib/cirros/shlib_cirros
```

These libraries provide common helpers for logging, command-line parsing,
datasource result inspection, device lookup, network formatting, version checks,
and error handling.

Runtime program index:

```text
Program          Source path                 Installed path        Primary role
-------          -----------                 --------------        ------------
cirros-ds        src/sbin/cirros-ds          /sbin/cirros-ds       datasource discovery
cirros-query     src/bin/cirros-query        /bin/cirros-query     datasource inspection
cirros-apply     src/sbin/cirros-apply       /sbin/cirros-apply    apply datasource data
cirros-per       src/bin/cirros-per          /bin/cirros-per       frequency gate
cirros-userdata  src/sbin/cirros-userdata    /sbin/cirros-userdata run user-data
cirros-status    src/sbin/cirros-status      /sbin/cirros-status   console diagnostics
```


## cirros-ds

`cirros-ds` is the datasource dispatcher.  It searches configured datasources in
a given mode and records the first datasource that succeeds.

Modes:

```text
local
net
```

Search order comes from either:

- `dslist=` on the kernel command line, or
- `DATASOURCE_LIST` in `/etc/cirros-init/config`.

Datasource success contract:

A datasource is considered found only if it:

1. exits with status 0, and
2. writes a readable `result` file in its output directory.

Exit 0 without `result` means the datasource did not find data in that mode.
Non-zero means an error was reported and the dispatcher continues.

On success, `cirros-ds` copies the datasource output to the runtime datasource
results directory and writes metadata files such as:

```text
dsname
dsmode
data/*
```

**Design note:**

`cirros-ds` is deliberately small: datasource implementations are separate
executables, and the dispatcher only defines search order and the success
contract.  That keeps local, network, and fallback datasources testable in
isolation.


## cirros-query

`cirros-query` is a small user/debugging interface for the selected datasource.
It can report the datasource name, datasource mode, available fields, and field
contents.

Commands:

```text
cirros-query datasource
cirros-query dsmode
cirros-query available
cirros-query get <field>
```

Example:

```bash
cirros-query datasource
cirros-query get instance-id
cirros-query get local-hostname
```

Use it when debugging guest metadata behavior from inside a booted CirrOS
instance.


## cirros-apply

`cirros-apply` applies the datasource that `cirros-ds` discovered.  Discovery
and application are separate so the boot sequence can find local data before
networking, start networking, then optionally find network metadata and apply
that.

Modes:

```text
local
net
```

If no datasource is present, or if the discovered datasource has a different
mode, `cirros-apply` exits successfully without doing work.

Apply flow:

1. verify that a datasource exists,
2. verify that its mode matches the requested apply mode,
3. run the datasource-specific `apply-local` or `apply-net` hook,
4. apply common CirrOS behavior.

Common behavior includes:

- set `/etc/hostname` from `hostname` or `local-hostname`,
- mount a device labeled `ephemeral0` at `/mnt` if present,
- preserve and prepare datasource-provided network interface data when present,
- install `public-keys` for the `cirros` user,
- install root keys with a forced command that tells users to log in as
  `cirros`,
- feed `random_seed` or `random-seed` into `/dev/urandom`.

**Design note:**

`cirros-apply` is where datasource data becomes guest configuration.  Keeping
common behavior here means individual datasources can focus on discovery and
normalization while hostname, SSH key, ephemeral disk, network-interface, and
random-seed handling stay consistent across datasource types.


## cirros-per

`cirros-per` runs a command at a defined frequency and records a marker so the
same action is not repeated too often.

Frequencies:

```text
always       run every time
always-ds    run every time, but only if there is a datasource
boot         run once per boot
instance     run once per datasource instance-id
once         run once ever
```

Typical use:

The init scripts call apply and user-data actions through `cirros-per` so that
instance-scoped work does not repeat on every boot of the same instance.  For
example, `src/etc/init.d/cirros-apply-local` uses:

```bash
cirros-per instance cirros-apply-local cirros-apply local
```

That means: for the current datasource instance, record the marker named
`cirros-apply-local`, and run `cirros-apply local` only if that marker has not
already been recorded.

**Design note:**

`cirros-per` provides the small amount of cloud-init-style idempotency that
CirrOS needs without pulling in a larger framework.  Instance-scoped actions use
the datasource `instance-id`, while boot-scoped actions use runtime state under
`/run`.


## cirros-userdata

`cirros-userdata` handles user-data from the selected datasource or from an
explicit file argument.

Behavior:

- If called without a file, it looks for `user-data` in the selected datasource.
- If no datasource or no user-data exists, it exits successfully without doing
  work.
- Executable files are run.
- Files beginning with `#!` are intended to be run as scripts.
- Non-executable, non-shebang data is ignored by this simple handler.

This is intentionally much smaller than cloud-init.  CirrOS supports enough
user-data behavior for testing common cloud workflows without carrying a full
Python cloud-init stack.


## cirros-status

`cirros-status` prints useful debugging information to the console near the end
of boot.

It reports information such as:

- platform and container detection,
- CPU and memory summary,
- disk list when not in a container,
- SSH host keys,
- network addresses and routes,
- datasource name and selected metadata fields,
- CirrOS version and uptime,
- gateway ping diagnostics when connectivity appears broken.

This output is useful when looking at a serial console in OpenStack, QEMU, or
another virtualized environment.

**Design note:**

The status output is optimized for serial-console debugging in virtualized
environments.  It intentionally prints enough platform, network, datasource, and
SSH host-key information to diagnose common cloud boot failures without logging
into the guest first.



## Datasource overview

Datasource implementation scripts live under `/lib/cirros/ds/` in the guest and
`src/lib/cirros/ds/` in the repository.  `cirros-ds` dispatches them in local or
network mode, and `cirros-apply` later runs the matching apply hook.

```text
Datasource    Source path                    Discovery/apply phases  Transport/source
----------    -----------                    ----------------------  ----------------
nocloud       src/lib/cirros/ds/nocloud      local/apply-local      cidata seed disk or seed dir
configdrive   src/lib/cirros/ds/configdrive  local/apply-local      OpenStack config-drive
ec2           src/lib/cirros/ds/ec2          net/apply-net          169.254.169.254 metadata
none          src/lib/cirros/ds/none         local/apply-local      explicit no-op datasource
```

Local datasources run before networking.  Network datasources run after network
startup.  The first datasource that writes a valid result becomes the selected
datasource for later query, apply, and user-data behavior.


## Datasource: NoCloud

The NoCloud datasource reads metadata from a local seed.  It is used heavily by
local QEMU tests and is the datasource exercised by `bin/test-boot`.

Search behavior:

- supports a filesystem labeled `cidata`,
- supports pre/post seed directories under `/var/lib/cloud/seed/`,
- requires `meta-data`,
- optionally copies `user-data`,
- optionally copies a `files/` tree.

Minimal seed example:

```bash
cat >meta-data <<'EOF'
{"instance-id":"i-local-test","local-hostname":"cirros-test"}
EOF

cat >user-data <<'EOF'
#!/bin/sh
echo "hello from userdata" >/run/userdata-ran
EOF

cloud-localds -d qcow2 seed.img user-data meta-data
```

During `apply-local`, a `files/` tree from the seed can be copied into the guest
filesystem.


## Datasource: OpenStack config-drive

The config-drive datasource reads OpenStack-style metadata from a local config
drive.

Search behavior:

- looks for labels `config-2` and `CONFIG-2`,
- defines pre/post seed directory variables, but current search only reaches
  them after a labeled config-drive device has been found,
- expects metadata under `openstack/latest/`,
- reads `meta_data.json`,
- optionally reads `user_data`,
- normalizes OpenStack field names into CirrOS datasource names,
- supports OpenStack `files` entries during apply.

Field normalization examples:

```text
uuid               -> instance-id
hostname           -> local-hostname
user_data          -> user-data
availability_zone  -> availability-zone
launch_index       -> launch-index
```

This datasource exists so CirrOS can test OpenStack config-drive behavior
without a full cloud-init implementation.


## Datasource: EC2 metadata

The EC2 datasource queries an EC2-style HTTP metadata service.  It is a network
mode datasource.

Default metadata URL:

```text
http://169.254.169.254/2009-04-04
```

Behavior:

- only supports `net` and `apply-net`,
- waits and retries for an instance id,
- fetches common metadata fields,
- writes fetched values into datasource `data/`,
- maps `ami-launch-index` to `launch-index`,
- relies on common `cirros-apply net` behavior for hostname, SSH keys, and
  random seed handling.

This datasource exists to test EC2-compatible metadata behavior in clouds that
provide the link-local metadata service.


## Datasource: none

The `none` datasource is intended to be an always-available local-mode
no-op datasource.  It provides a way to request a boot that does not depend on
NoCloud, config-drive, or EC2 metadata.

Useful kernel command-line example:

```text
dslist=none
```

This is helpful when debugging boot behavior unrelated to metadata discovery.


## growroot, growpart, and resize-filesystem

Relevant paths:

```text
src/bin/growroot
src/sbin/growpart
src/sbin/resize-filesystem
src/etc/init.d/resizefs
src/etc/default/resizefs
```

Purpose:

These tools support growing the root partition and filesystem when the backing
virtual disk is larger than the image's original root filesystem.

High-level responsibilities:

- `growpart` adjusts a partition table entry to use available disk space,
- `growroot` coordinates root partition growth,
- `resize-filesystem` resizes the filesystem,
- the init script and default config control when this runs during boot.

Design context:

Root growth support exists because cloud images are often launched on disks
larger than the downloaded image.  The resize path is part of first-boot guest
behavior, so test with a disk larger than the default image size, not only with
the unmodified release image.


## Other helper programs

Other small helpers in `src/bin`, `src/sbin`, and `src/usr/bin` include:

```text
lxc-is-container      detect container environment
json2fstree           convert JSON metadata into a filesystem tree
ec2metadata           query EC2-style metadata
parse-interfaces      parse network interface data
ssh-add-key           manage authorized_keys content
ssh-import-id         import SSH public keys
```

These helpers keep the image small and shell-oriented.  Before replacing them
with larger dependencies, consider image size, boot speed, and whether the
helper is used in early boot paths.


With the runtime programs documented, Part VII covers the artifact outputs and
bootloader assembly that make those files bootable.


# Part VII - Image Assembly and Boot Artifacts


## Bundle output overview

Stage 7 in Part IV is the execution walkthrough for `bin/bundle`.  This part is
the artifact reference: it explains the files that sequence leaves behind, how
staged names map to release names, and which artifacts matter for each boot
path.

`bin/bundle` mostly consumes already-built inputs: the Buildroot `rootfs.tar`, a
repacked kernel tarball, a prepared grub tarball, and the CirrOS `src/` overlay.
It does not decide Buildroot package selection.  Most kernel and grub inputs are
prepared before bundling, although helper code such as `prepare-grub` can still
fetch a cached legacy grub package if that supporting file is missing.


## Staged bundle outputs

`bin/bundle` writes per-architecture staged outputs under:

```text
$OUT/stage/$ARCH/
```

Important staged outputs include:

```text
part.img            minimal ext4 root partition image labeled cirros-rootfs
blank.img           empty root partition image used in UEC-style packaging
disk-minimal.qcow2  compressed qcow2 with traditional minimal rootfs
disk-full.qcow2     compressed qcow2 with pre-populated rootfs
kernel              kernel image for direct boot
initramfs         external initramfs for direct boot
filesys.tar.gz    gzip container root filesystem tarball
filesys.tar.xz    xz container root filesystem tarball
intermediate/     internal tarballs used while bundling
```

`bin/build-release` then creates release-facing names and copies or compresses
selected staged files into `$OUT/release/`.  In that mapping, `blank.img` is the
formatted-but-empty root partition image packaged for UEC-style/initramfs-copy
flows, while `filesys.tar.gz` and `filesys.tar.xz` become container rootfs
tarballs that intentionally omit kernel, initramfs, module, and bootloader
payloads.


## Kernel modules and initramfs artifacts

`bin/bundle` extracts the kernel package or kernel tarball, identifies the
kernel version, runs `depmod`, and collects selected modules and dependencies
based on `src/etc/modules`.

There are several related artifacts to understand:

```text
/lib/modules/$kver/       selected modules in the staged root filesystem
kernel                    direct-boot kernel artifact
initramfs                 direct-boot initramfs artifact
/boot/initrd.img-$kver    initrd path used by grub inside disk images
```

The script constructs initramfs content during bundling and has historically
tried to avoid wasting space by duplicating modules unnecessarily.  Current
`bin/bundle` creates two related initramfs forms while assembling artifacts:

- a full initramfs used for the final direct `initramfs` artifact and copied into
  the disk image's `/boot/initrd.img-$kver`,
- an intermediate smaller copy used while assembling staged kernel tar content.

When debugging module placement, inspect the actual built artifacts rather than
assuming every initramfs-like file has identical contents.

Changes involving kernels, storage drivers, virtio, filesystems, or boot modes
should test both:

- direct kernel/initramfs boot paths, and
- full disk/grub boot paths where applicable.


## Disk layout and bootloader placement

`bin/part2disk` wraps the root partition image in a GPT disk image and installs
bootloader data.

Current boot behavior by architecture:

```text
Architecture  Bootloader/layout                         test style
------------  ----------------------------------------  -----------------------
x86_64        legacy BIOS grub plus UEFI                disk boot, QEMU pc
aarch64       UEFI                                      disk + direct kernel test
arm           UEFI                                      disk + direct kernel test
ppc64le       IEEE1275/OpenFirmware with PReP payload   disk boot, QEMU pseries
riscv64       experimental UEFI path                    disk + direct kernel test
```

A simplified x86_64 disk layout is:

```text
GPT disk image
├── partition 1:  ext4 root filesystem labeled cirros-rootfs
└── partition 15: EFI System Partition when EFI boot support is requested
```

EFI images use a VFAT EFI System Partition with files under paths such as:

```text
EFI/BOOT/
EFI/ubuntu/grub.cfg
```

The generated grub config searches for the root filesystem label:

```text
cirros-rootfs
```

PowerPC uses the IEEE1275/PReP path and writes grub configuration into the root
filesystem under `/boot/grub/`.  For `ppc64le`, `bin/grab-grub-ieee` builds a
`powerpc-ieee1275` grub image from Ubuntu `grub-ieee1275-bin` packages, and
`bin/part2disk --grub-ieee` writes that image into a GPT partition type `4100`
PReP partition while keeping grub configuration on the root filesystem.


## Artifact layout

The build pipeline has three useful output levels:

```text
$OUT/build/$ARCH/     Buildroot-oriented build output
$OUT/stage/$ARCH/     staged bundle output for one architecture
$OUT/release/         final release-facing artifacts
```

The release directory contains a small set of artifact categories for each
architecture:

- bootable disk image,
- compressed root filesystem partition image,
- direct kernel and initramfs artifacts,
- container-oriented root filesystem artifacts,
- cloud/UEC-style packaging,
- LXD metadata,
- checksums,
- source archive material for tagged releases.

Current `bin/build-release` output names include:

```text
cirros-$VER-$ARCH-minimal.qcow2    compressed qcow2 with traditional minimal rootfs
cirros-$VER-$ARCH-full.qcow2       compressed qcow2 with pre-populated rootfs
cirros-$VER-$ARCH-rootfs.img.gz    gzip-compressed minimal ext4 root partition image
cirros-$VER-$ARCH-kernel           direct-boot kernel
cirros-$VER-$ARCH-initramfs        direct-boot initramfs
cirros-$VER-$ARCH-lxc.tar.gz       gzip container root filesystem tarball
cirros-$VER-$ARCH-lxc.tar.xz       xz container root filesystem tarball
cirros-$VER-$ARCH-lxd.tar.xz       LXD metadata tarball
cirros-$VER-$ARCH-uec.tar.gz       tarball containing blank.img, vmlinuz, initrd
buildroot_rootfs/buildroot-$VER-$ARCH.tar.gz  raw Buildroot rootfs tarball
MD5SUMS                            checksums for top-level release files
cirros-$VER-source.tar.gz          source tarball for tagged builds only
```

When debugging an artifact problem, work backwards:

1. Is the final file present under `$OUT/release/`?
2. Was the staged file created under `$OUT/stage/$ARCH/`?
3. Did `bin/bundle` produce it?
4. Did the Buildroot rootfs exist under `$OUT/build/$ARCH/`?
5. Did kernel or grub download/repack fail earlier?

For symptom-oriented debugging across these layers, see `Troubleshooting by
symptom`.


With artifacts documented, Part VIII covers how architecture affects every
layer from Buildroot config through kernel package naming, grub payload, and
QEMU boot command.


# Part VIII - Architecture Support


## Supported and experimental architectures

For this guide, treat the following as the established supported architecture
set:

```text
x86_64
aarch64
arm
ppc64le
```

Treat the following as experimental/work-in-progress:

```text
riscv64
```

`riscv64` appears in configs, scripts, and CI, but it has not been treated here
as officially released support pending maintainer review.


## Architecture naming matrix

Architecture names differ by layer:

```text
CirrOS arch | Buildroot arch | Ubuntu kernel arch | C library | boot path
------------|----------------|--------------------|------------|----------------------
x86_64      | x86_64         | amd64              | uClibc     | BIOS + UEFI
aarch64     | aarch64        | arm64              | uClibc     | UEFI
arm         | arm            | armhf              | uClibc     | UEFI
ppc64le     | powerpc64le    | ppc64el            | musl       | IEEE1275 / PReP
riscv64     | riscv64        | riscv64            | uClibc     | experimental EFI path
```

Do not assume that a name used in one layer is valid in another.  For example,
`ppc64le` is the CirrOS architecture name, `powerpc64le` is used by Buildroot,
and `ppc64el` is the Ubuntu package architecture.

PowerPC support currently means `ppc64le` only.  Older docs may mention
`powerpc` or `ppc64`, but current configs and build defaults only provide
`conf/buildroot-ppc64le.config`.  Historical OpenStack deployment notes used
properties such as `arch=ppc64le`, `hypervisor_type=kvm`,
`os_command_line="console=hvc0 console=tty0"`, and virtio-scsi disk/cdrom
properties.  Treat those as deployment hints to verify against the target cloud,
not as part of the build pipeline.


## Where architecture-specific decisions live

Architecture-specific behavior is spread across focused files:

```text
conf/buildroot-$ARCH.config       Buildroot arch/toolchain/package config
bin/build-release                 default arch list and component versions
bin/grab-kernels                  CirrOS arch -> Ubuntu package arch mapping
bin/grab-grub-efi                 EFI grub package and format mapping
bin/grab-grub-ieee                ppc64le IEEE1275 grub handling
bin/part2disk                     boot partition and grub installation logic
src/etc/modules                   module list and arch filters
bin/test-boot                     QEMU binary, machine, and direct boot mapping
.github/workflows/build-cirros.yaml  CI architecture matrix
```

When adding or changing architecture support, inspect all of these together.  A
Buildroot config that compiles is not enough; the kernel package mapping, grub
payload, boot layout, module list, QEMU smoke test, and release naming all need
to agree.


With architecture-specific outputs in mind, Part IX explains how to validate
changes locally, in CI, and in release workflows.


# Part IX - Testing, CI, and Release


## Local validation by change type

Use validation proportional to the risk of the change.

```text
Change type                 Minimum useful check
-----------                 --------------------
Documentation only           git diff --check
Buildroot package/config     x86_64 build, then affected architectures
Filesystem overlay           x86_64 build + boot test; see Filesystem finalization order
Init/datasource/network      boot test with relevant datasource; see Runtime boot sequence
Kernel/module/storage        affected architecture boot tests; see Module loading
Bootloader/disk layout       affected architecture boot tests + image inspection; see Disk layout
Release naming/metadata      inspect stage and release directories; see Artifact layout
```

Start with x86_64 unless the change is architecture-specific:

```bash
ARCHES="x86_64" bin/build-release daily
POWEROFF=true RELEASE_DIR=... IMG=... bin/test-boot
```

Do not copy old `root=noroot`, PV-GRUB, or external `lxc-libvirt-root` examples
from `doc/TESTING` without revalidating them.  The useful part of that older
file is its validation categories: QEMU boot, container boot,
OpenStack/config-drive, and EC2 metadata checks.  Prefer current commands:
`bin/test-boot` for local QEMU/NoCloud smoke tests; targeted config-drive or EC2
metadata checks only when changing those datasources; and direct
kernel/initramfs or `root=ramdisk`/`root=none` boots for initramfs/root-discovery
changes.


## bin/test-boot behavior

`bin/test-boot` supports normal and CI modes.

In CI mode, it uses:

```text
CI_BUILD=true
CI_BUILD_OUT=build-ci/
GUESTARCH=<arch>
```

and finds the disk image under the CI release directory.

Outside CI, it infers `GUESTARCH` from the `IMG` filename unless explicitly set.

The script selects QEMU behavior by architecture:

```text
arm       qemu-system-arm, virt,highmem=off, direct kernel/initrd
aarch64   qemu-system-aarch64, virt, cortex-a57, direct kernel/initrd
ppc64le   qemu-system-ppc64, pseries-2.12
x86_64    qemu-system-x86_64, pc
riscv64   qemu-system-riscv64, virt, direct kernel/initrd
```

Because different architectures exercise different boot paths, a single x86_64
boot test does not prove ARM, PowerPC, or experimental RISC-V boot behavior.
The `ppc64le` smoke test disk-boots with `qemu-system-ppc64` and virtio
network/storage/seed devices.  Older PowerKVM examples in `doc/README-powerpc.txt`
use KVM-only options, older pseries machine names, default `ibmveth`/`ibmvscsi`,
or direct kernel boot; treat those as historical notes rather than the current
validation path.

`bin/test-boot` writes transient `meta-data`, `user-data`, `seed.img`, and
`disk1.img` files in the current directory, so run it from a scratch directory
or clean those files before re-running.  It uses QEMU user networking on
`10.0.12.0/24`, attaches virtio networking/storage/rng devices where applicable,
and defaults to 512 MiB of memory unless `MEM` is overridden.  With
`POWEROFF=true`, the generated user-data installs an executable `/etc/rc.local`,
and `rc.sysinit` runs it after the rc3 scripts to power off the guest.


## GitHub Actions CI

The tracked GitHub Actions workflow is:

```text
.github/workflows/build-cirros.yaml
```

It currently:

- runs on Ubuntu 22.04,
- triggers on pushes to `main`, pull requests to `main`, and release-like tags,
- builds a matrix of architectures,
- sets `ARCHES` to one matrix architecture per job,
- uses `CI_BUILD=true` and `CI_BUILD_OUT=build-ci/`,
- caches `download/` and `ccache/`,
- runs `bin/system-setup`,
- installs boot-test dependencies,
- runs `bin/build-release`,
- runs `bin/test-boot`,
- uploads release artifacts from the CI output directory.

CI includes `riscv64`, but this guide still treats it as experimental until
maintainers decide otherwise.

To reproduce a CI-style boot test locally for an existing CI output directory:

```bash
CI_BUILD=true \
CI_BUILD_OUT=build-ci/ \
GUESTARCH=x86_64 \
POWEROFF=true \
bin/test-boot
```


## Release workflow and publishing context

Most contributors do not publish CirrOS releases.  They build and test images
locally or in CI.

Contributor build example:

```bash
ARCHES="x86_64" bin/build-release daily
```

Tagged release behavior differs from daily builds:

- a non-`daily` version must match a git tag,
- `~` is transformed to `_` when checking tag names,
- tagged releases include source archive material,
- artifact names use the requested version rather than a date-based daily
  version.

Maintainer-only publication context currently lives in:

```text
doc/create-release.txt
bin/mirror-dump-sstream-data
```

Those files describe mirror population, simplestreams metadata generation, and
GPG signatures.  No tracked GitHub Actions workflow invokes that publishing
path.  Treat it as maintainer-only/manual release context unless maintainers
confirm a newer automated publication process.

Do not copy `doc/create-release.txt` as a fresh contributor recipe without
maintainer review.  It contains useful concepts, but its Launchpad checkout,
Bazaar/simplestreams helper commands, mirror variables, and detached-signature
loop are historical/manual publication details rather than behavior performed by
`bin/build-release` or CI.

The official public download site is:

```text
https://download.cirros-cloud.net/
```


Part X turns the preceding reference material into common maintenance
workflows.


# Part X - Maintenance Workflows


## Updating a Buildroot package

Recommended workflow:

```bash
make ARCH=x86_64 OUT_D="$PWD/output/x86_64" br-menuconfig
make ARCH=x86_64 OUT_D="$PWD/output/x86_64"
git diff -- conf/buildroot-x86_64.config
ARCHES="x86_64" bin/build-release daily
POWEROFF=true RELEASE_DIR=... IMG=... bin/test-boot
```

Review checklist:

- Did the diff only change intended Buildroot symbols?
- Did Buildroot select additional dependencies?
- Is the package useful for cloud/virtualization testing?
- Is the size increase acceptable?
- Does it conflict with BusyBox applets or CirrOS scripts?
- Does it build under the libc/toolchain used by each target architecture?
- Should all architecture configs be updated, or only some?


## Updating BusyBox

BusyBox supplies `/bin/sh`, many core utilities, and behavior used by CirrOS
scripts.  Treat BusyBox changes as runtime changes, not just package changes.

Use:

```bash
make ARCH=x86_64 OUT_D="$PWD/output/x86_64" br-busybox-menuconfig
make ARCH=x86_64 OUT_D="$PWD/output/x86_64"
git diff -- conf/busybox.config
```

Before disabling or changing an applet, search for usage:

```bash
grep -Rn '\<ash\>' src bin conf doc
```

Replace `ash` in that example with the applet or command you plan to change.
Boot-test after BusyBox changes that affect shell behavior, init, networking,
filesystem tools, or commands used by datasource scripts.


## Updating Buildroot

Buildroot upgrades are high-risk.  They can affect toolchains, libc behavior,
package versions, Kconfig symbols, skeleton layout, patches, and generated
rootfs behavior.

Current Buildroot version is pinned in `bin/build-release`:

```bash
BR_VER="2022.02.4"
```

Recommended process:

1. Update `BR_VER`.
2. Download and unpack the new Buildroot version.
3. Re-apply or refresh `patches-buildroot/`.
4. Refresh each `conf/buildroot-$ARCH.config` using Buildroot's Kconfig update
   flow, such as `oldconfig` or `olddefconfig` through the `br-%` wrapper where
   appropriate.
5. Refresh `conf/busybox.config` if BusyBox symbols changed.
6. Check skeleton and rootfs output path assumptions.
7. Build x86_64.
8. Build every supported architecture.
9. Boot-test every supported architecture if possible.

Historical notes exist in `doc/buildroot-upgrade.txt`, but that file contains
stale commands and old architecture references.  Prefer current Makefile targets
and verify everything against current Buildroot behavior.


## Updating kernels

Kernel versions are controlled in `bin/build-release`:

```bash
KVER="..."
KVER_riscv64="..."
```

Recommended process:

1. Choose the Ubuntu kernel source version.
2. Verify image and module packages exist for every target architecture.
3. Update `KVER` and any `KVER_$ARCH` override.
4. Build one architecture.
5. Inspect `bin/grab-kernels` output.
6. Boot-test.
7. Repeat across supported architectures.

Kernel package naming can be brittle.  Future Ubuntu kernels may change image
package names, module package splits, or signed/unsigned package availability.


## Updating grub

Grub versions are controlled in `bin/build-release`:

```bash
GVER="..."
GVER_UNSIGNED="..."
```

Recommended process:

1. Choose the Ubuntu grub2 package version.
2. Verify EFI or IEEE1275 package availability for target architectures.
3. Build affected architectures.
4. Boot-test affected architectures.
5. Inspect `bin/grab-grub-efi`, `bin/grab-grub-ieee`, `bin/build-efi-images`,
   and `bin/part2disk` if package names or formats changed.


## Updating CA certificates

The CA certificate bundle is stored in the overlay under:

```text
src/etc/ssl/certs/ca-certificates.crt
```

`README.md` documents an optional workflow using Mozilla certificate data and:

```text
bin/mkcabundle
```

`bin/build-release` intentionally does not regenerate this file automatically.
Keeping the generated certificate bundle in source makes releases less dependent
on external services at build time and makes certificate updates reviewable.


## Changing init or datasource behavior

When changing init or datasource behavior, read in this order:

```text
src/init
src/etc/inittab
src/etc/init.d/rc.sysinit
src/etc/rc3.d/
src/sbin/cirros-ds
src/sbin/cirros-apply
src/sbin/cirros-userdata
src/lib/cirros/ds/*
src/lib/cirros/shlib
src/lib/cirros/shlib_cirros
```

Validation should include a real boot.  For datasource behavior, use a seed or
metadata source that exercises the changed path.  A bare boot without metadata
may not test the code you changed.


## Changing filesystem permissions

Use the layer model from `Filesystem finalization order`: ordinary file content
belongs in `src/`, ownership and device rules belong in `makedevs.list`, and
post-combine cleanup belongs in `fixup-fs`.  Buildroot-provided package files
belong in Buildroot config or package changes, not in `src/`.

Examples:

- Add a normal config file: place it under `src/etc/`; default root ownership
  and normal file mode may be enough.
- Add an init script: place it under `src/etc/init.d/`, add an rc symlink if it
  should run at boot, and ensure executable mode through git or `makedevs.list`.
- Add a sudoers drop-in: place it under `src/etc/sudoers.d/` and ensure mode
  `0440` through `makedevs.list`.


Part XI collects symptom-based troubleshooting, known stale areas, command
examples, and task-focused reading paths.


# Part XI - Troubleshooting and Quick Reference


## Troubleshooting by symptom

### Buildroot cannot download a package

Check:

```text
download/
$OUT/build-$ARCH.log
Buildroot package URLs
network/proxy environment
```

Try:

```bash
make ARCH=x86_64 OUT_D="$PWD/output/x86_64" br-source
```

### A package is missing in the guest

Check:

```text
conf/buildroot-$ARCH.config
$OUT/build/$ARCH/buildroot/.config
$OUT/build/$ARCH/rootfs.tar
```

Make sure you changed the correct architecture config.

### A CirrOS file is missing or has wrong permissions

Check:

```text
src/
makedevs.list
fixup-fs
bin/bundle overlay section
$OUT/stage/$ARCH/
```

Remember that the overlay is chowned to root during bundling.

### The guest cannot find the root filesystem

Check:

```text
kernel command line root=
filesystem label cirros-rootfs
src/init
src/etc/modules
bin/bundle
bin/part2disk
```

Use `debug-initramfs` to stop in early boot.

### Datasource is not found

Check:

```text
dslist= kernel command line
/etc/cirros-init/config
src/sbin/cirros-ds
src/lib/cirros/ds/<datasource>
/run/cirros/datasource
```

For NoCloud, verify the seed label and presence of `meta-data`.  For
config-drive, verify the label and `openstack/latest/meta_data.json`.  For EC2,
verify networking and the metadata URL.

### User-data does not run

Check:

```text
selected datasource
cirros-query available
cirros-query get user-data
src/sbin/cirros-userdata
src/etc/rc3.d/S95-cirros-userdata
cirros-per state markers
```

Use `bin/test-boot` with `POWEROFF=true` as a minimal known-good user-data
example.

### QEMU boot hangs

Check:

```text
IMG
RELEASE_DIR
GUESTARCH
bin/test-boot architecture case
QEMU packages
serial console output
```

For ARM, AArch64, and experimental RISC-V, make sure matching kernel and
initramfs files are available in `RELEASE_DIR`.


## Known inconsistencies and stale areas

This section records current repo/documentation rough edges that can confuse new
contributors.  It is not a request to fix them as part of every change.

### Active confusion risks

- `README.md` contains conflicting default-password text.  This guide documents
  `gocubsgo` based on `src/etc/issue` and the hash in `src/etc/shadow`.
- `README.md` lists the established supported architectures but does not list
  `riscv64`, while current scripts and CI include `riscv64`.  This guide treats
  `riscv64` as experimental/work-in-progress.
- `README.md` has shown a comma-separated `ARCHES` example, but current scripts
  iterate over whitespace-separated shell words.
- The top-level `Makefile` default `ARCH=i386` appears stale because there is no
  current `conf/buildroot-i386.config`.

### Stale historical docs

- `doc/buildroot-upgrade.txt` is historical and includes stale commands.
- `doc/TESTING` contains useful validation categories but some old command
  examples and external references.  In particular, prefer current
  `root=ramdisk`/`root=none` wording over old `root=noroot`, and avoid old
  EC2 PV-GRUB/AKI publication examples as current local test guidance.
- `doc/RELEASE.txt` is older than the current artifact set produced by
  `bin/build-release`.
- `doc/README-powerpc.txt` contains useful historical PowerPC/OpenStack context,
  but its `powerpc`/`ppc64` build example, old QEMU command, and "virtio not
  working" note are stale.  Current PowerPC support is `ppc64le`, uses
  IEEE1275/PReP grub, and current smoke tests use virtio.
- `doc/lxc-cli.txt` uses old LXC config keys and an old datasource config path.
  Treat it as historical evidence that container artifacts are rootfs tarballs,
  not as a current LXC recipe.
- `doc/misc.txt` describes appending changed `src/` files to an initrd for fast
  throwaway debugging.  That shortcut bypasses bundling, `makedevs.list`,
  `fixup-fs`, and normal artifact generation, so final validation still requires
  a real build/bundle and boot test.

### Maintainer-only publication context

- `doc/create-release.txt` and `bin/mirror-dump-sstream-data` document
  maintainer publication context, but no tracked GitHub Actions workflow invokes
  that path.


## Command cookbook

This appendix is a quick command summary.  Use the named sections above for
context, expected outputs, and troubleshooting details.

Install dependencies (`Build host assumptions`):

```bash
./bin/system-setup
```

Build one architecture (`Quick start build`):

```bash
ARCHES="x86_64" bin/build-release daily
```

Build several architectures (`Quick start build`):

```bash
ARCHES="x86_64 aarch64 arm" bin/build-release daily
```

Build with GNU parallel (`Full build walkthrough`):

```bash
CIRROS_PARALLEL=true bin/build-release daily
```

Build and boot-test from `bin/build-release` (`Stage 9: optional boot tests`):

```bash
ARCHES="x86_64" BOOTTEST=true bin/build-release daily
```

Run a manual boot test from a scratch directory (`bin/test-boot behavior`),
replacing the version as needed:

```bash
repo=$PWD; scratch=$(mktemp -d); cd "$scratch"
POWEROFF=true \
RELEASE_DIR="$repo/../build-d260528/release" \
IMG="$repo/../build-d260528/release/cirros-d260528-x86_64-full.qcow2" \
"$repo/bin/test-boot"
```

Build only the Buildroot rootfs for one architecture
(`Buildroot configuration files`):

```bash
make ARCH=x86_64 OUT_D="$PWD/output/x86_64"
```

Fetch Buildroot package sources (`Stage 3: fetch Buildroot package sources`):

```bash
make ARCH=x86_64 OUT_D="$PWD/output/x86_64" br-source
```

Edit a per-architecture Buildroot config (`Updating a Buildroot package`):

```bash
make ARCH=x86_64 br-menuconfig
```

Edit the shared BusyBox config (`Updating BusyBox`):

```bash
make ARCH=x86_64 br-busybox-menuconfig
```

Run a CI-style local boot test from a CI-style output directory
(`GitHub Actions CI`):

```bash
CI_BUILD=true \
CI_BUILD_OUT=build-ci/ \
GUESTARCH=x86_64 \
POWEROFF=true \
bin/test-boot
```


## Task-focused reading paths

This section maps task types to source files for reading context.  For debugging
symptoms after a failed build or boot, use `Troubleshooting by symptom` first.

Datasource bug:

```text
src/etc/rc3.d/S35*
src/etc/rc3.d/S45*
src/sbin/cirros-ds
src/sbin/cirros-apply
src/sbin/cirros-userdata
src/lib/cirros/ds/*
```

Overlay file missing or wrong mode:

```text
Makefile
bin/bundle
src/
makedevs.list
fixup-fs
```

Package missing:

```text
conf/buildroot-$ARCH.config
conf/busybox.config
Makefile
$OUT/build-$ARCH.log
```

Boot failure before root mount:

```text
src/init
doc/kernel-cmdline.md
src/etc/modules
bin/bundle
bin/part2disk
```

CI-only failure:

```text
.github/workflows/build-cirros.yaml
bin/build-release
bin/test-boot
build-ci/release/
```
