#!/bin/bash
set -x
gcloud run deploy brouter --region=northamerica-northeast2 --image=northamerica-northeast2-docker.pkg.dev/paddle-map/paddle-map/brouter:latest
