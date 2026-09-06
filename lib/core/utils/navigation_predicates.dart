import 'package:flutter/widgets.dart';

/// Route predicates for the "unwind to a known screen" navigations.
///
/// [ModalRoute.withName] on its own is unsafe for this: when the named route
/// is not on the stack the predicate matches nothing, and both `popUntil` and
/// `pushNamedAndRemoveUntil` respond by removing *every* route — leaving an
/// empty navigator, which renders as a black screen.
///
/// A stack without the expected name is a normal situation here, not a bug to
/// assert on: the screens running these unwinds are reachable from more than
/// one entry point, and only some of those paths put the named route below
/// them. Edit Meal sits under `addMealRoute` when it is opened from Add Meal,
/// and directly under whatever pushed it otherwise — the meal-detail edit
/// pencil reached from the Recipes or Library tab, for instance.
///
/// So this predicate stops at the first route as well. After the splash
/// screen replaces itself the first route is the main screen, which is the
/// floor these unwinds are aiming for anyway. Landing there is a worse-case
/// outcome worth having, against an empty navigator with nothing to
/// navigate back to.
RoutePredicate namedRouteOrFirst(String routeName) =>
    (route) => route.isFirst || route.settings.name == routeName;
