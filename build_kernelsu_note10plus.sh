#!/bin/bash
# build_kernelsu_note10plus.sh - Automated script to build KernelSU for Galaxy Note 10+ (SM-N975F)

# Exit on any error
set -e

# --- Configuration ---
NEW_KERNEL_SOURCE_URL="https://github.com/CruelKernel/samsung-exynos9820.git"
NEW_KERNEL_DIR="$HOME/CruelKernel_samsung-exynos9820"
KERNELSU_MAIN_DIR_NAME="KernelSU"
KERNELSU_REPO_URL="https://github.com/tiann/KernelSU.git"

ANYKERNEL_DIR="$HOME/AnyKernel3"
ANYKERNEL_URL="https://github.com/osm0sis/AnyKernel3.git"
AK3_ZIP_NAME="CruelKernelSU_Note10Plus_$(date +%Y%m%d-%H%M).zip"
OUT_DIR="$HOME/kernel_out" # Main out_dir for final products
STOCK_BOOT_IMG="$OUT_DIR/stock_boot.img"
FINAL_BOOT_IMG="$OUT_DIR/boot.img"
FINAL_TAR_MD5="$OUT_DIR/boot.tar.md5"

TOOLCHAIN_DIR="$HOME/proton-clang"
TOOLCHAIN_URL="https://github.com/kdrag0n/proton-clang.git"
TOOLCHAIN_BRANCH="master"

DEFCONFIG="exynos9820-d1_defconfig"
TARGET_BRANCH_NAME="samsung"

NUM_JOBS=$(nproc --all)
ARCH="arm64"
SUBARCH="arm64"
export ANDROID_MAJOR_VERSION=12

# Common make flags for Clang
MAKE_OPTS_CLANG="ARCH=$ARCH SUBARCH=$ARCH \
    O=$KERNEL_BUILD_OUT_DIR \
    LLVM=1 LLVM_IAS=1 \
    CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm \
    OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
    HOSTCC=clang HOSTLD=ld.lld \
    REGENERATE_PARSERS=1"

# --- Helper Functions ---
info() {
    echo -e "\033[1;34m[INFO]\033[0m $1"
}

error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1" >&2
    exit 1
}

# --- Main Script ---

info "Starting KernelSU build process for Samsung Galaxy Note 10+ \(SM-N975F\) using CruelKernel..."

info "Creating main output directory at $OUT_DIR..."
mkdir -p "$OUT_DIR"

if [ ! -f "$STOCK_BOOT_IMG" ]; then
    error "Stock boot image not found at $STOCK_BOOT_IMG. Please place it there and rename it to stock_boot.img."
fi
info "Stock boot image found."

info "Installing build dependencies..."
sudo apt-get update -y
sudo apt-get install -y git bc bison flex libssl-dev make libc6-dev libncurses5-dev \
    crossbuild-essential-arm64 libarchive-tools zip unzip ccache \
    python3 python3-pip rsync wget curl imagemagick libtinfo5 lz4 \
    libselinux1-dev libsepol-dev selinux-policy-dev --reinstall

if [ ! -d "$TOOLCHAIN_DIR" ]; then
    info "Cloning Proton Clang toolchain..."
    git clone --depth=1 -b "$TOOLCHAIN_BRANCH" "$TOOLCHAIN_URL" "$TOOLCHAIN_DIR"
else
    info "Proton Clang toolchain already exists. Skipping clone."
fi
export PATH="$TOOLCHAIN_DIR/bin:$PATH"
export LD_LIBRARY_PATH="$TOOLCHAIN_DIR/lib:$LD_LIBRARY_PATH"

info "Ensuring CruelKernel source: $NEW_KERNEL_SOURCE_URL"
if [ ! -d "$NEW_KERNEL_DIR" ]; then
    git clone "$NEW_KERNEL_SOURCE_URL" "$NEW_KERNEL_DIR"
