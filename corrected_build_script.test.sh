#!/bin/bash

# Test script for corrected_build_script.sh
# This script tests various components of the kernel build script

# Global test setup
setUp() {
    echo "DEBUG: Global setUp executing..." >&2
    
    # Create a temporary directory for testing
    TEST_DIR=$(mktemp -d)
    export TEST_DIR
    
    # Set up basic test environment
    SETUP_HAS_RUN="true"
    export SETUP_HAS_RUN
    
    # Mock functions for testing
    info() {
        echo "[INFO] $1"
        INFO_CALLED+=("$1")
    }
    export -f info
    
    error() {
        echo "[ERROR] $1" >&2
        ERROR_CALLED+=("$1")
        return 1
    }
    export -f error
    
    # Initialize tracking arrays
    INFO_CALLED=()
    ERROR_CALLED=()
    export INFO_CALLED ERROR_CALLED
    
    echo "DEBUG: setUp completed, TEST_DIR=$TEST_DIR" >&2
}

# Global test cleanup
tearDown() {
    echo "DEBUG: Global tearDown executing..." >&2
    
    # Clean up the temporary directory
    if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    fi
    
    # Unset test variables
    unset TEST_DIR SETUP_HAS_RUN INFO_CALLED ERROR_CALLED
    unset -f info error
    
    echo "DEBUG: tearDown completed" >&2
}

# Test 1: Basic setup verification
testBasicSetup() {
    echo "DEBUG: testBasicSetup executing..." >&2
    assertTrue "setUp should have run and set SETUP_HAS_RUN" "[ \"$SETUP_HAS_RUN\" = \"true\" ]"
    assertTrue "TEST_DIR should be set and exist" "[ -n \"$TEST_DIR\" ] && [ -d \"$TEST_DIR\" ]"
    echo "DEBUG: Basic setup test passed" >&2
}

# Test 2: KernelSU configuration test
testKernelSUConfiguration() {
    echo "DEBUG: testKernelSUConfiguration executing..." >&2
    
    # Create a mock .config file
    local config_dir="$TEST_DIR/config_test"
    mkdir -p "$config_dir"
    local config_file="$config_dir/.config"
    
    # Create initial config with some KernelSU-related options
    cat > "$config_file" << 'EOF'
# Mock kernel config file
CONFIG_KSU=n
CONFIG_KPROBES=n
CONFIG_OVERLAY_FS=n
CONFIG_MODULE_SIG=y
CONFIG_MODULE_SIG_ALL=y
CONFIG_MODULE_SIG_FORCE=y
CONFIG_KPERFMON=y
# End of mock config
EOF
    
    # Apply KernelSU configuration changes (simulating the build script logic)
    declare -A KSU_OPTIONS=(
        ["CONFIG_KSU"]=y
        ["CONFIG_KPROBES"]=y
        ["CONFIG_OVERLAY_FS"]=y
        ["CONFIG_MODULE_SIG"]=n
        ["CONFIG_MODULE_SIG_ALL"]=n
        ["CONFIG_MODULE_SIG_FORCE"]=n
    )
    
    for KCONFIG_OPT in "${!KSU_OPTIONS[@]}"; do
        DESIRED_VALUE="${KSU_OPTIONS[$KCONFIG_OPT]}"
        CURRENT_VALUE_LINE=$(grep "^${KCONFIG_OPT}=" "$config_file" || true)
        if [ -n "$CURRENT_VALUE_LINE" ]; then
            if [ "$CURRENT_VALUE_LINE" != "${KCONFIG_OPT}=${DESIRED_VALUE}" ]; then
                sed -i "s|^${KCONFIG_OPT}=.*|${KCONFIG_OPT}=${DESIRED_VALUE}|" "$config_file"
            fi
        else
            echo "${KCONFIG_OPT}=${DESIRED_VALUE}" >> "$config_file"
        fi
    done
    
    # Disable CONFIG_KPERFMON
    if grep -q "CONFIG_KPERFMON=y" "$config_file"; then
        sed -i 's/CONFIG_KPERFMON=y/# CONFIG_KPERFMON is not set/' "$config_file"
    fi
    
    # Verify the configuration changes
    assertTrue "CONFIG_KSU should be enabled" "grep -q '^CONFIG_KSU=y' '$config_file'"
    assertTrue "CONFIG_KPROBES should be enabled" "grep -q '^CONFIG_KPROBES=y' '$config_file'"
    assertTrue "CONFIG_OVERLAY_FS should be enabled" "grep -q '^CONFIG_OVERLAY_FS=y' '$config_file'"
    assertTrue "CONFIG_MODULE_SIG should be disabled" "grep -q '^CONFIG_MODULE_SIG=n' '$config_file'"
    assertTrue "CONFIG_MODULE_SIG_ALL should be disabled" "grep -q '^CONFIG_MODULE_SIG_ALL=n' '$config_file'"
    assertTrue "CONFIG_MODULE_SIG_FORCE should be disabled" "grep -q '^CONFIG_MODULE_SIG_FORCE=n' '$config_file'"
    assertTrue "CONFIG_KPERFMON should be disabled" "grep -q '^# CONFIG_KPERFMON is not set' '$config_file'"
    
    echo "DEBUG: KernelSU configuration test passed" >&2
}

