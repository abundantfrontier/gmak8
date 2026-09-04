#!/bin/bash
# Double-click in Finder to build Debug gmak8 and install to /Applications.
cd "$(dirname "$0")/.." || exit 1
bash scripts/dev-install.sh
status=$?
if [ "$status" -ne 0 ]; then
    echo
    echo "Install stopped (exit $status). Close this window when you are done reading."
    read -r _
fi
exit "$status"
