# #!/usr/bin/env bash
export STAGE="$1"
export NAMESPACE="$2"
export IMAGE_NAME=eu.gcr.io/one-day-only-infrastructure/redis-${STAGE}:$(uuidgen)

if [ -z "${STAGE}" ]
then {
    echo No stage defined
    exit 1
  }
fi

if [ -z "${STAGE}" ]
then {
    NAMESPACE=default
  }
fi

docker build . -t ${IMAGE_NAME}

if gcloud docker -- push ${IMAGE_NAME}
then echo "container pushed correctly"
else echo "error pushing container to registry" && exit 1
fi

mkdir _redis

envsubst < deployment/Namespace.yml > _redis/00Namespace.yml
envsubst < deployment/Services.yml > _redis/10Services.yml
envsubst < deployment/Sentinel.yml > _redis/20Sentinel.yml
envsubst < deployment/Slave.yml > _redis/Slave.yml

kubectl apply -f ./_redis/ --record

rm -rf _redis
