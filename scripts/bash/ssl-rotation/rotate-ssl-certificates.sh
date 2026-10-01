#!/bin/bash

################################################################################
# SSL Certificate Rotation Script for Nginx
# 
# Purpose: Safely rotate SSL certificates on VMs running nginx
# Features: 
#   - Idempotent (safe to run multiple times)
#   - Certificate validation and backup
#   - Nginx config validation and graceful reload
#   - Comprehensive error handling and logging
#   - Rollback on failure
#
# Author: DevOps Team
# Date: 2024
################################################################################

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_FILE:-/var/log/nginx-cert-rotation.log}"
BACKUP_DIR="${BACKUP_DIR:-/etc/nginx/certs.backup}"
NGINX_CERT_DIR="${NGINX_CERT_DIR:-/etc/nginx/certs}"
NGINX_CONFIG_DIR="${NGINX_CONFIG_DIR:-/etc/nginx}"
NGINX_PID_FILE="${NGINX_PID_FILE:-/var/run/nginx.pid}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Logging Functions
################################################################################

log() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
    
    case "${level}" in
        ERROR)
            echo -e "${RED}[ERROR]${NC} ${message}" >&2
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} ${message}"
            ;;
        INFO)
            echo -e "${GREEN}[INFO]${NC} ${message}"
            ;;
        DEBUG)
            if [[ "${VERBOSE}" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} ${message}"
            fi
            ;;
    esac
}

log_section() {
    echo ""
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=====================================${NC}"
    log INFO "$1"
}

################################################################################
# Validation Functions
################################################################################

# Check if script is running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log ERROR "This script must be run as root"
        exit 1
    fi
    log DEBUG "Running with root privileges"
}

# Validate that nginx is installed and running
check_nginx() {
    if ! command -v nginx &> /dev/null; then
        log ERROR "nginx is not installed"
        exit 1
    fi
    
    if ! systemctl is-active --quiet nginx; then
        log ERROR "nginx is not running. Please start nginx first"
        exit 1
    fi
    
    log INFO "nginx is installed and running"
}

# Validate certificate file format and existence
validate_certificate() {
    local cert_file="$1"
    local cert_type="$2"
    
    if [[ ! -f "${cert_file}" ]]; then
        log ERROR "Certificate file not found: ${cert_file}"
        return 1
    fi
    
    # Validate certificate format based on type
    case "${cert_type}" in
        crt|cert)
            if ! openssl x509 -in "${cert_file}" -noout &>/dev/null; then
                log ERROR "Invalid certificate format: ${cert_file}"
                return 1
            fi
            log INFO "Certificate validation passed: ${cert_file}"
            ;;
        key)
            if ! openssl rsa -in "${cert_file}" -check -noout &>/dev/null; then
                if ! openssl ec -in "${cert_file}" -check -noout &>/dev/null; then
                    log ERROR "Invalid key format: ${cert_file}"
                    return 1
                fi
            fi
            log INFO "Private key validation passed: ${cert_file}"
            ;;
        pem)
            if ! openssl x509 -in "${cert_file}" -noout &>/dev/null && \
               ! openssl rsa -in "${cert_file}" -check -noout &>/dev/null && \
               ! openssl ec -in "${cert_file}" -check -noout &>/dev/null; then
                log ERROR "Invalid PEM format: ${cert_file}"
                return 1
            fi
            log INFO "PEM file validation passed: ${cert_file}"
            ;;
    esac
    
    return 0
}

# Validate that certificate and key match
validate_cert_key_match() {
    local cert_file="$1"
    local key_file="$2"
    
    local cert_modulus
    local key_modulus
    
    # Get modulus from certificate
    cert_modulus=$(openssl x509 -noout -modulus -in "${cert_file}" 2>/dev/null | openssl md5)
    
    # Get modulus from key
    key_modulus=$(openssl rsa -noout -modulus -in "${key_file}" 2>/dev/null | openssl md5 || \
                  openssl ec -noout -modulus -in "${key_file}" 2>/dev/null | openssl md5)
    
    if [[ "${cert_modulus}" != "${key_modulus}" ]]; then
        log ERROR "Certificate and key do not match"
        return 1
    fi
    
    log INFO "Certificate and key match verified"
    return 0
}

# Check certificate expiration date
check_cert_expiration() {
    local cert_file="$1"
    local expiry_date
    local expiry_seconds
    local current_seconds
    local days_remaining
    
    expiry_date=$(openssl x509 -enddate -noout -in "${cert_file}" | cut -d= -f2)
    expiry_seconds=$(date -d "${expiry_date}" +%s)
    current_seconds=$(date +%s)
    days_remaining=$(( (expiry_seconds - current_seconds) / 86400 ))
    
    log INFO "Certificate expires on: ${expiry_date} (${days_remaining} days remaining)"
    
    if [[ ${days_remaining} -lt 0 ]]; then
        log WARN "Certificate is already expired"
    elif [[ ${days_remaining} -lt 30 ]]; then
        log WARN "Certificate will expire in ${days_remaining} days"
    fi
}

