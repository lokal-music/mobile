/// Some HTTP add-ons advertise CD resolution as "16/44.1" rather than
/// "16-bit / 44.1 kHz". Accept only explicit bit-depth/rate pairs; do not
/// interpret a bitrate or a generic lossless tier as PCM resolution.
({int bitDepth, int sampleRate})? compactAudioResolution(String? quality) {
  final input = quality?.trim() ?? '';
  final match = RegExp(
    r'(?<!\d)(16|24|32)\s*(?:-?\s*bits?)?\s*[/@]\s*'
    r'(44\.1|48|88\.2|96|176\.4|192|352\.8|384)\s*(?:k(?:hz)?)?(?!\d)',
    caseSensitive: false,
  ).firstMatch(input);
  if (match == null) return null;
  return (
    bitDepth: int.parse(match.group(1)!),
    sampleRate: (double.parse(match.group(2)!) * 1000).round(),
  );
}

/// Formats metadata advertised by a provider, not the decoded audio output.
/// Never synthesizes 44.1/48/96 kHz for a bit-depth-only response.
String catalogueQualityLabel(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return '';
  if (compactAudioResolution(text) case final pair?) {
    final rate = pair.sampleRate / 1000;
    final khz = rate == rate.roundToDouble()
        ? rate.toStringAsFixed(0)
        : rate.toStringAsFixed(1);
    return '${pair.bitDepth}-bit / $khz kHz';
  }
  final bits = RegExp(
    r'(?:^|[^0-9])(16|24|32)\s*-?\s*bits?',
    caseSensitive: false,
  ).firstMatch(text)?.group(1);
  final khz = RegExp(
    r'(?<![\d.])(\d{2,3}(?:\.\d+)?)\s*k(?:hz)?(?![a-z])',
    caseSensitive: false,
  ).firstMatch(text)?.group(1);
  if (bits != null || khz != null) {
    return [
      if (bits != null) '$bits-bit',
      if (khz != null)
        '${double.parse(khz).toStringAsFixed(khz.contains('.') ? 1 : 0)} kHz',
    ].join(' / ');
  }
  switch (text.toUpperCase()) {
    case 'HI_RES_LOSSLESS':
      return 'Hi-res lossless';
    case 'LOSSLESS':
      return 'Lossless';
    case 'HIGH':
      return 'High';
    case 'LOW':
      return 'Low';
  }
  return text.length < 42 ? text : '';
}

/// A Full Player badge is a quality *tier*, not a repetition of the
/// catalogue's bit-depth/sample-rate text. Those precise measurements remain
/// available in Song Metadata. A catalogue claim is not an audio probe.
String? catalogueStreamTierLabel({
  required String? quality,
  String? codec,
  int? bitDepth,
  int? sampleRate,
}) {
  final text = quality?.trim() ?? '';
  switch (text.toUpperCase().replaceAll('-', '_').replaceAll(' ', '_')) {
    case 'HI_RES_LOSSLESS':
      return 'HI-RES LOSSLESS';
    case 'LOSSLESS':
      return 'LOSSLESS';
    case 'HIGH':
      return 'HIGH';
    case 'LOW':
      return 'LOW';
  }

  final advertised = catalogueQualityLabel(quality);
  final bitText = RegExp(
    r'(?:^|[^\d])(16|24|32)\s*-?\s*bit',
    caseSensitive: false,
  ).firstMatch(advertised)?.group(1);
  final rateText = RegExp(
    r'(\d{2,3}(?:\.\d+)?)\s*kHz',
    caseSensitive: false,
  ).firstMatch(advertised)?.group(1);
  final bits = bitDepth ?? int.tryParse(bitText ?? '');
  final hz =
      sampleRate ??
      (rateText == null
          ? null
          : ((double.tryParse(rateText) ?? 0) * 1000).round());
  if (bits == null && hz == null) return null;

  final format = codec?.trim().toUpperCase() ?? '';
  const lossless = {
    'FLAC',
    'ALAC',
    'WAV',
    'WAVE',
    'AIFF',
    'WAVPACK',
    'APE',
    'WV',
  };
  const lossy = {'AAC', 'MP3', 'OPUS', 'VORBIS', 'OGG'};
  // A lossy file's decoded PCM width is not lossless source fidelity.
  if (lossy.contains(format)) return null;
  if ((bits ?? 0) > 16 || (hz ?? 0) > 48000) {
    return lossless.contains(format) ? 'HI-RES LOSSLESS' : 'HI-RES';
  }
  // Both CD measurements and an actual lossless codec are required to assert
  // LOSSLESS. Unknown progressive containers must not inherit the tier.
  if (lossless.contains(format) && bits != null && hz != null)
    return 'LOSSLESS';
  return null;
}

