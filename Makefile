ARCH = i386
TOP_D = $(shell pwd)
BR_D = $(TOP_D)/buildroot
OUT_D = $(TOP_D)/output/$(ARCH)
BR_OUT_D = $(OUT_D)/buildroot
CONF_D = $(TOP_D)/conf
DL_D = $(TOP_D)/download
SKEL_D = $(OUT_D)/skeleton

TMPDIR ?= $(OUT_D)/tmp
export TMPDIR

DISK_IMG = $(OUT_D)/disk.img
PART_IMG = $(OUT_D)/part.img
TAR_IMG = $(OUT_D)/rootfs.tar
BR_TAR_IMG = $(BR_OUT_D)/images/rootfs.tar
BR2_CCACHE_DIR = $(OUT_D)/ccache

BR_MAKE = cd $(BR_D) && mkdir -p "$(TMPDIR)" && \
   make O=$(BR_OUT_D) BR2_DL_DIR=$(DL_D) \
   BUSYBOX_CONFIG_FILE=$(BR_OUT_D)/busybox.config \
   BR2_CCACHE_DIR=$(BR2_CCACHE_DIR)

BR_DEPS = $(BR_D) $(BR_OUT_D)/busybox.config $(BR_OUT_D)/.config $(SKEL_D)/.dir

BR_CONFIG = $(CONF_D)/buildroot-$(ARCH).config

BUSYBOX_VERSION := $(shell sed -n -e s/BR2_BUSYBOX_VERSION="\(.*\)"/\\1/p < $(BR_CONFIG))
BUSYBOX_BUILD_DIR = $(BR_OUT_D)/build/busybox-$(BUSYBOX_VERSION)
BUSYBOX_BUILD_CONFIG = $(BUSYBOX_BUILD_DIR)/.config

unexport SED # causes random issues (LP: #920620)

all: $(TAR_IMG)

debug:
	@echo "BR_DEPS: $(BR_DEPS)"
	@echo "BR_MAKE: $(BR_MAKE)"
	@echo "BR_OUT_D: $(BR_OUT_D)"
	@echo "BUSYBOX_BUILD_CONFIG: $(BUSYBOX_BUILD_CONFIG)"

source: br_source minicloud_source

br_source: $(BR_DEPS) $(OUT_D)/.source.$(ARCH)
minicloud_source: $(DL_D)/.dir
	@echo hi world
	# here we would download the Ubuntu kernel

$(BR_D):
	@[ -d "$(BR_D)" ] || { echo "You Must download BUILDROOT, extract it, and symlink to $(BR_D)"; exit 1; }

$(OUT_D)/.source.$(ARCH): 
	$(BR_MAKE) source

$(BR_OUT_D)/busybox.config: $(CONF_D)/busybox.config $(BR_OUT_D)/.dir
	cp $(CONF_D)/busybox.config $@
	for s in configured built target_installed; do rm -f $(BR_OUT_D)/build/busybox-1.18.5/.stamp_$$s; done

$(BR_OUT_D)/.config: $(BR_CONFIG) $(BR_OUT_D)/.dir
	cp $(BR_CONFIG) $@

$(TAR_IMG): $(BR_TAR_IMG)
	cp $(BR_TAR_IMG) $(TAR_IMG)

$(BR_TAR_IMG): $(BR_DEPS)
	$(BR_MAKE)

$(SKEL_D)/.dir:
	# copy BR_D/fs/skeleton, then sync src/ over the
	# top of that.
	# depends on $(BR_D)/fs/skeleton (somehow)
	[ -d $(SKEL_D) ] || mkdir -p $(SKEL_D)
	rsync -a $(BR_D)/fs/skeleton/ $(SKEL_D)/ --delete
	rsync -a $(TOP_D)/src/ $(SKEL_D)/
	touch $(SKEL_D)/.dir

br-menuconfig: $(BR_OUT_D)/.config
	$(BR_MAKE) $* menuconfig
	cp $(BR_OUT_D)/.config $(CONF_D)/buildroot-$(ARCH).config

$(BUSYBOX_BUILD_CONFIG): $(CONF_D)/busybox.config
	cp $(CONF_D)/busybox.config $(BUSYBOX_BUILD_CONFIG)

br-busybox-menuconfig: $(BUSYBOX_BUILD_CONFIG)
	$(BR_MAKE) $* busybox-menuconfig
	cp $(BUSYBOX_BUILD_CONFIG) $(CONF_D)/busybox.config

br-%: $(BR_OUT_D)/.config $(BR_OUT_D)/busybox.config
	$(BR_MAKE) $*

%/.dir:
	mkdir -p $* && touch $@