else
    info "CruelKernel source directory $NEW_KERNEL_DIR already exists. Resetting and fetching all branches..."
    cd "$NEW_KERNEL_DIR"
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    if [ "$CURRENT_BRANCH" != "HEAD" ] && git rev-parse --verify HEAD >/dev/null 2>&1; then
        git reset --hard HEAD
    else
        info "Currently on detached HEAD or invalid repo state, attempting to ensure clean state for fetch."
        DEFAULT_REMOTE_BRANCH=$(git remote show origin | grep 'HEAD branch' | cut -d' ' -f5 || echo "master")
        git checkout "$DEFAULT_REMOTE_BRANCH" || true
        git reset --hard HEAD || true
    fi
    git clean -fdx
    info "Fetching all branches with explicit refspec..."
    git fetch origin refs/heads/*:refs/remotes/origin/* --prune
fi

cd "$NEW_KERNEL_DIR"
info "Currently in $NEW_KERNEL_DIR"

info "Checking out target branch: $TARGET_BRANCH_NAME"
if git rev-parse --verify --quiet "refs/heads/$TARGET_BRANCH_NAME"; then
    info "Local branch '$TARGET_BRANCH_NAME' already exists. Checking it out."
    git checkout "$TARGET_BRANCH_NAME"
else
    info "Local branch '$TARGET_BRANCH_NAME' does not exist. Creating and tracking origin/$TARGET_BRANCH_NAME."
    git checkout -b "$TARGET_BRANCH_NAME" "origin/$TARGET_BRANCH_NAME"
fi

info "Ensuring local '$TARGET_BRANCH_NAME' is up-to-date with remote."
git reset --hard "origin/$TARGET_BRANCH_NAME"
info "Successfully on branch '$TARGET_BRANCH_NAME'."
git branch --show-current

info "Makefile for branch '$TARGET_BRANCH_NAME':"
if [ -f "Makefile" ]; then head -n 5 Makefile; else error "Makefile not found."; fi

info "Integrating KernelSU..."
if [ ! -d "$KERNELSU_MAIN_DIR_NAME" ]; then
    info "Cloning KernelSU repository into $NEW_KERNEL_DIR/$KERNELSU_MAIN_DIR_NAME..."
    git clone --depth=1 "$KERNELSU_REPO_URL" "$KERNELSU_MAIN_DIR_NAME"
else
    info "KernelSU directory '$KERNELSU_MAIN_DIR_NAME' already exists. Ensuring it's up-to-date..."
    cd "$KERNELSU_MAIN_DIR_NAME"; git fetch --depth=1 origin main; git reset --hard origin/main; cd ..;
fi
if [ ! -f "$KERNELSU_MAIN_DIR_NAME/kernel/Kconfig" ]; then error "$KERNELSU_MAIN_DIR_NAME/kernel/Kconfig not found."; fi
info "KernelSU repository is present."
info "Creating/Correcting KernelSU Kconfig symlink..."
mkdir -p drivers
if [ -L "drivers/kernelsu" ]; then rm -f "drivers/kernelsu"; fi
if [ -d "drivers/kernelsu" ] && [ ! -L "drivers/kernelsu" ]; then rm -rf "drivers/kernelsu"; fi
ln -sf "../$KERNELSU_MAIN_DIR_NAME/kernel" drivers/kernelsu
info "KernelSU symlink created."

# Patch SELinux classmap.h
CLASSMAP_PATH="security/selinux/include/classmap.h"
if [ -f "$CLASSMAP_PATH" ]; then
    info "Patching $CLASSMAP_PATH for new address families..."
    # Ensure idempotency for AF_ definitions
    grep -q "xdp_socket" "$CLASSMAP_PATH" || sed -i '/{ "bpf",/i \        { "xdp_socket", { COMMON_SOCK_PERMS, NULL } },' "$CLASSMAP_PATH"
    grep -q "vsock_socket" "$CLASSMAP_PATH" || sed -i '/{ "bpf",/i \        { "vsock_socket", { COMMON_SOCK_PERMS, NULL } },' "$CLASSMAP_PATH"
    grep -q "kcm_socket" "$CLASSMAP_PATH" || sed -i '/{ "bpf",/i \        { "kcm_socket", { COMMON_SOCK_PERMS, NULL } },' "$CLASSMAP_PATH"
    grep -q "qipcrtr_socket" "$CLASSMAP_PATH" || sed -i '/{ "bpf",/i \        { "qipcrtr_socket", { COMMON_SOCK_PERMS, NULL } },' "$CLASSMAP_PATH"
    grep -q "smc_socket" "$CLASSMAP_PATH" || sed -i '/{ "bpf",/i \        { "smc_socket", { COMMON_SOCK_PERMS, NULL } },' "$CLASSMAP_PATH"
    
    # Robustly change the PF_MAX check to > 128
    sed -i 's/^#if PF_MAX > [0-9]\+/#if PF_MAX > 128 \/* Increased significantly to cover newer AFs *\//g' "$CLASSMAP_PATH"
    info "$CLASSMAP_PATH patched."
else
    error "$CLASSMAP_PATH not found."
fi

info "Skipping patches for scripts/Makefile.lib, relying on REGENERATE_PARSERS=1."
info "Attempting to patch scripts/dtc/Makefile to enforce dtc_ prefix for LEX and YACC."

# Remove any previous Makefile.host patches if they exist from old script versions
MAKEFILE_HOST_PATH="scripts/Makefile.host"
if [ -f "$MAKEFILE_HOST_PATH" ]; then
    if grep -q "DTC_PREFIX_FORCE_PATCH" "$MAKEFILE_HOST_PATH"; then
        info "Reverting previous DTC_PREFIX_FORCE_PATCH from $MAKEFILE_HOST_PATH..."
        # This removes lines containing the marker.
        sed -i '/DTC_PREFIX_FORCE_PATCH/d' "$MAKEFILE_HOST_PATH"
        info "$MAKEFILE_HOST_PATH DTC patch reverted/cleaned."
    else
        info "$MAKEFILE_HOST_PATH does not contain DTC_PREFIX_FORCE_PATCH. No revert needed."
    fi
else
    info "$MAKEFILE_HOST_PATH not found, skipping revert for it (expected if clean source)."
fi


# Clean up any previous Makefile.lib patches (V7)
MAKEFILE_LIB_PATH="scripts/Makefile.lib"
if [ -f "$MAKEFILE_LIB_PATH" ]; then
    if grep -q "# DTC_CMD_PATCH_V7" "$MAKEFILE_LIB_PATH"; then
        info "Reverting V7 patch from $MAKEFILE_LIB_PATH..."
        # This is complex to revert perfectly with sed, git checkout would be better.
        # For now, we'll assume git clean -fdx in the main script handles full revert if needed.
        # We will remove lines containing the V7 marker.
        sed -i "/# DTC_CMD_PATCH_V7/d" "$MAKEFILE_LIB_PATH"
        info "$MAKEFILE_LIB_PATH V7 patch markers removed."
    else
        info "$MAKEFILE_LIB_PATH does not contain V7 patch. No revert needed."
    fi
else
    info "$MAKEFILE_LIB_PATH not found, skipping V7 revert for it."
fi

# --- V17 Strategy for DTC Linker Error ---
# Goal: Both Flex and Bison use "dtc_" prefix. This is achieved by modifying
#       LEX_PREFIX_yy and YACC_PREFIX_yy in scripts/Makefile.lib to "dtc_".
#       This makes "dtc_" the default prefix for host tools if no other specific prefix is set.
#       No in-file prefix directives in .l or .y files.
#       All DTC-specific prefix patches in scripts/dtc/Makefile are removed.

# 1. Clean up ALL old DTC prefix patches from scripts/dtc/Makefile
DTC_MAKEFILE_PATH="scripts/dtc/Makefile"
if [ -f "$DTC_MAKEFILE_PATH" ]; then
    info "V17: Cleaning up ALL old DTC prefix patch markers and variable assignments from $DTC_MAKEFILE_PATH..."
    # Remove V3-V6 markers
    sed -i "/# DTC_LOCAL_PREFIX_OVERRIDE_PATCH/d" "$DTC_MAKEFILE_PATH"
    sed -i "/# DTC_FILE_SPECIFIC_PREFIX_PATCH/d" "$DTC_MAKEFILE_PATH"
    sed -i "/# DTC_TARGET_SPECIFIC_PREFIX_PATCH/d" "$DTC_MAKEFILE_PATH"
    # Remove V9 (nullify), V13 (set specific LEX/YACC_PREFIX vars), V14.2/V15.1 (HOSTFLAGS), V16.1 (LEX/YACC_PREFIX override) markers
    sed -i "/# DTC_NULLIFY_CMDLINE_PREFIX_FLAG_V9/d" "$DTC_MAKEFILE_PATH"
    sed -i "/# DTC_CMDLINE_PREFIX_SET_TO_DTC_V13/d" "$DTC_MAKEFILE_PATH"
    sed -i "/# DTC_HOSTFLAGS_PATCH_V14_2/d" "$DTC_MAKEFILE_PATH"
    sed -i "/# DTC_HOSTFLAGS_PATCH_V15_1/d" "$DTC_MAKEFILE_PATH"
    sed -i "/# DTC_LEX_YACC_PREFIX_OVERRIDE_V16_1/d" "$DTC_MAKEFILE_PATH"

    # Remove the actual variable assignment lines from various attempts
    sed -i "/^LEX_PREFIX_scripts_dtc_dtc-lexer\.lex\.c_shipped :=/d" "$DTC_MAKEFILE_PATH"
    sed -i "/^YACC_PREFIX_scripts_dtc_dtc-parser\.tab\.c_shipped :=/d" "$DTC_MAKEFILE_PATH"
    sed -i "/^YACC_PREFIX_scripts_dtc_dtc-parser\.tab\.h_shipped :=/d" "$DTC_MAKEFILE_PATH"
    sed -i "/^HOST_LEXFLAGS \+:= -Pdtc_/d" "$DTC_MAKEFILE_PATH"
    sed -i "/^HOST_YACCFLAGS \+:= -pdtc_/d" "$DTC_MAKEFILE_PATH"
    sed -i "/^HOST_LEXFLAGS := -Pdtc_/d" "$DTC_MAKEFILE_PATH"
    sed -i "/^HOST_YACCFLAGS := -pdtc_/d" "$DTC_MAKEFILE_PATH"
    sed -i "/^LEX_PREFIX := dtc_/d" "$DTC_MAKEFILE_PATH"
    sed -i "/^YACC_PREFIX := dtc_/d" "$DTC_MAKEFILE_PATH"
    info "$DTC_MAKEFILE_PATH fully cleaned of prior DTC prefix patches and variable assignments for V17."
else
    info "$DTC_MAKEFILE_PATH not found, skipping its cleanup (V17)."
fi

# 2. Patch scripts/Makefile.lib to change default yy prefixes to dtc_
MAKEFILE_LIB_PATH_FOR_V17="scripts/Makefile.lib" # Renamed to avoid conflict with other MAKEFILE_LIB_PATH
PATCH_MARKER_V17="# V17_DTC_DEFAULT_PREFIX_PATCH"
if [ -f "$MAKEFILE_LIB_PATH_FOR_V17" ]; then
    info "V17: Patching $MAKEFILE_LIB_PATH_FOR_V17 to set default LEX/YACC prefixes to 'dtc_'..."
    # Remove old V17 markers first for idempotency
    sed -i "/${PATCH_MARKER_V17}/d" "$MAKEFILE_LIB_PATH_FOR_V17"
    
    # Change LEX_PREFIX_yy = yy to LEX_PREFIX_yy = dtc_
    sed -i "s/^\(LEX_PREFIX_yy\s*=\s*\)yy/\1dtc_ ${PATCH_MARKER_V17}/" "$MAKEFILE_LIB_PATH_FOR_V17"
    # Change YACC_PREFIX_yy = yy to YACC_PREFIX_yy = dtc_
    sed -i "s/^\(YACC_PREFIX_yy\s*=\s*\)yy/\1dtc_ ${PATCH_MARKER_V17}/" "$MAKEFILE_LIB_PATH_FOR_V17"
    
    if grep -q "LEX_PREFIX_yy = dtc_" "$MAKEFILE_LIB_PATH_FOR_V17" && grep -q "YACC_PREFIX_yy = dtc_" "$MAKEFILE_LIB_PATH_FOR_V17"; then
        info "$MAKEFILE_LIB_PATH_FOR_V17 patched successfully for V17."
    else
        error "Failed to patch $MAKEFILE_LIB_PATH_FOR_V17 for V17. Prefixes not set to 'dtc_'."
    fi
    info "Content of $MAKEFILE_LIB_PATH_FOR_V17 around prefix definitions after V17 patch:"
    grep -C 5 "LEX_PREFIX_yy" "$MAKEFILE_LIB_PATH_FOR_V17" || true
    grep -C 5 "YACC_PREFIX_yy" "$MAKEFILE_LIB_PATH_FOR_V17" || true
else
    error "$MAKEFILE_LIB_PATH_FOR_V17 not found. Cannot apply V17 patches."
fi

# 3. Ensure scripts/dtc/dtc-lexer.l has NO flex prefix directive
DTC_LEXER_L_PATH="scripts/dtc/dtc-lexer.l"
PATCH_MARKER_L_V8_3="# DTC_L_PREFIX_DIRECTIVE_V8.3"
FLEX_DIRECTIVE_LINE_1="%option prefix=\"dtc_\""

if [ -f "$DTC_LEXER_L_PATH" ]; then
    info "V17: Ensuring no flex prefix directive is in $DTC_LEXER_L_PATH..."
    if grep -q "${PATCH_MARKER_L_V8_3}" "$DTC_LEXER_L_PATH" || grep -Fxq "${FLEX_DIRECTIVE_LINE_1}" "$DTC_LEXER_L_PATH"; then
        info "Found old flex prefix directive/marker in $DTC_LEXER_L_PATH. Removing for V17."
        awk -v marker="${PATCH_MARKER_L_V8_3}" -v directive="${FLEX_DIRECTIVE_LINE_1}" '
        BEGIN { skip_next = 0 }
        {
            if (skip_next) {
                skip_next = 0;
                next;
            }
            if ($0 == directive && getline next_line > 0 && index(next_line, marker) > 0) {
                skip_next = 1;
                next;
            }
            if ($0 == directive) { next; }
            if (index($0, marker) > 0) {next; }
            print;
        }' "$DTC_LEXER_L_PATH" > "${DTC_LEXER_L_PATH}.tmp" && mv "${DTC_LEXER_L_PATH}.tmp" "$DTC_LEXER_L_PATH"
        sed -i "/${FLEX_DIRECTIVE_LINE_1}/d" "$DTC_LEXER_L_PATH" # Fallback
        sed -i "/${PATCH_MARKER_L_V8_3}/d" "$DTC_LEXER_L_PATH" # Fallback
        sed -i '/^[[:space:]]*$/d' "$DTC_LEXER_L_PATH"
        info "$DTC_LEXER_L_PATH cleaned of flex directives for V17."
    else
        info "$DTC_LEXER_L_PATH is already clean of flex directives (V17)."
    fi
else
    error "$DTC_LEXER_L_PATH not found for V17."
fi

# 4. Ensure scripts/dtc/dtc-parser.y has NO bison prefix directive
DTC_PARSER_Y_PATH="scripts/dtc/dtc-parser.y"
PATCH_MARKER_Y_V8_3="# DTC_Y_PREFIX_DIRECTIVE_V8.3"
BISON_DIRECTIVE_LINE_1="%define api.prefix {dtc_}"

if [ -f "$DTC_PARSER_Y_PATH" ]; then
    info "V17: Ensuring no bison prefix directive is in $DTC_PARSER_Y_PATH..."
    if grep -q "${PATCH_MARKER_Y_V8_3}" "$DTC_PARSER_Y_PATH" || grep -Fxq "${BISON_DIRECTIVE_LINE_1}" "$DTC_PARSER_Y_PATH"; then
        info "Found old bison prefix directive/marker in $DTC_PARSER_Y_PATH. Removing for V17."
        sed -i "/${PATCH_MARKER_Y_V8_3}/d" "$DTC_PARSER_Y_PATH"
        sed -i "s|^${BISON_DIRECTIVE_LINE_1}$||" "$DTC_PARSER_Y_PATH"
        sed -i '/^[[:space:]]*$/d' "$DTC_PARSER_Y_PATH"
        info "$DTC_PARSER_Y_PATH cleaned of bison directives for V17."
    else
        info "$DTC_PARSER_Y_PATH is already clean of bison directives (V17)."
    fi
else
    error "$DTC_PARSER_Y_PATH not found for V17."
fi
# --- End V17 Strategy ---

if [ ! -f /usr/bin/python ] && [ -f /usr/bin/python3 ]; then
    sudo ln -sf /usr/bin/python3 /usr/bin/python; info "Created python symlink.";
fi

info "Removing pre-shipped DTC parser/lexer files to force regeneration (Attempt 1: Before mrproper)..."
rm -f "$NEW_KERNEL_DIR/scripts/dtc/dtc-lexer.lex.c_shipped"
rm -f "$NEW_KERNEL_DIR/scripts/dtc/dtc-parser.tab.c_shipped"
rm -f "$NEW_KERNEL_DIR/scripts/dtc/dtc-parser.tab.h_shipped"
ls -l "$NEW_KERNEL_DIR/scripts/dtc/"*shipped* 2>/dev/null || info "Verified: No *_shipped DTC files in source tree before mrproper."

info "Displaying scripts/Makefile.host content:"
cat "$NEW_KERNEL_DIR/scripts/Makefile.host" || error "Failed to cat $NEW_KERNEL_DIR/scripts/Makefile.host"

info "Cleaning kernel source tree thoroughly with make mrproper..."
make $MAKE_OPTS_CLANG -j"$NUM_JOBS" mrproper O="$KERNEL_BUILD_OUT_DIR"
info "Source tree cleaned with mrproper."

info "Available defconfigs in $NEW_KERNEL_DIR/arch/$ARCH/configs/:"
ls -1 "$NEW_KERNEL_DIR/arch/$ARCH/configs/" || info "Could not list defconfigs."
info "Using defconfig: $DEFCONFIG"

KERNEL_BUILD_OUT_DIR="$NEW_KERNEL_DIR/out"
mkdir -p "$KERNEL_BUILD_OUT_DIR"

info "Generating initial .config in '$KERNEL_BUILD_OUT_DIR' using $DEFCONFIG..."
make $MAKE_OPTS_CLANG -j"$NUM_JOBS" "$DEFCONFIG" O="$KERNEL_BUILD_OUT_DIR"
info "Generated $KERNEL_BUILD_OUT_DIR/.config."

info "Running first olddefconfig..."
make $MAKE_OPTS_CLANG -j"$NUM_JOBS" olddefconfig O="$KERNEL_BUILD_OUT_DIR"

info "Modifying $KERNEL_BUILD_OUT_DIR/.config..."
CONFIG_FILE="$KERNEL_BUILD_OUT_DIR/.config"
SAMSUNG_CONFIGS=( CONFIG_UH CONFIG_RKP CONFIG_KDP CONFIG_SECURITY_DEFEX CONFIG_PROCA CONFIG_TIMA_LKMAUTH CONFIG_SEC_RESTRICT_SETUID CONFIG_EXYNOS_CPTS_VERIFY_SECURE_ACCESS CONFIG_KPERFMON )
for cfg in "${SAMSUNG_CONFIGS[@]}"; do
    sed -i "s/^${cfg}=y/# ${cfg} is not set\n# ${cfg}=n/g" "$CONFIG_FILE"
    sed -i "s/^${cfg}=m/# ${cfg} is not set\n# ${cfg}=n/g" "$CONFIG_FILE"
done
grep -qxF 'CONFIG_KSU=y' "$CONFIG_FILE" || echo 'CONFIG_KSU=y' >> "$CONFIG_FILE"
grep -qxF 'CONFIG_OVERLAY_FS=y' "$CONFIG_FILE" || echo 'CONFIG_OVERLAY_FS=y' >> "$CONFIG_FILE"
if grep -q 'CONFIG_KSU_MANAGER=' "$CONFIG_FILE"; then sed -i 's/CONFIG_KSU_MANAGER=.*/CONFIG_KSU_MANAGER="kernelsu.Default"/g' "$CONFIG_FILE"; else echo 'CONFIG_KSU_MANAGER="kernelsu.Default"' >> "$CONFIG_FILE"; fi
sed -i 's/^CONFIG_KSU_DEBUG=y/# CONFIG_KSU_DEBUG is not set\n# CONFIG_KSU_DEBUG=n/g' "$CONFIG_FILE"
grep -qxF 'CONFIG_MODULES=y' "$CONFIG_FILE" || echo 'CONFIG_MODULES=y' >> "$CONFIG_FILE"