################################################################################
# Backup and Rotation Functions
################################################################################

# Create backup directory structure
create_backup_dir() {
    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="${BACKUP_DIR}/${backup_timestamp}"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        mkdir -p "${backup_path}"
        chmod 700 "${backup_path}"
    fi
    
    echo "${backup_path}"
}

# Backup existing certificates
backup_existing_certs() {
    local backup_path="$1"
    local cert_name="$2"
    
    if [[ ! -d "${NGINX_CERT_DIR}" ]]; then
        log DEBUG "Certificate directory does not exist yet: ${NGINX_CERT_DIR}"
        return 0
    fi
    
    local cert_file="${NGINX_CERT_DIR}/${cert_name}.crt"
    local key_file="${NGINX_CERT_DIR}/${cert_name}.key"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        if [[ -f "${cert_file}" ]]; then
            cp "${cert_file}" "${backup_path}/${cert_name}.crt.bak"
            log INFO "Backed up existing certificate: ${cert_name}.crt"
        fi
        
        if [[ -f "${key_file}" ]]; then
            cp "${key_file}" "${backup_path}/${cert_name}.key.bak"
            chmod 600 "${backup_path}/${cert_name}.key.bak"
            log INFO "Backed up existing key: ${cert_name}.key"
        fi
    else
        log DEBUG "[DRY RUN] Would backup: ${cert_file}"
        log DEBUG "[DRY RUN] Would backup: ${key_file}"
    fi
}

# Check if certificate already exists and is identical (idempotency check)
is_cert_already_installed() {
    local new_cert="$1"
    local cert_name="$2"
    local installed_cert="${NGINX_CERT_DIR}/${cert_name}.crt"
    
    if [[ ! -f "${installed_cert}" ]]; then
        return 1
    fi
    
    # Compare certificate hashes
    local new_cert_hash=$(openssl x509 -in "${new_cert}" -noout -fingerprint | cut -d= -f2)
    local installed_cert_hash=$(openssl x509 -in "${installed_cert}" -noout -fingerprint | cut -d= -f2)
    
    if [[ "${new_cert_hash}" == "${installed_cert_hash}" ]]; then
        log INFO "Certificate already installed and is identical (idempotent operation)"
        return 0
    fi
    
    return 1
}

# Install new certificates
install_certificates() {
    local cert_file="$1"
    local key_file="$2"
    local cert_name="$3"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        mkdir -p "${NGINX_CERT_DIR}"
        
        cp "${cert_file}" "${NGINX_CERT_DIR}/${cert_name}.crt"
        cp "${key_file}" "${NGINX_CERT_DIR}/${cert_name}.key"
        
        chmod 644 "${NGINX_CERT_DIR}/${cert_name}.crt"
        chmod 600 "${NGINX_CERT_DIR}/${cert_name}.key"
        
        log INFO "Installed new certificate: ${cert_name}.crt"
        log INFO "Installed new key: ${cert_name}.key"
    else
        log DEBUG "[DRY RUN] Would copy: ${cert_file} -> ${NGINX_CERT_DIR}/${cert_name}.crt"
        log DEBUG "[DRY RUN] Would copy: ${key_file} -> ${NGINX_CERT_DIR}/${cert_name}.key"
    fi
}

################################################################################
# Nginx Functions
################################################################################

# Validate nginx configuration
validate_nginx_config() {
    log INFO "Validating nginx configuration..."
    
    if nginx -t -c "${NGINX_CONFIG_DIR}/nginx.conf" &>/dev/null; then
        log INFO "nginx configuration is valid"
        return 0
    else
        log ERROR "nginx configuration validation failed"
        nginx -t -c "${NGINX_CONFIG_DIR}/nginx.conf" 2>&1 | while read -r line; do
            log ERROR "${line}"
        done
        return 1
    fi
}

# Gracefully reload nginx
reload_nginx() {
    if [[ "${DRY_RUN}" == "false" ]]; then
        log INFO "Reloading nginx..."
        
        if ! systemctl reload nginx; then
            log ERROR "Failed to reload nginx"
            return 1
        fi
        
        sleep 2
        
        if ! systemctl is-active --quiet nginx; then
            log ERROR "nginx stopped after reload"
            return 1
        fi
        
        log INFO "nginx successfully reloaded"
    else
        log DEBUG "[DRY RUN] Would reload nginx"
    fi
    
    return 0
}

################################################################################
# Cleanup Functions
################################################################################

# Remove old backups based on retention policy
cleanup_old_backups() {
    if [[ "${DRY_RUN}" == "false" ]]; then
        log INFO "Cleaning up backups older than ${BACKUP_RETENTION_DAYS} days..."
        
        find "${BACKUP_DIR}" -maxdepth 1 -type d -mtime "+${BACKUP_RETENTION_DAYS}" -exec rm -rf {} \; 2>/dev/null || true
        
        log INFO "Backup cleanup completed"
    else
        log DEBUG "[DRY RUN] Would remove backups older than ${BACKUP_RETENTION_DAYS} days"
    fi
}

