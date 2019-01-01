# keef
A single-host, multi-datacenter capable implementation of the Hashicorp stack

Keef is primarily designed for use as a DevOps experimentation environment. While it could be used for local development, its overhead may be too much to handle significant Nomad deployments. If you are using it for local development, you will likely want to run single instances of the Consul and Nomad servers.

*Note: Currently multi-datacenter support for Vault and Traefik is not provided.*

---

## Requirements
- Ansible
- Vagrant
- `vagrant-hosts` Vagrant plugin
- VirtualBox

---

## Running

While the provided `Vagrantfile` is supplied a default Consul encryption key, you will want to likely want to produce your own using the `consul keygen` command. This value can be set with the `CONSUL_RAW_KEY` environment variable.

First you will need to install the necessary Ansible playbooks:
```bash
ansible-galaxy install -r requirements.yml
```

It is easiest to start the VirtualBox instance and provision them in separate steps, particularly due to the attention needed when installing Vault. To start the instances run:
```bash
vagrant up --no-provision
```

Then start the Consul agents on all instances:
```bash
vagrant provision --provision-with consul
```

Then start the Vault agent:
```bash
vagrant provision --provision-with vault
```

At this point, you will need to unseal Vault to continue:
```bash
vagrant ssh vault-{{datacenter}}

>> vault operator init
...key info printed here...
>> vault unseal
...enter unseal keys and repeat...
>> exit
```

Then start the Nomad agents on all instances:
```bash
vagrant provision --provision-with nomad
```

Then start the Traefik agent:
```bash
vagrant provision --provision-with traefik
```

---

## Configuration

By default, the Vagrantfile starts a cluster in the `arlington` datacenter with the following server distribution:
- 3 Consul servers
- 1 Vault server
- 3 Nomad servers
- 3 Nomad clients
- 1 Traefik server

This is defined by the default configuration file found [here](./examples/keef.yml). Until documentation for configuration syntax is provided, this file can serve as an example to allow you to construct your own network topologies. The `Vagrantfile` will load your configuration from `keef.yml` if it is available.

---

## Network Routing

Keef uses [Traefik](https://traefik.io/) to provide a proxy into the clustered Virtualbox environment. As such, one can utilize the proxy by setting the following tags on a service in Consul:
- traefik.backend={{ Service name in Consul }}
- traefik.frontend.rule={{ A Traefik [frontend rule set](https://docs.traefik.io/basics/#frontends) }}

A few of these are already implemented for the cluster components:
- Consul - http://consul.localhost
- Nomad - http://nomad.localhost
- Vault - http://vault.localhost

The Traefik setup will bind to priority ports by default but they can be overriden with environment variables:

|             | Port | Environment Variable |
|          -: | :--: | :------------------: |
| HTTP Proxy  | 80   | TRAEFIK_HTTP_PORT    |
| HTTPS Proxy | 443  | TRAEFIK_HTTPS_PORT   |
| Web UI      | 8080 | TRAEFIK_UI_PORT      |

---

## Contributing

It's best to open an issue first so to allow for discussion on how a feature may be implemented, but feel free to fork and make pull requests with your contributions!
