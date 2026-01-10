#!/bin/bash
###############################################################################
# Script: run_all_tests.sh
# Description: Automate running workflow tests using generate_workflows.sh
#              and manage crontab entries for Rocoto workflows
#
# Usage: ./run_all_tests.sh <test_name|all|G|E|S|C> [suffix] [hpc_account]
#        test_name: specific test case name (e.g., C48_ATM) or "all" for all tests
#                   or G/E/S/C for GFS/GEFS/SFS/GCAFS test suites
#        suffix: tail to append to test name (e.g., "t", "t1", "dev") - defaults to "t"
#        hpc_account: defaults to platform-specific account
#
# Examples:
#   ./run_all_tests.sh C48_ATM t        # Creates C48_ATM_t
#   ./run_all_tests.sh all t1           # Creates all tests with _t1 suffix
###############################################################################

set -u

# Detect machine based on hostname
HOSTNAME=$(hostname -f)
if [[ "${HOSTNAME}" == *"wcoss2"* ]] || [[ "${HOSTNAME}" == *".wcoss2.ncep.noaa.gov" ]]; then
    MACHINE="wcoss2"
elif [[ "${HOSTNAME}" == *"hera"* ]] || [[ "${HOSTNAME}" == "hfe"* ]] || [[ "${HOSTNAME}" == *".HPC.MsState.Edu" ]]; then
    MACHINE="hera"
elif [[ "${HOSTNAME}" == *"gaea"* ]] || [[ "${HOSTNAME}" == "gaea"* ]]; then
    MACHINE="gaea"
else
    MACHINE="unknown"
fi

# Set paths based on machine
case "${MACHINE}" in
    "wcoss2")
        HOMEgfs="/lfs/h2/emc/global/noscrub/anton.fernando/global-workflow"
        RUNTESTS="/lfs/h2/emc/stmp/anton.fernando/RUNTESTS"
        HPC_ACCOUNT_DEFAULT="GFS-DEV"
        ;;
    "hera")
        HOMEgfs="${HOMEgfs:-/scratch3/NCEPDEV/global/Anton.Fernando/global-workflow}"
        RUNTESTS="${RUNTESTS:-/scratch3/NCEPDEV/global/$USER/RUNTESTS}"
        HPC_ACCOUNT_DEFAULT="fv3-cpu"
        ;;
    "gaea")
        HOMEgfs="/gpfs/f6/drsa-precip3/scratch/Anton.Fernando/global-workflow"
        RUNTESTS="/gpfs/f6/drsa-precip3/scratch/Anton.Fernando/RUNTESTS"
        HPC_ACCOUNT_DEFAULT="drsa-precip3"
        ;;
    *)
        # Default to Hera paths if machine not recognized
        HOMEgfs="${HOMEgfs:-/scratch3/NCEPDEV/global/Anton.Fernando/global-workflow}"
        RUNTESTS="${RUNTESTS:-/scratch3/NCEPDEV/global/$USER/RUNTESTS}"
        HPC_ACCOUNT_DEFAULT="fv3-cpu"
        ;;
esac

