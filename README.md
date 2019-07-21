# Kubernetes Jsonnet Controller

This controller lets you use Jsonnet to template your custom resources.
It also provides an event handler system for create, modify, and delete events
on your custom resources. These handlers are also Jsonnet templates, but they
are intended to be short-lived resources, such as `Job`s that run a maintenance script
to update metrics, send emails, notify a code repository, etc. whenever a custom
resource is modified in your cluster.

Create a `watches.json` file with something like so

```
[
  {
    "resource": "mycustomresource",
    "directory": "mycustomresource-dir"
  }
]
```

and create a directory named `mycustomresource-dir`. Inside it, create a `manifest.jsonnet`
file that returns an array of objects (to be compatible with Jsonnet's YAML output).
This will be executed to determine the manifest of resources the cluster should create for
your custom resource. It will be given two external variables: `name` and `spec`. `name` is
the string name in `.metadata.spec` on the custom resource. `spec` is the JSON-encoded `.spec`
data on the custom resource. Its values can be obtained with

```
local spec = std.parseJson(std.extVar('spec'));
```

Add any number of `*.jsonnet` files to `oncreate`, `onchange`, and `ondelete` directories placed
in `mycustomresource-dir`. These will be templated and passed to `kubectl apply`. If performing
jobs in this fashion, it is recommended that you use the `ObjectMeta` `generateName` feature to
avoid name conflicts when jobs are run multiple times, particularly for `onchange` events.

An example directory structure might look something like

```
.
├── Dockerfile
├── README.md
├── controller.sh
├── functions.sh
├── lib
├── mycustomresource
│   ├── manifest.jsonnet
│   ├── onchange
│   ├── oncreate
│   │   └── create-job.jsonnet
│   └── ondelete
└── watches.json
```

If you are using Docker, you can use the `bmwest/k8s-jsonnet-controller` image as a base with

```
FROM bmwest/k8s-jsonnet-controller:latest

COPY watches.yaml .
COPY mycustomresource ./mycustomresource
```

This project is a work in progress. If you encounter any issues, please report them on GitHub.
