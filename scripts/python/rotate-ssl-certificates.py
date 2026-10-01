#!/usr/bin/env python3

"""
SSL Certificate Rotation Script for Nginx (Python Implementation)

Purpose: Safely rotate SSL certificates on VMs running nginx
Features:
    - Idempotent (safe to run multiple times)
    - Certificate validation and backup
    - Nginx config validation and graceful reload
    - Comprehensive error handling and logging
    - Rollback on failure
    - Dry-run mode for testing

Author: DevOps Team
Date: 2024
"""

import os
import sys
import argparse
import logging
import subprocess
import shutil
import hashlib
import tempfile
from pathlib import Path
from datetime import datetime, timedelta
from typing import Optional, Tuple
import signal


class Colors:
    """ANSI color codes for terminal output"""
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'  # No Color


class CertificateRotationError(Exception):
    """Custom exception for certificate rotation errors"""
    pass


class NginxCertificateRotator:
    """Main class for handling nginx certificate rotation"""
    
    def __init__(self, 
                 cert_file: str,
                 key_file: str,
                 cert_name: str = "default",
                 nginx_cert_dir: str = "/etc/nginx/certs",
                 backup_dir: str = "/etc/nginx/certs.backup",
                 log_file: str = "/var/log/nginx-cert-rotation.log",
                 backup_retention_days: int = 30,
                 dry_run: bool = False,
                 verbose: bool = False):
        
        self.cert_file = Path(cert_file).resolve()
        self.key_file = Path(key_file).resolve()
        self.cert_name = cert_name
        self.nginx_cert_dir = Path(nginx_cert_dir)
        self.backup_dir = Path(backup_dir)
        self.backup_retention_days = backup_retention_days
        self.dry_run = dry_run
        self.verbose = verbose
        self.backup_path: Optional[Path] = None
        
        # Setup logging
        self.setup_logging(log_file)
    
    def setup_logging(self, log_file: str):
        """Configure logging to both file and console"""
        self.logger = logging.getLogger(__name__)
        self.logger.setLevel(logging.DEBUG if self.verbose else logging.INFO)
        
        # File handler
        file_handler = logging.FileHandler(log_file)
        file_handler.setLevel(logging.DEBUG)
        
        # Console handler
        console_handler = logging.StreamHandler()
        console_handler.setLevel(logging.INFO)
        
        # Formatter
        formatter = logging.Formatter(
            '%(asctime)s - %(levelname)s - %(message)s',
            datefmt='%Y-%m-%d %H:%M:%S'
        )
        
        file_handler.setFormatter(formatter)
        console_handler.setFormatter(self._get_colored_formatter())
        
        self.logger.addHandler(file_handler)
        self.logger.addHandler(console_handler)
    
    def _get_colored_formatter(self) -> logging.Formatter:
        """Create a colored formatter for console output"""
        class ColoredFormatter(logging.Formatter):
            COLORS = {
                'DEBUG': Colors.BLUE,
                'INFO': Colors.GREEN,
                'WARNING': Colors.YELLOW,
                'ERROR': Colors.RED,
            }
            
            def format(self, record):
                levelname = record.levelname
                color = self.COLORS.get(levelname, '')
                reset = Colors.NC
                record.levelname = f"{color}[{levelname}]{reset}"
                return super().format(record)
        
        return ColoredFormatter(
            '%(levelname)s %(message)s',
            datefmt='%Y-%m-%d %H:%M:%S'
        )
    
    def log_section(self, section_name: str):
        """Log a section header"""
        separator = "=" * 37
        self.logger.info(f"\n{separator}")
        self.logger.info(section_name)
        self.logger.info(f"{separator}\n")
    
    # Pre-flight checks
    
    def check_root(self):
        """Verify script is running as root"""
        if os.geteuid() != 0:
            raise CertificateRotationError("This script must be run as root")
        self.logger.debug("Running with root privileges")
    
    def check_nginx(self):
        """Verify nginx is installed and running"""
        # Check if nginx is installed
        result = subprocess.run(['which', 'nginx'], capture_output=True)
        if result.returncode != 0:
            raise CertificateRotationError("nginx is not installed")
        
        # Check if nginx is running
        result = subprocess.run(
            ['systemctl', 'is-active', 'nginx'],
            capture_output=True
        )
        if result.returncode != 0:
            raise CertificateRotationError("nginx is not running. Please start nginx first")
        
        self.logger.info("nginx is installed and running")
    
    def check_required_tools(self):
        """Verify required tools are available"""
        required_tools = ['openssl', 'nginx', 'systemctl']
        for tool in required_tools:
            result = subprocess.run(['which', tool], capture_output=True)
            if result.returncode != 0:
                raise CertificateRotationError(f"Required tool not found: {tool}")
        self.logger.debug("All required tools are available")
    
    # Certificate validation
    
    def validate_certificate_file(self):
        """Validate certificate file exists and has correct format"""
        if not self.cert_file.exists():
            raise CertificateRotationError(f"Certificate file not found: {self.cert_file}")
        
        # Verify it's a valid X.509 certificate
        result = subprocess.run(
            ['openssl', 'x509', '-in', str(self.cert_file), '-noout'],
            capture_output=True
        )
        if result.returncode != 0:
            raise CertificateRotationError(
                f"Invalid certificate format: {self.cert_file}"
            )
        
        self.logger.info(f"Certificate validation passed: {self.cert_file}")
    
    def validate_key_file(self):
        """Validate private key file exists and has correct format"""
        if not self.key_file.exists():
            raise CertificateRotationError(f"Key file not found: {self.key_file}")
        
        # Try RSA first
        result = subprocess.run(
            ['openssl', 'rsa', '-in', str(self.key_file), '-check', '-noout'],
            capture_output=True
        )
        
        # If RSA fails, try EC
        if result.returncode != 0:
            result = subprocess.run(
                ['openssl', 'ec', '-in', str(self.key_file), '-check', '-noout'],
                capture_output=True
            )
        
        if result.returncode != 0:
            raise CertificateRotationError(f"Invalid key format: {self.key_file}")
        
        self.logger.info(f"Private key validation passed: {self.key_file}")
    
    def validate_cert_key_match(self):
        """Verify certificate and key match"""
        # Get certificate modulus
        result = subprocess.run(
            ['openssl', 'x509', '-noout', '-modulus', '-in', str(self.cert_file)],
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            raise CertificateRotationError("Could not extract certificate modulus")
        cert_modulus = hashlib.md5(result.stdout.encode()).hexdigest()
        
        # Get key modulus (try RSA first, then EC)
        result = subprocess.run(
            ['openssl', 'rsa', '-noout', '-modulus', '-in', str(self.key_file)],
            capture_output=True,
            text=True
        )
        
        if result.returncode != 0:
            result = subprocess.run(
                ['openssl', 'ec', '-noout', '-modulus', '-in', str(self.key_file)],
                capture_output=True,
                text=True
            )
        
        if result.returncode != 0:
            raise CertificateRotationError("Could not extract key modulus")
        key_modulus = hashlib.md5(result.stdout.encode()).hexdigest()
        
        if cert_modulus != key_modulus:
            raise CertificateRotationError("Certificate and key do not match")
        
        self.logger.info("Certificate and key match verified")
    
    def check_cert_expiration(self):
        """Check and log certificate expiration date"""
        result = subprocess.run(
            ['openssl', 'x509', '-enddate', '-noout', '-in', str(self.cert_file)],
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            expiry_str = result.stdout.strip().replace('notAfter=', '')
            self.logger.info(f"Certificate expires on: {expiry_str}")
    
    def get_cert_fingerprint(self, cert_path: Path) -> str:
        """Get certificate fingerprint for comparison"""
        result = subprocess.run(
            ['openssl', 'x509', '-in', str(cert_path), '-noout', '-fingerprint'],
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            raise CertificateRotationError(f"Could not get fingerprint for {cert_path}")
        return result.stdout.strip()
    
    # Backup and rotation
    
    def create_backup_directory(self) -> Path:
        """Create timestamped backup directory"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_path = self.backup_dir / timestamp
        
        if self.dry_run:
            self.logger.debug(f"[DRY RUN] Would create backup directory: {backup_path}")
        else:
            backup_path.mkdir(parents=True, exist_ok=True)
            backup_path.chmod(0o700)
            self.logger.info(f"Created backup directory: {backup_path}")
        
        self.backup_path = backup_path
        return backup_path
    
    def backup_existing_certs(self):
        """Backup existing certificates if they exist"""
        cert_path = self.nginx_cert_dir / f"{self.cert_name}.crt"
        key_path = self.nginx_cert_dir / f"{self.cert_name}.key"
        
        if not self.nginx_cert_dir.exists():
            self.logger.debug(
                f"Certificate directory does not exist yet: {self.nginx_cert_dir}"
            )
            return
        
        if self.dry_run:
            if cert_path.exists():
                self.logger.debug(f"[DRY RUN] Would backup: {cert_path}")
            if key_path.exists():
                self.logger.debug(f"[DRY RUN] Would backup: {key_path}")
        else:
            if cert_path.exists():
                shutil.copy2(cert_path, self.backup_path / f"{self.cert_name}.crt.bak")
                self.logger.info(f"Backed up existing certificate: {self.cert_name}.crt")
            
            if key_path.exists():
                shutil.copy2(key_path, self.backup_path / f"{self.cert_name}.key.bak")
                (self.backup_path / f"{self.cert_name}.key.bak").chmod(0o600)
                self.logger.info(f"Backed up existing key: {self.cert_name}.key")
    
    def is_cert_already_installed(self) -> bool:
        """Check if identical certificate is already installed (idempotency)"""
        installed_cert = self.nginx_cert_dir / f"{self.cert_name}.crt"
        
        if not installed_cert.exists():
            return False
        
        try:
            new_fingerprint = self.get_cert_fingerprint(self.cert_file)
            installed_fingerprint = self.get_cert_fingerprint(installed_cert)
            
            if new_fingerprint == installed_fingerprint:
                self.logger.info(
                    "Certificate already installed and is identical (idempotent operation)"
                )
                return True
        except CertificateRotationError:
            # If we can't get fingerprints, proceed with rotation
            pass
        
        return False
    
    def install_certificates(self):
        """Install new certificates"""
        if self.dry_run:
            self.logger.debug(f"[DRY RUN] Would copy: {self.cert_file} -> "
                             f"{self.nginx_cert_dir}/{self.cert_name}.crt")
            self.logger.debug(f"[DRY RUN] Would copy: {self.key_file} -> "
                             f"{self.nginx_cert_dir}/{self.cert_name}.key")
        else:
            self.nginx_cert_dir.mkdir(parents=True, exist_ok=True)
            
            shutil.copy2(self.cert_file, 
                        self.nginx_cert_dir / f"{self.cert_name}.crt")
            (self.nginx_cert_dir / f"{self.cert_name}.crt").chmod(0o644)
            
            shutil.copy2(self.key_file,
                        self.nginx_cert_dir / f"{self.cert_name}.key")
            (self.nginx_cert_dir / f"{self.cert_name}.key").chmod(0o600)
            
            self.logger.info(f"Installed new certificate: {self.cert_name}.crt")
            self.logger.info(f"Installed new key: {self.cert_name}.key")
    
    # Nginx operations
    
    def validate_nginx_config(self) -> bool:
        """Validate nginx configuration syntax"""
        self.logger.info("Validating nginx configuration...")
        
        result = subprocess.run(
            ['nginx', '-t'],
            capture_output=True,
            text=True
        )
        
        if result.returncode != 0:
            self.logger.error("nginx configuration validation failed")
            for line in result.stderr.split('\n'):
                if line.strip():
                    self.logger.error(line)
            return False
        
        self.logger.info("nginx configuration is valid")
        return True
    
    def reload_nginx(self) -> bool:
        """Gracefully reload nginx"""
        if self.dry_run:
            self.logger.debug("[DRY RUN] Would reload nginx")
            return True
        
        self.logger.info("Reloading nginx...")
        
        result = subprocess.run(
            ['systemctl', 'reload', 'nginx'],
            capture_output=True,
            text=True
        )
        
        if result.returncode != 0:
            self.logger.error("Failed to reload nginx")
            return False
        
        # Wait for reload to complete
        import time
        time.sleep(2)
        
        # Verify nginx is still running
        result = subprocess.run(
            ['systemctl', 'is-active', 'nginx'],
            capture_output=True
        )
        
        if result.returncode != 0:
            self.logger.error("nginx stopped after reload")
            return False
        
        self.logger.info("nginx successfully reloaded")
        return True
    
    # Cleanup and rollback
    
    def cleanup_old_backups(self):
        """Remove backups older than retention period"""
        if self.dry_run:
            self.logger.debug(
                f"[DRY RUN] Would remove backups older than {self.backup_retention_days} days"
            )
            return
        
        self.logger.info(f"Cleaning up backups older than {self.backup_retention_days} days...")
        
        cutoff_date = datetime.now() - timedelta(days=self.backup_retention_days)
        
        if not self.backup_dir.exists():
            return
        
        for backup_path in self.backup_dir.iterdir():
            if not backup_path.is_dir():
                continue
            
            # Get modification time
            mtime = datetime.fromtimestamp(backup_path.stat().st_mtime)
            if mtime < cutoff_date:
                try:
                    shutil.rmtree(backup_path)
                    self.logger.info(f"Removed old backup: {backup_path.name}")
                except Exception as e:
                    self.logger.warning(f"Failed to remove backup {backup_path.name}: {e}")
        
        self.logger.info("Backup cleanup completed")
    
    def rollback_certificate(self) -> bool:
        """Rollback to previous certificate"""
        self.logger.warning("Attempting rollback to previous certificate...")
        
        if not self.backup_path:
            self.logger.error("No backup path available for rollback")
            return False
        
        cert_backup = self.backup_path / f"{self.cert_name}.crt.bak"
        key_backup = self.backup_path / f"{self.cert_name}.key.bak"
        
        if not cert_backup.exists() or not key_backup.exists():
            self.logger.error("Backup files not found, cannot rollback")
            return False
        
        try:
            shutil.copy2(cert_backup, 
                         self.nginx_cert_dir / f"{self.cert_name}.crt")
            shutil.copy2(key_backup,
                         self.nginx_cert_dir / f"{self.cert_name}.key")
            
            if self.validate_nginx_config() and self.reload_nginx():
                self.logger.info("Successfully rolled back to previous certificate")
                return True
            else:
                self.logger.error("Rollback failed - nginx is in an invalid state")
                return False
        
        except Exception as e:
            self.logger.error(f"Rollback failed with error: {e}")
            return False
    
    # Main execution
    
    def run(self) -> bool:
        """Execute the certificate rotation"""
        try:
            self.log_section("SSL Certificate Rotation Script")
            
            self.logger.info(f"Starting SSL certificate rotation")
            self.logger.info(f"Certificate: {self.cert_file}")
            self.logger.info(f"Key: {self.key_file}")
            self.logger.info(f"Certificate name: {self.cert_name}")
            if self.dry_run:
                self.logger.info("DRY RUN MODE ENABLED")
            
            # Pre-flight checks
            self.log_section("Pre-flight Checks")
            self.check_root()
            self.check_required_tools()
            self.check_nginx()
            
            # Validate certificates
            self.log_section("Validating Certificates")
            self.validate_certificate_file()
            self.validate_key_file()
            self.validate_cert_key_match()
            self.check_cert_expiration()
            
            # Check idempotency
            self.log_section("Idempotency Check")
            if self.is_cert_already_installed():
                self.logger.info("Rotation completed (certificate already installed)")
                return True
            
            # Create backups
            self.log_section("Creating Backups")
            self.create_backup_directory()
            self.backup_existing_certs()
            
            # Install new certificates
            self.log_section("Installing New Certificates")
            self.install_certificates()
            
            # Validate and reload
            self.log_section("Validating and Reloading Nginx")
            if not self.validate_nginx_config():
                self.logger.error("Configuration validation failed, rolling back...")
                if not self.rollback_certificate():
                    raise CertificateRotationError("Rollback failed - manual intervention required")
                return False
            
            if not self.reload_nginx():
                self.logger.error("Nginx reload failed, rolling back...")
                if not self.rollback_certificate():
                    raise CertificateRotationError("Rollback failed - manual intervention required")
                return False
            
            # Cleanup
            self.log_section("Cleanup")
            self.cleanup_old_backups()
            
            # Success
            self.log_section("Rotation Completed Successfully")
            self.logger.info("Certificate rotation completed without errors")
            return True
        
        except CertificateRotationError as e:
            self.logger.error(f"Certificate rotation failed: {e}")
            return False
        except Exception as e:
            self.logger.error(f"Unexpected error: {e}")
            if self.verbose:
                import traceback
                traceback.print_exc()
            return False


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description='Safely rotate SSL certificates on nginx VMs',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Rotate certificate
  sudo python3 rotate-ssl-certificates.py -c /tmp/cert.crt -k /tmp/key.key -n "example.com"
  
  # Dry-run mode
  sudo python3 rotate-ssl-certificates.py -c /tmp/cert.crt -k /tmp/key.key -n "example.com" --dry-run
  
  # Verbose mode
  sudo python3 rotate-ssl-certificates.py -c /tmp/cert.crt -k /tmp/key.key -n "example.com" --verbose
        """
    )
    
    # Required arguments
    parser.add_argument('-c', '--cert', required=True,
                       help='Path to the certificate file (.crt or .pem)')
    parser.add_argument('-k', '--key', required=True,
                       help='Path to the private key file (.key)')
    
    # Optional arguments
    parser.add_argument('-n', '--name', default='default',
                       help='Certificate name (default: default)')
    parser.add_argument('--nginx-cert-dir', default='/etc/nginx/certs',
                       help='Nginx certificate directory (default: /etc/nginx/certs)')
    parser.add_argument('--backup-dir', default='/etc/nginx/certs.backup',
                       help='Backup directory (default: /etc/nginx/certs.backup)')
    parser.add_argument('--log-file', default='/var/log/nginx-cert-rotation.log',
                       help='Log file path (default: /var/log/nginx-cert-rotation.log)')
    parser.add_argument('--backup-retention-days', type=int, default=30,
                       help='Backup retention in days (default: 30)')
    parser.add_argument('-d', '--dry-run', action='store_true',
                       help='Run in dry-run mode (no changes made)')
    parser.add_argument('-v', '--verbose', action='store_true',
                       help='Enable verbose output')
    
    args = parser.parse_args()
    
    # Create rotator and run
    rotator = NginxCertificateRotator(
        cert_file=args.cert,
        key_file=args.key,
        cert_name=args.name,
        nginx_cert_dir=args.nginx_cert_dir,
        backup_dir=args.backup_dir,
        log_file=args.log_file,
        backup_retention_days=args.backup_retention_days,
        dry_run=args.dry_run,
        verbose=args.verbose
    )
    
    # Handle signals
    def signal_handler(signum, frame):
        rotator.logger.error("Script interrupted")
        sys.exit(130)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Execute
    success = rotator.run()
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
