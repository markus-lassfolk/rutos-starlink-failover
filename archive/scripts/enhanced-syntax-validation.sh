#!/bin/sh
# Enhanced Syntax Validation for RUTOS Starlink Failover Project
# Version: 1.0.0
# Description: Additional syntax and structural validation tools to catch errors early
#
# This script provides enhanced validation capabilities beyond the main pre-commit script:
# - Shell syntax validation using multiple shells
# - Function brace matching and structure validation  
# - Variable usage validation
# - Missing function detection
# - Conditional block structure validation

set -e

# Version information
SCRIPT_VERSION="1.0.0"

# CRITICAL: Allow test execution for validation scripts
ALLOW_TEST_EXECUTION=1
export ALLOW_TEST_EXECUTION

# CRITICAL: Load RUTOS library system (REQUIRED)
. "$(dirname "$0")/lib/rutos-lib.sh"

# CRITICAL: Initialize script with library features (REQUIRED)
rutos_init "enhanced-syntax-validation.sh" "$SCRIPT_VERSION"

# Validation counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
SYNTAX_ERRORS=0
STRUCTURE_ERRORS=0
LOGIC_ERRORS=0

# === SHELL SYNTAX VALIDATION ===
# Check basic shell syntax using multiple shell parsers
validate_shell_syntax() {
    local file="$1"
    local errors_found=0
    
    log_info "🔍 Validating shell syntax: $file"
    
    # Test 1: POSIX shell syntax check
    log_debug "  Testing POSIX shell syntax..."
    if sh -n "$file" 2>/dev/null; then
        log_debug "  ✓ POSIX shell syntax valid"
    else
        local error_output
        error_output=$(sh -n "$file" 2>&1)
        log_error "  ❌ POSIX shell syntax error:"
        log_error "     $error_output"
        errors_found=$((errors_found + 1))
    fi
    
    # Test 2: Bash syntax check (if available)
    if command -v bash >/dev/null 2>&1; then
        log_debug "  Testing bash syntax compatibility..."
        if bash -n "$file" 2>/dev/null; then
            log_debug "  ✓ Bash syntax valid"
        else
            local error_output
            error_output=$(bash -n "$file" 2>&1)
            log_warning "  ⚠️ Bash syntax issue (may still be POSIX compatible):"
            log_warning "     $error_output"
        fi
    fi
    
    # Test 3: Busybox ash syntax check (if available)
    if command -v busybox >/dev/null 2>&1; then
        log_debug "  Testing busybox ash syntax..."
        if busybox ash -n "$file" 2>/dev/null; then
            log_debug "  ✓ Busybox ash syntax valid"
        else
            local error_output
            error_output=$(busybox ash -n "$file" 2>&1)
            log_warning "  ⚠️ Busybox ash syntax issue:"
            log_warning "     $error_output"
        fi
    fi
    
    return $errors_found
}

# === FUNCTION STRUCTURE VALIDATION ===
# Check for proper function definitions and brace matching
validate_function_structure() {
    local file="$1"
    local errors_found=0
    local line_num=0
    
    log_info "🔍 Validating function structure: $file"
    
    # Check for unmatched braces in functions
    local brace_stack=""
    local in_function=0
    local function_name=""
    
    while IFS= read -r line || [ -n "$line" ]; do
        line_num=$((line_num + 1))
        
        # Detect function definitions
        case "$line" in
            *"() {"*)
                function_name=$(echo "$line" | sed 's/()[[:space:]]*{.*//' | xargs)
                in_function=1
                brace_stack="${brace_stack}{"
                log_debug "  Found function: $function_name at line $line_num"
                ;;
            *"{"*)
                if [ "$in_function" = "1" ]; then
                    brace_stack="${brace_stack}{"
                fi
                ;;
            *"}"*)
                if [ "$in_function" = "1" ]; then
                    if [ -n "$brace_stack" ]; then
                        brace_stack="${brace_stack%?}"  # Remove last character
                        if [ -z "$brace_stack" ]; then
                            in_function=0
                            log_debug "  ✓ Function $function_name properly closed at line $line_num"
                        fi
                    else
                        log_error "  ❌ Unmatched closing brace at line $line_num"
                        errors_found=$((errors_found + 1))
                    fi
                fi
                ;;
        esac
    done < "$file"
    
    # Check for unclosed functions
    if [ -n "$brace_stack" ]; then
        log_error "  ❌ Unclosed function detected: $function_name"
        log_error "     Missing $(echo "$brace_stack" | wc -c) closing brace(s)"
        errors_found=$((errors_found + 1))
    fi
    
    return $errors_found
}

