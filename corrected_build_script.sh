#!/bin/bash
# Build script for Samsung Exynos 9820 (Galaxy S10/Note10) kernel with KernelSU
# Model: d1 (Galaxy Note 10+)

# Exit on any error
set -e

# --- Configuration ---
KERNEL_DIR="/home/joshua/Desktop/android_kernel_d1/samsung-exynos9820"
OUT_DIR="/home/joshua/Desktop/android_kernel_d1/build_output"
TOOLCHAIN_DIR="/home/joshua/proton-clang"
PREBUILT_DTC_PATH="/usr/local/bin/dtc"

# Kernel configuration
DEFCONFIG="exynos9820-d1_defconfig"
ARCH="arm64"
NUM_JOBS=$(nproc --all)

# KernelSU configuration
KERNELSU_REPO_URL="https://github.com/tiann/KernelSU.git"
KERNELSU_SOURCE_SUBDIR="kernelsu_src"

# AnyKernel3 configuration
ANYKERNEL_DIR="/home/joshua/Desktop/android_kernel_d1/AnyKernel3"
ANYKERNEL_URL="https://github.com/osm0sis/AnyKernel3.git"
AK3_ZIP_NAME="KernelSU_Note10Plus_$(date +%Y%m%d-%H%M).zip"

# Stock boot image for repacking
STOCK_BOOT_IMG="/home/joshua/Desktop/android_kernel_d1/stock_boot.img"
FINAL_BOOT_IMG="$OUT_DIR/boot.img"
FINAL_TAR_MD5="$OUT_DIR/boot.tar.md5"

# --- Helper Functions ---
info() {
    echo -e "\033[1;34m[INFO]\033[0m $1"
}

error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1" >&2
    exit 1
}

# --- Pre-flight checks ---
info "Checking prerequisites..."

# Check if kernel source exists
if [ ! -d "$KERNEL_DIR" ]; then
    error "Kernel source directory not found at $KERNEL_DIR"
fi

# Check if toolchain exists or use system GCC
USE_PROTON_CLANG=false
# Temporarily disable proton-clang due to system compatibility issues
# if [ -d "$TOOLCHAIN_DIR" ]; then
#     # Check if the proton-clang is compatible with the system
#     if "$TOOLCHAIN_DIR/bin/clang" --version &>/dev/null; then
#         USE_PROTON_CLANG=true
#         info "Using proton-clang toolchain"
#     else
#         info "Proton-clang appears incompatible with this system, falling back to GCC"
#     fi
# fi

if [ "$USE_PROTON_CLANG" = false ]; then
    # Check for system GCC cross-compiler
    if ! command -v aarch64-linux-gnu-gcc &> /dev/null; then
        info "Installing GCC cross-compiler..."
        sudo apt-get update
        sudo apt-get install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
    fi
    info "Using system GCC cross-compiler"
fi

# Check if pre-built DTC exists
if [ ! -f "$PREBUILT_DTC_PATH" ]; then
    error "Pre-built DTC not found at $PREBUILT_DTC_PATH. Please install it first."
fi

# Navigate to kernel directory
cd "$KERNEL_DIR" || error "Failed to navigate to kernel directory"

# --- Clean previous builds ---
info "Cleaning previous builds..."
rm -rf "$OUT_DIR" && mkdir -p "$OUT_DIR"

# --- Set up build environment ---
if [ "$USE_PROTON_CLANG" = true ]; then
    # Add toolchain to PATH
    export PATH="$TOOLCHAIN_DIR/bin:$PATH"
    
    # Set up for clang
    export ARCH=$ARCH
    export SUBARCH=$ARCH
    export CROSS_COMPILE=aarch64-linux-gnu-
    export CROSS_COMPILE_ARM32=arm-linux-gnueabi-
    export CC=clang
    export CLANG_TRIPLE=aarch64-linux-gnu-
    export AR=llvm-ar
    export NM=llvm-nm
    export OBJCOPY=llvm-objcopy
    export OBJDUMP=llvm-objdump
    export STRIP=llvm-strip
    export HOSTCC=gcc
    export HOSTCXX=g++
    export HOSTLD=ld
