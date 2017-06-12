#!/usr/bin/env bash
export STAGE="$1"

# Inject environment variables into the deployment and service yml files
envsubst < Service.yml > _Service.yml
envsubst < Catalyst.yml > _Catalyst.yml
envsubst < Master.yml > _Master.yml
envsubst < Sentinel.yml > _Sentinel.yml

function updateDeployments {
   sudo /opt/google-cloud-sdk/bin/kubectl apply -f _Service.yml --record
   sudo /opt/google-cloud-sdk/bin/kubectl apply -f _Master.yml --record
   sudo /opt/google-cloud-sdk/bin/kubectl apply -f _Sentinel.yml --record
}

if sudo /opt/google-cloud-sdk/bin/kubectl get deployment redis-master-${STAGE}
   then {
      updateDeployments
   }
   else {
      sudo /opt/google-cloud-sdk/bin/kubectl create -f _Catalyst.yaml --record
      updateDeployments
   }
fi
