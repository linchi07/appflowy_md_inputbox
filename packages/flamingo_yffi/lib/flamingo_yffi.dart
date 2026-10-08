library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'src/bindings.g.dart' as f;

/// Owned Dart copies of native events. No callback-owned pointer escapes FFI.
class YChange {
  YChange(this.root, this.path, {this.delta, this.keys});
  final String root;
  final List<Object> path;
  final List<Map<String, dynamic>>? delta;
  final Map<String, dynamic>? keys;
}

/// Synchronous, isolate-confined owner of an official yffi/Yrs document.
/// Dispose views/undo managers before disposing this owner.
class YDocument {
  YDocument({int? clientId}) {
    final options = f.yoptions();
    options.flags |= f.Y_OFFSET_UTF16;
    if (clientId != null) options.id = clientId;
    _doc = f.ydoc_new_with_options(options);
    f.ystring_destroy(options.guid);
    if (options.collection_id != nullptr) {
      f.ystring_destroy(options.collection_id);
    }
    _updates =
        NativeCallable<
          Void Function(Pointer<Void>, Uint32, Pointer<Char>)
        >.isolateLocal((Pointer<Void> _, int length, Pointer<Char> bytes) {
          _guardCallback(
            () => _pendingUpdates.add(
              Uint8List.fromList(bytes.cast<Uint8>().asTypedList(length)),
            ),
          );
        });
    write('binding:observe', (tx) {
      using((arena) {
        final key = tx._string(arena, 'flamingo:updates');
        f.ytransaction_observe_updates_v1(
          tx._txn,
          16,
          key,
          nullptr,
          _updates.nativeFunction,
        );
      });
    });
  }

  late final Pointer<f.YDoc> _doc;
  late final NativeCallable<Void Function(Pointer<Void>, Uint32, Pointer<Char>)>
  _updates;
  final Map<String, YMap> _roots = {};
  final List<
    NativeCallable<Void Function(Pointer<Void>, Uint32, Pointer<f.YEvent>)>
  >
  _observers = [];
  final Set<YUndoManager> _undo = {};
  final List<Uint8List> _pendingUpdates = [];
  final List<YChange> _pendingChanges = [];
  final List<Uint8List> _deferredPackets = [];
  bool _disposed = false;
  bool _active = false;
  Object? _callbackError;

  void _checkIdle() {
    if (_disposed) throw StateError('YDocument is disposed.');
    if (_active) throw StateError('Nested native transactions are forbidden.');
  }

  void _guardCallback(void Function() callback) {
    try {
      callback();
    } catch (error) {
      _callbackError ??= error;
    }
  }

  YMap map(String name) {
    _checkIdle();
    return _roots.putIfAbsent(
      name,
      () => using((arena) {
        final branch = f.ymap(_doc, _cstring(arena, name));
        final callback =
            NativeCallable<
              Void Function(Pointer<Void>, Uint32, Pointer<f.YEvent>)
            >.isolateLocal((
              Pointer<Void> _,
              int count,
              Pointer<f.YEvent> events,
            ) {
              _guardCallback(() {
                for (var i = 0; i < count; i++) {
                  _pendingChanges.add(_copyEvent(name, events + i));
                }
              });
            });
        f.yobserve_deep(
          branch,
          16,
          _cstring(arena, 'flamingo:observe'),
          nullptr,
          callback.nativeFunction,
        );
        _observers.add(callback);
        return YMap._(this, branch);
      }),
    );
  }

  T read<T>(T Function(YTransaction) action) => _transact(null, action);
  T write<T>(String origin, T Function(YTransaction) action) =>
      _transact(origin, action);

  T _transact<T>(String? origin, T Function(YTransaction) action) {
    _checkIdle();
    return using((arena) {
      final txn = origin == null
          ? f.ydoc_read_transaction(_doc)
          : f.ydoc_write_transaction(
              _doc,
              utf8.encode(origin).length,
              _cstring(arena, origin),
            );
      if (txn == nullptr) throw StateError('Cannot acquire Yrs transaction.');
      final wrapper = YTransaction._(this, txn, origin != null);
      _active = true;
      try {
        return action(wrapper);
      } finally {
        wrapper._open = false;
        // Yrs has no rollback: callers validate a command batch before writing.
        f.ytransaction_commit(txn);
        _active = false;
        if (_callbackError case final error?) {
          _callbackError = null;
          throw StateError('Cannot decode Yrs event: $error');
        }
      }
    });
  }

  Uint8List stateVector() => read(
    (tx) =>
        tx._binary((length) => f.ytransaction_state_vector_v1(tx._txn, length)),
  );

