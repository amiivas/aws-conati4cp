#Licensed Materials - Property of IBM
# (c) Copyright IBM Corporation 2020. All Rights Reserved.
#
# Note to U.S. Government Users Restricted Rights:
# Use, duplication or disclosure restricted by GSA ADP Schedule
# Contract with IBM Corp.
#******************************************************************************
# PREREQUISITES:
#   - Bash terminal
#   - Existing OpenShift Cluster with version > 4.4.13
#   - Logged into cluster on the OC CLI (https://docs.openshift.com/container-platform/4.4/cli_reference/openshift_cli/getting-started-cli.html)
#
# MADATORY PARAMETERS:
#   -n : <namespace> (string), Defaults to "cp4i"
#   -k : <entitlement key> (string)
#
# USAGE:
#   For usage and optional parameters see README.md
#

# initial variables
namespace='cp4i'
maxWaitTime=1800
navigatorMaxWaitTime=1800
maxTrials=1
currentTrial=1
entitlementKey=''
platformNavigatorReplicas="1"
asperaKey=''
capabilityAPIConnect="false";
capabilityAPPConnectDashboard="false";
capabilityAPPConenctDesigner="false";
capabilityAssetRepository="false";
capabilityOperationsDashboard="false";
deploymentScriptsPath="$(pwd)/cp4i-deployment/capabilities-runtimes-scripts";

storageClass="ocs-storagecluster-cephfs"
runtimeMQ="false";
runtimeKafka="false";
runtimeAspera="false";
runtimeDataPower="false";
platformPassword="";
cloudpakVersion="2021.3.1";
notificationEmail="amit.srivastav@cognizant.com";

# get cli input flags
while getopts 'w:t:n:k:i:c:a:1:2:3:4:5:6:7:8:9:p:e:' flag; do
  case "${flag}" in
  
    n) namespace="${OPTARG}" ;;
    w) maxWaitTime="${OPTARG}" ;;
    t) maxTrials="${OPTARG}" ;;
    k) entitlementKey="${OPTARG}" ;;
    i) cloudpakVersion="${OPTARG}" ;;
    c) currentTrial="${OPTARG}" ;;
    a) asperaKey="${OPTARG}" ;;
    1) capabilityAPIConnect=$(echo "${OPTARG}" | awk '{print tolower($0)}');;
    2) capabilityAPPConnectDashboard=$(echo "${OPTARG}" | awk '{print tolower($0)}');;
    3) capabilityAPPConenctDesigner=$(echo "${OPTARG}" | awk '{print tolower($0)}');;
    4) capabilityOperationsDashboard=$(echo "${OPTARG}" | awk '{print tolower($0)}');;
    5) capabilityAssetRepository=$(echo "${OPTARG}" | awk '{print tolower($0)}');;
    6) runtimeMQ=$(echo "${OPTARG}" | awk '{print tolower($0)}');;
    7) runtimeKafka=$(echo "${OPTARG}" | awk '{print tolower($0)}');;
    8) runtimeAspera=$(echo "${OPTARG}" | awk '{print tolower($0)}');;
    9) runtimeDataPower=$(echo "${OPTARG}" | awk '{print tolower($0)}');;
    p) platformPassword="${OPTARG}" ;;
    e) notificationEmail="${OPTARG}" ;;



  esac
done
echo "DEBUG: capabilityAPIConnect: ${capabilityAPIConnect}"
echo "DEBUG: capabilityAPPConnectDashboard: ${capabilityAPPConnectDashboard}"
echo "DEBUG: capabilityAPPConenctDesigner: ${capabilityAPPConenctDesigner}"
echo "DEBUG: capabilityOperationsDashboard: ${capabilityOperationsDashboard}"
echo "DEBUG: capabilityAssetRepository: ${capabilityAssetRepository}"
echo "DEBUG: runtimeMQ: ${runtimeMQ}"
echo "DEBUG: runtimeKafka: ${runtimeKafka}"
echo "DEBUG: runtimeAspera: ${runtimeAspera}"
echo "DEBUG: runtimeDataPower: ${runtimeDataPower}"



