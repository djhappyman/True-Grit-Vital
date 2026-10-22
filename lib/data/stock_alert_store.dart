part of 'record_store.dart';

/// Schema 26 adds the opt-in stock-alert preference and one durable native
/// episode per configured container's current low condition. The preference
/// is off when the row is absent, so an upgrade never enables an alert.
const stockAlertSchemaV26 = [
  'CREATE TABLE stock_notice_config(id INTEGER PRIMARY KEY CHECK(id=1),enabled INTEGER NOT NULL CHECK(enabled IN (0,1)),revision INTEGER NOT NULL CHECK(revision>0)) STRICT',
  'CREATE TABLE stock_notice_episode(container TEXT PRIMARY KEY,episode TEXT NOT NULL UNIQUE,person TEXT NOT NULL,item TEXT NOT NULL,notified INTEGER NOT NULL DEFAULT 0 CHECK(notified IN (0,1)),opened_at INTEGER NOT NULL,generation TEXT NOT NULL,FOREIGN KEY(container,person) REFERENCES stock_container(id,person) ON DELETE CASCADE) STRICT',
  'CREATE INDEX stock_notice_episode_owner ON stock_notice_episode(person,item,container)',
  'CREATE TABLE stock_notice_request(token TEXT PRIMARY KEY,episode TEXT NOT NULL,container TEXT,person TEXT,item TEXT,snapshot TEXT,state TEXT NOT NULL,active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0,1)),cancel_ack INTEGER NOT NULL DEFAULT 0 CHECK(cancel_ack IN (0,1)),fingerprint TEXT,reason TEXT,intent_revision INTEGER NOT NULL) STRICT',
  'CREATE INDEX stock_notice_request_work ON stock_notice_request(active,state,token)',
];

Future<void> _migrateStockAlertsV26(_Database db) async {
  for (final sql in stockAlertSchemaV26) {
    await db.customStatement(sql);
  }
}

/// The saved opt-in. Revision zero means no row exists, which is off.
final class StockAlertPreference {
  const StockAlertPreference({required this.enabled, required this.revision});
  final bool enabled;
  final int revision;
}

final class _StockNoticePreparation {
  _StockNoticePreparation({
    required this.selected,
    required this.attention,
    required this.obsolete,
    required this.complete,
    required this.exclusions,
    required this.enabled,
  });
  final List<StockNoticeReminder> selected, attention;
  final List<String> obsolete;
  final bool complete;
  final List<ReminderExclusion> exclusions;
  final bool enabled;
}

extension StockAlertRecordStore on RecordStore {
  Future<Map<String, Object?>> _stockAlertConfig() async {
    final rows = await _rows(
      'SELECT enabled,revision FROM stock_notice_config WHERE id=1',
    );
    return rows.isEmpty
        ? const {'enabled': 0, 'revision': 0}
        : Map<String, Object?>.from(rows.single);
  }

  StockAlertPreference _stockAlertPreference(Map<String, Object?> row) =>
      StockAlertPreference(
        enabled: row['enabled'] == 1,
        revision: row['revision'] as int,
      );

  Future<StockAlertPreference> stockAlertPreference() async =>
      _stockAlertPreference(await _stockAlertConfig());

  Stream<StockAlertPreference> watchStockAlertPreference() =>
      _watch(stockAlertPreference);

  /// Global opt-out is effective immediately: every live native token is
  /// retired and every episode ends. Re-enabling may open one new episode for a
  /// currently known low container.
  Future<void> _cancelStockNotices() async {
    await _db.customStatement(
      "UPDATE stock_notice_request SET active=0,state='pending',reason='cancelled' WHERE active=1",
    );
    await _db.customStatement('DELETE FROM stock_notice_episode');
  }

