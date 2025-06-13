#!/bin/bash

setup() {
    DIR=${REC_DIR:-$HOME/recordings}
    UNCONVERTED=()
    while IFS= read -r -d '' file; do
        if [ ! -f "${file}.m4v" ]; then
            UNCONVERTED+=("$file")
        fi
    done < <(find "$DIR" -type f ! -name "*.m4v" -print0)
}

convert() {
    count=0
    for FILE in "${UNCONVERTED[@]}"; do
        SIZE=$(awk -F';' '/size/ {gsub("[[:digit:]].size,[[:digit:]].[[:digit:]],?[[:digit:]].","",$1); gsub(",[[:digit:]].","x",$1); print $1}' "${FILE}")
        if [[ "${SIZE}" == "0x0" ]]; then SIZE="1280x720"; fi

        if [[ "${PARALLEL}" == "true" ]]; then
            /usr/local/bin/guacenc -s "${SIZE}" "${FILE}" &

            count=$((count + 1))
            if (( count % CONCURRENT_LIMIT == 0 )); then
                wait
            fi
        else
            /usr/local/bin/guacenc -s "${SIZE}" "${FILE}"
        fi
    done
    wait
}

s3sync () {
    aws s3 sync ${DIR}/ s3://${BUCKET}/ --exclude "*" --include "*.m4v"
}

main() {
    CONCURRENT_LIMIT=${CONCURRENT_LIMIT:-4}
    if [[ "${AUTOCONVERT}" == "true" ]]; then
        setup "$@"
        convert
        s3sync
    fi
    sleep ${AUTOCONVERT_WAIT:-15}
    main "$@"
}

main "$@"