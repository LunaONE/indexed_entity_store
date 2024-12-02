## 2.0.1

* Add tests for internal schema migrations
* Speed up `writeMany` by defaulting to use a single statement for all inserts (as opposed to a single transactions with many individual inserts)
  * One can revert to the previous behavior by setting `singleStatement: false` in the call
* Add `delete(where: )` to delete all rows matching a specific index-query

## 2.0.0

* Update method names
  * Most notably `insert` is now `write` to transmit the ambivalence between "insert" and "update"
  * `get` is now `read` to be symmetric to write (but instead of entities it takes keys, of course)
  * `query` now takes an optional `where` parameter, so instead of `getAll()` you can now just use `query()` to get the same result
  * `delete` now bundles multiple ways to identify entities to delete, offering a simpler API surface for the overall store
* Support foreign key (`referencing`) and `unique` constraints on indices
  * With `referencing` one can ensure that the index's value points to an entityt with the same primary key in another store
  * A `unique` index ensures that only one entity in the store uses the same value for that key

## 1.4.7

* Add `contains` functions for `String` index columns

## 1.4.6

* Re-enable foreign key constraint for every session
  * Clean up unused indices which were not automatically removed before (but will be going forward)

## 1.4.5

* try/catch with `ROLLBACK` in case a transaction fails, so as to not leave the database in a locked state
* Re-add explicit deletion of index, as `REPLACE INTO` was observed to not remove the entity's index on all platforms (and there is no clear documentation under what circumstances it would do or not do so)

## 1.4.4

* Add another example, showing how to build repositories with a `Future<ValueListenable<T>>` interface
* Fix index migration bug (introduced in 1.4.3), when a name is reused across index versions

## 1.4.3

* Add `insertMany` method to handle batch inserts/updates
  * This, combined with a new index, massively speeds up large inserts:
    - Inserting 1000 entities with 2 indices is now 40x faster than a simple loop using `insert`s individually
    - When updating 1000 existing entities with new values, the new implementation leads to an even greater 111x speed-up
  * This further proves that the synchronous database approach can handle even large local databases and operations. If you need to insert even larger amounts of data without dropping a frame, there is [a solution for that](https://github.com/simolus3/sqlite3.dart/issues/260#issuecomment-2446618546) as well.

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
