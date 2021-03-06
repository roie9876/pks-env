#!/usr/bin/env bash
# Set this via a env var
# CONCOURSE_URL="http://10.33.75.99:8080"
# EXTERNAL_DNS=<dns_ip>
# IMAGE_WEBSERVER_PORT=<port_number>
# VMWARE_USER
# VMWARE_PASSWORD
# NSXT_VERSION
# PIPELINE_BRANCH

ROOT_WORK_DIR="/home/workspace"
BIND_MOUNT_DIR="/home/concourse"
CONFIG_FILE_NAME="nsx_pipeline_config.yml"
CONFIG_FILE_NAME="pks_pipeline_config.yml"
HARBOR_FILE_NAME="harbor_pipeline_config.yml"

if [[ ! -e ${BIND_MOUNT_DIR}/${CONFIG_FILE_NAME} ]]; then
	echo "Config file ${BIND_MOUNT_DIR}/${CONFIG_FILE_NAME} not found, exiting"
	exit 1
fi

pipeline_internal_config="pipeline_config_internal.yml"

mkdir -p $ROOT_WORK_DIR
cd $ROOT_WORK_DIR
git clone https://github.com/concourse/concourse-docker.git
git clone https://github.com/sparameswaran/nsx-t-ci-pipeline.git

concourse_docker_dir=${ROOT_WORK_DIR}/concourse-docker
pipeline_dir=${ROOT_WORK_DIR}/nsx-t-ci-pipeline
cp ${concourse_docker_dir}/generate-keys.sh $BIND_MOUNT_DIR
cp ${pipeline_dir}/docker_compose/docker-compose.yml $BIND_MOUNT_DIR

# using fly to start the pipeline
CONCOURSE_TARGET=nsx-concourse
PIPELINE_NAME=pks-install
echo "logging into concourse at $CONCOURSE_URL"
fly -t $CONCOURSE_TARGET sync
fly --target $CONCOURSE_TARGET login --insecure --concourse-url $CONCOURSE_URL -n main
echo "setting the NSX-t install pipeline $PIPELINE_NAME"
fly_reset_cmd="fly -t $CONCOURSE_TARGET set-pipeline -p $PIPELINE_NAME -c ${pipeline_dir}/pipelines/install-pks-pipeline.yml -l ${BIND_MOUNT_DIR}/${pipeline_internal_config} -l ${BIND_MOUNT_DIR}/${CONFIG_FILE_NAME}"
yes | $fly_reset_cmd
echo "unpausing the pipepline $PIPELINE_NAME"
fly -t $CONCOURSE_TARGET unpause-pipeline -p $PIPELINE_NAME

# add an alias for set-pipeline command
echo "alias fly-reset=\"$fly_reset_cmd\"" >> ~/.bashrc
destroy_cmd="cd $BIND_MOUNT_DIR; fly -t $CONCOURSE_TARGET destroy-pipeline -p $PIPELINE_NAME; docker-compose down; docker stop nginx-server; docker rm nginx-server;"
echo "alias destroy=\"$destroy_cmd\"" >> ~/.bashrc
source ~/.bashrc

while true; do
	is_worker_running=$(docker ps | grep concourse-worker)
	if [[ ! $is_worker_running ]]; then
		docker-compose restart concourse-worker
		echo "concourse worker is down; restarted it"
		break
	fi
	sleep 5
done

sleep 3d
fly -t $CONCOURSE_TARGET destroy-pipeline -p $PIPELINE_NAME
docker-compose down
docker stop nginx-server
docker rm nginx-server
exit 0
