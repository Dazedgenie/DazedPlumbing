#!/bin/sh
# Runs every headless test against the mod's Lua. Needs a Lua 5.1-5.4 interpreter on PATH as `lua`; DazedCore is expected beside this repo.
cd "$(dirname "$0")" || exit 1
ROOT=../../common/media/lua
rc=0
for t in net plumbing place mains fuel digester freeze; do lua ${t}_test.lua $ROOT || rc=1; done
exit $rc
