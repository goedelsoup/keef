
def make_topology(datacenters, config)
    {
        'inventory' => make_inventory(datacenters, config),
        'host_map'  => make_host_map(datacenters, config)
    }
end

def make_inventory(datacenters, config)

    def provisioner_host_vars(h)
        {
            'ansible_host' => h['ansible_host'],
            'ansible_ssh_private_key_file' => h['ansible_ssh_private_key_file']
        }
    end

    def provisioner_group_vars(config)
        {
            'ansible_user' => 'vagrant',
            'ansible_ssh_extra_args' => '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null',
            'consul_raw_key' => config['consul_raw_key'],
        }
    end

    {
        'consul' => {
            'hosts' => get_hosts(datacenters, 'consul').map do |h|
                [h['inventory_name'], h['vars'].merge(provisioner_host_vars(h))]
            end.to_h,
            'vars'  => {
                'consul_install_dependencies' => false,
                'consul_dnsmasq_enable' => true,
                'consul_group_name' => 'consul',
                'consul_client_address' => '127.0.0.1',
                'consul_addresses' => {
                    'dns' => '0.0.0.0',
                    'http' => '0.0.0.0',
                    'https' => '0.0.0.0',
                    'rpc' => '0.0.0.0',
                    'grpc' => '0.0.0.0',
                },
                'consul_config_custom' => {
                    'telemetry' => {
                        'prometheus_retention_time' => '744h'
                    }
                }
            }.merge(provisioner_group_vars(config))
        },
        'vault' => {
            'hosts' => get_hosts(datacenters, 'vault').map do |h|
                [h['inventory_name'], h['vars'].merge(provisioner_host_vars(h))]
            end.to_h,
            'vars'  => {
                'vault_ui' => true,
                'vault_iface' => 'eth0',
                'vault_group_name' => 'vault',
                'vault_cluster_disable' => false,
                'vault_tls_disable' => true
            }.merge(provisioner_group_vars(config))
        },
        'nomad' => {
            'hosts' => get_hosts(datacenters, 'nomad').map do |h|
                [h['inventory_name'], h['vars'].merge(provisioner_host_vars(h))]
            end.to_h,
            'vars' => {
                'nomad_ports_http' => 4646,
                'nomad_ports_rpc'  => 4647,
                'nomad_ports_serf' => 4648,
                'nomad_use_consul' => true,
                'nomad_group_name' => 'nomad',
                'nomad_docker_enable' => true,
                'nomad_vault_enabled' => false,
                'nomad_vault_address' => 'vault.service.consul:8200',
                'nomad_network_interface' => 'eth1',
                'nomad_config_custom' => {
                    'telemetry' => {
                        'collection_interval' => '1s',
                        'disable_hostname' => true,
                        'prometheus_metrics' => true,
                        'publish_allocation_metrics' => true,
                        'publish_node_metrics' => true
                    }
                },
            }.merge(provisioner_group_vars(config))
        },
        'traefik' => {
            'hosts' => get_hosts(datacenters, 'traefik').map do |h|
                [h['inventory_name'], h['vars'].merge(provisioner_host_vars(h))]
            end.to_h,
            'vars'  => {
                # 'consul_address' => '0.0.0.0',
                'traefik_template' => './templates/traefik-consul.toml',
            }.merge(provisioner_group_vars(config))
        },
        'registry' => {
            'hosts' => get_hosts(datacenters, 'registry').map do |h|
                [h['inventory_name'], h['vars'].merge(provisioner_host_vars(h))]
            end.to_h,
            'vars'  => {}.merge(provisioner_group_vars(config))
        }
    }
end

def make_host_map(datacenters, config)
    consul = get_hosts(datacenters, 'consul').map do |h|
        [h['ip_addr'], h['host']]
    end
    vault = get_hosts(datacenters, 'vault').map do |h|
        [h['ip_addr'], h['host']]
    end
    nomad = get_hosts(datacenters, 'nomad').map do |h|
        [h['ip_addr'], h['host']]
    end
    traefik = get_hosts(datacenters, 'traefik').map do |h|
        [h['ip_addr'], h['host']]
    end
    registry = get_hosts(datacenters, 'registry').map do |h|
        [h['ip_addr'], h['host']]
    end

    consul.concat(vault).concat(nomad).concat(traefik).concat(registry).to_h