# check for missing mandatory namespace
if [ -z "$namespace" ]
then
      echo "ERROR: missing namespace argument, make sure to pass namespace, ex: '-n mynamespace'"
      exit 1;
fi

# check for missing mandatory entitlement key
if [ -z "$entitlementKey" ]
then
      echo "ERROR: missing ibm entitlement key argument, make sure to pass a key, ex: '-k mykey'"
      exit 1;
fi



# retry the installation - either with uninstalling or not
# increments the number of trials
# only retry if maximum number of trials isn't reached yet
function retry {
  # boolean flag indicates whether to uninstall or not
  uninstall=${1}

  if [[ $uninstall == true ]]
  then
    # uninstall
    sh ./cp4i-uninstall.sh -n ${namespace}
  fi
  
  # incermenent currentTrial
  currentTrial=$((currentTrial + 1))

  if [[ $currentTrial -gt $maxTrials ]]
    then 
    echo "ERROR: Max Install Trials Reached, exiting now";
    exit 1
  else
    # recall install inscript with current trial
    echo "INFO: Attempt Trial Number ${currentTrial} to install";

    install
  fi
}

# Delete existing subscriptions and install plans wich are stuck in "UpgradePending"
# Fixes a known issue in common services https://www.ibm.com/support/knowledgecenter/SSHKN6/installer/3.x.x/troubleshoot/op_hang.html
function cleanSubscriptions {
  # Get a list of subscriptions stuck in "UpgradePending"
  SUBSCRIPTIONS=$(oc get subscriptions -n ibm-common-services -o json |\
    jq 
  )

  if [[ "$SUBSCRIPTIONS" == "" ]]; then
    echo "INFO: No subscriptions in UpgradePending"
  else
    echo "INFO: The following subscriptions are stuck in UpgradePending:"
    echo "$SUBSCRIPTIONS"

    # Get a unique list of install plans for subscriptions that are stuck in "UpgradePending"
    INSTALL_PLANS=$(oc get subscription -n ibm-common-services -o json |\
      jq -r '[ .items[] | select(.status.state=="UpgradePending") | .status.installplan.name] | unique | .[]' \
    )
    echo "INFO: Associated installplans:"
    echo "$INSTALL_PLANS"

    # Delete the InstallPlans
    oc delete installplans -n ibm-common-services $INSTALL_PLANS

    # Delete the Subscriptions
    oc delete subscriptions -n ibm-common-services $SUBSCRIPTIONS
  fi
}

# Delete a subscription with the given name in the given namespace
function delete_subscription {
  NAMESPACE=${1}
  name=${2}
  echo "INFO: Deleting subscription $name from $NAMESPACE"
  SUBSCRIPTIONS=$(oc get subscriptions -n ${NAMESPACE}  -o json |\
    jq -r ".items[] | select(.metadata.name==\"$name\") | .metadata.name "\
  )
  echo "DEBUG: Found subscriptions:"
  echo "$SUBSCRIPTIONS"

  # Get a unique list of install plans for subscriptions that are stuck in "UpgradePending"
  INSTALL_PLANS=$(oc get subscription -n ${NAMESPACE}  -o json |\
    jq -r "[ .items[] | select(.metadata.name==\"$name\")| .status.installplan.name] | unique | .[]" \
  )
  echo "DEBUG: Associated installplans:"
  echo "$INSTALL_PLANS"

  # Get the csv
  CSV=$(oc get subscription -n ${NAMESPACE} ${name} -o json | jq -r .status.currentCSV)
  echo "DEBUG: Associated ClusterServiceVersion:"
  echo "$CSV"

  # Delete CSV
  oc delete csv -n ${NAMESPACE} $CSV

  # Delete the InstallPlans
  oc delete installplans -n ${NAMESPACE} $INSTALL_PLANS

  # Delete the Subscriptions
  oc delete subscriptions -n ${NAMESPACE}  $SUBSCRIPTIONS
}