# === CONDITIONAL BLOCK VALIDATION ===
# Check for proper if/then/else/fi structure
validate_conditional_structure() {
    local file="$1"
    local errors_found=0
    local line_num=0
    
    log_info "🔍 Validating conditional structure: $file"
    
    local if_stack=""
    local case_stack=""
    
    while IFS= read -r line || [ -n "$line" ]; do
        line_num=$((line_num + 1))
        
        # Check if statements
        case "$line" in
            *"if "*)
                if_stack="${if_stack}if"
                log_debug "  Found 'if' at line $line_num"
                ;;
            *"then"*)
                # Should have corresponding 'if'
                if [ -z "$if_stack" ]; then
                    log_error "  ❌ 'then' without 'if' at line $line_num"
                    errors_found=$((errors_found + 1))
                fi
                ;;
            *"elif "*)
                # Should be inside an if block
                if [ -z "$if_stack" ]; then
                    log_error "  ❌ 'elif' without 'if' at line $line_num"
                    errors_found=$((errors_found + 1))
                fi
                ;;
            *"else"*)
                # Should be inside an if block (but not case/esac)
                if [ -z "$if_stack" ] && [ -z "$case_stack" ]; then
                    log_error "  ❌ 'else' without 'if' or 'case' at line $line_num"
                    errors_found=$((errors_found + 1))
                fi
                ;;
            *"fi"*)
                if [ -n "$if_stack" ]; then
                    if_stack="${if_stack%if}"  # Remove last 'if'
                    log_debug "  ✓ 'fi' closes 'if' at line $line_num"
                else
                    log_error "  ❌ 'fi' without 'if' at line $line_num"
                    errors_found=$((errors_found + 1))
                fi
                ;;
            *"case "*)
                case_stack="${case_stack}case"
                log_debug "  Found 'case' at line $line_num"
                ;;
            *"esac"*)
                if [ -n "$case_stack" ]; then
                    case_stack="${case_stack%case}"  # Remove last 'case'
                    log_debug "  ✓ 'esac' closes 'case' at line $line_num"
                else
                    log_error "  ❌ 'esac' without 'case' at line $line_num"
                    errors_found=$((errors_found + 1))
                fi
                ;;
        esac
    done < "$file"
    
    # Check for unclosed blocks
    if [ -n "$if_stack" ]; then
        log_error "  ❌ Unclosed 'if' statement(s) detected"
        errors_found=$((errors_found + 1))
    fi
    
    if [ -n "$case_stack" ]; then
        log_error "  ❌ Unclosed 'case' statement(s) detected"
        errors_found=$((errors_found + 1))
    fi
    
    return $errors_found
}

# === VARIABLE USAGE VALIDATION ===
# Check for undefined variables and common usage issues
validate_variable_usage() {
    local file="$1"
    local errors_found=0
    local line_num=0
    
    log_info "🔍 Validating variable usage: $file"
    
    # Check for potentially undefined variables (basic check)
    while IFS= read -r line || [ -n "$line" ]; do
        line_num=$((line_num + 1))
        
        # Look for variable references that might be undefined
        # This is a basic check - more sophisticated analysis would require parsing
        case "$line" in
            *'${*:-}'*)
                # Good - using default value syntax
                ;;
            *'${'*'}'*)
                # Extract variable name and check if it's likely undefined
                var_name=$(echo "$line" | sed 's/.*\${//; s/}.*//' | cut -d: -f1 | cut -d- -f1)
                
                # Skip common variables that are usually defined
                case "$var_name" in
                    ""|PATH|HOME|USER|PWD|OLDPWD|SHELL|"#"|"?"|"$"|"!"|"*"|"@")
                        ;;
                    [0-9]*)
                        # Positional parameters
                        ;;
                    *)
                        # Check if variable is defined earlier in the file
                        if ! grep -q "^[[:space:]]*$var_name=" "$file" && 
                           ! grep -q "export.*$var_name" "$file" &&
                           ! grep -q "read.*$var_name" "$file"; then
                            log_warning "  ⚠️ Potentially undefined variable: \$${var_name} at line $line_num"
                            log_warning "     Consider using \${${var_name}:-default} for safety"
                        fi
                        ;;
                esac
                ;;
        esac
    done < "$file"
    
    return $errors_found
}

