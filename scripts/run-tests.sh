#!/bin/sh
set -e

echo "Running unit tests"
go test ./...
