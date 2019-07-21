#!/bin/bash

. ./functions.sh

function monitor_resource() {
  declare -r RESOURCE="$1"
  declare -r DIRECTORY="$2"

  declare -A resource_versions

  watch_forever \
    | jq -c --unbuffered \
    | while read -r line; do
      obj="$line"

      # Set object information
      name="$(get_name "$obj")"
      spec="$(get_spec "$obj")"
      version="$(get_version "$obj")"
      old_manifest="$(get_manifest "$obj")"

      # Set status check information
      deleted="$(is_deleted "$line")"
      finalizer_added="$(is_finalizer_added "$line")"
      new_manifest="$(render_jsonnet "./$DIRECTORY/manifest.jsonnet")"

      # If the object is being deleted, then we need to purge the manifest
      # and then remove the finalizer
      if [[ "$deleted" == "true" && "$finalizer_added" == "true" ]]; then
        echo -e "[$RESOURCE] delete $name"

        # We reset the obj value here because removing the finalizer
        # will change the resourceVersion
        remove_manifest "$old_manifest" &>/dev/null
        obj="$(remove_finalizer "$obj")"
        version="$(get_version "$obj")"

        # Remove the resource version information from the associative array
        unset resource_versions[$name]
        fire_event_handlers "ondelete"
      elif [[ -z "${resource_versions[$name]}" && "$finalizer_added" == "false" ]]; then
        echo "[$RESOURCE] create $name"

        # Add the finalizer and update the resource version variable
        add_manifest "$new_manifest"
        obj="$(update_manifest "$new_manifest")"
        obj="$(add_finalizer)"
        version="$(get_version "$obj")"

        resource_versions[$name]="$version"
        fire_event_handlers "oncreate"
      elif [[ "${resource_versions[$name]}" != "$version" ]]; then
        echo "[$RESOURCE] change $name"

        # If the manifest is different, then delete the old manifest, apply the new one,
        # and update the manifest annotaition
        if [[ "$new_manifest" != "$old_manifest" ]]; then
          echo "[$RESOURCE] applying manifest for $name"
          echo -e "$new_manifest"

          remove_manifest "$old_manifest"
          add_manifest "$new_manifest"
          obj="$(update_manifest "$new_manifest")"
          version="$(get_version "$obj")"

          resource_versions[$name]="$version"
          fire_event_handlers "onchange"
        else
          echo "[$RESOURCE] $name manifest unchanged. skipping"
        fi
      fi
    done
}

if [[ -z "$CONTROLLER_NAME" ]]; then
  declare -r CONTROLLER_NAME="jsonnet-controller"
fi

jq -c '.[]' <watches.json | {
  while read -r obj; do
    RESOURCE="$(extract "$obj" '.resource')"
    DIRECTORY="$(extract "$obj" '.directory')"

    echo "Starting monitor for $RESOURCE using directory $DIRECTORY"
    monitor_resource "$RESOURCE" "$DIRECTORY" &
  done

  trap "echo Interrupted. Killing monitors; killall background" SIGINT
  wait
  echo "Exiting"
}