# === FUNCTION CALL VALIDATION ===
# Check for calls to undefined functions
validate_function_calls() {
    local file="$1"
    local errors_found=0
    
    log_info "🔍 Validating function calls: $file"
    
    # Extract all function definitions
    local defined_functions
    defined_functions=$(grep -o '^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*()' "$file" | sed 's/[[:space:]]*//g; s/()//')
    
    # Extract all function calls (basic pattern)
    local line_num=0
    while IFS= read -r line || [ -n "$line" ]; do
        line_num=$((line_num + 1))
        
        # Look for function calls (words followed by space and arguments, not variable assignments)
        if echo "$line" | grep -q '[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]' && ! echo "$line" | grep -q '='; then
            # Extract potential function names
            for word in $line; do
                case "$word" in
                    [a-zA-Z_]*[a-zA-Z0-9_])
                        # Skip shell built-ins and common commands
                        case "$word" in
                            if|then|else|elif|fi|case|esac|for|while|until|do|done|function|return|exit|break|continue)
                                ;;
                            echo|printf|cat|grep|sed|awk|cut|sort|uniq|head|tail|wc|tr|test|"|"|"["|"]")
                                ;;
                            set|unset|export|readonly|local|shift|eval|exec|source|"|".|cd|pwd|mkdir|rmdir|rm|cp|mv|ln|chmod|chown)
                                ;;
                            command|type|which|hash|alias|unalias|jobs|fg|bg|kill|trap|wait|sleep|read)
                                ;;
                            true|false|"|":|date|uname|hostname|whoami|id|groups|umask)
                                ;;
                            *)
                                # Check if this function is defined in the file
                                if ! echo "$defined_functions" | grep -q "^$word$"; then
                                    # It might be from a library or external command
                                    if echo "$word" | grep -q '_' || echo "$word" | grep -q 'log_' || echo "$word" | grep -q 'rutos_'; then
                                        log_debug "  Library/external function call: $word at line $line_num"
                                    else
                                        log_warning "  ⚠️ Potential undefined function call: $word at line $line_num"
                                    fi
                                fi
                                ;;
                        esac
                        ;;
                esac
            done
        fi
    done < "$file"
    
    return $errors_found
}

# === MAIN VALIDATION FUNCTION ===
# Perform comprehensive syntax and structure validation
validate_file_comprehensive() {
    local file="$1"
    local total_errors=0
    
    log_step "Enhanced Syntax Validation: $file"
    
    # Skip non-shell files
    case "$file" in
        *.sh)
            ;;
        *)
            log_debug "Skipping non-shell file: $file"
            return 0
            ;;
    esac
    
    # Skip if file doesn't exist
    if [ ! -f "$file" ]; then
        log_warning "File not found: $file"
        return 1
    fi
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    # Run all validation checks
    log_info "Running enhanced syntax validation checks..."
    
    # 1. Shell syntax validation
    if validate_shell_syntax "$file"; then
        log_debug "✓ Shell syntax validation passed"
    else
        local syntax_errors=$?
        SYNTAX_ERRORS=$((SYNTAX_ERRORS + syntax_errors))
        total_errors=$((total_errors + syntax_errors))
        log_error "❌ Shell syntax validation failed with $syntax_errors errors"
    fi
    
    # 2. Function structure validation
    if validate_function_structure "$file"; then
        log_debug "✓ Function structure validation passed"
    else
        local structure_errors=$?
        STRUCTURE_ERRORS=$((STRUCTURE_ERRORS + structure_errors))
        total_errors=$((total_errors + structure_errors))
        log_error "❌ Function structure validation failed with $structure_errors errors"
    fi
    
    # 3. Conditional structure validation
    if validate_conditional_structure "$file"; then
        log_debug "✓ Conditional structure validation passed"
    else
        local conditional_errors=$?
        STRUCTURE_ERRORS=$((STRUCTURE_ERRORS + conditional_errors))
        total_errors=$((total_errors + conditional_errors))
        log_error "❌ Conditional structure validation failed with $conditional_errors errors"
    fi
    
    # 4. Variable usage validation (warnings only)
    validate_variable_usage "$file"
    
    # 5. Function call validation (warnings only)
    validate_function_calls "$file"
    
    if [ "$total_errors" -eq 0 ]; then
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        log_success "✅ Enhanced validation passed: $file"
        return 0
    else
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        log_error "❌ Enhanced validation failed: $file ($total_errors errors)"
        return $total_errors
    fi
}

