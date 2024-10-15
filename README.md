## Indexed Entity Store

`IndexedEntityStore` is a new approach to persistent data management for Flutter applications.

It's first and foremost goal is developer productivity while developing[^1]. Most applications a few thousand or less entities of each types, and if access to these is done via indexed queries, there is no need to make even the simplest data update `async`. Furthermore no manual mapping from entity to "rows" is needed. Just use `toJson`/`fromJson` methods which likely already exists on the typed[^2].

The library itself is developed in the [Berkeley style](https://www.cs.princeton.edu/courses/archive/fall13/cos518/papers/worse-is-better.pdf), meaning that the goal is to make it practially nice to use and also keep the implementation straighforward and small. While this might prevent some nice-to-have features in the best case, it also prevents the worst case meaning that development is slowing down as the code is too entrenched or abandoned and can not be easily migrated.

Because this library uses SQLite synchronously in the same thread, one can easily mix SQL and Dart code with virtually no overhead, which wouldn't be advisable in an `async` database setup (not least due to the added complexity that stuff could've chagned between statement). This means the developer can write simpler, more reusable queries and keep complex logic in Dart[^3].

### Example

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

final someTodo /* Todo? */ = todos.getOnce(99); // returns TODO with ID 99, if any
// Alternatively use `todos.get(99)` to get a subscription (`ValueListenable<Todo?>`) to the item, getting notified of every update

// While using the String columns here is not super nice, this works without code gen and will throw if using a non-indexed column
final openTodos /* List<Todo?> */ = todos.queryOnce((cols) => cols['done'].equals(false));

todos.insert(
  Todo(id: 99, text: 'Publish new version', done: false),
);
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
  deserialize: (s) => _FooEntity.fromJSON(
    jsonDecode(s) as Map<String, dynamic>,
  ),
);
```


[^1]: This means there is no code generation, manual migrations for schema updates, and other roadblocks. Hat tip to [Blackbird](https://github.com/marcoarment/Blackbird) to bringing this into focus.
[^2]: Or Protobuf, if you want to be strictly backwards compatible by default.
[^3]: https://www.sqlite.org/np1queryprob.html
