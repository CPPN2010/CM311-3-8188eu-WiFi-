/*
 * Modified flush_signals_thread() - empty function to avoid 'current' macro
 * File: include/osdep_service.h
 *
 * Reason: Device kernel has CONFIG_THREAD_INFO_IN_TASK=y (sp_el0 points
 * directly to task_struct), but the build kernel source lacks this option
 * (sp_el0 points to thread_info, needs current_thread_info()->task).
 * This mismatch causes 'current' macro to dereference NULL, leading to
 * kernel panic in rtw_cmd_thread+0x18c.
 *
 * Original code used signal_pending(current) and flush_signals(current).
 * Signal flushing is non-critical for this driver's operation.
 */

static inline void flush_signals_thread(void)
{
    /* Avoid using 'current' macro: build kernel lacks CONFIG_THREAD_INFO_IN_TASK
     * so current resolves to current_thread_info()->task which is wrong on
     * the device kernel (which has CONFIG_THREAD_INFO_IN_TASK=y, sp_el0 points
     * directly to task_struct). Signal flushing is non-critical for this driver. */
}
