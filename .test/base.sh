#!/bin/sh

if [ -z "$NICTOOL_HOME" ]; then
    if [ -n "$TRAVIS" ]; then
        NICTOOL_HOME="/home/travis/build/msimerson/NicTool"
    elif [ -n "$GITHUB_ACTIONS" ]; then
        NICTOOL_HOME="/home/runner/work/NicTool/NicTool"
    elif [ "$HOME" = "/Users/matt" ]; then
        NICTOOL_HOME="/Users/matt/git/nictool"
    elif [ "$HOME" = "/home/matt" ]; then
        NICTOOL_HOME="/home/matt/nictool"
    fi
fi

if [ -z "$NICTOOL_HOME" ]; then
    echo "Unknown test environment, export NICTOOL_HOME to continue"
    exit 1
fi

export NICTOOL_HOME
