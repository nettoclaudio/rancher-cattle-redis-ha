#!/bin/sh
#
# Identify the role (master or slave) of the current container in the cluster, 
# load the defaults configurations (redis.conf) based on that role and launch 
# the Redis service.
#
# Warning: This script relies on Rancher Metadata service for obtain informa-
# tion as Redis master IP address. For that make sure Rancher Metadata works.
set -e

# Prints a message on standard error output through the syslog tool.
#
# Globals:
#   None
#
# Arguments:
#   message - A string message.
#
# Returns:
#   None.
#
function print_error_message() {
  local message

  message="${1}"

  logger -s -t "redis-ha-entrypoint" "${message}"
}

# Given a resource (endpoint) it perform a HTTP request (method GET) on 
# Rancher Metadata service and show the content on standard output.
#
# Globals:
#   None
#
# Arguments:
#   resource - A string that means an endpoint on Rancher Metadata service.
#
#   rancher_metadata_version - would be: "2015-07-25", "2015-12-19", 
# "2016-07-29" (default value) or "latest".
#
# Returns:
#   A string that means the resource content on Rancher Metadata service.
#
function get_info_from_rancher_metadata_by_resource() {
  local resource
  local rancher_metadata_version

  resource="${1}"
  rancher_metadata_version=${2:-"2016-07-29"}

  wget -qO- "http://rancher-metadata.rancher.internal/${rancher_metadata_version}/${resource}"
}

# Executes a command on Redis instance.
#
# Globals:
#   REDIS_HA_MASTER_PASSWORD - Credential to authenticate on Rancher server
# before executing command.
#
# Arguments:
#   hostname - Redis server hostname (or IP address).
#
#   command - The command to be executed on Redis server.
#
# Returns:
#   a raw response of Redis command.
#
function execute_command_on_redis() {
  local hostname
  local command

  hostname=${1}
  command=${2}

  redis-cli --raw -a "${REDIS_HA_MASTER_PASSWORD}" -h "${hostname}" ${command}
}

# Checks if the Redis server is available.
#
# Globals:
#   None
#
# Arguments:
#   hostname - Redis server hostname (or IP address).
#
# Returns:
#   A status code number: 0 (success) or 1 (error).
#
function is_redis_available() {
  local hostname
  local response
  local exit_code

  hostname=${1}
  
  exit_code=1

  response=$(execute_command_on_redis ${hostname} "PING")

  if [[ $? -eq 0 ]] && [[ "${response}" == "PONG" ]]; then
    exit_code=0
  fi

  return ${exit_code}
}

# Get Redis master address from another Redis instance. Ask to Redis server
# which is your replication role to determine the Redis master address.
#
# Globals:
#   None
#
# Arguments:
#   hostname - Redis server hostname (or IP address).
#
# Returns:
#   A string of an IP address (e.g., 10.30.6.114.220).
#
function get_redis_master_address_from_another_redis_server() {
  local redis_master_address
  local redis_response
  local hostname

  hostname=${1}

  redis_response=$(execute_command_on_redis ${hostname} "ROLE")

  if [[ $? -ne 0 ]]; then
    print_error_message "Unexpected error at execution of ROLE command on Redis."
  fi

  role=$(printf "${redis_response}" | head -1)

  if [[ "${role}" == "master" ]]; then
    redis_master_address="${hostname}"
  fi

  if [[ "${role}" == "slave" ]]; then
    redis_master_address=$(printf "${redis_response}" | head -2 | tail -1)
  fi

  printf "%s" "${redis_master_address}"
}

# Get addresses of the non-stopped Redis servers (containers) in the Rancher 
# service.
#
# Globals:
#   None
#
# Arguments:
#   None
#
# Returns:
#   A list of IP adresses (separeted by new line '\n').
#
function get_addresses_of_running_redis_containers() {
  local number_of_containers
  local last_index
  local addresses
  local ip

  addresses=""

  number_of_containers=$(get_info_from_rancher_metadata_by_resource "/self/service/containers" | wc -l)

  last_index=$((${number_of_containers} - 1))

  for index in $(seq 0 ${last_index}); do
    state=$(get_info_from_rancher_metadata_by_resource "/self/service/containers/${index}/state")

    if [[ "${state}" == "stopped" ]]; then
      continue
    fi

    ip=$(get_info_from_rancher_metadata_by_resource "/self/service/containers/${index}/primary_ip")

    addresses="${ip}\n${addresses}"
  done

  printf ${addresses}
}

