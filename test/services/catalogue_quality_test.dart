import 'package:flutter_test/flutter_test.dart';
import 'package:flick/services/catalogue_quality.dart';
import 'package:flick/features/konnekted/konnekted_discovery.dart';
import 'package:flick/features/morneye/morneye_packages.dart';
import 'package:flick/features/morneye/morneye_playback_quality.dart';
import 'package:flick/features/discovery/discovery_models.dart';
import 'package:flick/models/song.dart';
import 'package:flick/widgets/lokal/lokal_quality.dart';

void main() {
  test('verified codecs survive container-only library scans', () {
    expect(audioCodecMatchesContainer('AAC', 'm4a'), isTrue);
    expect(audioCodecMatchesContainer('ALAC', 'mp4'), isTrue);
    expect(audioCodecMatchesContainer('AAC', 'flac'), isFalse);
    expect(audioCodecMatchesContainer('M4A', 'm4a'), isFalse);
  });

  test('Tidal HIGH/LOW preference survives Atmos catalogue availability', () {
    const tiers = [
      {'id': 'DOLBY_ATMOS', 'label': 'Dolby Atmos'},
      {'id': 'HI_RES_LOSSLESS', 'label': 'HiRes FLAC'},
      {'id': 'LOSSLESS', 'label': 'Lossless'},
      {'id': 'HIGH', 'label': 'High'},
      {'id': 'LOW', 'label': 'Low'},
    ];
    expect(explicitMorneyePlaybackTier(atmosRequested: false), isNull);
    expect(explicitMorneyePlaybackTier(atmosRequested: true), 'DOLBY_ATMOS');
    expect(
      explicitMorneyePlaybackTier(atmosRequested: true, provider: 'amazon'),
      'ac4',
    );
    expect(
      explicitMorneyePlaybackTier(atmosRequested: false, provider: 'amazon'),
      isNull,
    );
    expect(
      explicitMorneyePlaybackTier(
        atmosRequested: true,
        provider: 'amazon-new',
        atmosCodec: 'eac3-joc',
      ),
      'eac3',
      reason: 'JOC-only Amazon results must not request AC-4',
    );
    expect(
      explicitMorneyePlaybackTier(
        atmosRequested: true,
        provider: 'amazon-new',
        atmosCodec: 'ac4',
      ),
      'ac4',
    );
    expect(
      explicitMorneyePlaybackTier(
        atmosRequested: true,
        provider: 'tidal-web',
        atmosCodec: 'eac3-joc',
      ),
      'DOLBY_ATMOS',
    );
    for (final quality in ['HIGH', 'LOW', 'LOSSLESS']) {
      expect(
        resolveMorneyeRequestQuality(
          forPlayback: true,
          requested: explicitMorneyePlaybackTier(atmosRequested: false),
          configured: quality,
          options: tiers,
          provider: 'tidal-web',
        ),
        quality,
      );
    }
    expect(
      resolveMorneyeRequestQuality(
        forPlayback: true,
        requested: explicitMorneyePlaybackTier(atmosRequested: true),
        configured: 'LOW',
        options: tiers,
        provider: 'tidal-web',
      ),
      'DOLBY_ATMOS',
    );
  });

  test(
    'Amazon per-track ATMOS audioQualities earns the purple catalogue badge',
    () {
      final atmos = MorneyeTrack.of({
        'id': 'amazon-atmos',
        'name': 'A genuine spatial edition',
        'artists': ['Artist'],
        'audioQualities': ['HD', 'UHD', 'ATMOS'],
      }, 'a-amazon');
      expect(atmos.atmosAvailable, isTrue);
      final alias = MorneyeTrack.of({
        'id': 'amazon-alias',
        'name': 'Another spatial edition',
        'artists': ['Artist'],
        'audio_qualities': ['UHD', 'ATMOS'],
      }, 'a-amazon');
      expect(alias.atmosAvailable, isTrue);
      final noAtmos = MorneyeTrack.of({
        'id': 'amazon-stereo',
        'name': 'No spatial option in this catalogue',
        'artists': ['Artist'],
        'audioQualities': ['HD', 'UHD', '360RA'],
        'audio_quality': 'AC-4',
      }, 'a-amazon');
      expect(
        noAtmos.atmosAvailable,
        isFalse,
        reason: 'A codec name, another spatial format, or Amazon global tier is not an Atmos badge',
      );
      final noMetadata = MorneyeTrack.of({
        'id': 'amazon-unknown',
        'name': 'Unreported',
        'artists': ['Artist'],
      }, 'a-amazon');
      expect(noMetadata.atmosAvailable, isFalse);
    },
  );

  test('Amazon Search shows the selected normal tier, never a universal AC-4 badge', () {
    const amazonOptions = [
      {'id': 'best', 'label': 'FLAC Best Available', 'kind': 'lossless'},
      {'id': 'opus', 'label': 'Opus 320kbps', 'kind': 'lossy'},
      {'id': 'eac3', 'label': 'Dolby Digital Plus', 'kind': 'spatial'},
      {'id': 'ac4', 'label': 'Dolby Atmos (AC-4)', 'kind': 'spatial'},
    ];
    expect(
      amazonRequestedPlaybackQualityLabel(
        configured: null,
        options: amazonOptions,
      ),
      'FLAC best (requested)',
    );
    expect(
      amazonRequestedPlaybackQualityLabel(
        configured: 'best',
        options: amazonOptions,
      ),
      'FLAC best (requested)',
    );
    expect(
      amazonRequestedPlaybackQualityLabel(
        configured: 'opus',
        options: amazonOptions,
      ),
      'Opus 320kbps (requested)',
    );
    for (final spatial in ['ac4', 'eac3']) {
      expect(
        amazonRequestedPlaybackQualityLabel(
          configured: spatial,
          options: amazonOptions,
        ),
        isNull,
        reason: 'A selected spatial tier is not a verified search badge',
      );
    }
    expect(
      amazonRequestedPlaybackQualityLabel(configured: null, options: const []),
      isNull,
    );
    const ordinary = DiscoveryTrack(
      id: 'amazon-search',
      title: 'Test Me',
      artist: 'Artist',
      source: DiscoverySource.morneye,
      atmosAvailable: false,
      atmosRequestable: true,
      requestedQuality: 'FLAC best (requested)',
    );
    expect(
      ordinary.atmosAvailable,
      isFalse,
      reason:
          'Addon-wide AC-4 support is not per-track Atmos catalogue metadata',
    );
    expect(ordinary.atmosRequestable, isTrue);
    expect(ordinary.requestAtmos().atmosRequested, isTrue);
    final badge = onlineSearchAudioBadge(
      requestedQuality: ordinary.requestedQuality,
    );
    expect(badge.label, 'FLAC best (requested)');
    expect(badge.tooltip, contains('requested'));
    expect(badge.label, isNot(contains('AC-4')));
  });

  test(
    'confirmed Amazon JOC codec survives selection, artwork and Atmos request',
    () {
      const track = DiscoveryTrack(
        id: 'joc',
        title: 'Song',
        artist: 'Artist',
        source: DiscoverySource.morneye,
        addonId: 'amazon-new',
        atmosAvailable: true,
        atmosRequestable: true,
        atmosCodec: 'eac3-joc',
      );
      expect(track.requestAtmos().atmosCodec, 'eac3-joc');
      expect(
        track.withArtwork('https://example.com/cover.jpg').atmosCodec,
        'eac3-joc',
      );
      expect(
        explicitMorneyePlaybackTier(
          atmosRequested: track.requestAtmos().atmosRequested,
          provider: 'amazon-new',
          atmosCodec: track.requestAtmos().atmosCodec,
        ),
        'eac3',
      );
    },
  );

  test('WEBM/M4A containers are never treated as playback quality codecs', () {
    expect(verifiedAudioCodec('m4a'), isNull);
    expect(verifiedAudioCodec('webm'), isNull);
    expect(verifiedAudioCodec('isomp4'), isNull);
    expect(verifiedAudioCodec('aac'), 'AAC');
    expect(verifiedAudioCodec('opus'), 'OPUS');
    expect(verifiedAudioCodec('flac'), 'FLAC');
    expect(verifiedAudioCodec('alac'), 'ALAC');
  });

  test('Tidal HIGH/LOW and Amazon Opus use actual compressed-file bitrate', () {
    expect(
      measuredLossyBitrate(codec: 'AAC', bitsPerSecond: 320000),
      '320 kbps',
    );
    expect(measuredLossyBitrate(codec: 'AAC', bitsPerSecond: 96000), '96 kbps');
    expect(
      measuredLossyBitrate(codec: 'OPUS', bitsPerSecond: 192000),
      '192 kbps',
    );
    expect(
      measuredLossyBitrate(
        codec: 'OPUS',
        fileBytes: 2400000,
        duration: const Duration(seconds: 120),
      ),
      '160 kbps',
    );
    expect(measuredLossyBitrate(codec: 'AAC'), isNull);
    expect(
      measuredLossyBitrate(codec: 'FLAC', bitsPerSecond: 600000),
      isNull,
      reason: 'Compressed FLAC average bitrate is not a lossy tier',
    );
    expect(
      LokalQualityTier.of(
        const Song(
          id: 'tidal-high',
          title: 'T',
          artist: 'A',
          fileType: 'AAC',
          resolution: '320 kbps',
          duration: Duration(seconds: 120),
        ),
      ),
      LokalQualityTier.high,
    );
    expect(
      LokalQualityTier.of(
        const Song(
          id: 'tidal-low',
          title: 'T',
          artist: 'A',
          fileType: 'AAC',
          resolution: '96 kbps',
          duration: Duration(seconds: 120),
        ),
      ),
      LokalQualityTier.low,
    );
    expect(
      LokalQualityTier.of(
        const Song(
          id: 'yt-opus',
          title: 'T',
          artist: 'A',
          fileType: 'OPUS',
          resolution: '160 kbps',
          duration: Duration(seconds: 120),
        ),
      ),
      LokalQualityTier.high,
    );
  });

  test('Search names selected tiers as requests and does not fake catalogue maxima', () {
    const qobuz = [
      {'id': 'HI_RES_LOSSLESS', 'label': '24-Bit Max'},
      {'id': 'LOSSLESS', 'label': 'Lossless'},
    ];
    const tidal = [
      {'id': 'HI_RES_LOSSLESS', 'label': 'HiRes FLAC'},
      {'id': 'HIGH', 'label': 'High'},
      {'id': 'LOW', 'label': 'Low'},
    ];
    const amazon = [
      {'id': 'best', 'label': 'FLAC Best Available'},
      {'id': 'opus', 'label': 'Opus 320kbps'},
    ];
    expect(
      morneyeSelectedQualityLabel(configured: 'LOSSLESS', options: qobuz),
      'Lossless (selected)',
    );
    expect(
      morneyeSelectedQualityLabel(configured: 'HIGH', options: tidal),
      'High (selected)',
    );
    expect(
      morneyeSelectedQualityLabel(configured: 'LOW', options: tidal),
      'Low (selected)',
    );
    expect(
      morneyeSelectedQualityLabel(configured: 'opus', options: amazon),
      'Opus 320kbps (selected)',
    );
    expect(
      morneyeSelectedQualityLabel(configured: null, options: tidal),
      isNull,
    );
  });

  test('early HTTP and Morneye streams retain only advertised quality', () {
    final qobuz = advertisedOnlineAudio(
      codec: 'FLAC',
      quality: '24bit/96kHz',
      bitDepth: null,
      sampleRate: null,
    );
    expect(qobuz.fileType, 'FLAC');
    expect(qobuz.bitDepth, 24);
    expect(qobuz.sampleRate, 96000);
    expect(qobuz.resolution, '24bit/96kHz');
    final playing = Song(
      id: 'qobuz',
      title: 'Track',
      artist: 'Artist',
      duration: Duration.zero,
      fileType: qobuz.fileType,
      resolution: qobuz.resolution,
      bitDepth: qobuz.bitDepth,
      sampleRate: qobuz.sampleRate,
      filePath: 'lokal-progressive://audio/id',
      sourcePackage: 'konnekted.progressive',
    );
    expect(
      LokalQualityTier.of(playing),
      LokalQualityTier.hiRes,
      reason: 'Search catalogue measurements survive the player handoff',
    );

    final cd = advertisedOnlineAudio(
      codec: 'FLAC',
      quality: '16bit/44.1kHz',
      bitDepth: null,
      sampleRate: null,
    );
    expect(cd.sampleRate, 44100);
    final generic = advertisedOnlineAudio(
      codec: 'FLAC',
      quality: 'HI_RES_LOSSLESS',
      bitDepth: null,
      sampleRate: null,
    );
    expect(generic.bitDepth, isNull);
    expect(
      generic.sampleRate,
      isNull,
      reason: 'A broad tier cannot prove the actual sample rate',
    );
    final opus = advertisedOnlineAudio(
      codec: 'OPUS',
      quality: '320kbps',
      bitDepth: null,
      sampleRate: null,
    );
    expect(opus.fileType, 'OPUS');
    expect(opus.resolution, '320kbps');
  });

  test(
    'Amazon search never labels configured FLAC preference as track quality',
    () {
      expect(morneyeAdvertisedQuality(null), isNull);
      expect(morneyeAdvertisedQuality(''), isNull);
      expect(morneyeAdvertisedQuality('  '), isNull);
      expect(morneyeAdvertisedQuality('24bit/96kHz'), '24bit/96kHz');
      expect(
        catalogueAudioDetails(quality: morneyeAdvertisedQuality(null)),
        isEmpty,
      );
    },
  );

  test(
    'Amazon/Tidal Search uses actual cached Opus/AAC, not FLAC catalogue max',
    () {
      const opus = Song(
        id: 'amazon-opus',
        title: 'Track',
        artist: 'Artist',
        duration: Duration(seconds: 190),
        fileType: 'OPUS',
        resolution: '192 kbps',
        sampleRate: 48000,
      );
      final actual = morneyeSearchAudioDetails(verifiedPlayback: opus);
      expect(
        catalogueAudioDetails(
          codec: actual.codec,
          bitDepth: actual.bitDepth,
          sampleRate: actual.sampleRate,
          quality: opus.resolution,
        ),
        'OPUS · 48 kHz · 192 kbps',
      );
      expect(actual.codec, 'OPUS');
      expect(actual.bitDepth, isNull);
    },
  );

  test(
    'Amazon reuses probed Full Player quality for repeat Search results',
    () {
      const played = Song(
        id: 'amazon-downloaded',
        title: 'Song',
        artist: 'Artist',
        duration: Duration(minutes: 3),
        fileType: 'FLAC',
        bitDepth: 24,
        sampleRate: 96000,
      );
      final details = morneyeSearchAudioDetails(verifiedPlayback: played);
      expect(details.codec, 'FLAC');
      expect(details.bitDepth, 24);
      expect(details.sampleRate, 96000);
      expect(
        catalogueAudioDetails(
          codec: details.codec,
          bitDepth: details.bitDepth,
          sampleRate: details.sampleRate,
        ),
        'FLAC · 24-bit · 96 kHz',
      );

      final advertised = morneyeSearchAudioDetails(
        codec: 'AAC',
        bitDepth: null,
        sampleRate: 48000,
        verifiedPlayback: played,
      );
      expect(
        advertised.codec,
        'AAC',
        reason: 'A fresh source observation takes precedence over cache',
      );
      expect(advertised.sampleRate, 48000);
      expect(
        morneyeSearchAudioDetails().codec,
        isNull,
        reason: 'An unplayed Amazon track cannot inherit Best FLAC',
      );
      expect(morneyeSearchAudioDetails().sampleRate, isNull);
    },
  );

  test('catalogue quality includes only supplied bit depth and rate', () {
    expect(catalogueQualityLabel('24bit/96kHz'), '24-bit / 96 kHz');
    expect(catalogueQualityLabel('16bit/44.1kHz'), '16-bit / 44.1 kHz');
    expect(catalogueQualityLabel('24bit'), '24-bit');
    expect(catalogueQualityLabel('HI_RES_LOSSLESS'), 'Hi-res lossless');
    expect(catalogueQualityLabel('1411kbps'), '1411kbps');
    expect(catalogueAudioDetails(quality: '1411kbps'), '1411kbps');
    expect(catalogueAudioDetails(quality: '320kbps'), '320kbps');
    expect(catalogueQualityLabel(null), '');
    expect(catalogueQualityLabel(''), '');
  });

  test('all catalogue formats display genuine bit depth and sample rate', () {
    expect(
      catalogueAudioDetails(
        quality: 'HI_RES_LOSSLESS',
        bitDepth: 24,
        sampleRate: 96000,
      ),
      '24-bit / 96 kHz',
    );
    expect(
      catalogueAudioDetails(
        quality: 'LOSSLESS',
        bitDepth: 16,
        sampleRate: 44100,
      ),
      '16-bit / 44.1 kHz',
    );
    expect(
      catalogueAudioDetails(quality: '24bit/96kHz', bitDepth: 24),
      '24-bit / 96 kHz',
    );
    expect(catalogueAudioDetails(quality: 'LOSSLESS'), 'Lossless');
    expect(
      catalogueAudioDetails(codec: 'FLAC', bitDepth: 24, sampleRate: 192000),
      'FLAC · 24-bit · 192 kHz',
    );
    expect(catalogueAudioDetails(), isEmpty);
  });

  test('Mornye normalizes Hz and fractional kHz from provider metadata', () {
    MorneyeTrack track(Map<String, Object?> details) => MorneyeTrack.of({
      'id': 't1',
      'name': 'Song',
      'artists': ['Artist'],
      ...details,
    }, 'a-tidal');

    expect(track({'bit_depth': 24, 'sampling_rate': 44.1}).bitDepth, 24);
    expect(track({'bit_depth': 24, 'sampling_rate': 44.1}).sampleRate, 44100);
    expect(track({'bitDepth': 16, 'sampleRate': 48000}).sampleRate, 48000);
    expect(track({'sample_rate': '96 kHz'}).sampleRate, 96000);
    expect(track({'sampling_rate': 88200}).sampleRate, 88200);
    expect(track({}).sampleRate, isNull);
    expect(track({}).bitDepth, isNull);
  });

  test('Atmos requests remain explicit and use a separate source identity', () {
    const stereo = DiscoveryTrack(
      id: '123',
      title: 'Track',
      artist: 'Artist',
      source: DiscoverySource.morneye,
      addonId: 'tidal',
      atmosAvailable: true,
      catalogueBitDepth: 24,
      catalogueSampleRate: 96000,
      catalogueQuality: 'HI_RES_LOSSLESS',
    );
    final atmos = stereo.requestAtmos();
    expect(stereo.atmosRequested, isFalse);
    expect(atmos.atmosRequested, isTrue);
    expect(atmos.atmosAvailable, isTrue);
    expect(atmos.catalogueBitDepth, 24);
    expect(atmos.catalogueSampleRate, 96000);
    expect(atmos.key, isNot(stereo.key));
    expect(atmos.atmosDownload, isFalse);
    final download = stereo.requestAtmos(downloadOnly: true);
    expect(download.atmosRequested, isTrue);
    expect(download.atmosDownload, isTrue);
    expect(download.key, atmos.key, reason: 'Both request the same JOC source');
    expect(
      atmos.withArtwork('https://example.test/cover.jpg').atmosRequested,
      isTrue,
    );
    expect(
      download.withArtwork('https://example.test/cover.jpg').atmosDownload,
      isTrue,
    );
  });

  test('Tidal Atmos transport errors do not imply unavailable tier', () {
    const error =
        'Quality DOLBY_ATMOS failed without confirmation that the '
        'requested tier is unavailable | API attempt 1: TimeoutException '
        'after 0:00:30.000000';
    expect(tidalAtmosTransportFailure(error), isTrue);
    expect(tidalAtmosTransportMessage(error), contains('timed out'));
    expect(
      tidalAtmosTransportFailure('DOLBY_ATMOS API: HTTP 502 for /dl/tid'),
      isTrue,
    );
    expect(
      tidalAtmosTransportMessage('HTTP 502 for /dl/tid'),
      contains('HTTP 502'),
    );
    expect(tidalAtmosTransportFailure('QUALITY_UNAVAILABLE'), isFalse);
    const api502 =
        'Quality DOLBY_ATMOS failed without confirmation that '
        'the requested tier is unavailable | DOLBY_ATMOS API attempt 1: '
        'HTTP 502 for /dl/tid; DOLBY_ATMOS API attempt 2: HTTP 502 for /dl/tid';
    expect(tidalAtmosErrorMentionsMode(api502), isTrue);
    expect(tidalAtmosTransportFailure(api502), isTrue);
    expect(
      tidalAtmosTransportMessage(api502),
      'Tidal Atmos unavailable: download service HTTP 502. '
      'No Atmos stream was received. Retry later.',
    );
    expect(tidalAtmosErrorMentionsMode('HTTP 502 from Qobuz'), isFalse);
    expect(tidalAtmosTierUnavailable('QUALITY_UNAVAILABLE'), isTrue);
    expect(
      tidalAtmosTierUnavailable(
        'TIDAL API did not report EAC3_JOC for this track',
      ),
      isTrue,
    );
    expect(tidalAtmosTierUnavailable(api502), isFalse);
    expect(
      tidalAtmosTransportMessage(
        'DOLBY_ATMOS API attempt 1: TimeoutException after 0:00:30',
      ),
      contains('timed out'),
    );
  });

  test(
    'Tidal search displays requested quality, not the catalogue maximum',
    () {
      const tiers = [
        {'id': 'HI_RES_LOSSLESS', 'label': 'HiRes FLAC'},
        {'id': 'LOSSLESS', 'label': 'Lossless'},
        {'id': 'HIGH', 'label': 'High'},
        {'id': 'LOW', 'label': 'Low'},
        {'id': 'DOLBY_ATMOS', 'label': 'Dolby Atmos'},
      ];
      expect(
        tidalRequestedQualityLabel(configured: 'HIGH', options: tiers),
        'High (requested)',
      );
      expect(
        tidalRequestedQualityLabel(configured: 'LOW', options: tiers),
        'Low (requested)',
      );
      expect(
        tidalRequestedQualityLabel(configured: 'LOSSLESS', options: tiers),
        'Lossless (requested)',
      );
      expect(
        tidalRequestedQualityLabel(
          configured: 'HI_RES_LOSSLESS',
          options: tiers,
        ),
        'HiRes FLAC (requested)',
      );
      expect(
        tidalRequestedQualityLabel(configured: null, options: tiers),
        'HiRes FLAC (requested)',
        reason: 'The first advertised tier is the download fallback',
      );
      expect(
        tidalRequestedQualityLabel(configured: 'DOLBY_ATMOS', options: tiers),
        'Dolby Atmos (requested)',
        reason: 'A selected tier is a request, not proof of a catalogue edition or decoder',
      );
      expect(
        tidalRequestedQualityLabel(configured: 'LOW', options: []),
        isNull,
      );
      const requested = DiscoveryTrack(
        id: 'tidal-7',
        title: 'Track',
        artist: 'Artist',
        source: DiscoverySource.morneye,
        requestedQuality: 'High (requested)',
        catalogueQuality: null,
      );
      expect(
        requested.withArtwork('https://example.test/art.jpg').requestedQuality,
        'High (requested)',
      );
      expect(requested.requestAtmos().requestedQuality, 'High (requested)');
      expect(
        catalogueAudioDetails(quality: requested.catalogueQuality),
        isEmpty,
        reason: 'Requested quality must not masquerade as decoded audio',
      );
    },
  );

  test('Qobuz HTTP full-player badge is a tier rather than a resolution', () {
    expect(
      catalogueStreamTierLabel(quality: '24-bit / 44.1 kHz', codec: 'ONLINE'),
      'HI-RES',
      reason: 'Unknown progressive codec must not assert lossless',
    );
    expect(
      catalogueStreamTierLabel(quality: '24bit/44.1kHz', codec: 'FLAC'),
      'HI-RES LOSSLESS',
    );
    expect(
      catalogueStreamTierLabel(quality: '16-bit / 44.1 kHz', codec: 'FLAC'),
      'LOSSLESS',
    );
    expect(
      catalogueStreamTierLabel(quality: '24bit/96kHz', codec: 'AAC'),
      isNull,
      reason: 'Lossy PCM measurements do not prove hi-res fidelity',
    );
    expect(
      catalogueStreamTierLabel(quality: 'FLAC', codec: 'ONLINE'),
      isNull,
      reason: 'A codec name alone cannot imply sample precision',
    );
    expect(
      catalogueStreamTierLabel(quality: 'HI_RES_LOSSLESS', codec: 'ONLINE'),
      'HI-RES LOSSLESS',
      reason: 'Provider advertised its catalogue tier',
    );
  });

  test('Tidal Morneye Search retains advertised quality before playback', () {
    final tidal = MorneyeTrack.of({
      'id': 'tidal-123',
      'name': 'Example',
      'artists': ['Artist'],
      'audio_quality': 'HI_RES_LOSSLESS',
      'codec': 'FLAC',
      'bit_depth': 24,
      'sampling_rate': 44.1,
    }, 'a-tidal');
    final firstSearch = onlineSearchAudioBadge(
      catalogueQuality: tidal.quality,
      catalogueCodec: tidal.codec,
      catalogueBitDepth: tidal.bitDepth,
      catalogueSampleRate: tidal.sampleRate,
      requestedQuality: 'HiRes FLAC (requested)',
    );
    expect(firstSearch.label, 'FLAC · 24-bit · 44.1 kHz');
    expect(firstSearch.tooltip, contains('catalogue'));
    expect(firstSearch.label, isNot(contains('catalogue')));
    expect(firstSearch.label, isNot(contains('requested')));

    final low = onlineSearchAudioBadge(
      catalogueQuality: tidal.quality,
      catalogueCodec: tidal.codec,
      catalogueBitDepth: tidal.bitDepth,
      catalogueSampleRate: tidal.sampleRate,
      requestedQuality: 'Low (requested)',
    );
    expect(
      low.label,
      'FLAC · 24-bit · 44.1 kHz',
      reason:
          'Show only available per-track metadata; a different requested '
          'tier must not introduce a second chip or be mistaken for playback',
    );
    expect(low.tooltip, contains('catalogue'));
    final onlyRequest = onlineSearchAudioBadge(
      requestedQuality: 'High (requested)',
    );
    expect(
      onlyRequest.label,
      'High (requested)',
      reason: 'Fallback to the selected tier if catalogue metadata is absent',
    );
    expect(onlyRequest.tooltip, contains('requested'));
    final played = onlineSearchAudioBadge(
      verifiedQuality: 'AAC · 256 kbps',
      catalogueQuality: tidal.quality,
      requestedQuality: 'High (requested)',
    );
    expect(played.label, 'AAC · 256 kbps');
    expect(played.label, isNot(contains('catalogue')));
    expect(played.label, isNot(contains('requested')));
  });
}
