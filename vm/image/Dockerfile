# syntax=docker/dockerfile:1
# check=skip=FromPlatformFlagConstDisallowed

# The Alpine release every stage builds on, and the only place it is named. Python, Tk and the
# kernel are whatever that release ships. `just update-vm-image` rewrites this line, and
# `just build-vm-agent` passes it on to vm/agent/Dockerfile. See vm/README.md.
ARG ALPINE_VERSION=3.24

# icc-agent, built as vm/agent/Dockerfile builds it, from the named build context agent-src that
# vm/tools/build-image.sh points at vm/agent. The steps match that file's line for line, so the
# two builds share Docker's cache of the Rust toolchain.
FROM --platform=linux/386 alpine:${ALPINE_VERSION} AS agent-build

RUN apk add --no-cache rust cargo

WORKDIR /src

COPY --from=agent-src Cargo.toml Cargo.lock ./
RUN mkdir src && touch src/main.rs && cargo fetch --locked

COPY --from=agent-src src ./src
RUN target=$(rustc -vV | sed -n 's/^host: //p') && \
    RUSTFLAGS="-C target-feature=+crt-static" cargo build --release --locked --offline --target "$target" && \
    cp "target/$target/release/icc-agent" /icc-agent

# What icc-agent is linked from, for the bundle's NOTICES.txt: the crates with their licences,
# and the Rust and musl it is linked statically with. Only built when named, as build-image.sh
# does with --target agent-licences, so the image build does not wait on it.
FROM agent-build AS agent-crates
RUN target=$(rustc -vV | sed -n 's/^host: //p') && \
    { rustc -V | sed 's/^/# /'; \
      awk '/^P:/ { p = substr($0, 3) } /^V:/ && p == "musl-dev" { print "# musl-dev " substr($0, 3) }' /lib/apk/db/installed; \
      cargo tree --locked --offline --target "$target" --edges normal --prefix none --format '{p}|{l}' | sort -u; \
    } > /agent-crates.txt

FROM scratch AS agent-licences
COPY --from=agent-crates /agent-crates.txt /

# Alpine's config for the linux-virt kernel of the pinned release, that kernel's version, and the
# package's own version and aports commit for NOTICES.txt. Only these are taken from the package:
# the kernel stage below builds the same version itself. 3.22 names the config config-virt and
# 3.24 config-<release>-virt.
FROM --platform=linux/386 alpine:${ALPINE_VERSION} AS kernel-config
RUN apk add --no-cache linux-virt && \
    mkdir /out && \
    cp /boot/config-*virt /out/config-virt && \
    cp /usr/share/kernel/virt/kernel.release /out/release && \
    awk '/^P:/ { p = substr($0, 3) } p == "linux-virt" && /^[Voc]:/ { f[substr($0, 1, 1)] = substr($0, 3) } \
         END { print "linux-virt", f["V"], f["o"], f["c"] }' /lib/apk/db/installed > /out/package

# The kernel v86 boots: the linux-virt version, from kernel.org, with Alpine's config cut down by
# kernel/configure.sh. It builds on the build machine's own architecture, since clang
# cross-compiles for i386 on its own and under QEMU the build would take an hour. The source is
# kept in a cache mount and unpacked into tmpfs, so the tree never becomes a layer.
FROM --platform=$BUILDPLATFORM alpine:${ALPINE_VERSION} AS kernel
# gcc for the crt files and libgcc that clang links the kernel's host tools with. Alpine's clang
# stopped pulling it in with 3.24.
RUN apk add --no-cache bash bc bison clang coreutils diffutils elfutils-dev findutils flex gawk gcc \
        linux-headers lld llvm make openssl-dev perl tar xz zstd
