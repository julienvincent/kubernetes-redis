#!/bin/bash
mkdir /redis-master-data

########################################################
# Attempt to query one of the live sentinel instances
# for the current master.

# If no sentinels are alive or no masters are currently
# known then it returns a non-0 exit code.
########################################################
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

  redis-cli -h ${ADDRESS} INFO > /dev/null 2>&1
  if [[ ${?} == 0 ]]; then
    echo ${ADDRESS}
    return 0
  fi

  return 1
}

########################################################
# Query all ready pod ip addresses that the slave
# service is currently matching over. 

# If there are at least one ip in the collection, loop 
# over the ip addresses and run a redis-cli INFO query. 

# If any of the INFO queries contain 'role:master' then
# return the matching ip address, otherwise return with
# a non-0 exit code
########################################################
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

########################################################
# Attempt to find an active master redis instance by
# querying first the sentinels and then the api in order
########################################################
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

########################################################
# Start looking for a redis master instance with 10
# second delays.

# If and when a master instance is found, configure the
# redis instance to be a sentinel and monitor the 
# discoverred master instance.
########################################################
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
