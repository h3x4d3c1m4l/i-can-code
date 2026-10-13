import 'package:flutter/widgets.dart';
import 'package:i_can_code/routing/app_router.gr.dart';

/// What a [CatalogAnchor] names: a group's heading, or one lesson's card.
enum CatalogAnchorKind {

  group('group'),
  lesson('lesson');

  /// The query parameter an anchor of this kind travels in. MUST stay in step
  /// with the `@QueryParam`s of `CatalogScreen`, which
  /// `test/routing/app_router_test.dart` holds.
  final String parameter;

  const CatalogAnchorKind(this.parameter);

}

/// A place in a subject's catalog that an address can name:
/// `/learn-python?group=week-1` or `/learn-python?lesson=uitvoer`.
///
/// The catalog scrolls to it and lights it up. [id] is a `LessonGroup.id` or a
/// `Lesson.id`, never a position or a title, so a link survives the course
/// being reordered, reworded and translated. An id the course does not have
/// names nothing, and the catalog opens as it would without one.
///
/// A record, so two that name the same place are equal.
typedef CatalogAnchor = ({CatalogAnchorKind kind, String id});

/// A subject's catalog, as a route. **Build a [CatalogRoute] that carries an
/// [anchor] through here**, because of the key.
///
/// auto_route updates the page it already has in place. Asked for the anchor
/// it was last opened on, the catalog would be handed the arguments it already
/// had, and would not move. A key of its own makes every arrival at an anchor a
/// new screen, which scrolls. The reason [lessonRoute] keys a lesson, turned
/// round.
///
/// Without an anchor there is no key, so the catalog a reader comes back to is
/// the one they left, scrolled to where they left it.
CatalogRoute catalogRoute({required String subjectSlug, CatalogAnchor? anchor}) => CatalogRoute(
  key: anchor == null ? null : UniqueKey(),
  subjectSlug: subjectSlug,
  group: anchor?.kind == CatalogAnchorKind.group ? anchor?.id : null,
  lesson: anchor?.kind == CatalogAnchorKind.lesson ? anchor?.id : null,
);

/// The whole address of [anchor] in the catalog of [subjectSlug], for a reader
/// to paste somewhere else.
///
/// The route goes in the fragment: `https://host/#/learn-python?group=week-1`.
/// That is Flutter's hash URL strategy, which is the default on the web and
/// which the app leaves alone. Setting a path strategy would need this to
/// change with it.
///
/// [base] is the address the app is at, [Uri.base] unless a test says
/// otherwise.
Uri catalogAddress({required String subjectSlug, required CatalogAnchor anchor, Uri? base}) {
  final route = Uri(path: '/$subjectSlug', queryParameters: {anchor.kind.parameter: anchor.id});

  return (base ?? Uri.base).replace(fragment: route.toString());
}
