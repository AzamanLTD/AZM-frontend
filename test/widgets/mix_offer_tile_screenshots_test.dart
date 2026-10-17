// =============================================================================
// MIX OFFER TILE — visual evidence suite (2026-10-16, PR #156).
//
// Captures PNG previews of the product-gallery Mix tile at the three
// reference phone widths (320 / 360 / 390dp) in BOTH themes, covering the
// three store-logo states the review must see:
//
//   • a REAL logo — genuine bytes rendered through the exact production
//     path (the evidence cache manager serves local fixture files into
//     CachedNetworkImage; the sandbox blocks the sqlite-backed default)
//   • a MISSING logo — the storefront glyph + name, never an item image
//   • an IMAGE-ERROR — dead URLs degrade to glyphs, both image and logo
//
// Each capture asserts the tile contract on screen first, so the file
// doubles as a visual regression guard: square product image, distinct
// lower panel, exact verified GHS price, item + store rendered together,
// responsive near-square tile at every width.
//
// Captures land in .screenshots/ (untracked, ephemeral):
//   mix_tiles_320_light.png / mix_tiles_320_dark.png  … 390 …
// =============================================================================

import 'dart:io';
import 'dart:typed_data';

import 'package:azaman/marketplace/mix/mix_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/widgets/marketplace/discovery/mix_offer_card.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
// flutter_cache_manager re-exports package:file's File — the one FileInfo
// carries. LocalFileSystem() builds real on-disk files of that type.
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
// package:file's File is the concrete type flutter_cache_manager's
// FileInfo carries; dart:io File does not implement it.
import 'package:file/file.dart' as pfile;
import 'package:file/local.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:ui' show ImageByteFormat;

const _rootKey = Key('shot-root');

const _productUrl = 'https://evidence.local/jollof.png';
const _product2Url = 'https://evidence.local/kenkey.png';
const _logoUrl = 'https://evidence.local/biz-logo.png';
const _deadUrl = 'https://evidence.local/dead.png';

/// Local-file cache manager: REAL bytes for known URLs, a hard 404-style
/// failure for unknown ones (the honest image-error path). This is the
/// only piece of scaffolding — the widget tree is the production card.
class _EvidenceCacheManager implements BaseCacheManager {
  final Map<String, pfile.File> files;
  _EvidenceCacheManager(this.files);

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    final f = files[url];
    if (f == null) {
      throw Exception('404: $url (evidence image-error state)');
    }
    yield FileInfo(
      f,
      FileSource.Cache,
      DateTime.now().add(const Duration(days: 1)),
      url,
    );
  }

  @override
  Future<pfile.File> getSingleFile(String url,
          {String? key, Map<String, String>? headers}) async =>
      files[url]!;

  @override
  Future<FileInfo> downloadFile(String url,
      {String? key, Map<String, String>? authHeaders, bool force = false}) {
    throw UnimplementedError('evidence manager serves cache files only');
  }

  @override
  Future<FileInfo?> getFileFromCache(String key, {bool ignoreMemCache = false}) async => null;

  @override
  Future<FileInfo?> getFileFromMemory(String key) async => null;

  @override
  Future<pfile.File> putFile(String url, Uint8List fileBytes,
      {String? key,
      String? eTag,
      Duration maxAge = const Duration(days: 30),
      String fileExtension = 'file'}) {
    throw UnimplementedError('evidence manager is read-only');
  }

  @override
  Future<pfile.File> putFileStream(String url, Stream<List<int>> source,
      {String? key,
      String? eTag,
      Duration maxAge = const Duration(days: 30),
      String fileExtension = 'file'}) {
    throw UnimplementedError('evidence manager is read-only');
  }

  @override
  Stream<FileInfo> getFile(String url,
      {String? key, Map<String, String>? headers}) async* {
    final f = await getSingleFile(url);
    yield FileInfo(f, FileSource.Cache,
        DateTime.now().add(const Duration(days: 1)), url);
  }

  @override
  Future<void> removeFile(String key) async {}

  @override
  Future<void> emptyCache() async {}

  @override
  Future<void> dispose() async {}
}

bool _fontsLoaded = false;
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  final inter = await File('assets/fonts/Inter-Variable.ttf').readAsBytes();
  final interLoader = FontLoader('Inter')
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(inter).buffer)),
    );
  await interLoader.load();
  final regular =
      await File('assets/fonts/ComicNeue-Regular.ttf').readAsBytes();
  final bold = await File('assets/fonts/ComicNeue-Bold.ttf').readAsBytes();
  final comicLoader = FontLoader('ComicNeue')
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(regular).buffer)),
    )
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(bold).buffer)),
    );
  await comicLoader.load();
  _fontsLoaded = true;
}

Future<ThemeProvider> _seedTheme(AzamanTheme theme) async {
  SharedPreferences.setMockInitialValues({
    'azaman_theme': theme == AzamanTheme.dark ? 1 : 0,
  });
  final p = ThemeProvider();
  int guard = 0;
  while (!p.isLoaded && guard++ < 100) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(p.isLoaded, isTrue);
  return p;
}

