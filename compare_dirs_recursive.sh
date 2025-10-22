#!/bin/bash

################################################################################
# Compare directories - recursively process subdirectories
# Shows side-by-side table for each subdirectory pair
################################################################################

# Show help
show_help() {
    cat << 'EOF'
USAGE
  compare_recursive_subdirs.sh <dir_d> <dir_t> [output.csv] [-r] [-m exclude_dirs]

DESCRIPTION
  Compares files in two directories.

  By default: Compares ONLY files in the ROOT level (ignores subdirectories):x
  With -r flag: Compares ALL files RECURSIVELY in all subdirectories

  Files are matched by:
    1. Exact filename match
    2. Similar file size (within 5MB tolerance) if no exact match

  Generates side-by-side comparison tables and a detailed CSV report.

ARGUMENTS
  dir_d            Directory tree 1 (development/source)
  dir_t            Directory tree 2 (test/target)
  output.csv       Optional output CSV file (default: output.csv)
  -r               RECURSIVE mode: Compare all files in subdirectories
                   Without -r: Only compare root-level files
  -m patterns      Comma-separated list of directory patterns to EXCLUDE
                   Example: -m "gdiags,gfis,products"

OUTPUT FILES
  CSV Report:      Contains all file comparisons with hashes and sizes
  Terminal:        Side-by-side tables for each subdirectory
  Summary:         Statistics and lists of missing/different files at end

STATUS CODES
  ✓ PERFECT        Same size AND same hash (identical files)
  ~ SIZE_OK        Same size BUT different hash (content differs)
  ≈ CLOSE          Within 5% size difference (similar files)
  ✗ DIFFERENT      >5% size difference (significantly different)
  ← ONLY_D         File exists only in DIR_D
  → ONLY_T         File exists only in DIR_T

EXAMPLES
  # Compare root-level files only (default)
  ./compare_recursive_subdirs.sh /path/to/dir_d /path/to/dir_t

  # Compare root-level files with custom output
  ./compare_recursive_subdirs.sh /path/to/dir_d /path/to/dir_t results.csv

  # RECURSIVE: Compare all files in all subdirectories
  ./compare_recursive_subdirs.sh /path/to/dir_d /path/to/dir_t -r

  # Recursive with output file
  ./compare_recursive_subdirs.sh /path/to/dir_d /path/to/dir_t output.csv -r

  # Recursive excluding certain directories
  ./compare_recursive_subdirs.sh /path/to/dir_d /path/to/dir_t output.csv -r -m "cache,tmp"

  # Show this help message
  ./compare_recursive_subdirs.sh -h
  ./compare_recursive_subdirs.sh --help

NOTES
  - Default mode: Only compares FILES in the root directory level
  - Recursive mode (-r): Compares ALL files in ALL subdirectories
  - Use -m to exclude directory patterns (only in recursive mode)

EOF
}

# Check for help flag
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    show_help
    exit 0
fi

DIR_D=""
DIR_T=""
OUTPUT="output.csv"
EXCLUDE_PATTERNS=""
RECURSIVE=0

# Parse all arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -r|--recursive)
            RECURSIVE=1
            ;;
        -m)
            shift
            EXCLUDE_PATTERNS="$1"
            ;;
        *)
            # Positional arguments (dir_d, dir_t, output.csv)
            if [[ -z "$DIR_D" ]]; then
                DIR_D="$1"
            elif [[ -z "$DIR_T" ]]; then
                DIR_T="$1"
            elif [[ "$OUTPUT" == "output.csv" ]]; then
                OUTPUT="$1"
            fi
            ;;
    esac
    shift
done

if [[ ! -d "$DIR_D" ]] || [[ ! -d "$DIR_T" ]]; then
    echo "Usage: $0 <dir_d> <dir_t> [output.csv] [-r] [-m exclude_dirs]"
    echo "       $0 -h (for help)"
    exit 1
fi

# Function to check if directory should be excluded
should_exclude() {
    local dir="$1"
    local patterns="$2"

    if [[ -z "$patterns" ]]; then
        return 1  # Don't exclude if no patterns
    fi

    # Convert comma-separated patterns to array
    IFS=',' read -ra pattern_array <<< "$patterns"

    for pattern in "${pattern_array[@]}"; do
        pattern=$(echo "$pattern" | xargs)  # Trim whitespace
        # Check if pattern matches anywhere in the directory path
        if [[ "$dir" == *"$pattern"* ]]; then
            return 0  # Exclude this directory
        fi
    done

    return 1  # Don't exclude
}

# Format size for display
format_size() {
    local size=$1
    if [[ $size -lt 1024 ]]; then
        printf "%8dB" "$size"
    elif [[ $size -lt 1048576 ]]; then
        printf "%7dK" "$((size / 1024))"
    else
        printf "%7dM" "$((size / 1048576))"
    fi
}

