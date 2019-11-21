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

# Exec example:
# ./upload-rest.sh -f Sandbox/001 -i foobar-3.zip
#                  -n fossy -p fossy
#                  -s "https://<fqdn>/repo"
#
# For HTTPS GIT clones, the script will use the following
# environment variable, if they exist
# GIT_USERNAME=
# GIT_PASSWORD=
#

PROG_VERSION="1.0"
token_validity_days=2
token_scope="write"

debug="false"
folder="Software Repository"
cacert_file="$(dirname $0)/ca-certificates.crt"
curl_insecure="false"

_usage() {
cat <<-EOS

This programm will upload data to a Fossology server,
and automatically trigger scans.

It may be used to easily automate scans in a CI/CD environment.

Usage:
  <program> <authentication> <rest api url> <upload options> [other options...]
  <program> -v

Authentication methods:
  - Token           : -t <...>
  - User + Password : -n <...> -p <...>

Rest API URL: -r <rest_api_utl>
              Ex. https://service-fqdn/repo/api/v1

Upload options:
  - Binary file  : -i <upload-file>
  - Git clone URL: -u <git-url>

All options:
  -d , --debug       ) Debug mode
  -e , --extra-debug ) Extra Debug mode
  -f , --folder      ) Folder in which the upload will be added
  -g , --group-name  ) Fossology group
  -h , --help        ) This help
  -i , --input       ) Filename to upload
  -k , --insecure    ) Skip certificate check in curl command
  -n , --username    ) Fossology username
  -p , --password    ) Fossology password
  -r , --rest-url    ) Full address to Rest API service
  -R , --reuse       ) Enable reuse
  -s , --site-url    ) Fossology portal address
                       Enables printing the resulting Fossology URL
  -t , --api-token   ) API Access Token
  -u , --git-url     ) Url GIT repoisitory address
  -v , --version     ) Print current version
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
        else
            f_debug "CURL: Cannot find ca-cert file '$cacert_file', ignoring."
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

# Echo Folder ID if found
# Return 0 if found, 1 otherwise
# Arg 1: Folder name
# Arg 2: Parent folder ID

f_get_folder_id() {
    f_do_curl GET folders -H "$t_auth" || return 1
    jq ".[] | select(.\"name\" == \"$1\" and .\"parent\" == $2) | .\"id\"" $JSON_REPLY_FILE
}

# #############################################################################
#  Handle arguments
# #############################################################################

OPTS=`getopt -o def:g:hi:kn:p:r:Rs:t:u:v --long api-token:,debug,extra-debug,folder:,git-url:,group-name:,help,input:,insecure,password:,rest-url:,reuse,site-url:,username:,version -n 'parse-options' -- "$@"`

if [ $? != 0 ] ; then echo "Failed parsing options." >&2 ; exit 1 ; fi

while true; do
  case "$1" in
    -i | --input )       input_file="$2" ; shift; shift ;;
    -u | --git-url )     input_git_url="$2" ; shift; shift ;;
    -g | --group-name )  group_id="$2" ; shift; shift ;;
    -f | --folder )      folder="$2" ; shift; shift ;;
    -d | --debug )       debug="true"; shift ;;
    -e | --extra-debug ) debug="true" ; extra_debug="true" ; shift ;;
    -k | --insecure )    curl_insecure="true"; shift ;;
    -R | --reuse )       reuse="true"; shift ;;
    -t | --api-token )   t_tkn="$2" ; shift; shift ;;
    -n | --username )    t_usr="$2" ; shift; shift ;;
    -p | --password )    t_pwd="$2" ; shift; shift ;;
    -r | --rest-url )    rest_url="$2" ; shift; shift ;;
    -s | --site-url )    site_url="$2" ; shift; shift ;;
    -h | --help )        _usage 0 ;;
    -v | --version )     _version ;;
    *) break ;;
  esac
done

[ -n "$input_file$input_git_url" ] || _usage 1
[ -n "$rest_url" ] || _usage 1
# Remove trailing '/' from URL
site_url=$(echo "$site_url" | sed 's!/*$!!')

[ -n "$input_file" ] && upload_name="$(basename $input_file)"
[ -n "$input_git_url" ] && upload_name="$(echo $input_git_url | sed 's_.*/__')"