/// Exactly one Search quality badge per track. Prefer verified stream data;
/// otherwise show available provider metadata, or the requested setting when
/// the provider supplies no per-track details. The tooltip preserves provenance
/// without adding "(catalogue)" to the UI or showing a competing request chip.
({String label, String tooltip}) onlineSearchAudioBadge({
  String? verifiedQuality,
  String? requestedQuality,
  String? catalogueQuality,
  String? catalogueCodec,
  int? catalogueBitDepth,
  int? catalogueSampleRate,
}) {
  final verified = verifiedQuality?.trim() ?? '';
  if (verified.isNotEmpty) {
    return (
      label: verified,
      tooltip: 'Audio details from a resolved stream, not inferred from search metadata.',
    );
  }
  final advertised = catalogueAudioDetails(
    quality: catalogueQuality,
    codec: catalogueCodec,
    bitDepth: catalogueBitDepth,
    sampleRate: catalogueSampleRate,
  );
  if (advertised.isNotEmpty) {
    return (
      label: advertised,
      tooltip: 'Provider-advertised catalogue audio details; the actual delivered stream is verified during playback.',
    );
  }
  final requested = requestedQuality?.trim() ?? '';
  return (
    label: requested,
    tooltip: requested.isEmpty ? '' : 'Quality requested in add-on settings; the delivered stream is verified during playback.',
  );
}

// These are advertised source properties, not the actual decoder/output rate.
// Prefer explicit numerical fields over broad provider labels. Never substitute
// "24-bit / 96 kHz" merely because the catalogue says HI_RES_LOSSLESS.
String catalogueAudioDetails({
  String? quality,
  int? bitDepth,
  int? sampleRate,
  String? codec,
}) {
  final bits = bitDepth != null && bitDepth >= 8 && bitDepth <= 64
      ? bitDepth
      : null;
  final hz = sampleRate != null && sampleRate >= 8000 && sampleRate <= 768000
      ? sampleRate
      : null;
  final supplied = catalogueQualityLabel(quality);
  final bitText = bits == null ? null : '$bits-bit';
  String? rateText;
  if (hz != null) {
    final rate = hz / 1000;
    rateText =
        '${rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : rate.toStringAsFixed(1)} kHz';
  }
  final resolved = <String>[
    if (bitText != null) bitText,
    if (rateText != null) rateText,
  ];
  // A string may contain one of the measurements without the other.
  if (supplied.isNotEmpty) {
    final hasBits = RegExp(
      r'\d+\s*-?\s*bit',
      caseSensitive: false,
    ).hasMatch(supplied);
    final hasRate = RegExp(
      r'\d+(?:\.\d+)?\s*kHz',
      caseSensitive: false,
    ).hasMatch(supplied);
    if (resolved.isEmpty ||
        (bits == null && hasBits) ||
        (hz == null && hasRate)) {
      if (resolved.isEmpty) {
        resolved.add(supplied);
      } else {
        final extra = <String>[];
        if (bits == null && hasBits) {
          final match = RegExp(
            r'\d+\s*-?\s*bit',
            caseSensitive: false,
          ).firstMatch(supplied);
          if (match != null)
            extra.add(match.group(0)!.replaceAll(RegExp(r'\s+'), ''));
        }
        if (hz == null && hasRate) {
          final match = RegExp(
            r'\d+(?:\.\d+)?\s*kHz',
            caseSensitive: false,
          ).firstMatch(supplied);
          if (match != null)
            extra.add(match.group(0)!.replaceAll(RegExp(r'\s+'), ' '));
        }
        resolved.addAll(extra);
      }
    }
  }
  // Bitrate is independent of sample rate. Previously a known 48 kHz
  // decoder rate suppressed a real 192 kbps measurement, leaving misleading
  // "OPUS · 48 kHz" instead of the actual lossy quality.
  if (RegExp(
        r'\d+(?:\.\d+)?\s*kbps',
        caseSensitive: false,
      ).hasMatch(supplied) &&
      !resolved.any((part) => part.toLowerCase().contains('kbps'))) {
    resolved.add(supplied);
  }
  final format = codec?.trim().toUpperCase() ?? '';
  if (format.isNotEmpty &&
      format.length <= 12 &&
      !resolved.any((part) => part.toUpperCase() == format)) {
    return [format, ...resolved].join(' · ');
  }
  return resolved.join(' / ');
}

