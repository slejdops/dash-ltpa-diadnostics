# Quick Start Guide

## Immediate Problem Solving

If you're experiencing LTPA token, session, or performance issues right now, follow these steps:

## 1. Run the Diagnostic Script

```bash
# Make script executable (if not already)
chmod +x netcool-diagnostics.sh

# Run with root privileges for complete diagnostics
sudo ./netcool-diagnostics.sh

# Wait for completion (typically 2-5 minutes)
```

## 2. Review the Main Report

```bash
# Navigate to the output directory (timestamp-based)
cd netcool_diagnostics_YYYYMMDD_HHMMSS/

# Read the main diagnosis report
cat diagnosis_and_recommendations.txt
```

## 3. Quick Troubleshooting

### Problem: Users Being Logged Out / SSO Not Working

**Check:**
```bash
# Look at LTPA analysis
cat ltpa_analysis/ltpa_keys_analysis.txt
cat ltpa_analysis/ltpa_configuration.txt
```

**Common Fixes:**

1. **No LTPA keys found:**
   - Configure LTPA in WebSphere Admin Console
   - Security → Global security → Authentication → LTPA
   - Generate keys and export to all servers

2. **Different keys on different servers:**
   - Identify the primary server
   - Export LTPA keys from primary
   - Import to all other servers
   - Restart all servers

3. **Clock synchronization issues:**
   ```bash
   # Check system time
   date

   # Install and configure NTP
   sudo yum install ntp         # RHEL/CentOS
   sudo systemctl enable ntpd
   sudo systemctl start ntpd

   # Verify sync
   ntpq -p
   ```

### Problem: Poor GUI Performance

**Check:**
```bash
# Review performance metrics
cat performance/performance_metrics.txt
cat performance/webgui_performance.txt
```

**Common Fixes:**

1. **High Memory Usage (>80%):**
   - Increase JVM heap size
   - Edit: `$WAS_HOME/profiles/*/config/cells/*/nodes/*/servers/*/server.xml`
   - Look for: `-Xmx` parameter
   - Recommended: `-Xmx4096m` or higher

2. **Thread Pool Exhaustion:**
   - WebSphere Admin Console
   - Servers → Application servers → [server] → Thread pools
   - Increase WebContainer thread pool max size

3. **Database Connection Issues:**
   - Check connection pool sizes
   - Review database response times
   - Optimize slow queries

### Problem: Session Loss / Data Loss

**Check:**
```bash
# Review session configuration
cat ltpa_analysis/session_management.txt
```

**Common Fixes:**

1. **Session Timeout Too Short:**
   - Edit web.xml in application
   - Increase `<session-timeout>` value (minutes)
   - Default: 30, Recommended: 60-120

2. **No Session Persistence:**
   - Enable session database in WebSphere
   - Servers → Application servers → [server] → Session management
   - Enable "Enable database persistence"

3. **Load Balancer Issues:**
   - Configure sticky sessions
   - Ensure session affinity is enabled
   - Use persistent cookies for session tracking

## 4. Check Error Logs

```bash
# Review log analysis for specific errors
cat logs/error_analysis.txt

# Look for LTPA errors
grep -i "ltpa" logs/*.log.tail

# Look for session errors
grep -i "session" logs/*.log.tail

# Look for authentication errors
grep -i "authentication\|auth.*fail" logs/*.log.tail
```

## 5. Immediate Actions Checklist

Use this checklist to resolve common issues:

### LTPA Token Issues
- [ ] LTPA keys exist on all servers
- [ ] LTPA keys are identical across all servers
- [ ] Server clocks are synchronized (NTP configured)
- [ ] LTPA timeout is appropriate (default 120 min)
- [ ] Cookie domain is correctly configured
- [ ] SSL/HTTPS is properly configured

### Session Management
- [ ] Session timeout is appropriate
- [ ] Session persistence is enabled (if HA required)
- [ ] Load balancer has sticky sessions enabled
- [ ] Session database is accessible (if used)
- [ ] Session memory is not exhausted

### Performance
- [ ] Memory usage < 80%
- [ ] JVM heap size is appropriate
- [ ] Thread pools are not exhausted
- [ ] Database connections are available
- [ ] No excessive garbage collection
- [ ] Disk I/O is not bottlenecked

## 6. WebSphere Admin Console Quick Fixes

### To Configure LTPA:

1. Log into WebSphere Admin Console
2. Navigate to: **Security → Global security**
3. Under Authentication:
   - Click **LTPA**
   - Set timeout (e.g., 120 minutes)
   - Click **Apply**
4. Generate keys:
   - Click **LTPA** in breadcrumb
   - Set password
   - Click **Generate Keys**
   - Save configuration
5. Export keys:
   - Enter file name: `/tmp/ltpa.keys`
   - Enter password
   - Click **Export keys**
6. Copy keys to all servers:
   ```bash
   scp /tmp/ltpa.keys server2:/tmp/
   ```
