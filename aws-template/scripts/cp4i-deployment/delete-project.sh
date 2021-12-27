namespace=''
while getopts 'n:v' flag; do
  case "${flag}" in
  
    n) namespace="${OPTARG}" ;;
  esac
done

if [ -z "$namespace" ]
then
      echo "Error: missing namespace argument, make sure to pass namespace, ex: '-n mynamespace'"
      exit 1;
fi

# Deletes namespace without waiting and may put it in Terminiating state
oc delete project ${namespace} --ignore-not-found

# Get namespace info and remove Kubernities finalizers // a workaround to get rid of terminiating state 
# If this fails it means there was no terminiating state so we don't care about the error 
namespaceInfo=$(oc get namespace  ${namespace} -o json --ignore-not-found | jq -r .spec.finalizers=[])
echo "$namespaceInfo" > ./namespaceInfo.json

# apply the new info to namespace finalize // a workaround to get rid of terminiating state  
# If this fails it means there was no terminiating state so we don't care about the error 

oc replace --raw /api/v1/namespaces/${namespace}/finalize -f ./namespaceInfo.json 
rm ./namespaceInfo.json

# Enforce waiting for deleting namespace if it was in terminiating 
# If this fails it means there was no terminiating state so we don't care about the error 
oc delete namespace ${namespace} --ignore-not-found

exit 0;