  Future<StockAlertPreference> setStockAlerts({
    required String commandId,
    required bool enabled,
    required int expectedRevision,
  }) async {
    _requireWritable();
    final result = await _command(
      commandId,
      ['stock_alerts', enabled, expectedRevision],
      () async {
        final current = await _stockAlertConfig();
        if (current['revision'] != expectedRevision) {
          throw const CommandConflict('stock_alert_revision');
        }
        await _db.customStatement(
          'INSERT INTO stock_notice_config(id,enabled,revision) VALUES (1,?,1) ON CONFLICT(id) DO UPDATE SET enabled=excluded.enabled,revision=revision+1',
          [enabled ? 1 : 0],
        );
        if (!enabled) await _cancelStockNotices();
        final updated = await _stockAlertConfig();
        return {
          'enabled': updated['enabled'] == 1,
          'revision': updated['revision'] as int,
        };
      },
    );
    return StockAlertPreference(
      enabled: result['enabled'] == true,
      revision: result['revision'] as int,
    );
  }

  /// The in-app notice treats a configured unknown or aggregate-limited
  /// balance as attention. The native lane accepts only a measured balance, so
  /// it can never fabricate a low quantity.
  StockNoticeState? _stockNativeCondition(Map<String, Object?> row) {
    if (row['balance_status'] != 'known') return null;
    final balance = _storedPair(row, 'numerator', 'denominator');
    if (balance == null) {
      throw const FormatException('known_stock_without_balance');
    }
    final threshold = _storedPair(row, 'threshold_n', 'threshold_d');
    if (row['refill'] == 1 && balance <= ExactAmount.zero) {
      return StockNoticeState.refill;
    }
    return threshold != null && balance <= threshold
        ? StockNoticeState.low
        : null;
  }

  Map<String, Object?> _stockNoticeJson(StockNoticeReminder r) => {
    'token': r.requestToken,
    'taken': r.takenToken,
    'snooze': r.snoozeToken,
    'skip': r.skipToken,
    'generation': r.generation,
    'namespace': r.namespace,
    'container': r.containerId,
    'person': r.personId,
    'item': r.itemId,
    'item_name': r.itemName,
    'label': r.label,
    'unit': r.unit,
    'condition': r.condition.name,
    'balance_n': r.balance?.numerator.toString(),
    'balance_d': r.balance?.denominator.toString(),
    'threshold_n': r.threshold?.numerator.toString(),
    'threshold_d': r.threshold?.denominator.toString(),
    'refill': r.refillEnabled,
    'deadline': r.deadlineMilliseconds,
    'opened': r.opened,
  };

  ExactAmount? _stockNoticePair(Map<String, dynamic> m, String n, String d) {
    final numerator = m[n] as String?, denominator = m[d] as String?;
    if ((numerator == null) != (denominator == null)) {
      throw const FormatException('stock_notice_pair');
    }
    return numerator == null
        ? null
        : ExactAmount.fromStorage(numerator, denominator!);
  }

  StockNoticeReminder _stockNoticeRead(Map<String, Object?> row) {
    final m = jsonDecode(row['snapshot'] as String) as Map<String, dynamic>;
    return StockNoticeReminder(
      requestToken: m['token'] as String,
      takenToken: m['taken'] as String,
      snoozeToken: m['snooze'] as String,
      skipToken: m['skip'] as String,
      generation: m['generation'] as String,
      namespace: m['namespace'] as String,
      containerId: m['container'] as String,
      personId: m['person'] as String,
      itemId: m['item'] as String,
      itemName: m['item_name'] as String,
      label: m['label'] as String,
      unit: m['unit'] as String,
      condition: StockNoticeState.values.byName(m['condition'] as String),
      balance: _stockNoticePair(m, 'balance_n', 'balance_d'),
      threshold: _stockNoticePair(m, 'threshold_n', 'threshold_d'),
      refillEnabled: m['refill'] == true,
      deadlineMilliseconds: m['deadline'] as int,
      intentRevision: row['intent_revision'] as int,
      repairState: ReminderRepairState.values.byName(row['state'] as String),
      reason: row['reason'] as String?,
      adapterFingerprint: row['fingerprint'] as String?,
      opened: m['opened'] == true,
    );
  }

