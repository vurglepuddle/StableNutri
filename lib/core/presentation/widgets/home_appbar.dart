import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/stable_wordmark.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/generated/l10n.dart';

class HomeAppbar extends StatelessWidget implements PreferredSizeWidget {
  const HomeAppbar({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      // The lockup carries the name, so there is no separate title text.
      title: const Align(
        alignment: Alignment.centerLeft,
        child: StableWordmark(),
      ),
      actions: [
        Semantics(
          identifier: 'today-open-diary',
          child: IconButton(
            tooltip: S.of(context).diaryLabel,
            onPressed: () =>
                Navigator.of(context).pushNamed(NavigationOptions.diaryRoute),
            icon: const Icon(Icons.calendar_month_outlined),
          ),
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
