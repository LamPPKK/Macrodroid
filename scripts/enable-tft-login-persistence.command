#!/bin/zsh
set -euo pipefail

# Transform Engine.ini on stdin. Riot owns and encrypts the saved session;
# this only enables its existing Unreal Config preference.
LC_ALL=C /usr/bin/awk '
    BEGIN {
        section = "[/Script/OnlineSubsystemRiot.RGIOPRiotGamesApiSettings]"
    }
    {
        sub(/\r$/, "")
        header = $0
        sub(/^[[:space:]]+/, "", header)
        sub(/[[:space:]]+$/, "", header)
    }
    header == section {
        in_section = 1
        print
        if (!found) print "bPersistLogin=True"
        found = 1
        next
    }
    header ~ /^\[/ { in_section = 0 }
    in_section && /^[[:space:]]*bPersistLogin[[:space:]]*=/ { next }
    { print }
    END {
        if (!found) {
            if (NR > 0) print ""
            print section
            print "bPersistLogin=True"
        }
    }
'
