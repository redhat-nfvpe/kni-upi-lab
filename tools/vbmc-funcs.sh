#!/bin/bash

delete_vbmc() {
    local name="$1"

    if vbmc show "$name" > /dev/null 2>&1; then
        vbmc stop "$name" > /dev/null 2>&1
        vbmc delete "$name" > /dev/null 2>&1
    fi
}

create_vbmc() {
    local name="$1"
    local port="$2"

    vbmc add "$name" --port "$port" --username ADMIN --password ADMIN
    vbmc start "$name" > /dev/null 2>&1
}