info "Finalizing with second olddefconfig..."
make $MAKE_OPTS_CLANG -j"$NUM_JOBS" olddefconfig O="$KERNEL_BUILD_OUT_DIR"
info "Checking CONFIG_MODULES: $(grep "CONFIG_MODULES" "$CONFIG_FILE" || echo "Not found")"

info "Ensuring include directories exist..."
mkdir -p "$KERNEL_BUILD_OUT_DIR/include/config" "$KERNEL_BUILD_OUT_DIR/include/generated"
info "Checking for auto.conf: $(ls -lA "$KERNEL_BUILD_OUT_DIR/include/config/auto.conf" || echo "Not found")"
info "Checking for autoconf.h: $(ls -lA "$KERNEL_BUILD_OUT_DIR/include/generated/autoconf.h" || echo "Not found")"
if [ ! -f "$KERNEL_BUILD_OUT_DIR/include/config/tristate.conf" ]; then
    info "WARNING: tristate.conf NOT FOUND. Touching it."
    touch "$KERNEL_BUILD_OUT_DIR/include/config/tristate.conf"
fi

info "Removing pre-shipped DTC parser/lexer files again to be absolutely sure (Attempt 2: Before prepare)..."
rm -f "$NEW_KERNEL_DIR/scripts/dtc/dtc-lexer.lex.c_shipped"
rm -f "$NEW_KERNEL_DIR/scripts/dtc/dtc-parser.tab.c_shipped"
rm -f "$NEW_KERNEL_DIR/scripts/dtc/dtc-parser.tab.h_shipped"
ls -l "$NEW_KERNEL_DIR/scripts/dtc/"*shipped* 2>/dev/null || info "Verified: No *_shipped DTC files in source tree before prepare."
info "Also removing any potentially stale generated DTC files from OUT directory's scripts/dtc..."
rm -f "$KERNEL_BUILD_OUT_DIR/scripts/dtc/dtc-lexer.lex.c"
rm -f "$KERNEL_BUILD_OUT_DIR/scripts/dtc/dtc-parser.tab.c"
rm -f "$KERNEL_BUILD_OUT_DIR/scripts/dtc/dtc-parser.tab.h"
ls -l "$KERNEL_BUILD_OUT_DIR/scripts/dtc/"* 2>/dev/null || info "Verified: $KERNEL_BUILD_OUT_DIR/scripts/dtc/ content after cleaning."


