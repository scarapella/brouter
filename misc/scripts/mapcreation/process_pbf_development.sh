#!/bin/bash
set -e
cd "$(dirname "$0")"

OUTPUT_DIR=""
JAVA_ARGS=""
PLANET_FILE_ARG=""
AVOID_MAP_POLLING=false
SRTM_PATH="./srtm3_bef/"

usage() {
  echo "Usage: ./process_pbf_development.sh [--output-dir <directory>] [--java-args <args>] [--avoid-map-polling] [--srtm-dir <directory>] <planet-file>" >&2
  echo "       ./process_pbf_development.sh --output-dir ../../segments4/ --java-args '-Xmx8G -Xms4G' --avoid-map-polling --srtm-dir ../../srtm_bef3/ planet-latest.osm.pbf" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      if [[ -z "$2" || "$2" == --* ]]; then
        echo "Error: --output-dir requires a directory path" >&2
        usage
        exit 1
      fi
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --output-dir=*)
      OUTPUT_DIR="${1#*=}"
      shift
      ;;
    --srtm-dir)
      if [[ -z "$2" || "$2" == --* ]]; then
        echo "Error: --bef-dir requires a directory path" >&2
        usage
        exit 1
      fi
      SRTM_PATH="$2"
      shift 2
      ;;
    --srtm-dir=*)
      SRTM_PATH="${1#*=}"
      shift
      ;;
    --java-args)
      if [[ -z "$2" || "$2" == --* ]]; then
        echo "Error: --java-args requires Java arguments" >&2
        usage
        exit 1
      fi
      JAVA_ARGS="$2"
      shift 2
      ;;
    --java-args=*)
      JAVA_ARGS="${1#*=}"
      shift
      ;;
    --avoid-map-polling)
      AVOID_MAP_POLLING=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$PLANET_FILE_ARG" ]]; then
        PLANET_FILE_ARG="$1"
        shift
      else
        echo "Error: unexpected argument '$1'" >&2
        usage
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$PLANET_FILE_ARG" ]]; then
  echo "Error: planet file path required" >&2
  usage
  exit 1
fi

SRTM_PATH=$(realpath "$SRTM_PATH")
PLANET_FILE=$(realpath "./$PLANET_FILE_ARG")

if [[ ! -f "$PLANET_FILE" ]];
	then echo "Error: planet file '$PLANET_FILE' not found" >&2
	exit 1
fi

DELETE_TMP_FILES=true
FORCE_GENERATE=true
DEBUG=false
set -x


#if debug is set to true then enable bash debug mode
if [ "$DEBUG" == "true" ]; then
    set -x
    FORCE_GENERATE=true
    DELETE_TMP_FILES=false
    RECURSE_FILES_CMD="ls -lR"

fi

# Fetch OSM planet dump if no planet file is specified
# if [ -z "$PLANET_FILE" ]; then
#     echo "Fetching OSM planet dump"
#     if [ -x "$(command -v osmupdate)" ] && [[ -f "./planet-latest.osm.pbf" ]]; then
#         # Prefer running osmupdate to update the planet file if available
#         mv "./planet-latest.osm.pbf" "./planet-latest.old.osm.pbf"
#         osmupdate "planet-latest.old.osm.pbf" "./planet-latest.osm.pbf"
#         rm "./planet-latest.old.osm.pbf"
#     else
#         # Otherwise, download it again
#         wget -N http://planet.openstreetmap.org/pbf/planet-latest.osm.pbf
#     fi
# fi

# if [ "$FORCE_GENERATE" != "true" ]; then
#     if test lastmaprun.date -nt planet-latest.osm.pbf; then
#     echo "no osm update, exiting"
#     exit 0
#     fi
# fi
# touch lastmaprun.date

#rm -rf /var/www/brouter/segments4_lastrun

if [[ -z "$JAVA_ARGS" ]]; then
#  JAVA_ARGS='-Xmx6144M -Xms6144M -Xmn256M'
  #for now, no args is honestly better
  JAVA_ARGS=''
fi
JAVA="java $JAVA_ARGS"

BROUTER_PROFILES=$(realpath "../../profiles2")

BROUTER_JAR=$(realpath $(ls ../../../brouter-server/build/libs/brouter-*-all.jar) || true)
if [[ ! -f "$BROUTER_JAR" ]];
	then echo "Error: Brouter jar file '$BROUTER_JAR' not found" >&2
    BROUTER_JAR=$(realpath /brouter.jar)
fi
if [[ ! -f "$BROUTER_JAR" ]];
	then echo "Error: Brouter jar file '$BROUTER_JAR' not found" >&2
    exit 1
fi
echo  "Using Brouter jar file '$BROUTER_JAR'"

#PLANET_FILE=${PLANET_FILE:-$(realpath "./planet-latest.osm.pbf")}

# Download SRTM zip files from
# https://cgiarcsi.community/data/srtm-90m-digital-elevation-database-v4-1/
# (use the "ArcInfo ASCII" version) and put the ZIP files directly in this
# folder:
#SRTM_PATH=$(realpath "./srtm3_bef/")

rm -rf tmp
mkdir tmp
cd tmp
mkdir nodetiles
mkdir waytiles
mkdir waytiles55
mkdir nodes55

${JAVA} -cp ${BROUTER_JAR} -cp ${BROUTER_JAR} -Ddeletetmpfiles=${DELETE_TMP_FILES} -DuseDenseMaps=true -DavoidMapPolling=${AVOID_MAP_POLLING}  btools.util.StackSampler btools.mapcreator.OsmFastCutter ${BROUTER_PROFILES}/lookups.dat nodetiles waytiles nodes55 waytiles55  bordernids.dat  relations.dat  restrictions.dat  ${BROUTER_PROFILES}/all.brf ${BROUTER_PROFILES}/trekking.brf ${BROUTER_PROFILES}/softaccess.brf ${PLANET_FILE}
$RECURSE_FILES_CMD  || true

mkdir unodes55
${JAVA} -cp ${BROUTER_JAR} -cp ${BROUTER_JAR} -Ddeletetmpfiles=${DELETE_TMP_FILES} -DuseDenseMaps=true -DavoidMapPolling=${AVOID_MAP_POLLING} btools.util.StackSampler btools.mapcreator.PosUnifier nodes55 unodes55 bordernids.dat bordernodes.dat ${SRTM_PATH}
$RECURSE_FILES_CMD  || true

mkdir segments
${JAVA} -cp ${BROUTER_JAR} -cp ${BROUTER_JAR} -DuseDenseMaps=true -DskipEncodingCheck=true btools.util.StackSampler btools.mapcreator.WayLinker unodes55 waytiles55 bordernodes.dat restrictions.dat ${BROUTER_PROFILES}/lookups.dat ${BROUTER_PROFILES}/all.brf segments rd5
$RECURSE_FILES_CMD  || true

cd ..

if [[ -n "$OUTPUT_DIR" ]]; then
  echo "Copying segments to $OUTPUT_DIR"
  mkdir -p "$OUTPUT_DIR" || {
    echo "Error: failed to create output directory $OUTPUT_DIR" >&2
    exit 1
  }
  cp ./tmp/segments/* "$OUTPUT_DIR/" || {
    echo "Error: failed to copy segments to $OUTPUT_DIR" >&2
    exit 1
  }
fi

#rm -rf segments
#mv tmp/segments segments
#cp /var/www/brouter/segments4/.htaccess segments
#cp /var/www/brouter/segments4/storageconfig.txt segments
#mv /var/www/brouter/segments4 /var/www/brouter/segments4_lastrun
#mv segments /var/www/brouter/segments4
#rm -rf tmp