# Stores the reply data from the latest Rest call.
JSON_REPLY_FILE=$(mktemp) || f_fatal "Cannot create temp file"

cat <<EOS

Service URL: $site_url
REST API   : $rest_url
Username   : $t_usr
Group ID   : $group_id
Token      : $(echo $t_tkn | cut -c 1-8)...
Debug      : $debug
Extra Debug: $extra_debug
Folder     : $folder
Reuse      : $reuse
Upload Name: $upload_name

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
    echo "No Token, trying to generate one"
    if ! echo "$t_usr:$_pwd" | grep -q "^..*:..*$"
    then
        token_name="ci-cd_$(date +%Y%m%d-%H%M%S)"
        token_expire=$(f_get_token_expire_date)
cat <<-EOS
== Create token:
- Valitidy: $token_validity_days days
- Expires : $token_expire
- Name    : $token_name
- Scope   : $token_scope

EOS

        options_json=$(jq -n \
            --argjson user_username "\"$t_usr\"" \
            --argjson user_password "\"$t_pwd\"" \
            --argjson token_name    "\"$token_name\"" \
            --argjson token_scope   "\"$token_scope\"" \
            --argjson token_expire  "\"$token_expire\"" \
            -f "json-templates/request-token.json") || \
            f_fatal "JQ operation failed"
        f_do_curl POST tokens \
            -H "Content-Type: application/json" \
            -d "$options_json" || f_fatal "REST command failed"
        t_tkn=$(jq '."Authorization"' $JSON_REPLY_FILE | sed 's/Bearer //' | tr -d '"')
        [ -z "$t_tkn" ] && f_fatal "Failed to create token"
        [ "$t_tkn" = "null" ] && f_fatal "Failed to create token"
        echo "Token: $(echo $t_tkn | cut -c 1-16)..."
    fi
fi

t_auth="Authorization:Bearer $t_tkn"

[ -z "$t_tkn" ] && f_fatal "No Token"

# #############################################################################
# Folders
# #############################################################################

f_log_part "Folder"

# List Folder
# Searches and create if nedded the folders at each level
# Reads successive folfer names
# Echo last folder ID to stdout
f_handle_folders() {
    local parent_id=1
    local level_id=
    while read level_name
    do
        f_debug "= Folder : $level_name - parent_id:$parent_id"
        level_id=$(f_get_folder_id "$level_name" $parent_id) || \
            f_fatal "Failed to list folders" >/dev/null
        if [ -n "$level_id" ]
        then
            f_debug "=        : Found   - id:$level_id"
        else
            # Create a new folder
            f_do_curl POST folders -H "$t_auth" \
                -H "parentFolder:$parent_id" \
                -H "folderName:$level_name" \
                || f_fatal "Failed to create folder '$level_name'"
            level_id=$(f_get_folder_id "$level_name" $parent_id) || \
                f_fatal "Failed to list folders" >/dev/null
            [ -n "$level_id" ] || f_fatal "Failed to find created folder"
            f_debug "=        : Created - id:$level_id"
        fi
        parent_id=$level_id
    done
    echo $level_id
}

echo "Folder path: '$folder'"

folder_id=$(echo "$folder" | tr '/' '\n' | f_handle_folders) || f_fatal "Error handling folders"
echo "Folder ID  : $folder_id"
[ -n "$folder_id" ] || f_fatal "Bug."

# #############################################################################
# Upload
# #############################################################################

f_log_part "Upload"

[ -n "$group_id" ] && option_groupid="-H groupId:$group_id"
if [ -n "$input_file" ]
then
    echo "Upload file: $input_file"
    f_debug && ls -l $input_file
    f_do_curl POST  uploads -H "$t_auth" $option_groupid \
        -H "folderId:$folder_id" \
        -H "uploadDescription:REST Upload - from File" \
        -H "public:private" \
        -H "ignoreScm:true" \
        -H "Content-Type:multipart/form-data" \
        -F "fileInput=@\"$input_file\";type=application/octet-stream" \
        || f_fatal "REST command failed"
