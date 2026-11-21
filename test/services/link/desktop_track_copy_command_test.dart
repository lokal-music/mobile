import 'package:flick/services/link/desktop_track_copy_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rejects empty, oversized and invalid track ID lists', () {
    expect(() => validateDesktopTrackCopyIds([]), throwsFormatException);
    expect(
      () => validateDesktopTrackCopyIds(
        List.generate(maxDesktopTracksToCopy + 1, (index) => '$index'),
      ),
      throwsFormatException,
    );
    for (final ids in [
      ['track', 'track'],
      [' track'],
      ['track\u0000id'],
      [42],
      [List.filled(513, 'x').join()],
    ]) {
      expect(() => validateDesktopTrackCopyIds(ids), throwsFormatException);
    }
  });

  test(
    'copies selected originals sequentially and reports partial failures',
    () async {
      final active = <String>{};
      final order = <String>[];
      final progress = <DesktopTrackCopyProgress>[];
      final result = await copyDesktopCatalogueTracks(
        requestedIds: ['one', 'present', 'missing', 'broken', 'two'],
        loadCatalogue: () async => [
          {'id': 'one', 'title': 'First'},
          {'id': 'present', 'title': 'Existing'},
          {'id': 'broken', 'title': 'Unreadable'},
          {'id': 'two', 'title': 'Second'},
          {'id': 'not-requested', 'title': 'Ignore'},
        ],
        isAlreadyPresent: (id) async => id == 'present',
        copyTrack: (track) async {
          final id = track['id']! as String;
          expect(active, isEmpty);
          active.add(id);
          order.add(id);
          await Future<void>.delayed(Duration.zero);
          active.remove(id);
          if (id == 'broken') {
            throw StateError('Storage permission was revoked.');
          }
        },
        onProgress: progress.add,
      );

      expect(order, ['one', 'broken', 'two']);
      expect(result.requested, 5);
      expect(result.copied, 2);
      expect(result.alreadyPresent, 1);
      expect(progress.map((item) => item.processed), [1, 2, 3, 4, 5]);
      expect(progress.last.total, 5);
      expect(result.failures, hasLength(2));
      expect(result.failures.first, 'Unavailable desktop song');
      expect(
        result.failures.last,
        contains('Unreadable: Storage permission was revoked.'),
      );
    },
  );

  test('validates before loading desktop catalogue', () async {
    var loaded = false;
    await expectLater(
      copyDesktopCatalogueTracks(
        requestedIds: [],
        loadCatalogue: () async {
          loaded = true;
          return [];
        },
        isAlreadyPresent: (_) async => false,
        copyTrack: (_) async {},
      ),
      throwsFormatException,
    );
    expect(loaded, isFalse);
  });
}
