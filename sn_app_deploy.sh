#!/bin/bash
set -e

INSTANCE_USERNAME="<midserver username>"
BASE_64_CRED=""

# Path to Private Key and Certificate files which should be provided in case the MID Server should use mTLS
PATH_TO_MID_KEY=""
PATH_TO_MID_CERT=""

BASE_64_INSTANCE_USERNAME=""
USE_MTLS=""

if [ ! -z "$SN_DEBUG" ]; then
  echo ""
  echo "************************************"
  echo "Script is running in SN-DEBUG mode"
  echo "************************************"
  echo ""
fi

is_instance_using_adcv2() {
  echo -n "Detecting the MTLS configuration of the instance ${INSTANCE_NAME}  .....  "
  curl_response=""
  #curl_response=`curl -s -o /dev/null -w "%{http_code}" https://${INSTANCE_FQDN}/adcv2/server`
  curl_response="nope"
  if [[ "$curl_response" != "200" ]]; then
    echo "the MTLS authentication is not available since the instance load balancer is not ADCv2 (http_code=$curl_response)"
    echo "The basic authentication will be used by the MID server"
    false;
  else
    echo "the instance is configured for the MTLS authentication"
    true;
  fi
}

should_mid_use_mtls() {
  if ! is_instance_using_adcv2; then
    return 0
  fi
  echo -n "Please select if the MTLS authentication will be used by the MID Server (press Enter for [y]): (y/n)"
    while true
    do
      read AUTH_TYPE_INP
      if [[ -z "$AUTH_TYPE_INP" ]]; then
        AUTH_TYPE_INP="y"
      fi
      if [[ "$AUTH_TYPE_INP" == "y" || "$AUTH_TYPE_INP" == "Y" ]]; then
        USE_MTLS="true"
        return 1 # use mtls
      elif [[ "$AUTH_TYPE_INP" == "n" || "$AUTH_TYPE_INP" == "N" ]]; then
        return 0 # don't use mtls
      fi
      echo -n "Invalid input. Please try again (press Enter for [y]): (y/n)"
    done
}

