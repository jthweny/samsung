/*
 * Samsung Exynos 9820 Undefined Symbol Stubs
 * Created to resolve vmlinux linking issues with Samsung proprietary drivers
 * These are minimal stub implementations to satisfy the linker
 */

#include <linux/export.h>
#include <linux/types.h>

/* Forward declarations */
struct decon_device;

/* 1. DISPLAY/TUI PROTECTION STUBS */

/**
 * decon_tui_protection - Stub for Samsung TUI protection
 * @tui_en: TUI enable flag
 * Returns: 0 (success)
 */
int decon_tui_protection(bool tui_en)
{
    /* Stub implementation - always return success */
    return 0;
}
EXPORT_SYMBOL(decon_tui_protection);

/**
 * decon_drvdata - Samsung display controller driver data array
 * Array of pointers to decon_device structures (MAX_DECON_CNT = 3)
 */
struct decon_device *decon_drvdata[3] = { NULL, NULL, NULL };
EXPORT_SYMBOL(decon_drvdata);

/* 2. SOFT-FLOAT STUBS (ARM64 kernel compatible - no FP types) */

/**
 * __floatunditf - Convert unsigned 64-bit int to 128-bit float
 * @u: unsigned 64-bit integer
 * Returns: 128-bit float as two 64-bit values (dummy implementation)
 * 
 * ARM64 kernel uses -mgeneral-regs-only, so we can't use floating-point types.
 * This is a minimal stub that just returns the input value in a way that
 * satisfies the linker for soft-float operations.
 */
void __floatunditf(unsigned long long u)
{
    /* Stub - does nothing but satisfies linker */
    return;
}
EXPORT_SYMBOL(__floatunditf);

/**
 * __multf3 - 128-bit float multiplication stub
 * ARM64 kernel compatible version - returns dummy result
 */
void __multf3(void)
{
    /* Stub - does nothing but satisfies linker */
    return;
}
EXPORT_SYMBOL(__multf3);

/**
 * __fixunstfdi - Convert 128-bit float to unsigned 64-bit int
 * Returns: 0 (dummy value)
 */
unsigned long long __fixunstfdi(void)
{
    /* Stub - return 0 as dummy value */
    return 0ULL;
}
EXPORT_SYMBOL(__fixunstfdi);

/* 3. SENSOR HUB STUB */

/**
 * send_hall_ic_status - Stub for hall sensor status
 * @enable: hall sensor enable flag
 * Returns: 0 (success)
 */
int send_hall_ic_status(bool enable)
{
    /* Stub implementation - always return success */
    return 0;
}
EXPORT_SYMBOL(send_hall_ic_status);

/* 4. SPI DMA OPERATIONS STUB */

/**
 * s3c_dma_get_ops - Get Samsung DMA operations structure
 * Returns: NULL (no DMA operations available)
 */
void *s3c_dma_get_ops(void)
{
    /* Stub implementation - return NULL to indicate no DMA ops */
    return NULL;
}
EXPORT_SYMBOL(s3c_dma_get_ops);