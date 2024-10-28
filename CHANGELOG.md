## 1.4.2

* Add full example app
* Implement `DisposableValueListenable` for `QueryResult`

## 1.4.1

* Add `deleteAll` method

## 1.4.0

* Enhance subscriptions to not emit updates when the underlying database value has not changed
  * E.g. when an object is updated with the exact same storage values or a query ends up with the same result list no updates are emitted
* Fix unsubscribe for queries

## 1.3.0

* Add `single`/`singleOnce` for cases where one expects a single match, but does not have a primary key
* Add `limit` and `orderBy` to `query`/`queryOnce`
* Add `orderBy` to `getAll`/`getAllOnce`

## 1.2.2

* Fix index query building on Android / latest `sqlite3_flutter_libs`

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