# Rollback to previous certificate in case of failure
rollback_certificate() {
    local backup_path="$1"
    local cert_name="$2"
    
    log WARN "Attempting rollback to previous certificate..."
    
    local cert_backup="${backup_path}/${cert_name}.crt.bak"
    local key_backup="${backup_path}/${cert_name}.key.bak"
    
    if [[ ! -f "${cert_backup}" ]] || [[ ! -f "${key_backup}" ]]; then
        log ERROR "Backup files not found, cannot rollback"
        return 1
    fi
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        cp "${cert_backup}" "${NGINX_CERT_DIR}/${cert_name}.crt"
        cp "${key_backup}" "${NGINX_CERT_DIR}/${cert_name}.key"
        
        if validate_nginx_config && reload_nginx; then
            log INFO "Successfully rolled back to previous certificate"
            return 0
        else
            log ERROR "Rollback failed - nginx is in an invalid state"
            return 1
        fi
    fi
}

################################################################################
# Main Function
################################################################################

main() {
    local cert_file=""
    local key_file=""
    local cert_name="default"
    
    log_section "SSL Certificate Rotation Script"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--cert)
                cert_file="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
                shift 2
                ;;
            -k|--key)
                key_file="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
                shift 2
                ;;
            -n|--name)
                cert_name="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            -v|--verbose)
                VERBOSE="true"
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    # Validate input
    if [[ -z "${cert_file}" ]] || [[ -z "${key_file}" ]]; then
        log ERROR "Certificate and key files are required"
        print_usage
        exit 1
    fi
    
    log INFO "Starting SSL certificate rotation"
    log INFO "Certificate: ${cert_file}"
    log INFO "Key: ${key_file}"
    log INFO "Certificate name: ${cert_name}"
    [[ "${DRY_RUN}" == "true" ]] && log INFO "DRY RUN MODE ENABLED"
    
    # Pre-flight checks
    check_root
    check_nginx
    
    # Validate certificates
    log_section "Validating Certificates"
    validate_certificate "${cert_file}" "crt" || exit 1
    validate_certificate "${key_file}" "key" || exit 1
    validate_cert_key_match "${cert_file}" "${key_file}" || exit 1
    check_cert_expiration "${cert_file}"
    
    # Check idempotency
    log_section "Idempotency Check"
    if is_cert_already_installed "${cert_file}" "${cert_name}"; then
        log INFO "Rotation completed (certificate already installed)"
        exit 0
    fi
    
    # Create backup
    log_section "Creating Backups"
    local backup_path=$(create_backup_dir)
    log INFO "Backup directory: ${backup_path}"
    backup_existing_certs "${backup_path}" "${cert_name}"
    
    # Install new certificates
    log_section "Installing New Certificates"
    install_certificates "${cert_file}" "${key_file}" "${cert_name}"
    
    # Validate and reload
    log_section "Validating and Reloading Nginx"
    if ! validate_nginx_config; then
        log ERROR "Configuration validation failed, rolling back..."
        rollback_certificate "${backup_path}" "${cert_name}" || exit 1
        exit 1
    fi
    
    if ! reload_nginx; then
        log ERROR "Nginx reload failed, rolling back..."
        rollback_certificate "${backup_path}" "${cert_name}" || exit 1
        exit 1
    fi
    
    # Cleanup old backups
    log_section "Cleanup"
    cleanup_old_backups
    
    log_section "Rotation Completed Successfully"
    log INFO "Certificate rotation completed without errors"
    
    return 0
}

################################################################################
# Usage Function
################################################################################

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Required Options:
  -c, --cert FILE        Path to the certificate file (.crt or .pem)
  -k, --key FILE         Path to the private key file (.key)

Optional Options:
  -n, --name NAME        Certificate name (default: 'default')
  -d, --dry-run          Run in dry-run mode (no changes made)
  -v, --verbose          Enable verbose output
  -h, --help             Display this help message

Environment Variables:
  LOG_FILE               Log file path (default: /var/log/nginx-cert-rotation.log)
  BACKUP_DIR             Backup directory (default: /etc/nginx/certs.backup)
  NGINX_CERT_DIR         Certificate directory (default: /etc/nginx/certs)
  BACKUP_RETENTION_DAYS  Backup retention in days (default: 30)

Examples:
  # Rotate certificate
  sudo $0 -c /tmp/cert.crt -k /tmp/key.key -n "example.com"
  
  # Dry-run mode
  sudo $0 -c /tmp/cert.crt -k /tmp/key.key -n "example.com" -d
  
  # Verbose mode
  sudo $0 -c /tmp/cert.crt -k /tmp/key.key -n "example.com" -v

EOF
}

################################################################################
# Entry Point
################################################################################

trap 'log ERROR "Script interrupted"; exit 130' INT TERM

# Ensure log directory exists
mkdir -p "$(dirname "${LOG_FILE}")"

main "$@"