  Future<void> _endStockEpisode(String container) async {
    await _db.customStatement(
      "UPDATE stock_notice_request SET active=0,state='pending',reason='cancelled' WHERE container=? AND active=1",
      [container],
    );
    await _db.customStatement(
      'DELETE FROM stock_notice_episode WHERE container=?',
      [container],
    );
  }

  Future<void> _insertStockNotice({
    required Map<String, Object?> container,
    required Map<String, Object?> episode,
    required StockNoticeState condition,
    required DateTime now,
  }) async {
    final deadline = now
        .toUtc()
        .add(const Duration(seconds: 60))
        .millisecondsSinceEpoch;
    if (deadline <= now.toUtc().millisecondsSinceEpoch) {
      throw const FormatException('stock_notice_deadline');
    }
    final request = StockNoticeReminder(
      requestToken: newCommandId(),
      // Unused opaque action tokens keep the native request identity complete.
      // No stock notice ever exposes or accepts Taken, Snooze or Skip.
      takenToken: newCommandId(),
      snoozeToken: newCommandId(),
      skipToken: newCommandId(),
      generation: generation,
      namespace: episode['namespace'] as String,
      containerId: container['id'] as String,
      personId: container['person'] as String,
      itemId: container['item'] as String,
      itemName: container['item_name'] as String,
      label: container['label'] as String,
      unit: container['unit'] as String,
      condition: condition,
      balance: _storedPair(container, 'numerator', 'denominator'),
      threshold: _storedPair(container, 'threshold_n', 'threshold_d'),
      refillEnabled: container['refill'] == 1,
      deadlineMilliseconds: deadline,
      intentRevision: 1,
      repairState: ReminderRepairState.pending,
    );
    await _db.customStatement(
      "INSERT INTO stock_notice_request(token,episode,container,person,item,snapshot,state,intent_revision) VALUES (?,?,?,?,?,?,'pending',1)",
      [
        request.requestToken,
        episode['episode'],
        request.containerId,
        request.personId,
        request.itemId,
        jsonEncode(_stockNoticeJson(request)),
      ],
    );
    await _db.customStatement(
      'UPDATE stock_notice_episode SET notified=1 WHERE container=?',
      [request.containerId],
    );
  }

  Future<bool> _stockNoticeStillLive(StockNoticeReminder r) async {
    if (r.generation != generation) return false;
    final episodes = await _rows(
      'SELECT episode FROM stock_notice_episode WHERE container=?',
      [r.containerId],
    );
    if (episodes.isEmpty) return false;
    final requests = await _rows(
      'SELECT episode FROM stock_notice_request WHERE token=?',
      [r.requestToken],
    );
    if (requests.isEmpty ||
        requests.single['episode'] != episodes.single['episode']) {
      return false;
    }
    final container = await _rows(
      'SELECT c.*,i.name AS item_name,o.archived,o.reminders_stopped FROM stock_container c JOIN item i ON i.id=c.item AND i.person=c.person JOIN person o ON o.id=c.person WHERE c.id=? AND c.person=?',
      [r.containerId, r.personId],
    );
    if (container.isEmpty) return false;
    final row = container.single;
    return row['notice_active'] == 1 &&
        row['archived'] == 0 &&
        row['reminders_stopped'] == 0 &&
        _stockNativeCondition(row) != null;
  }

