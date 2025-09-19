#!/bin/bash

while true; do
  for i in {1..9}; do
    curl -s "http://$MAIN_ENDPOINT/status/200?ip=$REMOTE_ENDPOINT"
    echo
    sleep 0.5
  done
  curl -s "http://$MAIN_ENDPOINT/status/500?ip=$REMOTE_ENDPOINT"
  echo
  curl -s "http://$MAIN_ENDPOINT/status/500?ip=$REMOTE_ENDPOINT"
  echo
  sleep 0.5
done