# Check file differences based on file type
check_file_diff() {
    local file_d="$1"
    local file_t="$2"
    local filename="$3"

    # Get file extension
    local ext="${filename##*.}"

    # Check file type and perform appropriate comparison
    case "$ext" in
        tar)
            # Compare tar file contents
            local d_contents=$(tar -tf "$file_d" 2>/dev/null | sort)
            local t_contents=$(tar -tf "$file_t" 2>/dev/null | sort)
            if [[ "$d_contents" == "$t_contents" ]]; then
                echo "TAR: File list identical"
                return 0
            else
                echo "TAR: File contents differ"
                return 1
            fi
            ;;
        txt)
            # Compare text files line by line
            local d_lines=$(wc -l < "$file_d" 2>/dev/null)
            local t_lines=$(wc -l < "$file_t" 2>/dev/null)
            if [[ "$d_lines" != "$t_lines" ]]; then
                echo "TXT: Different line counts (D: $d_lines, T: $t_lines)"
                return 1
            fi
            # Check if first and last lines are same
            local d_first=$(head -1 "$file_d" 2>/dev/null)
            local t_first=$(head -1 "$file_t" 2>/dev/null)
            if [[ "$d_first" != "$t_first" ]]; then
                echo "TXT: Different content (first line differs)"
                return 1
            fi
            echo "TXT: Structure appears identical (same line count and first line)"
            return 0
            ;;
        nc)
            # Compare NetCDF files - check dimensions and variables
            if command -v ncdump &> /dev/null; then
                local d_dims=$(ncdump -h "$file_d" 2>/dev/null | grep "dimensions:")
                local t_dims=$(ncdump -h "$file_t" 2>/dev/null | grep "dimensions:")
                if [[ "$d_dims" == "$t_dims" ]]; then
                    echo "NC: Dimensions identical"
                    return 0
                else
                    echo "NC: Dimensions differ"
                    return 1
                fi
            else
                echo "NC: ncdump not available, using binary comparison"
                return 2
            fi
            ;;
        grib2|grib|grb|grb2|grbf*)
            # GRIB files - check if both are valid GRIB
            if command -v wgrib2 &> /dev/null; then
                local d_msgs=$(wgrib2 "$file_d" 2>/dev/null | wc -l)
                local t_msgs=$(wgrib2 "$file_t" 2>/dev/null | wc -l)
                if [[ "$d_msgs" == "$t_msgs" && "$d_msgs" -gt 0 ]]; then
                    echo "GRIB2: Same number of messages ($d_msgs)"
                    return 0
                else
                    echo "GRIB2: Different message counts (D: $d_msgs, T: $t_msgs)"
                    return 1
                fi
            elif command -v wgrib &> /dev/null; then
                local d_msgs=$(wgrib "$file_d" 2>/dev/null | wc -l)
                local t_msgs=$(wgrib "$file_t" 2>/dev/null | wc -l)
                if [[ "$d_msgs" == "$t_msgs" && "$d_msgs" -gt 0 ]]; then
                    echo "GRIB: Same number of messages ($d_msgs)"
                    return 0
                else
                    echo "GRIB: Different message counts (D: $d_msgs, T: $t_msgs)"
                    return 1
                fi
            else
                echo "GRIB: wgrib/wgrib2 not available, using binary comparison"
                return 2
            fi
            ;;
        *)
            # Unknown type, return 2 for unknown
            echo "UNKNOWN: Cannot determine file type"
            return 2
            ;;
    esac
}

echo "DIR_D: $DIR_D"
echo "DIR_T: $DIR_T"
echo "Output CSV: $OUTPUT"
echo "Mode: $([ $RECURSIVE -eq 1 ] && echo 'RECURSIVE (all subdirectories)' || echo 'ROOT LEVEL ONLY (ignoring subdirectories)')"
if [[ -n "$EXCLUDE_PATTERNS" ]]; then
    echo "Excluding directories matching: $EXCLUDE_PATTERNS"
fi
echo ""

# CSV header
echo "subdir,d_file,d_size,t_file,t_size,d_hash,t_hash,status" > "$OUTPUT"

