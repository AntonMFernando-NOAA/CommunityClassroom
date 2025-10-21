#!/bin/bash

################################################################################
# Compare directories - recursively process subdirectories
# Shows side-by-side table for each subdirectory pair
################################################################################

# Show help
show_help() {
    cat << 'EOF'
USAGE
  compare_recursive_subdirs.sh <dir_d> <dir_t> [output.csv]

DESCRIPTION
  Recursively compares all subdirectories between two directory trees.
  Files are matched by:
    1. Exact filename match
    2. Similar file size (within 5MB tolerance) if no exact match

  Generates side-by-side comparison tables and a detailed CSV report.

ARGUMENTS
  dir_d            Directory tree 1 (development/source)
  dir_t            Directory tree 2 (test/target)
  output.csv       Optional output CSV file (default: output.csv)

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
  # Compare two directories and save results to output.csv
  ./compare_recursive_subdirs.sh /path/to/dir_d /path/to/dir_t

  # Compare and save results to custom filename
  ./compare_recursive_subdirs.sh /path/to/dir_d /path/to/dir_t results.csv

  # Show this help message
  ./compare_recursive_subdirs.sh -h
  ./compare_recursive_subdirs.sh --help

CSV COLUMNS
  subdir            Relative subdirectory path
  d_file            Filename in DIR_D
  d_size            File size in DIR_D (bytes)
  t_file            Filename in DIR_T
  t_size            File size in DIR_T (bytes)
  d_hash            MD5 hash of file in DIR_D
  t_hash            MD5 hash of file in DIR_T
  status            Comparison status (PERFECT, SIZE_OK, CLOSE, DIFFERENT, MISSING)

EOF
}

# Check for help flag
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    show_help
    exit 0
fi

DIR_D="$1"
DIR_T="$2"
OUTPUT="${3:-output.csv}"

if [[ ! -d "$DIR_D" ]] || [[ ! -d "$DIR_T" ]]; then
    echo "Usage: $0 <dir_d> <dir_t> [output.csv]"
    echo "       $0 -h (for help)"
    exit 1
fi

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

echo "DIR_D: $DIR_D"
echo "DIR_T: $DIR_T"
echo ""

# CSV header
echo "subdir,d_file,d_size,t_file,t_size,d_hash,t_hash,status" > "$OUTPUT"

# Get all subdirectories from DIR_D (ALL levels, not just leaves)
echo "Getting all subdirectories from DIR_D..."

find "$DIR_D" -mindepth 1 -type d | sort | while read subdir_path_d; do
    # Extract relative path
    subdir=$(echo "$subdir_path_d" | sed "s|^$DIR_D/||")

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

echo ""
echo "════════════════════════════════════════════════════════════════════════════════"
echo "FINAL SUMMARY"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""

# Parse CSV for summary statistics
if [[ -f "$OUTPUT" ]]; then
    total_files=$(tail -n +2 "$OUTPUT" | wc -l)
    perfect_files=$(tail -n +2 "$OUTPUT" | awk -F',' '$8 == "PERFECT" {c++} END {print c+0}')
    size_ok_files=$(tail -n +2 "$OUTPUT" | awk -F',' '$8 == "SIZE_OK" {c++} END {print c+0}')
    close_files=$(tail -n +2 "$OUTPUT" | awk -F',' '$8 == "CLOSE" {c++} END {print c+0}')
    different_files=$(tail -n +2 "$OUTPUT" | awk -F',' '$8 == "DIFFERENT" {c++} END {print c+0}')
    missing_files=$(tail -n +2 "$OUTPUT" | awk -F',' '$8 == "MISSING" {c++} END {print c+0}')

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
        echo "MISSING FILES (not found in both directories):"
        echo "════════════════════════════════════════════════════════════════════════════════"
        tail -n +2 "$OUTPUT" | awk -F',' '$8 == "MISSING" {
            if ($2 == "NOTFOUND") {
                printf "  → ONLY_T: %-50s [%10s] in %s\n", $4, $5" B", $1
            } else {
                printf "  ← ONLY_D: %-50s [%10s] in %s\n", $2, $3" B", $1
            }
        }' | sort
        echo ""
    fi

    # Show different sized files
    if [[ $different_files -gt 0 ]]; then
        echo "════════════════════════════════════════════════════════════════════════════════"
        echo "DIFFERENT SIZED FILES (>5% size difference):"
        echo "════════════════════════════════════════════════════════════════════════════════"
        tail -n +2 "$OUTPUT" | awk -F',' '$8 == "DIFFERENT" {
            d_name = $2
            d_size = $3
            t_name = $4
            t_size = $5
            subdir = $1
            if (d_size > 0) {
                diff = t_size - d_size
                if (diff < 0) diff = -diff
                pct = (diff * 100) / d_size
                printf "  %s\n", subdir "/"
                printf "    D: %-50s [%12s B] (%s)\n", d_name, d_size, $6
                printf "    T: %-50s [%12s B] (%s)\n", t_name, t_size, $7
                printf "    → Difference: %s B (%+.1f%% %s)\n", diff, pct, (t_size > d_size ? "larger" : "smaller")
                printf "\n"
            }
        }' | sort
        echo ""
    fi

    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "All subdirectories processed."
    echo "Output CSV: $OUTPUT"
else
    echo "Error: CSV file not found: $OUTPUT"
fi
