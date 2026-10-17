// Where both workers put the standard library in the interpreter's filesystem.
//
// It is the place CPython's getpath looks unasked, with PYTHONHOME=/ as the
// prefix. Since 3.15 getpath checks that place on every start and writes
// "Could not find the standard library directory!" to stderr when it is empty,
// and a PYTHONPATH does not count as an answer. See docs/python-wasm-build.md.
//
// A new minor version renames both, and `pythonStdlibPath` in
// lib/services/python/python_assets_web.dart with them.

/** The stdlib zip. */
export const STDLIB_ZIP = '/lib/python315.zip';

/** Empty, and still required: the check fails without it although this build
 *  loads no extension modules. */
export const STDLIB_DIRECTORIES = ['/lib/python3.15/lib-dynload'];
