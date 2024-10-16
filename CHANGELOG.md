## 1.2.1

* Fix DB init with the latest SQLite from `sqlite3_flutter_libs` on Android

## 1.2.0

* Typed indices: All queries not check the parameter types, such that one does not accidentally pass a `String` to an `int` index field for example.
  * These are checked at runtime, as the interface does not allow specifying the type signature per column
  * Additional the index-building specification has been changed, to be able to discern field which are nullable and those which must not be
* Add more query methods: less than (or equal) and greater than (or equal)

## 1.1.1

* Add `deleteEntity` in case the caller does not have access to the primary key used by the connector (e.g. if it's a combined one)

## 1.1.0

* Adds reactivity
  - Callers now get notified for every update to their queries
  - All queries are now reactive by default, so queries can be composed without missing any updates. This is highly useful unless the synchronizations happens on a higher application layer, in which case the `*Once` methods can be used.

## 1.0.0

* Initial release.
