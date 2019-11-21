# fossology-tools

This repository gathers some Fossology helpers built by Orange and Orange Business Services.


## Script: `upload-rest.sh`

This is an example script that performs the following:
1. [optional] create a token from username + password
1. Create all required folders
1. Upload a binary file, or Git URL
1. Wait for unpack job to finish successfuly (polling)
1. [optional] looks up previous upload for Reuse.
1. Trigger scan jobs
1. Build URL to browse in Fossology


Notes:
- Autentication: Use either the username+pasword OR the token option.
- GIT proxy credentials may be provided via environment variables
- You can specify the Group ID to which the upload will belong
- The REST API URL can be provided separately

Caveats:
- Group ID: works to upload, but not to trigger a job (yet)
- Group Name: Only the group ID can be specified, not the group name.

## GitLab Integration

Example of integration step in GitLab-CI scripts:
```
os_compliance_scan:
    stage: os_compliance_scan
    image: <--your registry here-->:fossology-client
    script:
        - tar -czf /builds/$CI_PROJECT_NAMESPACE/$CI_PROJECT_NAME-$CI_COMMIT_REF_NAME.tar.gz -C /builds/$CI_PROJECT_NAMESPACE/$CI_PROJECT_NAME .
        - cd /usr/local/share/fossology-rest-api
        - ./upload-rest.sh
            -d
            -f "$CI_PROJECT_NAMESPACE/$CI_PROJECT_NAME"
            -i /builds/$CI_PROJECT_NAMESPACE/$CI_PROJECT_NAME-$CI_COMMIT_REF_NAME.tar.gz
            -r $FY_REST_URL
            -t $FY_TOKEN
            -R
```

## Jenkins Integration

Example of integration step in Jenkins configuration:

**Note**: If your Jenkins agent runs on the Fossology server, Fossology can directly scan the *Jenkins workspace* instead of preparing a new tarball as done below.


```
reg=<--your registry here-->
img=fossology-client

[ -z "$BRANCH_NAME" ] && BRANCH_NAME=master

jenkins_tmp_dir=/data/jenkins/tmp
docker_mnt_dir=/mnt
tarball_file=$JOB_BASE_NAME-$BRANCH_NAME.tar.gz


cat <<EOS
JOB_BASE_NAME: $JOB_BASE_NAME
BRANCH_NAME  : $BRANCH_NAME
WORKSPACE    : $WORKSPACE
EOS

tar -czf $jenkins_tmp_dir/$tarball_file  $WORKSPACE

o_r="https://fossology-fqdn/api/v1"
o_t="eyJ0eXAiOiJ..."

docker pull $reg:$img
docker run \
  -v $jenkins_tmp_dir/$tarball_file:$docker_mnt_dir/$tarball_file:ro \
  $reg:$img \
  ./upload-rest.sh -d -R -r "$o_r" -t "$o_t" \
  -f "Jenkins/$JOB_NAME" -i $docker_mnt_dir/$tarball_file

rm -v $jenkins_tmp_dir/$tarball_file

```


