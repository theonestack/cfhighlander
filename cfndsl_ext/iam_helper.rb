def service_role_assume_policy(services)

  services = (services.kind_of?(Array) ? services : [services])
  statement = []

  services.each do |service|
    unless service.end_with? '.amazonaws.com'
      service = "#{service}.amazonaws.com"
    end
    statement << { Effect: 'Allow', Principal: { Service: "#{service}" }, Action: 'sts:AssumeRole' }
  end
  return {
      Version: '2012-10-17',
      Statement: statement
  }
end


def iam_policy_allow(name, actions, resource='*')

  return {
      PolicyName: name,
      PolicyDocument: {
          Statement: [{
              Sid: name.gsub('_', '').gsub('-', '').downcase,
              Action: actions,
              Resource: resource,
              Effect: 'Allow'
          }]
      }
  }
end

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
      resource = (@policies[policy].key?('resource') ? (@policies[policy]['resource']) : ["*"])
      @policy_array << { PolicyName: policy, PolicyDocument: { Statement: [{ Effect: 'Allow', Action: @policies[policy]['action'], Resource: resource }] } }
    end
    return @policy_array
  end

end