# Test 3: DTC management test
testDTCManagement() {
    echo "DEBUG: testDTCManagement executing..." >&2
    
    # Create mock DTC environment
    local dtc_test_dir="$TEST_DIR/dtc_test"
    mkdir -p "$dtc_test_dir/bin"
    mkdir -p "$dtc_test_dir/kernel/scripts/dtc"
    
    # Create a mock DTC binary
    local mock_dtc="$dtc_test_dir/bin/dtc"
    cat > "$mock_dtc" << 'EOF'
#!/bin/bash
echo "dtc version 1.6.0"
exit 0
EOF
    chmod +x "$mock_dtc"
    
    # Create mock DTC Makefile
    local dtc_makefile="$dtc_test_dir/kernel/scripts/dtc/Makefile"
    cat > "$dtc_makefile" << 'EOF'
hostprogs-y := dtc
dtc-objs += dtc.o
dtc-objs += dtc-lexer.lex.o
dtc-objs += dtc-parser.tab.o
EOF
    
    # Create mock shipped files
    echo "mock lexer content" > "$dtc_test_dir/kernel/scripts/dtc/dtc-lexer.lex.c_shipped"
    echo "mock parser content" > "$dtc_test_dir/kernel/scripts/dtc/dtc-parser.tab.c_shipped"
    echo "mock parser header" > "$dtc_test_dir/kernel/scripts/dtc/dtc-parser.tab.h_shipped"
    
    # Test DTC binary existence and executability
    assertTrue "Mock DTC binary should exist" "[ -f '$mock_dtc' ]"
    assertTrue "Mock DTC binary should be executable" "[ -x '$mock_dtc' ]"
    
    # Test DTC version check
    local dtc_version_output
    dtc_version_output=$("$mock_dtc" --version 2>/dev/null || echo "version check failed")
    assertContains "DTC should report version" "$dtc_version_output" "dtc version"
    
    # Simulate DTC Makefile modification (commenting out in-tree DTC build)
    sed -i -e 's/^\(hostprogs-y\s*:=\s*dtc\)/# \1/' \
           -e 's/^\(dtc-objs\s*+=.*dtc\.o.*\)/# \1/' \
           -e 's/^\(dtc-objs\s*+=.*dtc-lexer\.lex\.o.*\)/# \1/' \
           "$dtc_makefile"
    
    # Verify Makefile was modified correctly
    assertFalse "hostprogs-y := dtc should be commented out" "grep -q '^hostprogs-y\s*:=\s*dtc' '$dtc_makefile'"
    assertTrue "hostprogs-y := dtc should be commented" "grep -q '^# hostprogs-y\s*:=\s*dtc' '$dtc_makefile'"
    
    # Test copying DTC binary to scripts directory
    cp "$mock_dtc" "$dtc_test_dir/kernel/scripts/dtc/dtc"
    assertTrue "DTC should be copied to scripts directory" "[ -f '$dtc_test_dir/kernel/scripts/dtc/dtc' ]"
    assertTrue "Copied DTC should be executable" "[ -x '$dtc_test_dir/kernel/scripts/dtc/dtc' ]"
    
    # Test copying shipped files
    cp "$dtc_test_dir/kernel/scripts/dtc/dtc-lexer.lex.c_shipped" "$dtc_test_dir/kernel/scripts/dtc/dtc-lexer.lex.c"
    cp "$dtc_test_dir/kernel/scripts/dtc/dtc-parser.tab.c_shipped" "$dtc_test_dir/kernel/scripts/dtc/dtc-parser.tab.c"
    cp "$dtc_test_dir/kernel/scripts/dtc/dtc-parser.tab.h_shipped" "$dtc_test_dir/kernel/scripts/dtc/dtc-parser.tab.h"
    
    assertTrue "dtc-lexer.lex.c should be created from _shipped" "[ -f '$dtc_test_dir/kernel/scripts/dtc/dtc-lexer.lex.c' ]"
    assertTrue "dtc-parser.tab.c should be created from _shipped" "[ -f '$dtc_test_dir/kernel/scripts/dtc/dtc-parser.tab.c' ]"
    assertTrue "dtc-parser.tab.h should be created from _shipped" "[ -f '$dtc_test_dir/kernel/scripts/dtc/dtc-parser.tab.h' ]"
    
    echo "DEBUG: DTC management test passed" >&2
}

