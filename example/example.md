### Example

See [the detailed app](https://github.com/LunaONE/indexed_entity_store/tree/main/example) for a full-blown example showcasing various approach of how to build an app on top of this package. Or look below for a simple introduction.

#### Simple example

Let's see how this would look for a simple TODO list application.

```dart
class Todo {
  final int id;
  final String text;
  final bool done;

  Todo({ required this.id, required this.text, required this.done });

  // These would very likely be created by [json_serializable](https://pub.dev/packages/json_serializable) or [freezed](https://pub.dev/packages/freezed) already for your models
  Map<String, dynamic> toJSON() {
    return {
        'id': id,
        'text': text,
        'done': done,
    };
  }

  static Todo fromJSON(Map<String, dynamic> json) {
    return Todo(
        id: json['id'],
        text: json['text'],
        done: json['done'],
    );
  }
}
```

```dart
final db = IndexedEntityDabase.open('/tmp/appdata.sqlite3'); // in practice put into app dir

final todos = db.entityStore(todoConnector);

// While using the String columns here is not super nice, this works without code gen and will throw if using a non-indexed column
final openTodos = todos.query((cols) => cols['done'].equals(false));

print(openTodos.value); // prints an empty list on first run as no TODOs are yet added to the database

todos.insert(
  Todo(id: 1, text: 'Publish new version', done: false),
);

print(openTodos.value); // now prints a list containing the newly added TODO
// `openTodos` was actually updated right after the insert, and one could e.g. `addListener` to connect side-effects on every change

openTodos.dispose(); // unsubscribe when no loger interested in updates
```

The above code omitted the defintion of `todoConnector`. This is the tiny piece of configuration that tells the library how to map between its storage and the entity's type. For a Todo task it might look like this:


```dart
final todoConnector = IndexedEntityConnector<Todo, int /* key type */, String /* DB type */>(
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
```

The benefit of using the connector instead of a base class interface that would need to be implemented by every storage model, is that you can store arbitrary classes, even those you might not control.
