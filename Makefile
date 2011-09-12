ARCH = i386
TOP_D = $(shell pwd)
BR_D = $(TOP_D)/buildroot
OUT_D = $(TOP_D)/output/$(ARCH)
BR_OUT_D = $(OUT_D)/buildroot
CONF_D = $(TOP_D)/conf
DL_D = $(TOP_D)/download

DISK_IMG = $(OUT_D)/disk.img
PART_IMG = $(OUT_D)/part.img
TAR_IMG = $(OUT_D)/rootfs.tar
BR_TAR_IMG = $(BR_OUT_D)/images/rootfs.tar

BR_MAKE = cd $(BR_D) && make O=$(BR_OUT_D) BR2_DL_DIR=$(DL_D) BUSYBOX_CONFIG_FILE=$(BR_OUT_D)/busybox.config
BR_DEPS = $(BR_D) $(BR_OUT_D)/busybox.config $(BR_OUT_D)/.config

all: $(TAR_IMG)

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

$(BR_OUT_D)/.config: $(CONF_D)/busybox.config $(BR_OUT_D)/.dir
	cp $(CONF_D)/buildroot-$(ARCH).config $@

$(TAR_IMG): $(BR_TAR_IMG)
	cp $(BR_TAR_IMG) $(TAR_IMG)

$(BR_TAR_IMG): $(BR_DEPS)
	$(BR_MAKE)

%/.dir:
	mkdir -p $* && touch $@
