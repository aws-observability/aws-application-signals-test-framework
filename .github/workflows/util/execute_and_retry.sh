#!/bin/bash

# This function is for retrying commands in the case they fail. It accepts three arguments
# $1: Number of retries it will attempt
# $2: Command to execute
# $3: (Optional) Command for cleaning up resources if $2 fails.
# $4: (Optional) Sleep time between run. Default value is 10 seconds
execute_and_retry () {
  # Warning: The variables called in this function are not local and will be shared with the calling function.
  # Make sure that the variable names do not conflict
  execute_retry_counter=0
  max_execute_retry=$1
  command=$2
  cleanup=$3
  sleep_time=$4
  echo "Initiating execute_and_retry.sh script for command $command"
  while [ $execute_retry_counter -lt $max_execute_retry ]; do
   echo "Attempt Number $execute_retry_counter for execute_and_retry.sh"
   attempt_failed=0
   eval "$command" || attempt_failed=$?

   if [ $attempt_failed -ne 0 ]; then
     echo "Command failed for execute_and_retry.sh, executing cleanup command for another attempt"
     eval "$cleanup"
     execute_retry_counter=$(($execute_retry_counter+1))
     sleep "${sleep_time:-10}"
   else
     echo "Command executed successfully for execute_and_retry.sh, exiting script"
     break
   fi

   if [ "$execute_retry_counter" -ge "$max_execute_retry" ]; then
     echo "Max retry reached, command failed to execute properly. Exiting execute_and_retry.sh script"
     exit 1
   fi
  done
}

export VARIABLE=execute_and_retry