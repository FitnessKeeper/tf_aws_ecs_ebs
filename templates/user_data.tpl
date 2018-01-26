#!/bin/bash
echo ECS_CLUSTER=${cluster_name} >> /etc/ecs/ecs.config
echo 'OPTIONS="$${OPTIONS} --storage-opt dm.basesize=${docker_storage_size}G"' >> /etc/sysconfig/docker
/etc/init.d/docker restart
echo ECS_ENGINE_AUTH_TYPE=dockercfg >> /etc/ecs/ecs.config
echo 'ECS_ENGINE_AUTH_DATA={"https://index.docker.io/v1/": { "auth": "${dockerhub_token}", "email": "${dockerhub_email}"}}' >> /etc/ecs/ecs.config

# mount additional EBS volume
mkdir -p /opt/data

# loop until EBS volume is available
until mount -t ext4 -o ro ${data_device} /opt/data 2>/dev/null; do
  echo "Waiting for ${data_device} to become available..."
  sleep 1
done

# Append addition user-data script
${additional_user_data_script}
