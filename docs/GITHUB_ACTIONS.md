# GitHub Actions CI/CD Setup

## Overview

Taurus uses GitHub Actions for continuous integration, testing, and automated releases across multiple platforms and Ruby versions.

## Workflows

### 1. CI/CD Workflow (`.github/workflows/main.yml`)

**Triggers:**
- Push to `main` branch
- Pull requests
- Manual dispatch

**Features:**
- Multi-platform testing (Ubuntu x64/ARM64, macOS Intel/Apple Silicon)
- Multiple Ruby versions (3.0, 3.1, 3.2, 3.3, 3.4)
- Matrix-based configuration from `matrix.json`
- C extension compilation
- Ruby (RSpec) and C (Google Test) unit tests
- Performance benchmarks
- RuboCop linting
- Artifact collection

**Jobs:**
1. `load-matrix` - Loads platform/Ruby combinations from matrix.json
2. `test` - Runs full test suite on all matrix configurations
3. `benchmark` - Performance benchmarks on Ubuntu and macOS
4. `lint` - Code quality checks with RuboCop
5. `all-checks` - Verifies all tests passed

### 2. Release Workflow (`.github/workflows/release.yml`)

**Triggers:**
- Push of version tags (`v*`)
- Manual dispatch with version input

**Features:**
- Cross-platform native gem building
- Automated GitHub releases
- RubyGems.org publication
- Installation verification

**Jobs:**
1. `build-native-gems` - Builds native gems for:
   - x86_64-linux (Ubuntu 20.04+)
   - x86_64-darwin (Intel Macs)
   - arm64-darwin (Apple Silicon)

2. `build-source-gem` - Builds source gem for other platforms

3. `create-release` - Creates GitHub release with:
   - All gem files
   - SHA256 checksums
   - Release notes

4. `publish-rubygems` - Publishes to RubyGems.org

5. `verify-release` - Tests installation from RubyGems on multiple platforms

## Matrix Configuration

The `matrix.json` file defines all platform/Ruby combinations for testing:

```json
[
  {
    "runner": "ubuntu-22.04",
    "os": "ubuntu",
    "arch": "x64",
    "ruby": "3.3",
    "name": "ubuntu-22-ruby-3.3"
  },
  ...
]
```

**Supported Platforms:**
- Ubuntu 22.04 (x64, ARM64)
- macOS 13 (Intel)
- macOS latest (Apple Silicon)

**Ruby Versions:**
- 3.0, 3.1, 3.2, 3.3, 3.4

## Setup Requirements

### For CI/CD

No additional setup required - workflows run automatically on push/PR.

### For Releases

Required GitHub secrets:
- `RUBYGEMS_API_KEY` - API key for publishing to RubyGems.org

**To set up:**
1. Get API key from https://rubygems.org/profile/edit
2. Go to repository Settings → Secrets and variables → Actions
3. Add new secret named `RUBYGEMS_API_KEY`

## Creating a Release

### Automatic (Recommended)

1. Update version in `lib/taurus/version.rb`
2. Update `CHANGELOG.md`
3. Commit changes: `git commit -m "chore: bump version to X.Y.Z"`
4. Create and push tag:
   ```bash
   git tag v0.1.0
   git push origin v0.1.0
   ```
5. GitHub Actions automatically:
   - Builds native gems
   - Creates GitHub release
   - Publishes to RubyGems
   - Verifies installation

### Manual Dispatch

1. Go to Actions → Release workflow
2. Click "Run workflow"
3. Enter version (e.g., `0.1.0`)
4. Click "Run workflow"

## Artifacts

### Test Artifacts

Each test run produces:
- Compiled native extensions (`.so`/`.bundle` files)
- SHA256 checksums
- Retention: 30 days

### Release Artifacts

Each release includes:
- Source gem (all platforms)
- Native gems (Linux x64, macOS x64, macOS ARM64)
- Combined SHA256 checksums
- Retention: Permanent (GitHub release)

## Monitoring

### Build Status

Check build status:
- Badge on README.md
- Actions tab in GitHub repository
- Email notifications (if configured)

### Performance Tracking

Benchmark artifacts available for:
- Ubuntu latest
- macOS latest

Download from Actions → Workflow run → Artifacts

## Troubleshooting

### Build Failures

**C Extension Won't Compile:**
```bash
# Local reproduction:
bundle exec rake clean
bundle exec rake compile
```

**Test Failures:**
```bash
# Run tests locally:
bundle exec rake spec  # Ruby tests
bundle exec rake test_c  # C tests
```

**Cross-compilation Issues:**
- Check rake-compiler-dock is latest version
- Verify extconf.rb lists all source files
- Check for platform-specific #ifdef code

### Release Failures

**Native Gem Build Fails:**
- Check rake-compiler-dock logs
- Verify source files compile on target platform
- Test locally with Docker:
  ```bash
  bundle exec rake-compiler-dock bash
  ```

**RubyGems Publication Fails:**
- Verify `RUBYGEMS_API_KEY` secret is set
- Check gem name isn't already taken
- Ensure version number is unique

**Verification Fails:**
- Wait longer (gem indexing lag)
- Check if gem published successfully
- Verify gem installs manually:
  ```bash
  gem install taurus -v X.Y.Z
  ```

## Best Practices

### Before Merging PRs

- Ensure all tests pass
- Check benchmark results for regressions
- Review RuboCop warnings
- Test on multiple platforms if changing C code

### Before Releasing

1. Run full test suite locally
2. Update CHANGELOG.md
3. Bump version number
4. Test installation from local gem:
   ```bash
   gem build taurus.gemspec
   gem install taurus-X.Y.Z.gem
   ```
5. Create tag and push

### Maintaining Matrix

When adding platforms:
1. Add to `matrix.json`
2. Test locally if possible
3. Monitor first CI run
4. Update documentation

When deprecating Ruby:
1. Remove from `matrix.json`
2. Update README.md
3. Update gemspec `required_ruby_version`

## Performance Considerations

### CI Speed

Average runtime:
- Test job: 5-10 minutes per platform
- Benchmark: 10-15 minutes per platform
- Total (parallel): ~15-20 minutes

### Release Speed

Average runtime:
- Build gems: ~10 minutes (parallel)
- Create release: ~2 minutes
- Publish: ~5 minutes
- Verify: ~10 minutes
- Total: ~30 minutes

## Future Enhancements

### Planned

- Windows support (MSYS2/MinGW)
- Additional ARM64 platforms
- Performance trend tracking
- Code coverage reporting
- Security scanning (Dependabot, CodeQL)

### Under Consideration

- Nightly builds with latest Ruby
- Cross-Ruby compatibility matrix
- Memory profiling in CI
- Benchmark comparison vs. Nokogiri/Ox

## Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [ruby/setup-ruby Action](https://github.com/ruby/setup-ruby)
- [rake-compiler Documentation](https://github.com/rake-compiler/rake-compiler)
- [RubyGems API Documentation](https://guides.rubygems.org/rubygems-org-api/)

## Support

For CI/CD issues:
1. Check Actions logs
2. Search existing GitHub issues
3. Create new issue with:
   - Workflow run URL
   - Platform/Ruby version
   - Error messages
   - Steps to reproduce
