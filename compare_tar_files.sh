#!/usr/bin/env python3
"""
Compare tar archive log files to verify they contain the same files.

This script compares two HTAR log files to ensure they archive identical file sets.
"""

import sys
import argparse
from pathlib import Path
from typing import Set, Tuple


# ANSI color codes
class Colors:
    """ANSI color codes for terminal output."""
    RESET = '\033[0m'
    BOLD = '\033[1m'
    RED = '\033[91m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    MAGENTA = '\033[95m'
    CYAN = '\033[96m'

    @staticmethod
    def disable():
        """Disable all colors."""
        Colors.RESET = ''
        Colors.BOLD = ''
        Colors.RED = ''
        Colors.GREEN = ''
        Colors.YELLOW = ''
        Colors.BLUE = ''
        Colors.MAGENTA = ''
        Colors.CYAN = ''


def parse_tar_log(log_file: Path) -> Set[str]:
    """
    Parse an HTAR log file and extract the list of archived files.

    Parameters
    ----------
    log_file : Path
        Path to the HTAR log file

    Returns
    -------
    Set[str]
        Set of file paths that were archived
    """
    files = set()

    with open(log_file, 'r') as f:
        for line in f:
            line = line.strip()
            # Look for lines like: "HTAR: a   <filepath>"
            if line.startswith("HTAR: a"):
                # Extract the file path (everything after "HTAR: a" with whitespace stripped)
                parts = line.split(None, 2)  # Split on whitespace, max 3 parts
                if len(parts) >= 3:
                    filepath = parts[2]
                    files.add(filepath)

    return files


def compare_file_lists(files1: Set[str], files2: Set[str],
                       label1: str, label2: str) -> Tuple[bool, str]:
    """
    Compare two sets of files and generate a report.

    Parameters
    ----------
    files1 : Set[str]
        First set of files
    files2 : Set[str]
        Second set of files
    label1 : str
        Label for first file set
    label2 : str
        Label for second file set

    Returns
    -------
    Tuple[bool, str]
        (are_identical, report_message)
    """
    only_in_1 = files1 - files2
    only_in_2 = files2 - files1
    common = files1 & files2

    report = []
    report.append(f"{Colors.CYAN}{Colors.BOLD}{'=' * 80}{Colors.RESET}")
    report.append(f"{Colors.CYAN}{Colors.BOLD}TAR FILE COMPARISON REPORT{Colors.RESET}")
    report.append(f"{Colors.CYAN}{Colors.BOLD}{'=' * 80}{Colors.RESET}")
    report.append(f"\n{Colors.BLUE}{label1}:{Colors.RESET}")
    report.append(f"  Total files: {Colors.BOLD}{len(files1)}{Colors.RESET}")
    report.append(f"\n{Colors.BLUE}{label2}:{Colors.RESET}")
    report.append(f"  Total files: {Colors.BOLD}{len(files2)}{Colors.RESET}")
    report.append(f"\n{Colors.MAGENTA}Common files: {Colors.BOLD}{len(common)}{Colors.RESET}")

    if not only_in_1 and not only_in_2:
        report.append(f"\n{Colors.GREEN}{Colors.BOLD}✓ SUCCESS: Both tar logs contain identical file sets!{Colors.RESET}")
        report.append(f"{Colors.CYAN}{'=' * 80}{Colors.RESET}")
        return True, "\n".join(report)

    report.append(f"\n{Colors.RED}{Colors.BOLD}✗ FAILURE: File sets differ!{Colors.RESET}")

    if only_in_1:
        report.append(f"\n{Colors.RED}Files only in {label1} ({len(only_in_1)} files):{Colors.RESET}")
        report.append(f"{Colors.RED}{'-' * 80}{Colors.RESET}")
        for f in sorted(only_in_1):
            report.append(f"{Colors.RED}  - {f}{Colors.RESET}")

    if only_in_2:
        report.append(f"\n{Colors.GREEN}Files only in {label2} ({len(only_in_2)} files):{Colors.RESET}")
        report.append(f"{Colors.GREEN}{'-' * 80}{Colors.RESET}")
        for f in sorted(only_in_2):
            report.append(f"{Colors.GREEN}  + {f}{Colors.RESET}")

    report.append(f"{Colors.CYAN}{'=' * 80}{Colors.RESET}")
    return False, "\n".join(report)


def main():
    """Main entry point for the script."""
    parser = argparse.ArgumentParser(
        description="Compare two HTAR log files to verify identical file sets",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s file1.log file2.log
  %(prog)s -v develop_archive.log test_archive.log
        """
    )

    parser.add_argument(
        'log1',
        type=Path,
        help='First HTAR log file (e.g., develop branch)'
    )

    parser.add_argument(
        'log2',
        type=Path,
        help='Second HTAR log file (e.g., test branch)'
    )

    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help='Show detailed output including common files'
    )

    parser.add_argument(
        '-q', '--quiet',
        action='store_true',
        help='Only show summary (suppress file lists)'
    )

    parser.add_argument(
        '--no-color',
        action='store_true',
        help='Disable colored output'
    )

    args = parser.parse_args()

    # Disable colors if requested or not in a terminal
    if args.no_color or not sys.stdout.isatty():
        Colors.disable()

    # Validate input files
    if not args.log1.exists():
        print(f"{Colors.RED}ERROR: Log file not found: {args.log1}{Colors.RESET}", file=sys.stderr)
        return 1

    if not args.log2.exists():
        print(f"{Colors.RED}ERROR: Log file not found: {args.log2}{Colors.RESET}", file=sys.stderr)
        return 1

    # Parse both log files
    print(f"{Colors.CYAN}Parsing {args.log1}...{Colors.RESET}")
    files1 = parse_tar_log(args.log1)

    print(f"{Colors.CYAN}Parsing {args.log2}...{Colors.RESET}")
    files2 = parse_tar_log(args.log2)

    # Compare file lists - use parent directory paths as labels
    label1 = str(args.log1.parent)
    label2 = str(args.log2.parent)

    identical, report = compare_file_lists(files1, files2, label1, label2)

    # Print report
    if args.quiet:
        # Only show summary line
        if identical:
            print(f"{Colors.GREEN}✓ SUCCESS: Tar logs contain identical file sets{Colors.RESET}")
        else:
            print(f"{Colors.RED}✗ FAILURE: Tar logs differ{Colors.RESET}")
            print(f"  Files only in {label1}: {Colors.RED}{len(files1 - files2)}{Colors.RESET}")
            print(f"  Files only in {label2}: {Colors.GREEN}{len(files2 - files1)}{Colors.RESET}")
    else:
        print("\n" + report)

    # Show common files if verbose
    if args.verbose and not args.quiet:
        common = files1 & files2
        print(f"\n{Colors.MAGENTA}Common files ({len(common)}):{Colors.RESET}")
        print(f"{Colors.CYAN}{'-' * 80}{Colors.RESET}")
        for f in sorted(common):
            print(f"  {f}")

    return 0 if identical else 1


if __name__ == "__main__":
    sys.exit(main())