# Get auth port with internal url and apply the operand config in common services namespace
function IAM_Update_OperandConfig {

  # set EXTERNAL to external url - if not found retry
  EXTERNAL=$(oc get configmap console-config -n openshift-console -o jsonpath="{.data['console-config\.yaml']}" | grep -A2 'clusterInfo:' | tail -n1 | awk '{ print $2}' )
  if [ -z "$EXTERNAL" ] 
  then
  echo "ERROR: Failed getting EXTERNAL in IAM_Update_OperandConfig";
    retry true
  fi
  echo "INFO: External url: ${EXTERNAL}"

  # set INT_URL to internal url - if not found retry
  export INT_URL="${EXTERNAL}/.well-known/oauth-authorization-server"
  if [ -z "$INT_URL" ] 
  then
    echo "ERROR: Failed getting INT_URL in IAM_Update_OperandConfig";

    retry true
  fi
    echo "INFO: INT_URL: ${INT_URL}"

  # set IAM_URL to iam url - if not found retry
  export IAM_URL=$(curl -k $INT_URL | jq -r '.issuer')
  if [ -z "$IAM_URL" ] 
  then
      echo "ERROR: Failed getting IAM_URL in IAM_Update_OperandConfig";

    retry true
  fi
  echo "INFO: IAM URL : ${IAM_URL}"

  # update OperandConfig of common services to use IAM Url - if it fails retry
  echo "INFO: Updating the OperandConfig 'common-service' for IAM Authentication"
  oc get OperandConfig -n ibm-common-services $(oc get OperandConfig -n ibm-common-services | sed -n 2p | awk '{print $1}') -o json | jq '(.spec.services[] | select(.name == "ibm-iam-operator") | .spec.authentication)|={"config":{"roksEnabled":true,"roksURL":"'$IAM_URL'","roksUserPrefix":"IAM#"}}' | oc apply -f -
  if [[ $? != 0 ]]
  then 
    echo "ERROR: Failed Updating OperandConfig";
    retry true
  fi
}

# print a formatted time in minutes and seconds from the given input in seconds
function output_time {
  SECONDS=${1}
  if((SECONDS>59));then
    printf "%d minutes, %d seconds" $((SECONDS/60)) $((SECONDS%60))
  else
    printf "%d seconds" $SECONDS
  fi
}

# wait for a subscription to be successfully installed
# takes the name and the namespace as input
# waits for the specified maxWaitTime - if that is exceeded the subscriptions is deleted and it returns 1
function wait_for_subscription {
  NAMESPACE=${1}
  NAME=${2}

  phase=""
  # inital time
  time=0
  # wait interval - how often the status is checked in seconds
  wait_time=5

  until [[ "$phase" == "Succeeded" ]]; do
    csv=$(oc get subscription -n ${NAMESPACE} ${NAME} -o json | jq -r .status.currentCSV)
    wait=0
    if [[ "$csv" == "null" ]]; then
      echo "INFO: Waited for $(output_time $time), not got csv for subscription"
      wait=1
    else
      phase=$(oc get csv -n ${NAMESPACE} $csv -o json | jq -r .status.phase)
      if [[ "$phase" != "Succeeded" ]]; then
        echo "INFO: Waited for $(output_time $time), csv not in Succeeded phase, currently: $phase"
        wait=1
      fi
    fi

    # if subscriptions hasn't succeeded yet: wait
    if [[ "$wait" == "1" ]]; then
      ((time=time+$wait_time))
      if [ $time -gt $maxWaitTime ]; then
        echo "ERROR: Failed after waiting for $((maxWaitTime/60)) minutes"
        # delete subscription after maxWaitTime has exceeded
        delete_subscription ${NAMESPACE} ${NAME}
        return 1
      fi

      # wait
      sleep $wait_time
    fi
  done
  echo "INFO: $NAME has succeeded"
}

