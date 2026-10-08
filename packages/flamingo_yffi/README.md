# flamingo_yffi

Isolate-confined Dart wrapper around the pinned official yffi C ABI. Native code
assets are built by hook/build.dart from the unmodified y-crdt submodule. Both
yffi and yrs use tag v0.28.0 (commit 23b7f5693bbf9e7d26340c521ee8647f79bdfba2).

Use a transaction closure; handles must not escape their owner's lifetime.
Yrs does not roll back a write closure. Validate a complete domain command
before writing. Dispose each document explicitly. Native events and updates
are copied while callbacks are live; never retain their C pointers.

The wrapper currently supports the Map/Array/Text, v1 update, native selective
undo, and relative-position APIs used by Flamingo. Text offsets are UTF-16.
C string keys/text cannot contain NUL; the domain binding rejects them before
writing. This wrapper is not an editor binding or transport protocol.

See ../../docs/collaboration.md for ownership, resource limits, platform status
and table-structure limitations. MIT licenses for the upstream code are kept in
vendor/y-crdt/LICENSE.
