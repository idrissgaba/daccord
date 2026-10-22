import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/views/box/accord_embed_box.dart';
import 'package:bonfire/features/messaging/views/box/accord_markdown_box.dart';
import 'package:bonfire/features/messaging/views/box/accord_message_markup.dart';
import 'package:bonfire/features/messaging/views/message_media_gate.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Joins the plain text of every [RichText] paragraph on screen (skipping the
/// chip RichTexts, whose root span is a [WidgetSpan]).
String _paragraphText(WidgetTester tester) {
  final buffer = StringBuffer();
  for (final element in find.byType(RichText).evaluate()) {
    final span = (element.widget as RichText).text;
    if (span is WidgetSpan) continue;
    buffer.write(span.toPlainText());
  }
  return buffer.toString();
}

Widget _host(Widget child) => MaterialApp(
  theme: buildAppTheme(AppThemePreset.dark),
  home: Scaffold(body: child),
);

void main() {
  testWidgets(
    'renders markdown and a channel chip together; chip is tappable',
    (tester) async {
      String? tapped;
      final markup = accordMarkupSyntaxes(
        AccordMarkupContext(
          channelByName: {
            'general': AccordChannel(id: 'c1', name: 'general', type: 'text'),
          },
        ),
      );

      await tester.pumpWidget(
        _host(
          AccordMarkdownBox(
            content: 'see **bold** in #general now',
            syntaxExtensions: markup,
            elementBuilders: accordMarkupBuilders(
              onTapChannel: (id) => tapped = id,
            ),
          ),
        ),
      );
      await tester.pump();

      // Markdown was applied (asterisks stripped), not shown verbatim.
      final text = _paragraphText(tester);
      expect(text, contains('bold'));
      expect(text, isNot(contains('*')));

      // The channel rendered as a chip pill, and tapping it fires the callback.
      expect(find.text('#general'), findsOneWidget);
      await tester.tap(find.text('#general'));
      await tester.pump();
      expect(tapped, 'c1');
    },
  );

  testWidgets('chips @everyone but leaves email-like @ handles as plain text', (
    tester,
  ) async {
    final markup = accordMarkupSyntaxes(const AccordMarkupContext());

    await tester.pumpWidget(
      _host(
        AccordMarkdownBox(
          content: 'mail me at email@host then ping @everyone',
          syntaxExtensions: markup,
          elementBuilders: accordMarkupBuilders(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('@everyone'), findsOneWidget);
    expect(_paragraphText(tester), contains('email@host'));
  });

  testWidgets('unresolved #channel stays plain text (no chip)', (tester) async {
    final markup = accordMarkupSyntaxes(const AccordMarkupContext());

    await tester.pumpWidget(
      _host(
        AccordMarkdownBox(
          content: 'look at #nowhere please',
          syntaxExtensions: markup,
          elementBuilders: accordMarkupBuilders(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('#nowhere'), findsNothing);
    expect(_paragraphText(tester), contains('#nowhere'));
  });

  testWidgets('markdown local image URI is blocked before an image is built', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const AccordMarkdownBox(
          content: '![private](file:///etc/passwd)',
          trustedMediaBaseUrl: 'https://chat.example/cdn',
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(MessageMediaGate), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.text('private'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('load-external-message-image')),
      findsNothing,
    );
  });

  testWidgets('markdown and embed images require consent off the CDN origin', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            const AccordMarkdownBox(
              content: '![pixel](https://tracker.example/markdown.png)',
              trustedMediaBaseUrl: 'https://chat.example/cdn',
            ),
            AccordEmbedBox(
              embed: AccordEmbed(
                image: {'url': 'https://tracker.example/embed.png'},
              ),
              cdnUrl: 'https://chat.example/cdn',
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(
      find.textContaining('Load external image from tracker.example'),
      findsNWidgets(2),
    );
  });

  testWidgets('a -# line renders as smaller, dimmed subtext', (tester) async {
    await tester.pumpWidget(
      _host(
        AccordMarkdownBox(
          content: 'main line\n-# fine **print**',
          syntaxExtensions: accordMarkupSyntaxes(),
          elementBuilders: accordMarkupBuilders(),
        ),
      ),
    );
    await tester.pump();

    final text = _paragraphText(tester);
    expect(text, contains('main line'));
    expect(text, contains('fine print'));
    expect(text, isNot(contains('-#')));
    expect(text, isNot(contains('*')));

    double? sizeOf(String needle) {
      for (final element in find.byType(RichText).evaluate()) {
        final span = (element.widget as RichText).text;
        double? found;
        span.visitChildren((child) {
          if (child is TextSpan &&
              (child.text ?? '').contains(needle) &&
              child.style?.fontSize != null) {
            found = child.style!.fontSize;
            return false;
          }
          return true;
        });
        if (found != null) return found;
        if (span is TextSpan && (span.text ?? '').contains(needle)) {
          return span.style?.fontSize;
        }
      }
      return null;
    }

    final mainSize = sizeOf('main line');
    final subSize = sizeOf('fine');
    expect(mainSize, isNotNull);
    expect(subSize, isNotNull);
    expect(subSize!, lessThan(mainSize!));
  });

  testWidgets('a <t:…> token shows a formatted date, not the raw token', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        AccordMarkdownBox(
          content: 'meet <t:1792660000:D> or <t:1792660000:R>',
          syntaxExtensions: accordMarkupSyntaxes(),
          elementBuilders: accordMarkupBuilders(),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('<t:'), findsNothing);
    // 1792660000 is in October 2026; the D style shows the month and year.
    expect(find.textContaining('2026'), findsWidgets);
    // The relative one reads "… ago" or "in …" depending on today.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            ((w.data ?? '').endsWith(' ago') ||
                (w.data ?? '').startsWith('in ')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('an out-of-range timestamp stays literal text', (tester) async {
    await tester.pumpWidget(
      _host(
        AccordMarkdownBox(
          content: 'bad <t:9999999999999>',
          syntaxExtensions: accordMarkupSyntaxes(),
          elementBuilders: accordMarkupBuilders(),
        ),
      ),
    );
    await tester.pump();
    expect(_paragraphText(tester), contains('<t:9999999999999>'));
  });
}
