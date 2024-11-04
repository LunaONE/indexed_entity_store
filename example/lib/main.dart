import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:indexed_entity_store_example/src/examples/async_value_group_and_detail.dart';
import 'package:indexed_entity_store_example/src/examples/future_value_listenable_group_and_detail.dart';
import 'package:indexed_entity_store_example/src/examples/simple_synchronous.dart';
import 'package:path_provider/path_provider.dart';

late final Directory applicationCacheDirectory;

void main() async {
  // Normally this setup would of course be done after the initial frame / loading screen is rendered
  WidgetsFlutterBinding.ensureInitialized();
  applicationCacheDirectory = await getApplicationCacheDirectory();

  runApp(const IndexedEntityStoreExampleApp());
}

class IndexedEntityStoreExampleApp extends StatelessWidget {
  const IndexedEntityStoreExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoApp(
      home: ExampleSelector(),
    );
  }
}

class ExampleSelector extends StatefulWidget {
  const ExampleSelector({
    super.key,
  });

  @override
  State<ExampleSelector> createState() => _ExampleSelectorState();
}

class _ExampleSelectorState extends State<ExampleSelector> {
  Widget? _example;

  static const Map<String, Widget> examples = {
    'Simple synchronous data repository': SimpleSynchronousExample(),
    '`AsyncValue`-based product list & detail view':
        AsyncValueGroupDetailExample(),
    '`Future<ValueSource<T>>`-based product list & detail view':
        AsynchronousGroupDetailExample(),
  };

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Examples'),
      ),
      child: SafeArea(
        child: _example ??
            ListView(
              children: [
                for (final MapEntry(key: name, value: widget)
                    in examples.entries)
                  CupertinoListTile(
                    onTap: () {
                      setState(() {
                        _example = widget;
                      });
                    },
                    title: Text(name),
                  ),
              ],
            ),
      ),
    );
  }
}
