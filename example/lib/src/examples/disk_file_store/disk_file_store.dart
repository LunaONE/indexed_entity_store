import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:indexed_entity_store/indexed_entity_store.dart';

typedef FileWithMetadata<T> = ({T metadata, String filepath});

class DiskFileStore<
    // Metadata
    T,
    // Primary key
    K> {
  late final IndexedEntityStore<FileWithMetadata<T>, K> _store;

  final String _baseDirectory;

  final String _entityKey;

  final K Function(T) _getPrimaryKey;

  DiskFileStore(
    IndexedEntityDabase database, {
    required String entityKey,

    /// The base directory where files from this connector are stored
    ///
    /// Files are stored in subfolders like `$metadataId/$originalFilename` in order to preserver the filename and extension for e.g. sharing
    ///
    /// If a given file is outside of this directory, a copy will be created inside this structure.
    /// Any previously existing file will be removed.
    required String baseDirectory,
    required K Function(T) getPrimaryKey,
    required void Function(IndexCollector<FileWithMetadata<T>> index)
        getIndices,
    required String Function(T) serializeMetadata,
    required T Function(String) deserializeMetadata,
  })  : _baseDirectory = baseDirectory,
        _entityKey = entityKey,
        _getPrimaryKey = getPrimaryKey {
    _store = database.entityStore(
      _DiskFileConnector<T, K>(
        entityKey,
        getPrimaryKey,
        getIndices,
        serializeMetadata,
        deserializeMetadata,
      ),
    );
  }

  QueryResult<FileWithMetadata<T>?> read(K key) {
    return _store.read(key);
  }

  /// Writes the file + metadata to the store
  ///
  /// If needed, it copies the file to the entries directory, so that the store has its own copy of the data.
  /// It is valid to the outside to modify this file in-place, without needed to update the store on every modification.
  ///
  /// Any previous files attached to this entry (under the same or different file name) are removed upon insert.
  void write(FileWithMetadata<T> e) {
    final entityDirectoryPath = Uri.directory(_baseDirectory)
        .resolve('./$_entityKey/${_getPrimaryKey(e.metadata)}/');
    final entityDirectory = Directory.fromUri(entityDirectoryPath);

    var filePath = e.filepath;

    // If file exists outside desired storage dir, copy it in
    if (!e.filepath.startsWith(
        entityDirectoryPath.toFilePath(windows: Platform.isWindows))) {
      entityDirectory.createSync(recursive: true);

      filePath = File(e.filepath)
          .copySync(entityDirectoryPath
              .resolve('./${Uri.parse(e.filepath).pathSegments.last}')
              .toFilePath(windows: Platform.isWindows))
          .path;

      debugPrint('Copied file from ${e.filepath} to $filePath');
    }

    for (final existingFile in entityDirectory.listSync().whereType<File>()) {
      if (existingFile.path != filePath) {
        debugPrint('Deleting previous file $existingFile');
        existingFile.deleteSync();
      }
    }

    return _store.write((metadata: e.metadata, filepath: filePath));
  }

  void delete({
    required K key,
  }) {
    final existingEntry = _store.readOnce(key);
    if (existingEntry != null) {
      File(existingEntry.filepath).deleteSync();

      _store.delete(key: key);
    }
  }

  QueryResult<List<FileWithMetadata<T>>> query({
    QueryBuilder? where,
    OrderByClause? orderBy,
    int? limit,
  }) {
    return _store.query(
      where: where,
      orderBy: orderBy,
      limit: limit,
    );
  }
}

class _DiskFileConnector<T, K>
    implements IndexedEntityConnector<FileWithMetadata<T>, K, Uint8List> {
  _DiskFileConnector(
    this.entityKey,
    this._getPrimaryKey,
    this._getIndices,
    this._serialize,
    this._deserialize,
  );

  @override
  final String entityKey;

  final K Function(T) _getPrimaryKey;

  final void Function(IndexCollector<FileWithMetadata<T>> index) _getIndices;

  final String Function(T) _serialize;

  final T Function(String) _deserialize;

  @override
  K getPrimaryKey(FileWithMetadata<T> e) => _getPrimaryKey(e.metadata);

  @override
  Uint8List serialize(FileWithMetadata<T> e) {
    final serializedMetadata =
        const Utf8Encoder().convert(_serialize(e.metadata));
    final serializedFilepath = const Utf8Encoder().convert(e.filepath);

    final lengthHeader = Uint8List.view(
      // uint32 is enough for 4GB of metadata
      (ByteData(4)..setUint32(0, serializedMetadata.length)).buffer,
    );

    return (BytesBuilder(copy: false)
          ..add(lengthHeader)
          ..add(serializedMetadata)
          ..add(serializedFilepath))
        .takeBytes();
  }

  @override
  FileWithMetadata<T> deserialize(Uint8List s) {
    final metaDataLength = ByteData.view(s.buffer).getUint32(0);

    final metadata = _deserialize(const Utf8Decoder()
        .convert(Uint8List.view(s.buffer, 4, metaDataLength)));
    final filepath = const Utf8Decoder()
        .convert(Uint8List.view(s.buffer, 4 + metaDataLength));

    return (
      metadata: metadata,
      filepath: filepath,
    );
  }

  @override
  void getIndices(IndexCollector<FileWithMetadata<T>> index) {
    index((e) => e.filepath, as: '_internal_filepath', unique: true);
    _getIndices(index);
  }
}