enter_key_and_cert_for_mid() {
  echo -n "Please enter the MID Server private key file path (absolute or relative):"
  while true
  do
    read PATH_TO_MID_KEY
    if [[ -f "$PATH_TO_MID_KEY" ]]; then
      MID_KEY_FILENAME=$(basename "$PATH_TO_MID_KEY")
      if [[ ${#PATH_TO_MID_KEY} = ${#MID_KEY_FILENAME} ]]; then
        PATH_TO_MID_KEY="./$PATH_TO_MID_KEY"
      fi
      break
    fi
    echo "The provided private key file path $PATH_TO_MID_KEY doesn't exist. Please try again:";
  done

  echo -n "Please enter the MID Server certificate file path (absolute or relative):"
  while true
  do
    read PATH_TO_MID_CERT
    if [[ -f "$PATH_TO_MID_CERT" ]]; then
      MID_CERT_FILENAME=$(basename "$PATH_TO_MID_CERT")
      if [[ ${#PATH_TO_MID_CERT} = ${#MID_CERT_FILENAME} ]]; then
        PATH_TO_MID_CERT="./$PATH_TO_MID_CERT"
      fi
      break
    fi
    echo "The provided certificate file path $PATH_TO_MID_CERT doesn't exist. Please try again:";
  done

  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i "bak" "s?TLS_PEM_BUNDLE_VALUE?$(cat $PATH_TO_MID_KEY $PATH_TO_MID_CERT | base64)?" servicenow_acc_mid_temp.yml
  else
    sed -i 's/TLS_PEM_BUNDLE_VALUE/'"$(cat $PATH_TO_MID_KEY $PATH_TO_MID_CERT | base64 | tr -d '\n')"'/g' servicenow_acc_mid_temp.yml
  fi
}

enter_password() {
  #echo -n "Please enter the password of the user $INSTANCE_USERNAME: ";stty -echo; read INSTANCE_PASSWORD; stty echo; echo
  BASE_64_CRED=`echo -n "$INSTANCE_USERNAME:$INSTANCE_PASSWORD"| base64`

  INSTANCE_PASSWORD=`echo $INSTANCE_PASSWORD | base64`

  #echo -n "Please re-enter the password: ";stty -echo; read INSTANCE_PASSWORD1; stty echo; echo
  #INSTANCE_PASSWORD1=`echo $INSTANCE_PASSWORD1 | base64`

  #if [[ "$INSTANCE_PASSWORD" != "$INSTANCE_PASSWORD1" ]]; then
  #    echo -n "Passwords do not match. The deployment can't proceed"; echo
  #    exit 1
  #  fi
}

set_mid_api_key() {
  # Value of MID_API_KEY is set as env variable before script call
  #BASE64_MID_API_KEY=`echo -n $MID_API_KEY | base64`
  BASE64_MID_API_KEY=`echo -n $API_KEY | base64`
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i 'bak' 's/MID_API_KEY_VALUE/'$BASE64_MID_API_KEY'/g' servicenow_acc_mid_temp.yml
  else
    sed -i 's/MID_API_KEY_VALUE/'$BASE64_MID_API_KEY'/g' servicenow_acc_mid_temp.yml
  fi
}

validate_image_url() {
  # Validate if images are defined for ACC and MID containers
  NUM_OF_IMAGES=0
  if grep -q "MID_IMAGE_URL_VALUE" servicenow_acc_mid_temp.yml; then
    echo "Invalid deployment configuration: the MID image url is missing."
    echo "Please replace the placeholder MID_IMAGE_URL_VALUE by the image url in all files in the table 'sn_k8s_itom_config' and try again"
    NUM_OF_IMAGES=1
  fi

  if grep -q "ACC_IMAGE_URL_VALUE" servicenow_acc_mid_temp.yml; then
    echo "Invalid deployment configuration: the ACC image url is missing."
    echo "Please replace the placeholder ACC_IMAGE_URL_VALUE by the image url in all files in the table 'sn_k8s_itom_config' and try again"
    NUM_OF_IMAGES=2
  fi

  if [[ "${NUM_OF_IMAGES}" -gt 0 ]]; then
    exit 1
  fi
}

cno_rest_api() {
  REST_API_RESOURCE=$1
   # If no MTLS auth use basic auth cred
  if [[ -z "$USE_MTLS" ]]; then
    url_response=`curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Basic $BASE_64_CRED" https://${INSTANCE_FQDN}/api/sn_k8s/cni_api/${REST_API_RESOURCE}`
  else
    set +e
    url_response=`curl -s -o /dev/null -w "%{http_code}" --key $PATH_TO_MID_KEY --cert $PATH_TO_MID_CERT https://${INSTANCE_FQDN}/api/sn_k8s/cni_api/${REST_API_RESOURCE}`
    set -e
  fi

  if [[ "$url_response" != "200" ]]; then
    echo "Invalid credentials were provided (http_code=$url_response). The deployment can't proceed"
    exit 1
  fi
}

validate_credentials() {
  echo -n "Validating the provided credentials  .....  "
  cno_rest_api check_cred_mid
  cno_rest_api check_cred_disco
  echo "the provided credentials are valid"
}

function valid_port {
    local port=$1
    local stat=0
    if  (($port < 1 || $port > 65535)); then
        stat=1
    fi
    return $stat
}

# This procedure is used to collect the namespace or project (In OpenShift) name
# And create our components under this namespace to avoid hardcoded names
enter_namespace() {
  local namespace_alias="namespace"
  #local CURRENT_NAMESPACE="servicenow"
  local CURRENT_NAMESPACE="sn-${INSTANCE}"

  if [[ "$CLUSTER_TYPE" == "OC" ]]; then
    namespace_alias="project"
  fi

  #echo -n "Please enter the name of $namespace_alias (press Enter to use default $namespace_alias $CURRENT_NAMESPACE): "; read NAMESPACE

  if [ -z "$NAMESPACE" ]
  then
      NAMESPACE=$CURRENT_NAMESPACE
  fi

  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i 'bak' 's/NAMESPACE_VALUE/'$NAMESPACE'/g' servicenow_acc_mid_temp.yml
  else
    sed -i 's/NAMESPACE_VALUE/'$NAMESPACE'/g' servicenow_acc_mid_temp.yml
  fi
}

# This procedure is used to enable or disable proxy on MID
# The current implementation is not support proxy with credentials based auth
configure_proxy() {
  #read -p "Please select if the MID Server is working via proxy (press Enter for [n]): (y/n)" is_proxy
  is_proxy="n"
  local PROXY_HOST=""
  local PROXY_PORT=""
  local PROXY_ENABLED="false"
  case ${is_proxy:0:1} in
      y|Y )
        PROXY_ENABLED="true"
        read -p "Please enter the proxy host: " PROXY_HOST
        if [ -z "$PROXY_HOST" ]; then
          echo "The proxy host is empty, the deployment can't proceed" 1>&2
          exit 1
        fi

        read -p "Please enter the proxy port: " PROXY_PORT
        if ! valid_port $PROXY_PORT; then
          echo "The port [${PROXY_PORT}] is not valid, the deployment can't proceed" 1>&2
          exit 1
        fi
      ;;
      * )
      ;;
  esac

  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i 'bak' 's/PROXY_ENABLED_VALUE/'\"$PROXY_ENABLED\"'/g' servicenow_acc_mid_temp.yml
    sed -i 'bak' 's/PROXY_HOST_VALUE/'\"$PROXY_HOST\"'/g' servicenow_acc_mid_temp.yml
    sed -i 'bak' 's/PROXY_PORT_VALUE/'\"$PROXY_PORT\"'/g' servicenow_acc_mid_temp.yml
  else
    sed -i 's/PROXY_ENABLED_VALUE/'\"$PROXY_ENABLED\"'/g' servicenow_acc_mid_temp.yml
    sed -i 's/PROXY_HOST_VALUE/'\"$PROXY_HOST\"'/g' servicenow_acc_mid_temp.yml
    sed -i 's/PROXY_PORT_VALUE/'\"$PROXY_PORT\"'/g' servicenow_acc_mid_temp.yml
  fi

}

# if INSTANCE_NAME starts with thunderdonme, build the URL according to thunderdome naming
setInstanceFqdn() {
  if [[ "$INSTANCE_NAME" == "thunderdome-k8s"* ]]; then
    INSTANCE_NAME=${INSTANCE_NAME:12}
    INSTANCE_FQDN=${INSTANCE_NAME}-node1.thunder.devsnc.com
  else
    INSTANCE_FQDN=${INSTANCE_NAME}.service-now.com
  fi
}

#This procedure is responsible for initalization of sn_k8s_cno_deployment_status table
# due deployment activation
update_deployment_status() {
curl -H "Authorization: Basic $BASE_64_CRED" https://${INSTANCE_FQDN}/api/sn_k8s/cni_api/sn_deployment_status \
--request POST \
--header "Accept:application/json" \
--header "Content-Type:application/json" \
--data "{
        \"deployment_status\": {
                \"deployment_id\": \"$SUFFIX_UID_SHORT\"
        }
}"
}

#echo -n "Please enter the instance name (press Enter for instance <myinstance>): "; read INSTANCE_NAME
INSTANCE_NAME=$INSTANCE
if [ -z "$INSTANCE_NAME" ]
then
    INSTANCE_NAME=<myinstance>
    setInstanceFqdn
else
  setInstanceFqdn
  is_inst_alive=`curl -Is https://${INSTANCE_FQDN} | head -1|cut '-d ' '-f2'`
  if [[ "$is_inst_alive" != "200" ]]; then
      echo "The instance name ${INSTANCE_FQDN} is not valid, the deployment can't proceed"
      exit 1
  fi
fi

# Value of INSTANCE_USERNAME is set as env variable before script call
BASE_64_INSTANCE_USERNAME=`echo $INSTANCE_USERNAME | base64`

enter_password

#if ! should_mid_use_mtls $1 ; then
   # Download a config YAML file which has the TLS secret instead of the basic auth secret
#  if [[ "$CLUSTER_TYPE" == "OC" ]]; then
#    curl -Ls -H "Authorization: Basic $BASE_64_CRED" https://${INSTANCE_FQDN}/api/sn_k8s/cni_api/sn_app_config\?mid_auth_type=mtls\&cluster_type=oc > servicenow_acc_mid_temp.yml; echo
#  else
#    curl -Ls -H "Authorization: Basic $BASE_64_CRED" https://${INSTANCE_FQDN}/api/sn_k8s/cni_api/sn_app_config\?mid_auth_type=mtls > servicenow_acc_mid_temp.yml; echo
#  fi
#  enter_key_and_cert_for_mid
#else
#$  if [[ "$CLUSTER_TYPE" == "OC" ]]; then
#    curl -Ls -H "Authorization: Basic $BASE_64_CRED" https://${INSTANCE_FQDN}/api/sn_k8s/cni_api/sn_app_config\?cluster_type=oc > servicenow_acc_mid_temp.yml; echo
#  else
#    curl -H "Authorization: Basic $BASE_64_CRED" https://${INSTANCE_FQDN}/api/sn_k8s/cni_api/sn_app_config > servicenow_acc_mid_temp.yml; echo
#  fi

#validate_image_url

#  -H "Authorization: Basic $BASE_64_CRED"
#  if [[ "$OSTYPE" == "darwin"* ]]; then
#    sed -i 'bak' 's/INSTANCE_USERNAME_VALUE/'$BASE_64_INSTANCE_USERNAME'/g' servicenow_acc_mid_temp.yml;
#    sed -i 'bak' 's/INSTANCE_PASSWORD_VALUE/'$INSTANCE_PASSWORD'/g' servicenow_acc_mid_temp.yml;
#  else
#    sed -i 's/INSTANCE_USERNAME_VALUE/'$BASE_64_INSTANCE_USERNAME'/g' servicenow_acc_mid_temp.yml;
#    sed -i 's/INSTANCE_PASSWORD_VALUE/'$INSTANCE_PASSWORD'/g' servicenow_acc_mid_temp.yml;
#  fi
#fi
sed -i 's/INSTANCE_USERNAME_VALUE/'$BASE_64_INSTANCE_USERNAME'/g' servicenow_acc_mid_temp.yml;
sed -i 's/INSTANCE_PASSWORD_VALUE/'$INSTANCE_PASSWORD'/g' servicenow_acc_mid_temp.yml;

CLUSTER_NAME=""
SUFFIX_UID_FULL=""
SUFFIX_UID_SHORT=""

# we must shorten the cluster name/id as it is part of the MID name, and MID name is max 40 chars
if [[ "$CLUSTER_TYPE" == "OC" ]]; then
  CLUSTER_NAME=`kubectl get clusterversion -o jsonpath='{.items[].spec.clusterID}{"\n"}'`
  SUFFIX_UID_FULL=${CLUSTER_NAME}
else
  CURRENT_CONTEXT=`kubectl config current-context`
  CLUSTER_NAME=`echo ${CURRENT_CONTEXT}|xargs basename`
  if [[ "$OSTYPE" == "darwin"* ]]; then
    SUFFIX_UID_FULL=`echo ${CLUSTER_NAME}${INSTANCE_NAME}|md5`
  else
    SUFFIX_UID_FULL=`echo ${CLUSTER_NAME}${INSTANCE_NAME}|md5sum|cut -c 1-32`
  fi
fi

SUFFIX_UID_SHORT=${SUFFIX_UID_FULL: -5}

if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i 'bak' 's/CLUSTER_NAME_VALUE/'$CLUSTER_NAME'/g' servicenow_acc_mid_temp.yml
  sed -i 'bak' 's/INSTANCE_NAME/'$INSTANCE_NAME'/g' servicenow_acc_mid_temp.yml
  sed -i 'bak' 's/INSTANCE_FQDN/'$INSTANCE_FQDN'/g' servicenow_acc_mid_temp.yml
  sed -i 'bak' 's/SUFFIX_UID_SHORT/'$SUFFIX_UID_SHORT'/g' servicenow_acc_mid_temp.yml
else
  sed -i 's/CLUSTER_NAME_VALUE/'$CLUSTER_NAME'/g' servicenow_acc_mid_temp.yml
  sed -i 's/INSTANCE_NAME/'$INSTANCE_NAME'/g' servicenow_acc_mid_temp.yml
  sed -i 's/INSTANCE_FQDN/'$INSTANCE_FQDN'/g' servicenow_acc_mid_temp.yml
  sed -i 's/SUFFIX_UID_SHORT/'$SUFFIX_UID_SHORT'/g' servicenow_acc_mid_temp.yml
fi

validate_credentials

#configure_proxy

enter_namespace

set_mid_api_key

update_deployment_status

kubectl apply -f servicenow_acc_mid_temp.yml

# The file is kept in debug mode
#if [ -z "$SN_DEBUG" ]; then
#    rm servicenow_acc_mid_temp.yml*
#else
#    echo "Keeping servicenow_acc_mid_temp.yml for debugging"
#    rm servicenow_acc_mid_temp.ymlbak
#fi
