require 'yaml'
require './lib/inventory.rb'

consul_raw_key = ENV['CONSUL_RAW_KEY'] || 'q1JhR11WqBR6tJegMUKK8g=='

traefik_http = ENV['TRAEFIK_HTTP_PORT'] || 80
traefik_https = ENV['TRAEFIK_HTTPS_PORT'] || 443
traefik_ui = ENV['TRAEFIK_UI_PORT'] || 8080

config = if File.file?('keef.yml')
    YAML.load(File.read('keef.yml'))
else
    YAML.load(File.read('examples/keef.yml'))
end

datacenters = config["datacenters"]

topology = make_topology(datacenters, {
    'consul_raw_key' => ENV['CONSUL_RAW_KEY'] || 'q1JhR11WqBR6tJegMUKK8g=='
})

inventory = topology['inventory']
host_map = topology['host_map']

# puts topology.to_yaml

File.open('./inventory.yml', 'w') { |file| file.write(inventory.to_yaml) }
File.open('./host_map.yml', 'w') { |file| file.write(host_map.to_yaml) }

def make_host_name(datacenter, service, index)
    "#{service}-#{index}.#{datacenter}.consul"
end

def make_private_ip(base, service, index)
    "10.#{base}.#{service["cidr_segment"]}.#{service["cidr_prefix"]}#{index}"
end

def add_all_hosts(config, host_map)
    config.vm.provision :hosts do |p|
        p.sync_hosts = false
        host_map.each do |(ip, host)|
            p.add_host ip, [host]
        end
    end
end

consul_group = []
vault_group = []
nomad_group = []
traefik_group = []
registry_group = []

host_map = {}

host_vars = {}