###############################################################################
# Function: setup_environment
# Description: Set up the environment for the detected machine
###############################################################################
setup_environment() {
  echo "Setting up environment for ${MACHINE}..."

  # Set MACHINE_ID based on detected machine
  case "${MACHINE}" in
    "wcoss2")
      MACHINE_ID="wcoss2"
      ;;
    "hera")
      MACHINE_ID="hera"
      ;;
    "gaea")
      MACHINE_ID="gaea"
      ;;
    *)
      MACHINE_ID=""
      ;;
  esac

  # Source machine detection script if it exists
  if [[ -f "${HOMEgfs}/ush/detect_machine.sh" ]]; then
    source "${HOMEgfs}/ush/detect_machine.sh"
    if [[ -n "${MACHINE_ID}" ]]; then
      echo "Machine ID detected: ${MACHINE_ID}"
    else
      echo "Machine ID not detected by detect_machine.sh"
    fi
  else
    echo -e "${YELLOW}Warning: detect_machine.sh not found at ${HOMEgfs}/ush/detect_machine.sh${NC}"
  fi

  # Load modules if module command is available
  if command -v module >/dev/null 2>&1; then
    module use "${HOMEgfs}/modulefiles" 2>/dev/null || true
    if [[ -n "${MACHINE_ID}" ]]; then
      module load "module_gwsetup.${MACHINE_ID}" 2>/dev/null || true
    fi
  fi

  # Source workflow setup
  if [[ -f "${HOMEgfs}/dev/ush/gw_setup.sh" ]]; then
    source "${HOMEgfs}/dev/ush/gw_setup.sh"
    echo "Workflow environment setup completed"
  else
    echo -e "${YELLOW}Warning: gw_setup.sh not found at ${HOMEgfs}/dev/ush/gw_setup.sh${NC}"
  fi

  echo ""
}

###############################################################################
# Function: show_help
# Description: Display help information
###############################################################################
show_help() {
    cat << EOF
$(basename "$0") - Automate running workflow tests with automatic platform detection

USAGE:
    $(basename "$0") <test_name|all|G|E|S|C> [suffix] [hpc_account]
    $(basename "$0") [--help|-h]

DESCRIPTION:
    This script automates the creation and execution of Global Workflow test cases
    using generate_workflows.sh. It automatically detects the HPC platform and
    configures appropriate paths and test lists.

ARGUMENTS:
    test_name       Specific test case name (e.g., C48_ATM) or test suite:
                    - all: All available test cases
                    - G/gfs: GFS test cases only
                    - E/gefs: GEFS test cases only
                    - S/sfs: SFS test cases only
                    - C/gcafs: GCAFS test cases only
    suffix          (Optional) Tail to append to test name (e.g., "t", "t1", "dev")
                    Defaults to "t" if not specified
    hpc_account     (Optional) HPC account to use (defaults to platform-specific account)

OPTIONS:
    --help, -h      Show this help message

PLATFORM DETECTION:
    The script automatically detects the HPC platform based on hostname:

    WCOSS2:         Includes extended test cases (C48_S2SW_extended, C96_atm3DVar_extended)
                    Uses paths: /lfs/h2/emc/global/noscrub/anton.fernando/global-workflow
                                /lfs/h2/emc/stmp/anton.fernando/RUNTESTS
                    Default account: GFS-DEV

    Hera:           Standard test cases only
                    Uses paths: /scratch3/NCEPDEV/global/Anton.Fernando/global-workflow
                                /scratch3/NCEPDEV/global/\$USER/RUNTESTS
                    Default account: fv3-cpu

    Gaea:           Standard test cases only
                    Uses paths: /gpfs/f6/drsa-precip3/scratch/Anton.Fernando/global-workflow
                                /gpfs/f6/drsa-precip3/scratch/Anton.Fernando/RUNTESTS
                    Default account: drsa-precip3
    C96_gcafs_cycled           C96_gcafs_cycled_noDA    C96mx100_S2S
    C96mx025_S2S

EXAMPLES:
    # Run single test case (suffix defaults to "t")
    $(basename "$0") C48_ATM

    # Run single test case with custom suffix
    $(basename "$0") C48_ATM t1

    # Run all test cases
    $(basename "$0") all

    # Run specific test suites
    $(basename "$0") G         # GFS tests only (suffix defaults to "t")
    $(basename "$0") E t       # GEFS tests only
    $(basename "$0") S t       # SFS tests only
    $(basename "$0") C t       # GCAFS tests only

    # Show this help
    $(basename "$0") --help

OUTPUT:
    - Creates experiment directories in RUNTESTS/EXPDIR/
    - Generates Rocoto XML and database files
    - Updates crontab with workflow entries
    - Initiates Rocoto workflows
    - Logs all output to ~/utils/run_all_tests.log

NOTES:
    - The script automatically manages crontab entries
    - Failed experiments are reported but don't stop execution
    - Use 'crontab -l' to view current entries
    - Use 'crontab -e' to manually edit crontab
EOF
}

