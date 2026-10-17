# The licence texts the image carries

`NOTICES.txt`, in every bundle, ends with the text of every licence the image's
parts declare. The texts are here, one file each, and `vm/tools/lib/licences.mjs`
puts them into the notices. The GPL and the LGPL ask for their text to travel
with the binary, so a bundle missing one cannot be released: `just
package-vm-image` refuses it. See [docs/vm-build.md](../../docs/vm-build.md),
"Licences".

## What is here

| File | Answers |
| --- | --- |
| `<spdx-id>.txt` | Every part that declares `<spdx-id>`, whichever way its expression names it. |
| `packages/<name>.txt` | That one Alpine package, and only where no identifier it declares has a text. It is how a package that declares `custom` carries its licence at all. |

`GPL-2.0-only` and `GPL-2.0-or-later` are one text under two names, and the
notices print such a pair as one section. A declaration that is no licence
(`Public Domain`) has no text and is listed as such.

## Where each came from

Every `<spdx-id>.txt` is the SPDX licence list's own text for that identifier,
verbatim:

    https://github.com/spdx/license-list-data/blob/main/text/<spdx-id>.txt

All 28 were compared byte for byte against that source on 2026-09-20, when the
list stood at version 3.29.0. `LLVM-exception` is an exception rather than a
licence and sits in the same `text/` directory.

The two in `packages/` are the package's own licence file, byte for byte:

| File | From |
| --- | --- |
| `packages/libxcvt.txt` | `COPYING` of <https://gitlab.freedesktop.org/xorg/lib/libxcvt> |
| `packages/font-alias.txt` | `COPYING` of <https://gitlab.freedesktop.org/xorg/font/alias> |

## Adding one

An image update that brings in a package under a licence nothing here answers
fails `node --test vm/tools/test/licences.test.mjs`, which holds this directory
against `vm/image/packages.lock`, and `just package-vm-image` refuses the bundle
when the licence is copyleft. To close it:

1. Take the text from the SPDX list at the URL above, under the identifier the
   package declares. Where SPDX has no such identifier, take the package's own
   licence file from its upstream source and save it as `packages/<name>.txt`.
2. Save it verbatim. Do not reflow it, do not indent it and do not correct it:
   what makes it a copy of the licence is that it is unchanged.
3. Run `node vm/tools/write-notices.mjs` to write the bundle's `NOTICES.txt`
   again and name it in the manifest. That needs the build directory the bundle
   came from, and no image rebuild.
4. Note it in the table above, with where it came from.