else
    # Set up for GCC
    export ARCH=$ARCH
    export SUBARCH=$ARCH
    export CROSS_COMPILE=aarch64-linux-gnu-
    export HOSTCC=gcc
    export HOSTCXX=g++
fi

# Set up build environment with external DTC
export DTC="$PREBUILT_DTC_PATH"
export PATH="$PREBUILT_DTC_PATH:$PATH"

# Copy external DTC to kernel scripts directory to prevent building
info "Setting up external DTC to avoid build conflicts..."
mkdir -p "$KERNEL_DIR/scripts/dtc"
cp "$PREBUILT_DTC_PATH" "$KERNEL_DIR/scripts/dtc/dtc"
chmod +x "$KERNEL_DIR/scripts/dtc/dtc"

# Modify DTC Makefile to prevent building
DTC_MAKEFILE="$KERNEL_DIR/scripts/dtc/Makefile"
if [ -f "$DTC_MAKEFILE" ]; then
    # Comment out the DTC build rules to prevent conflicts
    sed -i 's/^hostprogs-y.*dtc/# &/' "$DTC_MAKEFILE"
    sed -i 's/^dtc-objs/# &/' "$DTC_MAKEFILE"
    sed -i 's/^always.*dtc/# &/' "$DTC_MAKEFILE"
fi

# Fix SELinux classmap check - update the maximum to allow for 46 address families
info "Patching SELinux classmap.h maximum check..."
sed -i 's/#if PF_MAX > 44/#if PF_MAX > 46/' "$KERNEL_DIR/security/selinux/include/classmap.h"

if [ "$USE_PROTON_CLANG" = true ]; then
    export CROSS_COMPILE="aarch64-linux-gnu-"
    export CC="$TOOLCHAIN_DIR/bin/clang"
    export CLANG_TRIPLE="aarch64-linux-gnu-"
    export PATH="$TOOLCHAIN_DIR/bin:$PATH"
else
    export CROSS_COMPILE="aarch64-linux-gnu-"
    export CC="aarch64-linux-gnu-gcc"
fi

# Force the use of external DTC to avoid compilation issues
make_flags=(
    "ARCH=$ARCH"
    "O=$OUT_DIR"
    "CROSS_COMPILE=$CROSS_COMPILE"
    "CC=$CC"
    "DTC=$PREBUILT_DTC_PATH"
    "EXTRA_CFLAGS=-Wno-error=format-extra-args -Wno-error=format -Wno-error=array-bounds -Wno-error=array-compare -Wno-error=maybe-uninitialized -Wno-error=address -Wno-error=address-of-packed-member -Wno-error=missing-attributes -Wno-error=restrict -Wno-error=unused-result -Wno-error=zero-length-bounds -Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types -Wno-error=strict-aliasing -Wno-error=cast-align -Wno-error=uninitialized -Wno-error=stringop-overflow -Wno-error=stringop-truncation -Wno-error=sizeof-pointer-memaccess -Wno-error=misleading-indentation -Wno-error=unused-function -Wno-error=unused-variable -Wno-error -Wno-error=strict-prototypes"
    "-j$NUM_JOBS"
)

# Clean with proper parameters
info "Cleaning previous builds..."
make "${make_flags[@]}" clean

# Update config
make "${make_flags[@]}" olddefconfig

# Create dummy NPU firmware to satisfy build if it doesn't exist
FIRMWARE_NPU_DIR="$KERNEL_DIR/firmware/npu"
FIRMWARE_NPU_BIN="$FIRMWARE_NPU_DIR/NPU.bin"
if [ ! -f "$FIRMWARE_NPU_BIN" ]; then
    info "Creating dummy NPU.bin firmware at $FIRMWARE_NPU_BIN"
    mkdir -p "$FIRMWARE_NPU_DIR"
    touch "$FIRMWARE_NPU_BIN"
fi

