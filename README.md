# base.vm.windows

This repository contains the code used to build images containing the base operating system and tools
that are required by all Windows resources. Images can be created for Hyper-V.

## Image

### Contents

The current process will install Windows 2016 Server Core, i.e. without UI, on  the disk and will then
configure the following tools and services:

* [Consul](https://consul.io) - Provides service discovery for the environment as well as a distributed
  key-value store.
* [Consul-Template](https://github.com/hashicorp/consul-template) - Renders template files based on
  information stored in the `Consul` key-value store and the [Vault](https://vaultproject.io) secret
  store.
* [Filebeat](https://syslog-ng.org/) - Tails file logs and sends them onto the
  [central log storage server](https://github.com/Calvinverse/resource.documents.storage). The version
  of Filebeat installed is a [modified version](https://github.com/pvandervelde/filebeat.mqtt)
  that sends logs to a [message queue](https://github.com/Calvinverse/resource.queue).
* [Winlogbeat](https://www.elastic.co/guide/en/beats/winlogbeat/current/_winlogbeat_overview.html) -
  Tails the Windows event logs and sends them onto the
  [central log storage server](https://github.com/Calvinverse/resource.documents.storage). The version
  of Winlogbeat installed is a [modified version](https://github.com/pvandervelde/winlogbeat.mqtt)
  that sends logs to a [message queue](https://github.com/Calvinverse/resource.queue).
* [Telegraf](https://www.influxdata.com/time-series-platform/telegraf/) - Captures metrics for the
  resource and forwards them onto the [time series database](https://github.com/Calvinverse/resource.metrics.storage)
  for storage and processing.
* [Unbound](https://www.unbound.net/) - A local DNS resolver to allow resolving DNS requests via
  Consul for the environment specific requests and external DNS servers for all other requests.

### Configuration

* WinRM is enabled on the standard ports.
* The firewall is enabled and blocks all ports except the ports that are explicitly opened.
* All available updates will be applied.
* A single administrator level user is added called `thebigkahuna`.
* A set of standard applications are installed as mentioned above.
* Configurations for `Consul` and `Unbound` should be provided via the provisioning
  CD when a new machine is created from the base image. All other services and applications should
  obtain their configuration via `Consul-Template` and the `Consul` key-value store.

### Provisioning

For provisoning reasons a Windows service called `provisioning` is added which:

* Read the files on the DVD drive and:
  * Disable WinRM if the `allow_winrm.json` file does not exist
  * Copy the configuration files and certificates for consul and unbound
  * Enable all the Windows services for the afore mentioned services
  * Execute the resource specific provisioning steps found in the `Initialize-CustomResource` function
    in the `c:\ops\provisioning\Initialize-CustomResource.ps1` file.
* Sets the host name to `cv<SHORT_NAME>-<MAJOR><MINOR><PATCH>-<3_CHARACTER_RANDOM_STRING>` where
  * `<SHORT_NAME>` - Is a four character short version of the name of the resource
  * `<MAJOR>` - The major version number
  * `<MINOR>` - The minor version number
  * `<PATCH>` - The patch version number
  * `<3_CHARACTER_RANDOM_STRING>` - A random string of 3 characters
* Eject the DVD if the provisioning files were obtained from DVD
* Restart the machine to ensure that all changes are locked in and so that the machine comes up
  with the new machine name

Note that the Windows machine name is considerably shorter than the Linux machine name. This is due
to the fact that Windows machine names are NetBios compliant and thus can only be 15 characters in
length.

#### Consul config files

For Consul there are a number of configuration files that are expected in the provisioning location.
For server and client nodes they are:

* **consul/consul_region.json** - Contains the Consul datacenter and domain information
* **consul/consul_secrets.json** - Contains the [gossip encrypt](https://www.consul.io/docs/security/encryption#gossip-encryption) key
* **consul/client/consul_client_location.json** - Contains the configuration entries that tell Consul
  how to connect to the cluster

For examples on how to configure for Hyper-V please look at the configuration folder in the
[calvinverse.configuration](https://github.com/Calvinverse/calvinverse.configuration/tree/master/config/iso/shared/consul) repository.

#### Unbound config files

For Unbound one configuration file is expected. This file is expected to be found in the provisioning location at: `unbound/unbound_zones.conf` and it is expected to contain the unbound zone information.

For examples on how to configure for Hyper-V please look at the configuration folder in the
[calvinverse.configuration](https://github.com/Calvinverse/calvinverse.configuration/tree/master/config/iso/shared/unbound) repository.

### Logs

Logs are collected via the [Filebeat](https://github.com/pvandervelde/filebeat.mqtt)
and [Winlogbeat](https://github.com/pvandervelde/winlogbeat.mqtt) if the
Consul-Template service has been provided with the appropriate credentials to allow the logs to be
pushed to a RabbitMQ exchange. If no credentials are provided then no logs will be captured.

For file logs the exchange the log messages are pushed to is determined by the
Consul Key-Value key at `config/services/queue/logs/filelog/exchange` on the
[vhost](https://www.rabbitmq.com/vhosts.html) defined by the `config/services/queue/logs/filelog/vhost`
K-V key. The `filelog` routing key is applied to each log message.

For Windows event logs the exchange the log messages are pushed to is determined by the
Consul Key-Value key at `config/services/queue/logs/eventlog/exchange` on the
[vhost](https://www.rabbitmq.com/vhosts.html) defined by the `config/services/queue/logs/eventlog/vhost`
K-V key. The `filelog` routing key is applied to each log message.

### Metrics

Metrics are collected through different means.

* Metrics for Consul are collected by Consul sending [StatsD](https://www.consul.io/docs/agent/telemetry.html)
  metrics to [Telegraf](https://www.influxdata.com/time-series-platform/telegraf/).
* Metrics for Unbound are collected by Telegraf pulling the metrics.
* System metrics, e.g. CPU, disk, network and memory usage, are collected by Telegraf.

## Build, test and release

The build process follows the standard procedure for
[building Calvinverse images](https://www.calvinverse.net/documentation/how-to-build). Because the base
image is build during this process the following differences exist.

### Hyper-V images

* In order to build a Hyper-V image the following properties need to be specified as part of the
  command line used to build the image:
  * `ShouldCreateHyperVImage` should be set to `true`
  * The Windows Server ISO is obtained from the internal storage as defined by the MsBuild
    property `IsoDirectory`. It is expected that the ISO is called `windows_server_1803_updates.iso`.
    In order to reduce the amount of time needed to create the base image it is recommended to merge
    as many Windows update into the ISO prior to use.
* A number of additional scripts and configuration files have to be gathered. Amongst these files is
  the Windows `unattend.xml` file. The
  [unattend file](https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/update-windows-settings-and-scripts-create-your-own-answer-file-sxs)
  contains the OS configuration and it is provided to the machine when booting from the ISO initially.
* Once Packer has created the VM it will additionally
  * Add the OS ISO as a secondary DVD drive
  * Start the machine and provide the boot command which points the machine to the ISO and the location of the unattend
    file. The OS installation will start and during this process the unattend file is read leading the machine to be
    configured with
    * A US english culture
    * In the UTC timezone
    * A single administrator user called `thebigkahuna`
  * Once the OS is installed the standard process will be followed


## Deploy

The base image should never be deployed to live running infrastructure hence it will not be needing deploy information.
