#!/bin/bash
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
  
  get_info_from_rancher_metadata_by_resource "/self/service/containers/0/uuid"
}

# Request to Rancher Metadata service the current container UUID.
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
function get_current_uuid() {
  
  get_info_from_rancher_metadata_by_resource "/self/container/uuid"
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

  verify_required_environment_variables

  if [[ $? -ne 0 ]]; then
    print_error_message "Impossible enter in the Redis replication mode."
    exit 1
  fi

  if [[ "$(get_current_uuid)" == "$(get_master_uuid)" ]]; then
    
    run_redis_in_foreground_mode "master"
  else

    run_redis_in_foreground_mode "slave" "$(get_master_ip_address)"
  fi
}

main