# Create dummy y771_d1.bin TSP firmware
FIRMWARE_TSP_DIR="$KERNEL_DIR/firmware/tsp_sec"
FIRMWARE_TSP_BIN="$FIRMWARE_TSP_DIR/y771_d1.bin"
if [ ! -f "$FIRMWARE_TSP_BIN" ]; then
    info "Creating dummy y771_d1.bin TSP firmware at $FIRMWARE_TSP_BIN"
    mkdir -p "$FIRMWARE_TSP_DIR"
    touch "$FIRMWARE_TSP_BIN"
fi

# Create dummy y771_d2.bin TSP firmware
FIRMWARE_TSP_D2_BIN="$FIRMWARE_TSP_DIR/y771_d2.bin"
if [ ! -f "$FIRMWARE_TSP_D2_BIN" ]; then
    info "Creating dummy y771_d2.bin TSP firmware at $FIRMWARE_TSP_D2_BIN"
    # No need for mkdir -p as $FIRMWARE_TSP_DIR should exist from previous y771_d1.bin creation
    touch "$FIRMWARE_TSP_D2_BIN"
fi

# Create dummy y771_d1_bringup.bin TSP firmware
FIRMWARE_TSP_D1_BRINGUP_BIN="$FIRMWARE_TSP_DIR/y771_d1_bringup.bin"
if [ ! -f "$FIRMWARE_TSP_D1_BRINGUP_BIN" ]; then
    info "Creating dummy y771_d1_bringup.bin TSP firmware at $FIRMWARE_TSP_D1_BRINGUP_BIN"
    touch "$FIRMWARE_TSP_D1_BRINGUP_BIN"
fi

# --- Configure kernel ---
info "Configuring kernel with $DEFCONFIG..."
make "${make_flags[@]}" "$DEFCONFIG"

# --- TEMPORARILY DISABLED: KernelSU Integration ---
# info "Integrating KernelSU..."
# KERNELSU_SRC_PATH="$KERNEL_DIR/$KERNELSU_SOURCE_SUBDIR"

# if [ ! -d "$KERNELSU_SRC_PATH" ]; then
#     info "Cloning KernelSU repository..."
#     git clone --depth=1 "$KERNELSU_REPO_URL" "$KERNELSU_SRC_PATH"
# else
#     info "Updating KernelSU..."
#     cd "$KERNELSU_SRC_PATH"
#     git fetch --depth=1 origin main
#     git reset --hard origin/main
#     cd "$KERNEL_DIR"
# fi

# # Create symlink for KernelSU in drivers
# info "Creating KernelSU symlink..."
# mkdir -p "$KERNEL_DIR/drivers"
# if [ -L "$KERNEL_DIR/drivers/kernelsu" ]; then
#     rm -f "$KERNEL_DIR/drivers/kernelsu"
# fi
# ln -sf "../$KERNELSU_SOURCE_SUBDIR/kernel" "$KERNEL_DIR/drivers/kernelsu"

# # Add KernelSU to drivers Makefile
# if ! grep -q "CONFIG_KSU" "$KERNEL_DIR/drivers/Makefile"; then
#     echo 'obj-$(CONFIG_KSU) += kernelsu/' >> "$KERNEL_DIR/drivers/Makefile"
#     info "Added KernelSU to drivers/Makefile"
# fi

# # Add KernelSU to drivers Kconfig
# if ! grep -q 'source "drivers/kernelsu/Kconfig"' "$KERNEL_DIR/drivers/Kconfig"; then
#     # Find endmenu and insert before it
#     if grep -q "^endmenu" "$KERNEL_DIR/drivers/Kconfig"; then
#         sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' "$KERNEL_DIR/drivers/Kconfig"
#     else
#         echo 'source "drivers/kernelsu/Kconfig"' >> "$KERNEL_DIR/drivers/Kconfig"
#     fi
#     info "Added KernelSU to drivers/Kconfig"
# fi

info "KernelSU integration temporarily disabled for base kernel build"

# --- Apply patches ---
info "Applying necessary patches..."

