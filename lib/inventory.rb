
def make_topology(datacenters, config)
    {
        'inventory' => make_inventory(datacenters, config),
        'port_map'  => make_port_map(datacenters, config)
    }
end

def make_inventory(datacenters, config)

    def defaults(h, config)
        {
            'ansible_host' => h['ansible_host'],
            'ansible_user' => 'vagrant',
            'ansible_ssh_private_key_file' => h['ansible_ssh_private_key_file'],
            'ansible_ssh_extra_args' => '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null',
            'consul_raw_key' => config['consul_raw_key']
        }
    end

    {
        'consul' => {
            'hosts' => get_hosts(datacenters, 'consul').map do |h|
                [h['inventory_name'], h['vars'].merge(defaults(h, config))]
            end.to_h,
            'vars'  => {
                'consul_install_dependencies' => false,
                'consul_dnsmasq_enable' => true,
                'consul_group_name' => 'consul',
            }
        },
        'vault' => {
            'hosts' => get_hosts(datacenters, 'vault').map do |h|
                [h['inventory_name'], h['vars'].merge(defaults(h, config))]
            end.to_h,
            'vars'  => {
                'vault_ui' => true,
                'vault_iface' => 'eth0',
                'vault_group_name' => 'vault',
            }
        },
        'nomad' => {
            'hosts' => get_hosts(datacenters, 'nomad').map do |h|
                [h['inventory_name'], h['vars'].merge(defaults(h, config))]
            end.to_h,
            'vars' => {
                'nomad_ports_http' => 4646,
                'nomad_ports_rpc'  => 4647,
                'nomad_ports_serf' => 4648,
                'nomad_use_consul' => true,
                'nomad_group_name' => 'nomad',
            }
        },
        'traefik' => {
            'hosts' => get_hosts(datacenters, 'traefik').map do |h|
                [h['inventory_name'], h['vars'].merge(defaults(h, config))]
            end.to_h,
            'vars'  => {
                'traefik_template' => './templates/traefik-consul.toml'
            }
        }
    }
end

def make_port_map(datacenters, config)
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

    consul.concat(vault).concat(nomad).concat(traefik).to_h
end

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
    "#{service}-#{index}.#{datacenter}.consul"
end

def make_inventory_name(datacenter, service, index)
    if !(index == nil)
        "#{service}-#{datacenter}-#{index}".gsub '_', '-'
    else
        "#{service}-#{datacenter}".gsub '_', '-'
    end
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
    end
end

def make_consul_service(datacenter, datacenter_config, service, service_config, index)

    cidr_ii = datacenter_config['cidr_segment']

    hostname = make_host_name(datacenter, service, index)
    ip_address = make_private_ip(cidr_ii, service_config, index)
    inventory_name = make_inventory_name(datacenter, service, index)
    
    def get_role(service, index)
        if service == 'consul'
            if index == 1
                'bootstrap'
            else
                'server'
            end
        else
            'client'
        end
    end

    {
        "host" => hostname,
        "ip_addr" => ip_address,
        "inventory_name" => inventory_name,

        "ansible_host" => ip_address,
        "ansible_ssh_private_key_file" => "./.vagrant/machines/#{inventory_name}/virtualbox/private_key",

        "vars" => {
            "consul_node_role" => get_role(service, index),
            "consul_datacenter" => datacenter,
            "consul_install_dependencies" => false,
            "consul_bind_address" => ip_address,
            "consul_dnsmasq_enable" => true,
            "consul_raw_key" => datacenter_config['consul_raw_key']
        }
    }
end

def make_vault_service(datacenter, datacenter_config, service, service_config, index)

    cidr_ii = datacenter_config["cidr_segment"]

    hostname = make_host_name(datacenter, service, index)
    ip_address = make_private_ip(cidr_ii, service_config, index)
    inventory_name = make_inventory_name(datacenter, service, index)
    
    if service == 'vault'
    {
        "host" => hostname,
        "ip_addr" => ip_address,
        "inventory_name" => inventory_name,

        "ansible_host" => ip_address,
        "ansible_ssh_private_key_file" => "./.vagrant/machines/#{inventory_name}/virtualbox/private_key",

        "vars" => {
            "vault_cluster_name" => datacenter,
            "vault_datacenter" => datacenter,
            "vault_address" => ip_address,
            "vault_cluster_addr" => "http://#{hostname}:{{ (vault_port | int) + 1 }}",
            "vault_api_addr" => "http://#{hostname}:{{ vault_port }}"
        }
    }
    end
end

def make_nomad_service(datacenter, datacenter_config, service, service_config, index)

    cidr_ii = datacenter_config["cidr_segment"]

    hostname = make_host_name(datacenter, service, index)
    ip_address = make_private_ip(cidr_ii, service_config, index)
    inventory_name = make_inventory_name(datacenter, service, index)

    
    nomad_role = if service == 'nomad_server'
        'server'
    elsif service == 'nomad_client'
        'client'
    elsif (!datacenter_config.key?('nomad_server') && service == 'consul')
        'server'
    end

    if !(nomad_role == nil) 
    {
        "host" => hostname,
        "ip_addr" => ip_address,
        "inventory_name" => inventory_name,

        "ansible_host" => ip_address,
        "ansible_ssh_private_key_file" => "./.vagrant/machines/#{inventory_name}/virtualbox/private_key",

        "vars" => {
            "nomad_node_role" => nomad_role,
            "nomad_datacenter" => datacenter,
            "nomad_bind_address" => ip_address,
            "nomad_advertise_address" => ip_address,
            "nomad_consul_address" => "#{ip_address}:8500",
            "nomad_vault_address" => make_host_name(datacenter, 'vault', 1)
        }
    }
    end
end

def make_traefik_service(datacenter, datacenter_config, service, service_config, index)

    cidr_ii = datacenter_config["cidr_segment"]

    hostname = make_host_name(datacenter, service, index)
    ip_address = make_private_ip(cidr_ii, service_config, index)
    inventory_name = make_inventory_name(datacenter, service, index)
    
    if service == 'traefik'
    {
        "host" => hostname,
        "ip_addr" => ip_address,
        "inventory_name" => inventory_name,

        "ansible_host" => ip_address,
        "ansible_ssh_private_key_file" => "./.vagrant/machines/#{inventory_name}/virtualbox/private_key",

        "vars" => {
            "consul_address" => ip_address
        }
    }
    end
end