# Parse arguments
if [[ $# -eq 0 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    show_help
    exit 0
fi

if [[ $# -lt 1 ]]; then
  echo "Error: Insufficient arguments"
  echo ""
  echo "Usage: $0 <test_name|all|G|E|S|C> [suffix] [hpc_account]"
  echo "       $0 [--help|-h]"
  echo ""
  echo "Run '$0 --help' for detailed information"
  exit 1
fi

TEST_NAME="${1}"
TEST_SUFFIX="${2:-t}"  # Default to "t" if not provided
HPC_ACCOUNT="${3:-${HPC_ACCOUNT_DEFAULT}}"

# Detect global-workflow home directory
# HOMEgfs and RUNTESTS are now set above based on machine detection

# Create single log file (overwrites previous run)
LOG_DIR="${HOME}/utils"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/run_all_tests.log"

# Clear previous log
> "${LOG_FILE}"

echo "Log file: ${LOG_FILE}"
echo ""

###############################################################################
# Function: get_yaml_system
# Description: Extract the 'net' field from a YAML file to determine system type
# Arguments:
#   $1 - YAML file path
# Returns: system name (gfs, gefs, gcafs, sfs) or empty string if not found
###############################################################################
get_yaml_system() {
  local yaml_file="${1}"
  local system=""

  # Extract the net field from the YAML
  if [[ -f "${yaml_file}" ]]; then
    system=$(grep -E '^  net:' "${yaml_file}" | sed 's/.*net:\s*//' | tr -d ' ')
  fi

  echo "${system}"
}

###############################################################################
# Function: categorize_test_cases
# Description: Categorize all available test cases by system type
###############################################################################
categorize_test_cases() {
  GFS_TEST_CASES=()
  GEFS_TEST_CASES=()
  SFS_TEST_CASES=()
  GCAFS_TEST_CASES=()

  for test_case in "${ALL_TEST_CASES[@]}"; do
    local yaml_file="${HOMEgfs}/dev/ci/cases/pr/${test_case}.yaml"
    local system=$(get_yaml_system "${yaml_file}")

    case "${system}" in
      "gfs")
        GFS_TEST_CASES+=("${test_case}")
        ;;
      "gefs")
        GEFS_TEST_CASES+=("${test_case}")
        ;;
      "sfs")
        SFS_TEST_CASES+=("${test_case}")
        ;;
      "gcafs")
        GCAFS_TEST_CASES+=("${test_case}")
        ;;
      *)
        # If system not recognized, add to GFS as default
        GFS_TEST_CASES+=("${test_case}")
        ;;
    esac
  done
}

# All available test cases
ALL_TEST_CASES=(
  "C48_ATM"
  "C48_S2SW"
  "C48_S2SWA_gefs"
  "C48mx500_3DVarAOWCDA"
  "C48mx500_hybAOWCDA"
  "C96C48_hybatmDA"
  "C96C48_hybatmsnowDA"
  "C96C48_hybatmsoilDA"
  "C96C48_ufs_hybatmDA"
  "C96C48_ufsgsi_hybatmDA"
  "C96C48mx500_S2SW_cyc_gfs"
  "C96_atm3DVar"
  "C96_gcafs_cycled"
  "C96_gcafs_cycled_noDA"
  "C96mx100_S2S"
  "C96mx025_S2S"
)

# Add extended tests for WCOSS2
if [[ "${MACHINE}" == "wcoss2" ]]; then
  ALL_TEST_CASES+=("C48_S2SW_extended")
  ALL_TEST_CASES+=("C96_atm3DVar_extended")
fi

# Categorize test cases by system
categorize_test_cases