# Patch for SELinux classmap.h
CLASSMAP_PATH="$KERNEL_DIR/security/selinux/include/classmap.h"
if [ -f "$CLASSMAP_PATH" ]; then
    info "Patching SELinux classmap.h..."
    
    # Add stddef.h include for NULL
    if ! grep -q "#include <stddef.h>" "$CLASSMAP_PATH"; then
        sed -i '1i#include <stddef.h>' "$CLASSMAP_PATH"
    fi
    
    # Change flask.h include to local
    sed -i 's|#include <flask.h>|#include "flask.h"|g' "$CLASSMAP_PATH"
    
    # Add missing socket classes if needed
    if ! grep -q "netlink_smc_socket" "$CLASSMAP_PATH"; then
        sed -i '/netlink_xfrm_socket/a\\tsel_avc_socket_compat(NETLINK_SMC, "netlink_smc_socket")' "$CLASSMAP_PATH"
    fi
    
    # Update PF_MAX
    sed -i 's/#define PF_MAX\s*[0-9]\+/#define PF_MAX 45/' "$CLASSMAP_PATH"
    
    # Add bpf capability if missing
    if ! grep -q '"bpf",' "$CLASSMAP_PATH"; then
        sed -i '/"audit_read",/a\\t\t"bpf",' "$CLASSMAP_PATH"
    fi
    
    info "SELinux classmap.h patched"
fi

# Patch vision-dev.c to find vision-config.h
VISION_DEV_C_PATH="$KERNEL_DIR/drivers/vision/vision-core/vision-dev.c"
if [ -f "$VISION_DEV_C_PATH" ]; then
    if grep -q '#include "vision-config.h"' "$VISION_DEV_C_PATH"; then
        info "Patching include path in $VISION_DEV_C_PATH for vision-config.h"
        sed -i 's|#include "vision-config.h"|#include "../include/vision-config.h"|' "$VISION_DEV_C_PATH"
    fi
fi

# --- Configure KernelSU options ---
info "Configuring base kernel options..."
# TEMPORARILY DISABLED: KernelSU specific options
# echo "CONFIG_KPROBES=y" >> "$OUT_DIR/.config"
# echo "CONFIG_HAVE_KPROBES=y" >> "$OUT_DIR/.config"
# echo "CONFIG_KPROBE_EVENTS=y" >> "$OUT_DIR/.config"
echo "CONFIG_OVERLAY_FS=y" >> "$OUT_DIR/.config"
echo "CONFIG_MODULE_SIG=n" >> "$OUT_DIR/.config"

# Disable problematic TCP congestion control modules
echo "# CONFIG_TCP_CONG_WESTWOOD is not set" >> "$OUT_DIR/.config"
echo "# CONFIG_TCP_CONG_HTCP is not set" >> "$OUT_DIR/.config"

# Ensure KernelSU is disabled
echo "# CONFIG_KSU is not set" >> "$OUT_DIR/.config"

