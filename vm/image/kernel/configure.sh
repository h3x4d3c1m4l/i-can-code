#!/bin/sh
# Cuts Alpine's linux-virt config down to the one machine it has to run on, v86: one CPU and no
# ACPI (v86 offers neither), no block layer (the root is 9p), and no module loader, so what the
# guest used to load is built in and nothing reads /lib/modules or an initramfs. The rest is code
# a v86 guest never runs: tracing, BPF, audit, LSMs, IPv6, netfilter, hypervisor guests, sound
# and USB. See docs/vm-build.md, "The kernel".
#
# Usage: configure.sh, in the kernel tree, with Alpine's config as .config and ARCH=i386 and
# LLVM=1 in the environment. Exits 1 if Kconfig dropped an option the guest needs.
set -eu

c=scripts/config

cut_down() {
  # With MODULES off Kconfig would build every =m into the kernel, so nothing is left as one.
  sed -i -E 's/^(CONFIG_[A-Za-z0-9_]+)=m$/# \1 is not set/' .config
  # What the guest loaded as modules: virtio and 9p for the root, bochs-drm and its fbdev for
  # Xorg, evdev, the PS/2 mouse the VMMouse rides on, and the keyboard.
  for o in $NEEDED; do $c -e "$o"; done
  $c -d MODULES -d DRM_SIMPLEDRM -d SYSFB_SIMPLEFB -d INPUT_MOUSEDEV
  # 128 MiB fits in low memory, so neither PAE nor highmem has anything to map.
  $c -d SMP -d NUMA -d X86_PAE -d HIGHMEM4G -d HIGHMEM64G -e NOHIGHMEM
  $c -d ACPI -d EFI -d KEXEC -d CRASH_DUMP -d HIBERNATION -d SUSPEND -d X86_MCE -d MICROCODE
  $c -d PARAVIRT -d XEN -d KVM_GUEST -d HYPERV -d JAILHOUSE_GUEST -d ACRN_GUEST
  $c -d BLOCK -d SWAP -d ZSWAP -d MD -d ATA -d SCSI
  $c -d BPF_SYSCALL -d BPF_JIT -d CGROUP_BPF -d AUDIT -d SECURITY -d INTEGRITY -d IO_URING
  $c -d FTRACE -d KPROBES -d UPROBES -d PROFILING -d KALLSYMS_ALL
  $c -d IPV6 -d NETFILTER -d XFRM -d NET_SCHED -d BRIDGE -d VLAN_8021Q -d WIRELESS -d CFG80211 -d BT
  $c -d SOUND -d USB_SUPPORT -d HID -d INPUT_JOYSTICK -d INPUT_TABLET -d INPUT_TOUCHSCREEN -d INPUT_MISC
  $c -d DEBUG_INFO -e DEBUG_INFO_NONE -d ZERO_CALL_USED_REGS -e INPUT_MOUSE -e NETWORK_FILESYSTEMS
  $c -d SLUB_DEBUG -d DEBUG_BUGVERBOSE -d MODULE_SIG -d RANDOMIZE_BASE
}

# Only options a user can set: the helpers under them are selected, and which helpers bochs-drm
# selects changes between kernels (TTM and VRAM up to 6.12, GEM SHMEM in 6.18).
NEEDED="VIRTIO_PCI NET_9P NET_9P_VIRTIO 9P_FS DRM DRM_BOCHS DRM_FBDEV_EMULATION FB FB_CORE
  FRAMEBUFFER_CONSOLE INPUT_EVDEV INPUT_MOUSE MOUSE_PS2 MOUSE_PS2_VMMOUSE SERIO_I8042 KEYBOARD_ATKBD
  DEVTMPFS DEVTMPFS_MOUNT TMPFS UNIX"

# Twice: olddefconfig can turn on a new option's default that the first pass would have cut.
cut_down
make olddefconfig >/dev/null
cut_down
make olddefconfig >/dev/null

# What the guest cannot do without, including what the agent's sandbox and PREPARE lean on. An
# option whose dependencies a new kernel moved is dropped by olddefconfig without a word.
missing=""
for o in $NEEDED SERIAL_8250 VT CGROUPS MEMCG SHMEM; do
  grep -q "^CONFIG_$o=y$" .config || missing="$missing $o"
done
if grep -q '^CONFIG_MODULES=y$' .config; then missing="$missing (MODULES is still on)"; fi
if [ -n "$missing" ]; then
  echo "configure.sh: the kernel config lost what the guest needs:$missing" >&2
  exit 1
fi
