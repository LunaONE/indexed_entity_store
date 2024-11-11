import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:indexed_entity_store_example/src/examples/disk_file_store/disk_file_store.dart';
import 'package:indexed_entity_store_example/src/stores/database_helper.dart';
import 'package:path_provider/path_provider.dart';

class DiskFileStorageExample extends StatefulWidget {
  const DiskFileStorageExample({super.key});

  @override
  State<DiskFileStorageExample> createState() => _DiskFileStorageExampleState();
}

class _DiskFileStorageExampleState extends State<DiskFileStorageExample> {
  late final String baseDirectory;

  var baseDirectoryFiles = <String>[];

  final database = getNewDatabase();

  DiskFileStore<ImageMetadata, int>? fileStore;

  late final storeFiles = fileStore!.query();

  @override
  void initState() {
    super.initState();

    getApplicationDocumentsDirectory().then((value) {
      setState(() {
        debugPrint('getApplicationDocumentsDirectory: ${value.path}');

        baseDirectory = (Directory.fromUri(value.uri
                .resolve('./file_store_example/${FlutterTimeline.now}'))
              ..createSync(recursive: true))
            .path;

        if (kDebugMode) {
          print('baseDirectory: $baseDirectory');
        }

        fileStore = DiskFileStore<ImageMetadata, int>(
          database,
          entityKey: 'files',
          baseDirectory: baseDirectory,
          getPrimaryKey: (i) => i.id,
          getIndices: (index) {},
          serializeMetadata: (e) => e.toJSONString(),
          deserializeMetadata: ImageMetadata.fromJSONString,
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (fileStore == null) {
      return const CupertinoActivityIndicator();
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Files in `baseDirectory`:',
              style: TextStyle(fontSize: 20)),
          CupertinoButton(
            onPressed: _updateDirectoryListing,
            child: const Text('Reload'),
          ),
          for (final file in baseDirectoryFiles) Text(file),
          const Text('Files in `DiskFileStore`:',
              style: TextStyle(fontSize: 20)),
          Row(
            children: [
              CupertinoButton(
                onPressed: _loadNewFile,
                child: const Text('Load another'),
              ),
              CupertinoButton(
                onPressed: _updateFirstFile,
                child: const Text('Update first'),
              ),
              CupertinoButton(
                onPressed: _deleteLast,
                child: const Text('Delete last'),
              ),
            ],
          ),
          ValueListenableBuilder(
            valueListenable: storeFiles,
            builder: (context, storeFiles, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final storeFile in storeFiles)
                    Row(
                      children: [
                        SizedBox(
                          width: 100,
                          // NOTE(tp): Even though the image's (PNG) data is available synchronously now, the decoding still happens asynchronously in the framework as multiple frames,
                          //           thus the UI minimally flickers initially as no explicit height is given here.
                          child: Image.file(File(storeFile.filepath)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'ID: ${storeFile.metadata.id}\n'
                            'Filepath: ${storeFile.filepath}\n'
                            'Fetched at: ${storeFile.metadata.fetchedAt}',
                          ),
                        )
                      ],
                    ),
                ],
              );
            },
          )
        ],
      ),
    );
  }

  void _updateDirectoryListing() {
    setState(() {
      baseDirectoryFiles = [
        for (final entry in Directory(baseDirectory)
            .listSync(recursive: true)
            .whereType<File>())
          entry.path,
      ];
    });
  }

  Future<(String, File)> fetchNewFile() async {
    final tempDirectory = await getApplicationCacheDirectory();

    final imageKey = DateTime.now().microsecondsSinceEpoch;

    final url = 'https://api.multiavatar.com/$imageKey.png';
    final response = await http.readBytes(Uri.parse(url));
    final file = await File.fromUri(
            tempDirectory.uri.resolve('./profile_image_$imageKey.png'))
        .writeAsBytes(response);

    return (url, file);
  }

  Future<void> _loadNewFile() async {
    final (url, file) = await fetchNewFile();

    fileStore!.write((
      metadata: ImageMetadata(
        id: DateTime.now().microsecondsSinceEpoch,
        fetchedAt: DateTime.now(),
        url: url,
      ),
      filepath: file.path
    ));

    _updateDirectoryListing();
  }

  Future<void> _updateFirstFile() async {
    final (url, file) = await fetchNewFile();

    fileStore!.write((
      metadata: ImageMetadata(
        id: storeFiles.value.first.metadata.id,
        fetchedAt: DateTime.now(),
        url: url,
      ),
      filepath: file.path
    ));

    _updateDirectoryListing();
  }

  void _deleteLast() {
    fileStore!.delete(key: storeFiles.value.last.metadata.id);

    _updateDirectoryListing();
  }

  @override
  void dispose() {
    storeFiles.dispose();
    database.dispose();

    super.dispose();
  }
}

class ImageMetadata {
  final int id;
  final DateTime fetchedAt;
  final String url;

  ImageMetadata({
    required this.id,
    required this.fetchedAt,
    required this.url,
  });

  // These would very likely be created by [json_serializable](https://pub.dev/packages/json_serializable)
  // or [freezed](https://pub.dev/packages/freezed) already for your models
  String toJSONString() {
    return jsonEncode({
      'id': id,
      'fetchedAt': fetchedAt.millisecondsSinceEpoch,
      'url': url,
    });
  }

  static ImageMetadata fromJSONString(String json) {
    final jsonData = jsonDecode(json);

    return ImageMetadata(
      id: jsonData['id'],
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(jsonData['fetchedAt']),
      url: jsonData['url'],
    );
  }
}
