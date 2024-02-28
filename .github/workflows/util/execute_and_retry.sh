#!/bin/bash

execute_and_retry () {
  retry_counter=0
  max_retry=$1
  while [ $retry_counter -lt $max_retry ]; do
   deployment_failed=0
   eval "$2" || deployment_failed=$?

   if [ $deployment_failed -eq 1 ]; then
     eval "$3"
     retry_counter=$(($retry_counter+1))
     sleep 5
   else
     break
   fi

   if [ $retry_counter -eq $max_retry ]; then
     echo "Max retry reached, command failed to execute properly. Exiting code"
     exit 1
   fi
  done
}

export -f execute_and_retry