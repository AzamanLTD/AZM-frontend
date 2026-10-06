import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/services/oracle_rates_client.dart';

void main() {
  group('SingleFlight (§9 oracle-rate dedupe law)', () {
    test('concurrent callers share ONE run', () async {
      final flight = SingleFlight();
      var runs = 0;
      Future<int> slow() async {
        runs++;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return runs;
      }

      final a = flight.run('k', slow);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final b = flight.run('k', slow);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final c = flight.run('k', slow);

      final results = await Future.wait([a, b, c]);
      expect(runs, 1, reason: 'three concurrent callers must not start three requests');
      expect(results, everyElement(1));
      expect(flight.hasInFlight, isFalse);
    });

    test('a caller arriving AFTER the flight settles starts a fresh run', () async {
      final flight = SingleFlight();
      var runs = 0;
      Future<int> run() async {
        runs++;
        return runs;
      }

      expect(await flight.run('k', run), 1);
      expect(await flight.run('k', run), 2, reason: 'no caching — settled requests do not replay');
      expect(runs, 2);
    });

    test('different keys do not coalesce with each other', () async {
      final flight = SingleFlight();
      var runs = 0;
      Future<int> run() async {
        final mine = ++runs;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return mine;
      }

      final a = flight.run('oracle', run);
      final b = flight.run('susu', run);
      expect(await Future.wait([a, b]), [1, 2]);
      expect(runs, 2, reason: 'only same-key calls share a request');
    });

    test('an error settles the flight and reaches every sharer', () async {
      final flight = SingleFlight();
      var runs = 0;
      Future<int> boom() async {
        runs++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        throw StateError('endpoint down');
      }

      final a = flight.run('k', boom);
      final b = flight.run('k', boom);
      await expectLater(a, throwsStateError);
      await expectLater(b, throwsStateError);
      expect(runs, 1);
      expect(flight.hasInFlight, isFalse, reason: 'a failed flight must not wedge the key forever');
    });

    test('a failed flight does not poison the next caller', () async {
      final flight = SingleFlight();
      Future<int> boom() async => throw StateError('down');
      Future<int> fine() async => 42;

      await expectLater(flight.run('k', boom), throwsStateError);
      expect(await flight.run('k', fine), 42, reason: 'post-failure callers start a clean new run');
    });
  });
}
