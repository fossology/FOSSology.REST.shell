#!/bin/sh

#
# Software Name : Fossology Helper Tools
# Version: 1.0
# Copyright (c) 2019 Orange Business Services
# SPDX-License-Identifier: MIT
#
# This software is distributed under the MIT License
# the text of which is available at https://spdx.org/licenses/MIT.html
# or see the "license.txt" file for more details.
#
# Author: Nicolas Toussaint nicolas1.toussaint@orange.com
# Software description: Fossology helper tools
#
# download-rest.sh was created from upload-rest.sh and modified by Sony Corporation
#
# Exec example:
# ./download-rest.sh -F spdx2
#                  -n fossy -p fossy
#                  -r "https://<fqdn>/repo/api/v1"
#                  -u <upload_id>
#

PROG_VERSION="1"
token_validity_days=2
token_scope="write"

debug="false"
cacert_file="$(dirname $0)/ca-certificates.crt"
curl_insecure="false"
output_dir=$(pwd)

json_templates_dir="$(dirname $0)/json-templates"

_usage() {
cat <<-EOS

This programm will trigger report generation
on an existing upload and download it.

It may be used to easily automate scans in a CI/CD environment.

Usage:
  <program> <authentication> <rest api url> <upload id> <report format> [other options...]
  <program> -v

Authentication methods:
  - Token           : -t <...>
  - User + Password : -n <...> -p <...>

Rest API URL: -r <rest_api_utl>
              Ex. https://service-fqdn/repo/api/v1

All options:
  -d , --debug         ) Debug mode
  -e , --extra-debug   ) Extra Debug mode
  -F , --report-format ) Format of the report to download
  -h , --help          ) This help
  -k , --insecure      ) Skip certificate check in curl command
  -n , --username      ) Fossology username
  -o , --output-dir    ) Output directory to download report
  -p , --password      ) Fossology password
  -r , --rest-url      ) Full address to Rest API service
  -t , --api-token     ) API Access Token
  -u , --upload-id     ) Upload ID on the server
  -v , --version       ) Print current version
EOS
    exit $1
}

