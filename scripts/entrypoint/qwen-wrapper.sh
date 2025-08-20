#!/bin/bash

# Qwen CLI Wrapper Script
# Ensures proper terminal settings for interactive use

# Force proper terminal configuration
export TERM=${TERM:-xterm-256color}
export FORCE_COLOR=1

# Initialize terminal settings
if [ -t 0 ] && [ -t 1 ]; then
    # We have a proper TTY, configure it
    stty sane 2>/dev/null || true
    stty echo 2>/dev/null || true
    stty icanon 2>/dev/null || true
    stty -echo 2>/dev/null && stty echo 2>/dev/null || true
fi

# Execute qwen with all passed arguments
exec qwen "$@"