  Uint8List encodeUpdate([Uint8List? stateVector]) => read(
    (tx) => using(
      (arena) => tx._binary(
        (length) => f.ytransaction_state_diff_v1(
          tx._txn,
          tx._bytes(arena, stateVector),
          stateVector?.length ?? 0,
          length,
        ),
      ),
    ),
  );

  void applyUpdate(Uint8List update) {
    if (update.isEmpty) throw const FormatException('Empty Yrs update.');
    write('binding:remote', (tx) {
      using((arena) {
        final result = f.ytransaction_apply(
          tx._txn,
          tx._bytes(arena, update),
          update.length,
        );
        if (result != 0) throw FormatException('Invalid Yrs update ($result).');
      });
    });
    final pending = read((tx) {
      final data = f.ytransaction_pending_update(tx._txn);
      final deletes = f.ytransaction_pending_ds(tx._txn);
      final result = data != nullptr || deletes != nullptr;
      if (data != nullptr) f.ypending_update_destroy(data);
      if (deletes != nullptr) f.ydelete_set_destroy(deletes);
      return result;
    });
    if (pending) {
      if (!(update.length == 2 && update[0] == 0 && update[1] == 0) &&
          !_deferredPackets.any((packet) => _sameBytes(packet, update))) {
        _deferredPackets.add(Uint8List.fromList(update).asUnmodifiableView());
      }
    } else {
      _deferredPackets.clear();
    }
  }

  /// yffi state_diff encodes integrated state only. Retain accepted packets
  /// while native dependencies/deletions are pending so snapshots can restore.
  List<Uint8List> get pendingPackets {
    _checkIdle();
    return List.unmodifiable(_deferredPackets);
  }

  List<Uint8List> takeUpdates() {
    final result = List<Uint8List>.of(_pendingUpdates);
    _pendingUpdates.clear();
    return result;
  }

  List<YChange> takeChanges() {
    final result = List<YChange>.of(_pendingChanges);
    _pendingChanges.clear();
    return result;
  }

  YUndoManager undoManager(String origin, Iterable<YMap> scopes) {
    _checkIdle();
    final result = using((arena) {
      final options = arena<f.YUndoManagerOptions>();
      options.ref.capture_timeout_millis = 0;
      final manager = f.yundo_manager(options);
      for (final scope in scopes) {
        if (!identical(scope._owner, this)) {
          throw ArgumentError('Foreign scope');
        }
        f.yundo_manager_add_scope(manager, _doc, scope._branch);
      }
      f.yundo_manager_add_origin(
        manager,
        utf8.encode(origin).length,
        _cstring(arena, origin),
      );
      return YUndoManager._(this, manager);
    });
    _undo.add(result);
    return result;
  }

  void dispose() {
    if (_disposed) return;
    _checkIdle();
    for (final manager in _undo.toList()) {
      manager.dispose();
    }
    write(
      'binding:dispose',
      (tx) => using((arena) {
        f.ytransaction_unobserve_updates_v1(
          tx._txn,
          16,
          _cstring(arena, 'flamingo:updates'),
        );
      }),
    );
    using((arena) {
      for (final root in _roots.values) {
        f.yunobserve_deep(
          root._branch,
          16,
          _cstring(arena, 'flamingo:observe'),
        );
      }
    });
    for (final callback in _observers) {
      callback.close();
    }
    _updates.close();
    f.ydoc_destroy(_doc);
    _disposed = true;
    _pendingChanges.clear();
    _pendingUpdates.clear();
    _deferredPackets.clear();
  }
}

class YTransaction {
  YTransaction._(this._owner, this._txn, this._writable);
  final YDocument _owner;
  final Pointer<f.YTransaction> _txn;
  final bool _writable;
  bool _open = true;
  void _check(_YBranch branch, {bool write = false}) {
    if (!_open || !identical(branch._owner, _owner)) {
      throw StateError('Expired transaction or foreign branch.');
    }
    if (write && !_writable) throw StateError('Read-only transaction.');
  }

  Pointer<Char> _string(Arena arena, String text) => _cstring(arena, text);
  Pointer<Char> _bytes(Arena arena, Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return nullptr;
    final result = arena<Uint8>(bytes.length);
    result.asTypedList(bytes.length).setAll(0, bytes);
    return result.cast();
  }

  Uint8List _binary(Pointer<Char> Function(Pointer<Uint32>) create) => using((
    arena,
  ) {
    final length = arena<Uint32>();
    final data = create(length);
      if (data == nullptr) {
        throw const FormatException('Invalid Yrs binary input.');
      }
    try {
      return Uint8List.fromList(data.cast<Uint8>().asTypedList(length.value));
    } finally {
      f.ybinary_destroy(data, length.value);
    }
  });
}