# create a subscriptions and wait for it to be in succeeded state - if it fails: retry ones
# if it fails 2 times retry the whole installation
# param namespace: the namespace the subscription is created in
# param source: the catalog source of the operator
# param name: name of the subscription
# param channel: channel to be used for the subscription
# param retried: indicate whether this subscription has failed before and this is the retry
function create_subscription {
  NAMESPACE=${1}
  SOURCE=${2}
  NAME=${3}
  CHANNEL=${4}
  #CHANNEL="v1.4"
  RETRIED=${5:-false};
  SOURCE_namespace="openshift-marketplace"
  SUBSCRIPTION_NAME="${NAME}"
	
  if [ -z "$CHANNEL" ]
  then
	CHANNEL=$(oc describe packagemanifests ${NAME} -n openshift-marketplace | grep 'Default Channel:' | tail -n1 | awk '{print $3}')
  fi
  
  # create subscription itself
  cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ${SUBSCRIPTION_NAME}
  namespace: ${NAMESPACE}
spec:
  channel: ${CHANNEL}
  installPlanApproval: Automatic
  name: ${NAME}
  source: ${SOURCE}
  sourceNamespace: ${SOURCE_namespace}
EOF

  # wait for it to succeed and retry if not
  wait_for_subscription ${NAMESPACE} ${SUBSCRIPTION_NAME}
  if [[ "$?" != "0"   ]]; then
    if [[ $RETRIED == true ]]
    then
      echo "ERROR: Failed to install subscription ${NAME} after retrial, reinstalling now";
      retry true
    fi
    echo "INFO: retrying subscription ${NAME}";
    create_subscription ${NAMESPACE} ${SOURCE} ${NAME} true
  fi
}

# install an instance of the platform navigator operator
# wait until it is ready - if it fails retry
function install_platform_navigator {
  RETRIED=${1:-false};
  time=0
while ! cat <<EOF | oc apply -f -
apiVersion: integration.ibm.com/v1beta1
kind: PlatformNavigator
metadata:
  name: ${namespace}-navigator
  namespace: ${namespace}
spec:
  license:
    accept: true
    license: L-RJON-C5CSNH
  mqDashboard: true
  replicas: ${platformNavigatorReplicas}
  storage:
    class: ${storageClass}
  version: 2021.3.1
EOF

  do
    if [ $time -gt $navigatorMaxWaitTime ]; then
      echo "ERROR: Exiting installation as timeout waiting for PlatformNavigator to be created"
      return 1
    fi
    echo "INFO: Waiting for PlatformNavigator to be created. Waited ${time} seconds(s)."
    time=$((time + 1))
    sleep 60
  done

  # Waiting for platform navigator object to be ready
  echo "INFO: Waiting for platform navigator object to be ready"

  time=0
  while [[ "$(oc get PlatformNavigator -n ${namespace} ${namespace}-navigator -o json | jq -r '.status.conditions[] | select(.type=="Ready").status')" != "True" ]]; do
    echo "INFO: The platform navigator object status:"
    echo "INFO: $(oc get PlatformNavigator -n ${namespace} ${namespace}-navigator)"
    if [ $time -gt $navigatorMaxWaitTime ]; then
      echo "ERROR: Exiting installation Platform Navigator object is not ready"
      if [[ $RETRIED == false ]]
      then 
        echo "INFO: Retrying to install Platform Navigator"
        install_platform_navigator true
      else 
      retry true
      fi
    fi

    echo "INFO: Waiting for platform navigator object to be ready. Waited ${time} second(s)."

    time=$((time + 60))
    sleep 60
  done
}

function wait_for_product {
  type=${1}
  release_name=${2}
    time=0
    status=false;
  while [[ "$status" == false ]]; do
        currentStatus="$(oc get ${type} -n ${namespace} ${release_name} -o json | jq -r '.status.conditions[] | select(.type=="Ready").status')";
        if [ "$currentStatus" == "True" ]
        then
          status=true
        fi

    if [ "$status" == false ] 
    then
        currentStatus="$(oc get ${type} -n ${namespace} ${release_name} -o json | jq -r '.status.phase')"

       if [ "$currentStatus" == "Ready" ] || [ "$currentStatus" == "Running" ]
        then
          status=true
        fi
    fi


  
    echo "INFO: The ${type}   status:"
    echo "INFO: $(oc get ${type} -n ${namespace} ${release_name} )"
    if [ $time -gt $maxWaitTime ]; then
      echo "ERROR: Exiting installation ${type}  object is not ready"
      return 1
    fi

    echo "INFO: Waiting for ${type} object to be ready. Waited ${time} second(s)."

    time=$((time + 5))
    sleep 5
  done
}