# Determine which tests to run
case "${TEST_NAME}" in
  "all")
    TEST_CASES=("${ALL_TEST_CASES[@]}")
    echo "Running ALL test cases with suffix: ${TEST_SUFFIX}"
    ;;
  "G"|"gfs")
    TEST_CASES=("${GFS_TEST_CASES[@]}")
    echo "Running GFS test cases with suffix: ${TEST_SUFFIX}"
    ;;
  "E"|"gefs")
    TEST_CASES=("${GEFS_TEST_CASES[@]}")
    echo "Running GEFS test cases with suffix: ${TEST_SUFFIX}"
    ;;
  "S"|"sfs")
    TEST_CASES=("${SFS_TEST_CASES[@]}")
    echo "Running SFS test cases with suffix: ${TEST_SUFFIX}"
    ;;
  "C"|"gcafs")
    TEST_CASES=("${GCAFS_TEST_CASES[@]}")
    echo "Running GCAFS test cases with suffix: ${TEST_SUFFIX}"
    ;;
  *)
    # Validate test name exists in the list
    if [[ " ${ALL_TEST_CASES[@]} " =~ " ${TEST_NAME} " ]]; then
      TEST_CASES=("${TEST_NAME}")
      echo "Running single test case: ${TEST_NAME} with suffix: ${TEST_SUFFIX}"
    else
      echo "Error: Test case '${TEST_NAME}' not found in available tests"
      echo "Available tests: ${ALL_TEST_CASES[@]}"
      echo "Available test suites: G/gfs, E/gefs, S/sfs, C/gcafs, all"
      exit 1
    fi
    ;;
esac
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Temporary file for crontab entries
CRONTAB_ENTRIES_FILE=$(mktemp)
trap 'rm -f "${CRONTAB_ENTRIES_FILE}"' EXIT

###############################################################################
# Function: run_create_experiment
# Description: Run create_experiment.py for a test case (mimics gwtest)
# Arguments:
#   $1 - Test case name
#   $2 - Test suffix
###############################################################################
run_create_experiment() {
  local test_case="${1}"
  local test_suffix="${2}"
  local pslot="${test_case}_${test_suffix}"
  local yaml_file="${HOMEgfs}/dev/ci/cases/pr/${test_case}.yaml"

  echo -e "${YELLOW}Creating experiment for ${test_case} ${test_suffix}...${NC}"

  # Check if YAML file exists
  if [[ ! -f "${yaml_file}" ]]; then
    echo -e "${RED}✗ YAML file not found: ${yaml_file}${NC}"
    return 1
  fi

  # Change to workflow directory
  cd "${HOMEgfs}/dev/workflow" || return 1

  # Run generate_workflows.sh
  # Provide automatic responses: N for RUNTESTS removal, Y for DATAROOT removal
  # Send all output to log file only
  printf "N\nY\n" | HPC_ACCOUNT="${HPC_ACCOUNT}" \
  ./generate_workflows.sh -A "${HPC_ACCOUNT}" -y "${test_case}" -t "${test_suffix}" "${RUNTESTS}" >> "${LOG_FILE}" 2>&1

  local exit_code=${PIPESTATUS[1]}

  if [[ ${exit_code} -eq 0 ]]; then
    echo -e "${GREEN}✓ Successfully created experiment for ${test_case}${NC}"

    # Extract crontab entry from the generated .crontab file
    local crontab_file="${RUNTESTS}/EXPDIR/${pslot}/${pslot}.crontab"
    if [[ -f "${crontab_file}" ]]; then
      local crontab_line=$(grep "rocotorun" "${crontab_file}" || true)
      if [[ -n "${crontab_line}" ]]; then
        echo "${crontab_line}" >> "${CRONTAB_ENTRIES_FILE}"
        echo -e "${GREEN}  Crontab entry captured${NC}"
      else
        echo -e "${YELLOW}  No rocotorun entry found in ${crontab_file}${NC}"
      fi
    else
      echo -e "${YELLOW}  Crontab file not found: ${crontab_file}${NC}"
    fi
  else
    echo -e "${RED}✗ Failed to create experiment for ${test_case}${NC}"
  fi

  echo ""

  return ${exit_code}
}

