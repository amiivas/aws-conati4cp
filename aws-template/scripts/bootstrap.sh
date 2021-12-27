#!/bin/bash


##### "Main" starts here
SCRIPT=${0##*/}

export INSTALLOCPFLAG=$(echo "${INSTALL_OCP_FLAG}" | awk '{print tolower($0)}')

echo "Installing OCP: $INSTALLOCPFLAG"

echo $SCRIPT
source ${P}


if [[ "$INSTALLOCPFLAG" == "true" ]] 
then
echo "[INFO] Enable epel-release-latest-7"
#yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
qs_enable_epel &> /var/log/userdata.qs_enable_epel.log
yum -y install jq

#curl --silent --show-error --retry 5 https://bootstrap.pypa.io/pip/2.7/get-pip.py | python2
qs_retry_command 10 pip install boto3 &> /var/log/userdata.boto3_install.log


###
##ADDING CP4I VERSION
#InstallCP4IVersion = ${CP4IVersion}
#echo $InstallCP4IVersion

###
cd /tmp
qs_retry_command 10 wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
qs_retry_command 10 yum install -y ./amazon-ssm-agent.rpm
systemctl start amazon-ssm-agent
systemctl enable amazon-ssm-agent
rm -f ./amazon-ssm-agent.rpm

##qs_retry_command 10 wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.6.19/openshift-client-linux.tar.gz
## 4.8 ocp client
qs_retry_command 10 wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.8.22/openshift-client-linux.tar.gz
tar xvf openshift-client-linux.tar.gz
mv ./oc /usr/bin/
mv ./kubectl /usr/bin

##qs_retry_command 10 wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.6.19/openshift-install-linux.tar.gz
## 4.8 ocp installer
qs_retry_command 10 wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.8.22/openshift-install-linux.tar.gz
tar xvf openshift-install-linux.tar.gz
mv ./openshift-install /ibm/
cd -

aws s3 cp  ${CP4I_QS_S3URI}scripts/  /ibm/ --recursive
cd /ibm
# Make sure there is a "logs" directory in the current directory
if [ ! -d "${PWD}/logs" ]; then
  mkdir logs
  rc=$?
  if [ "$rc" != "0" ]; then
	# Not sure why this would ever happen, but...
	# Have to echo here since trace log is not set yet.
	echo "Creating ${PWD}/logs directory failed.  Exiting..."
	exit 1
  fi
fi

LOGFILE="${PWD}/logs/${SCRIPT%.*}.log"

# Setting aws credentials
#aws configure set aws_access_key_id ${AWS_ACCESS_KEY}
#aws configure set aws_secret_access_key ${AWS_ACCESS_SECRET}

mkdir -p artifacts
mkdir -p  templates
chmod +x /ibm/cp4i_install.py
chmod +x /ibm/destroy.sh
chmod +x /ibm/cp4i-deployment/cp4i-install.sh
chmod +x /ibm/cp4i-deployment/email-notify.sh
chmod +x /usr/bin/oc
chmod +x /usr/bin/kubectl
chmod +x /ibm/openshift-install

echo $HOME
export KUBECONFIG=/root/.kube/config
echo $KUBECONFIG
echo $PATH

fi

/ibm/cp4i_install.py --region "${AWS_REGION}" --stackid "${AWS_STACKID}" --stack-name ${AWS_STACKNAME} --logfile $LOGFILE --loglevel "*=all"