_version() {
    echo
    echo "$(basename $0): Version $PROG_VERSION"
    echo
    exit 0
}
f_extra_debug() {
    echo "$extra_debug" | grep -q "^true$" || return 1
    [ $# -gt 0 ] && echo "$@" >&2
    return 0
}

f_debug() {
    echo "$debug" | grep -q "^true$" || return 1
    [ $# -gt 0 ] && echo "$@" >&2
    return 0
}

f_log_part() {
cat >&2 <<-EOS

======================================
=== $*
======================================

EOS
}

f_fatal() {
    echo >&2
    echo "Fatal: $@" >&2
    exit 1
}

f_output_json() {
    echo >&2
    echo "<<< JSON OUTPUT <<<" >&2
    if [ -n "$1" ]
    then head -n $1 $JSON_REPLY_FILE >&2
    else cat $JSON_REPLY_FILE | jq . >&2
    fi
    echo '>>> >>> >>> >>> >>>' >&2
}

# Download file from $rest_url
# Arg1. Action to be appended to REST base URI
# Arg+. All other query parameters
#
# Returns:
# x 0 on Success
# x Curl return code on curl error
#
f_download_file() {
    local curl_cert_opt=

    echo "Output directory: $output_dir"
    if $curl_insecure
    then
        f_debug "CURL: do not check remote certificate"
        curl_cert_opt="-k"
    else
        if [ -r "$cacert_file" ]
        then
            curl_cert_opt="--cacert $cacert_file"
        fi
    fi
    rest_action=$1

    shift 1
    f_extra_debug && set -x

    # Download file in output directory
    echo "Downloading file"
    cd $output_dir
    filename=$(curl $curl_cert_opt -s -S -O -J -X GET $rest_url/$rest_action "$@" \
        -w %{filename_effective})
    rc=$?
    cd - > /dev/null

    f_extra_debug && set +x
    if [ $rc -ne 0 ]
    then
        f_debug "CURL exit code  : $rc"
    else
        echo "Downloaded file: $output_dir/$filename"
    fi

    return $rc
}

# wait for all jobs to complete
# Arg1. upload ID
#
# Prints marks for job status while waiting:
# eg:
# - Q : Queued job
# - P : Processing
#
# Throws fatal error if a job fails
#
f_wait_for_jobs_completion() {
    local upload_id=$1
    marks=
    while true
    do
        # get jobs status
        f_do_curl GET "jobs?upload=$upload_id" -H "$t_auth" \
                || f_fatal "Failed to find job"

        job_count=$(jq '. | length' $JSON_REPLY_FILE)

        # exit if even a single job fails
        failed_job_count=$(jq '[.[].status] |
                map(select(. == "Failed")) |
                length' $JSON_REPLY_FILE)

        if [ $failed_job_count -gt 0 ]
        then
            f_fatal "Job failed"
        fi


        # Exit if all jobs completed
        completed_job_count=$(jq '[.[].status] |
                map(select(. == "Completed")) |
                length' $JSON_REPLY_FILE)

        if [ $completed_job_count -eq $job_count ]
        then
            break
        fi


        # Print marks
        marks=$(jq '[.[].status] | map(.[0:1]) | add' $JSON_REPLY_FILE | tr -d '"')
        echo -n "$marks"

        sleep 1
    done

    [ -n "$marks" ] && echo
    echo "Jobs done"
}



# Execute REST Query
# Full Curl command output stored in the file $JSON_REPLY_FILE
#
# Arg1. HTTP Verb: GET or POST
# Arg2. Action to be appended to REST base URI
# Arg+. All other query parameters
#
# Returns:
# x 0 on Success - Json contains a "Code" entry in the 200 family
# x Json error code otherwise.
# x 999 on Curl error
#
f_do_curl() {
    local curl_cert_opt=
    if $curl_insecure
    then
        f_debug "CURL: do not check remote certificate"
        curl_cert_opt="-k"
    else
        if [ -r "$cacert_file" ]
        then
            curl_cert_opt="--cacert $cacert_file"
        fi
    fi
    http_verb=$1
    rest_action=$2

    shift 2
    [ -s "$JSON_REPLY_FILE" ] && >$JSON_REPLY_FILE
    f_extra_debug && set -x
    curl $curl_cert_opt -s -S -X $http_verb $rest_url/$rest_action "$@" > $JSON_REPLY_FILE
    rc=$?
    f_extra_debug && set +x
    if [ $rc -ne 0 ]
    then
        f_debug "CURL exit code  : $rc"
        f_debug "CURL output file: $JSON_REPLY_FILE"
    fi
    [ $rc -ne 0 ] && return 999

    if ! head -n 1 $JSON_REPLY_FILE | jq . >/dev/null 2>&1
    then
        f_output_json 5
        f_fatal "Reply is not JSON"
    else
        if ! code=$(cat $JSON_REPLY_FILE | jq 'try .code  catch 0 |  if . == null then 0 else . end')
        then
            f_output_json 5
            f_fatal "Error reading error code."
        else
            f_extra_debug && f_output_json
            if echo "$code" | grep -q '^[02]'
            then
                return 0
            else
cat >&2 <<-EOS
ERROR:
  Code: $(cat $JSON_REPLY_FILE | jq '.code')
  Message: $(cat $JSON_REPLY_FILE | jq '.message')
EOS
                return 1
            fi
        fi
    fi

}

f_get_token_expire_date() {
    local now=$(date +%s)
    local exp=$((now + token_validity_days * 24 * 60 * 60))
    date +%Y-%m-%d --date="@$exp"
}


# #############################################################################
#  Handle arguments
# #############################################################################

OPTS=`getopt -o deF:hkn:o:p:r:t:u:v --long api-token:,debug,extra-debug,help,insecure,output-dir:,password:,rest-url:,report-format:,upload-id:,username:,version -n 'parse-options' -- "$@"`

if [ $? != 0 ] ; then echo "Failed parsing options." >&2 ; exit 1 ; fi

while true; do
  case "$1" in
    -F | --report-format ) report_format="$2" ; shift; shift ;;
    -d | --debug )         debug="true"; shift ;;
    -e | --extra-debug )   debug="true" ; extra_debug="true" ; shift ;;
    -k | --insecure )      curl_insecure="true"; shift ;;
    -t | --api-token )     t_tkn="$2" ; shift; shift ;;
    -n | --username )      t_usr="$2" ; shift; shift ;;
    -o | --output-dir )    output_dir="$2"; shift; shift ;;
    -p | --password )      t_pwd="$2" ; shift; shift ;;
    -r | --rest-url )      rest_url="$2" ; shift; shift ;;
    -u | --upload-id )     upload_id="$2" ; shift; shift ;;
    -h | --help )          _usage 0 ;;
    -v | --version )       _version ;;
    *) break ;;
  esac
