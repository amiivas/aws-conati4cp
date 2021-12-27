JOB_NAMESPACE="integration"
scriptsPath="$(pwd)/cp4i-deployment";

while getopts 'n:v' flag; do
  case "${flag}" in
  
    n) JOB_NAMESPACE="${OPTARG}" ;;
  esac
done

echo "INFO: Deleting the platform navigator CR in the ${JOB_NAMESPACE} namespace"
oc delete PlatformNavigator -n ${JOB_NAMESPACE} ${JOB_NAMESPACE}-navigator

# Deleting all ClusterServiceVersions
echo "INFO: Deleting all ClusterServiceVersions in the ${JOB_NAMESPACE} namespace"
oc delete ClusterServiceVersion -n ${JOB_NAMESPACE} $(oc get -n ${JOB_NAMESPACE} ClusterServiceVersion | grep -v operand-deployment-lifecycle-manager | awk '{print $1}' | sed -n '1!p')

# Deleting all Subscription
echo "INFO: Deleting all Subscriptions in the ${JOB_NAMESPACE} namespace"
oc delete Subscription -n ${JOB_NAMESPACE} --all

# Deleting the operator group
echo "INFO: Deleting the operator group in the ${JOB_NAMESPACE} namespace"
oc delete OperatorGroup -n ${JOB_NAMESPACE} ${JOB_NAMESPACE}-og

# Deleting the ibm-entitlement-key secret
echo "INFO: Deleting ibm-entitlement-key secret"
oc delete secret -n ${JOB_NAMESPACE} ibm-entitlement-key 
sh ${scriptsPath}/delete-project.sh -n ${JOB_NAMESPACE};
echo "Uninstall is complete"