datacenters.each_with_index do |(datacenter, dc_config), index|
    # Add Consul servers
    (1..dc_config["consul"]["count"]).each do |consul_index|
        consul_host_id = "consul-#{datacenter}-#{consul_index}"
        consul_host = make_host_name(datacenter, "consul", consul_index)
        consul_ip = make_private_ip(dc_config["cidr_segment"], dc_config["consul"], consul_index)

        consul_group << consul_host_id
        host_map.merge! Hash[consul_ip, consul_host]

        consul_node_role = if consul_index == 1
            "bootstrap"
        else
            "server"
        end

        host_vars.merge! Hash[consul_host_id, {
            "consul_node_role" => consul_node_role,
            "consul_datacenter" => datacenter,
            "consul_install_dependencies" => false,
            "consul_bind_address" => consul_ip,
            "consul_dnsmasq_enable" => true,
            "consul_raw_key" => consul_raw_key
        }]

        # if no Nomad servers are defined, colocate them on the Consul servers
        if !dc_config.key?('nomad_server')
            host_vars[consul_host_id].merge!({
                "nomad_node_role" => "server",
                "nomad_datacenter" => datacenter,
                "nomad_use_consul" => true,
                "nomad_bind_address" => consul_ip,
                "nomad_advertise_address" => consul_ip,
                "nomad_consul_address" => "#{consul_ip}:8500",
                "nomad_vault_address" => make_host_name(datacenter, "vault", 1),
                "nomad_ports_http" => 4646,
                "nomad_ports_rpc" => 4647,
                "nomad_ports_serf" => 4648
            })
            nomad_group << consul_host_id
        end
    end

    # Add Vault
    if (dc_config.key?("vault"))
        vault_host_id = "vault-#{datacenter}"
        vault_host = make_host_name(datacenter, "vault", 1)
        vault_ip = make_private_ip(dc_config["cidr_segment"], dc_config["vault"], 1)

        consul_group << vault_host_id
        vault_group << vault_host_id
        host_map.merge! Hash[vault_ip, vault_host]

        host_vars.merge! Hash[vault_host_id, {
            "consul_node_role" => "client",
            "consul_datacenter" => datacenter,
            "consul_install_dependencies" => false,
            "consul_bind_address" => vault_ip,
            "consul_dnsmasq_enable" => true,
            "consul_raw_key" => consul_raw_key,

            "vault_cluster_name" => datacenter,
            "vault_datacenter" => datacenter,
            "vault_ui" => true,
            "vault_iface" => "eth0",
            "vault_address" => vault_ip,
            "vault_cluster_addr" => "http://#{vault_host}:{{ (vault_port | int) + 1 }}",
            "vault_api_addr" => "http://#{vault_host}:{{ vault_port }}"
        }]
    end

    if dc_config.key?('nomad_server')
        # Add Nomad servers
        (1..dc_config["nomad_server"]["count"]).each do |nomad_index|
            nomad_host_id = "nomad-#{datacenter}-#{nomad_index}"
            nomad_host = make_host_name(datacenter, "nomad", nomad_index)
            nomad_ip = make_private_ip(dc_config["cidr_segment"], dc_config["nomad_server"], nomad_index)

            consul_group << nomad_host_id
            nomad_group << nomad_host_id
            host_map.merge! Hash[nomad_ip, nomad_host]

            host_vars.merge! Hash[nomad_host_id, {
                "consul_node_role" => "client",
                "consul_datacenter" => datacenter,
                "consul_install_dependencies" => false,
                "consul_bind_address" => nomad_ip,
                "consul_dnsmasq_enable" => true,
                "consul_raw_key" => consul_raw_key,

                "nomad_node_role" => "server",
                "nomad_datacenter" => datacenter,
                "nomad_use_consul" => true,
                "nomad_bind_address" => nomad_ip,
                "nomad_advertise_address" => nomad_ip,
                "nomad_consul_address" => "#{nomad_ip}:8500",
                "nomad_vault_address" => make_host_name(datacenter, "vault", 1),
                "nomad_ports_http" => 4646,
                "nomad_ports_rpc" => 4647,
                "nomad_ports_serf" => 4648
            }]
        end
    end

    if dc_config.key?('nomad_client')
        # Add Nomad clients
        (1..dc_config["nomad_client"]["count"]).each do |nomad_index|
            nomad_host_id = "nomad-client-#{datacenter}-#{nomad_index}"
            nomad_host = make_host_name(datacenter, "nomad-client", nomad_index)
            nomad_ip = make_private_ip(dc_config["cidr_segment"], dc_config["nomad_client"], nomad_index)

            consul_group << nomad_host_id
            nomad_group << nomad_host_id
            host_map.merge! Hash[make_private_ip(dc_config["cidr_segment"], dc_config["nomad_client"], nomad_index), nomad_host]

            host_vars.merge! Hash[nomad_host_id, {
                "consul_node_role" => "client",
                "consul_datacenter" => datacenter,
                "consul_install_dependencies" => false,
                "consul_bind_address" => nomad_ip,
                "consul_dnsmasq_enable" => true,
                "consul_raw_key" => consul_raw_key,

                "nomad_node_role" => "client",
                "nomad_datacenter" => datacenter,
                "nomad_use_consul" => true,
                "nomad_bind_address" => nomad_ip,
                "nomad_advertise_address" => nomad_ip,
                "nomad_consul_address" => "#{nomad_ip}:8500",
                "nomad_vault_address" => make_host_name(datacenter, "vault", 1),
                "nomad_ports_http" => 4646,
                "nomad_ports_rpc" => 4647,
                "nomad_ports_serf" => 4648
            }]
        end
    end

    # Add Traefik
    if dc_config.key?("traefik")
        traefik_host_id = "traefik-#{datacenter}"
        traefik_host = make_host_name(datacenter, "traefik", 1)
        traefik_ip = make_private_ip(dc_config["cidr_segment"], dc_config["traefik"], 1)

        consul_group << traefik_host_id
        traefik_group << traefik_host_id
        host_map.merge! Hash[traefik_ip, traefik_host]

        host_vars.merge! Hash[traefik_host_id, {
            "consul_node_role" => "client",
            "consul_datacenter" => datacenter,
            "consul_install_dependencies" => false,
            "consul_bind_address" => traefik_ip,
            "consul_dnsmasq_enable" => true,
            "consul_raw_key" => consul_raw_key,
            
            "consul_address" => traefik_ip,
            "traefik_template" => "./templates/traefik-consul.toml"
        }]
    end

    # Add Docker registry
    if dc_config.key?("registry")
        registry_host_id = "registry-#{datacenter}"
        registry_host = make_host_name(datacenter, "registry", 1)
        registry_ip = make_private_ip(dc_config["cidr_segment"], dc_config["registry"], 1)

        consul_group << registry_host_id
        registry_group << registry_host_id
        host_map.merge! Hash[registry_ip, registry_host]

        host_vars.merge! Hash[registry_host_id, {
            "consul_node_role" => "client",
            "consul_datacenter" => datacenter,
            "consul_install_dependencies" => false,
            "consul_bind_address" => registry_ip,
            "consul_dnsmasq_enable" => true,
            "consul_raw_key" => consul_raw_key,
        }]
    end