###############################################################################
# Function: add_crontab_entries
# Description: Add crontab entries if they don't exist or are commented out
###############################################################################
add_crontab_entries() {
  if [[ ! -s "${CRONTAB_ENTRIES_FILE}" ]]; then
    echo -e "${YELLOW}No crontab entries to add${NC}"
    return 0
  fi

  echo -e "${YELLOW}Checking and updating crontab entries...${NC}"

  # Get current crontab
  local current_crontab=$(mktemp)
  crontab -l > "${current_crontab}" 2>/dev/null || true

  local updated=0

  while IFS= read -r crontab_entry; do
    # Extract the experiment name from the crontab line
    local exp_name=$(echo "${crontab_entry}" | grep -oP '(?<=/EXPDIR/)[^/]+(?=/)' || echo "")

    if [[ -z "${exp_name}" ]]; then
      echo -e "${RED}  Warning: Could not parse experiment name from: ${crontab_entry}${NC}"
      continue
    fi

    # Escape special characters for sed
    local exp_name_escaped=$(echo "${exp_name}" | sed 's/\[/\\[/g; s/\]/\\]/g; s/\./\\./g; s/\*/\\*/g; s/\^/\\^/g; s/\$/\\$/g; s/\//\\\//g')

    # Check if this entry exists (active or commented)
    if grep -qF "${exp_name}" "${current_crontab}"; then
      # Check if it's commented out
      if grep -q "^#.*${exp_name}" "${current_crontab}"; then
        echo -e "${YELLOW}  Uncommenting existing entry for ${exp_name}${NC}"
        # Use awk with variable to safely uncomment lines containing exp_name
        awk -v name="$exp_name_escaped" '$0 ~ name && /^#/ {sub(/^#/, "")} {print}' "${current_crontab}" > "${current_crontab}.tmp" && mv "${current_crontab}.tmp" "${current_crontab}"
        updated=1
      else
        echo -e "${GREEN}  Entry for ${exp_name} already exists and is active${NC}"
      fi
    else
      echo -e "${GREEN}  Adding new entry for ${exp_name}${NC}"
      echo "${crontab_entry}" >> "${current_crontab}"
      updated=1
    fi
  done < "${CRONTAB_ENTRIES_FILE}"

  # Update crontab if changes were made
  if [[ ${updated} -eq 1 ]]; then
    crontab "${current_crontab}"
    echo -e "${GREEN}✓ Crontab updated successfully${NC}"
  else
    echo -e "${GREEN}✓ No crontab changes needed${NC}"
  fi

  rm -f "${current_crontab}"
}

###############################################################################
# Function: run_rocoto_experiments
# Description: Execute rocotorun for all created experiments
# Arguments:
#   $1 - Test suffix (e.g., t1)
###############################################################################
run_rocoto_experiments() {
  local test_suffix="${1}"
  local runtests_expdir="${RUNTESTS}/EXPDIR"

  echo ""
  echo "=============================================================================="
  echo "                    RUNNING ROCOTO WORKFLOWS"
  echo "=============================================================================="

  for test_case in "${TEST_CASES[@]}"; do
    local exp_name="${test_case}_${test_suffix}"
    local exp_dir="${runtests_expdir}/${exp_name}"
    local db_file="${exp_name}.db"
    local xml_file="${exp_name}.xml"

    if [[ ! -d "${exp_dir}" ]]; then
      echo -e "${YELLOW}⚠ Skipping ${exp_name} - directory not found${NC}"
      continue
    fi

    echo -e "${YELLOW}Running rocotorun for ${exp_name}...${NC}"
    cd "${exp_dir}" || continue

    # Run rocotorun for the experiment
    echo -e "${GREEN}  rocotorun -d ${db_file} -w ${xml_file}${NC}"
    rocotorun -d "${db_file}" -w "${xml_file}" >> "${LOG_FILE}" 2>&1

    echo ""
  done

  echo "=============================================================================="
  echo -e "${GREEN}✓ Rocoto workflows initiated${NC}"
  echo "=============================================================================="
}