# Compare files - either recursive or root level only
if [[ $RECURSIVE -eq 1 ]]; then
    # RECURSIVE MODE: Compare root files first, then all subdirectories
    echo "Comparing files in root directory and all subdirectories recursively..."
    excluded_count=0
    processed_count=0

    # Process root directory first
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "Comparing: . (root level)"
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo ""

    # Create header
    printf "%-40s %-10s │ %-40s %-10s │ Status\n" "D_FILES" "Size" "T_FILES" "Size"
    printf "%s\n" "$(printf '═%.0s' {1..130})"

    # Get sorted lists of files with sizes
    declare -A d_files_array t_files_array
    declare -A d_sizes_array t_sizes_array
    declare -a d_files_list t_files_list

    # Build arrays for DIR_D files (root only)
    while IFS= read -r d_name; do
        [[ -z "$d_name" ]] && continue
        d_size=$(stat -c%s "$DIR_D/$d_name" 2>/dev/null || stat -f%z "$DIR_D/$d_name" 2>/dev/null)
        d_files_array["$d_name"]=1
        d_sizes_array["$d_name"]=$d_size
        d_files_list+=("$d_name")
    done < <(find "$DIR_D" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort -V)

    # Build arrays for DIR_T files (root only)
    while IFS= read -r t_name; do
        [[ -z "$t_name" ]] && continue
        t_size=$(stat -c%s "$DIR_T/$t_name" 2>/dev/null || stat -f%z "$DIR_T/$t_name" 2>/dev/null)
        t_files_array["$t_name"]=1
        t_sizes_array["$t_name"]=$t_size
        t_files_list+=("$t_name")
    done < <(find "$DIR_T" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort -V)

    # Track matched files
    declare -A d_matched t_matched
    total=0
    matched=0

    # First pass: Match files by exact name
    for d_name in "${d_files_list[@]}"; do
        if [[ -n "${t_files_array[$d_name]}" ]]; then
            d_size=${d_sizes_array[$d_name]}
            t_size=${t_sizes_array[$d_name]}
            d_hash=$(md5sum "$DIR_D/$d_name" 2>/dev/null | awk '{print $1}')
            t_hash=$(md5sum "$DIR_T/$d_name" 2>/dev/null | awk '{print $1}')
            d_size_fmt=$(format_size "$d_size")
            t_size_fmt=$(format_size "$t_size")

            # Determine match status
            status=""
            if [[ "$d_size" -eq "$t_size" ]]; then
                if [[ "$d_hash" == "$t_hash" ]]; then
                    status="✓ PERFECT"
                    matched=$((matched + 1))
                else
                    status="~ SIZE_OK"
                fi
            else
                if [[ $d_size -gt 0 ]]; then
                    diff=$((t_size - d_size))
                    [[ $diff -lt 0 ]] && diff=$((-diff))
                    pct=$((diff * 100 / d_size))
                    if [[ $pct -lt 5 ]]; then
                        status="≈ CLOSE"
                    else
                        status="✗ DIFFERENT"
                    fi
                fi
            fi

            echo ".,$d_name,$d_size,$d_name,$t_size,$d_hash,$t_hash,$status" >> "$OUTPUT"
            printf "%-40s %s │ %-40s %s │ %s\n" "${d_name:0:40}" "$d_size_fmt" "${d_name:0:40}" "$t_size_fmt" "$status"

            d_matched["$d_name"]=1
            t_matched["$d_name"]=1
            total=$((total + 1))
        fi
    done

    # Second pass: Match remaining files by similar size
    for d_name in "${d_files_list[@]}"; do
        [[ -n "${d_matched[$d_name]}" ]] && continue

        d_size=${d_sizes_array[$d_name]}
        d_hash=$(md5sum "$DIR_D/$d_name" 2>/dev/null | awk '{print $1}')
        d_size_fmt=$(format_size "$d_size")

        best_match=""
        best_match_diff=999999999

        for t_name in "${t_files_list[@]}"; do
            [[ -n "${t_matched[$t_name]}" ]] && continue

            t_size=${t_sizes_array[$t_name]}
            size_diff=$((d_size - t_size))
            [[ $size_diff -lt 0 ]] && size_diff=$((-size_diff))

            if [[ $size_diff -lt 5242880 ]]; then
                if [[ $size_diff -lt $best_match_diff ]]; then
                    best_match="$t_name"
                    best_match_diff=$size_diff
                fi
            fi
        done

        if [[ -n "$best_match" ]]; then
            t_name="$best_match"
            t_size=${t_sizes_array[$t_name]}
            t_hash=$(md5sum "$DIR_T/$t_name" 2>/dev/null | awk '{print $1}')
            t_size_fmt=$(format_size "$t_size")

            status=""
            if [[ "$d_size" -eq "$t_size" ]]; then
                if [[ "$d_hash" == "$t_hash" ]]; then
                    status="✓ PERFECT"
                    matched=$((matched + 1))
                else
                    status="~ SIZE_OK"
                fi
            else
                if [[ $d_size -gt 0 ]]; then
                    diff=$((t_size - d_size))
                    [[ $diff -lt 0 ]] && diff=$((-diff))
                    pct=$((diff * 100 / d_size))
                    if [[ $pct -lt 5 ]]; then
                        status="≈ CLOSE"
                    else
                        status="✗ DIFFERENT"
                    fi
                fi
            fi

            echo ".,$d_name,$d_size,$t_name,$t_size,$d_hash,$t_hash,$status" >> "$OUTPUT"
            printf "%-40s %s │ %-40s %s │ %s\n" "${d_name:0:40}" "$d_size_fmt" "${t_name:0:40}" "$t_size_fmt" "$status"

            d_matched["$d_name"]=1
            t_matched["$t_name"]=1
            total=$((total + 1))
        else
            t_size_fmt="      -"
            status="← ONLY_D"
            echo ".,$d_name,$d_size,NOTFOUND,0,$d_hash,,MISSING" >> "$OUTPUT"
            printf "%-40s %s │ %-40s %s │ %s\n" "${d_name:0:40}" "$d_size_fmt" "" "$t_size_fmt" "$status"
            total=$((total + 1))
        fi
    done

    # Third pass: Show remaining files only in t
    for t_name in "${t_files_list[@]}"; do
        [[ -n "${t_matched[$t_name]}" ]] && continue

        t_size=${t_sizes_array[$t_name]}
        t_hash=$(md5sum "$DIR_T/$t_name" 2>/dev/null | awk '{print $1}')
        t_size_fmt=$(format_size "$t_size")
        d_size_fmt="      -"
        status="→ ONLY_T"

        echo ".,NOTFOUND,0,$t_name,$t_size,,t_hash,MISSING" >> "$OUTPUT"
        printf "%-40s %s │ %-40s %s │ %s\n" "" "$d_size_fmt" "${t_name:0:40}" "$t_size_fmt" "$status"
        total=$((total + 1))
    done

    echo ""
    printf "%s\n" "$(printf '═%.0s' {1..130})"
    echo "Subdir Summary: Total=$total, Perfect=$matched"
    echo ""
    echo ""

    # Now process subdirectories
    find "$DIR_D" -mindepth 1 -type d | sort | while read subdir_path_d; do
        # Extract relative path
        subdir=$(echo "$subdir_path_d" | sed "s|^$DIR_D/||")

        # Check if should be excluded
        if should_exclude "$subdir" "$EXCLUDE_PATTERNS"; then
            excluded_count=$((excluded_count + 1))
            continue
        fi

        # Build corresponding path in DIR_T
        subdir_path_t="$DIR_T/$subdir"

        # Skip if corresponding directory doesn't exist in DIR_T
        if [[ ! -d "$subdir_path_t" ]]; then
            continue
        fi

        # Count files in this directory only (not in subdirectories)
        d_file_count=$(find "$subdir_path_d" -maxdepth 1 -type f 2>/dev/null | wc -l)
        t_file_count=$(find "$subdir_path_t" -maxdepth 1 -type f 2>/dev/null | wc -l)

        # Skip if no files in either directory
        if [[ $d_file_count -eq 0 && $t_file_count -eq 0 ]]; then
            continue
        fi

        processed_count=$((processed_count + 1))

        echo "════════════════════════════════════════════════════════════════════════════════"
        echo "Comparing: $subdir"
        echo "════════════════════════════════════════════════════════════════════════════════"
        echo ""

        # Create header
        printf "%-40s %-10s │ %-40s %-10s │ Status\n" "D_FILES" "Size" "T_FILES" "Size"
        printf "%s\n" "$(printf '═%.0s' {1..130})"

        # Get sorted lists of files with sizes
        declare -A d_files_array t_files_array
        declare -A d_sizes_array t_sizes_array
        declare -a d_files_list t_files_list

        # Build arrays for DIR_D files
        while IFS= read -r d_name; do
            [[ -z "$d_name" ]] && continue
            d_size=$(stat -c%s "$subdir_path_d/$d_name" 2>/dev/null || stat -f%z "$subdir_path_d/$d_name" 2>/dev/null)
            d_files_array["$d_name"]=1
            d_sizes_array["$d_name"]=$d_size
            d_files_list+=("$d_name")
        done < <(find "$subdir_path_d" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort -V)

        # Build arrays for DIR_T files
        while IFS= read -r t_name; do
            [[ -z "$t_name" ]] && continue
            t_size=$(stat -c%s "$subdir_path_t/$t_name" 2>/dev/null || stat -f%z "$subdir_path_t/$t_name" 2>/dev/null)
            t_files_array["$t_name"]=1
            t_sizes_array["$t_name"]=$t_size
            t_files_list+=("$t_name")
        done < <(find "$subdir_path_t" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort -V)

        # Track matched files
        declare -A d_matched t_matched
        total=0
        matched=0

        # First pass: Match files by exact name
        for d_name in "${d_files_list[@]}"; do
            if [[ -n "${t_files_array[$d_name]}" ]]; then
                d_size=${d_sizes_array[$d_name]}
                t_size=${t_sizes_array[$d_name]}
                d_hash=$(md5sum "$subdir_path_d/$d_name" 2>/dev/null | awk '{print $1}')
                t_hash=$(md5sum "$subdir_path_t/$d_name" 2>/dev/null | awk '{print $1}')
                d_size_fmt=$(format_size "$d_size")
                t_size_fmt=$(format_size "$t_size")

                # Determine match status
                status=""
                if [[ "$d_size" -eq "$t_size" ]]; then
                    if [[ "$d_hash" == "$t_hash" ]]; then
                        status="✓ PERFECT"
                        matched=$((matched + 1))
                    else
                        status="~ SIZE_OK"
                    fi
                else
                    if [[ $d_size -gt 0 ]]; then
                        diff=$((t_size - d_size))
                        [[ $diff -lt 0 ]] && diff=$((-diff))
                        pct=$((diff * 100 / d_size))
                        if [[ $pct -lt 5 ]]; then
                            status="≈ CLOSE"
                        else
                            status="✗ DIFFERENT"
                        fi
                    fi
                fi

                echo "$subdir,$d_name,$d_size,$d_name,$t_size,$d_hash,$t_hash,$status" >> "$OUTPUT"
                printf "%-40s %s │ %-40s %s │ %s\n" "${d_name:0:40}" "$d_size_fmt" "${d_name:0:40}" "$t_size_fmt" "$status"

                d_matched["$d_name"]=1
                t_matched["$d_name"]=1
                total=$((total + 1))
            fi
        done

        # Second pass: Match remaining files by similar size and name
        for d_name in "${d_files_list[@]}"; do
            [[ -n "${d_matched[$d_name]}" ]] && continue

            d_size=${d_sizes_array[$d_name]}
            d_hash=$(md5sum "$subdir_path_d/$d_name" 2>/dev/null | awk '{print $1}')
            d_size_fmt=$(format_size "$d_size")

            # Find best matching file in t by size similarity and name
            best_match=""
            best_match_diff=999999999

            for t_name in "${t_files_list[@]}"; do
                [[ -n "${t_matched[$t_name]}" ]] && continue

                t_size=${t_sizes_array[$t_name]}
                size_diff=$((d_size - t_size))
                [[ $size_diff -lt 0 ]] && size_diff=$((-size_diff))

                # Only consider if size difference < 5MB
                if [[ $size_diff -lt 5242880 ]]; then
                    if [[ $size_diff -lt $best_match_diff ]]; then
                        best_match="$t_name"
                        best_match_diff=$size_diff
                    fi
                fi
            done

            if [[ -n "$best_match" ]]; then
                t_name="$best_match"
                t_size=${t_sizes_array[$t_name]}
                t_hash=$(md5sum "$subdir_path_t/$t_name" 2>/dev/null | awk '{print $1}')
                t_size_fmt=$(format_size "$t_size")

                status=""
                if [[ "$d_size" -eq "$t_size" ]]; then
                    if [[ "$d_hash" == "$t_hash" ]]; then
                        status="✓ PERFECT"
                        matched=$((matched + 1))
                    else
                        status="~ SIZE_OK"
                    fi
                else
                    if [[ $d_size -gt 0 ]]; then
                        diff=$((t_size - d_size))
                        [[ $diff -lt 0 ]] && diff=$((-diff))
                        pct=$((diff * 100 / d_size))
                        if [[ $pct -lt 5 ]]; then
                            status="≈ CLOSE"
                        else
                            status="✗ DIFFERENT"
                        fi
                    fi
                fi

                echo "$subdir,$d_name,$d_size,$t_name,$t_size,$d_hash,$t_hash,$status" >> "$OUTPUT"
                printf "%-40s %s │ %-40s %s │ %s\n" "${d_name:0:40}" "$d_size_fmt" "${t_name:0:40}" "$t_size_fmt" "$status"

                d_matched["$d_name"]=1
                t_matched["$t_name"]=1
                total=$((total + 1))
            else
                # No match found in t
                t_size_fmt="      -"
                status="← ONLY_D"
                echo "$subdir,$d_name,$d_size,NOTFOUND,0,$d_hash,,MISSING" >> "$OUTPUT"
                printf "%-40s %s │ %-40s %s │ %s\n" "${d_name:0:40}" "$d_size_fmt" "" "$t_size_fmt" "$status"
                total=$((total + 1))
            fi
        done

        # Third pass: Show remaining files only in t
        for t_name in "${t_files_list[@]}"; do
            [[ -n "${t_matched[$t_name]}" ]] && continue

            t_size=${t_sizes_array[$t_name]}
            t_hash=$(md5sum "$subdir_path_t/$t_name" 2>/dev/null | awk '{print $1}')
            t_size_fmt=$(format_size "$t_size")
            d_size_fmt="      -"
            status="→ ONLY_T"

            echo "$subdir,NOTFOUND,0,$t_name,$t_size,,t_hash,MISSING" >> "$OUTPUT"
            printf "%-40s %s │ %-40s %s │ %s\n" "" "$d_size_fmt" "${t_name:0:40}" "$t_size_fmt" "$status"
            total=$((total + 1))
        done

        echo ""
        printf "%s\n" "$(printf '═%.0s' {1..130})"
        echo "Subdir Summary: Total=$total, Perfect=$matched"
        echo ""
        echo ""
    done
