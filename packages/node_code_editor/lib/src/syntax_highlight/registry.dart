// Curated grammar registry based on highlight.dart 0.7.0.
// Upstream license and provenance are in LICENSE and README.md.
import 'src/highlight.dart';
import 'src/mode.dart';
import 'languages/bash.dart' as bash;
import 'languages/clojure.dart' as clojure;
import 'languages/cmake.dart' as cmake;
import 'languages/cpp.dart' as cpp;
import 'languages/cs.dart' as cs;
import 'languages/css.dart' as css;
import 'languages/dart.dart' as dart;
import 'languages/diff.dart' as diff;
import 'languages/dockerfile.dart' as dockerfile;
import 'languages/elixir.dart' as elixir;
import 'languages/erlang.dart' as erlang;
import 'languages/go.dart' as go;
import 'languages/gradle.dart' as gradle;
import 'languages/graphql.dart' as graphql;
import 'languages/groovy.dart' as groovy;
import 'languages/haskell.dart' as haskell;
import 'languages/http.dart' as http;
import 'languages/ini.dart' as ini;
import 'languages/java.dart' as java;
import 'languages/javascript.dart' as javascript;
import 'languages/json.dart' as json;
import 'languages/julia.dart' as julia;
import 'languages/kotlin.dart' as kotlin;
import 'languages/less.dart' as less;
import 'languages/lua.dart' as lua;
import 'languages/makefile.dart' as makefile;
import 'languages/markdown.dart' as markdown;
import 'languages/nginx.dart' as nginx;
import 'languages/objectivec.dart' as objectivec;
import 'languages/perl.dart' as perl;
import 'languages/php.dart' as php;
import 'languages/powershell.dart' as powershell;
import 'languages/protobuf.dart' as protobuf;
import 'languages/python.dart' as python;
import 'languages/r.dart' as r;
import 'languages/ruby.dart' as ruby;
import 'languages/rust.dart' as rust;
import 'languages/scala.dart' as scala;
import 'languages/scss.dart' as scss;
import 'languages/sql.dart' as sql;
import 'languages/swift.dart' as swift;
import 'languages/tex.dart' as tex;
import 'languages/typescript.dart' as typescript;
import 'languages/vim.dart' as vim;
import 'languages/vue.dart' as vue;
import 'languages/xml.dart' as xml;
import 'languages/yaml.dart' as yaml;

final Map<String, Mode> codeLanguageModes = {
  'bash': bash.bash,
  'clojure': clojure.clojure,
  'cmake': cmake.cmake,
  'cpp': cpp.cpp,
  'cs': cs.cs,
  'css': css.css,
  'dart': dart.dart,
  'diff': diff.diff,
  'dockerfile': dockerfile.dockerfile,
  'elixir': elixir.elixir,
  'erlang': erlang.erlang,
  'go': go.go,
  'gradle': gradle.gradle,
  'graphql': graphql.graphql,
  'groovy': groovy.groovy,
  'haskell': haskell.haskell,
  'http': http.http,
  'ini': ini.ini,
  'java': java.java,
  'javascript': javascript.javascript,
  'json': json.json,
  'julia': julia.julia,
  'kotlin': kotlin.kotlin,
  'less': less.less,
  'lua': lua.lua,
  'makefile': makefile.makefile,
  'markdown': markdown.markdown,
  'nginx': nginx.nginx,
  'objectivec': objectivec.objectivec,
  'perl': perl.perl,
  'php': php.php,
  'powershell': powershell.powershell,
  'protobuf': protobuf.protobuf,
  'python': python.python,
  'r': r.r,
  'ruby': ruby.ruby,
  'rust': rust.rust,
  'scala': scala.scala,
  'scss': scss.scss,
  'sql': sql.sql,
  'swift': swift.swift,
  'tex': tex.tex,
  'typescript': typescript.typescript,
  'vim': vim.vim,
  'vue': vue.vue,
  'xml': xml.xml,
  'yaml': yaml.yaml,
};

final Set<String> codeLanguageIds = {
  for (final entry in codeLanguageModes.entries) ...{
    entry.key,
    ...?entry.value.aliases,
  },
};

final Highlight codeHighlight = Highlight()
  ..registerLanguages(codeLanguageModes);
