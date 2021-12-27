#!/bin/bash
#******************************************************************************
# Licensed Materials - Property of IBM
# (c) Copyright IBM Corporation 2020. All Rights Reserved.
#
# Note to U.S. Government Users Restricted Rights:
# Use, duplication or disclosure restricted by GSA ADP Schedule
# Contract with IBM Corp.
#******************************************************************************

#******************************************************************************
# PREREQUISITES:
#   - Logged into cluster on the OC CLI (https://docs.openshift.com/container-platform/4.4/cli_reference/openshift_cli/getting-started-cli.html)
#
# PARAMETERS:
#   -n : <namespace> (string), Defaults to "cp4i"
#   -r : <release-name> (string), Defaults to "es-demo"
#
# USAGE:
#   With defaults values
#     ./release-es.sh
#
#   Overriding the namespace and release-name
#     ./release-es.sh -n cp4i-prod -r prod

function usage {
    echo "Usage: $0 -n <namespace> -r <release-name>"
}

username="admin"
password=""

while getopts "u:p:" opt; do
  case ${opt} in
    u ) username="$OPTARG"
      ;;
    p ) password="$OPTARG"
      ;;
    \? ) usage; exit
      ;;
  esac
done

if [ "$password" == "" ]
then
    echo "ERROR: No password specified"
    exit 1;
fi

echo "INFO: Changing password for user $username"

username=$(echo $username | base64)
password=$(echo $password | base64)

cat << EOF | oc apply -f -
kind: Secret
apiVersion: v1
metadata:
  name: platform-auth-idp-credentials
  namespace: ibm-common-services
data:
  admin_password: ${password}
  admin_username: ${username}
type: Opaque
EOF