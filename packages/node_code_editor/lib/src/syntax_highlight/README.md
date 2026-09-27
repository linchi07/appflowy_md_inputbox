# Vendored syntax rules

The parser core and the 47 selected language definitions in this directory
come from `highlight` 0.7.0, the Dart port of highlight.js:
https://github.com/pd4d10/highlight.dart

The Dart port is MIT licensed; see [LICENSE](LICENSE). Its source is derived
from highlight.js, which uses BSD 3-Clause; see
[HIGHLIGHT_JS_LICENSE](HIGHLIGHT_JS_LICENSE). The grammar files are generated
by the upstream project. We replaced the parser’s `collection` helper with Dart’s
`Iterable.firstOrNull` and limited language registration to the selected set.
No unrelated language files or Flutter highlighting widgets are included.
