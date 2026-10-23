import 'package:web/web.dart' as web;

/// The id MUST match the splash's container in `web/index.html`.
void removeSplash() => web.document.getElementById('loading-container')?.remove();
