#!/bin/sh
# Remove a per-user Forge installation using the installer's ownership checks.
exec sh "$(dirname "$0")/install.sh" --uninstall
