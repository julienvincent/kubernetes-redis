#!/usr/bin/env bash
export STAGE="$1"
export IMAGE_NAME=eu.gcr.io/one-day-only-infrastructure/redis-${STAGE}:${CIRCLE_SHA1}

# Apply a container tag to the built container. This tag contains repository information
# which tells kubectl where to push the container, as well as a unique label which will
# be used to tell the Deployment which image to use.
docker tag redis ${IMAGE_NAME}

if sudo /opt/google-cloud-sdk/bin/gcloud docker -- push ${IMAGE_NAME}
    then echo "container pushed correctly"

    # If the container push failed, we do not want to trigger a kube deploy.
    else echo "error pushing container to registry" && exit 1
fi

# Inject environment variables into the deployment and service yml files
envsubst < deployment/SentinelService.yml > _SentinelService.yml

envsubst < deployment/Catalyst.yml > _Catalyst.yml
envsubst < deployment/Slave.yml > _Slave.yml
envsubst < deployment/Sentinel.yml > _Sentinel.yml

sudo /opt/google-cloud-sdk/bin/kubectl create -f _Catalyst.yml --record

sudo /opt/google-cloud-sdk/bin/kubectl apply -f _SentinelService.yml --record

sudo /opt/google-cloud-sdk/bin/kubectl apply -f _Sentinel.yml --record
sudo /opt/google-cloud-sdk/bin/kubectl apply -f _Slave.yml --record

# watch the deployment
sudo /opt/google-cloud-sdk/bin/kubectl rollout status deployment/redis-${STAGE}