# Configure Mali GPU driver for Exynos 9820 (Mali-G76 MP12)
echo "CONFIG_MALI_DDK_VERSION=y" >> "$OUT_DIR/.config"
echo "CONFIG_MALI_BIFROST_R26P0=y" >> "$OUT_DIR/.config"
echo "# CONFIG_MALI_BIFROST_R32P1 is not set" >> "$OUT_DIR/.config"
echo "# CONFIG_MALI_BIFROST_R19P0_Q is not set" >> "$OUT_DIR/.config"
echo "# CONFIG_MALI_BIFROST_R16P0 is not set" >> "$OUT_DIR/.config"
echo "# CONFIG_MALI_BIFROST_R14P0 is not set" >> "$OUT_DIR/.config"
echo "# CONFIG_MALI_BIFROST_R12P0 is not set" >> "$OUT_DIR/.config"
echo "# CONFIG_MALI_BIFROST_R10P0 is not set" >> "$OUT_DIR/.config"
echo "CONFIG_MALI_MIDGARD=y" >> "$OUT_DIR/.config"
echo "CONFIG_MALI_EXPERT=y" >> "$OUT_DIR/.config"
echo "CONFIG_MALI_DVFS=y" >> "$OUT_DIR/.config"
echo "CONFIG_MALI_DEBUG_SYS=y" >> "$OUT_DIR/.config"
echo "CONFIG_MALI_DEBUG_KERNEL_SYSFS=y" >> "$OUT_DIR/.config"
echo "CONFIG_MALI_REAL_HW=y" >> "$OUT_DIR/.config"
echo "CONFIG_MALI_DMA_BUF_LEGACY_COMPAT=y" >> "$OUT_DIR/.config"
echo "CONFIG_MALI_PLATFORM_NAME=\"exynos\"" >> "$OUT_DIR/.config"
echo "CONFIG_MALI_EXYNOS_CLOCK=y" >> "$OUT_DIR/.config"
echo "CONFIG_MALI_EXYNOS_DVFS=y" >> "$OUT_DIR/.config"
echo "CONFIG_MALI_EXYNOS_PM=y" >> "$OUT_DIR/.config"
echo "CONFIG_MALI_EXYNOS_RTPM=y" >> "$OUT_DIR/.config"
echo "CONFIG_MALI_EXYNOS_QOS=y" >> "$OUT_DIR/.config"
echo "CONFIG_MALI_EXYNOS_THERMAL=y" >> "$OUT_DIR/.config"
echo "CONFIG_MALI_EXYNOS_BTS_MO=y" >> "$OUT_DIR/.config"
echo "CONFIG_MALI_EXYNOS_DEBUG=y" >> "$OUT_DIR/.config"
echo "CONFIG_MALI_EXYNOS_DEVICETREE=y" >> "$OUT_DIR/.config"
echo "CONFIG_MALI_EXYNOS_CL_BOOST=y" >> "$OUT_DIR/.config"
echo "CONFIG_MALI_PRFCNT_SET_PRIMARY=y" >> "$OUT_DIR/.config"

echo "CONFIG_MALI_PLATFORM_THIRDPARTY=n" >> "$OUT_DIR/.config"
echo "CONFIG_MALI_PLATFORM_THIRDPARTY_NAME=\"exynos\"" >> "$OUT_DIR/.config"

echo "CONFIG_MALI_PRFCNT_SET_SECONDARY=n" >> "$OUT_DIR/.config"
echo "CONFIG_MALI_PRFCNT_SET_SECONDARY_VIA_DEBUG_FS=n" >> "$OUT_DIR/.config"
echo "CONFIG_MALI_RT_PM=y" >> "$OUT_DIR/.config"
echo "CONFIG_MALI_EXYNOS_TRACE=n" >> "$OUT_DIR/.config"
echo "CONFIG_MALI_SEC_CL_BOOST=y" >> "$OUT_DIR/.config"
echo "CONFIG_MALI_PM_QOS=y" >> "$OUT_DIR/.config"
echo "CONFIG_MALI_SEC_VK_BOOST=n" >> "$OUT_DIR/.config"

# Add dummy define for CONFIG_OPTION_REGION if not present in modem_main.c
MODEM_MAIN_C_PATH="$KERNEL_DIR/drivers/misc/modem_v1/modem_main.c"
if [ -f "$MODEM_MAIN_C_PATH" ]; then
    if ! grep -q "#define CONFIG_OPTION_REGION" "$MODEM_MAIN_C_PATH"; then
        info "Adding dummy define for CONFIG_OPTION_REGION to $MODEM_MAIN_C_PATH"
        # Add it after the last include, a bit crudely for now.
        # A better way would be to find a suitable spot or use a dedicated patch file.
        LAST_INCLUDE_LINE=$(grep -n "#include" "$MODEM_MAIN_C_PATH" | tail -n 1 | cut -d: -f1)
        if [ -n "$LAST_INCLUDE_LINE" ]; then
            sed -i "${LAST_INCLUDE_LINE}a\\#ifndef CONFIG_OPTION_REGION\\n#define CONFIG_OPTION_REGION \"DEFAULT_REGION\"\\n#endif" "$MODEM_MAIN_C_PATH"
        else # Fallback if no includes found, add at top (less ideal)
            sed -i '1i\\#ifndef CONFIG_OPTION_REGION\\n#define CONFIG_OPTION_REGION "DEFAULT_REGION"\\n#endif' "$MODEM_MAIN_C_PATH"
        fi
    fi
