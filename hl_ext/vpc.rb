def subnet_parameters(subnets, maximum_availability_zones)
  subnets.each { |subnet_name, subnet_config|
    # Account mappings for AZs
    maximum_availability_zones.times do |x|

      # Request output from other component as input
      # to this component
      OutputParam component: 'vpc', name: "Subnet#{subnet_config['name']}#{x}"

    end
  }
end