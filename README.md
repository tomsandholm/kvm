# kvm
kvm builder tools

Variables:
<pre>
key variables are:
DISTRO:...(xenial|bionic) (default: xenial)
SWAPSIZE:.(GB) (default: 2)
DATASIZE:.(GB) (default: 0)
RAM:......(MB) (default: 2048)
VCPUS:....(COUNT) (default: 2)
NAME:.....fqdn (REQUIRED) 
NET:......(static|dhcp) (default: static)

Targets
help    --> This help
list    --> List currently defined libvirt nodes
targets --> Produce this listing
stats   --> Display variable info
clean   --> Clean
sources --> Build sources directory
base    --> Build qcow2 base images
image   --> libvirt node images
disks   --> Create node disks
rootfs  --> Create node rootfs disk
swap    --> Create node swap disk
data    --> Create node data disk
Delete  --> Delete node
node    --> Create node

Tasks:

Build a node using defaults:
make -e NAME=some-node-fqdn node

Build a node with a data disk of 8 gb
make -e NAME=fqdn DATASIZE=8 node

Build a node from distro xenial
make -e NAME=fqdn DISTRO=xenial node

Delete a node
make -e NAME=fqdn Delete

</pre>
