import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/photo_lightbox.dart';

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('shows a loader while the full-size image is in flight',
      (tester) async {
    await tester.pumpWidget(
      _wrap(const PhotoLightbox(url: 'https://example.test/photo.jpg')),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('This photo couldn’t be loaded.'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a dead URL lands on an error affordance, not a black void',
      (tester) async {
    await tester.pumpWidget(
      _wrap(const PhotoLightbox(url: 'https://example.test/expired.jpg')),
    );
    // The test binding answers every HTTP request with a 400, so the image
    // resolves to an error — the expired-signed-URL case.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.text("This photo couldn't be loaded."), findsOneWidget);
    expect(find.text('Tap anywhere to close.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a caption stays legible over the failed image', (tester) async {
    await tester.pumpWidget(
      _wrap(const PhotoLightbox(
        url: 'https://example.test/expired.jpg',
        caption: 'Summit at sunrise',
      )),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Summit at sunrise'), findsOneWidget);
    expect(find.text("This photo couldn't be loaded."), findsOneWidget);
  });

  testWidgets('tapping the barrier dismisses the viewer', (tester) async {
    await tester.pumpWidget(_wrap(Builder(
      builder: (context) => TextButton(
        onPressed: () =>
            showPhotoLightbox(context, url: 'https://example.test/p.jpg'),
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(PhotoLightbox), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(PhotoLightbox), findsNothing);
  });

  testWidgets('carries a named close control, not only tap-anywhere',
      (tester) async {
    // Tap-anywhere-to-dismiss is invisible to a screen reader and to anyone
    // who does not know the gesture, and the viewer had no other exit.
    await tester.pumpWidget(
      _wrap(const PhotoLightbox(url: 'https://example.test/photo.jpg')),
    );
    await tester.pump();

    expect(find.byTooltip('Close photo'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the image itself is labelled — by its caption when it has one',
      (tester) async {
    // Without a semanticLabel the viewer is one unnamed rectangle; the
    // caption below it is a separate node and is often absent entirely.
    await tester.pumpWidget(
      _wrap(const PhotoLightbox(
        url: 'https://example.test/photo.jpg',
        caption: 'Summit at sunrise',
      )),
    );
    await tester.pump();

    final img = tester.widget<Image>(find.byType(Image));
    expect(img.semanticLabel, 'Summit at sunrise');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('an uncaptioned image falls back to a generic label',
      (tester) async {
    await tester.pumpWidget(
      _wrap(const PhotoLightbox(url: 'https://example.test/photo.jpg')),
    );
    await tester.pump();

    final img = tester.widget<Image>(find.byType(Image));
    expect(img.semanticLabel, 'Open photo');
    await tester.pump(const Duration(seconds: 1));
  });
}
