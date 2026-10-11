import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/licenses/bundled_licenses.dart';
import 'package:i_can_code/services/licenses/license_catalog.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/theme/squircle_input_border.dart';
import 'package:i_can_code/views/components/catalog_group_heading.dart';
import 'package:i_can_code/views/licenses_screen/components/license_row.dart';
import 'package:i_can_code/views/licenses_screen/license_labels.dart';

/// The licence screen's list: a search field, and under it every component the
/// app ships, under a heading for where it comes from.
class LicenseList extends StatelessWidget {

  /// What the headings are indented by, so they line up with the names under
  /// them rather than with the edge of a row's hover fill.
  static const double _headingInset = 14;

  /// What to list, already narrowed to the search. See [groupsMatching].
  final Map<LicenseOrigin, List<LicensedComponent>> groups;

  /// The component whose row is marked, or null where none is open.
  final LicensedComponent? selected;

  final ValueChanged<LicensedComponent> onPick;

  /// What the search field opens with.
  ///
  /// A narrow window takes this list away while a component is open. The
  /// field has to come back saying what [groups] is still narrowed to.
  final String query;

  final ValueChanged<String> onSearch;

  const LicenseList({
    required this.groups,
    required this.selected,
    required this.onPick,
    required this.query,
    required this.onSearch,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = context.localizations;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FTextField(
          control: .managed(initial: TextEditingValue(text: query), onChange: (value) => onSearch(value.text)),
          hint: localizations.licensesScreen_search,
          // A name is not prose: nothing here is a word to capitalise or correct.
          textCapitalization: TextCapitalization.none,
          autocorrect: false,
          prefixBuilder: (context, style, variants) =>
              FTextField.prefixIconBuilder(context, style, variants, const Icon(FLucideIcons.search)),
          style: FTextFieldStyleDelta.delta(
            // A chip's radius, not a control's: the field is one line tall, and
            // a squircle bows inward past half its shortest side.
            border: squircleFieldBorder(context, radius: kChipCornerRadius),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: groups.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _headingInset),
                  child: Text(
                    localizations.licensesScreen_empty,
                    style: context.appTheme.text.bodySmall.copyWith(
                      fontSize: 16,
                      color: context.theme.colors.mutedForeground,
                    ),
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    for (final MapEntry(key: origin, value: components) in groups.entries) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(_headingInset, 12, _headingInset, 8),
                          child: CatalogGroupHeading(originLabel(localizations, origin)),
                        ),
                      ),
                      SliverList.builder(
                        itemCount: components.length,
                        itemBuilder: (context, index) {
                          final component = components[index];

                          return LicenseRow(
                            name: componentName(localizations, component),
                            selected: identical(component, selected),
                            onPress: () => onPick(component),
                          );
                        },
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 12)),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

}