# === USAGE INFORMATION ===
show_usage() {
    cat <<EOF
Enhanced Syntax Validation for RUTOS Starlink Failover Project

USAGE:
    $0 [OPTIONS] [FILES...]

OPTIONS:
    --help, -h              Show this help message
    --version, -v           Show version information
    --all                   Validate all shell scripts in the project
    --syntax-only           Only run shell syntax validation
    --structure-only        Only run structure validation
    --debug                 Enable debug output

EXAMPLES:
    $0 script.sh                           # Validate single file
    $0 script1.sh script2.sh              # Validate multiple files
    $0 --all                               # Validate all project shell scripts
    $0 --syntax-only --all                 # Only syntax check all scripts
    $0 --debug script.sh                   # Validate with debug output

This script provides enhanced validation beyond the main pre-commit validation:
- Shell syntax checking with multiple parsers (sh, bash, busybox)
- Function brace matching and structure validation
- Conditional block structure validation (if/fi, case/esac)
- Variable usage analysis
- Function call validation

Integration with main pre-commit validation:
- Run this script before the main pre-commit-validation.sh
- Use --all flag to validate the entire project
- Use specific checks (--syntax-only) for quick validation
EOF
}

# === MAIN EXECUTION ===
main() {
    local files=""
    local validate_all=0
    local syntax_only=0
    local structure_only=0
    
    # Parse command line arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --help|-h)
                show_usage
                exit 0
                ;;
            --version|-v)
                log_info "Enhanced Syntax Validation v$SCRIPT_VERSION"
                exit 0
                ;;
            --all)
                validate_all=1
                ;;
            --syntax-only)
                syntax_only=1
                ;;
            --structure-only)
                structure_only=1
                ;;
            --debug)
                DEBUG=1
                export DEBUG
                ;;
            -*)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                files="$files $1"
                ;;
        esac
        shift
    done
    
    # Determine files to validate
    if [ "$validate_all" = "1" ]; then
        log_info "Finding all shell scripts in the project..."
        files=$(find . -name "*.sh" -type f | grep -v ".git" | sort)
        log_info "Found $(echo "$files" | wc -w) shell scripts"
    elif [ -z "$files" ]; then
        log_error "No files specified. Use --all to validate all scripts or specify files."
        show_usage
        exit 1
    fi
    
    # Validate each file
    local exit_code=0
    for file in $files; do
        if [ "$syntax_only" = "1" ]; then
            if ! validate_shell_syntax "$file"; then
                exit_code=1
            fi
        elif [ "$structure_only" = "1" ]; then
            if ! validate_function_structure "$file" || ! validate_conditional_structure "$file"; then
                exit_code=1
            fi
        else
            if ! validate_file_comprehensive "$file"; then
                exit_code=1
            fi
        fi
    done
    
    # Final summary
    log_step "Enhanced Syntax Validation Summary"
    log_info "Total checks: $TOTAL_CHECKS"
    log_info "Passed: $PASSED_CHECKS"
    log_info "Failed: $FAILED_CHECKS"
    log_info "Syntax errors: $SYNTAX_ERRORS"
    log_info "Structure errors: $STRUCTURE_ERRORS"
    
    if [ "$exit_code" -eq 0 ]; then
        log_success "🎉 All enhanced syntax validation checks passed!"
    else
        log_error "❌ Enhanced syntax validation found issues"
        log_info "💡 Fix the syntax and structure errors above before committing"
    fi
    
    exit $exit_code
}

# Run main function
main "$@"
