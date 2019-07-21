#!/bin/bash

. ./functions.sh

function monitor_resource() {
  declare -r RESOURCE="$1"
  declare -r DIRECTORY="$2"

  declare -A resource_versions

  kubectl get "$RESOURCE" -o json --watch \
    | jq -c --unbuffered \
    | while read -r line; do
      #   obj="$(get_obj "$line")"
      obj="$line"

      # echo "$obj" | jq '.'

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
      if [[ "$deleted" == "true" ]]; then
        echo -e "Handling delete for $RESOURCE/$name"

        # We reset the obj value here because removing the finalizer will change the resourceVersion
        remove_manifest "$old_manifest"
        echo "Removing finalizer"
        obj="$(remove_finalizer "$obj")"
        version="$(get_version "$obj")"
        echo "$obj" | jq

        # Remove the resource version information from the associative array
        unset resource_versions[$name]
        old_manifest=""
        new_manifest=""

        fire_event_handlers "ondelete"
      elif [[ -z "${resource_versions[$name]}" && "$finalizer_added" == "false" ]]; then
        echo "Handling create for $RESOURCE/$name"

        # Add the finalizer and update the resource version variable
        obj="$(add_finalizer)"
        version="$(get_version "$obj")"

        resource_versions[$name]="$version"
        fire_event_handlers "oncreate"
      elif [[ "${resource_versions[$name]}" != "$version" ]]; then
        echo "Handling modify for $RESOURCE/$name"

        resource_versions[$name]="$version"
        fire_event_handlers "onchange"
      fi

      # If the manifest is different, then delete the old manifest, apply the new one,
      # and update the manifest annotaition
      if [[ "$new_manifest" != "$old_manifest" ]]; then
        echo "Applying manifest"
        echo -e "$new_manifest"

        remove_manifest "$old_manifest"
        add_manifest "$new_manifest"
        obj="$(update_manifest "$new_manifest")"
        version="$(get_version "$obj")"

        resource_versions[$name]="$version"
      fi

      echo "Done"
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
    while [[ 1 ]]; do
      monitor_resource "$RESOURCE" "$DIRECTORY"
    done &
  done

  wait
  echo "Exiting"
}
