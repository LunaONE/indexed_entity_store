import 'package:flutter/foundation.dart';
import 'package:riverpod/riverpod.dart' show AsyncValue;
import 'package:value_listenable_extensions/value_listenable_extensions.dart';

extension FutureToValueListenable<T> on Future<T> {
  /// Return a `DisposableValueListenable` which `value` contains the current state of the `Future`
  DisposableValueListenable<AsyncValue<T>> asAsyncValue() {
    final value = ValueNotifier<AsyncValue<T>>(AsyncValue.loading());

    then((result) => value.value = AsyncValue.data(result));
    catchError((e, s) => value.value = AsyncValue.error(e!, s));

    return ValueListenableView(
      value,
      dispose: () {
        value.dispose();
      },
    );
  }
}