fi

# Add dummy define for CONFIG_OPTION_REGION if not present in link_device_memory_sbd.c
LINK_DEV_MEM_SBD_C_PATH="$KERNEL_DIR/drivers/misc/modem_v1/link_device_memory_sbd.c"
if [ -f "$LINK_DEV_MEM_SBD_C_PATH" ]; then
    if ! grep -q "#define CONFIG_OPTION_REGION" "$LINK_DEV_MEM_SBD_C_PATH"; then
        info "Adding dummy define for CONFIG_OPTION_REGION to $LINK_DEV_MEM_SBD_C_PATH"
        LAST_INCLUDE_LINE=$(grep -n "#include" "$LINK_DEV_MEM_SBD_C_PATH" | tail -n 1 | cut -d: -f1)
        if [ -n "$LAST_INCLUDE_LINE" ]; then
            sed -i "${LAST_INCLUDE_LINE}a\\#ifndef CONFIG_OPTION_REGION\\n#define CONFIG_OPTION_REGION \"DEFAULT_REGION\"\\n#endif" "$LINK_DEV_MEM_SBD_C_PATH"
        else # Fallback if no includes found, add at top (less ideal)
            sed -i '1i\\#ifndef CONFIG_OPTION_REGION\\n#define CONFIG_OPTION_REGION "DEFAULT_REGION"\\n#endif' "$LINK_DEV_MEM_SBD_C_PATH"
        fi
    fi
fi

# --- Build kernel ---
info "Building kernel with $NUM_JOBS jobs..."

# Build the kernel
make "${make_flags[@]}"

# Check if kernel image was built successfully
KERNEL_IMAGE="$OUT_DIR/arch/arm64/boot/Image"
if [ ! -f "$KERNEL_IMAGE" ]; then
    error "Kernel build failed! Image not found at $KERNEL_IMAGE"
    exit 1
fi

info "Kernel built successfully!"
info "Kernel image: $KERNEL_IMAGE"

# --- Package kernel ---
info "Packaging kernel..."

# Clone or update AnyKernel3
if [ ! -d "$ANYKERNEL_DIR" ]; then
    info "Cloning AnyKernel3..."
    git clone "$ANYKERNEL_URL" "$ANYKERNEL_DIR"
else
    info "Updating AnyKernel3..."
    cd "$ANYKERNEL_DIR"
    git pull
    cd "$KERNEL_DIR"
fi

# Prepare AnyKernel3 directory
cd "$ANYKERNEL_DIR"
rm -rf Image.gz dtb modules
mkdir -p dtb modules

# Copy kernel image
cp "$KERNEL_IMAGE" ./

# Copy DTB files
find "$OUT_DIR/arch/$ARCH/boot/dts/" -name "*.dtb" -exec cp {} ./dtb/ \;

# Copy kernel modules if any
find "$OUT_DIR" -name "*.ko" -exec cp {} ./modules/ \;

