#!/bin/bash
set -e

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

# Deploy
echo_info "Exporting Firebase remote-config"

remote_config_file="${project_id}_remote_config.json"

submit_cmd="firebase remoteconfig:get"
submit_cmd="$submit_cmd --project \"${project_id}\" -o \"${remote_config_file}\""

# Optional params
if [ "${is_debug}" = true ] ; then
    submit_cmd="$submit_cmd --debug"
fi

echo_details "$submit_cmd"
echo

eval "${submit_cmd}"

if [ $? -ne 0 ] ; then
    echo_fail "Fail"
fi

# Backup to repository
echo_info "Backup Firebase remote-config to repository"

# Commit to repo
echo_info "Commit and push remote-config backup to \"firebase_remote_config_backup\" branch"

checkout_cmd="git checkout -B firebase_remote_config_backup; git pull"

echo_details "$checkout_cmd"
echo

eval "${checkout_cmd}"

if [ $? -ne 0 ] ; then
    echo_fail "Fail"
fi

commit_cmd="git add \"${remote_config_file}\""
commit_cmd="$commit_cmd; git diff-index --quiet HEAD || git commit -m \"Firebase remote-config backup\""
commit_cmd="$commit_cmd; git push -u origin HEAD"

echo_details "$commit_cmd"
echo

eval "${commit_cmd}"

if [ $? -eq 0 ] ; then
    echo_done "Success"
else
    echo_fail "Fail"
fi