info "Running 'make O=$KERNEL_BUILD_OUT_DIR prepare'..."
make $MAKE_OPTS_CLANG -j"$NUM_JOBS" prepare O="$KERNEL_BUILD_OUT_DIR"
info "Checking include paths after 'make prepare'..."
ls -lA "$KERNEL_BUILD_OUT_DIR/include/generated/" || info "include/generated/ not found"
ls -lA "$KERNEL_BUILD_OUT_DIR/include/config/" || info "include/config/ not found"

info "Aggressively removing DTC _shipped and generated files before final build..."
rm -f "$NEW_KERNEL_DIR/scripts/dtc/dtc-lexer.lex.c_shipped" \
      "$NEW_KERNEL_DIR/scripts/dtc/dtc-parser.tab.c_shipped" \
      "$NEW_KERNEL_DIR/scripts/dtc/dtc-parser.tab.h_shipped"
rm -f "$KERNEL_BUILD_OUT_DIR/scripts/dtc/dtc-lexer.lex.c" \
      "$KERNEL_BUILD_OUT_DIR/scripts/dtc/dtc-parser.tab.c" \
      "$KERNEL_BUILD_OUT_DIR/scripts/dtc/dtc-parser.tab.h" \
      "$KERNEL_BUILD_OUT_DIR/scripts/dtc/dtc-lexer.lex.o" \
      "$KERNEL_BUILD_OUT_DIR/scripts/dtc/dtc-parser.tab.o" \
      "$KERNEL_BUILD_OUT_DIR/scripts/dtc/dtc"
