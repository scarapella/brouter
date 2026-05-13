#!/bin/bash
set -e
cd "$(dirname "$0")"

OUTPUT_DIR=""
JAVA_ARGS=""
PLANET_FILE_ARG=""
AVOID_MAP_POLLING=false
SRTM_PATH="./srtm3_bef/"
TMP_BACKUP_DIR=""
DELETE_TMP_FILES=true


usage() {
  echo "" >&2
  echo "Usage: process_pbf_development.sh <planet-file> [options...]" >&2
  echo "--output-dir <directory>     Location to store the .rd5 segment files" >&2
  echo "--java-args <args>           Java arguments to pass to the Brouter processes">&2
  echo "--avoid-map-polling          Avoid polling of files, (necessary for small pbf files)">&2
  echo "--srtm-dir <directory>       Directory containing SRTM data" >&2
  echo "--tmp-backup-dir <directory> Used to store tmp files in a persistent place for resuming processing" >&2
  echo "--help                       Show this help message" >&2
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
    --tmp-backup-dir)
      if [[ -z "$2" || "$2" == --* ]]; then
        echo "Error: --tmp-backup-dir requires a directory path" >&2
        usage
        exit 1
      fi
      TMP_BACKUP_DIR="$2"
      shift 2
      ;;
    --tmp-backup-dir=*)
      TMP_BACKUP_DIR="${1#*=}"
      shift
      ;;
    --srtm-dir)
      if [[ -z "$2" || "$2" == --* ]]; then
        echo "Error: --srtm-dir requires a directory path" >&2
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
    --force-failure)
      FORCE_FAILURE=true
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



if [[ -z "$JAVA_ARGS" ]]; then
#  JAVA_ARGS='-Xmx6144M -Xms6144M -Xmn256M'
  #for now, no args is honestly better
  JAVA_ARGS=''
fi
JAVA="java $JAVA_ARGS"

BROUTER_PROFILES=$(realpath "../../profiles2")

BROUTER_JAR=$(realpath $(ls ../../../brouter-server/build/libs/brouter-*-all.jar) || true)
if [[ ! -f "$BROUTER_JAR" ]]; then 
    BROUTER_JAR=$(realpath /brouter.jar)
fi
if [[ ! -f "$BROUTER_JAR" ]];
	then echo "Error: Brouter jar file '$BROUTER_JAR' not found" >&2
    exit 1
fi
echo  "Using Brouter jar file '$BROUTER_JAR'"


# Setup checkpoint file
CHECKPOINT_FILE=".process_pbf_checkpoint"
TODAY=$(date +%Y-%m-%d)

# Convert TMP_BACKUP_DIR to absolute path if provided and scope by date
if [[ -n "$TMP_BACKUP_DIR" ]]; then
    TMP_BACKUP_DIR=$(realpath "$TMP_BACKUP_DIR")
    TMP_BACKUP_DIR_DATED="${TMP_BACKUP_DIR}/${TODAY}"
    mkdir -p "$TMP_BACKUP_DIR_DATED"
    echo "Using backup directory: $TMP_BACKUP_DIR_DATED"
fi

# Initialize or resume from checkpoint
if [[ ! -d tmp ]]; then
    mkdir tmp
fi

# If backup directory exists for today, restore from it first
if [[ -n "$TMP_BACKUP_DIR_DATED" && -d "$TMP_BACKUP_DIR_DATED" ]]; then
    echo "=== Found backup directory for ${TODAY}, restoring tmp data ==="
    rsync -a "$TMP_BACKUP_DIR_DATED/" tmp/
    echo "=== Restore complete ==="
fi

cd tmp

# Read checkpoint and validate date
CHECKPOINT_DATA=$(cat "../$CHECKPOINT_FILE" 2>/dev/null || echo "$TODAY 0")
CHECKPOINT_DATE=$(echo "$CHECKPOINT_DATA" | awk '{print $1}')
CHECKPOINT=$(echo "$CHECKPOINT_DATA" | awk '{print $2}')

# If checkpoint is from a different day, reset to 0
if [[ "$CHECKPOINT_DATE" != "$TODAY" ]]; then
    echo "=== Checkpoint from $CHECKPOINT_DATE is expired. Starting fresh. ==="
    CHECKPOINT=0
    echo "$TODAY 0" > "../$CHECKPOINT_FILE"
else
    echo "=== Resuming from checkpoint: step $CHECKPOINT ==="
fi

