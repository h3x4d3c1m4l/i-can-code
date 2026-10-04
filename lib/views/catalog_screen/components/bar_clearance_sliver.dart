import 'package:flutter/widgets.dart';
import 'package:i_can_code/views/components/app_header.dart';

/// Keeps the top of a [CustomScrollView] clear of the bar, and makes every
/// pinned sliver after it pin *below* the bar rather than behind it.
///
/// The page runs under the bar (see `AppHeaderHost`), so the top of its
/// viewport is hidden. A pinned sliver paints at its [SliverConstraints.overlap],
/// and the viewport sets that from what the pinned slivers before it still
/// paint. This one is pinned and paints nothing, so the overlap below it never
/// drops under [AppHeader.height], and what scrolls past still shows through.
///
/// It MUST be the first sliver.
class BarClearanceSliver extends StatelessWidget {

  const BarClearanceSliver({super.key});

  @override
  Widget build(BuildContext context) => const PinnedHeaderSliver(child: SizedBox(height: AppHeader.height));

}
