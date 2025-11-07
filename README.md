# Tivoli Netcool DASH/JazzSM/WebGUI Diagnostic Tool

A comprehensive bash script for diagnosing issues with IBM Tivoli Netcool DASH, JazzSM, and WebGUI stack, with special focus on LTPA token configuration, user sessions, and GUI performance.

## Overview

This diagnostic tool collects system information, analyzes configurations, and helps identify issues related to:

- **LTPA Token Configuration**: Key files, security settings, cookie configuration
- **User Session Management**: Session persistence, timeouts, and affinity
- **GUI Performance**: Resource usage, thread pools, caching, and bottlenecks
- **Log Analysis**: Automatic error detection and pattern matching

## Features

### Core Diagnostics

- **System Information Collection**
  - OS details, CPU, memory, disk space
  - Network configuration
  - Running processes and ports

- **LTPA Token Analysis**
  - LTPA key file detection and validation
  - Security.xml configuration analysis
  - Cookie configuration review
  - SSO setup verification

- **Session Management**
  - Session configuration analysis
  - Session timeout settings
  - Session persistence configuration
  - Session manager settings

- **Performance Metrics**
  - CPU and memory usage
  - Disk I/O statistics
  - Network statistics
  - Java heap analysis
  - Thread pool status
  - Connection counts

- **Log Collection & Analysis**
  - Automatic log file discovery
  - Error pattern detection
  - LTPA-specific error identification
  - Session and authentication errors
  - Performance issue detection

### Output

The script generates a comprehensive diagnostic package including:

- System information reports
- LTPA configuration analysis
- Session management analysis
- Performance metrics
- Log excerpts and error analysis
- Configuration file copies
- Diagnosis and recommendations report

## Requirements

### System Requirements

- Linux/Unix system
- Bash 4.0 or higher
- Root or administrative privileges (recommended for full diagnostics)

### Optional Tools

These tools enhance the diagnostic output but are not required:

- `iostat` - for I/O statistics
- `lsof` - for open files and connections
- `jstat` - for Java heap statistics
- `netstat` or `ss` - for network statistics

## Installation

1. Download the script:
```bash
wget https://raw.githubusercontent.com/your-repo/netcool-diagnostics.sh
# or
curl -O https://raw.githubusercontent.com/your-repo/netcool-diagnostics.sh
```

2. Make it executable:
```bash
chmod +x netcool-diagnostics.sh
```

3. Run with appropriate permissions:
```bash
sudo ./netcool-diagnostics.sh
```

## Usage

### Basic Usage

Run with default settings:
```bash
sudo ./netcool-diagnostics.sh
```

### Command Line Options

```bash
./netcool-diagnostics.sh [OPTIONS]

OPTIONS:
    -h, --help                  Show help message
    -v, --verbose               Enable verbose output
    -f, --full-logs             Collect full log files (default: last 1000 lines)
    -s, --skip-sensitive        Skip collecting sensitive information
    --exclude-dirs DIRS         Comma-separated list of directories to exclude from scanning
    --no-default-excludes       Don't use default directory exclusions
    --dash-home PATH            Set DASH home directory
    --webgui-home PATH          Set WebGUI home directory
    --jazzsm-home PATH          Set JazzSM home directory
    --was-home PATH             Set WebSphere home directory
```

**Default Excluded Directories:**

By default, the following directories are excluded from scanning to improve performance:
- `/proc` - Process information
- `/sys` - System information
- `/dev` - Device files
- `/run` - Runtime data
- `/tmp` - Temporary files
- `/var/tmp` - Temporary files
- `/boot` - Boot files
- `/mnt` - Mount points
- `/media` - Removable media

### Examples

**Standard diagnostic run:**
```bash
sudo ./netcool-diagnostics.sh
```

**Verbose output with full logs:**
```bash
sudo ./netcool-diagnostics.sh --verbose --full-logs
```

**Custom installation paths:**
```bash
sudo ./netcool-diagnostics.sh \
  --was-home /opt/IBM/WebSphere/AppServer \
  --jazzsm-home /opt/IBM/JazzSM \
  --webgui-home /opt/IBM/tivoli/netcool/webgui
```

**Skip sensitive data:**
```bash
sudo ./netcool-diagnostics.sh --skip-sensitive
```

**Exclude additional directories:**
```bash
# Exclude backup and archive directories
sudo ./netcool-diagnostics.sh --exclude-dirs "/backup,/archive,/old"

# Exclude home directories to focus on system files
sudo ./netcool-diagnostics.sh --exclude-dirs "/home"
```

