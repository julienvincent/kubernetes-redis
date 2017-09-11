#!/bin/bash
mkdir /redis-master-data

function getMasterFromSentinel {
  ADDRESS=$(timeout -t 2 redis-cli -h redis-sentinel-${STAGE} -p 26379 --csv SENTINEL get-master-addr-by-name mymaster | tr ',' ' ' | cut -d' ' -f1)

  if [[ -n ${ADDRESS} ]]
    then {
      ADDRESS="${ADDRESS//\"}"
    }
    else {
      return 1
    }
  fi

  redis-cli -h ${ADDRESS} INFO
  if [[ ${?} == 0 ]]; then
    echo ${ADDRESS}
    return 0
  fi

  return 1
}

function getMasterFromApi {
  TOKEN=$(</var/run/secrets/kubernetes.io/serviceaccount/token)
  K8_URL=https://${KUBERNETES_SERVICE_HOST}/api/v1/namespaces/${NAMESPACE}/endpoints/redis-slave-${STAGE}
  ADDRESSES=$(curl -sSk -H "Authorization: Bearer ${TOKEN}" ${K8_URL} | jq -r '.subsets[].addresses')

  if [[ ${ADDRESSES} == "null" ]]; then
    return 1
  fi

  IP_ADDRESSES=( $(echo ${ADDRESSES} | jq -r '.[].ip') )

  for i in "${IP_ADDRESSES[@]}"; do
	  INSTANCE_ROLE=$(timeout -t 2 redis-cli -h ${i} INFO | grep ^role | tr -d '\040\011\012\015')

    if [[ "${INSTANCE_ROLE}" == "role:master" ]]; then
      MASTER_IP=${i}
      break
    fi
  done

  if [[ -n ${MASTER_IP} ]]; then
    echo ${MASTER_IP}
    return 0
  fi

  return 1
}

function getCurrentMaster {
  CURRENT_MASTER=$(getMasterFromSentinel)
  if [[ ${?} == 0 ]]; then
    echo ${CURRENT_MASTER}
    return 0
  fi

  CURRENT_MASTER=$(getMasterFromApi)
  if [[ ${?} == 0 ]]; then
    echo ${CURRENT_MASTER}
    return 0
  fi

  return 1
}

function launchMaster {
  redis-server /redis-master/redis.conf --protected-mode no
}

function launchSentinel {
  while true; do
    MASTER=$(getCurrentMaster)

    if [[ ${?} == 0 ]]; then
      echo "Master found with IP: ${MASTER}"
      break
    fi

    echo "Couldn't find master. Retrying in 10..."
    sleep 10
  done

  sentinel_conf=sentinel.conf

  echo "sentinel monitor mymaster ${MASTER} 6379 2" > ${sentinel_conf}
  echo "sentinel down-after-milliseconds mymaster 5000" >> ${sentinel_conf}
  echo "sentinel parallel-syncs mymaster 1" >> ${sentinel_conf}
  echo "bind 0.0.0.0" >> ${sentinel_conf}

  redis-sentinel ${sentinel_conf} --protected-mode no
}

function launchSlave {
  sed -i "s/%master-ip%/${1}/" /redis-slave/redis.conf
  sed -i "s/%master-port%/6379/" /redis-slave/redis.conf
  redis-server /redis-slave/redis.conf --protected-mode no
}

function launch {
  while true; do
    MASTER=$(getCurrentMaster)

    if [[ ${?} == 0 ]]; then
      echo "Master found with IP: ${MASTER}"
      launchSlave ${MASTER}
      break
    fi

    if [[ "${HOSTNAME}" == "redis-slave-${STAGE}-0" ]]; then
      LAUNCH_MASTER=1
      break
    fi

    echo "Couldn't find master. Retrying in 10..."
    sleep 10
  done

  if [[ -n ${LAUNCH_MASTER} ]]; then
    launchMaster
  fi
}

if [[ "${REDIS_INSTANCE_TYPE}" == "sentinel" ]]; then
  launchSentinel
  exit 0
fi

launch
