/// Whether this build ships the machine's image in `web/vm/image/`, which git
/// ignores and a build fetches or makes on its own.
///
/// Set with `--dart-define=ICC_VM_IMAGE=true`, which a build MUST pass only when
/// the image is in place. Without one every download is a 404, and the page
/// could only put that to the student as their connection failing.
const bool vmImageIncluded = bool.fromEnvironment('ICC_VM_IMAGE');

/// Where the build serves the image, relative to the document: `manifest.json`
/// and the bundle it names.
const String vmImagePath = 'vm/image/';
