import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:indexed_entity_store/indexed_entity_store.dart';
import 'package:indexed_entity_store_example/src/stores/database_helper.dart';

enum HotReloadCase {
  intial,

  /// Switching to this case will cause an error, as there is a persistent query on the age
  ///
  /// Since this error is not something that happens at normal runtime, but just during development when
  /// using index names which are no longer value, it's exposed through the `QueryResult.value` (which
  /// will `throw` when access), such that we don't have to wrap the `value` into a success/error wrapper
  /// all the time (because under ordinary circumstances we'll always have a successful value).
  withoutAgeIndex,

  /// When this is active, a new name index is created, and only if active is a query for this index used
  ///
  /// Thus there will be no error, but instead the new query starts working right away, showcasing how the
  /// code gracefully handles updates while coding.
  withNameIndex,
}

const _currentCase = HotReloadCase.withNameIndex;

/// Showcases how the store can be updated during development, supporting hot-reload
class HotReloadExample extends StatefulWidget {
  const HotReloadExample({
    super.key,
  });

  @override
  State<HotReloadExample> createState() => _HotReloadExampleState();
}

class _HotReloadExampleState extends State<HotReloadExample> {
  final database = getNewDatabase(); // todo merge again

  late final PersonStore store = database.entityStore(PersonConnector());

  late final QueryResult<List<Person>> everyone = store.query();

  late final QueryResult<List<Person>> adults =
      store.query(where: (cols) => cols['age'].greaterThanOrEqual(18));

  QueryResult<List<Person>>? roberts;

  @override
  initState() {
    super.initState();

    // ignore: invalid_use_of_protected_member
    // WidgetsBinding.instance.registerSignalServiceExtension(
    //   name: FoundationServiceExtensions.reassemble.name,
    //   callback: () async {
    //     print('reassemble');
    //   },
    // );

    store.writeMany([
      Person(id: 1, name: 'Sam', age: 5),
      Person(id: 2, name: 'Bob', age: 3),
      Person(id: 3, name: 'Robert', age: 20),
      Person(id: 4, name: 'Max', age: 21),
    ]);
  }

  @override
  void reassemble() {
    super.reassemble();

    debugPrint('Reassemble');
    database.handleHotReload();
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    // });

    if (_currentCase == HotReloadCase.withNameIndex) {
      roberts = store.query(
          where: (cols) =>
              cols['name'].equals('Robert') | cols['name'].equals('Bob'));
    } else {
      roberts?.dispose();
      roberts = null;
    }

    // static final _hotReload = ChangeNotifier();
    // static Listenable get hotReload => _hotReload;

    // WidgetsFlutterBinding.ensureInitialized().addObserver(observer);
    // WidgetsFlutterBinding.ensureInitialized().buildOwner.;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Change the `_currentCase` value in the code and see how the app adapts to the new configuration after hot-reload',
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _GroupWidget(name: 'Everyone', persons: everyone),
                _GroupWidget(name: 'Adults', persons: adults),
                if (roberts != null)
                  _GroupWidget(name: 'Roberts', persons: roberts!),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    // In practice, whoever create the database, store, and repository would have to dispose it

    everyone.dispose();
    adults.dispose();
    roberts?.dispose();

    super.dispose();
  }
}

class _GroupWidget extends StatelessWidget {
  const _GroupWidget({
    // ignore: unused_element
    super.key,
    required this.name,
    required this.persons,
  });

  final String name;

  final QueryResult<List<Person>> persons;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: persons,
      builder: (context, persons, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            Text(
              '  $name',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            for (final person in persons)
              CupertinoListTile(
                title: Text('${person.name} (${person.age})'),
              ),
          ],
        );
      },
    );
  }
}

// class SimpleSynchronousRepository {
//   final TodoStore _store;

//   SimpleSynchronousRepository({
//     required TodoStore store,
//   }) : _store = store;

//   void init() {
//     _store.write(Todo(id: 1, text: 'Brew Coffe', done: false));
//     _store.write(Todo(id: 2, text: 'Get milk', done: false));
//     _store.write(Todo(id: 3, text: 'Read newspaper', done: false));
//   }

//   QueryResult<List<Todo>> getOpenTodos() {
//     return _store.query(where: (cols) => cols['done'].equals(false));
//   }

//   void updateTodo(Todo todo) {
//     _store.write(todo);
//   }
// }

typedef PersonStore = IndexedEntityStore<Person, int>;

// Instantiate the store on top of the DB?
// with (super.database)
// would that make query writing better by e.g. using `store.ageCol.equals` ?

class PersonConnector
    implements
        IndexedEntityConnector<
            Person,
            // key type
            int,
            // DB value type
            String> {
  @override
  final entityKey = 'person';

  @override
  void getIndices(IndexCollector<Person> index) {
    if (_currentCase != HotReloadCase.withoutAgeIndex) {
      index((p) => p.age, as: 'age');
    }

    if (_currentCase == HotReloadCase.withNameIndex) {
      index((p) => p.name, as: 'name');
    }
  }

  @override
  int getPrimaryKey(Person e) => e.id;

  @override
  String serialize(Person e) => jsonEncode(e.toJSON());

  @override
  Person deserialize(String s) => Person.fromJSON(
        jsonDecode(s) as Map<String, dynamic>,
      );
}

class Person {
  Person({
    required this.id,
    required this.name,
    required this.age,
  });

  final int id;

  final String name;

  final int age;

  // These would very likely be created by [json_serializable](https://pub.dev/packages/json_serializable)
  // or [freezed](https://pub.dev/packages/freezed) already for your models
  Map<String, dynamic> toJSON() {
    return {
      'id': id,
      'name': name,
      'age': age,
    };
  }

  static Person fromJSON(Map<String, dynamic> json) {
    return Person(
      id: json['id'],
      name: json['name'],
      age: json['age'],
    );
  }
}

class Foo extends WidgetsBindingObserver {}

class HotReloadTracker {
  static final _instance = HotReloadTracker._internal();
  factory HotReloadTracker() => _instance;

  HotReloadTracker._internal() {
    if (kDebugMode) {
      print("HotReloadTracker initialized - possible hot reload");
    }
  }
}
