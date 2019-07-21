#!/bin/bash

# Utility functions

function pipe() {
  printf '%s' "$1"
}

function extract() {
  local input="$1"
  shift
  pipe "$input" | jq -r "$@"
}

function watch_forever() {
  while :; do
    kubectl get "$RESOURCE" -o json --watch
  done
}

# Accessors

function get_obj() {
  pipe "$1" | jq \
    '(
      .metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"]
      | fromjson
      | .apiVersion
    ) as $apiVersion
    | .apiVersion = $apiVersion'
}

function get_name() {
  extract "$1" '.metadata.name'
}

function get_spec() {
  extract "$1" '.spec'
}

function get_version() {
  extract "$1" '.metadata.resourceVersion'
}

function get_manifest() {
  extract "$1" '.metadata.annotations.jsonnetManifest'
}

function is_deleted() {
  extract "$1" '.metadata.deletionTimestamp != null'
}

function is_finalizer_added() {
  pipe "$1" \
    | jq \
      --arg controller "$CONTROLLER_NAME" \
      '.metadata.finalizers // [] | contains([$controller])'
}

# Templating

function render_jsonnet() {
  local file="$1"

  jsonnet -y \
    -J lib \
    -J "$DIRECTORY" \
    --ext-str "name=$name" \
    --ext-str "spec=$spec" \
    "$file"
}

function fire_event_handlers() {
  for f in $(find "$DIRECTORY/$1" -name "*.jsonnet"); do
    echo -e "[$RESOURCE]: $1: applying $f"
    render_jsonnet "$f" | kubectl create -f -
  done
}

# Modify object

function remove_manifest() {
  pipe "$1" | kubectl delete -f -
}

function remove_finalizer() {
  kubectl patch \
    "$RESOURCE" "$name" \
    --type json \
    --patch "$(
      pipe "$1" \
        | jq -c \
          --arg controller "$CONTROLLER_NAME" \
          '.metadata.finalizers
          | index($controller)
          | if . != null then
            [{op: "remove", path: "/metadata/finalizers/\(.)"}]
          else
            []
          end'
    )" \
    -o json
}

function add_manifest() {
  pipe "$1" | kubectl apply -f - -o json
}

function update_manifest() {
  kubectl patch \
    "$RESOURCE" "$name" \
    --type json \
    --patch "$(
      jq -c -n \
        --arg manifest "$1" \
        '[{
            op: "add",
            path: "/metadata/annotations/jsonnetManifest",
            value: $manifest
          }]'
    )" \
    -o json
}

function add_finalizer() {
  kubectl patch \
    "$RESOURCE" "$name" \
    --type json \
    --patch "$(
      jq -c -n \
        --arg controller "$CONTROLLER_NAME" \
        '[
            {op: "add", path: "/metadata/finalizers", value: []},
            {op: "add", path: "/metadata/finalizers/0", value: $controller}
        ]'
    )" \
    -o json
}