else
    # ROOT LEVEL ONLY MODE: Compare files only in root directories
    echo "Comparing files in the given directories (not recursing into subdirectories)..."
    excluded_count=0
    processed_count=0

    # Check if root directory should be excluded
    if should_exclude "" "$EXCLUDE_PATTERNS"; then
        echo "Root directory matches exclusion pattern."
        exit 0
    fi

    # Count files only in the root directories (not in any subdirectories)
    d_file_count=$(find "$DIR_D" -maxdepth 1 -type f 2>/dev/null | wc -l)
    t_file_count=$(find "$DIR_T" -maxdepth 1 -type f 2>/dev/null | wc -l)

    # Skip if no files in either directory
    if [[ $d_file_count -eq 0 && $t_file_count -eq 0 ]]; then
        echo "No files found in the root directories to compare."
        exit 0
    fi

    # We have files to compare, so process them
    subdir=""
    subdir_path_d="$DIR_D"
    subdir_path_t="$DIR_T"

    if [[ -d "$subdir_path_t" ]]; then

        processed_count=$((processed_count + 1))

        echo "════════════════════════════════════════════════════════════════════════════════"
        echo "Comparing: $DIR_D vs $DIR_T (root level files only)"
        echo "════════════════════════════════════════════════════════════════════════════════"
        echo ""

        # Create header
        printf "%-40s %-10s │ %-40s %-10s │ Status\n" "D_FILES" "Size" "T_FILES" "Size"
        printf "%s\n" "$(printf '═%.0s' {1..130})"

        # Get sorted lists of files with sizes
        declare -A d_files_array t_files_array
        declare -A d_sizes_array t_sizes_array
        declare -a d_files_list t_files_list

        # Build arrays for DIR_D files
        while IFS= read -r d_name; do
            [[ -z "$d_name" ]] && continue
            d_size=$(stat -c%s "$subdir_path_d/$d_name" 2>/dev/null || stat -f%z "$subdir_path_d/$d_name" 2>/dev/null)
            d_files_array["$d_name"]=1
            d_sizes_array["$d_name"]=$d_size
            d_files_list+=("$d_name")
        done < <(find "$subdir_path_d" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort -V)

        # Build arrays for DIR_T files
        while IFS= read -r t_name; do
            [[ -z "$t_name" ]] && continue
            t_size=$(stat -c%s "$subdir_path_t/$t_name" 2>/dev/null || stat -f%z "$subdir_path_t/$t_name" 2>/dev/null)
            t_files_array["$t_name"]=1
            t_sizes_array["$t_name"]=$t_size
            t_files_list+=("$t_name")
        done < <(find "$subdir_path_t" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort -V)

        # Track matched files
        declare -A d_matched t_matched
        total=0
        matched=0

        # First pass: Match files by exact name
        for d_name in "${d_files_list[@]}"; do
            if [[ -n "${t_files_array[$d_name]}" ]]; then
                d_size=${d_sizes_array[$d_name]}
                t_size=${t_sizes_array[$d_name]}
                d_hash=$(md5sum "$subdir_path_d/$d_name" 2>/dev/null | awk '{print $1}')
                t_hash=$(md5sum "$subdir_path_t/$d_name" 2>/dev/null | awk '{print $1}')
                d_size_fmt=$(format_size "$d_size")
                t_size_fmt=$(format_size "$t_size")

                # Determine match status
                status=""
                if [[ "$d_size" -eq "$t_size" ]]; then
                    if [[ "$d_hash" == "$t_hash" ]]; then
                        status="✓ PERFECT"
                        matched=$((matched + 1))
                    else
                        status="~ SIZE_OK"
                    fi
                else
                    if [[ $d_size -gt 0 ]]; then
                        diff=$((t_size - d_size))
                        [[ $diff -lt 0 ]] && diff=$((-diff))
                        pct=$((diff * 100 / d_size))
                        if [[ $pct -lt 5 ]]; then
                            status="≈ CLOSE"
                        else
                            status="✗ DIFFERENT"
                        fi
                    fi
                fi

                echo ",$d_name,$d_size,$d_name,$t_size,$d_hash,$t_hash,$status" >> "$OUTPUT"
                printf "%-40s %s │ %-40s %s │ %s\n" "${d_name:0:40}" "$d_size_fmt" "${d_name:0:40}" "$t_size_fmt" "$status"

                d_matched["$d_name"]=1
                t_matched["$d_name"]=1
                total=$((total + 1))
            fi
        done

        # Second pass: Match remaining files by similar size and name
        for d_name in "${d_files_list[@]}"; do
            [[ -n "${d_matched[$d_name]}" ]] && continue

            d_size=${d_sizes_array[$d_name]}
            d_hash=$(md5sum "$subdir_path_d/$d_name" 2>/dev/null | awk '{print $1}')
            d_size_fmt=$(format_size "$d_size")

            # Find best matching file in t by size similarity and name
            best_match=""
            best_match_diff=999999999

            for t_name in "${t_files_list[@]}"; do
                [[ -n "${t_matched[$t_name]}" ]] && continue

                t_size=${t_sizes_array[$t_name]}
                size_diff=$((d_size - t_size))
                [[ $size_diff -lt 0 ]] && size_diff=$((-size_diff))

                # Only consider if size difference < 5MB
                if [[ $size_diff -lt 5242880 ]]; then
                    if [[ $size_diff -lt $best_match_diff ]]; then
                        best_match="$t_name"
                        best_match_diff=$size_diff
                    fi
                fi
            done

            if [[ -n "$best_match" ]]; then
                t_name="$best_match"
                t_size=${t_sizes_array[$t_name]}
                t_hash=$(md5sum "$subdir_path_t/$t_name" 2>/dev/null | awk '{print $1}')
                t_size_fmt=$(format_size "$t_size")

                status=""
                if [[ "$d_size" -eq "$t_size" ]]; then
                    if [[ "$d_hash" == "$t_hash" ]]; then
                        status="✓ PERFECT"
                        matched=$((matched + 1))
                    else
                        status="~ SIZE_OK"
                    fi
                else
                    if [[ $d_size -gt 0 ]]; then
                        diff=$((t_size - d_size))
                        [[ $diff -lt 0 ]] && diff=$((-diff))
                        pct=$((diff * 100 / d_size))
                        if [[ $pct -lt 5 ]]; then
                            status="≈ CLOSE"
                        else
                            status="✗ DIFFERENT"
                        fi
                    fi
                fi

                echo ",$d_name,$d_size,$t_name,$t_size,$d_hash,$t_hash,$status" >> "$OUTPUT"
                printf "%-40s %s │ %-40s %s │ %s\n" "${d_name:0:40}" "$d_size_fmt" "${t_name:0:40}" "$t_size_fmt" "$status"

                d_matched["$d_name"]=1
                t_matched["$t_name"]=1
                total=$((total + 1))
            else
                # No match found in t
                t_size_fmt="      -"
                status="← ONLY_D"
                echo ",$d_name,$d_size,NOTFOUND,0,$d_hash,,MISSING" >> "$OUTPUT"
                printf "%-40s %s │ %-40s %s │ %s\n" "${d_name:0:40}" "$d_size_fmt" "" "$t_size_fmt" "$status"
                total=$((total + 1))
            fi
        done

        # Third pass: Show remaining files only in t
        for t_name in "${t_files_list[@]}"; do
            [[ -n "${t_matched[$t_name]}" ]] && continue

            t_size=${t_sizes_array[$t_name]}
            t_hash=$(md5sum "$subdir_path_t/$t_name" 2>/dev/null | awk '{print $1}')
            t_size_fmt=$(format_size "$t_size")
            d_size_fmt="      -"
            status="→ ONLY_T"

            echo ",NOTFOUND,0,$t_name,$t_size,,t_hash,MISSING" >> "$OUTPUT"
            printf "%-40s %s │ %-40s %s │ %s\n" "" "$d_size_fmt" "${t_name:0:40}" "$t_size_fmt" "$status"
            total=$((total + 1))
        done

        echo ""
        echo "Subdir Summary: Total=$total, Perfect=$matched"
        echo ""
        echo ""
    fi
