# leptris vs the field

The authoritative cross-library numbers live in the README's
Performance section (measured with metanorma/serialbench).

This local benchmark compares against Nokogiri only:

    LEPTRIS_LIB_PATH=/path/to/libleptris.dylib bundle exec ruby benchmark/leptris_vs_nokogiri.rb

For the full-field race (Ox, Nokogiri, Oga, REXML, Leptris), use
https://github.com/metanorma/serialbench — leptris's adapter ships
there under `lib/serialbench/serializers/xml/leptris_serializer.rb`.
