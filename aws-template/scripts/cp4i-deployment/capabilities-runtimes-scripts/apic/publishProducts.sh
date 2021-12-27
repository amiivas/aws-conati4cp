#!/bin/bash

export namespace=$1
export apic_release_name=$2
export org=$3
export user=$4
export password=$5
export apic_server=$6

if [[ "$org" == "" ]]; then
  org=cts-demo
fi

whoami

echo '************* Inside publish-products.sh ***************'
resp=$(apic --accept-license --live-help)
sleep 2


echo "Logging to API Manager :: ${apic_server} for user ${user} and password ${password}"


sleep 5
products_folder_path="/ibm/cp4i-deployment/capabilities-runtimes-scripts/apic/products/"
cd ${products_folder_path}
apic login --server ${apic_server} --username ${user} --password ${password} --realm provider/default-idp-2
echo "Products Folder Path ${products_folder_path}" 
for FILE in *product*; 
do 
   if [[ -f "$FILE" ]]; then
     echo  "Publishing $FILE"
     
     echo "User logged in : " 
     apic products:publish --server ${apic_server} --org ${org} --catalog sandbox cts-demo-apic-product_1.0.0.yaml
     var=$?
     
     if [[ var -eq 0 ]]; then
       mkdir -p ../published
       mv $FILE ../published/.
     fi
   else 
     echo "No Products to publish !!."
   fi
done
sleep 5
echo "Uploading APIs in draft state in API Manager"
for FILE in *; 
do 
   if [[ -f "$FILE" ]]; then
     echo  "Uploading $FILE"
     apic draft-apis:create --server ${apic_server} --org ${org} $FILE
     var=$?
     if [[ var -eq 0 ]]; then
       mkdir -p ../draftapis
       mv $FILE ../draftapis/.
     fi
   else 
     echo "No APIs to upload !!."
   fi
done

echo "********* script completed ********"

yes | sh createSubscription.sh ${namespace} ${apic_release_name} ${org} ${user} ${password} ${apic_server}
