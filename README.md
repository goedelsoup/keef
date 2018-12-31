# hashistak
A local implementation of the Hashicorp stack

*Note: Currently multi-datacenter support for Vault and Traefik is not provided.*

---

## Requirements
- Vagrant
- `vagrant-hosts` Vagrant plugin
- VirtualBox

---

## Running

While the provided `Vagrantfile` is supplied a default Consul encryption key, you will want to likely want to produce your own using the `consul keygen` command. This value can be set with the `CONSUL_RAW_KEY` environment variable.

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

This is defined by the default `datacenters.yml` file found [here](./default.yml). Until documentation for configuration syntax is provided, this file can serve as an example to allow you to construct your own network topologies.

---

## Contributing

It's best to open an issue first so to allow for discussion on how a feature may be implemented, but feel free to fork and make pull requests with your contributions!