abstract class _YBranch {
  _YBranch(this._owner, this._branch);
  final YDocument _owner;
  final Pointer<f.Branch> _branch;
}

/// Preliminary shared types are integrated once; never overwrite an existing
/// YText/YMap with a new preliminary type when editing its content.
class YNewMap {
  const YNewMap();
}

class YNewArray {
  const YNewArray();
}

class YNewText {
  const YNewText();
}

class YMap extends _YBranch {
  YMap._(super.owner, super.branch);
  dynamic get(YTransaction tx, String key) {
    tx._check(this);
    return using((arena) {
      final output = f.ymap_get(_branch, tx._txn, _cstring(arena, key));
      if (output == nullptr) return null;
      try {
        return _decode(output.ref, _owner);
      } finally {
        f.youtput_destroy(output);
      }
    });
  }

  void set(YTransaction tx, String key, Object? value) {
    tx._check(this, write: true);
    using((arena) {
      final input = arena<f.YInput>()..ref = _input(arena, value);
      f.ymap_insert(_branch, tx._txn, _cstring(arena, key), input);
    });
  }

  void remove(YTransaction tx, String key) {
    tx._check(this, write: true);
    using((arena) => f.ymap_remove(_branch, tx._txn, _cstring(arena, key)));
  }

  Map<String, dynamic> entries(YTransaction tx) {
    tx._check(this);
    final result = <String, dynamic>{};
    final iterator = f.ymap_iter(_branch, tx._txn);
    try {
      while (true) {
        final entry = f.ymap_iter_next(iterator);
        if (entry == nullptr) break;
        try {
          result[_string(entry.ref.key)] = _decode(entry.ref.value.ref, _owner);
        } finally {
          f.ymap_entry_destroy(entry);
        }
      }
    } finally {
      f.ymap_iter_destroy(iterator);
    }
    return result;
  }
}

class YArray extends _YBranch {
  YArray._(super.owner, super.branch);
  List<dynamic> values(YTransaction tx) {
    tx._check(this);
    final result = <dynamic>[];
    final iterator = f.yarray_iter(_branch, tx._txn);
    try {
      while (true) {
        final output = f.yarray_iter_next(iterator);
        if (output == nullptr) break;
        try {
          result.add(_decode(output.ref, _owner));
        } finally {
          f.youtput_destroy(output);
        }
      }
    } finally {
      f.yarray_iter_destroy(iterator);
    }
    return result;
  }

  void insert(YTransaction tx, int index, String value) {
    tx._check(this, write: true);
    final length = f.yarray_len(_branch);
    if (index < 0 || index > length) throw RangeError.range(index, 0, length);
    using((arena) {
      final input = arena<f.YInput>()..ref = _input(arena, value);
      f.yarray_insert_range(_branch, tx._txn, index, input, 1);
    });
  }

  void remove(YTransaction tx, int index) {
    tx._check(this, write: true);
    final length = f.yarray_len(_branch);
    if (index < 0 || index >= length) {
      throw RangeError.range(index, 0, length - 1);
    }
    f.yarray_remove_range(_branch, tx._txn, index, 1);
  }
}

class YText extends _YBranch {
  YText._(super.owner, super.branch);
  List<Map<String, dynamic>> delta(YTransaction tx) {
    tx._check(this);
    return using((arena) {
      final length = arena<Uint32>();
      final chunks = f.ytext_chunks(_branch, tx._txn, length);
      try {
        return [
          for (var i = 0; i < length.value; i++)
            {
              'insert': _decode(chunks[i].data, _owner),
              if (chunks[i].fmt_len > 0)
                'attributes': {
                  for (var j = 0; j < chunks[i].fmt_len; j++)
                    _string(chunks[i].fmt[j].key): _decode(
                      chunks[i].fmt[j].value.ref,
                      _owner,
                    ),
                },
            },
        ];
      } finally {
        f.ychunks_destroy(chunks, length.value);
      }
    });
  }

