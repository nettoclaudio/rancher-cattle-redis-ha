#!/bin/bash
#
# Identify the Redis Replication master (aka Redis master) through the Rancher
# Metadata service and connect to it as a Redis Sentinel.
#
# Warning: This script relies on Rancher Metadata service for obtain informa-
# tion about Redis master (IP address, for instance). For that make sure 
# Rancher Metadata works.
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

  logger -s -t "redis-ha-sentinel-entrypoint" "${message}"
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

# Checks if the required environment variables are set.
#
# Globals:
#   REDIS_HA_SENTINEL_QUORUM - Minimun number of Redis Sentinels for detect 
# master and start failover process if necessary.
#
#   REDIS_HA_SENTINEL_PASSWORD - The Redis AUTH credential.
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

  if [[ -z "${REDIS_HA_SENTINEL_QUORUM}" ]]; then
    exit_code=1

    print_error_message "The REDIS_HA_SENTINEL_QUORUM variable is not set (or is empty). Export it with the minimum acceptable quorum by either using the '-e' flag or on the docker-compose.yml."
  fi

  if [[ -z "${REDIS_HA_SENTINEL_PASSWORD}" ]]; then
    exit_code=1

    print_error_message "The REDIS_HA_SENTINEL_PASSWORD variable is not set (or is empty). Export it with the minimum acceptable quorum by either using the '-e' flag or on the docker-compose.yml."
  fi

  return ${exit_code}
}

# Request to Rancher Metadata service the container UUID such as is running in
# the master replication mode.
# 
# Warning: The master instance will be the first container requested by Rancher.
#          There are no ways to select the Redis master manually for now.
#
# Globals:
#   None
#
# Returns:
#   None
#
# Returns:
#   A string of an UUID (e.g., 319af1b9-feb7-448d-8dec-7c42c2a1e9ad).
#
function get_master_uuid() {
  local redis_service_name

  redis_service_name=${1:-"redis"}

  get_info_from_rancher_metadata_by_resource "/self/stack/services/${redis_service_name}/containers/0/uuid"
}

# Request to Rancher Metadata service the container IP such as is running in
# the master replication mode.
#
# Globals:
#   None
#
# Returns:
#   None
#
# Returns:
#   A string of an IP address (e.g., 10.30.6.114.220).
#
function get_master_ip_address() {
  local master_uuid

  master_uuid="$(get_master_uuid)"

  get_info_from_rancher_metadata_by_resource "/containers/${master_uuid}/primary_ip"
}

# Prepare the Redis Sentinel configuration file based on environment variables.
#
# Globals:
#   REDIS_HA_SENTINEL_MASTER_NAME - A string that contains the name of Redis 
# groups. (default value: 'redis-ha-default')
#
#   REDIS_HA_SENTINEL_MASTER_HOSTNAME - A string that contains the address of
# the Redis master instance.
#
#   REDIS_HA_SENTINEL_QUORUM - Minimun number of Redis Sentinels for detect 
# master and start failover process if necessary.
#
#   REDIS_HA_SENTINEL_PASSWORD - The Redis AUTH credential.
#
# Arguments:
#   $1 - A string that contains the address of the Redis master instance.
#
# Returns:
#   None
function prepare_sentinel_config_file() {
  local sentinel_config_file

  REDIS_HA_SENTINEL_MASTER_HOSTNAME=${1}
  export REDIS_HA_SENTINEL_MASTER_HOSTNAME

  sentinel_config_file=${2:-"/etc/redis/sentinel.conf"}

  if [[ -z "${REDIS_HA_SENTINEL_MASTER_NAME}" ]]; then
    REDIS_HA_SENTINEL_MASTER_NAME="redis-ha-default"
    print_error_message "The REDIS_HA_SENTINEL_MASTER_NAME variable is not set. Assuming default value '${REDIS_HA_SENTINEL_MASTER_NAME}'."

    export REDIS_HA_SENTINEL_MASTER_NAME
  fi

  if [[ ! -f "${sentinel_config_file}" ]]; then

    envsubst '${REDIS_HA_SENTINEL_MASTER_NAME}:${REDIS_HA_SENTINEL_MASTER_HOSTNAME}:${REDIS_HA_SENTINEL_QUORUM}:${REDIS_HA_SENTINEL_PASSWORD}' < "${sentinel_config_file}.skel" > "${sentinel_config_file}"
  fi

  chmod 640 "${sentinel_config_file}"
}

#  Executes the Redis Sentinel in foreground mode.
#
# Globals:
#   None
#
# Arguments:
#   sentinel_config_file - An absolute filename on systemfile. 
# (default value: '/etc/redis/sentinel.conf')
#
# Returns:
#   None
#
function run_redis_sentinel_in_foreground_mode() {
  local sentinel_config_file

  sentinel_config_file=${1:-"/etc/redis/sentinel.conf"}

  exec redis-server "${sentinel_config_file}" --sentinel
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

  verify_required_environment_variables

  if [[ $? -ne 0 ]]; then
    print_error_message "Impossible initialize the Redis Sentinel."
    exit 1
  fi

  prepare_sentinel_config_file "$(get_master_ip_address)"

  run_redis_sentinel_in_foreground_mode
}

main