info "DTC shipped/generated files removed."

info "Starting final kernel build \(Image.gz\)..."
make $MAKE_OPTS_CLANG -j"$NUM_JOBS" Image.gz O="$KERNEL_BUILD_OUT_DIR"

KERNEL_IMAGE_PATH="$KERNEL_BUILD_OUT_DIR/arch/$ARCH/boot/Image.gz"
DTBO_IMAGE_PATH="$KERNEL_BUILD_OUT_DIR/arch/$ARCH/boot/dtbo.img"

if [ ! -f "$KERNEL_IMAGE_PATH" ]; then error "Kernel Image.gz not found at $KERNEL_IMAGE_PATH!"; fi
info "Kernel build completed: $KERNEL_IMAGE_PATH"
if [ -f "$DTBO_IMAGE_PATH" ]; then info "dtbo.img found: $DTBO_IMAGE_PATH"; else info "dtbo.img not found."; fi

cd "$HOME"
info "Preparing AnyKernel3..."
if [ ! -d "$ANYKERNEL_DIR" ]; then
    info "Cloning AnyKernel3..."; git clone --depth=1 "$ANYKERNEL_URL" "$ANYKERNEL_DIR";
else
    info "AnyKernel3 found. Cleaning/updating..."; cd "$ANYKERNEL_DIR"; git clean -fdx;
    git fetch origin && git reset --hard origin/master || (info "Failed origin/master reset, trying local HEAD" && git rev-parse --verify HEAD >/dev/null 2>&1 && git reset --hard HEAD || info "AnyKernel3 reset failed.");
    cd "$HOME";
