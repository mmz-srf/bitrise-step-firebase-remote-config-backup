#!/bin/bash

#=======================================
# Functions
#=======================================

RESTORE='\033[0m'
RED='\033[00;31m'
YELLOW='\033[00;33m'
BLUE='\033[00;34m'
GREEN='\033[00;32m'

function color_echo {
    color=$1
    msg=$2
    echo -e "${color}${msg}${RESTORE}"
}

function echo_fail {
    msg=$1
    echo
    color_echo "${RED}" "${msg}"
    exit 1
}

function echo_warn {
    msg=$1
    color_echo "${YELLOW}" "${msg}"
}

function echo_info {
    msg=$1
    echo
    color_echo "${BLUE}" "${msg}"
}

function echo_details {
    msg=$1
    echo "  ${msg}"
}

function echo_done {
    msg=$1
    color_echo "${GREEN}" "  ${msg}"
    exit 0
}

function validate_required_input {
    key=$1
    value=$2
    if [ -z "${value}" ] ; then
        echo_fail "Missing required input: ${key}"
    fi
}

function escape {
    token=$1
    quoted=$(echo "${token}" | sed -e 's/\"/\\"/g' )
    echo "${quoted}"
}

function validate_required_input_with_options {
    key=$1
    value=$2
    options=$3

    validate_required_input "${key}" "${value}"

    found="0"
    for option in "${options[@]}" ; do
        if [ "${option}" == "${value}" ] ; then
            found="1"
        fi
    done

    if [ "${found}" == "0" ] ; then
        echo_fail "Invalid input: (${key}) value: (${value}), valid options: ($( IFS=$", "; echo "${options[*]}" ))"
    fi
}

#=======================================
# Helper Functions
#=======================================

function execute {
  cmd=$1
  err_msg=$2

  echo_details "$cmd"
  echo

  eval "${cmd}"

  if [ $? -ne 0 ] ; then
      echo_fail "$err_msg"
  fi
}

function delete_branch {
    branch_name=$1
    echo "  ${msg}"
}

#=======================================
# Main
#=======================================

#
# Validate parameters
echo_info "Configs:"
echo_details "* service_credentials_file: $service_credentials_file"
echo_details "* project_id: $project_id"
echo_details "* is_debug: $is_debug"
echo_details "* upgrade_firebase_tools: $upgrade_firebase_tools"

echo

if [ -z "${service_credentials_file}" ]; then
    echo_fail "No authentication input was defined, please fill in Service Credentials Field."
elif [ ! -f "${service_credentials_file}" ]; then
    if [[ $service_credentials_file == http* ]]; then
      echo_info "Service Credentials File is a remote url, downloading it ..."
      curl $service_credentials_file --output credentials.json
      service_credentials_file=$(pwd)/credentials.json
      echo_info "Downloaded Service Credentials File to path: ${service_credentials_file}"
    else
      echo_fail "Service Credentials File defined but does not exist at path: ${service_credentials_file}"
    fi
fi

if [ -z "${project_id}" ] ; then
    echo_fail "Firebase Project ID is not defined"
fi

# Install Firebase
if [ "${upgrade_firebase_tools}" = true ] ; then
    curl -sL firebase.tools | upgrade=true bash
else
    curl -sL firebase.tools | bash
fi

# Export Service Credentials File
if [ -n "${service_credentials_file}" ] ; then
    export GOOGLE_APPLICATION_CREDENTIALS="${service_credentials_file}"
fi

# Export
#
echo_info "Exporting Firebase remote-config"
echo

remote_config_file="${project_id}_remote_config.json"

firebase_cmd="firebase remoteconfig:get"
firebase_cmd="$firebase_cmd --project \"${project_id}\" -o \"${remote_config_file}\""

# Optional params
if [ "${is_debug}" = true ] ; then
    firebase_cmd="$firebase_cmd --debug"
fi

execute "$firebase_cmd" "Cannot export remote-config from Firebase."

# Backup to repository
echo_info "Backup Firebase remote-config to repository"
echo

### Check for changes
#
check_cmd="git diff-index --quiet HEAD"

echo_details "$check_cmd"
echo

eval "$check_cmd"

if [ $? -eq 0 ]; then
    echo_done "No changes. Nothing to do."
fi

### Create Branch
#
backup_branch_name="firebase_remote_config_backup"

## cleanup (not used at the moment)
#old_branch=$(git branch --show-current)
#cleanup_cmd="git checkout \"$old_branch\""
#cleanup_cmd="$cleanup_cmd; git branch --delete \"$backup_branch_name\""
#cleanup_cmd="$cleanup_cmd; git push origin -d \"$backup_branch_name\""

echo_info "Create \"$backup_branch_name\" branch"

branch_cmd="git checkout -b \"$backup_branch_name\" HEAD"

execute "$branch_cmd" "Cannot create branch."

### Commit & Push
#
echo_info "Add and commit \"${remote_config_file}\""

commit_cmd="git add \"${remote_config_file}\""
commit_cmd="$commit_cmd; git commit -m \"Firebase remote-config backup\""
commit_cmd="$commit_cmd; git push -u origin HEAD"

execute "$commit_cmd" "Cannot commit."

### Install GH
#
echo_info "Install GH"

install_gh_cmd="curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
  && sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
  && sudo apt update \
  && sudo apt install gh -y"

execute "$install_gh_cmd" "Cannot install GH."

### Create PR
#
create_pr_cmd="echo \"$SRF_APPS_GITHUB_TOKEN\" > .githubtoken"
create_pr_cmd="$create_pr_cmd; gh auth login --with-token < .githubtoken"
create_pr_cmd="$create_pr_cmd; gh pr create --fill"

execute "$create_pr_cmd" "Cannot create PR."

echo_done "Success"