end

# puts host_vars.to_yaml

Vagrant.configure("2") do |config|

    config.vm.provider "virtualbox" do |v|
        v.memory = 1500
        v.cpus = 2
    end

    # Loop all defined datacenters and provision a Hashicorp cluster
    datacenters.each_with_index do |(datacenter, dc_config), index|
        
        # Configure Consul server nodes
        (1..dc_config["consul"]["count"]).each do |consul_index|
            
            config.vm.define "consul-#{datacenter}-#{consul_index}" do |consul|
            private_ip = make_private_ip(dc_config["cidr_segment"], dc_config["consul"], consul_index)

            consul.vm.box = "centos/7"
            consul.vm.hostname = make_host_name(datacenter, "consul", consul_index)
            consul.vm.network "private_network", ip: private_ip

            if (!dc_config.key?("traefik") && consul_index == 1 && index == 1)
                consul.vm.network "forwarded_port", guest: 80, host: 80
                consul.vm.network "forwarded_port", guest: 8080, host: 8080
                consul.vm.network "forwarded_port", guest: 443, host: 443
            end

            add_all_hosts(consul, host_map)
            end
        end

        # Configure Vault
        if (dc_config.key?("vault"))

            config.vm.define "vault-#{datacenter}" do |vault|
            private_ip = make_private_ip(dc_config["cidr_segment"], dc_config["vault"], 1)

            vault.vm.box = "centos/7"
            vault.vm.hostname = make_host_name(datacenter, "vault", 1)
            vault.vm.network "private_network", ip: private_ip

            add_all_hosts(vault, host_map)
            end
        end

        # Configure Nomad server nodes
        if dc_config.key?('nomad_server')

            (1..dc_config["nomad_server"]["count"]).each do |nomad_index|

                config.vm.define "nomad-#{datacenter}-#{nomad_index}" do |nomad|
                private_ip = make_private_ip(dc_config["cidr_segment"], dc_config["nomad_server"], nomad_index)

                nomad.vm.box = "centos/7"
                nomad.vm.hostname = make_host_name(datacenter, "nomad", nomad_index)
                nomad.vm.network "private_network", ip: private_ip

                add_all_hosts(nomad, host_map)
                end
            end
        end

        # Configure Nomad client nodes
        if dc_config.key?('nomad_client')

            (1..dc_config["nomad_client"]["count"]).each do |nomad_index|

                config.vm.define "nomad-client-#{datacenter}-#{nomad_index}" do |nomad|
                private_ip = make_private_ip(dc_config["cidr_segment"], dc_config["nomad_client"], nomad_index)

                nomad.vm.box = "centos/7"
                nomad.vm.hostname = make_host_name(datacenter, "nomad-client", nomad_index)
                nomad.vm.network "private_network", ip: private_ip

                add_all_hosts(nomad, host_map)
                end
            end
        end

        # Configure Traefik
        if dc_config.key?("traefik")

            config.vm.define "traefik-#{datacenter}" do |traefik|
            private_ip = make_private_ip(dc_config["cidr_segment"], dc_config["traefik"], 1)

            traefik.vm.box = "centos/7"
            traefik.vm.hostname = make_host_name(datacenter, "traefik", 1)
            traefik.vm.network "private_network", ip: private_ip

            traefik.vm.network "forwarded_port", guest: 80, host: 80
            traefik.vm.network "forwarded_port", guest: 8080, host: 8080
            traefik.vm.network "forwarded_port", guest: 443, host: 443
            # traefik.vm.network "forwarded_port", guest: 53, host: 53, protocol: 'tcp'
            # traefik.vm.network "forwarded_port", guest: 53, host: 53, protocol: 'udp'

            add_all_hosts(traefik, host_map)
            end
        end

        # Configure Docker registry
        if dc_config.key?("registry")

            config.vm.define "registry-#{datacenter}" do |registry|
            private_ip = make_private_ip(dc_config["cidr_segment"], dc_config["registry"], 1)

            registry.vm.box = "centos/7"
            registry.vm.hostname = make_host_name(datacenter, "registry", 1)
            registry.vm.network "private_network", ip: private_ip
            
            add_all_hosts(registry, host_map)
            end
        end
    end
end