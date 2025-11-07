#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DIAGNOSTIC_SCRIPT="$REPO_ROOT/netcool-diagnostics.sh"

TESTS_PASSED=0
TESTS_FAILED=0

log_test() {
    echo "=========================================="
    echo "TEST: $1"
    echo "=========================================="
}

log_pass() {
    echo "✓ PASS: $1"
    ((TESTS_PASSED++))
}

log_fail() {
    echo "✗ FAIL: $1"
    ((TESTS_FAILED++))
}

cleanup() {
    if [ -n "$TEST_FIXTURE" ] && [ -d "$TEST_FIXTURE" ]; then
        rm -rf "$TEST_FIXTURE"
    fi
    if [ -n "$TEST_OUTPUT" ] && [ -d "$TEST_OUTPUT" ]; then
        rm -rf "$TEST_OUTPUT"
    fi
}

trap cleanup EXIT

create_test_fixture() {
    TEST_FIXTURE=$(mktemp -d)
    TEST_OUTPUT=$(mktemp -d)
    
    mkdir -p "$TEST_FIXTURE/opt/IBM/WebSphere/AppServer/profiles/AppSrv01/config/cells/cell01/security"
    mkdir -p "$TEST_FIXTURE/opt/IBM/WebSphere/AppServer/profiles/AppSrv01/logs/server1"
    mkdir -p "$TEST_FIXTURE/opt/IBM/WebSphere/AppServer/profiles/AppSrv01/logs/server1/ffdc"
    mkdir -p "$TEST_FIXTURE/opt/IBM/JazzSM/logs"
    mkdir -p "$TEST_FIXTURE/opt/IBM/tivoli/netcool/webgui/logs"
    mkdir -p "$TEST_FIXTURE/app1/WEB-INF"
    mkdir -p "$TEST_FIXTURE/app2/WEB-INF"
    
    cat > "$TEST_FIXTURE/opt/IBM/WebSphere/AppServer/profiles/AppSrv01/config/cells/cell01/security/ltpa.keys" << 'EOF'
com.ibm.websphere.ltpa.version=1.0
com.ibm.websphere.ltpa.3DESKey=AAABBBCCCDDDEEEFFF
com.ibm.websphere.ltpa.PrivateKey=XXXYYYZZZAAABBBCCC
com.ibm.websphere.ltpa.PublicKey=PPPQQQRRRSSSTTTUUU
EOF
    
    cat > "$TEST_FIXTURE/opt/IBM/WebSphere/AppServer/profiles/AppSrv01/config/cells/cell01/security/security.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<security:Security xmlns:security="http://www.ibm.com/websphere/appserver/schemas/5.0/security.xmi">
    <authMechanisms xmi:type="security:LTPA" xmi:id="LTPA_1" timeout="120" keysFileName="ltpa.keys">
        <singleSignOn enabled="true" domain=".example.com" requiresSSL="true"/>
    </authMechanisms>
</security:Security>
EOF
    
    cat > "$TEST_FIXTURE/app1/WEB-INF/web.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<web-app>
    <session-config>
        <session-timeout>45</session-timeout>
    </session-config>
</web-app>
EOF
    
    cat > "$TEST_FIXTURE/app2/WEB-INF/web.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<web-app>
    <session-config>
        <session-timeout>15</session-timeout>
    </session-config>
</web-app>
EOF
    
    cat > "$TEST_FIXTURE/opt/IBM/WebSphere/AppServer/profiles/AppSrv01/logs/server1/SystemOut.log" << 'EOF'
[2024-01-15 10:00:00] INFO: Server started
[2024-01-15 10:05:00] ERROR: LTPA token validation failed
[2024-01-15 10:10:00] WARN: Session timeout occurred
[2024-01-15 10:15:00] ERROR: Authentication failed for user admin
EOF
    
    cat > "$TEST_FIXTURE/opt/IBM/WebSphere/AppServer/profiles/AppSrv01/logs/server1/ffdc/exception_001.log" << 'EOF'
Exception: OutOfMemoryError
Stack trace follows...
EOF
    
    echo "Test fixture created at: $TEST_FIXTURE"
}

test_basic_execution() {
    log_test "Basic script execution with test fixture"
    
    create_test_fixture
    
    bash "$DIAGNOSTIC_SCRIPT" \
        --root "$TEST_FIXTURE" \
        --output-dir "$TEST_OUTPUT/diag1" \
        --skip-sensitive \
        --no-default-excludes \
        > /dev/null 2>&1
    
    if [ -f "$TEST_OUTPUT/diag1/diagnosis_and_recommendations.txt" ]; then
        log_pass "diagnosis_and_recommendations.txt created"
    else
        log_fail "diagnosis_and_recommendations.txt not created"
    fi
    
    if [ -f "$TEST_OUTPUT/diag1/diagnostic_report.log" ]; then
        log_pass "diagnostic_report.log created"
    else
        log_fail "diagnostic_report.log not created"
    fi
}

test_ltpa_key_detection() {
    log_test "LTPA key file detection"
    
    create_test_fixture
    
    bash "$DIAGNOSTIC_SCRIPT" \
        --root "$TEST_FIXTURE" \
        --output-dir "$TEST_OUTPUT/diag2" \
        --skip-sensitive \
        --no-default-excludes \
        > /dev/null 2>&1
    
    if [ -f "$TEST_OUTPUT/diag2/ltpa_analysis/ltpa_keys_analysis.txt" ]; then
        if grep -q "ltpa.keys" "$TEST_OUTPUT/diag2/ltpa_analysis/ltpa_keys_analysis.txt"; then
            log_pass "LTPA key file detected"
        else
            log_fail "LTPA key file not detected in analysis"
        fi
    else
        log_fail "ltpa_keys_analysis.txt not created"
    fi
}

