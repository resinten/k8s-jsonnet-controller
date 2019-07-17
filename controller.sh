#!/bin/bash

function pipe() {
    printf '%s' "$1"
}

function extract() {
    local input="$1"
    shift
    pipe "$input" | jq -r "$@"
}

function monitor_resource() {
    local resource="$1"
    local directory="$2"

    declare -A resource_versions

    kubectl get "$resource" -o json --watch |
        jq -c --unbuffered |
        while read -r line; do
            local name="$(extract "$line" '.metadata.name')"
            local spec="$(extract "$line" '.spec')"
            local version="$(extract "$line" '.metadata.resourceVersion')"
            local deleted="$(extract "$line" '.metadata.deletionTimestamp != null')"

            local old_manifest="$(extract "$line" '.metadata.annotations.jsonnetManifest')"
            local manifest="$(
                jsonnet -y \
                    -J lib \
                    -J "$directory" \
                    --ext-str "name=$name" \
                    --ext-str "spec=$spec" \
                    "./$directory/manifest.jsonnet"
            )"

            echo -e "$manifest"

            local event=""

            if [[ "$deleted" == "true" ]]; then
                echo -e "Handling delete for $resource/$name"
                pipe "$old_manifest" | kubectl delete -f -
                event="ondelete"
                unset resource_versions[$name]
            else
                if [[ -z "${resource_versions[$name]}" ]]; then
                    echo "Handling create for $resource/$name"
                    event="oncreate"
                elif [[ "${resource_versions[$name]}" != "$version" ]]; then
                    echo "Modified resource $resource/$name"
                    event="onchange"
                fi

                if [[ "$manifest" != "$old_manifest" ]]; then
                    pipe "$manifest" | kubectl apply -f -
                    pipe "$line" |
                        jq \
                            --arg manifest "$manifest" \
                            '.metadata.annotations.jsonnetManifest |= $manifest' |
                        kubectl apply -f -
                fi

                resource_versions[$name]="$version"
            fi

            if [[ ! -z "$event" ]]; then
                for f in $(find "$directory/$event" -name "*.jsonnet"); do
                    echo -e "$event: Executing $f"
                    jsonnet -y \
                        -J lib \
                        -J "$directory" \
                        --ext-str "name=$name" \
                        --ext-str "spec=$spec" \
                        "$f" |
                        kubectl apply -f -
                done
            fi
        done
}

jq -c '.[]' <watches.json | {
    while read -r line; do
        resource="$(extract "$line" '.resource')"
        directory="$(extract "$line" '.directory')"

        echo "Starting monitor for $resource using directory $directory"
        monitor_resource "$resource" "$directory" &
    done

    wait
    echo "Exiting"
}