7. Import keys on other servers:
   - WebSphere Admin Console on other servers
   - Security → Global security → LTPA
   - Enter file name and password
   - Click **Import keys**
8. Restart all servers

### To Increase JVM Heap:

1. WebSphere Admin Console
2. Navigate to: **Servers → Server Types → WebSphere application servers**
3. Click your server name
4. Under Server Infrastructure:
   - Click **Java and Process Management**
   - Click **Process definition**
   - Click **Java Virtual Machine**
5. Modify heap sizes:
   - Initial heap size: `1024` MB
   - Maximum heap size: `4096` MB (adjust based on available RAM)
6. Click **Apply** and **Save**
7. Restart server

### To Configure Session Persistence:

1. WebSphere Admin Console
2. Navigate to: **Servers → Server Types → WebSphere application servers**
3. Click your server name
4. Under Container Settings:
   - Click **Session management**
   - Click **Distributed environment settings**
5. Enable persistence:
   - Select **Enable database persistence**
   - Configure datasource
6. Click **Apply** and **Save**
7. Restart server

## 7. Command-Line Quick Fixes

### Restart WebSphere Services:

```bash
# Stop server
cd $WAS_HOME/profiles/[profile]/bin
./stopServer.sh server1 -username admin -password [password]

# Start server
./startServer.sh server1

# Check status
./serverStatus.sh -all
```

### Clear WebSphere Cache:

```bash
cd $WAS_HOME/profiles/[profile]/temp
rm -rf *

cd $WAS_HOME/profiles/[profile]/wstemp
rm -rf *

# Restart server after clearing cache
```

### Verify LTPA Keys:

```bash
# Find LTPA key files
find / -name "ltpa.keys" 2>/dev/null

# Compare checksums across servers
md5sum /path/to/ltpa.keys

# Keys should have identical checksums on all servers
```

### Monitor Real-Time Performance:

```bash
# Monitor Java processes
top -p $(pgrep -d',' java)

# Monitor memory
watch -n 1 free -h

# Monitor connections
watch -n 1 "netstat -an | grep ESTABLISHED | wc -l"

# Monitor logs for errors
tail -f $WAS_HOME/profiles/*/logs/*/SystemOut.log | grep -i error
```

## 8. When to Escalate

Escalate to IBM Support if:

- [ ] LTPA keys configured but SSO still not working
- [ ] Performance issues persist after tuning
- [ ] Frequent OutOfMemory errors even after heap increase
- [ ] Database connection pool completely exhausted
- [ ] Unexplained crashes or hung processes
- [ ] Security vulnerabilities identified

Include diagnostic archive when opening support ticket:
```bash
# Archive is automatically created
ls -lh netcool_diagnostics_*.tar.gz

# Copy to safe location
cp netcool_diagnostics_*.tar.gz /backup/location/
```

## 9. Preventive Measures

After resolving immediate issues:

1. **Schedule Regular Diagnostics:**
   ```bash
   # Add to crontab
   0 2 * * 0 /path/to/netcool-diagnostics.sh --skip-sensitive
   ```

2. **Monitor Key Metrics:**
   - Set up monitoring for memory usage
   - Alert on high CPU usage
   - Monitor session counts
   - Track authentication failures

3. **Document Configuration:**
   - Keep copy of ltpa.keys in secure location
   - Document all configuration changes
   - Maintain change log

4. **Regular Maintenance:**
   - Weekly log review
   - Monthly performance analysis
   - Quarterly capacity planning
   - Annual security audits

## 10. Getting Help

### Script Issues
- Check file permissions
- Verify paths with `--was-home` etc.
- Run with `--verbose` for detailed output
- Check script output in log file

### WebSphere Issues
- Review IBM Knowledge Center
- Check WebSphere documentation
- Search IBM Support forums
- Open PMR with IBM Support

### Need More Details?
See the full README.md for comprehensive documentation.

## Quick Reference: Common Paths

```bash
# WebSphere
WAS_HOME=/opt/IBM/WebSphere/AppServer
PROFILE=/opt/IBM/WebSphere/AppServer/profiles/AppSrv01

# JazzSM
JAZZSM_HOME=/opt/IBM/JazzSM

# Netcool WebGUI
WEBGUI_HOME=/opt/IBM/tivoli/netcool/webgui

# Common Logs
SYSTEMOUT=$PROFILE/logs/server1/SystemOut.log
SYSTEMERR=$PROFILE/logs/server1/SystemErr.log

# LTPA Keys
LTPA_KEYS=$PROFILE/config/cells/*/security/ltpa.keys

# Configuration
SECURITY_XML=$PROFILE/config/cells/*/security.xml
SERVER_XML=$PROFILE/config/cells/*/nodes/*/servers/*/server.xml
```

## Emergency Contacts

Keep these handy:

- WebSphere Admin: _______________________
- Database Admin: _______________________
- Network Admin: _______________________
- IBM Support: https://www.ibm.com/mysupport
- Internal Helpdesk: _______________________

---

**Remember:** Always test configuration changes in non-production first!
