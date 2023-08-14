#!/bin/sh

# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

cloud-init status --wait
echo "##########CUSTOM_SCRIPT_URL###########: $CUSTOM_SCRIPT_URL"

if pgrep -xf "bash custom-script.sh"
then
    echo Exiting deployment as a workload is already executing.
    exit 1
esle
    echo Starting the worklaod.
# Running custom-script in background, arm template completion wont wait on this
# stdout and stderr will be logged in <$HOME>/custom-script.out and <$HOME>/custom-script.err
    curl -o custom-script.sh $CUSTOM_SCRIPT_URL
    nohup bash custom-script.sh > "/home/${ADMIN_USER_NAME}/agent.out" 2> "/home/${ADMIN_USER_NAME}/agent.err" &

fi