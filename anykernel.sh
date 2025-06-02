# AnyKernel3 Ramdisk Mod Script
# Samsung Galaxy Note 10+ (d1) Custom Kernel Package
properties() { '
kernel.string=Custom Kernel for Galaxy Note 10+ (d1) by Cursor AI
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=d1
device.name2=d1q
device.name3=SM-N975F
device.name4=SM-N975U
device.name5=SM-N975N
supported.versions=9.0,10.0,11.0,12.0
supported.patchlevels=
'; }

# Shell variables
block=/dev/block/by-name/boot;
is_slot_device=0;
ramdisk_compression=auto;
patch_vbmeta_flag=auto;

# Import functions/variables and setup
. tools/ak3-core.sh;

# Install kernel
dump_boot;
write_boot;