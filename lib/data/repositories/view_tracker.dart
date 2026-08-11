import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ViewTargetType { recipe, plan, post }

/// Counts views without turning a read-heavy app into a write-heavy one.
///
/// Views outnumber every other event by two orders of magnitude, and Firestore
/// writes cost roughly three times what reads do. Done naively — one write per
/// screen open — 10,000 daily actives viewing 30 items a day is 300,000 writes
/// a day, and that bill only ever grows. Four rules keep it small:
///
///   1. **A view is a detail screen held for 2+ seconds.** Not a feed
///      impression. Counting impressions is what kills the budget, and nobody
///      needs the number.
///   2. **Deduplicate on the device.** One person opening the same recipe eight
///      times today is one view. This alone removes most of the writes.
///   3. **Batch.** Buffer and flush every 30 seconds or on backgrounding — one
///      write carrying ten views instead of ten writes.
///   4. **Never let the client touch the counter.** These are append-only
///      events; a Function aggregates them into `stats.views` and
///      `viewers/{uid}`, then deletes them. Vanity numbers get faked the moment
///      they're writable.
class ViewTracker {
  ViewTracker({
    required SharedPreferences prefs,
    FirebaseFirestore? firestore,
    this.flushInterval = const Duration(seconds: 30),
    this.dwellThreshold = const Duration(seconds: 2),
  }) : _prefs = prefs,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final SharedPreferences _prefs;
  final FirebaseFirestore _firestore;
  final Duration flushInterval;
  final Duration dwellThreshold;

  static const _seenKey = 'viewTracker.seenToday';
  static const _seenDayKey = 'viewTracker.seenDay';
  static const _maxBufferedEvents = 50;

  final List<Map<String, dynamic>> _buffer = [];
  Timer? _flushTimer;
  Set<String>? _seenToday;

  /// Today's already-counted targets, reset at local midnight so a genuine
  /// return visit tomorrow counts again.
  Set<String> get _seen {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (_seenToday == null || _prefs.getString(_seenDayKey) != today) {
      final stored = _prefs.getString(_seenDayKey) == today
          ? _prefs.getStringList(_seenKey) ?? const <String>[]
          : const <String>[];
      _seenToday = stored.toSet();
      if (_prefs.getString(_seenDayKey) != today) {
        unawaited(_prefs.setString(_seenDayKey, today));
        unawaited(_prefs.setStringList(_seenKey, const []));
      }
    }
    return _seenToday!;
  }

  /// Call when a detail screen opens. Returns a disposer to call when it
  /// closes — the view only counts if the screen outlived [dwellThreshold],
  /// which filters out the back-button-immediately case.
  void Function() trackScreen({
    required ViewTargetType type,
    required String targetId,
    required String viewerUid,
    required bool isGuest,
  }) {
    final openedAt = DateTime.now();
    var disposed = false;

    return () {
      if (disposed) return;
      disposed = true;
      if (DateTime.now().difference(openedAt) < dwellThreshold) return;
      record(
        type: type,
        targetId: targetId,
        viewerUid: viewerUid,
        isGuest: isGuest,
      );
    };
  }

  void record({
    required ViewTargetType type,
    required String targetId,
    required String viewerUid,
    required bool isGuest,
  }) {
    final key = '${type.name}:$targetId';
    if (!_seen.add(key)) return;
    unawaited(_prefs.setStringList(_seenKey, _seen.toList()));

    _buffer.add({
      'uid': viewerUid,
      'targetType': type.name,
      'targetId': targetId,
      // Guests raise the count but never appear in anyone's viewer list. Same
      // for anyone who's turned on incognito browsing — the Function checks
      // their profile rather than trusting a client flag.
      'anonymous': isGuest,
      'at': FieldValue.serverTimestamp(),
    });

    if (_buffer.length >= _maxBufferedEvents) {
      unawaited(flush());
    } else {
      _flushTimer ??= Timer(flushInterval, () => unawaited(flush()));
    }
  }

  /// Writes the buffer as one batch. Call on app backgrounding too — a person
  /// who reads five recipes and swipes the app away should still be counted.
  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_buffer.isEmpty) return;

    final pending = List<Map<String, dynamic>>.from(_buffer);
    _buffer.clear();

    try {
      final batch = _firestore.batch();
      final events = _firestore.collection('viewEvents');
      for (final event in pending) {
        batch.set(events.doc(), event);
      }
      await batch.commit();
    } catch (_) {
      // Views are not worth retrying forever or surfacing to anyone. Drop them
      // and move on; the counter being slightly low beats a growing queue.
    }
  }

  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }
}
