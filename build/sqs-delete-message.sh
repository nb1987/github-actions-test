#!/usr/bin/env bash

: ${ENVIRONMENT?"ENVIRONMENT env variable is required"}
: ${URL?"URL env variable is required"}
: ${ID?"ID env variable is required"}

#source node_modules/@ofx/bash-build-libraries/_ofx_env.sh
#source node_modules/@ofx/bash-build-libraries/_aws.sh

# Install JQ for parsing JSON
sudo apt install jq
echo "---------------------------------"
echo "Parameters"
echo "---------------------------------"
echo "Enviroment: ${ENVIRONMENT,,}"
echo "URL: ${URL}"
echo "Message ID: ${ID}"

# Checks queue URL input
if [ -z "${URL}" ]
then
    echo "Invalid input cannot process command!"
else
    echo "Processing message(s) in SQS queue..."
    messages_deleted=0
    # long-polling (specifying --wait-time-seconds greater than 0) of SQS does NOT guarantee that it will return all or even multiple messages in the queue, 
    # even if there *are* multiple messages in the queue and even if we *do* specify a --max-number-of-messages that is greater than 1
    # we can ONLY know that we've drained a queue once we get back an empty response from a long poll, hence the necessity of the while loop below
    sqs_response=$(aws sqs receive-message --queue-url ${URL} --message-attribute-names All --output json --visibility-timeout 300 --wait-time-seconds 1 --max-number-of-messages 10)
    while [ ! -z "$sqs_response" ]; do
        # bash for-loop will split when it encounters any whitespace, so first we encode each message as base64 as a hack around this;
        # inside the loop we can decode the base64-encoded JSON object
        for message in $(echo "${sqs_response}" | jq -r '.Messages[] | @base64'); do
            receipt_handle=$(echo $message | base64 --decode | jq -r '.ReceiptHandle')
            message_id=$(echo $message | base64 --decode | jq -r '.MessageId')
            if [ "$message_id" = "$ID" ]; then
                aws sqs delete-message --queue-url $URL --receipt-handle $receipt_handle
                echo "Deleted message with MessageId $message_id and with ReceiptHandle $receipt_handle"
                messages_deleted=$(( $messages_deleted + 1 ))
            fi
        done

        sqs_response=$(aws sqs receive-message --queue-url ${URL} --message-attribute-names All --output json --visibility-timeout 300 --wait-time-seconds 1 --max-number-of-messages 10)
    done

    echo "Deleted $messages_deleted message(s) from the queue"
fi