end

# def make_vm_cluster(datacenters, config)

# end

def get_hosts(datacenters, service)
    datacenters.map do |(datacenter_name, datacenter_config)|
        datacenter_config.map do |(service_name, service_config)|
            if is_valid_service_config(service_config)
                if service_config.key?('count')
                    (1..service_config['count']).map do |index|
                        make_service(service, datacenter_name, datacenter_config, service_name, service_config, index) 
                    end
                else
                    make_service(service, datacenter_name, datacenter_config, service_name, service_config, nil) 
                end
            end
        end.flatten
    end.flatten.compact
end

def is_valid_service_config(service_config)
    service_config.is_a?(Hash) && service_config.key?('cidr_segment') && service_config.key?('cidr_prefix')
end

def make_private_ip(base, service, index)
    if !(index == nil)
        "10.#{base}.#{service["cidr_segment"]}.#{service["cidr_prefix"]}#{index}"
    else
        "10.#{base}.#{service["cidr_segment"]}.#{service["cidr_prefix"]}1"
    end
end

def make_host_name(datacenter, service, index)
    if !(index == nil)
        "#{service}-#{index}.#{datacenter}.consul".gsub '_', '-'
    else
        "#{service}-1.#{datacenter}.consul".gsub '_', '-'
    end
end

def make_inventory_name(datacenter, service, index)
    if !(index == nil)
        "#{service}-#{datacenter}-#{index}".gsub '_', '-'
    else
        "#{service}-#{datacenter}".gsub '_', '-'
    end
end

def make_network(datacenter, datacenter_config, service, service_config, index)
    cidr_ii = datacenter_config['cidr_segment']
    {
        'hostname' => make_host_name(datacenter, service, index),
        'ip_address' => make_private_ip(cidr_ii, service_config, index),
        'inventory_name' => make_inventory_name(datacenter, service, index)
    }
end

def make_service(service, datacenter, datacenter_config, service_name, service_config, index)
    case service
    when "consul"
        make_consul_service(datacenter, datacenter_config, service_name, service_config, index)
    when "vault"
        make_vault_service(datacenter, datacenter_config, service_name, service_config, index)
    when "nomad"
        make_nomad_service(datacenter, datacenter_config, service_name, service_config, index)
    when "traefik"
        make_traefik_service(datacenter, datacenter_config, service_name, service_config, index)
    when "registry"
        make_registry_service(datacenter, datacenter_config, service_name, service_config, index)
    end
end

def is_consul_bootstrap(service, index)
    (service == 'consul' && index == 1)
end

def make_consul_service(datacenter, datacenter_config, service, service_config, index)

    network = make_network(datacenter, datacenter_config, service, service_config, index)
    
    def get_role(service, index)
        if is_consul_bootstrap(service, index)
            'bootstrap'
        elsif service == 'consul'
            'server'
        else
            'client'
        end
    end

    {
        "host" => network['hostname'],
        "ip_addr" => network['ip_address'],
        "inventory_name" => network['inventory_name'],

        "ansible_host" => network['ip_address'],
        "ansible_ssh_private_key_file" => "./.vagrant/machines/#{network['inventory_name']}/virtualbox/private_key",

        'vars' => {
            'consul_node_role' => get_role(service, index),
            'consul_datacenter' => datacenter,
            'consul_bind_address' => network['ip_address']
        }
    }
end

