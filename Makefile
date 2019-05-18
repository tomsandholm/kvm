MAKEFLAGS += --silent

.PHONEY:	help

check_defined = \
  $(strip $(foreach 1,$1, \
      $(call __check_defined,$1,$(strip $(value 2)))))
__check_defined = \
    $(if $(value $1),, \
      $(error Undefined $1$(if $2, ($2))))

help:
	echo ">>> key variables are:"
	echo "     DISTRO:  (xenial|bionic)"
	echo "     SWAPSIZE: (GB)"
	echo "     DATASIZE: (GB)"
	echo "     RAM: (MB)"
	echo "     VCPUS: (COUNT)"
	echo "     NAME:  fqdn (REQUIRED)"
	echo ""
	echo ">>> Targets"
	make targets
	echo ""
	echo ">>> Current nodes ares:"
	make list

list:
	ls $(IMGDIR)
	
targets:
	sed -n 's/^\([a-Z][a-Z]*\):.*/\1/gp' Makefile

## the distro to build
DISTRO := xenial
#DISTRO := bionic

## derived from NAME, a required env variable
SNAME = $(shell echo $(NAME) | cut -d'.' -f1)

## the URL of where to get THIS $DISTRO
URL := $(shell egrep "^$(DISTRO)" ./distro | cut -d';' -f3)

## the IMG name of THIS $DISTRO
SRC := $(shell egrep "^$(DISTRO)" ./distro | cut -d';' -f4)

## stuff
UUID := $(shell uuidgen)

## get ipaddress of supplied NAME->SNAME
IPADDRESS := $(shell getent hosts $(SNAME)|awk '{print $$1}')

## what role to give node, populates /etc/role
ROLE := general

## what env to give node, populates /etc/aenv
ENV := dev

## swapdisk size
## in GB
SWAPSIZE := 2

## datadisk size
## in GB
DATASIZE := 0

## rootdisk size
## in GB
ROOTSIZE := 8

## database disk size
## in GB
DBSIZE := 8

## docroot disk size
## in GB
WEBSIZE := 8

## guest node ram size
RAM := 2048

## guest node cpu coount
VCPUS := 2

## guest node os type
OS-VARIANT := ubuntu16.04

## where the etc directoy lives
ETCDIR := /etc/kvmbld

## where we store virtual nodes stuff 
VARDIR := /var/lib/kvmbld

## base images directory, used as backing store for qcow2 images
BASEDIR := $(VARDIR)/base

## individual nodes disks
IMGDIR := $(VARDIR)/images

## where are the source images
SRCDIR := $(VARDIR)/sources

## either static or dhcp
NET := static

## command to pass virt-install for swap disk allocation
SWAPDISK := --disk path=$(IMGDIR)/$(SNAME)/swap.qcow2,device=disk,bus=virtio

## command to pass virt-install for data disk allocation
DATADISK := --disk path=$(IMGDIR)/$(SNAME)/data.qcow2,device=disk,bus=virtio

## command to pass virt-install for database disk allocation
DBDISK := --disk path=$(IMGDIR)/$(SNAME)/db.qcow2,device=disk,bus=virtio

## command to pass virt-install for document root disk allocation
WEBDISK := --disk path=$(IMGDIR)/$(SNAME)/docroot.qcow2,device=disk,bus=virtio

## if SWAPSIZE is zero, then do not create SWAPDISK
ifeq ($(SWAPSIZE),0)
	SWAPDISK := 
endif

## if DATADISK is zero, then do not create DATADISK
ifeq ($(DATASIZE),0)
	DATADISK :=
endif

## if DBSIZE is zero, then do not create DBDISK
ifeq ($(DBSIZE),0)
	DBDISK :=
endif

## if WEBSIZE is zero, then do not create WEBDISK
ifeq ($(WEBSIZE),0)
	WEBDISK :=
endif


