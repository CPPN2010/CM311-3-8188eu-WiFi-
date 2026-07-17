#!/usr/bin/env python3
"""Patch flush_signals_thread to avoid using 'current' macro which has wrong
definition when CONFIG_THREAD_INFO_IN_TASK mismatch between build and runtime."""

hdr = '/root/build/rtl8188eu-master/include/osdep_service.h'

with open(hdr, 'r') as f:
    content = f.read()

old = '''static inline void flush_signals_thread(void)
{
	if (signal_pending (current))
		flush_signals(current);
}'''

new = '''static inline void flush_signals_thread(void)
{
	/* Avoid using 'current' macro: build kernel lacks CONFIG_THREAD_INFO_IN_TASK
	 * so current resolves to current_thread_info()->task which is wrong on
	 * the device kernel (which has CONFIG_THREAD_INFO_IN_TASK=y, sp_el0 points
	 * directly to task_struct). Signal flushing is non-critical for this driver. */
}'''

if old in content:
    content = content.replace(old, new, 1)
    with open(hdr, 'w') as f:
        f.write(content)
    print('Patched flush_signals_thread to no-op')
elif 'Avoid using' in content:
    print('Already patched')
else:
    print('ERROR: pattern not found')
    idx = content.find('flush_signals_thread')
    if idx >= 0:
        print(repr(content[idx:idx+150]))
    exit(1)