done

[ -n "$rest_url" ] || _usage 1
[ -n "$upload_id" ] || _usage 1
[ -n "$report_format" ] || _usage 1


# Stores the reply data from the latest Rest call.
JSON_REPLY_FILE=$(mktemp) || f_fatal "Cannot create temp file"

cat <<EOS
Rest Client: Version $PROG_VERSION

Upload ID        : $upload_id
REST API         : $rest_url
Username         : $t_usr
Token            : $(echo $t_tkn | cut -c 1-8)...
Debug            : $debug
Extra Debug      : $extra_debug
Output Directory : $output_dir
Report format    : $report_format

JSON_REPLY_FILE: $JSON_REPLY_FILE

EOS

# #############################################################################
# Authentication
# #############################################################################

f_log_part "Authentication"
if [ -n "$t_tkn" ]
then
    echo "Using provided token"
else
    echo "No token provided: generatating one"
    if ! echo "$t_usr:$_pwd" | grep -q "^..*:..*$"
    then
        token_name="ci-cd_$(date +%Y%m%d-%H%M%S)"
        token_expire=$(f_get_token_expire_date)
        options_json=$(jq -n \
            --argjson user_username "\"$t_usr\"" \
            --argjson user_password "\"$t_pwd\"" \
            --argjson token_name    "\"$token_name\"" \
            --argjson token_scope   "\"$token_scope\"" \
            --argjson token_expire  "\"$token_expire\"" \
            -f "$json_templates_dir/request-token.json") || \
            f_fatal "JQ operation failed"
        f_do_curl POST tokens \
            -H "Content-Type: application/json" \
            -d "$options_json" || f_fatal "REST command failed"
        t_tkn=$(jq '."Authorization"' $JSON_REPLY_FILE | sed 's/Bearer //' | tr -d '"')
        [ -z "$t_tkn" ] && f_fatal "Failed to create token"
        [ "$t_tkn" = "null" ] && f_fatal "Failed to create token"
        f_debug "Created token: $token_name"
        f_debug "- Valitidy: $token_validity_days days"
        f_debug "- Expires : $token_expire"
        f_debug "- Scope   : $token_scope"
        f_debug "<<<<"
        f_debug "$t_tkn"
        f_debug ">>>>"
    fi
fi

t_auth="Authorization:Bearer $t_tkn"

[ -z "$t_tkn" ] && f_fatal "No Token"



# ############################################################################
# Wait for previously running jobs to complete
# ############################################################################

f_log_part "Wait for any running jobs to finish"

# Check if the scan jobs have finished
f_wait_for_jobs_completion $upload_id


# #############################################################################
# Generate report
# #############################################################################

f_log_part "Schedule report generation"

f_do_curl GET report -H "$t_auth" \
    -H "uploadId:$upload_id" \
    -H "reportFormat:$report_format" || f_fatal "Failed to generate report"

report_url=$(jq '.message' $JSON_REPLY_FILE)
report_id=$(echo $report_url | awk -F / '{print $NF}' | tr -d '"')

cat <<EOS

- Report ID    : $report_id
- Report Format: $report_format

EOS

echo "Wait for report generation jobs to finish"
f_wait_for_jobs_completion $upload_id

# #############################################################################
# Download report
# #############################################################################

f_log_part "Download report"
f_download_file "report/$report_id" -H "$t_auth" \
        || f_fatal "Failed to download report"


f_log_part "End"