## target to list stuff
stats:
	$(info DISTRO:....$(DISTRO))
	$(info URL:.......$(URL))
	$(info SRC:.......$(SRC))
	$(info NAME:......$(NAME))
	$(info SNAME:.....$(SNAME))
	$(info IPADDRESS:.$(IPADDRESS))
	$(info UUID:......$(UUID))
	$(info ENV:.......$(ENV))
	$(info ROLE:......$(ROLE))
	$(info dirs:......$(dirs))

## destructive!
clean:
	rm -rf $(SRCDIR)
	rm -rf $(BASEDIR)
	rm -rf $(IMGDIR)
	rm -rf *.tmp1
	rm -rf *.tmp2

## just remove a single image
clean-image:
	rm -rf $(IMGDIR)/$(SNAME)

## get our source images
sources:	$(SRCDIR)/$(DISTRO)

$(SRCDIR)/$(DISTRO):
	@:$(call check_defined,NAME)
	mkdir -p $(SRCDIR)/$(DISTRO)
	cd $(SRCDIR)/$(DISTRO) && wget $(URL)
	
## setup the base master qcow2 images
base:	sources $(BASEDIR)/$(DISTRO)

$(BASEDIR)/$(DISTRO):	$(BASEDIR)/$(DISTRO)/rootfs.qcow2

$(BASEDIR)/$(DISTRO)/rootfs.qcow2:
	mkdir -p $(BASEDIR)/$(DISTRO)
	cp -v $(SRCDIR)/$(DISTRO)/$(SRC) $(BASEDIR)/$(DISTRO)/rootfs.qcow2

## create a node image
image:	base $(IMGDIR)/$(SNAME)

$(IMGDIR)/$(SNAME): $(IMGDIR)/$(SNAME)/rootfs.qcow2

$(IMGDIR)/$(SNAME)/rootfs.qcow2:
	mkdir -p $(IMGDIR)/$(SNAME)
ifeq ($(ROOTSIZE),0)
	qemu-img create -f qcow2 -b $(BASEDIR)/$(DISTRO)/rootfs.qcow2 $(IMGDIR)/$(SNAME)/rootfs.qcow2
else
	qemu-img create -f qcow2 -b $(BASEDIR)/$(DISTRO)/rootfs.qcow2 $(IMGDIR)/$(SNAME)/rootfs.qcow2
	qemu-img resize $(IMGDIR)/$(SNAME)/rootfs.qcow2 $(ROOTSIZE)G
endif
	qemu-img info $(IMGDIR)/$(SNAME)/rootfs.qcow2

# configure the user-data PACKAGES base on ROLE setting
role:	$(IMGDIR)/$(SNAME)/user-data

# install packages-$(ROLE)
$(IMGDIR)/$(SNAME)/user-data:
	cp user-data.tmpl user-data.tmp1
	sed "/PACKAGES/r ./packages-$(ROLE)" user-data.tmpl > user-data.tmp2
	cp user-data.tmp2 user-data.tmp1
	sed "/BOOTCMD/r ./bootcmd-$(ROLE).tmpl" user-data.tmp1 > user-data.tmp2
	cp user-data.tmp2 user-data.tmp1
	sed "/MOUNTS/r ./mounts-$(ROLE).tmpl" user-data.tmp1 > user-data.tmp2
	cp user-data.tmp2 user-data

## pull all the disk stuff together
disks:	rootfs swap data db web

## create our node root disk
rootfs:	image 

## create our node swap disk
swap:	$(IMGDIR)/$(SNAME)/swap.qcow2

$(IMGDIR)/$(SNAME)/swap.qcow2:
	mkdir -p $(IMGDIR)/$(SNAME)
	if [ $(SWAPSIZE) -gt 0 ]; then \
		qemu-img create -f qcow2 $(IMGDIR)/$(SNAME)/swap.qcow2 $(SWAPSIZE)G; \
	fi

## create our node data disk
data:	$(IMGDIR)/$(SNAME)/data.qcow2

