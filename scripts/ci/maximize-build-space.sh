#!/usr/bin/env bash
# Maximize available disk space on GitHub Actions runners by removing
# unused pre-installed software. Based on:
# https://github.com/easimon/maximize-build-space/blob/v10/action.yml#L121-L137
set -euo pipefail

echo "Available storage before removing unused software:"
sudo df -h
echo
sudo rm -rf /usr/local/lib/android
echo "Available storage after removing android:"
sudo df -h
echo
sudo rm -rf /opt/hostedtoolcache/CodeQL
echo "Available storage after removing codeql:"
sudo df -h
echo