/// toImage/file IO need REAL async — capture inside `tester.runAsync`.
Future<void> _capture(WidgetTester tester, String name) async {
  var ok = false;
  await tester.runAsync(() async {
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(_rootKey));
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = (await image.toByteData(format: ImageByteFormat.png))!;
    Directory('.screenshots').createSync(recursive: true);
    File('.screenshots/$name.png').writeAsBytesSync(data.buffer.asUint8List());
    ok = true;
  });
  expect(ok, isTrue, reason: 'capture $name wrote a PNG');
}

MixOffer _fullPayloadOffer() => const MixOffer(
      productId: 'p-live',
      businessId: 'bp-1',
      bizId: 'BIZ-1',
      businessName: "Auntie Adjoa's Kitchen",
      businessCategory: 'FOOD_BEVERAGE',
      businessLogoUrl: _logoUrl,
      name: 'Jollof Rice',
      imageUrls: [_productUrl],
      price: MixOfferPrice.fixedGhs('25.00'),
      isAvailable: true,
      capabilities: MixOfferCapabilities(payableIn: ['USDC']),
    );

MixOffer _missingLogoOffer() => const MixOffer(
      productId: 'p-kenkey',
      businessId: 'bp-2',
      bizId: 'BIZ-2',
      businessName: 'Osu Kenkey Bar',
      businessCategory: 'FOOD_BEVERAGE',
      name: 'Banku & Tilapia',
      imageUrls: [_product2Url],
      price: MixOfferPrice.fixedGhs('48.50'),
      capabilities: MixOfferCapabilities(payableIn: ['USDC']),
    );