#function to install IBM Cloud Pak foundational services
function install_foundation_services {

  #using namespace as "common-service";

  echo "INFO: Creating namespace, OperatorGroup, and subscription"

  cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: common-service

---
apiVersion: operators.coreos.com/v1alpha2
kind: OperatorGroup
metadata:
  name: operatorgroup
  namespace: common-service
spec:
  targetNamespaces:
  - common-service

---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-common-service-operator
  namespace: common-service
spec:
  channel: v3
  installPlanApproval: Automatic
  name: ibm-common-service-operator
  source: opencloud-operators
  sourceNamespace: openshift-marketplace
EOF

  #Validating the status of ibm-common-service-operator
  wait_for_subscription common-service ibm-common-service-operator

  # wait for the Operand Deployment Lifecycle Manager to be installed
  wait_for_subscription ibm-common-services operand-deployment-lifecycle-manager-app

  # wait for CommonService to get succeeded
  #wait_for_product CommonService common-service ibm-common-services

  #Changing the storage class to openshift cluster storage file system
  cat <<EOF | oc apply -f -
apiVersion: operator.ibm.com/v3
kind: CommonService
metadata:
  name: common-service
  namespace: ibm-common-services
spec:
  storageClass: ocs-storagecluster-cephfs
EOF

echo "INFO: OperandRegistry Status:  $(oc get operandregistry -n ibm-common-services -o json | jq -r '.items[].status.phase')"

#Installing IBM Cloud Pak foundational services operands
  cat <<EOF | oc apply -f -
apiVersion: operator.ibm.com/v1alpha1
kind: OperandRequest
metadata:
  name: common-service
  namespace: ibm-common-services
spec:
  requests:
    - operands:
        - name: ibm-cert-manager-operator
        - name: ibm-mongodb-operator
        - name: ibm-iam-operator
        - name: ibm-monitoring-exporters-operator
        - name: ibm-monitoring-prometheusext-operator
        - name: ibm-monitoring-grafana-operator
        - name: ibm-healthcheck-operator
        - name: ibm-management-ingress-operator
        - name: ibm-licensing-operator
        - name: ibm-commonui-operator
        - name: ibm-events-operator
        - name: ibm-ingress-nginx-operator
        - name: ibm-auditlogging-operator
        - name: ibm-platform-api-operator
        - name: ibm-zen-operator
      registry: common-service
EOF

  subscriptions=$(oc get subscription -n ibm-common-services -o json | jq -r ".items[].metadata.name")
  for subscription in ${subscriptions}; do
    wait_for_subscription ibm-common-services "${subscription}"
  done
}