elif [ -n "$input_git_url" ]
then
    echo "Upload GIT URL: $input_git_url"
    options_json=$(jq -n \
        --argjson vcs_url "\"$input_git_url\"" \
        --argjson vcs_username "\"$GIT_USERNAME\"" \
        --argjson vcs_password "\"$GIT_PASSWORD\"" \
        -f "json-templates/upload-vcs_auth.json") || \
        f_fatal "JQ operation failed"
    f_do_curl POST  uploads -H "$t_auth" \
        -H "folderId:$folder_id" \
        -H "uploadDescription:REST Upload - from VCS" \
        -H "public:private" \
        $option_json_username $option_json_password \
        -H "Content-Type:application/json" \
        -d "$options_json" \
        || f_fatal "REST command failed"
else
    f_fatal "BUG - Upload"
fi

upload_id=$(cat $JSON_REPLY_FILE | jq .message)

# Search the ITEM ID, only ti build the resulting Fossology browsable URL
# Do not do it if <site_url> was not provided
if [ -n "$site_url" ]
then
    # that's a pretty clunky way to find the item ID to build the URL, but works for now
    f_do_curl GET search -H "$t_auth" -H "filename:$upload_name" || f_fatal "Failed to search folder"

    item_id=$(cat $JSON_REPLY_FILE | jq ".[-1] | select(.\"upload\".\"folderid\" == $folder_id) | .uploadTreeId")
    fossology_url="$site_url/?mod=license&upload=$upload_id&folder=$folder_id&item=$item_id"
    f_debug "Item ID: $item_id"
    f_debug "Fossology URL: $fossology_url"
else
    f_debug "Not Site URL provided"
    fossology_url="n/a"
fi

# TODO: filter with 'upload:#' option, when it works
f_do_curl GET "jobs?upload=$upload_id" -H "$t_auth" || f_fatal "Failed to find upload job"
job_status=$(jq '.[].status' $JSON_REPLY_FILE)
job_id=$(jq '.[].id' $JSON_REPLY_FILE)
group_id_n=$(jq '.[].groupId' $JSON_REPLY_FILE | tr -d '"')
job_upload_eta=$(jq '.[].eta' $JSON_REPLY_FILE)

cat <<EOS

- Upload ID: $upload_id
- Job ID   : $job_id
- Group ID : $group_id_n
- Job ETA  : $job_upload_eta

EOS

echo "Unpack job: started"
mark=
while true
do
    f_do_curl GET "jobs?upload=$upload_id" -H "$t_auth" || f_fatal "Failed to find upload job"
    upload_status=$(jq '.[].status' $JSON_REPLY_FILE | tr -d '"')
    case $upload_status in
        "Queued") mark="Q" ;;
        "Processing") mark="P" ;;
        "Completed") break ;;
        "Failed") f_fatal "Upload Job Failed" ;;
        *) f_fatal "BUG."
    esac
    echo -n "$mark"
    sleep 1
done
[ -n "$mark" ] && echo
echo "Unpack job: terminated with status '$upload_status'"

# #############################################################################
# Scan Job
# #############################################################################

scan_options_file="json-templates/scan-options.json"
if [ "$reuse" = "true" ]
then
    f_log_part "Reuse"
    # Try to guess previous upload, to use it as a base for reuse.
    f_do_curl GET search -H "$t_auth" -H "filename:$upload_name" || fatal "Failed to search folder"
    previous_upload_id=$(cat $JSON_REPLY_FILE | jq '.[-2].upload.id')
    if echo "$previous_upload_id" | grep -q '^[0-9]*$'
    then
        scan_options_file="json-templates/scan-options-reuse.json"
        [ -z "$previous_upload_id" ] && f_fatal "Failed to find ID for reuse"
        jq_reuse_args="--argjson reuse_upload $previous_upload_id --argjson reuse_group $group_id_n"
        echo "REUSE: Previous Upload ID: $previous_upload_id"
    else
        echo "No Previous upload found, skipping Reuse option"
    fi
else
    f_debug "REUSE: Disabled"
fi

f_log_part "Trigger Scan Jobs"

echo "Fossology URL: $fossology_url"
echo
echo "Scan jobs: starting"

options_json=$(jq -n $jq_reuse_args -f $scan_options_file) || f_fatal "JQ operation failed"
f_do_curl POST  jobs -H "$t_auth" \
    -H "Content-Type:application/json" \
    -H "folderId:$folder_id" \
    -H "uploadId:$upload_id" \
    -d "$options_json" || f_fatal "Failed to start scan"

echo "Scan jobs: started"

f_log_part "End"