# Create anykernel.sh configuration
cat > anykernel.sh << 'EOF'
# AnyKernel3 Ramdisk Mod Script
properties() { '
kernel.string=KernelSU for Galaxy Note 10+ (d1) by joshua
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=d1
device.name2=d1q
device.name3=
device.name4=
device.name5=
supported.versions=
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
EOF

# Create flashable zip
info "Creating flashable zip: $OUT_DIR/$AK3_ZIP_NAME"
zip -r9 "$OUT_DIR/$AK3_ZIP_NAME" * -x .git/\* README.md

# --- Create boot.img ---
if [ -f "$STOCK_BOOT_IMG" ]; then
    info "Creating boot.img..."
    cd "$OUT_DIR"
    
    # Use magiskboot if available, otherwise use mkbootimg
    if command -v magiskboot &> /dev/null; then
        cp "$STOCK_BOOT_IMG" boot_stock.img
        magiskboot unpack boot_stock.img
        cp "$KERNEL_IMAGE" kernel
        magiskboot repack boot_stock.img
        mv new-boot.img "$FINAL_BOOT_IMG"
        rm -f boot_stock.img kernel ramdisk.cpio*
    else
        info "magiskboot not found, skipping boot.img creation"
    fi
    
    # Create Odin flashable tar
    if [ -f "$FINAL_BOOT_IMG" ]; then
        info "Creating Odin flashable tar..."
        tar -H ustar -c boot.img -f boot.tar
        md5sum -t boot.tar >> boot.tar
        mv boot.tar "$FINAL_TAR_MD5"
    fi
fi

# --- Summary ---
info "Build completed successfully!"
echo "----------------------------------------------------"
echo " KernelSU for Galaxy Note 10+ Build Summary"
echo "----------------------------------------------------"
echo " Flashable ZIP: $OUT_DIR/$AK3_ZIP_NAME"
if [ -f "$FINAL_BOOT_IMG" ]; then
    echo " Boot Image: $FINAL_BOOT_IMG"
fi
if [ -f "$FINAL_TAR_MD5" ]; then
    echo " Odin TAR: $FINAL_TAR_MD5"
fi
echo "----------------------------------------------------"
echo "Remember to backup your device before flashing!"

# Robust prepend of __visible_for_testing macro for DEFEX sources using absolute paths
DEFEX_COMMON_C_ABS_PATH="/home/joshua/Desktop/android_kernel_d1/samsung-exynos9820/security/samsung/defex_lsm/core/defex_common.c"
DEFEX_LSM_C_ABS_PATH="/home/joshua/Desktop/android_kernel_d1/samsung-exynos9820/security/samsung/defex_lsm/core/defex_lsm.c"
DEFEX_MAIN_C_ABS_PATH="/home/joshua/Desktop/android_kernel_d1/samsung-exynos9820/security/samsung/defex_lsm/core/defex_main.c"
DEFEX_CACHES_C_ABS_PATH="/home/joshua/Desktop/android_kernel_d1/samsung-exynos9820/security/samsung/defex_lsm/catch_engine/defex_caches.c"
DEFEX_SIGN_C_ABS_PATH="/home/joshua/Desktop/android_kernel_d1/samsung-exynos9820/security/samsung/defex_lsm/cert/defex_sign.c"
DEFEX_RULES_PROC_C_ABS_PATH="/home/joshua/Desktop/android_kernel_d1/samsung-exynos9820/security/samsung/defex_lsm/core/defex_rules_proc.c"
MACRO_DEFINITION="#ifndef __visible_for_testing\n#define __visible_for_testing static\n#endif"

for DEFEX_FILE in "$DEFEX_COMMON_C_ABS_PATH" "$DEFEX_LSM_C_ABS_PATH" "$DEFEX_MAIN_C_ABS_PATH" "$DEFEX_CACHES_C_ABS_PATH" "$DEFEX_SIGN_C_ABS_PATH" "$DEFEX_RULES_PROC_C_ABS_PATH"; do
    echo "INFO: Ensuring __visible_for_testing definition is prepended to $DEFEX_FILE"
    if [ -f "$DEFEX_FILE" ]; then
        if ! grep -Fxq "#define __visible_for_testing static" "$DEFEX_FILE"; then
            echo -e "$MACRO_DEFINITION\n$(cat \"$DEFEX_FILE\")" > "$DEFEX_FILE.tmp" && mv "$DEFEX_FILE.tmp" "$DEFEX_FILE"
            echo "INFO: Macro prepended to $DEFEX_FILE."
        else
            echo "INFO: __visible_for_testing static define already present in $DEFEX_FILE."
        fi
    else
        echo "WARNING: $DEFEX_FILE not found. Cannot prepend macro."
    fi
done 