function install {
# -------------------- BEGIN INSTALLATION --------------------
echo "INFO: Starting installation of Cloud Pak for Integration in $namespace"


# create new project
oc new-project $namespace
# check if the project has been created - if not retry
oc get project $namespace
if [[ $? == 1 ]]
  then
    retry false
fi

# Create IBM Entitlement Key Secret
oc create secret docker-registry ibm-entitlement-key \
    --docker-username=cp \
    --docker-password=$entitlementKey \
    --docker-server=cp.icr.io \
    --namespace=${namespace}

# check if it has been created - if not retry
oc get secret ibm-entitlement-key -n $namespace
if [[ $? == 1 ]]
  then
    retry false
fi

#Create Open Cloud and IBM Cloud Operator CatalogSource
  cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: opencloud-operators
  namespace: openshift-marketplace
spec:
  displayName: IBMCS Operators
  publisher: IBM
  sourceType: grpc
  image: docker.io/ibmcom/ibm-common-service-catalog:latest
  updateStrategy:
    registryPoll:
      interval: 45m
EOF


  cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-operator-catalog
  namespace: openshift-marketplace
spec:
  displayName: IBM Operator Catalog
  image: 'icr.io/cpopen/ibm-operator-catalog:latest'
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 45m
EOF

# check if Operator catalog source has been created - if not retry
oc get CatalogSource opencloud-operators -n openshift-marketplace
if [[ $? == 1 ]]
  then
    retry false
fi

oc get CatalogSource ibm-operator-catalog -n openshift-marketplace
if [[ $? == 1 ]]
  then
    retry false
fi

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ${namespace}-og
  namespace: ${namespace}
spec:
  targetNamespaces:
    - ${namespace}
EOF

# check if Operator Group has been created
oc get OperatorGroup ${namespace}-og -n ${namespace}
if [[ $? != 0 ]]
  then
    retry false
fi

#Installing IBM Cloud Pak Foundational Services
  install_foundation_services
  echo "Validating IBM Common Services.."
  status=false
  time=0
  while [[ "$status" == false ]]; do

        if [ $time -gt 15 ]; then
                echo "WARNING: IBM common services alert.."
                        status=true
        fi

        count=$(oc get pods -n ibm-common-services | wc -l)

  if [[ count -lt 47 ]]; then
                echo -e "INFO: Pods are still getting created for ${release_name} Waiting.."
                time=$((time + 1))
                status=false
                sleep 60
        else
        echo "INFO: IBM Common Services reached to stable state.."
                status=true
        fi
  done

  #sleep 120

  #echo "INFO: Installing CP4I version ${cloudpakVersion} operators..."
  create_subscription "openshift-operators" "certified-operators" "couchdb-operator-certified"
  #the Aspera operator is not supported on OCP 4.7.
  #create_subscription ${namespace} "ibm-operator-catalog" "aspera-hsts-operator" "v1.2-eus"
  #create_subscription "openshift-operators" "ibm-operator-catalog" "datapower-operator"
  create_subscription "openshift-operators" "ibm-operator-catalog" "ibm-appconnect"
  #create_subscription "${namespace}" "ibm-operator-catalog" "ibm-eventstreams" "v2.3"
  create_subscription "openshift-operators" "ibm-operator-catalog" "ibm-mq"
  #create_subscription "${namespace}" "ibm-operator-catalog" "ibm-integration-asset-repository" "v1.2"
  # Apply the subscription for navigator. This needs to be before apic so apic knows it's running in cp4i
  create_subscription "openshift-operators" "ibm-operator-catalog" "ibm-integration-platform-navigator"
  #Installing APIC v10.0.2.0 which requires operator version 2.2
  create_subscription "${namespace}" "ibm-operator-catalog" "ibm-apiconnect" "v2.2"
  #Will install Datapower Operator
  create_subscription "openshift-operators" "ibm-operator-catalog" "ibm-integration-operations-dashboard"

#Accessing Cloud Pak console
  echo "INFO: IBM Cloud Pak foundational services console :: https://$(oc get route -n ibm-common-services cp-console -o jsonpath='{.spec.host}')"

  #Default user name and password
  echo "INFO: username :: $(oc -n ibm-common-services get secret platform-auth-idp-credentials -o jsonpath='{.data.admin_username}' | base64 -d && echo)  & password :: $(oc -n ibm-common-services get secret platform-auth-idp-credentials -o jsonpath='{.data.admin_password}' | base64 -d)"

echo "INFO: Operand config common-services found: $(oc get OperandConfig -n ibm-common-services | sed -n 2p | awk '{print $1}')"
echo "INFO: Proceeding with updating the OperandConfig to enable Openshift Authentication..."
# Update the OperandConfig to use the correct IAM Url
IAM_Update_OperandConfig


status="$(oc get PlatformNavigator -n "${namespace}" "${namespace}"-navigator -o json | jq -r '.status.conditions[] | select(.type=="Ready").status')";

  echo "INFO: The platform navigator object status: ${status}"
  if [ "${status}" == "True" ]; then
    # Printing the platform navigator object status
    route=$(oc get route -n "${namespace}" "${namespace}"-navigator-pn -o json | jq -r .spec.host);
    echo "INFO: PLATFORM NAVIGATOR ROUTE IS: $route";
    echo "INFO: Plaform Navigator initial admin password : $(oc extract secret/platform-auth-idp-credentials -n ibm-common-services --to=-)";
  else
	# Instantiate Platform Navigator
	echo "INFO: Instantiating Platform Navigator"
	install_platform_navigator
	echo "INFO: Sending Notification Email to ${notificationEmail}"	
	sh $(pwd)/cp4i-deployment/email-notify.sh "IBM Cloud Pak For Integration v${cloudpakVersion}" "completed" "${namespace}" "${notificationEmail}" ""
  fi

  



if [[ ! -z "$platformPassword" ]]
then
      echo "INFO: Changing Platform Password"
  sh ${deploymentScriptsPath}/change-cs-credentials.sh -p ${platformPassword}
    
fi


echo "INFO: CP4I Installed Successfully on project ${namespace}"

if [[ "$capabilityOperationsDashboard" == "true" ]] 
then
echo "INFO: Installing Capability Operations Dashboard";
sh ${deploymentScriptsPath}/release-tracing.sh -n ${namespace} -r operations-dashboard -f ${storageClass} -p -b gp2
wait_for_product OperationsDashboard operations-dashboard
fi

if [[ "$capabilityAPIConnect" == "true" ]] 
then
echo "INFO: Installing Capability API Connect";
sh ${deploymentScriptsPath}/install-apic.sh ${namespace} ${notificationEmail}
fi

if [[ "$capabilityAPPConnectDashboard" == "true" ]] 
then
echo "INFO: Installing Capability App Connect Dashbaord";
sh ${deploymentScriptsPath}/release-ace-dashboard.sh -n ${namespace} -r app-connect-dashboard -s ${storageClass} -p
wait_for_product Dashboard app-connect-dashboard

fi
if [[ "$capabilityAPPConenctDesigner" == "true" ]] 
then
echo "INFO: Installing Capability App Connect Designer";
sh ${deploymentScriptsPath}/release-ace-designer.sh -n ${namespace} -r app-connect-designer -s ${storageClass}
wait_for_product Dashboard DesignerAuthoring Dashboard app-connect-designer
fi

if [[ "$capabilityAssetRepository" == "true" ]] 
then
echo "INFO: Installing Capability Asset Repository";
sh ${deploymentScriptsPath}/release-ar.sh -n ${namespace} -r assets-repo -a ${storageClass} -c ${storageClass}
wait_for_product AssetRepository assets-repo

fi


if [[ "$runtimeMQ" == "true" ]] 
then
echo "INFO: Installing Runtime MQ";
sh ${deploymentScriptsPath}/release-mq.sh -n ${namespace} -r mq  -z ${namespace}
wait_for_product QueueManager mq

fi

if [[ "$runtimeKafka" == "true" ]] 
then
echo "INFO: Installing Runtime Kafka";
sh ${deploymentScriptsPath}/release-es.sh -n ${namespace} -r kafka  -p -c ${storageClass}
wait_for_product EventStreams kafka

fi

if [[ "$runtimeAspera" == "true" ]] 
then
echo "INFO: Installing Runtime Aspera";
sh ${deploymentScriptsPath}/release-aspera.sh -n ${namespace} -r aspera -p -c ${storageClass} -k ${asperaKey}
wait_for_product IbmAsperaHsts aspera

fi

if [[ "$runtimeDataPower" == "true" ]] 
then
echo "INFO: Installing Runtime DataPower";
sh ${deploymentScriptsPath}/release-datapower.sh -n ${namespace} -r datapower -p -a admin
wait_for_product DataPowerService datapower

fi

echo "INFO: cp4i-install.sh scripts completed"
}

install
exit 0