  Future<_StockNoticePreparation> _prepareStockNotices(
    DateTime now,
    String namespace,
  ) async {
    final config = await _stockAlertConfig();
    if (config['enabled'] != 1) {
      await _cancelStockNotices();
      final obsoleteRows = await _rows(
        'SELECT token FROM stock_notice_request WHERE active=0 AND cancel_ack=0 ORDER BY token LIMIT 257',
      );
      return _StockNoticePreparation(
        selected: const [],
        attention: const [],
        obsolete: obsoleteRows
            .take(256)
            .map((r) => r['token'] as String)
            .toList(),
        complete: obsoleteRows.length <= 256,
        exclusions: const [],
        enabled: false,
      );
    }
    var complete = true;
    final exclusions = <ReminderExclusion>[];
    final containers = await _rows(
      'SELECT c.*,i.name AS item_name,o.archived,o.reminders_stopped FROM stock_container c JOIN item i ON i.id=c.item AND i.person=c.person JOIN person o ON o.id=c.person WHERE c.notice_active=1 AND (c.refill=1 OR c.threshold_n IS NOT NULL) ORDER BY c.person,c.item,c.id LIMIT 1001',
    );
    if (containers.length > 1000) {
      complete = false;
      exclusions.add(
        const ReminderExclusion(
          scope: 'stock:notices',
          reason: 'work_limit',
          count: 1,
        ),
      );
    }
    final scoped = containers.take(1000).toList();
    final episodeByContainer = {
      for (final row in await _rows('SELECT * FROM stock_notice_episode'))
        row['container'] as String: row,
    };
    String requestKey(String container, String episode) =>
        '$container\u0000$episode';
    final requestKeys = {
      for (final row in await _rows(
        'SELECT container,episode FROM stock_notice_request',
      ))
        requestKey(row['container'] as String, row['episode'] as String),
    };
    final live = <String>{};
    for (final container in scoped) {
      final id = container['id'] as String;
      final condition =
          container['archived'] == 0 && container['reminders_stopped'] == 0
          ? _stockNativeCondition(container)
          : null;
      if (condition == null) {
        await _endStockEpisode(id);
        episodeByContainer.remove(id);
        continue;
      }
      live.add(id);
      var episode = episodeByContainer[id];
      if (episode == null) {
        episode = {
          'container': id,
          'episode': newCommandId(),
          'namespace': namespace,
        };
        await _db.customStatement(
          'INSERT INTO stock_notice_episode(container,episode,person,item,notified,opened_at,generation) VALUES (?,?,?,?,0,?,?)',
          [
            id,
            episode['episode'],
            container['person'],
            container['item'],
            DateTime.now().toUtc().microsecondsSinceEpoch,
            generation,
          ],
        );
        episodeByContainer[id] = episode;
      } else {
        episode = {...episode, 'namespace': namespace};
        episodeByContainer[id] = episode;
      }
      if (!requestKeys.contains(requestKey(id, episode['episode'] as String))) {
        await _insertStockNotice(
          container: container,
          episode: episode,
          condition: condition,
          now: now,
        );
        requestKeys.add(requestKey(id, episode['episode'] as String));
      }
    }
    // Only a complete inventory read can prove that an episode's container is
    // gone. A bounded, incomplete read leaves other episodes untouched.
    if (containers.length <= 1000) {
      for (final id in episodeByContainer.keys.toList()) {
        if (!live.contains(id)) {
          await _endStockEpisode(id);
          episodeByContainer.remove(id);
        }
      }
    }
    final activeRows = await _rows(
      'SELECT * FROM stock_notice_request WHERE active=1 AND snapshot IS NOT NULL ORDER BY token LIMIT 1001',
    );
    if (activeRows.length > 1000) {
      complete = false;
      exclusions.add(
        const ReminderExclusion(
          scope: 'stock:notices',
          reason: 'work_limit',
          count: 1,
        ),
      );
    }
    final liveRows = {for (final row in scoped) row['id'] as String: row};
    final liveEpisodes = {
      for (final entry in episodeByContainer.entries)
        entry.key: entry.value['episode'] as String,
    };
    final all = <StockNoticeReminder>[];
    for (final row in activeRows.take(1000)) {
      final request = _stockNoticeRead(row);
      final container = liveRows[request.containerId];
      // An incomplete inventory read cannot prove this request wrong. Keep it
      // in the snapshot rather than cancelling an unexamined native notice.
      if (container == null && containers.length > 1000) {
        all.add(request);
        continue;
      }
      final condition = container == null
          ? null
          : _stockNativeCondition(container);
      // The request belongs to exactly this episode, owner and known state.
      // Any mismatch retires it without ever minting a replacement.
      if (request.namespace != namespace ||
          container == null ||
          container['archived'] != 0 ||
          container['reminders_stopped'] != 0 ||
          condition == null ||
          liveEpisodes[request.containerId] != row['episode']) {
        await _db.customStatement(
          "UPDATE stock_notice_request SET active=0,state='pending',reason='cancelled' WHERE token=?",
          [request.requestToken],
        );
        continue;
      }
      // Keep the displayed exact balance current, but never change the token or
      // the one-episode decision.
      final updated = request.copyWith(
        itemName: container['item_name'] as String,
        label: container['label'] as String,
        unit: container['unit'] as String,
        condition: condition,
        balance: _storedPair(container, 'numerator', 'denominator'),
        threshold: _storedPair(container, 'threshold_n', 'threshold_d'),
        refillEnabled: container['refill'] == 1,
      );
      final encoded = jsonEncode(_stockNoticeJson(updated));
      if (encoded != row['snapshot']) {
        await _db.customStatement(
          'UPDATE stock_notice_request SET snapshot=? WHERE token=?',
          [encoded, request.requestToken],
        );
      }
      all.add(updated);
    }
    final allocation = allocateStockNotices(all);
    if (allocation.excluded.isNotEmpty) complete = false;
    for (final excluded in allocation.excluded) {
      await _db.customStatement(
        "UPDATE stock_notice_request SET state='capacity',reason='capacity' WHERE token=?",
        [excluded.requestToken],
      );
    }
    // A request that waited behind capacity or a blocked capability carries a
    // stale absolute deadline. Refresh that same token when it finally gets a
    // slot so a deferred notice is not silently expired by preparation.
    final selected = <StockNoticeReminder>[];
    for (final request in allocation.selected) {
      if (!request.projectedUtc.isAfter(now) &&
          [
            ReminderRepairState.pending,
            ReminderRepairState.failed,
            ReminderRepairState.unknown,
            ReminderRepairState.capacity,
          ].contains(request.repairState)) {
        final refreshed = request.copyWith(
          deadlineMilliseconds: now
              .toUtc()
              .add(const Duration(seconds: 60))
              .millisecondsSinceEpoch,
        );
        await _db.customStatement(
          'UPDATE stock_notice_request SET snapshot=? WHERE token=?',
          [jsonEncode(_stockNoticeJson(refreshed)), request.requestToken],
        );
        selected.add(refreshed);
      } else {
        selected.add(request);
      }
    }
    // A settled token from an ended episode can be pruned once the adapter has
    // acknowledged its cancellation. Active episodes keep their single row as
    // the durable no-rearm fence.
    await _db.customStatement(
      "DELETE FROM stock_notice_request WHERE rowid IN (SELECT r.rowid FROM stock_notice_request r WHERE r.active=0 AND r.cancel_ack=1 AND NOT EXISTS(SELECT 1 FROM stock_notice_episode e WHERE e.episode=r.episode) ORDER BY r.token LIMIT 256)",
    );
    final obsoleteRows = await _rows(
      'SELECT token FROM stock_notice_request WHERE active=0 AND cancel_ack=0 ORDER BY token LIMIT 257',
    );
    if (obsoleteRows.length > 256) complete = false;
    final attention = <StockNoticeReminder>[
      for (final request in allocation.excluded)
        request.copyWith(
          repairState: ReminderRepairState.capacity,
          reason: 'capacity',
        ),
    ];
    return _StockNoticePreparation(
      selected: selected,
      attention: attention,
      obsolete: obsoleteRows
          .take(256)
          .map((r) => r['token'] as String)
          .toList(),
      complete: complete,
      exclusions: [
        ...exclusions,
        for (final request in allocation.excluded)
          ReminderExclusion(
            scope: 'stock:${request.containerId}',
            reason: 'capacity',
            count: 1,
          ),
      ],
      enabled: true,
    );
  }

