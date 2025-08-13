#!/bin/sh
# Test script for syntax validation

test_function() {
    echo "This function is properly closed"
}

broken_function() {
    echo "This function is missing a closing brace"
# Missing closing brace here

if [ "1" = "1" ]; then
    echo "This if statement is properly closed"
fi

if [ "1" = "1" ]; then
    echo "This if statement is missing fi"
# Missing fi here

# This should be detected as a main function call
main() {
    echo "Hello world"
}
