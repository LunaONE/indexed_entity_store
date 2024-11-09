import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:indexed_entity_store/indexed_entity_store.dart';
import 'package:indexed_entity_store_example/src/stores/database_helper.dart';
import 'package:value_listenable_extensions/value_listenable_extensions.dart';

class BinaryDataStorageExample extends StatefulWidget {
  const BinaryDataStorageExample({
    super.key,
  });

  @override
  State<BinaryDataStorageExample> createState() =>
      _BinaryDataStorageExampleState();
}

class _BinaryDataStorageExampleState extends State<BinaryDataStorageExample> {
  final database = getNewDatabase();

  late final simpleRepository = SimpleImageRepository(
    store: database.entityStore(plainImageConnector),
  );
  late final withMetadataRepository = ImageWithMetadataRepository(
    store: database.entityStore(imageWithMetadataConnector),
  );

  late var simpleImage = simpleRepository.getImage();
  late var metadataImage = withMetadataRepository.getImage();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Shows 2 approaches of how to store binary data. Press the refresh button to re-init, loading the images anew from memory.',
        ),
        const SizedBox(height: 20),
        CupertinoButton.filled(
          onPressed: _reInit,
          child: const Text('Re-init'),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Simple binary storage',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                ValueListenableBuilder(
                  valueListenable: simpleImage,
                  builder: (context, image, _) {
                    if (image == null) {
                      return const CupertinoActivityIndicator();
                    }

                    return SizedBox(
                      width: 100,
                      // NOTE(tp): Even though the image's (PNG) data is available synchronously now, the decoding still happens asynchronously in the framework as multiple frames,
                      //           thus the UI minimally flickers initially as no explicit height is given here.
                      child: Image.memory(image),
                    );
                  },
                ),
                const SizedBox(height: 20),
                const Text(
                  'Binary storage with metadata prefix',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                ValueListenableBuilder(
                  valueListenable: metadataImage,
                  builder: (context, image, _) {
                    if (image == null) {
                      return const CupertinoActivityIndicator();
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 100,
                          child: Image.memory(image.data),
                        ),
                        Text(
                          'Fetched at ${image.metadata.fetchedAt}\nfrom ${image.metadata.url}',
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    simpleImage.dispose();
    metadataImage.dispose();

    database.dispose();

    super.dispose();
  }

  void _reInit() {
    setState(() {
      simpleImage.dispose();
      simpleImage = simpleRepository.getImage();

      metadataImage.dispose();
      metadataImage = withMetadataRepository.getImage();
    });
  }
}

/// Shows how to straightforwardly store binary data
///
/// This is generally only advisable when no meta-data is needed, and the users know the key needed to access the items afterwards (as they can not be retrieved with the connector's current `deserialize` interface)
class SimpleImageRepository {
  final PlainImageStore _simpleStore;

  SimpleImageRepository({
    required PlainImageStore store,
  }) : _simpleStore = store;

  DisposableValueListenable<Uint8List?> getImage() {
    const imageKey = 'profile_picture';

    final data = _simpleStore.read(imageKey).transform((r) => r?.data);

    if (data.value == null) {
      debugPrint('ImageRepository: Fetching image from network');
      // Fetch the data from the network if we don't have it yet
      http
          .readBytes(Uri.parse('https://api.multiavatar.com/$imageKey.png'))
          .then((response) {
        _simpleStore.write((key: imageKey, data: response));
      });
    } else {
      debugPrint('ImageRepository: Using stored image');
    }

    return data;
  }
}

typedef PlainImageStore = IndexedEntityStore<ImageRow, String>;

typedef ImageRow = ({String key, Uint8List data});

/// Connector which stores a plain image (or any binary data) by key
final plainImageConnector = IndexedEntityConnector<ImageRow, String, List<int>>(
  entityKey: 'plain_image',
  getPrimaryKey: (t) => t.key,
  getIndices: (index) {},
  serialize: (t) => t.data,
  // TODO(tp): In this example the key is not returned, which just shows the need to have support for additional meta-data which is shown in the second connector
  deserialize: (s) => (key: '', data: Uint8List.fromList(s)),
);

/// Shows how to store binary data with meta data
class ImageWithMetadataRepository {
  final ImageWithMetadataStore _store;

  ImageWithMetadataRepository({
    required ImageWithMetadataStore store,
  }) : _store = store;

  DisposableValueListenable<ImageWithMetadata?> getImage() {
    const imageId = 12345678;

    final data = _store.read(imageId);

    if (data.value == null ||
        data.value!.metadata.fetchedAt
            .isBefore(DateTime.now().subtract(const Duration(seconds: 10)))) {
      debugPrint('ImageWithMetadataRepository: Fetching image from network');

      final url =
          'https://api.multiavatar.com/${DateTime.now().millisecondsSinceEpoch}.png';

      // Fetch the data from the network if we don't have it yet
      http.readBytes(Uri.parse(url)).then((response) {
        _store.write((
          metadata: ImageMetadata(
            id: imageId,
            fetchedAt: DateTime.now(),
            url: url,
          ),
          data: response
        ));
      });
    } else {
      debugPrint('ImageWithMetadataRepository: Using stored image');
    }

    return data;
  }
}

typedef ImageWithMetadataStore = IndexedEntityStore<ImageWithMetadata, int>;

typedef ImageWithMetadata = ({ImageMetadata metadata, Uint8List data});

final imageWithMetadataConnector =
    IndexedEntityConnector<ImageWithMetadata, int, Uint8List>(
  entityKey: 'metadata_image',
  getPrimaryKey: (t) => t.metadata.id,
  getIndices: (index) {
    index((t) => t.metadata.fetchedAt, as: 'fetchedAt');
  },
  serialize: (t) {
    final metadataJSON = JsonUtf8Encoder().convert(t.metadata.toJSON());

    final lengthHeader = Uint8List.view(
      // uint32 is enough for 4GB of metadata
      (ByteData(4)..setUint32(0, metadataJSON.length)).buffer,
    );

    return (BytesBuilder(copy: false)
          ..add(lengthHeader)
          ..add(metadataJSON)
          ..add(t.data))
        .takeBytes();
  },
  deserialize: (s) {
    final metaDataLength = ByteData.view(s.buffer).getUint32(0);

    // This creates a more efficient UTF8 JSON Decoder internally (https://stackoverflow.com/a/79158945)
    final jsonDecoder = const Utf8Decoder().fuse(const JsonDecoder());
    final metaData = ImageMetadata.fromJSON(
      jsonDecoder.convert(Uint8List.view(s.buffer, 4, metaDataLength))
          as Map<String, dynamic>,
    );

    return (
      metadata: metaData,

      // Assuming that the binary data is much bigger than the meta-data,
      // this a view in the underlying storage and doesn't copy it out (this could be made adaptive, to
      // copy when the binary data is actually less than e.g. half of the bytes)
      data: Uint8List.view(s.buffer, 4 + metaDataLength).asUnmodifiableView(),
    );
  },
);

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
  Map<String, dynamic> toJSON() {
    return {
      'id': id,
      'fetchedAt': fetchedAt.millisecondsSinceEpoch,
      'url': url,
    };
  }

  static ImageMetadata fromJSON(Map<String, dynamic> json) {
    return ImageMetadata(
      id: json['id'],
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(json['fetchedAt']),
      url: json['url'],
    );
  }
}

// TODO(tp): Write abstraction for "binary with metadata" store
