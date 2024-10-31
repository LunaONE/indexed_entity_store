import 'package:flutter/cupertino.dart';
import 'package:indexed_entity_store/indexed_entity_store.dart';
import 'package:indexed_entity_store_example/src/stores/entities/todo.dart';
import 'package:indexed_entity_store_example/src/stores/todo_connector.dart';

/// Showcases a simple example where the initial data is synchronously available
/// (mocked here via the repository's `init`)
class SimpleSynchronousExample extends StatefulWidget {
  const SimpleSynchronousExample({
    super.key,
  });

  @override
  State<SimpleSynchronousExample> createState() =>
      _SimpleSynchronousExampleState();
}

class _SimpleSynchronousExampleState extends State<SimpleSynchronousExample> {
  final repository = SimpleSynchronousRepository(store: getTodoStore())..init();

  late final openTodos = repository.getOpenTodos();

  @override
  initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tap any todo do mark it as done (and disappear from the list)',
        ),
        Expanded(
          child: SingleChildScrollView(
            child: ValueListenableBuilder(
              valueListenable: openTodos,
              builder: (context, openTodos, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final openTodo in openTodos)
                      CupertinoListTile(
                        onTap: () => repository
                            .updateTodo(openTodo.copyWith(done: true)),
                        title: Text(openTodo.text),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    // In practice, whoever create the database, store, and repository would have to dispose it

    openTodos.dispose();

    super.dispose();
  }
}

class SimpleSynchronousRepository {
  final TodoStore _store;

  SimpleSynchronousRepository({
    required TodoStore store,
  }) : _store = store;

  void init() {
    _store.write(Todo(id: 1, text: 'Brew Coffe', done: false));
    _store.write(Todo(id: 2, text: 'Get milk', done: false));
    _store.write(Todo(id: 3, text: 'Read newspaper', done: false));
  }

  QueryResult<List<Todo>> getOpenTodos() {
    return _store.query(where: (cols) => cols['done'].equals(false));
  }

  void updateTodo(Todo todo) {
    _store.write(todo);
  }
}
