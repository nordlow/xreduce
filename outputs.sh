#!/bin/bash

# Check if correct number of arguments is provided
if [ "$#" -lt 2 ]; then
	echo "Usage: $0 OUTPUT CMD [ARG...]

To few arguments given."
  exit 1
fi

# Store the first argument as the expected output
EXPECTED_OUTPUT="$1"
shift # Shift all arguments left, so CMD becomes the new first argument

# Run CMD and capture its stdout and stderr
OUTPUT=$( "$@" 2>&1 )

# Check if OUTPUT contains the expected output string
if [[ "$OUTPUT" == *"$EXPECTED_OUTPUT"* ]]; then
  exit 0 # Success: the output contains the expected string
else
  exit 1 # Failure: the output doesn't match
fi
