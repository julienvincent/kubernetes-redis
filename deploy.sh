# #!/usr/bin/env bash
export STAGE=${1}
export REGISTRY=${2}
export NAMESPACE=${3}

if [[ ! -n ${REGISTRY }]]; then
  echo "--> No registry provided. Please provide a google registry as the second argument"
fi

export IMAGE_NAME=eu.gcr.io/${REGISTRY}/redis-${STAGE}:$(uuidgen)

if [[ ! -n ${STAGE} ]]; then
  echo "--> No stage provided. Please provide a stage as first argument"
  exit 1
fi

if [[ ! -n ${NAMESPACE} ]]; then
  NAMESPACE=default
fi

docker build . -t ${IMAGE_NAME}

if ! gcloud docker -- push ${IMAGE_NAME}; then
  echo "--> Error pushing container to registry"
  exit 1
fi

mkdir _redis

envsubst < deployment/Namespace.yml > _redis/00Namespace.yml
envsubst < deployment/Services.yml > _redis/10Services.yml
envsubst < deployment/Sentinel.yml > _redis/20Sentinel.yml
envsubst < deployment/Slave.yml > _redis/30Slave.yml

kubectl apply -f ./_redis/ --record

rm -rf _redis