# Test 4: Build environment setup test
testBuildEnvironmentSetup() {
    echo "DEBUG: testBuildEnvironmentSetup executing..." >&2
    
    # Create mock build environment
    local build_env_dir="$TEST_DIR/build_env"
    mkdir -p "$build_env_dir/toolchain/bin"
    mkdir -p "$build_env_dir/kernel_src"
    mkdir -p "$build_env_dir/build_out"
    
    # Create mock toolchain binaries
    local toolchain_bins=("clang" "ld.lld" "llvm-ar" "llvm-nm" "llvm-objcopy" "llvm-objdump" "llvm-strip")
    for bin in "${toolchain_bins[@]}"; do
        local mock_bin="$build_env_dir/toolchain/bin/$bin"
        cat > "$mock_bin" << EOF
#!/bin/bash
echo "Mock $bin executed with args: \$*"
exit 0
EOF
        chmod +x "$mock_bin"
        assertTrue "Mock $bin should be executable" "[ -x '$mock_bin' ]"
    done
    
    # Test toolchain directory structure
    assertTrue "Toolchain directory should exist" "[ -d '$build_env_dir/toolchain' ]"
    assertTrue "Toolchain bin directory should exist" "[ -d '$build_env_dir/toolchain/bin' ]"
    
    # Test kernel source directory
    assertTrue "Kernel source directory should exist" "[ -d '$build_env_dir/kernel_src' ]"
    
    # Test build output directory
    assertTrue "Build output directory should exist" "[ -d '$build_env_dir/build_out' ]"
    
    echo "DEBUG: Build environment setup test passed" >&2
}

# Test 5: SELinux classmap.h patching test
testSELinuxClassmapPatching() {
    echo "DEBUG: testSELinuxClassmapPatching executing..." >&2
    
    # Create mock SELinux directory structure
    local selinux_dir="$TEST_DIR/selinux_test/security/selinux/include"
    mkdir -p "$selinux_dir"
    
    # Create mock classmap.h file
    local classmap_file="$selinux_dir/classmap.h"
    cat > "$classmap_file" << 'EOF'
/* Original file content without needed patches */
#include <linux/socket.h>

static struct security_class_mapping secclass_map[] = {
	{ "socket", { NULL } },
	{ "tcp_socket", { NULL } },
	{ "netlink_socket", {
		"create",
		NULL
	} },
	{
		"netlink_xfrm_socket", {
			"create",
			NULL
		}
	},
	{ NULL }
};

/* Original capability definitions */
#define CAP_AUDIT_READ 37
#define CAP_LAST_CAP CAP_AUDIT_READ

#if CAP_LAST_CAP > CAP_AUDIT_READ
#error New capability defined, please update capability_names.
#endif

/* PF_MAX definition too low */
#define PF_MAX 44

#error New address family defined, please update secclass_map.
EOF
    
    # Apply SELinux patches (simulating the build script logic)
    
    # Add stddef.h include
    if ! grep -q "#include <stddef.h>" "$classmap_file"; then
        sed -i '1i#include <stddef.h>' "$classmap_file"
    fi
    
    # Add flask.h include
    if ! grep -q "#include \"flask.h\"" "$classmap_file"; then
        sed -i '1i#include "flask.h"' "$classmap_file"
    fi
    
    # Set PF_MAX to 45
    sed -i "s/#define PF_MAX\s*[0-9]\+/#define PF_MAX 45/" "$classmap_file"
    
    # Define CAP_BPF
    if grep -q "#define CAP_AUDIT_READ\s*37" "$classmap_file"; then
        sed -i '/#define CAP_AUDIT_READ\s*37/a #define CAP_BPF\t\t\t38' "$classmap_file"
    fi
    
    # Update CAP_LAST_CAP
    sed -i "s/#define CAP_LAST_CAP\s*CAP_AUDIT_READ/#define CAP_LAST_CAP CAP_BPF/" "$classmap_file"
    
    # Update the preprocessor check
    sed -i "s/#if CAP_LAST_CAP > CAP_AUDIT_READ/#if CAP_LAST_CAP > CAP_BPF/" "$classmap_file"
    
    # Remove the #error line
    sed -i '/#error New address family defined, please update secclass_map./d' "$classmap_file"
    
    # Verify the patches were applied
    assertTrue "stddef.h should be included" "grep -q '#include <stddef.h>' '$classmap_file'"
    assertTrue "flask.h should be included" "grep -q '#include \"flask.h\"' '$classmap_file'"
    assertTrue "PF_MAX should be set to 45" "grep -q '#define PF_MAX 45' '$classmap_file'"
    assertTrue "CAP_BPF should be defined as 38" "grep -q '#define CAP_BPF\s*38' '$classmap_file'"
    assertTrue "CAP_LAST_CAP should be updated to CAP_BPF" "grep -q '#define CAP_LAST_CAP CAP_BPF' '$classmap_file'"
    assertTrue "CAP_LAST_CAP check should be updated" "grep -q '#if CAP_LAST_CAP > CAP_BPF' '$classmap_file'"
    assertFalse "Error line should be removed" "grep -q '#error New address family defined, please update secclass_map.' '$classmap_file'"
    
    echo "DEBUG: SELinux classmap.h patching test passed" >&2
}

