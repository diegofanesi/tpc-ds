# ==============================================================================
# Bash Environment Serialization and Deserialization Functions
#
# This script provides functions to save and load simple shell variables
# (strings and numbers) between different shell sessions or cells.
# It now uses a simple KEY="VALUE" format.
#
# NOTE: This version does NOT save arrays or functions.
#
# Usage:
#   1. At the beginning of your script/cell, load any previous state:
#      load_env
#
#   2. Define your new variables:
#      NEW_VAR="a value with spaces"
#
#   3. At the end of your script/cell, save only the new state:
#      save_env
# ==============================================================================

# This global array stores the names of variables that existed at the start.
declare -a SH_EXISTING_VARS

# --- Function to Save Only New Variables ---
#
# Serializes only the simple variables (not arrays/functions) that were created
# *after* `load_env` was run. It writes them as `export KEY="VALUE"` lines.
#
# @param $1 (optional) The path to the file where the new state should be saved.
#       Defaults to "/tmp/$EXECUTION_ID".
save_env() {
  local V_FILE=${1:-"/tmp/$EXECUTION_ID.state"}
  # Ensure load_env was run first by checking if the array has content.
  if [[ ${#SH_EXISTING_VARS[@]} -eq 0 ]]; then
    echo "❌ Error: 'load_env' must be run before 'save_env' to set a baseline."
    return 1
  fi

  # Use an associative array for efficient lookups of existing variables.
  declare -A _vars_to_exclude
  for var_name in "${SH_EXISTING_VARS[@]}"; do
    _vars_to_exclude["$var_name"]=1
  done

  # Also, prevent the state-tracking and internal function variables from being saved.
  _vars_to_exclude["SH_EXISTING_VARS"]=1
  _vars_to_exclude["_vars_to_exclude"]=1
  _vars_to_exclude["V_FILE"]=1
  _vars_to_exclude["all_current_vars"]=1
  _vars_to_exclude["var_name"]=1
  _vars_to_exclude["var_value"]=1

  # Get a list of all current variables.
  local all_current_vars=($(compgen -v))

  # Overwrite the state file.
  : > "$V_FILE"

  # Iterate through all current variables and save only the new ones.
  for var_name in "${all_current_vars[@]}"; do
    if [[ -z "${_vars_to_exclude[$var_name]}" ]]; then
      # Check if the variable is an array. If so, skip it.
      # The `declare -p` output for an array contains "declare -a".
      if [[ "$(declare -p "$var_name" 2>/dev/null)" =~ "declare -a" ]]; then
        echo "ℹ Skipping array variable: $var_name"
        continue
      fi

      # Get the variable's value using indirect parameter expansion.
      local var_value="${!var_name}"
      
      # Write the export command to the file, ensuring the value is quoted.
      echo "export ${var_name}=\"${var_value}\"" >> "$V_FILE"
    fi
  done

  echo "✔ New shell state saved successfully to: $V_FILE"
}

# --- Function to Load Environment and Set Baseline ---
#
# Records the names of all currently existing variables,
# then loads additional ones by sourcing a state file.
#
# @param $1 (optional) The path to the file from which to load the state.
#       Defaults to "/tmp/$EXECUTION_ID".
load_env() {
  local V_FILE=${1:-"/tmp/$EXECUTION_ID.state"}

  # Record all existing variable names before loading new ones.
  # We only care about variables now, not functions.
  SH_EXISTING_VARS=($(compgen -v))
  echo "ⓘ Baseline of existing variables has been set."

  # Check if the state file exists and has content (-s).
  if [ -s "$V_FILE" ]; then
    # The 'source' command executes the file content in the current shell.
    # Since the file now contains 'export KEY="VALUE"' lines, this works perfectly.
    source "$V_FILE"
    echo "✔ Shell state loaded successfully from: $V_FILE"
  else
    echo "ℹ No state file found at: $V_FILE. No variables loaded."
  fi
}


# Automatically save new variables when the shell process exits.
trap save_env EXIT

# Run load_env at the start to establish the baseline and load previous state.
load_env