import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mvc_app/modules/cars/vehicles_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// postgrest decodes any response larger than this on a background isolate
/// (postgrest_builder.dart), and that isolate never completes under the test
/// binding's fake async — the screen would sit on its spinner forever. The
/// canned payload has to stay below the ceiling.
const int _isolateDecodeThreshold = 10000;

/// Rows shaped like our `vehicle_listings` table, kept terse for the ceiling
/// above. No images, so the cards fall back to the local placeholder rather
/// than reaching for the network.
String _rows(int count) => jsonEncode([
      for (var i = 1; i <= count; i++)
        {
          'id': 'i$i',
          'stock': 'S$i',
          'year': 2020,
          'make': i.isEven ? 'Honda' : 'Toyota',
          'model': 'M$i',
          'status': 'Pre-Owned',
          'mileage': 1000 * i,
          'price': 10000 + i,
          'created_at': '2025-01-01',
          'updated_at': '2025-01-01',
        }
    ]);

Future<void> _initSupabase(int listingCount) async {
  final rows = _rows(listingCount);
  // Checked here because an oversized fixture hangs these tests rather than
  // failing them, which is a miserable thing to debug.
  expect(rows.length, lessThan(_isolateDecodeThreshold));

  await Supabase.initialize(
    url: 'https://test.supabase.co',
    anonKey: 'test-anon-key',
    debug: false,
    authOptions: const FlutterAuthClientOptions(
      localStorage: EmptyLocalStorage(),
      autoRefreshToken: false,
    ),
    // postgrest reads `response.request` while parsing, so it has to be
    // carried back on every canned response.
    httpClient: MockClient((request) async {
      final body =
          request.url.path.endsWith('/vehicle_listings') ? rows : '[]';
      return http.Response(
        body,
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
}

/// The footer spinner runs for as long as pages remain, so the tree never goes
/// quiescent and `pumpAndSettle` would time out. A fixed handful of frames is
/// enough to flush the load future and finish any scroll settling.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpScreen(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: CarsVehiclesScreen()));
  await _settle(tester);
}

Finder get _listScrollable => find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );

ScrollPosition _listPosition(WidgetTester tester) =>
    tester.state<ScrollableState>(_listScrollable).position;

Future<void> _scrollDown(WidgetTester tester, {double by = -900}) async {
  await tester.drag(find.byType(ListView), Offset(0, by));
  await _settle(tester);
}

/// Drags towards the end of the list until [target] has been built, which is
/// also what drives the screen to reveal further pages.
Future<void> _scrollUntil(
  WidgetTester tester,
  Finder target, {
  int maxDrags = 40,
}) async {
  for (var i = 0; i < maxDrags && target.evaluate().isEmpty; i++) {
    await _scrollDown(tester);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // No LIFTKIT_KEY: the dealer feed reports itself unconfigured and is
    // skipped, leaving the community rows as the whole result set.
    dotenv.testLoad(fileInput: '');
  });

  tearDown(() async {
    await Supabase.instance.dispose();
  });

  testWidgets('holds back the rest of the results until the user scrolls',
      (tester) async {
    await _initSupabase(45);
    await _pumpScreen(tester);

    expect(find.text('2020 Toyota M1'), findsOneWidget);

    // A windowed list can only scroll as far as the page it has revealed.
    final firstPageExtent = _listPosition(tester).maxScrollExtent;
    expect(firstPageExtent, greaterThan(0));
    expect(find.text('Showing all 45 vehicles'), findsNothing);

    await _scrollDown(tester, by: -firstPageExtent);
    expect(
      _listPosition(tester).maxScrollExtent,
      greaterThan(firstPageExtent),
      reason: 'reaching the end of page 1 should have revealed page 2',
    );
  });

  testWidgets('keeps revealing pages until every match has been shown',
      (tester) async {
    await _initSupabase(45);
    await _pumpScreen(tester);

    await _scrollUntil(tester, find.text('Showing all 45 vehicles'));

    // The end-of-list marker is only built once nothing is left to reveal.
    expect(find.text('Showing all 45 vehicles'), findsOneWidget);
    expect(find.text('2020 Toyota M45'), findsOneWidget);
  });

  testWidgets('does not page a result set that fits on one page',
      (tester) async {
    await _initSupabase(8);
    await _pumpScreen(tester);

    await _scrollUntil(tester, find.text('Showing all 8 vehicles'));
    expect(find.text('Showing all 8 vehicles'), findsOneWidget);
  });

  testWidgets('searching starts again from the first page at the top',
      (tester) async {
    await _initSupabase(45);
    await _pumpScreen(tester);

    await _scrollDown(tester);
    await _scrollDown(tester);
    expect(_listPosition(tester).pixels, greaterThan(0));

    // 22 Hondas — still more than one page, so the end marker must not be
    // reachable until the user has scrolled through the new results too.
    await tester.enterText(find.byType(TextField), 'Honda');
    await _settle(tester);

    expect(_listPosition(tester).pixels, 0,
        reason: 'a new search should return the user to the top');
    expect(find.text('2020 Honda M2'), findsOneWidget);
    expect(find.text('Showing all 22 vehicles'), findsNothing);

    await _scrollUntil(tester, find.text('Showing all 22 vehicles'));
    expect(find.text('Showing all 22 vehicles'), findsOneWidget);
  });
}