###############################################################################
# Function: display_summary
# Description: Display summary of crontab entries
###############################################################################
display_summary() {
  echo ""
  echo "=============================================================================="
  echo "                         CRONTAB ENTRIES SUMMARY"
  echo "=============================================================================="

  if [[ -s "${CRONTAB_ENTRIES_FILE}" ]]; then
    cat "${CRONTAB_ENTRIES_FILE}"
  else
    echo "No crontab entries were generated"
  fi

  echo "=============================================================================="
  echo ""
  echo "To view your current crontab, run: crontab -l"
  echo "To edit your crontab manually, run: crontab -e"
  echo ""
}

###############################################################################
# Main execution
###############################################################################
main() {
  # Set up environment first
  setup_environment

  # Log the header to file
  {
    echo "=============================================================================="
    echo "      Running Workflow Tests with Automatic Setup and Crontab Management"
    echo "=============================================================================="
    echo "Machine: ${MACHINE} (hostname: ${HOSTNAME})"
    echo "HOMEgfs: ${HOMEgfs}"
    echo "RUNTESTS: ${RUNTESTS}"
    echo "Test Suffix: ${TEST_SUFFIX}"
    echo "HPC Account: ${HPC_ACCOUNT}"
    echo "Test Cases: ${#TEST_CASES[@]}"
    echo "=============================================================================="
    echo ""
  } >> "${LOG_FILE}"

  # Display header on terminal
  echo "=============================================================================="
  echo "      Running Workflow Tests with Automatic Setup and Crontab Management"
  echo "=============================================================================="
  echo "Machine: ${MACHINE} (hostname: ${HOSTNAME})"
  echo "HOMEgfs: ${HOMEgfs}"
  echo "RUNTESTS: ${RUNTESTS}"
  echo "Test Suffix: ${TEST_SUFFIX}"
  echo "HPC Account: ${HPC_ACCOUNT}"
  echo "Test Cases: ${#TEST_CASES[@]}"
  echo "=============================================================================="
  echo ""

  local success_count=0
  local fail_count=0

  # Run all test cases
  for test_case in "${TEST_CASES[@]}"; do
    if run_create_experiment "${test_case}" "${TEST_SUFFIX}"; then
      ((success_count++))
    else
      ((fail_count++))
    fi

    # Brief pause between tests
    sleep 2
  done

  # Log and display summary
  {
    echo "=============================================================================="
    echo "                         TEST EXECUTION SUMMARY"
    echo "=============================================================================="
    echo "Successful: ${success_count}"
    echo "Failed: ${fail_count}"
    echo "=============================================================================="
    echo ""
  } >> "${LOG_FILE}"

  echo "=============================================================================="
  echo "                         TEST EXECUTION SUMMARY"
  echo "=============================================================================="
  echo -e "Successful: ${GREEN}${success_count}${NC}"
  echo -e "Failed: ${RED}${fail_count}${NC}"
  echo "=============================================================================="
  echo ""

  # Add crontab entries
  add_crontab_entries

  # Display summary
  display_summary

  # Run rocoto workflows for all experiments
  run_rocoto_experiments "${TEST_SUFFIX}"

  # Exit with error if any tests failed
  if [[ ${fail_count} -gt 0 ]]; then
    echo -e "${RED}Some tests failed. Please review the output above.${NC}"
    return 1
  fi

  echo -e "${GREEN}All tests completed successfully!${NC}"
  return 0
}

# Run main function
main "$@"