  void applyDelta(YTransaction tx, List<Map<String, dynamic>> delta) {
    tx._check(this, write: true);
    var consumed = 0;
    final length = f.ytext_len(_branch, tx._txn);
    // Invalid offsets can panic across the C ABI, so check the whole batch first.
    for (final op in delta) {
      if (op.containsKey('insert')) {
        final text = op['insert'];
        if (text is! String || text.contains('\u0000')) {
          throw ArgumentError('YText inserts must be strings without NUL.');
        }
      } else {
        final count = op['retain'] ?? op['delete'];
        if (count is! int || count <= 0) {
          throw ArgumentError('Invalid text delta');
        }
        consumed += count;
        if (consumed > length) throw RangeError('Delta exceeds text length.');
      }
    }
    if (delta.isEmpty) return;
    using((arena) {
      final ops = arena<f.YDeltaIn>(delta.length);
      for (var i = 0; i < delta.length; i++) {
        final op = delta[i];
        final attrs = op['attributes'] == null
            ? nullptr.cast<f.YInput>()
            : (arena<f.YInput>()..ref = _input(arena, op['attributes']));
        if (op.containsKey('insert')) {
          final data = arena<f.YInput>()..ref = _input(arena, op['insert']);
          ops[i] = f.ydelta_input_insert(data, attrs);
        } else if (op.containsKey('retain')) {
          ops[i] = f.ydelta_input_retain(op['retain'] as int, attrs);
        } else {
          ops[i] = f.ydelta_input_delete(op['delete'] as int);
        }
      }
      f.ytext_insert_delta(_branch, tx._txn, ops, delta.length);
    });
  }

  Uint8List anchor(YTransaction tx, int offset, {int assoc = 0}) {
    tx._check(this, write: true);
    final length = f.ytext_len(_branch, tx._txn);
    if (offset < 0 || offset > length) {
      throw RangeError.range(offset, 0, length);
    }
    // yffi's index constructor returns null for After at the sequence end.
    // Use its native type-relative position for this boundary (also empty text).
    final pos = offset == length && assoc >= 0
        ? using((arena) {
            final id = f.ybranch_id(_branch);
            final scope = id.client_or_len >= 0
                ? {
                    'type': {
                      'client': id.client_or_len,
                      'clock': id.variant.clock,
                    },
                  }
                : {
                    'tname': utf8.decode(
                      id.variant.name.asTypedList(-id.client_or_len),
                    ),
                  };
            return f.ysticky_index_from_json(
              _cstring(arena, jsonEncode({...scope, 'assoc': 0})),
            );
          })
        : f.ysticky_index_from_index(_branch, tx._txn, offset, assoc);
    if (pos == nullptr) throw StateError('Cannot create relative position.');
    try {
      return tx._binary((len) => f.ysticky_index_encode(pos, len));
    } finally {
      f.ysticky_index_destroy(pos);
    }
  }

  int? resolve(YTransaction tx, Uint8List anchor) {
    tx._check(this);
    return using((arena) {
      final pos = f.ysticky_index_decode(
        tx._bytes(arena, anchor),
        anchor.length,
      );
      if (pos == nullptr) return null;
      try {
        final branch = arena<Pointer<f.Branch>>();
        final index = arena<Uint32>();
        f.ysticky_index_read(pos, tx._txn, branch, index);
        return branch.value == _branch ? index.value : null;
      } finally {
        f.ysticky_index_destroy(pos);
      }
    });
  }
}

class YUndoManager {
  YUndoManager._(this._owner, this._manager);
  final YDocument _owner;
  final Pointer<f.YUndoManager> _manager;
  bool _disposed = false;
  void _check() {
    _owner._checkIdle();
    if (_disposed) throw StateError('Undo manager is disposed.');
  }

  bool get canUndo {
    _check();
    return f.yundo_manager_undo_stack_len(_manager) > 0;
  }

  int get undoLength {
    _check();
    return f.yundo_manager_undo_stack_len(_manager);
  }

  bool get canRedo {
    _check();
    return f.yundo_manager_redo_stack_len(_manager) > 0;
  }

  void clear() {
    _check();
    f.yundo_manager_clear(_manager);
  }

  bool undo() {
    _check();
    return f.yundo_manager_undo(_manager) != 0;
  }

  bool redo() {
    _check();
    return f.yundo_manager_redo(_manager) != 0;
  }

  void dispose() {
    if (_disposed) return;
    _check();
    f.yundo_manager_destroy(_manager);
    _owner._undo.remove(this);
    _disposed = true;
  }
}

Pointer<Char> _cstring(Arena arena, String text) {
  if (text.contains('\u0000')) throw ArgumentError('FFI string contains NUL.');
  return text.toNativeUtf8(allocator: arena).cast();
}

String _string(Pointer<Char> value) => value.cast<Utf8>().toDartString();

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