**Scan everything (no exclusions):**
```bash
# Warning: This may take a very long time and find many irrelevant files
sudo ./netcool-diagnostics.sh --no-default-excludes
```

**Combine options:**
```bash
# Fast scan excluding large directories
sudo ./netcool-diagnostics.sh \
  --exclude-dirs "/backup,/data/archives" \
  --skip-sensitive \
  --verbose
```

## Default Paths

The script uses these default paths (can be overridden with options):

- **DASH_HOME**: `/opt/IBM/JazzSM/profile/bin`
- **WEBGUI_HOME**: `/opt/IBM/tivoli/netcool/webgui`
- **JAZZSM_HOME**: `/opt/IBM/JazzSM`
- **WAS_HOME**: `/opt/IBM/WebSphere/AppServer`

You can also set these as environment variables before running:

```bash
export WAS_HOME=/custom/path/to/websphere
export JAZZSM_HOME=/custom/path/to/jazzsm
./netcool-diagnostics.sh
```

## Output Structure

The script creates a timestamped directory with the following structure:

```
netcool_diagnostics_YYYYMMDD_HHMMSS/
├── diagnostic_report.log           # Main execution log
├── diagnosis_and_recommendations.txt  # Summary and recommendations
├── system_info/
│   ├── system_overview.txt         # System details
│   ├── processes.txt               # Running processes
│   └── listening_ports.txt         # Network ports
├── ltpa_analysis/
│   ├── ltpa_configuration.txt      # LTPA config analysis
│   ├── ltpa_keys_analysis.txt      # Key file analysis
│   ├── cookie_configuration.txt    # Cookie settings
│   └── session_management.txt      # Session config
├── performance/
│   ├── performance_metrics.txt     # System metrics
│   └── webgui_performance.txt      # WebGUI specific
├── logs/
│   ├── logs_summary.txt            # Log file locations
│   ├── error_analysis.txt          # Error patterns
│   └── *.log.tail                  # Log excerpts
└── config/
    └── [various config files]      # Copied configurations
```

A compressed archive is also created: `netcool_diagnostics_YYYYMMDD_HHMMSS.tar.gz`

## Interpreting Results

### Main Report

Start with `diagnosis_and_recommendations.txt` for:
- Summary of findings
- Identified issues
- Recommended actions
- Common LTPA problems and solutions

### LTPA Token Issues

Check `ltpa_analysis/` directory for:

1. **Missing LTPA keys**: No ltpa.keys files found
   - Action: Configure LTPA in WebSphere Admin Console
   - Generate and export LTPA keys

2. **Key mismatches**: Multiple different key files
   - Action: Synchronize LTPA keys across all servers
   - Use the same ltpa.keys file cluster-wide

3. **Cookie problems**: Domain or path misconfigurations
   - Action: Review cookie domain settings
   - Ensure proper cookie path configuration

4. **Clock skew**: Time synchronization issues
   - Action: Configure NTP on all servers
   - Verify system clocks are synchronized

### Session Issues

Review `ltpa_analysis/session_management.txt` for:

- Session timeout configurations
- Session persistence settings
- Session database configuration
- Session replication status

### Performance Problems

Analyze `performance/` directory for:

- High memory usage (>80%)
- CPU bottlenecks
- Thread pool exhaustion
- Connection pool issues
- Disk I/O problems

## Common Issues and Solutions

### Issue 1: LTPA Token Not Working

**Symptoms:**
- Users logged out unexpectedly
- SSO not working between applications
- Authentication errors in logs

**Diagnostic Steps:**
1. Check if LTPA keys exist: `ltpa_analysis/ltpa_keys_analysis.txt`
2. Verify key synchronization across servers
3. Review cookie configuration
4. Check for clock synchronization issues

**Solutions:**
- Generate and configure LTPA keys in WebSphere
- Copy ltpa.keys to all servers in the cluster
- Adjust LTPA timeout settings
- Synchronize server clocks with NTP

### Issue 2: Session Loss

**Symptoms:**
- Users lose session data
- Frequent re-authentication required
- Session-related errors in logs

**Diagnostic Steps:**
1. Review `ltpa_analysis/session_management.txt`
2. Check session timeout values
3. Verify session persistence configuration
4. Review load balancer session affinity

**Solutions:**
- Increase session timeout if too short
- Enable session database persistence
- Configure sticky sessions on load balancer
- Enable session replication for HA

### Issue 3: Poor GUI Performance

**Symptoms:**
- Slow page loads
- Timeouts
- High resource usage