fi

echo ""
echo "════════════════════════════════════════════════════════════════════════════════"
echo "FINAL SUMMARY"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""

# Parse CSV for summary statistics
if [[ -f "$OUTPUT" ]]; then
    total_files=$(tail -n +2 "$OUTPUT" | wc -l)
    perfect_files=$(tail -n +2 "$OUTPUT" | awk -F',' '$8 ~ /PERFECT/ {c++} END {print c+0}')
    size_ok_files=$(tail -n +2 "$OUTPUT" | awk -F',' '$8 ~ /SIZE_OK/ {c++} END {print c+0}')
    close_files=$(tail -n +2 "$OUTPUT" | awk -F',' '$8 ~ /CLOSE/ {c++} END {print c+0}')
    different_files=$(tail -n +2 "$OUTPUT" | awk -F',' '$8 ~ /DIFFERENT/ {c++} END {print c+0}')
    missing_files=$(tail -n +2 "$OUTPUT" | awk -F',' '$8 ~ /MISSING/ {c++} END {print c+0}')

    echo "Summary Statistics:"
    echo "  Total files compared:     $total_files"
    echo "  Perfect matches:          $perfect_files"
    echo "  Same size (diff hash):    $size_ok_files"
    echo "  Close size (<5% diff):    $close_files"
    echo "  Different size (>5%):     $different_files"
    echo "  Missing files:            $missing_files"
    echo ""

    # Show missing files
    if [[ $missing_files -gt 0 ]]; then
        echo "════════════════════════════════════════════════════════════════════════════════"
        echo "MISSING FILES (not found in both directories): $missing_files files"
        echo "════════════════════════════════════════════════════════════════════════════════"
        if [[ $missing_files -le 15 ]]; then
            tail -n +2 "$OUTPUT" | awk -F',' '$8 ~ /MISSING/ {
                if ($2 == "NOTFOUND") {
                    printf "  → ONLY_T: %-50s [%10s B] in %s\n", $4, $5, $1
                } else {
                    printf "  ← ONLY_D: %-50s [%10s B] in %s\n", $2, $3, $1
                }
            }' | sort
        else
            echo "  Details available in: $OUTPUT"
        fi
        echo ""
    fi

    # Show same size but different hash files
    if [[ $size_ok_files -gt 0 ]]; then
        echo "════════════════════════════════════════════════════════════════════════════════"
        echo "SAME SIZE BUT DIFFERENT HASH FILES: $size_ok_files files"
        echo "════════════════════════════════════════════════════════════════════════════════"
        if [[ $size_ok_files -le 15 ]]; then
            tail -n +2 "$OUTPUT" | awk -F',' '$8 ~ /SIZE_OK/ {
                d_name = $2
                d_size = $3
                t_name = $4
                t_size = $5
                d_hash = $6
                t_hash = $7
                subdir = $1
                printf "  %s/\n", (subdir == "." ? "ROOT" : subdir)
                printf "    D: %-50s [%12s B] (hash: %s)\n", d_name, d_size, d_hash
                printf "    T: %-50s [%12s B] (hash: %s)\n", t_name, t_size, t_hash
                printf "\n"
            }' | sort
        else
            echo "  Details available in: $OUTPUT"
        fi
        echo ""
    fi

    # Show close size files
    if [[ $close_files -gt 0 ]]; then
        echo "════════════════════════════════════════════════════════════════════════════════"
        echo "CLOSE SIZE FILES (<5% size difference): $close_files files"
        echo "════════════════════════════════════════════════════════════════════════════════"
        if [[ $close_files -le 15 ]]; then
            tail -n +2 "$OUTPUT" | awk -F',' '$8 ~ /CLOSE/ {
                d_name = $2
                d_size = $3
                t_name = $4
                t_size = $5
                subdir = $1
                if (d_size > 0) {
                    diff = t_size - d_size
                    if (diff < 0) diff = -diff
                    pct = (diff * 100) / d_size
                    printf "  %s/\n", (subdir == "." ? "ROOT" : subdir)
                    printf "    D: %-50s [%12s B]\n", d_name, d_size
                    printf "    T: %-50s [%12s B]\n", t_name, t_size
                    printf "    → Difference: %s B (%+.1f%% %s)\n", diff, pct, (t_size > d_size ? "larger" : "smaller")
                    printf "\n"
                }
            }' | sort
        else
            echo "  Details available in: $OUTPUT"
        fi
        echo ""
    fi

    # Show different sized files
    if [[ $different_files -gt 0 ]]; then
        echo "════════════════════════════════════════════════════════════════════════════════"
        echo "DIFFERENT SIZED FILES (>5% size difference): $different_files files"
        echo "════════════════════════════════════════════════════════════════════════════════"
        if [[ $different_files -le 15 ]]; then
            tail -n +2 "$OUTPUT" | awk -F',' '$8 ~ /DIFFERENT/ {
                d_name = $2
                d_size = $3
                t_name = $4
                t_size = $5
                subdir = $1
                if (d_size > 0) {
                    diff = t_size - d_size
                    if (diff < 0) diff = -diff
                    pct = (diff * 100) / d_size
                    printf "  %s/\n", (subdir == "." ? "ROOT" : subdir)
                    printf "    D: %-50s [%12s B] (%s)\n", d_name, d_size, $6
                    printf "    T: %-50s [%12s B] (%s)\n", t_name, t_size, $7
                    printf "    → Difference: %s B (%+.1f%% %s)\n", diff, pct, (t_size > d_size ? "larger" : "smaller")
                    printf "\n"
                }
            }' | sort
        else
            echo "  Details available in: $OUTPUT"
        fi
        echo ""
    fi

    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "All subdirectories processed."
    echo "Output CSV: $OUTPUT"
else
    echo "Error: CSV file not found: $OUTPUT"
fi