/// Provider-advertised numbers for the early streaming handoff. Search can
/// know the catalogue format before native audio probing has started, so keep
/// its *explicit* measurements when creating the temporary playable Song.
/// Never infer a rate/depth from a generic HI_RES/LOSSLESS quality tier.
({String fileType, String? resolution, int? bitDepth, int? sampleRate})
advertisedOnlineAudio({
  required String? codec,
  required String? quality,
  required int? bitDepth,
  required int? sampleRate,
  String fallbackFileType = 'ONLINE',
}) {
  final advertised = quality?.trim();
  final compact = compactAudioResolution(advertised);
  final bits =
      bitDepth ??
      compact?.bitDepth ??
      int.tryParse(
        RegExp(r'(?<!\d)(?:16|24|32)\s*-?\s*bits?', caseSensitive: false)
                .firstMatch(advertised ?? '')
                ?.group(0)
                ?.replaceAll(RegExp(r'[^0-9]'), '') ??
            '',
      );
  final rawRate = RegExp(
    r'(?<![\d.])(\d{2,3}(?:\.\d+)?)\s*k(?:hz)?\b',
    caseSensitive: false,
  ).firstMatch(advertised ?? '')?.group(1);
  final hz =
      sampleRate ??
      compact?.sampleRate ??
      (rawRate == null
          ? null
          : ((double.tryParse(rawRate) ?? 0) * 1000).round());
  final candidate = codec?.trim().toUpperCase() ?? '';
  const known = {
    'FLAC',
    'ALAC',
    'AAC',
    'MP3',
    'OPUS',
    'VORBIS',
    'WAV',
    'AIFF',
    'OGG',
  };
  return (
    fileType: known.contains(candidate) ? candidate : fallbackFileType,
    resolution: advertised == null || advertised.isEmpty ? null : advertised,
    bitDepth: bits != null && bits >= 8 && bits <= 64 ? bits : null,
    sampleRate: hz != null && hz >= 8000 && hz <= 768000 ? hz : null,
  );
}

/// Only a *codec*, not its containing file format, can classify audio.
/// M4A/MP4 and WebM are containers which may contain multiple lossy codecs;
/// displaying them as quality badges was incorrect.
String? verifiedAudioCodec(Object? value) {
  final raw = value?.toString().toLowerCase().trim() ?? '';
  if (raw.isEmpty || raw == 'null' || raw == 'unknown') return null;
  if (raw.contains('flac')) return 'FLAC';
  if (raw.contains('alac')) return 'ALAC';
  if (raw.contains('opus')) return 'OPUS';
  if (raw.contains('vorbis')) return 'VORBIS';
  if (raw.contains('aac') || raw.contains('mp4a')) return 'AAC';
  if (raw.contains('mp3') || raw.contains('mpeg_layer3')) return 'MP3';
  if (raw.startsWith('pcm_')) return 'WAV';
  if (raw.contains('wavpack')) return 'WAVPACK';
  return null;
}

/// Whether a verified audio codec can be retained when a library scan reports
/// only its containing file format.
bool audioCodecMatchesContainer(Object? codecValue, Object? containerValue) {
  final codec = verifiedAudioCodec(codecValue);
  final container = containerValue?.toString().toLowerCase().trim() ?? '';
  if (codec == null || container.isEmpty) return false;
  return switch (container.replaceFirst(RegExp(r'^\.'), '')) {
    'm4a' || 'mp4' || 'isomp4' => codec == 'AAC' || codec == 'ALAC',
    'mp3' || 'mpeg' => codec == 'MP3',
    'flac' => codec == 'FLAC',
    'wav' || 'wave' => codec == 'WAV',
    'ogg' || 'oga' => codec == 'OPUS' || codec == 'VORBIS',
    'opus' => codec == 'OPUS',
    'webm' => codec == 'OPUS' || codec == 'VORBIS',
    'wv' || 'wavpack' => codec == 'WAVPACK',
    _ => false,
  };
}

/// Approximate *measured file average* bitrate, not the selected download
/// option or a generic 320 kbps provider promise. A usable native probe may
/// supply bits/second directly; otherwise full file bytes / known duration
/// gives an honest rounded average. Never invent a quality tier from a
/// file extension, decoder sample width or hi-res catalogue maximum.
String? measuredLossyBitrate({
  required String? codec,
  Object? bitsPerSecond,
  int? fileBytes,
  Duration? duration,
}) {
  if (!{'AAC', 'MP3', 'OPUS', 'VORBIS'}.contains(codec)) return null;
  final bps = bitsPerSecond is num
      ? bitsPerSecond.toDouble()
      : double.tryParse(bitsPerSecond?.toString() ?? '');
  final seconds = duration?.inMilliseconds == null
      ? 0.0
      : duration!.inMilliseconds / 1000.0;
  final observed = bps != null && bps >= 16000 && bps <= 1500000
      ? bps
      : (fileBytes != null && fileBytes > 0 && seconds >= 5)
      ? fileBytes * 8 / seconds
      : null;
  if (observed == null || !observed.isFinite) return null;
  final kbps = (observed / 1000).round();
  return kbps > 0 ? '$kbps kbps' : null;
}

/// A requested Morneye setting is a helpful Search hint, not the actual
/// file's quality. In particular Qobuz/Tidal catalogue maximums cannot be
/// shown as the quality of a user-selected lower rendition.
String? morneyeSelectedQualityLabel({
  required String? configured,
  required List<dynamic> options,
}) {
  final selection = configured?.trim() ?? '';
  if (selection.isEmpty) return null;
  for (final option in options) {
    if (option is! Map || option['id']?.toString() != selection) continue;
    final label = option['label']?.toString().trim() ?? '';
    if (label.isEmpty) return null;
    return '$label (selected)';
  }
  return null;
}