test_session_timeout_detection() {
    log_test "Session timeout detection and policy check"
    
    create_test_fixture
    
    bash "$DIAGNOSTIC_SCRIPT" \
        --root "$TEST_FIXTURE" \
        --output-dir "$TEST_OUTPUT/diag3" \
        --no-default-excludes \
        > /dev/null 2>&1
    
    if [ -f "$TEST_OUTPUT/diag3/ltpa_analysis/session_management.txt" ]; then
        if grep -q "session-timeout" "$TEST_OUTPUT/diag3/ltpa_analysis/session_management.txt"; then
            log_pass "Session timeout detected"
        else
            log_fail "Session timeout not detected"
        fi
        
        if grep -q "WARNING.*15 min.*below recommended minimum" "$TEST_OUTPUT/diag3/ltpa_analysis/session_management.txt"; then
            log_pass "Session timeout policy violation detected (15 min < 30 min)"
        else
            log_fail "Session timeout policy violation not detected"
        fi
    else
        log_fail "session_management.txt not created"
    fi
}

test_log_collection() {
    log_test "Log collection including ffdc directories"
    
    create_test_fixture
    
    bash "$DIAGNOSTIC_SCRIPT" \
        --root "$TEST_FIXTURE" \
        --output-dir "$TEST_OUTPUT/diag4" \
        --no-default-excludes \
        > /dev/null 2>&1
    
    if [ -f "$TEST_OUTPUT/diag4/logs/SystemOut.log.tail" ]; then
        log_pass "SystemOut.log collected"
    else
        log_fail "SystemOut.log not collected"
    fi
    
    if [ -d "$TEST_OUTPUT/diag4/logs" ] && find "$TEST_OUTPUT/diag4/logs" -name "*ffdc*" | grep -q .; then
        log_pass "FFDC directory collected"
    else
        log_fail "FFDC directory not collected"
    fi
}

test_error_analysis() {
    log_test "Log error analysis"
    
    create_test_fixture
    
    bash "$DIAGNOSTIC_SCRIPT" \
        --root "$TEST_FIXTURE" \
        --output-dir "$TEST_OUTPUT/diag5" \
        --no-default-excludes \
        > /dev/null 2>&1
    
    if [ -f "$TEST_OUTPUT/diag5/logs/error_analysis.txt" ]; then
        if grep -q "LTPA token validation failed" "$TEST_OUTPUT/diag5/logs/error_analysis.txt"; then
            log_pass "LTPA error detected in analysis"
        else
            log_fail "LTPA error not detected in analysis"
        fi
    else
        log_fail "error_analysis.txt not created"
    fi
}

test_checksum_grouping() {
    log_test "LTPA key checksum grouping"
    
    create_test_fixture
    
    mkdir -p "$TEST_FIXTURE/opt/IBM/WebSphere/AppServer/profiles/AppSrv02/config/cells/cell02/security"
    cp "$TEST_FIXTURE/opt/IBM/WebSphere/AppServer/profiles/AppSrv01/config/cells/cell01/security/ltpa.keys" \
       "$TEST_FIXTURE/opt/IBM/WebSphere/AppServer/profiles/AppSrv02/config/cells/cell02/security/ltpa.keys"
    
    bash "$DIAGNOSTIC_SCRIPT" \
        --root "$TEST_FIXTURE" \
        --output-dir "$TEST_OUTPUT/diag6" \
        --no-default-excludes \
        > /dev/null 2>&1
    
    if [ -f "$TEST_OUTPUT/diag6/ltpa_analysis/ltpa_keys_analysis.txt" ]; then
        if grep -q "SHA256 Checksum" "$TEST_OUTPUT/diag6/ltpa_analysis/ltpa_keys_analysis.txt"; then
            log_pass "LTPA key checksums calculated"
        else
            log_fail "LTPA key checksums not calculated"
        fi
        
        if grep -q "All LTPA key files have matching checksums" "$TEST_OUTPUT/diag6/ltpa_analysis/ltpa_keys_analysis.txt"; then
            log_pass "Matching LTPA keys detected correctly"
        else
            log_fail "Matching LTPA keys not detected"
        fi
    else
        log_fail "ltpa_keys_analysis.txt not created"
    fi
}

test_time_sync_check() {
    log_test "Time synchronization check"
    
    create_test_fixture
    
    bash "$DIAGNOSTIC_SCRIPT" \
        --root "$TEST_FIXTURE" \
        --output-dir "$TEST_OUTPUT/diag7" \
        --no-default-excludes \
        > /dev/null 2>&1
    
    if [ -f "$TEST_OUTPUT/diag7/system_info/time_synchronization.txt" ]; then
        log_pass "Time synchronization check performed"
    else
        log_fail "time_synchronization.txt not created"
    fi
}

echo "========================================"
echo "Running Diagnostic Script Tests"
echo "========================================"
echo ""

test_basic_execution
test_ltpa_key_detection
test_session_timeout_detection
test_log_collection
test_error_analysis
test_checksum_grouping
test_time_sync_check

echo ""
echo "========================================"
echo "Test Results Summary"
echo "========================================"
echo "Tests Passed: $TESTS_PASSED"
echo "Tests Failed: $TESTS_FAILED"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
