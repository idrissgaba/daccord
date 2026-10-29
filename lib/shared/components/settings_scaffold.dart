import 'package:bonfire/theme/theme.dart';
import 'package:bonfire/shared/components/escape_to_close.dart';
import 'package:flutter/material.dart';

/// Standard chrome for a pushed settings sub-page: themed [Scaffold] +
/// [AppBar] with a back button that calls `Navigator.maybePop`.
class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final scaffold = Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.foreground,
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: actions,
      ),
      floatingActionButton: floatingActionButton,
      // Content keeps a readable column on wide windows instead of
      // stretching toggles to the far edge.
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: body,
        ),
      ),
    );
    return EscapeToClose(child: scaffold);
  }
}
