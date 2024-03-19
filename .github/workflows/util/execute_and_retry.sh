#!/bin/bash

# This function is for retrying commands in the case they fail. It accepts three arguments
# $1: Number of retries it will attempt
# $2: Command to execute
# $3: (Optional) Command for cleaning up resources if $2 fails
execute_and_retry () {
  # Warning: The variables called in this function are not local and will be shared with the calling function.
  # Make sure that the variable names do not conflict
  execute_retry_counter=0
  max_execute_retry=$1
  command=$2
  cleanup=$3
  while [ $execute_retry_counter -lt $max_execute_retry ]; do
   attempt_failed=0
   eval "$command" || attempt_failed=$?

   if [ $attempt_failed -ne 0 ]; then
     eval "$cleanup"
     execute_retry_counter=$(($execute_retry_counter+1))
     sleep 5
   else
     break
   fi

   if [ $execute_retry_counter -eq $max_execute_retry ]; then
     echo "Max retry reached, command failed to execute properly. Exiting code"
     exit 1
   fi
  done
}

export -f execute_and_retry