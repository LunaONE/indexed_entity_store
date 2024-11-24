#!/bin/sh

set +x

fvm flutter run --release -d macos ./perf/write_many.dart