# Step 1: OsmFastCutter
if [[ "$CHECKPOINT" -lt 1 ]]; then
    echo "=== Running Step 1: OsmFastCutter ==="
    mkdir -p nodetiles waytiles waytiles55 nodes55

    ${JAVA} -cp ${BROUTER_JAR} -cp ${BROUTER_JAR} -Ddeletetmpfiles=${DELETE_TMP_FILES} -DuseDenseMaps=true -DavoidMapPolling=${AVOID_MAP_POLLING}  btools.util.StackSampler btools.mapcreator.OsmFastCutter ${BROUTER_PROFILES}/lookups.dat nodetiles waytiles nodes55 waytiles55  bordernids.dat  relations.dat  restrictions.dat  ${BROUTER_PROFILES}/all.brf ${BROUTER_PROFILES}/trekking.brf ${BROUTER_PROFILES}/softaccess.brf ${PLANET_FILE}

    # Backup tmp directory if TMP_BACKUP_DIR is set
    if [[ -n "$TMP_BACKUP_DIR_DATED" ]]; then
        echo "=== Backing up tmp directory to $TMP_BACKUP_DIR_DATED ==="
        rsync -a --delete ./ "$TMP_BACKUP_DIR_DATED/"
        echo "=== Backup complete ==="
    fi

    echo "$TODAY 1" > "../$CHECKPOINT_FILE"
    echo "=== Step 1 completed: OsmFastCutter ==="
    if [[ "$FORCE_FAILURE" == "true" ]]; then
        exit 1
    fi
else
    echo "=== Skipping Step 1: OsmFastCutter (already completed) ==="
fi

  # Step 2: PosUnifier
if [[ "$CHECKPOINT" -lt 2 ]]; then
    echo "=== Running Step 2: PosUnifier ==="
    mkdir -p unodes55

    ${JAVA} -cp ${BROUTER_JAR} -cp ${BROUTER_JAR} -Ddeletetmpfiles=${DELETE_TMP_FILES} -DuseDenseMaps=true -DavoidMapPolling=${AVOID_MAP_POLLING} btools.util.StackSampler btools.mapcreator.PosUnifier nodes55 unodes55 bordernids.dat bordernodes.dat ${SRTM_PATH}

    # Backup tmp directory if TMP_BACKUP_DIR is set
    if [[ -n "$TMP_BACKUP_DIR_DATED" ]]; then
        echo "=== Backing up tmp directory to $TMP_BACKUP_DIR_DATED ==="
        rsync -a --delete ./ "$TMP_BACKUP_DIR_DATED/"
        echo "=== Backup complete ==="
    fi

    echo "$TODAY 2" > "../$CHECKPOINT_FILE"
    echo "=== Step 2 completed: PosUnifier ==="
else
    echo "=== Skipping Step 2: PosUnifier (already completed) ==="
fi

# Step 3: WayLinker
if [[ "$CHECKPOINT" -lt 3 ]]; then
    echo "=== Running Step 3: WayLinker ==="
    mkdir -p segments

    ${JAVA} -cp ${BROUTER_JAR} -cp ${BROUTER_JAR} -DuseDenseMaps=true -DskipEncodingCheck=true btools.util.StackSampler btools.mapcreator.WayLinker unodes55 waytiles55 bordernodes.dat restrictions.dat ${BROUTER_PROFILES}/lookups.dat ${BROUTER_PROFILES}/all.brf segments rd5

    # Backup tmp directory if TMP_BACKUP_DIR is set
    if [[ -n "$TMP_BACKUP_DIR_DATED" ]]; then
        echo "=== Backing up tmp directory to $TMP_BACKUP_DIR_DATED ==="
        rsync -a --delete ./ "$TMP_BACKUP_DIR_DATED/"
        echo "=== Backup complete ==="
    fi

    echo "$TODAY 3" > "../$CHECKPOINT_FILE"
    echo "=== Step 3 completed: WayLinker ==="
else
    echo "=== Skipping Step 3: WayLinker (already completed) ==="
fi

echo "=== All processing steps completed ==="

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

# Clean up checkpoint file after successful completion
rm -f "$CHECKPOINT_FILE"

# Clean up backup directory if it was used
if [[ -n "$TMP_BACKUP_DIR_DATED" ]]; then
    echo "Cleaning up backup directory: $TMP_BACKUP_DIR_DATED"
    rm -rf "$TMP_BACKUP_DIR_DATED"
fi

echo "Process completed successfully."