f.YInput _input(Arena arena, Object? value) {
  if (value == null) return f.yinput_null();
  if (value is bool) return f.yinput_bool(value ? 1 : 0);
  if (value is int) return f.yinput_long(value);
  if (value is num) return f.yinput_float(value.toDouble());
  if (value is String) return f.yinput_string(_cstring(arena, value));
  if (value is YNewText) return f.yinput_ytext(_cstring(arena, ''));
  if (value is YNewMap) return f.yinput_ymap(nullptr, nullptr, 0);
  if (value is YNewArray) return f.yinput_yarray(nullptr, 0);
  // Recursion preserves integer/bool/null types in JSON attributes.
  if (value is Map) {
    final keys = arena<Pointer<Char>>(value.isEmpty ? 1 : value.length);
    final values = arena<f.YInput>(value.isEmpty ? 1 : value.length);
    var i = 0;
    for (final entry in value.entries) {
      keys[i] = _cstring(arena, entry.key as String);
      values[i++] = _input(arena, entry.value);
    }
    return f.yinput_json_map(keys, values, value.length);
  }
  if (value is List) {
    final values = arena<f.YInput>(value.isEmpty ? 1 : value.length);
    for (var i = 0; i < value.length; i++) {
      values[i] = _input(arena, value[i]);
    }
    return f.yinput_json_array(values, value.length);
  }
  throw ArgumentError('Unsupported Yrs input: ${value.runtimeType}');
}

dynamic _decode(f.YOutput value, YDocument? owner) => switch (value.tag) {
  f.Y_JSON_NULL || f.Y_JSON_UNDEF => null,
  f.Y_JSON_BOOL => value.value.flag != 0,
  f.Y_JSON_INT => value.value.integer,
  f.Y_JSON_NUM => value.value.num,
  f.Y_JSON_STR => _string(value.value.str),
  f.Y_JSON_BUF => Uint8List.fromList(
    value.value.buf.cast<Uint8>().asTypedList(value.len),
  ),
  f.Y_JSON_ARR => [
    for (var i = 0; i < value.len; i++) _decode(value.value.array[i], owner),
  ],
  f.Y_JSON_MAP => {
    for (var i = 0; i < value.len; i++)
      _string(value.value.map[i].key): _decode(
        value.value.map[i].value.ref,
        owner,
      ),
  },
  f.Y_MAP when owner != null => YMap._(owner, value.value.y_type),
  f.Y_TEXT when owner != null => YText._(owner, value.value.y_type),
  f.Y_ARRAY when owner != null => YArray._(owner, value.value.y_type),
  _ => throw FormatException('Unexpected Yrs value type ${value.tag}'),
};

YChange _copyEvent(String root, Pointer<f.YEvent> event) => using((arena) {
  final length = arena<Uint32>();
  final e = event.ref;
  final content = arena<f.YEventContent>()..ref = e.content;
  final nativePath = switch (e.tag) {
    f.Y_TEXT => f.ytext_event_path(content.cast(), length),
    f.Y_MAP => f.ymap_event_path(content.cast(), length),
    f.Y_ARRAY => f.yarray_event_path(content.cast(), length),
    _ => throw FormatException('Unsupported shared event ${e.tag}'),
  };
  final path = <Object>[];
  try {
    for (var i = 0; i < length.value; i++) {
      path.add(
        nativePath[i].tag == f.Y_EVENT_PATH_KEY
            ? _string(nativePath[i].value.key)
            : nativePath[i].value.index,
      );
    }
  } finally {
    f.ypath_destroy(nativePath, length.value);
  }
  if (e.tag == f.Y_TEXT) {
    final ops = f.ytext_event_delta(content.cast(), length);
    try {
      return YChange(
        root,
        path,
        delta: [
          for (var i = 0; i < length.value; i++)
            {
              switch (ops[i].tag) {
                f.Y_EVENT_CHANGE_ADD => 'insert',
                f.Y_EVENT_CHANGE_DELETE => 'delete',
                _ => 'retain',
              }: ops[i].tag == f.Y_EVENT_CHANGE_ADD
                  ? _decode(ops[i].insert.ref, null)
                  : ops[i].len,
              if (ops[i].attributes_len > 0)
                'attributes': {
                  for (var j = 0; j < ops[i].attributes_len; j++)
                    _string(ops[i].attributes[j].key): _decode(
                      ops[i].attributes[j].value,
                      null,
                    ),
                },
            },
        ],
      );
    } finally {
      f.ytext_delta_destroy(ops, length.value);
    }
  }
  if (e.tag == f.Y_MAP && path.length == 2 && path.last == 'props') {
    final keys = f.ymap_event_keys(content.cast(), length);
    try {
      return YChange(
        root,
        path,
        keys: {
          for (var i = 0; i < length.value; i++)
            _string(keys[i].key): keys[i].new_value == nullptr
                ? null
                : _decode(keys[i].new_value.ref, null),
        },
      );
    } finally {
      f.yevent_keys_destroy(keys, length.value);
    }
  }
  return YChange(root, path);
});