MixOffer _imageErrorOffer() => const MixOffer(
      productId: 'p-dead',
      businessId: 'bp-3',
      bizId: 'BIZ-3',
      businessName: 'Makola Fabrics',
      businessCategory: 'RETAIL_GOODS',
      businessLogoUrl: _deadUrl,
      name: 'Kente Cloth (2 yards)',
      imageUrls: [_deadUrl],
      price: MixOfferPrice.fixedGhs('120.00'),
      isAvailable: false,
      capabilities: MixOfferCapabilities(payableIn: ['USDC']),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final cacheManager = _EvidenceCacheManager({
    _productUrl: const LocalFileSystem().file('test/fixtures/mix_evidence/product.png'),
    _product2Url:
        const LocalFileSystem().file('test/fixtures/mix_evidence/product2.png'),
    _logoUrl: const LocalFileSystem().file('test/fixtures/mix_evidence/logo.png'),
  });

  for (final width in [320.0, 360.0, 390.0]) {
    for (final theme in AzamanTheme.values) {
      final mode = theme == AzamanTheme.dark ? 'dark' : 'light';
      final name = 'mix_tiles_${width.toInt()}_$mode';

      testWidgets('gallery tile preview ${width.toInt()}dp — $mode',
          (tester) async {
        tester.view.physicalSize = Size(width, 780);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // FontLoader/engine decode + the theme load loop need REAL async.
        final tp = (await tester.runAsync(() => _seedTheme(theme)))!;
        await tester.runAsync(_loadFonts);

        final opened = <MixOffer>[];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [themeProvider.overrideWith((ref) => tp)],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeProvider.getThemeData(tp.currentTheme),
              home: Scaffold(
                body: RepaintBoundary(
                  key: _rootKey,
                  child: ListView(
                    padding:
                        const EdgeInsets.fromLTRB(AzSpace.lg, AzSpace.md, AzSpace.lg, 0),
                    children: [
                      // Pair row 1 — the feed's real composition:
                      // [real logo tile | missing-logo tile]
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: MixOfferCard(
                              offer: _fullPayloadOffer(),
                              onOpenStore: opened.add,
                              cacheManager: cacheManager,
                            ),
                          ),
                          const SizedBox(width: AzSpace.sm),
                          Expanded(
                            child: MixOfferCard(
                              offer: _missingLogoOffer(),
                              onOpenStore: opened.add,
                              cacheManager: cacheManager,
                            ),
                          ),
                        ],
                      ),
                      // Pair row 2 — the error state:
                      // [image-error tile | honest absence]
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: MixOfferCard(
                              offer: _imageErrorOffer(),
                              onOpenStore: opened.add,
                              cacheManager: cacheManager,
                            ),
                          ),
                          const SizedBox(width: AzSpace.sm),
                          Expanded(
                            child: MixOfferCard(
                              offer: const MixOffer(
                                productId: 'p-unpriced',
                                businessId: 'bp-4',
                                bizId: 'BIZ-4',
                                businessName: 'Ada’s Sews',
                                businessCategory: 'RETAIL_GOODS',
                                name: 'Custom Smock',
                                imageUrls: [_productUrl],
                                price: MixOfferPrice.unknown(),
                                capabilities:
                                    MixOfferCapabilities(payableIn: []),
                              ),
                              onOpenStore: opened.add,
                              cacheManager: cacheManager,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        // Real bytes need REAL async to decode through the cache manager:
        // the decode future completes on the engine's real loop, and its
        // continuation microtasks run on the following pumps. Fixed pumps
        // (NOT pumpAndSettle — placeholder shimmers animate forever).
        // Real decode needs INTERLEAVED real-async windows and pumps:
        // each window advances the engine's decode loop, each pump
        // delivers the fake-zone microtasks and ticks the fade-in so the
        // image stream moves to its next stage. Wait until EVERY real
        // image has decoded AND faded in — tile 1's logo leaves the
        // placeholder (fallback count 4 → 3), and tiles 2 and 4 mount
        // their product rasters. (NOT pumpAndSettle — placeholder
        // shimmers animate forever.)
        final tiles = find.byType(MixOfferCard);
        var settled = false;
        for (var i = 0; i < 25 && !settled; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 80)));
          await tester.pump(const Duration(milliseconds: 120));
          settled = find
                      .byKey(const ValueKey('mix_store_logo_fallback'))
                      .evaluate()
                      .length ==
                  3 &&
              // Tile 1: BOTH rasters (product + logo — two RawImages).
              tester
                      .widgetList<RawImage>(find.descendant(
                          of: tiles.at(0), matching: find.byType(RawImage)))
                      .length >=
                  2 &&
              // Tile 2: its product raster (logo is the glyph here).
              tester
                      .widgetList<RawImage>(find.descendant(
                          of: tiles.at(1), matching: find.byType(RawImage)))
                      .isNotEmpty &&
              // Tile 4: its product raster (no logo, dead-image tile 3
              // has none at all).
              tester
                      .widgetList<RawImage>(find.descendant(
                          of: tiles.at(3), matching: find.byType(RawImage)))
                      .isNotEmpty;
        }
        expect(settled, isTrue,
            reason: 'all real images decoded and mounted their rasters');
        // Finish any in-flight fade-in (MotionTokens.control is 180ms):
        // the raster mounts at fade START, but the capture must show it
        // fully painted. Pump well past the longest fade the card runs.
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 400));
        }

        // ── The tile contract, asserted on screen before the capture ──

        // Gallery format: the pair fills the row, tiles are near-square.
        expect(tiles, findsNWidgets(4));
        final firstPair = tester
            .getRect(tiles.at(0))
            .translate(0, tester.getRect(tiles.at(1)).top);
        expect(firstPair.width,
            closeTo((width - 2 * AzSpace.lg - AzSpace.sm) / 2, 1),
            reason: 'each tile is a responsive half-feed cell');
        final a = tester.getSize(tiles.at(0));
        expect(a.height, greaterThan(a.width * 0.9),
            reason: 'near-square: tall-product tile, not a squat row card');

        // The product image is a square filling the tile width.
        final imageA = tester.getSize(
            find.descendant(of: tiles.at(0), matching: find.byType(CachedNetworkImage)).first);
        expect(imageA.height, closeTo(imageA.width, 1));

        // Real bytes actually decoded and mounted — the raster is there,
        // not a placeholder skeleton.
        expect(
            find.descendant(of: tiles.at(0), matching: find.byType(RawImage)),
            findsAtLeastNWidgets(2),
            reason: 'tile 1 renders decoded fixture bytes: product raster '
                'plus the real-logo raster');

        // The distinct lower panel sits below it.
        expect(find.byKey(const ValueKey('mix_offer_panel')), findsNWidgets(4));

        // Exact verified GHS price strings — never floated.
        expect(find.text('GH₵\u00A025.00'), findsOneWidget);
        expect(find.text('GH₵\u00A048.50'), findsOneWidget);
        expect(find.text('GH₵\u00A01,200.00'), findsNothing);

        // MISSING price renders the honest state, not a zero.
        expect(find.text('Price unavailable'), findsOneWidget);

        // Item + offering store rendered together (the Mix invariant).
        expect(find.text("Auntie Adjoa's Kitchen"), findsOneWidget);
        expect(find.text('Osu Kenkey Bar'), findsOneWidget);

        // REAL logo state: the logo slot is an image, not a glyph.
        final realLogo = find.descendant(
            of: find.byKey(const ValueKey('mix_store_logo')),
            matching: find.byType(CachedNetworkImage));
        // CachedNetworkImage nests an inner instance — assert presence,
        // not count.
        expect(realLogo, findsAtLeastNWidgets(1),
            reason: 'the genuine logo URL is mounted for byte rendering');

        // MISSING + FAILED logo states: exactly three glyph fallbacks —
        // the missing-logo tile, the dead-URL tile, and the fourth tile
        // (no logo URL). Tile 1's REAL logo left the placeholder state.
        expect(find.byKey(const ValueKey('mix_store_logo_fallback')),
            findsNWidgets(3));

        // Availability only when the payload said so.
        expect(find.byKey(const ValueKey('mix_chip_Unavailable')), findsOneWidget);

        await _capture(tester, name);
      });
    }
  }
}
