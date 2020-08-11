#!/bin/bash
%{ if eni_trunking_desired_setting != "unset" ~}

echo "checking AWS ECS account settings for ENI trunking awsvpcTrunking set on this instance role"
echo "installing dependencies"
yum install -y jq aws-cli

echo "getting aws ecs account settings"
aws ecs list-account-settings --region ${region} --name awsvpcTrunking > account-settings.json
cat account-settings.json
echo "getting value of awsvpcTrunking"
AWSVPCTRUNKING_SETTING=$(cat account-settings.json | jq --raw-output '.settings[] | .value' | sort | uniq)
echo $AWSVPCTRUNKING_SETTING
echo "converting terraform boolean ${eni_trunking_desired_setting} to aws api enabled or disabled"
if [[ "${eni_trunking_desired_setting}" == "true" ]] ; then \
  ENI_TRUNK_VALUE_DESIRED="enabled"
elif [[ "${eni_trunking_desired_setting}" == "false" ]] ; then  \
  ENI_TRUNK_VALUE_DESIRED="disabled"
else
  echo "shouldn't have reached this, exiting"
  exit
fi
echo "checking existing setting against desired setting: $${ENI_TRUNK_VALUE_DESIRED}"
if [[ "$${AWSVPCTRUNKING_SETTING}" != "$${ENI_TRUNK_VALUE_DESIRED}" ]]; then \
  echo "mismatch, setting"
  aws ecs put-account-setting \
      --name awsvpcTrunking \
      --value $ENI_TRUNK_VALUE_DESIRED \
      --region ${region}
  echo "done setting value"
  echo "checking feature flag for if this instance should terminate"
  aws ssm get-parameter --region ${region} --name "/ecs-cluster/${cluster_name}/eni_trunking_mismatch_on_boot_terminate_instance" > eni_trunking_mismatch_on_boot_terminate_instance.json
  cat eni_trunking_mismatch_on_boot_terminate_instance.json
  ENI_TRUNKING_MISMATCH_ON_BOOT_TERMINATE_INSTANCE=$(cat eni_trunking_mismatch_on_boot_terminate_instance.json | jq --raw-output '.Parameter .Value')
  echo "should terminate = $${ENI_TRUNKING_MISMATCH_ON_BOOT_TERMINATE_INSTANCE}"
  if [[ "$${ENI_TRUNKING_MISMATCH_ON_BOOT_TERMINATE_INSTANCE}" == "true" ]] ; then  \
    echo "terminating this instance"
    MY_INSTANCE_ID=$(cat /var/lib/cloud/data/instance-id)
    echo $${MY_INSTANCE_ID}
    aws ec2 terminate-instances --instance-ids $${MY_INSTANCE_ID} --region ${region}
    echo "done, exiting to prevent further userdata from running"
    exit 1
  else
    echo "feature flag is set to false or not set, so not terminating instance"
  fi # end should terminate on eni trunking mismatch
else
  echo "ENI Trunking is set correctly, no action needed"
fi # end eni trunking mismatch

%{ endif ~}
echo ECS_CLUSTER=${cluster_name} >> /etc/ecs/ecs.config
echo ECS_ENGINE_AUTH_TYPE=dockercfg >> /etc/ecs/ecs.config
echo 'ECS_ENGINE_AUTH_DATA={"https://index.docker.io/v1/": { "auth": "${dockerhub_token}", "email": "${dockerhub_email}"}}' >> /etc/ecs/ecs.config
mkfs -t ext4 $(readlink -f /dev/xvdcz)
e2label $(readlink -f /dev/xvdcz) docker-data
grep -q ^LABEL=docker-data /etc/fstab || echo "LABEL=docker-data /var/lib/docker ext4 defaults" >> /etc/fstab
grep -q ^LABEL=/opt/data /etc/fstab || echo "LABEL=/opt/data /opt/data ext4 defaults" >> /etc/fstab
grep -q "$(readlink -f /dev/xvdcz) /var/docker-data" /proc/mounts || mount /var/lib/docker
grep -q "$(readlink -f /dev/xvdcv) /opt/data" /proc/mounts || mount /opt/data
echo 'DOCKER_STORAGE_OPTIONS="--storage-driver overlay2"' > /etc/sysconfig/docker-storage
/sbin/service docker restart
mkdir -p /root/.docker
echo '{"auths": {"https://index.docker.io/v1/": { "auth": "${dockerhub_token}", "email": "${dockerhub_email}"}}}' >> /root/.docker/config.json

# Append addition user-data script
${additional_user_data_script}
