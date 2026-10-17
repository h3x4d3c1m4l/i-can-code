// Where the image tools read and write. ICC_VM_BUILD_DIR moves all of it, the bundle included,
// into a directory of one's own, so a trial build (a newer Alpine, a size experiment) leaves
// vm/build/ and the app's web/vm/image/ as they were. build-image.sh reads the same variable.

import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const repoDir = fileURLToPath(new URL('../../..', import.meta.url));

const defaultBuildDir = path.join(repoDir, 'vm/build');

/** bzImage, fs.json, rootfs-flat/, bios/, the package lock and every report. */
export const buildDir = process.env.ICC_VM_BUILD_DIR ? path.resolve(process.env.ICC_VM_BUILD_DIR) : defaultBuildDir;

/** The bundle a page loads: web/vm/image/, or image/ inside any other build directory. */
export const imageDir = buildDir === defaultBuildDir ? path.join(repoDir, 'web/vm/image') : path.join(buildDir, 'image');