def make_vault_service(datacenter, datacenter_config, service, service_config, index)

    network = make_network(datacenter, datacenter_config, service, service_config, index)
    
    if (service == 'vault')
    {
        "host" => network['hostname'],
        "ip_addr" => network['ip_address'],
        "inventory_name" => network['inventory_name'],

        "ansible_host" => network['ip_address'],
        "ansible_ssh_private_key_file" => "./.vagrant/machines/#{network['inventory_name']}/virtualbox/private_key",

        "vars" => {
            "vault_cluster_name" => datacenter,
            "vault_datacenter" => datacenter,
            "vault_address" => network['ip_address'],
            "vault_cluster_address" => "{{ vault_address }}:{{ (vault_port | int) + 1 }}",
            "vault_cluster_addr" => "http://#{network['hostname']}:{{ (vault_port | int) + 1 }}",
            "vault_api_addr" => "http://#{network['hostname']}:{{ vault_port }}"
        }
    }
    elsif (is_consul_bootstrap(service, index) && !datacenter_config.key?('vault'))
    {
        "host" => network['hostname'],
        "ip_addr" => network['ip_address'],
        "inventory_name" => network['inventory_name'],

        "ansible_host" => network['ip_address'],
        "ansible_ssh_private_key_file" => "./.vagrant/machines/#{network['inventory_name']}/virtualbox/private_key",

        "vars" => {
            "vault_cluster_name" => datacenter,
            "vault_datacenter" => datacenter,
            "vault_address" => network['ip_address'],
            "vault_cluster_address" => "{{ vault_address }}:{{ (vault_port | int) + 1 }}",
            "vault_cluster_addr" => "http://#{network['hostname']}:{{ (vault_port | int) + 1 }}",
            "vault_api_addr" => "http://#{network['hostname']}:{{ vault_port }}"
        }
    }
    end
end

def make_nomad_service(datacenter, datacenter_config, service, service_config, index)

    network = make_network(datacenter, datacenter_config, service, service_config, index)
    
    bootstrap = {
        'role' => if service == 'nomad_server'
            'server'
        elsif service == 'nomad_client'
            'client'
        elsif (!datacenter_config.key?('nomad_server') && service == 'consul')
            if (!datacenter_config.key?('nomad_client'))
                'both'
            else
                'server'
            end
        end,
        'expect' =>  if (!datacenter_config.key?('nomad_server') && service == 'consul')
            datacenter_config['consul']['count']
        else
            '{{ nomad_servers | count }}'
        end
    }

    if !(bootstrap['role'] == nil) 
    {
        "host" => network['hostname'],
        "ip_addr" => network['ip_address'],
        "inventory_name" => network['inventory_name'],

        "ansible_host" => network['ip_address'],
        "ansible_ssh_private_key_file" => "./.vagrant/machines/#{network['inventory_name']}/virtualbox/private_key",

        "vars" => {
            "nomad_node_role" => bootstrap['role'],
            "nomad_bootstrap_expect" => bootstrap['expect'],
            "nomad_datacenter" => datacenter,
            "nomad_bind_address" => network['ip_address'],
            "nomad_advertise_address" => network['ip_address'],
        }
    }
    end
end

def make_traefik_service(datacenter, datacenter_config, service, service_config, index)

    network = make_network(datacenter, datacenter_config, service, service_config, index)
    
    if (service == 'traefik' || (is_consul_bootstrap(service, index) && !datacenter_config.key?('traefik')))
    {
        "host" => network['hostname'],
        "ip_addr" => network['ip_address'],
        "inventory_name" => network['inventory_name'],

        "ansible_host" => network['ip_address'],
        "ansible_ssh_private_key_file" => "./.vagrant/machines/#{network['inventory_name']}/virtualbox/private_key",

        "vars" => {
            'consul_address' => network['ip_address']
        }
    }
    end
end

def make_registry_service(datacenter, datacenter_config, service, service_config, index)

    network = make_network(datacenter, datacenter_config, service, service_config, index)
    
    if (service == 'registry' || (is_consul_bootstrap(service, index) && !datacenter_config.key?('registry')))
    {
        "host" => network['hostname'],
        "ip_addr" => network['ip_address'],
        "inventory_name" => network['inventory_name'],

        "ansible_host" => network['ip_address'],
        "ansible_ssh_private_key_file" => "./.vagrant/machines/#{network['inventory_name']}/virtualbox/private_key",

        "vars" => {}
    }
    end
end