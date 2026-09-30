import 'dart:math' as math;
import 'dart:typed_data';

/// A compact amplitude envelope of a recording, normalized to 0..1.
class Waveform {
  Waveform(this.envelope, this.duration);

  /// Peak amplitude per bucket, evenly spaced over [duration].
  final List<double> envelope;

  /// Length of the recording in seconds.
  final double duration;

  /// Envelope value at [t] seconds, linearly interpolated.
  double at(double t) =>
      duration <= 0 ? 0 : sampleEnvelope(envelope, t / duration);

  /// Times (seconds) of the most prominent local peaks, in time order. These
  /// are the "hints" the UI lifts off the waveform while listening.
  List<double> peakTimes({int max = 28}) {
    final n = envelope.length;
    if (n < 3) return const [];
    final window = math.max(1, n ~/ 60);
    final peaks = <int>[];
    for (var i = 0; i < n; i++) {
      final v = envelope[i];
      if (v < 0.15) continue;
      var isPeak = true;
      for (var j = math.max(0, i - window); j <= math.min(n - 1, i + window); j++) {
        if (envelope[j] > v || (envelope[j] == v && j < i)) {
          isPeak = false;
          break;
        }
      }
      if (isPeak) peaks.add(i);
    }
    peaks.sort((a, b) => envelope[b].compareTo(envelope[a]));
    final top = peaks.take(max).toList()..sort();
    return [for (final i in top) i / (n - 1) * duration];
  }

  /// Builds an envelope from WAV bytes (16-bit PCM or 32-bit float). Returns
  /// null if the bytes aren't a WAV this understands.
  static Waveform? fromWavBytes(Uint8List bytes, {int buckets = 800}) {
    if (bytes.length < 44) return null;
    final data = ByteData.sublistView(bytes);
    String tag(int at) => String.fromCharCodes(bytes.sublist(at, at + 4));
    if (tag(0) != 'RIFF' || tag(8) != 'WAVE') return null;

    int? format, channels, sampleRate, bits, dataStart, dataLength;
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final id = tag(offset);
      var size = data.getUint32(offset + 4, Endian.little);
      final body = offset + 8;
      if (id == 'fmt ' && body + 16 <= bytes.length) {
        format = data.getUint16(body, Endian.little);
        channels = data.getUint16(body + 2, Endian.little);
        sampleRate = data.getUint32(body + 4, Endian.little);
        bits = data.getUint16(body + 14, Endian.little);
      } else if (id == 'data') {
        // Streamed WAVs sometimes leave the size as 0 or 0xFFFFFFFF.
        if (size == 0 || body + size > bytes.length) size = bytes.length - body;
        dataStart = body;
        dataLength = size;
        break;
      }
      offset = body + size + (size & 1);
    }
    if (format == null || dataStart == null || channels == null || channels == 0) {
      return null;
    }
    final isFloat = format == 3 || (format == 0xFFFE && bits == 32);
    if (!(bits == 16 || (isFloat && bits == 32))) return null;

    final bytesPerSample = bits! ~/ 8;
    final frameSize = bytesPerSample * channels;
    final frames = dataLength! ~/ frameSize;
    if (frames == 0 || sampleRate == null || sampleRate == 0) return null;

    double sampleAt(int frame) {
      final at = dataStart! + frame * frameSize;
      return isFloat
          ? data.getFloat32(at, Endian.little)
          : data.getInt16(at, Endian.little) / 32768.0;
    }

    final count = math.min(buckets, frames);
    final envelope = List<double>.filled(count, 0);
    // Scan at most ~256 samples per bucket; plenty for a visual envelope.
    final framesPerBucket = frames / count;
    final stride = math.max(1, framesPerBucket ~/ 256);
    for (var b = 0; b < count; b++) {
      final from = (b * framesPerBucket).floor();
      final to = math.min(frames, ((b + 1) * framesPerBucket).floor());
      var peak = 0.0;
      for (var f = from; f < to; f += stride) {
        final v = sampleAt(f).abs();
        if (v > peak) peak = v;
      }
      envelope[b] = peak;
    }
    return Waveform(normalizeEnvelope(envelope), frames / sampleRate);
  }
}

/// Scales an envelope so its loudest point is 1, with a gentle curve so quiet
/// passages stay visible.
List<double> normalizeEnvelope(List<double> values) {
  final peak = values.fold<double>(0, math.max);
  if (peak < 1e-4) return List<double>.filled(values.length, 0);
  return [for (final v in values) math.pow(v / peak, 0.8).toDouble()];
}

/// Linearly interpolated envelope value at [fraction] (0..1) of its length.
double sampleEnvelope(List<double> envelope, double fraction) {
  if (envelope.isEmpty) return 0;
  if (envelope.length == 1) return envelope.first;
  final pos = fraction.clamp(0.0, 1.0) * (envelope.length - 1);
  final i = pos.floor();
  final j = math.min(i + 1, envelope.length - 1);
  return envelope[i] + (envelope[j] - envelope[i]) * (pos - i);
}
