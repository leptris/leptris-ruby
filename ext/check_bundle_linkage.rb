# frozen_string_literal: true

# Linkage contract for shipped native layers (#1739 / ruby#481): a
# Ruby extension resolves rb_* symbols from the LOADING interpreter,
# so the artifact must never link libruby — mkmf records the
# building ruby's absolute path (setup-ruby's hostedtoolcache
# location), which dlopen-fails on every other machine and silently
# degrades the whole install to FFI. On darwin the check is
# stricter: every load command must stay inside the loader
# allowlist. Windows PE DLLs are exempt — binding the build
# runtime is the documented contract there (#227).
#
# Runnable as a script over any number of artifacts (exit 1 on the
# first violated contract batch) or required for the pure checks in
# spec/check_bundle_linkage_spec.rb.
module CheckBundleLinkage
  ALLOWED_PREFIXES = %w[@rpath/ @loader_path/ @executable_path/ /usr/lib/ /System/].freeze

  # The LC_LOAD_DYLIB paths otool -L lists that fall outside the
  # allowlist. +otool_output+ is the raw stdout of `otool -L <file>`;
  # entries are the tab-indented "<install name> (compatibility
  # version X, current version Y)" lines.
  def self.load_command_violations(otool_output)
    otool_output.lines.grep(/^\t.*\(compatibility version/)
                .filter_map { |l| l.split.first }
                .reject { |path| ALLOWED_PREFIXES.any? { |p| path.start_with?(p) } }
  end

  # The libruby sonames a strings(1) dump reveals — the ELF-side
  # tripwire for DT_NEEDED entries and RUNPATH spellings alike.
  def self.libruby_references(strings_output)
    strings_output.scan(/libruby[\w.]*/).uniq
  end
end

if $PROGRAM_NAME == __FILE__
  require "shellwords"

  status = 0
  ARGV.each do |path|
    next if path.end_with?(".dll")

    bad = CheckBundleLinkage.libruby_references(`strings #{Shellwords.escape(path)} 2>/dev/null`)
    unless bad.empty?
      warn "ERROR: #{path} references #{bad.join(', ')} — Ruby symbols must " \
           "resolve from the loading interpreter, never a linked libruby " \
           "(#1739); link with -undefined dynamic_lookup / plain -shared"
      status = 1
    end
    next unless RUBY_PLATFORM.include?("darwin")

    viol = CheckBundleLinkage.load_command_violations(`otool -L #{Shellwords.escape(path)} 2>/dev/null`)
    next if viol.empty?

    warn "ERROR: #{path} carries load commands outside the loader " \
         "allowlist (#{CheckBundleLinkage::ALLOWED_PREFIXES.join(' ')}): " \
         "#{viol.join(', ')} (#1739)"
    status = 1
  end
  exit status
end