# Checks if the required environment variables are set.
#
# Globals:
#   REDIS_HA_MASTER_PASSWORD - A string that means the cluster credential.
#
# Arguments:
#   None
#
# Returns:
#   A status code number: 0 (success) or 1 (error).
#
function verify_required_environment_variables() {
  local exit_code

  exit_code=0

  if [[ -z "${REDIS_HA_MASTER_PASSWORD}" ]]; then
    exit_code=1

    print_error_message "The REDIS_HA_MASTER_PASSWORD environment variable is not set. Export it with the password being used to access the MASTER by either using the '-e' flag or on the docker-compose.yml. Remember to use the same password for both the Redis instances (master and slaves)."
  fi

  return ${exit_code}
}

# Request to Rancher Metadata service the current container IP address.
# 
# Globals:
#   None
#
# Arguments:
#   None
#
# Returns:
#   A string of an IP address (e.g., 10.30.6.114.220).
#
function get_current_ip_address() {
  
  get_info_from_rancher_metadata_by_resource "/self/container/primary_ip"
}

# Get the Redis master address. 
#
# Globals:
#   None
#
# Arguments:
#   None
#
# Returns:
#   A string of an IP address (e.g., 10.30.6.114.220).
#
function get_master_ip_address() {
  local master_address
  local addresses
  local address
  local fallback_master_address
  
  addresses=$(get_addresses_of_running_redis_containers)

  fallback_master_address=$(printf "${addresses}" | head -1)

  for address in ${addresses}; do
    is_redis_available "${address}"

    if [[ $? -ne 0 ]]; then
      continue
    fi

    master_address=$(get_redis_master_address_from_another_redis_server ${address})
    
    break
  done

  if [[ -z "${master_address}" ]]; then
    master_address="${fallback_master_address}"
  fi

  printf "${master_address}"
}

# Executes the Redis instance based on your role.
#
# Globals:
#   REDIS_HA_MASTER_PASSWORD -A string that means the Redis master credential.
#
# Arguments:
#   replication_role - A string which would be: "master" or "slave".
#
#   master_ip_address - A string of an IP address (required iff `replication_role`
# is equals to "slave")
#
# Returns:
#   None
#
function run_redis_in_foreground_mode() {
  local replication_role
  local master_ip_address
  local redis_replication_configs

  replication_role=${1}
  redis_replication_configs="--requirepass ${REDIS_HA_MASTER_PASSWORD} --masterauth ${REDIS_HA_MASTER_PASSWORD}"

  if [[ "${replication_role}" == "slave" ]]; then
    master_ip_address=${2}

    redis_replication_configs="${redis_replication_configs} --slaveof ${master_ip_address} 6379"
  fi

  exec redis-server ${redis_replication_configs}
}

# Initial function for flow control.
#
# Globals:
#   None
#
# Arguments:
#   None
#
# Returns:
#   None
#
function main() {
  local instance_role
  local redis_master_ip_address

  verify_required_environment_variables

  if [[ $? -ne 0 ]]; then
    print_error_message "Impossible entering on the Redis replication mode."
    exit 1
  fi

  redis_master_ip_address="$(get_master_ip_address)"

  if [[ "${redis_master_ip_address}" == "$(get_current_ip_address)" ]]; then
    instance_role="master"
  else
    instance_role="slave"
  fi

  run_redis_in_foreground_mode "${instance_role}" "${redis_master_ip_address}"
}

if [[ -n "${DEBUG_MODE}" ]] && [[ "${DEBUG_MODE}" == "true" ]]; then
  set -x
fi

main