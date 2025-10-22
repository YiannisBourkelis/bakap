# termiNAS v1.0.0-alpha.2 Release Notes

**Release Date**: October 23, 2025  
**Release Type**: Alpha (Experimental)

## ⚠️ Important Notice

This is an **alpha release** intended for testing purposes only. While functional, termiNAS has not been extensively tested in production environments. Always maintain independent backups of critical data.

## 🚀 What's New in Alpha 2

This release focuses on **performance optimization** of the `manage_users.sh` management tool, with dramatic speed improvements for environments with many snapshots.

### Performance Improvements

#### Massively Faster Snapshot Size Calculations
- **7-20x performance improvement** for `list` and `info` commands
- Optimized snapshot size calculations using single-pass `find` processing
- Created reusable `get_snapshots_logical_size()` function for better code maintainability

**Before vs After Performance:**

| Snapshots | Before | After | Speedup |
|-----------|--------|-------|---------|
| 100 | ~10-15s | ~1-2s | **7-10x** |
| 500 | ~60s | ~3-5s | **12-20x** |
| 1000+ | Minutes | ~5-10s | **Massive!** |

**Technical Details:**
- Replaced inefficient per-snapshot `while` loop with single `find` command
- Used built-in `-printf` instead of external `stat` processes
- Stream processing with awk instead of repeated `bc` invocations
- No subshell overhead - everything in a single efficient pipeline

#### Fixed Connection Status Display
- **Resolved "Last SFTP" showing "Never" bug** in `manage_users.sh list` command
- Fixed bash subshell issue preventing `CONNECTION_CACHE` array persistence
- Changed from pipe (`|`) to process substitution (`< <(...)`) to maintain parent shell context
- Made awk scripts compatible with both GNU awk and mawk for broader system support

#### Optimized Connection Cache Building
- **Improved `build_connection_cache()` performance**: ~8 seconds → ~1-2 seconds
- Replaced inefficient log parsing loops with optimized awk single-pass processing
- Added epoch timestamp caching to avoid redundant `date` command invocations
- Reduced overall `list` command execution time for better user experience

## 📦 Installation

**New Installation:**
```bash
git clone https://github.com/YiannisBourkelis/terminas.git
cd terminas
sudo ./src/server/setup.sh
```

**Upgrade from Alpha 1:**
```bash
cd /path/to/terminas
git pull origin main
# No additional steps needed - scripts are backward compatible
```

## 🐛 Known Issues

Same as Alpha 1:
- Limited testing on non-Debian systems
- Samba/SMB support is optional and requires manual testing
- Time Machine support is new and may have edge cases
- Windows client requires PowerShell 2.0+ (Windows Server 2008 R2+)

## 📚 Documentation

- **README.md**: Complete setup and usage guide
- **CHANGELOG.md**: Detailed change history
- **CONTRIBUTING.md**: Guidelines for contributors
- **PROJECT_REQUIREMENTS.md**: Original project scope

## 🔗 Resources

- **Repository**: https://github.com/YiannisBourkelis/terminas
- **Issues**: https://github.com/YiannisBourkelis/terminas/issues
- **License**: MIT License

## 🙏 Feedback

As an alpha release, your feedback is crucial! Please report:
- Bugs and issues on GitHub
- Performance problems
- Feature requests
- Documentation improvements

**Testing Checklist:**
- ✅ `manage_users.sh list` now executes much faster with many snapshots
- ✅ "Last SFTP" column displays actual connection times
- ✅ `manage_users.sh info <username>` completes quickly even with 500+ snapshots
- ⏳ All other functionality remains unchanged and stable

## 📝 Full Changelog

See [CHANGELOG.md](CHANGELOG.md) for complete details.

---

**Thank you for testing termiNAS!** 🎉
