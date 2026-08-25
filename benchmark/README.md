# leptris vs the field

Two scripts, two questions:

- `read_paths.rb` — the binding's own hot paths (readonly read
  loops, SAX, NodeSet unions, css, parse-query-serialize).
  Machine-relative; run before/after any read-path change:

      bundle exec ruby benchmark/read_paths.rb

- `leptris_vs_nokogiri.rb` — cross-library comparison against
  Nokogiri only:

      LEPTRIS_LIB_PATH=/path/to/libleptris.dylib bundle exec ruby benchmark/leptris_vs_nokogiri.rb

For the full-field race (Ox, Nokogiri, Oga, REXML, Leptris), use
https://github.com/metanorma/serialbench — leptris's adapter ships
there under `lib/serialbench/serializers/xml/leptris_serializer.rb`.