  /// Captures a native Open envelope for a stock notice. It returns review
  /// context only; no administration, stock movement or plan change occurs.
  Future<StockNoticeOpen?> captureStockNoticeOpen({
    required String envelopeId,
    required String namespace,
    required String requestToken,
    required String actionToken,
    required ReminderActionKind action,
  }) async {
    _requireWritable();
    if ([
      envelopeId,
      namespace,
      requestToken,
      actionToken,
    ].any((s) => s.isEmpty || s.length > 128)) {
      throw const CommandConflict('reminder_envelope');
    }
    if (action != ReminderActionKind.open || actionToken != requestToken) {
      return null;
    }
    return _reminderTransaction(() async {
      _requireWritable();
      final config = await _stockAlertConfig();
      if (config['enabled'] != 1) return null;
      final rows = await _rows(
        'SELECT * FROM stock_notice_request WHERE token=? AND active=1 AND snapshot IS NOT NULL',
        [requestToken],
      );
      if (rows.isEmpty) return null;
      final raw = rows.single;
      final request = _stockNoticeRead(raw);
      final snapshot =
          jsonDecode(raw['snapshot'] as String) as Map<String, dynamic>;
      if (snapshot['opened'] == true ||
          request.namespace != namespace ||
          request.generation != generation ||
          !await _stockNoticeStillLive(request)) {
        return null;
      }
      await _db.customStatement(
        "UPDATE stock_notice_request SET snapshot=json_set(snapshot,'\$.opened',json('true')) WHERE token=?",
        [requestToken],
      );
      return StockNoticeOpen(
        envelopeId: envelopeId,
        personId: request.personId,
        itemId: request.itemId,
        containerId: request.containerId,
      );
    });
  }