fi

cd "$ANYKERNEL_DIR"
rm -rf ramdisk dtb kernel kernel.gz Image Image.gz Image.gz-dtb zImage dtbo.img anykernel.zip modules system/lib/modules/*
info "Copying artifacts to AnyKernel3..."
cp "$KERNEL_IMAGE_PATH" "$ANYKERNEL_DIR/"
if [ -f "$DTBO_IMAGE_PATH" ]; then cp "$DTBO_IMAGE_PATH" "$ANYKERNEL_DIR/"; fi

info "Modifying anykernel.sh..."
cat <<EOF > anykernel.sh
# AnyKernel3 Ramdisk Mod Script
properties() { '
kernel.string=CruelKernelSU for Galaxy Note 10+ \(SM-N975F\) by $(whoami)
do.devicecheck=1; do.modules=0; do.systemless=1; do.cleanup=1; do.cleanuponabort=0;
device.name1=d1; device.name2=d1x; device.name3=d1xx;
supported.versions=12; supported.patchlevels=;
'; }
block=/dev/block/by-name/boot; is_slot_device=0; ramdisk_compression=auto; patch_vbmeta_flag=auto;
. tools/ak3-core.sh;
dump_boot; write_boot;
EOF

info "Creating AnyKernel3 ZIP: $OUT_DIR/$AK3_ZIP_NAME"
zip -r9 "$OUT_DIR/$AK3_ZIP_NAME" * -x ".git*" LICENSE README.md "*.zip" tools/magiskboot tools/busybox tools/lz4 tools/xz

cd "$HOME"
if ! command -v magiskboot &> /dev/null; then
    info "magiskboot not found. Downloading..."; MAGISKBOOT_PATH_LOCAL="$HOME/magiskboot";
    wget https://github.com/topjohnwu/Magisk/raw/master/native/out/arm64-v8a/magiskboot -O "$MAGISKBOOT_PATH_LOCAL"; chmod +x "$MAGISKBOOT_PATH_LOCAL";
else
    MAGISKBOOT_PATH_LOCAL=$(command -v magiskboot);
fi
info "Using magiskboot: $MAGISKBOOT_PATH_LOCAL"

STOCK_BOOT_UNPACKED_DIR="$OUT_DIR/stock_boot_unpacked"
info "Unpacking stock boot.img to $STOCK_BOOT_UNPACKED_DIR..."
rm -rf "$STOCK_BOOT_UNPACKED_DIR"; mkdir -p "$STOCK_BOOT_UNPACKED_DIR"
"$MAGISKBOOT_PATH_LOCAL" unpack -h "$STOCK_BOOT_IMG" "$STOCK_BOOT_UNPACKED_DIR"

if [ -f "$STOCK_BOOT_UNPACKED_DIR/ramdisk.cpio" ]; then
    info "Repacking new boot.img..."
    cp "$KERNEL_IMAGE_PATH" "$STOCK_BOOT_UNPACKED_DIR/kernel"
    if [ -f "$DTBO_IMAGE_PATH" ]; then cp "$DTBO_IMAGE_PATH" "$STOCK_BOOT_UNPACKED_DIR/dtbo";
    elif [ -f "$STOCK_BOOT_UNPACKED_DIR/dtbo" ]; then info "Using stock dtbo.";
    else info "No dtbo found to repack."; fi
    "$MAGISKBOOT_PATH_LOCAL" repack "$STOCK_BOOT_UNPACKED_DIR" "$FINAL_BOOT_IMG"
    info "New boot.img: $FINAL_BOOT_IMG"

    info "Creating Odin TAR: $FINAL_TAR_MD5"
    cd "$OUT_DIR"; if [ -f boot.tar.md5 ]; then rm boot.tar.md5; fi; if [ -f boot.tar ]; then rm boot.tar; fi
    tar -H ustar -cf boot.tar ./boot.img; md5sum -t boot.tar >> boot.tar; mv boot.tar "$FINAL_TAR_MD5";
    info "Odin TAR created: $FINAL_TAR_MD5"; cd "$HOME";
else
    error "Failed to unpack stock_boot.img. Cannot create raw boot.img."
fi

info "Build process finished!"
info "Outputs:"
info "  AnyKernel3 ZIP: $OUT_DIR/$AK3_ZIP_NAME"
if [ -f "$FINAL_BOOT_IMG" ]; then info "  Raw Boot Image: $FINAL_BOOT_IMG"; fi
if [ -f "$FINAL_TAR_MD5" ]; then info "  Odin Flashable TAR: $FINAL_TAR_MD5"; fi
info "Remember to backup your device before flashing!"
exit 0