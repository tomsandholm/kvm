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

DISTRO := xenial
#DISTRO := bionic
SNAME = $(shell echo $(NAME) | cut -d'.' -f1)
URL := $(shell egrep "^$(DISTRO)" ./distro | cut -d';' -f3)
SRC := $(shell egrep "^$(DISTRO)" ./distro | cut -d';' -f4)
UUID := $(shell uuidgen)
IPADDRESS := $(shell getent hosts $(SNAME)|awk '{print $$1}')
ROLE := general
ENV := dev
## in GB
SWAPSIZE := 2
## in GB
DATASIZE := 0
RAM := 2048
VCPUS := 2
OS-VARIANT := ubuntu16.04
ETCDIR := /etc/kvmbld
VARDIR := /var/lib/kvmbld
BASEDIR := $(VARDIR)/base
IMGDIR := $(VARDIR)/images
SRCDIR := $(VARDIR)/sources
NET := static
SWAPDISK := --disk path=$(IMGDIR)/$(SNAME)/swap.qcow2,device=disk,bus=virtio
DATADISK := --disk path=$(IMGDIR)/$(SNAME)/data.qcow2,device=disk,bus=virtio

ifeq ($(SWAPSIZE),0)
	SWAPDISK := 
endif

ifeq ($(DATASIZE),0)
	DATADISK :=
endif

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
image:	$(IMGDIR)/$(SNAME)

$(IMGDIR)/$(SNAME): $(IMGDIR)/$(SNAME)/rootfs.qcow2

$(IMGDIR)/$(SNAME)/rootfs.qcow2:
	mkdir -p $(IMGDIR)/$(SNAME)
	qemu-img create -f qcow2 -b $(BASEDIR)/$(DISTRO)/rootfs.qcow2 $(IMGDIR)/$(SNAME)/rootfs.qcow2
	qemu-img info $(IMGDIR)/$(SNAME)/rootfs.qcow2

## pull all the disk stuff together
disks:	rootfs swap data

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

## create our installation cdrom
config.iso:	disks network-config
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
	rm -rf nodes/$(SNAME)
	sudo sed -i "/^$(NAME).*/d" /etc/ansible/hosts
	make -e NAME=$(NAME) clean-image

## create a node using virt-install
node:	config.iso
	@:$(call check_defined,NAME)

	virt-install --connect=qemu:///system --name $(SNAME) --ram $(RAM) --vcpus=$(VCPUS) --os-type=linux --os-variant=ubuntu16.04 --disk path=$(IMGDIR)/$(SNAME)/rootfs.qcow2,device=disk,bus=virtio $(SWAPDISK) $(DATADISK) --disk path=$(IMGDIR)/$(SNAME)/config.iso,device=cdrom --graphics none --import --wait=-1
	sudo echo "$(NAME)" >> /etc/ansible/hosts
	virsh start $(SNAME)


