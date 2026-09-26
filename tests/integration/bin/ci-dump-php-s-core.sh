#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 LibreCode coop and contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Dump a readable PHP stack from a php -S worker core.
# JIT frames show as n/a in coredumpctl; zbacktrace reads EG(current_execute_data).
set -u

sudo coredumpctl --no-pager list || true

curl -fsSL -o /tmp/php.gdbinit \
	https://raw.githubusercontent.com/php/php-src/PHP-8.3/.gdbinit || true

{
	echo "===== latest php core ====="
	sudo coredumpctl --no-pager info || true
	echo "===== gdb zbacktrace + bt full ====="
	sudo coredumpctl --no-pager debug --debugger=gdb --debugger-arguments="-batch -ex 'set pagination off' -ex 'set debuginfod enabled on' -ex 'source /tmp/php.gdbinit' -ex zbacktrace -ex 'bt full' -ex 'info registers'" || true
} | tee /tmp/php-s-gdb-bt.txt
