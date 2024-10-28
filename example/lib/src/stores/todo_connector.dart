import 'dart:convert';

import 'package:indexed_entity_store/indexed_entity_store.dart';
import 'package:indexed_entity_store_example/src/stores/database_helper.dart';
import 'package:indexed_entity_store_example/src/stores/entities/todo.dart';

typedef TodoStore = IndexedEntityStore<Todo, int>;

final todoConnector =
    IndexedEntityConnector<Todo, int /* key type */, String /* DB type */ >(
  entityKey: 'todo',
  getPrimaryKey: (t) => t.id,
  getIndices: (index) {
    index((t) => t.done, as: 'done');
  },
  serialize: (t) => jsonEncode(t.toJSON()),
  deserialize: (s) => Todo.fromJSON(
    jsonDecode(s) as Map<String, dynamic>,
  ),
);

/// Creates a new Todo store, backed by a new, temporary database
///
/// In practice a single database would likely be reused with many stores,
/// and more importantly the same instance would be used instead of a new one created
/// each time as done here for the showcase.
TodoStore getTodoStore() {
  return getNewDatabase().entityStore(todoConnector);
}