COPY --from=kernel-config /out/ /kernel/
COPY kernel/configure.sh /kernel/
# The checksum comes from the same server over the same TLS, so it catches a truncated or corrupt
# download and nothing more.
RUN --mount=type=cache,id=icc-vm-kernel-source,target=/cache \
    --mount=type=tmpfs,target=/build \
    set -eux; \
    version=$(sed 's/-.*//' /kernel/release); \
    tarball=linux-$version.tar.xz; \
    url=https://cdn.kernel.org/pub/linux/kernel/v${version%%.*}.x; \
    find /cache -name 'linux-*.tar.xz*' ! -name "$tarball" -delete; \
    [ -f "/cache/$tarball" ] || { wget -q -O "/cache/$tarball.part" "$url/$tarball" && mv "/cache/$tarball.part" "/cache/$tarball"; }; \
    wget -q -O /build/sha256sums.asc "$url/sha256sums.asc"; \
    grep " $tarball\$" /build/sha256sums.asc > /build/sum; \
    (cd /cache && sha256sum -c /build/sum) || { rm -f "/cache/$tarball"; exit 1; }; \
    tar -xf "/cache/$tarball" -C /build; \
    cd "/build/linux-$version"; \
    cp /kernel/config-virt .config; \
    export ARCH=i386 LLVM=1 KBUILD_BUILD_USER=icc KBUILD_BUILD_HOST=icc-vm; \
    sh /kernel/configure.sh; \
    make -j"$(nproc)" bzImage > /build/make.log 2>&1 || { tail -60 /build/make.log; exit 1; }; \
    mkdir /out; \
    cp arch/x86/boot/bzImage /out/vmlinuz; \
    cp .config /out/config; \
    { echo "release $(make -s kernelrelease)"; echo "source $url/$tarball"; \
      echo "sha256 $(cut -d ' ' -f 1 /build/sum)"; echo "config $(cat /kernel/package)"; } > /out/kernel.txt

# The guest the Tkinter playground runs in: Alpine i386, its Python with Tk, and Xorg on fbdev.
# v86 emulates a 32-bit PC, so the platform is fixed rather than taken from the build. Grown from
# v86's tools/docker/alpine recipe. docs/vm-build.md is the build and its reasons. It stays the
# last stage, the one a build without --target makes.
FROM --platform=linux/386 alpine:${ALPINE_VERSION} AS image

# alpine-base's dependencies without busybox-suid, a setuid-root busybox behind su, passwd and
# mount that nothing in the guest needs. Without it those applets are plain busybox links.
RUN apk add --no-cache openrc alpine-baselayout alpine-conf alpine-release apk-tools busybox \
        busybox-mdev-openrc busybox-openrc musl-utils

RUN apk add --no-cache python3 tk python3-tkinter tzdata

# xwininfo is not used by anything in the guest; it is how a build is checked from the console.
RUN apk add --no-cache xorg-server xf86-video-fbdev xf86-input-evdev font-dejavu xwininfo

