import 'package:flutter/foundation.dart';
import 'package:indexed_entity_store/indexed_entity_store.dart';
import 'package:indexed_entity_store_example/main.dart';

IndexedEntityDabase getNewDatabase() {
  if (!applicationCacheDirectory.existsSync()) {
    applicationCacheDirectory.createSync(recursive: true);
  }

  return IndexedEntityDabase.open(applicationCacheDirectory.uri
      .resolve('./sample_db_${FlutterTimeline.now}.sqlite3')
      .toFilePath());
}
