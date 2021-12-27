#!/bin/bash

export namespace=$1
export user_email=$2
export org=$3


release_name="apic"
echo "Release Name:" ${release_name}
maxWaitTime=3600
apicPath="$(pwd)/cp4i-deployment/capabilities-runtimes-scripts/apic"

function wait_for_product {
  type=${1}
  release_name=${2}
  NAMESPACE=${3}
  time=0
  status=false;
  while [[ "$status" == false ]]; do

        currentStatus="$(oc get "${type}" -n "${NAMESPACE}" "${release_name}" -o json | jq -r '.status.phase')"

        if [ "$currentStatus" == "Ready" ] || [ "$currentStatus" == "Running" ] || [ "$currentStatus" == "Succeeded" ]
        then
          status=true
        fi


    echo "INFO: The ${type} status: $currentStatus"
    if [ "$status" == false ]; then
      if [ $time -gt $maxWaitTime ]; then
        echo "ERROR: Exiting installation ${type}  object is not ready"
        return 1
      fi

      echo "INFO: Waiting for ${type} object to be ready. Waited ${time} second(s)."

      time=$((time + 60))
      sleep 60
    fi
  done
}


echo "Installing API Connect in ${namespace} .."
echo "Tracing is currently set to false"

cat << EOF | oc apply -f -
apiVersion: apiconnect.ibm.com/v1beta1
kind: APIConnectCluster
metadata:
  labels:
    app.kubernetes.io/instance: apiconnect
    app.kubernetes.io/managed-by: ibm-apiconnect
    app.kubernetes.io/name: apiconnect-${namespace}
  name: ${release_name}
  namespace: ${namespace}
spec:
  imagePullSecrets:
    - ibm-entitlement-key
  imageRegistry: cp.icr.io/cp/apic
  license:
    accept: true
    use: nonproduction
    license: L-RJON-BZ5LTP
    metric: VIRTUAL_PROCESSOR_CORE
  profile: n1xc10.m48
  version: 10.0.2.0
  storageClassName: ocs-storagecluster-ceph-rbd
EOF

echo "Validating API Connect installation.."
apic=0
time=0
while [[ apic -eq 0 ]]; do

        if [ $time -gt 3600 ]; then
                echo "Timed-out : API Connect Installation failed.."
                exit 1
        fi


        gw_release_name=${release_name}
        ptl_release_name=${release_name}
        mgmt_release_name=${release_name}
        apic_release_name=${release_name}
        wait_for_product ManagementCluster "${mgmt_release_name}-mgmt" "${namespace}"
        wait_for_product PortalCluster "${ptl_release_name}-ptl" "${namespace}"
        wait_for_product GatewayCluster "${gw_release_name}-gw" "${namespace}"

        echo "INFO: Waiting for APIConnectCluster to be in Ready state .."
        wait_for_product APIConnectCluster "${apic_release_name}" "${namespace}"

        echo "API Connect Installation successful.."
        apic=1;

    
	echo "Sending notification"
	sh $(pwd)/cp4i-deployment/email-notify.sh "IBM API Connect v10.0.2.0" "completed" "${namespace}" "${user_email}" ""

    if [[ apic -eq 1 ]]; then
		yes | sh $(apicPath}/createProviderOrganization.sh ${namespace} ${openshift_user} ${release_name} ${org}
    fi


done