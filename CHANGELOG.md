## 1.1.0

* Adds reactivity
  - Callers now get notified for every update to their queries
  - All queries are now reactive by default, so queries can be composed without missing any updates. This is highly useful unless the synchronizations happens on a higher application layer, in which case the `*Once` methods can be used.

## 1.0.0

* Initial release.