**Diagnostic Steps:**
1. Review `performance/performance_metrics.txt`
2. Check memory usage and heap settings
3. Analyze thread pool configuration
4. Review `performance/webgui_performance.txt`

**Solutions:**
- Increase JVM heap size if needed
- Tune thread pool sizes
- Enable caching where appropriate
- Optimize database connection pools
- Review and optimize queries

### Issue 4: Clock Synchronization

**Symptoms:**
- LTPA validation failures
- Intermittent SSO issues
- Time-based token errors

**Diagnostic Steps:**
1. Check system time on all servers
2. Review NTP configuration
3. Look for time skew in logs

**Solutions:**
```bash
# Install and configure NTP
sudo yum install ntp    # RHEL/CentOS
sudo apt-get install ntp  # Ubuntu/Debian

# Configure NTP
sudo systemctl enable ntpd
sudo systemctl start ntpd

# Verify synchronization
ntpq -p
```

## Troubleshooting the Script

### Permission Denied Errors

If you see permission denied errors:
```bash
# Run with sudo
sudo ./netcool-diagnostics.sh

# Or run as root
su -
./netcool-diagnostics.sh
```

### Commands Not Found

If optional tools are missing:
```bash
# RHEL/CentOS
sudo yum install sysstat net-tools lsof

# Ubuntu/Debian
sudo apt-get install sysstat net-tools lsof
```

### Custom Paths

If your installation uses non-standard paths:
```bash
# Find your installation
find / -name "server.xml" 2>/dev/null
find / -name "ltpa.keys" 2>/dev/null

# Use custom paths
./netcool-diagnostics.sh --was-home /your/path/to/websphere
```

## Best Practices

1. **Regular Diagnostics**: Run monthly or after configuration changes
2. **Baseline Collection**: Create a baseline when system is healthy
3. **Archive Results**: Keep diagnostic archives for trend analysis
4. **Review Regularly**: Check recommendations and implement fixes
5. **Document Changes**: Note configuration changes and their impact

## Performance Tips

### Speeding Up Diagnostics

The diagnostic script scans the entire filesystem by default, which can be time-consuming on large systems. Here are ways to improve performance:

**1. Use Directory Exclusions**

The script excludes common system directories by default (`/proc`, `/sys`, `/dev`, etc.). Add more exclusions for large, irrelevant directories:

```bash
# Exclude backup directories
sudo ./netcool-diagnostics.sh --exclude-dirs "/backup,/archive"

# Exclude multiple large directories
sudo ./netcool-diagnostics.sh --exclude-dirs "/backup,/archive,/data/old,/mnt/storage"
```

**2. Focus on Specific Directories**

If you know where your WebSphere installation is, you can significantly speed up the scan by excluding everything else:

```bash
# Only scan IBM directories (exclude most of the filesystem)
sudo ./netcool-diagnostics.sh --exclude-dirs "/home,/var/lib,/usr/share,/usr/local"
```

**3. Skip Full Log Collection**

By default, only the last 1000 lines of each log are collected. This is usually sufficient. Avoid `--full-logs` unless necessary:

```bash
# Fast scan with tail logs only (default)
sudo ./netcool-diagnostics.sh
```

**4. Skip Sensitive Data Collection**

If you don't need detailed LTPA key information:

```bash
sudo ./netcool-diagnostics.sh --skip-sensitive
```

### Typical Scan Times

- **Default scan** (with exclusions): 2-5 minutes
- **No exclusions** (`--no-default-excludes`): 10-30 minutes (depending on disk size)
- **With additional exclusions**: 1-3 minutes

### What Gets Excluded

When using `--exclude-dirs`, the script will:
- Skip searching in those directories entirely
- Improve performance significantly
- May miss configuration files in excluded directories

**Recommendation**: Start with default exclusions, then add more if needed based on your environment.

## Security Considerations

- The script collects configuration files that may contain sensitive information
- Use `--skip-sensitive` flag to limit sensitive data collection
- Protect diagnostic archives (they contain configuration details)
- Review collected data before sharing with support
- Clean up diagnostic archives when no longer needed

## Integration with Monitoring

Consider scheduling periodic diagnostics:

```bash
# Add to crontab for weekly execution
0 2 * * 0 /path/to/netcool-diagnostics.sh --skip-sensitive

# Or create a wrapper script for automated runs
#!/bin/bash
/path/to/netcool-diagnostics.sh > /var/log/netcool-diagnostics-$(date +\%Y\%m\%d).log 2>&1
```

