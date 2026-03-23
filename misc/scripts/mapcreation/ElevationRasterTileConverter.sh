#!/bin/bash
set -e
cd "$(dirname "$0")"

JAVA='java -Xmx6144M -Xms6144M -Xmn256M'

BROUTER_PROFILES=$(realpath "../../profiles2")

BROUTER_JAR=$(realpath $(ls ../../../brouter-server/build/libs/brouter-*-all.jar))
#pass all parameters to ElevationRasterTileConverter
${JAVA} -cp ${BROUTER_JAR} -cp ${BROUTER_JAR} btools.mapcreator.ElevationRasterTileConverter $@
