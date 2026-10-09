#!/bin/bash
cd ~/opt/rocm-7.14.1-dl
F=therock-dist-linux-gfx1151-7.14.1.tar.gz; SZ=1713467716
for i in $(seq 1 50); do
  [ "$(stat -c%s $F 2>/dev/null)" = "$SZ" ] && break
  wget -4 -c -q --tries=3 --timeout=30 --read-timeout=60 https://repo.amd.com/rocm/tarball-multi-arch/$F; sleep 2
done
h=$(sha256sum $F | cut -d" " -f1); echo "sha $h"
[ "$h" = c40e8f2bd6630a7d11557c762b99c6fa8afb04c9bd0e51ed1675ee1ca24afb00 ] && echo SHA_OK || echo SHA_BAD