## Support and Resources

### IBM Documentation

- [IBM WebSphere Application Server Documentation](https://www.ibm.com/docs/en/was)
- [IBM Tivoli Netcool/OMNIbus Documentation](https://www.ibm.com/docs/en/netcoolomnibus)
- [IBM Jazz for Service Management Documentation](https://www.ibm.com/docs/en/jazz-sm)

### Common Log Locations

- WebSphere: `$WAS_HOME/profiles/*/logs/*/SystemOut.log`
- JazzSM: `$JAZZSM_HOME/logs/`
- WebGUI: `$WEBGUI_HOME/logs/`

### Key Configuration Files

- LTPA Keys: `*/security/ltpa.keys`
- Security Config: `*/config/cells/*/security.xml`
- Server Config: `*/config/cells/*/nodes/*/servers/*/server.xml`

## Contributing

If you have improvements or suggestions:
1. Test your changes thoroughly
2. Document new features
3. Follow the existing code style
4. Submit detailed pull requests

## License

This tool is provided as-is for diagnostic purposes.

## Changelog

### Version 2.0.0 (2025-11-07)
- **Major Enhancement Release**: Comprehensive improvements and new diagnostic capabilities
- **Fixed `run_find()` function**: Removed eval, now uses proper arrays for safer execution
- **LTPA Key Checksum Analysis**: Automatically detects and groups LTPA keys by SHA256 checksum
  - Identifies key mismatches across servers that cause SSO failures
  - Provides detailed synchronization recommendations
  - Detects stale keys (>365 days old by default)
- **Time Synchronization Check**: New NTP/Chrony status verification
  - Detects clock skew that causes LTPA validation failures
  - Supports timedatectl, ntpq, and chronyc
  - Configurable offset threshold (default: 500ms)
- **Session Timeout Policy Checks**: Automatic validation against configurable thresholds
  - Flags timeouts below 30 minutes (frequent logouts)
  - Flags timeouts above 240 minutes (security risk)
  - Extracts and analyzes session-timeout values from web.xml
- **Improved Log Collection**: Fixed ffdc directory handling
  - Properly copies ffdc directories recursively
  - Separates file and directory handling
  - Prevents "Is a directory" errors
- **New CLI Options**:
  - `--output-dir PATH`: Specify custom output directory
  - `--root PATH`: Limit filesystem search for faster diagnostics and testing
- **Enhanced Error Handling**:
  - Added trap for cleanup on interruption
  - Improved connection counting (safe_count_connections)
  - Better command availability detection
- **Redaction Framework**: Enhanced --skip-sensitive mode
  - Redacts passwords, secrets, tokens in configurations
  - Safer for automated/scheduled runs
- **Test Harness**: New fixture-based test suite in tests/run_tests.sh
  - 7 comprehensive tests covering all major features
  - Validates LTPA detection, session analysis, log collection
  - Enables regression testing
- **Code Quality Improvements**:
  - Fixed critical shellcheck warnings
  - Improved quoting and variable handling
  - Better separation of concerns
- **Policy Thresholds**: Configurable via script variables
  - LTPA_KEY_AGE_THRESHOLD_DAYS (default: 365)
  - SESSION_TIMEOUT_MIN (default: 30)
  - SESSION_TIMEOUT_MAX (default: 240)
  - NTP_OFFSET_THRESHOLD_MS (default: 500)

### Version 1.1.1 (2025-11-06)
- **Critical Bug Fix**: Fixed `run_find()` function that was preventing file discovery
- Security.xml and other configuration files now properly found in all directories
- Simplified find command exclusion logic from complex parentheses to standard prune syntax
- Removed unused `build_find_exclude_params()` function
- Verified fix with comprehensive testing across multiple file locations

### Version 1.1.0 (2025-11-06)
- Added `--exclude-dirs` option to exclude directories from scanning
- Added `--no-default-excludes` option to scan all directories
- Default exclusions for `/proc`, `/sys`, `/dev`, `/run`, `/tmp`, `/var/tmp`, `/boot`, `/mnt`, `/media`
- Improved performance with selective directory scanning
- Updated documentation with performance tips

### Version 1.0.0 (2025-11-06)
- Initial release
- LTPA token diagnostics
- Session management analysis
- Performance metrics collection
- Log analysis and error detection
- Automated recommendations

## Author

Generated for Tivoli Netcool diagnostics

## Disclaimer

This diagnostic tool is provided for troubleshooting purposes. Always review collected data before sharing. The tool does not make any changes to your system configuration.
