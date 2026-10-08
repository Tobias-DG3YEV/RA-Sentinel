/*
 * SPDX-FileCopyrightText: 2026 Tobias Weber <tobiw@supralfuid.com>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

# iqcap - IQ snapshot transport configuration module (shared)

`iqcap_cfg.c/.h` is the ONE copy of the configuration logic used by both ECU firmware tree!

It has no HAL or RTOS dependency. Each tree hands in its register accessors and NV store through `iqcap_port_t`. Both Debug makefiles reference this directory directly.
