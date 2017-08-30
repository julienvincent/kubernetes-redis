# #!/usr/bin/env bash
export STAGE="$1"
export IMAGE_NAME=eu.gcr.io/one-day-only-infrastructure/redis-${STAGE}:$(uuidgen)

docker build . -t ${IMAGE_NAME}

if gcloud docker -- push ${IMAGE_NAME}
  then echo "container pushed correctly"
  # If the container push failed, we do not want to trigger a kube deploy.
  else echo "error pushing container to registry" && exit 1
fi

envsubst < deployment/SentinelService.yml > _SentinelService.yml
envsubst < deployment/Catalyst.yml > _Catalyst.yml
envsubst < deployment/Sentinel.yml > _Sentinel.yml
envsubst < deployment/Slave.yml > _Slave.yml

kubectl create -f _Catalyst.yml --record
kubectl apply -f _SentinelService.yml --record
kubectl apply -f _Sentinel.yml --record
kubectl apply -f _Slave.yml --record

kubectl rollout status deployment/redis-${STAGE}

rm _Catalyst.yml _SentinelService.yml _Sentinel.yml _Slave.yml