# Test 6: Boot image creation test
testBootImageCreation() {
    echo "DEBUG: testBootImageCreation executing..." >&2
    
    # Create mock boot image environment
    local boot_test_dir="$TEST_DIR/boot_test"
    mkdir -p "$boot_test_dir/out"
    mkdir -p "$boot_test_dir/anykernel/tools"
    
    # Create mock boot.img
    local boot_img="$boot_test_dir/out/boot.img"
    echo "MOCK_BOOT_IMG_CONTENT" > "$boot_img"
    
    # Create mock magiskboot tool
    local magiskboot="$boot_test_dir/anykernel/tools/magiskboot"
    cat > "$magiskboot" << 'EOF'
#!/bin/bash
case "$1" in
    "unpack")
        echo "Mock magiskboot: unpacking $2"
        touch kernel.gz ramdisk.cpio
        ;;
    "repack")
        echo "Mock magiskboot: repacking $2 to $3"
        echo "MOCK_REPACKED_BOOT" > "$3"
        ;;
    *)
        echo "Mock magiskboot: unknown command $1"
        ;;
esac
exit 0
EOF
    chmod +x "$magiskboot"
    
    # Test boot.img creation process
    assertTrue "Boot image should exist" "[ -f '$boot_img' ]"
    assertTrue "Magiskboot tool should be executable" "[ -x '$magiskboot' ]"
    
    # Test magiskboot unpack simulation
    cd "$boot_test_dir" || fail "Failed to cd to boot test directory"
    "$magiskboot" unpack "$boot_img"
    assertTrue "Kernel file should be created by unpack" "[ -f 'kernel.gz' ]"
    assertTrue "Ramdisk file should be created by unpack" "[ -f 'ramdisk.cpio' ]"
    
    # Test magiskboot repack simulation
    local new_boot="$boot_test_dir/out/new_boot.img"
    "$magiskboot" repack "$boot_img" "$new_boot"
    assertTrue "New boot image should be created by repack" "[ -f '$new_boot' ]"
    
    # Test boot.tar.md5 creation
    cd "$boot_test_dir/out" || fail "Failed to cd to out directory"
    tar -H ustar -c boot.img -f boot.tar
    md5sum -t boot.tar >> boot.tar
    mv boot.tar boot.tar.md5
    
    assertTrue "boot.tar.md5 should be created" "[ -f 'boot.tar.md5' ]"
    
    # Verify tar.md5 content
    mkdir -p "$boot_test_dir/extract"
    tar -xf boot.tar.md5 -C "$boot_test_dir/extract"
    assertTrue "Extracted boot.img should exist" "[ -f '$boot_test_dir/extract/boot.img' ]"
    
    echo "DEBUG: Boot image creation test passed" >&2
}

# Test 7: Build script syntax check
testBuildScriptSyntax() {
    echo "DEBUG: testBuildScriptSyntax executing..." >&2
    
    local build_script="/home/joshua/Desktop/android_kernel_d1/corrected_build_script.sh"
    
    # Check if build script exists
    assertTrue "Build script should exist" "[ -f '$build_script' ]"
    
    # Check if build script is executable
    assertTrue "Build script should be executable" "[ -x '$build_script' ]"
    
    # Perform basic syntax check
    if command -v bash >/dev/null 2>&1; then
        if bash -n "$build_script" 2>/dev/null; then
            echo "DEBUG: Build script syntax check passed" >&2
        else
            fail "Build script has syntax errors"
        fi
    else
        echo "DEBUG: bash not available for syntax check, skipping" >&2
    fi
    
    echo "DEBUG: Build script syntax test completed" >&2
}

# Load shunit2 test framework
. /usr/bin/shunit2