// The emulated machine this image is built for. A saved state restores only into the settings it
// was saved with, so everything that boots the image or writes its manifest reads them from here.
export const machine = {
    // The run's budget and Xorg's room for a program's pixmaps both come out of the warm machine's
    // free memory, and at 96 MiB they could not both hold a 1920 x 1080 Canvas. What 128 costs is
    // in docs/vm-build.md, "The machine".
    memoryMiB: 128,
    // bochs-drm ignores an adapter with less than 4 MiB, and at 4 MiB it rejects any mode whose
    // frame does not fit twice, so 800 x 600 is also the largest screen this allows.
    vgaMiB: 4,
    // ttyS1, the agent's control line. ttyS0 stays the kernel console.
    uart1: true,
    screen: { width: 800, height: 600 },
    cmdline: [
        // v86's 9p root, which the kernel mounts itself: there is no initramfs. ignoreqv because
        // v86 reports every file's qid version as 0, which Linux since 6.12 takes to mean
        // "uncacheable": without it nothing read over 9p stays in the page cache, and every exec
        // fetches its binary again.
        "rw root=host9p rootfstype=9p rootflags=trans=virtio,cache=loose,ignoreqv",
        // v86's TSC is the only clocksource worth having; do not let a watchdog swap it out.
        "tsc=reliable",
        "console=ttyS0",
        // The X screen size: fbdev takes whatever mode bochs-drm's fbdev emulation starts in.
        "video=800x600",
        // v86's TSC counts on while the CPU is stopped, and a resume would look like a hang to
        // the lockup and stall detectors. vm_host.js stops the TSC with the CPU, so nothing
        // should trip them; these keep the console quiet if something ever resumes it unaided.
        "nowatchdog nosoftlockup rcupdate.rcu_cpu_stall_suppress=1",
        // Page-table isolation and retpolines guard against speculative-execution flaws that
        // v86's CPU, which does not speculate, cannot have, and every syscall pays for them.
        "mitigations=off",
        // A freed page keeps whatever was in it, and the saved state carries every one of those
        // bytes. Zeroing on free makes them all compress alike: 1.2 MB off the state, with no
        // slowdown measured over the corpus.
        "init_on_free=1",
    ].join(" "),
};
