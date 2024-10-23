## Indexed Entity Store

`IndexedEntityStore` offers fast, *synchronous* persistent data storage for Flutter applications.

* 💨 Fast: Optimized for both data access and development speed.
  * Use hot-reload instead of code generation and writing manual schema migrations.
  * All queries use indices, so data access is always instantaneous.
* ⚡️ Reactive: Every read from the store is reactive by default, so your application can update whenever the underlying data changes.
* 📖 Simple: Offers a handful of easy-to-use APIs, and strives for a straightforward implementation of only a few hundred lines of codes.

It's first and foremost goal is developer productivity while developing[^1]. Most applications a few thousand or less entities of each types, and if access to these is done via indexed queries, there is no need to make even the simplest data update `async`. Furthermore no manual mapping from entity to "rows" is needed. Just use `toJson`/`fromJson` methods which likely already exists on the typed[^2].

The library itself is developed in the [Berkeley style](https://www.cs.princeton.edu/courses/archive/fall13/cos518/papers/worse-is-better.pdf), meaning that the goal is to make it practially nice to use and also keep the implementation straighforward and small. While this might prevent some nice-to-have features in the best case, it also prevents the worst case meaning that development is slowing down as the code is too entrenched or abandoned and can not be easily migrated.

Because this library uses SQLite synchronously in the same thread, one can easily mix SQL and Dart code with virtually no overhead, which wouldn't be advisable in an `async` database setup (not least due to the added complexity that stuff could've chagned between statement). This means the developer can write simpler, more reusable queries and keep complex logic in Dart[^3].

[^1]: This means there is no code generation, manual migrations for schema updates, and other roadblocks. Hat tip to [Blackbird](https://github.com/marcoarment/Blackbird) to bringing this into focus.
[^2]: Or Protobuf, if you want to be strictly backwards compatible by default.
[^3]: https://www.sqlite.org/np1queryprob.html
