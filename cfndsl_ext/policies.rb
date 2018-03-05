class IAMPolicies

  def initialize(custom_policies = nil)
    @managed_policies = YAML.load(File.read("#{File.dirname(__FILE__)}/config/managed_policies.yaml"))
    @policy_array = Array.new
    @policies = (not custom_policies.nil?) ? @managed_policies.merge(custom_policies) : @managed_policies
  end

  def get_policies(group = nil)
    if group.kind_of?(Array)
      puts group
      create_policies(group)
    else
      create_policies(@config['default_policies']) if @config.key?('default_policies')
      create_policies(@config['group_policies'][group]) unless group.nil?
    end
    return @policy_array
  end

  def create_policies(policies)
    policies.each do |policy|
      raise "ERROR: #{policy} policy doesn't exist in the managed policies or as a custom policy" if !@policies.key?(policy)
      resource = (@policies[policy].key?('resource') ? gsub_yml(@policies[policy]['resource']) : ["*"])
      @policy_array << { PolicyName: policy, PolicyDocument: { Statement: [{ Effect: 'Allow', Action: @policies[policy]['action'], Resource: resource }] } }
    end
    return @policy_array
  end

  # replaces %{variables} in the yml
  def gsub_yml(resource)
    replaced = []
    resource.each { |r|
      if r.is_a? String
        replaced << r.gsub('%{source_bucket}', @config['source_bucket'])
      else
        replaced << r
      end
    }

    return replaced
  end

end
