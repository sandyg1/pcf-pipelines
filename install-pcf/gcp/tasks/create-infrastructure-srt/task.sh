#!/bin/bash
set -eu

root=$PWD

# us: ops-manager-us/pcf-gcp-1.9.2.tar.gz -> ops-manager-us/pcf-gcp-1.9.2.tar.gz
pcf_opsman_bucket_path=$(grep -i 'us:.*.tar.gz' pivnet-opsmgr/*GCP.yml | cut -d' ' -f2)

# ops-manager-us/pcf-gcp-1.9.2.tar.gz -> opsman-pcf-gcp-1-9-2
pcf_opsman_image_name=$(echo $pcf_opsman_bucket_path | sed 's%.*/\(.*\).tar.gz%opsman-\1%' | sed 's/\./-/g')



if [[ ${POE_SSL_NAME1} == "" || ${POE_SSL_NAME1} == "null" ]]; then
  echo "Generating Self Signed Certs for ${SYSTEM_DOMAIN} & ${APPS_DOMAIN} ..."
  pcf-pipelines/scripts/gen_ssl_certs.sh "${SYSTEM_DOMAIN}" "${APPS_DOMAIN}"
  pcf_ert_ssl_cert=$(cat ${SYSTEM_DOMAIN}.crt)
  pcf_ert_ssl_key=$(cat ${SYSTEM_DOMAIN}.key)
else
  pcf_ert_ssl_cert="$POE_SSL_CERT1"
  pcf_ert_ssl_key="$POE_SSL_KEY1"
fi

export GOOGLE_CREDENTIALS=${GCP_SERVICE_ACCOUNT_KEY}
export GOOGLE_PROJECT=${GCP_PROJECT_ID}
export GOOGLE_REGION=${GCP_REGION}

terraform init pcf-pipelines/install-pcf/gcp/terraform-srt

terraform plan \
  -var "gcp_proj_id=${GCP_PROJECT_ID}" \
  -var "gcp_region=${GCP_REGION}" \
  -var "gcp_zone_1=${GCP_ZONE_1}" \
  -var "gcp_zone_2=${GCP_ZONE_2}" \
  -var "gcp_zone_3=${GCP_ZONE_3}" \
  -var "gcp_storage_bucket_location=${GCP_STORAGE_BUCKET_LOCATION}" \
  -var "prefix=${GCP_RESOURCE_PREFIX}" \
  -var "pcf_opsman_image_name=${pcf_opsman_image_name}" \
  -var "pcf_ert_domain=${PCF_ERT_DOMAIN}" \
  -var "system_domain=${SYSTEM_DOMAIN}" \
  -var "apps_domain=${APPS_DOMAIN}" \
  -var "pcf_ert_ssl_cert=${pcf_ert_ssl_cert}" \
  -var "pcf_ert_ssl_key=${pcf_ert_ssl_key}" \
  -out terraform.tfplan \
  -state terraform-state/terraform.tfstate \
  pcf-pipelines/install-pcf/gcp/terraform-srt

terraform apply \
  -state-out $root/create-infrastructure-output/terraform.tfstate \
  -parallelism=5 \
  terraform.tfplan

cd $root/create-infrastructure-output
  output_json=$(terraform output -json -state=terraform.tfstate)
  pub_ip_global_pcf=$(echo $output_json | jq --raw-output '.pub_ip_global_pcf.value')
  pub_ip_ssh_and_doppler=$(echo $output_json | jq --raw-output '.pub_ip_ssh_and_doppler.value')
  pub_ip_ssh_tcp_lb=$(echo $output_json | jq --raw-output '.pub_ip_ssh_tcp_lb.value')
  pub_ip_opsman=$(echo $output_json | jq --raw-output '.pub_ip_opsman.value')
cd -

echo "Please configure DNS as follows:"
echo "----------------------------------------------------------------------------------------------"
echo "*.${SYSTEM_DOMAIN} == ${pub_ip_global_pcf}"
echo "*.${APPS_DOMAIN} == ${pub_ip_global_pcf}"
echo "ssh.${SYSTEM_DOMAIN} == ${pub_ip_ssh_and_doppler}"
echo "doppler.${SYSTEM_DOMAIN} == ${pub_ip_ssh_and_doppler}"
echo "loggregator.${SYSTEM_DOMAIN} == ${pub_ip_ssh_and_doppler}"
echo "tcp.${PCF_ERT_DOMAIN} == ${pub_ip_ssh_tcp_lb}"
echo "opsman.${PCF_ERT_DOMAIN} == ${pub_ip_opsman}"
echo "----------------------------------------------------------------------------------------------"