  Future<bool> _acknowledgeStockNotice(
    String token,
    int intentRevision,
    ReminderReceipt receipt,
    String fingerprint,
    String? reason,
  ) async {
    final rows = await _rows(
      'SELECT * FROM stock_notice_request WHERE token=?',
      [token],
    );
    if (rows.isEmpty || rows.single['intent_revision'] != intentRevision) {
      return false;
    }
    final row = rows.single;
    if (row['active'] == 0 && receipt != ReminderReceipt.cancelled) {
      return false;
    }
    final old = row['state'] as String;
    // Terminal monotonicity matches the ordinary and event lanes. A consumed,
    // uncertain or cancelled notice never regresses under a late receipt.
    if (['consumed', 'postUncertain', 'cancelled'].contains(old) &&
        !(old == 'postUncertain' && receipt == ReminderReceipt.consumed) &&
        old != receipt.name) {
      return false;
    }
    final state = switch (receipt) {
      ReminderReceipt.accepted => 'prepared',
      ReminderReceipt.consumed => 'consumed',
      ReminderReceipt.cancelled => 'cancelled',
      ReminderReceipt.postUncertain => 'postUncertain',
      ReminderReceipt.failed => 'failed',
      ReminderReceipt.unknown => 'unknown',
    };
    final settled = [
      ReminderReceipt.consumed,
      ReminderReceipt.postUncertain,
      ReminderReceipt.cancelled,
    ].contains(receipt);
    await _db.customStatement(
      'UPDATE stock_notice_request SET state=?,fingerprint=?,reason=?,active=?,cancel_ack=? WHERE token=?',
      [
        state,
        fingerprint,
        reason,
        settled ? 0 : 1,
        settled || (row['cancel_ack'] as int) == 1 ? 1 : 0,
        token,
      ],
    );
    return true;
  }
}