$(IMGDIR)/$(SNAME)/data.qcow2:
	mkdir -p $(IMGDIR)/$(SNAME)
	if [ $(DATASIZE) -gt 0 ]; then \
		qemu-img create -f qcow2 $(IMGDIR)/$(SNAME)/data.qcow2 $(DATASIZE)G; \
	fi

db:	$(IMGDIR)/$(SNAME)/db.qcow2

$(IMGDIR)/$(SNAME)/db.qcow2:
	mkdir -p $(IMGDIR)/$(SNAME)
	if [ $(DBSIZE) -gt 0 ]; then \
		qemu-img create -f qcow2 $(IMGDIR)/$(SNAME)/db.qcow2 $(DBSIZE)G; \
	fi

web:	$(IMGDIR)/$(SNAME)/docroot.qcow2

$(IMGDIR)/$(SNAME)/docroot.qcow2:
	mkdir -p $(IMGDIR)/$(SNAME)
	if [ $(WEBSIZE) -gt 0 ]; then \
		qemu-img create -f qcow2 $(IMGDIR)/$(SNAME)/docroot.qcow2 $(WEBSIZE)G; \
	fi


## create our installation cdrom
config.iso:	role disks network-config
	genisoimage -o $(IMGDIR)/$(SNAME)/config.iso -V cidata -r -J $(IMGDIR)/$(SNAME)/meta-data $(IMGDIR)/$(SNAME)/user-data $(IMGDIR)/$(SNAME)/network-config


## create the network configuration
network-config:	meta-data $(IMGDIR)/$(SNAME)/network-config

$(IMGDIR)/$(SNAME)/network-config:
ifeq ($(NET),static)
	cp network-config-static.tmpl $(IMGDIR)/$(SNAME)/network-config
	sed -i "s/<IPADDRESS>/$(IPADDRESS)/g" $(IMGDIR)/$(SNAME)/network-config
endif
ifeq ($(NET),dhcp)
	cp network-config-dhcp.tmpl $(IMGDIR)/$(SNAME)/network-config
endif

## create the cloud-init meta-data
meta-data:	$(IMGDIR)/$(SNAME)/meta-data

$(IMGDIR)/$(SNAME)/meta-data:
	echo "instance-id: $(UUID)" > $(IMGDIR)/$(SNAME)/meta-data
	echo "role: $(ROLE)" >> $(IMGDIR)/$(SNAME)/meta-data
	echo "aenv: $(ENV)" >> $(IMGDIR)/$(SNAME)/meta-data
	echo "local-hostname: $(NAME)" >> $(IMGDIR)/$(SNAME)/meta-data
	echo "public-keys: " >> $(IMGDIR)/$(SNAME)/meta-data
	echo "- `cat $(HOME)/.ssh/id_rsa.pub`" >> $(IMGDIR)/$(SNAME)/meta-data
	cp user-data $(IMGDIR)/$(SNAME)/user-data

## delete our node
Delete:
	@:$(call check_defined,NAME)
	virsh destroy $(SNAME) || echo "Node stop failed for $(SNAME)"
	virsh undefine $(SNAME) --remove-all-storage
	rm -rf $(IMGDIR)/$(SNAME)
	sudo sed -i "/^$(NAME).*/d" /etc/ansible/hosts
	make -e NAME=$(NAME) clean-image

## create a node using virt-install
node:	config.iso
	@:$(call check_defined,NAME)

	virt-install --connect=qemu:///system --name $(SNAME) --ram $(RAM) --vcpus=$(VCPUS) --os-type=linux --os-variant=ubuntu16.04 --disk path=$(IMGDIR)/$(SNAME)/rootfs.qcow2,device=disk,bus=virtio $(SWAPDISK) $(DATADISK) $(DBDISK) $(WEBDISK) --disk path=$(IMGDIR)/$(SNAME)/config.iso,device=cdrom --graphics none --import --wait=-1
	sudo echo "$(NAME)" >> /etc/ansible/hosts
	virsh start $(SNAME)


