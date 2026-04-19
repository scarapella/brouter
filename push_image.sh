#!/bin/bash
set -x
podman tag brouter:latest northamerica-northeast2-docker.pkg.dev/paddle-map/paddle-map/brouter:latest
podman push northamerica-northeast2-docker.pkg.dev/paddle-map/paddle-map/brouter:latest