# Mesa's Gallium drivers and LLVM are only reached through glx and glamor, which 10-v86.conf
# disables. ensurepip, lib2to3 (gone since 3.13), turtledemo and the build config have no use
# without a compiler or a network. Optimised pycs are only read under -O, which nothing passes.
# build-image.sh reads /lib/apk/db/installed for vm/image/packages.lock, so it has to stay.
RUN set -eux; \
    stdlib=$(python3 -c 'import sysconfig; print(sysconfig.get_path("stdlib"))'); \
    config=$(python3 -c 'import sysconfig; print(sysconfig.get_config_var("LIBPL"))'); \
    rm -rf /usr/share/man /usr/share/doc /usr/share/info /usr/share/gtk-doc /usr/share/locale \
           /usr/lib/tk8.*/demos /usr/include /usr/share/aclocal /usr/share/pkgconfig /usr/lib/pkgconfig \
           /var/cache/apk/*; \
    rm -f /usr/lib/libLLVM*.so* /usr/lib/libgallium-*.so /usr/lib/dri/*.so /usr/lib/gallium-pipe/*.so \
          /usr/lib/libSPIRV-Tools*.so* \
          /usr/lib/xorg/modules/libglamoregl.so /usr/lib/xorg/modules/extensions/libglx.so; \
    rm -rf "$stdlib/ensurepip" "$stdlib/lib2to3" "$stdlib/turtledemo" "$config"; \
    find "$stdlib" -name '*.opt-[12].pyc' -delete

# More files nothing in the guest reads. They cost the student almost nothing, since a file never
# read is never fetched, but they are most of the rootfs a release carries and a deploy serves:
# the libraries only Mesa's GL, the SPIR-V tools or each other link, those tools, the bitmap fonts
# but for the cursor and the 6x13 Xorg falls back to, the Tcl packages Tk never loads, and
# CPython's own test modules. The scanelf pass then holds every library an ELF file still names
# against what is left, so a package that starts linking one of these stops the build here rather
# than a student's run. Python's .py sources stay: a traceback quotes the stdlib lines it names.
RUN set -eu; \
    dynload=$(python3 -c 'import sysconfig; print(sysconfig.get_config_var("DESTSHARED"))'); \
    cd /usr/lib; \
    rm -f libGL.so* libEGL.so* libGLES*.so* gbm/dri_gbm.so libepoxy.so* libdrm_*.so* libxml2.so* \
          libbrotlienc.so* libhogweed.so* libelf*.so* libpsx.so* libmpdec++.so* libstdc++.so* libpython3.so \
          libxcb-composite.so* libxcb-damage.so* libxcb-dbe.so* libxcb-dpms.so* libxcb-dri2.so* \
          libxcb-dri3.so* libxcb-glx.so* libxcb-present.so* libxcb-randr.so* libxcb-record.so* \
          libxcb-render.so* libxcb-res.so* libxcb-screensaver.so* libxcb-shm.so* libxcb-sync.so* \
          libxcb-xf86dri.so* libxcb-xfixes.so* libxcb-xinerama.so* libxcb-xinput.so* libxcb-xkb.so* \
          libxcb-xtest.so* libxcb-xv.so* libxcb-xvmc.so* \
          /usr/bin/spirv-*; \
    rm -rf itcl[0-9]* thread[0-9]* tdbc*; \
    rm -f "$dynload"/_test*.so "$dynload"/_ctypes_test*.so "$dynload"/_xxtestfuzz*.so \
          "$dynload"/xxlimited*.so "$dynload"/xxsubtype*.so; \
    cd /usr/share/fonts/misc; \
    grep -E '^(cursor|6x13|6x13-ISO8859-1)\.pcf\.gz ' fonts.dir > /tmp/fonts.dir; \
    for f in *.pcf.gz; do grep -q "^$f " /tmp/fonts.dir || rm "$f"; done; \
    { wc -l < /tmp/fonts.dir; cat /tmp/fonts.dir; } > fonts.dir; \
    rm /tmp/fonts.dir; \
    fc-cache -f; \
    scanelf -qRF '%F %n' /bin /sbin /lib /usr | while read -r file needed; do \
      for so in $(echo "$needed" | tr , ' '); do \
        for dir in /lib /usr/lib /usr/local/lib "${file%/*}"; do [ -e "$dir/$so" ] && continue 2; done; \
        echo "$file needs $so"; \
      done; \
    done > /tmp/unresolved; \
    if [ -s /tmp/unresolved ]; then echo "libraries named but gone:" >&2; cat /tmp/unresolved >&2; exit 1; fi; \
    rm /tmp/unresolved

# Alpine ships checked-hash pycs, so every import also reads and hashes the .py beside it, and
# over 9p that read is a fetch. An unchecked-hash pyc is trusted as it is, whatever the mtimes.
RUN stdlib=$(python3 -c 'import sysconfig; print(sysconfig.get_path("stdlib"))') && \
    python3 -m compileall -q -f -j 0 --invalidation-mode unchecked-hash "$stdlib" && \
    python3 -c 'import pathlib, sys; \
bad = [str(p) for p in pathlib.Path(sys.argv[1]).rglob("*.pyc") if p.read_bytes()[4:8] != b"\x01\0\0\0"]; \
sys.exit("not unchecked-hash: " + " ".join(bad[:5]) if bad else 0)' "$stdlib"

COPY files/ /

# The student's program runs as uid 1000. The host drops a run's files into /icc/in over 9p,
# and only the agent, as root, reads them from there.
RUN set -eux; \
    adduser -D -u 1000 -h /home/student -s /sbin/nologin student; \
    install -d -m 0755 /icc; \
    install -d -m 0700 /icc/in; \
    chmod 0444 /usr/lib/icc/prelude.py; \
    echo localhost > /etc/hostname; \
    sed -i 's|^SUBSYSTEM=input;\.\*|SUBSYSTEM=input;(input/)?event[0-9]+ root:input 0660 @/usr/lib/icc/mdev-input\n&|' \
        /etc/mdev.conf; \
    grep -q '/usr/lib/icc/mdev-input' /etc/mdev.conf; \
    for i in devfs dmesg mdev; do rc-update add $i sysinit; done; \
    for i in hwclock sysctl hostname bootmisc; do rc-update add $i boot; done; \
    rc-update add killprocs shutdown

# The agent starts Xorg as root, so the wrapper needs no setuid bit of its own. No file in the
# guest may keep one: a bug in it would be root for the student's program.
RUN set -eu; \
    chmod u-s /usr/libexec/Xorg.wrap; \
    setid=$(find / -xdev -type f -perm /6000); \
    if [ -n "$setid" ]; then echo "setuid or setgid files left: $setid" >&2; exit 1; fi

# v86 is handed the kernel directly and the kernel mounts the 9p root itself, so there is no
# initramfs. build-image.sh takes the kernel, its config and kernel.txt out of /boot, which the
# rootfs leaves out.
COPY --from=kernel /out/ /boot/

# Last, so a change to the agent rebuilds nothing above. files/etc/inittab respawns it on ttyS1.
COPY --from=agent-build /icc-agent /usr/local/bin/icc-agent
