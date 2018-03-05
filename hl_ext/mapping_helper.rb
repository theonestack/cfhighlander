require_relative '../lib/highlander.mapproviders'

# Return mapping provider as class
def mappings_provider(provider_name)
  return nil if provider_name.nil?
  provider = nil
  providers = Object.const_get('Highlander').const_get('MapProviders')
  begin
    providers.const_get(provider_name)
  rescue NameError => e
    if e.to_s.include? 'uninitialized constant Highlander::MapProviders::'
      return nil
    end
    STDERR.puts(e.to_s)
    raise e
  end
end

# Return all of the maps from mapping provider
def mappings_provider_maps(provider_name, config)
  provider = mappings_provider(provider_name)

  if provider.nil?
    STDERR.puts("Can't find mapping provider #{provider_name} and it's maps")
    return nil
  else
    return provider.getMaps(config)
  end
end

# Renders CloudFormation function for retrieving Mapping value. If key name and map name are not given,
# extraction from mapping provider will be tried
def mapping_value(component:, provider_name:, value_name:, key_name: nil)

  provider = nil

  # if key name is nil, provider must provide key
  if key_name.nil?
    provider = mappings_provider(provider_name)
    if provider.nil?
      STDERR.puts("Error: mapping provider #{provider_name} not found, can't render value of #{value_name} attribute")
      exit 240
    end
    unless provider.respond_to? 'getDefaultKey'
      STDERR.puts("Error: #{provider} does not implement getDefaultKey. Can't render value of #{value_name} attribtue")
      exit 241
    end

    key_name = provider.getDefaultKey
  end

  # Map name defaults to provider name. If provider exists and implements getMapName
  # map name will be dynamically resolved via this method
  map_name = provider_name

  provider = mappings_provider(provider_name) if provider.nil?
  unless provider.nil?
    if provider.respond_to? 'getMapName'
      map_name = provider.getMapName
    end
  end

  # there is no provider
  # and map name is not a reference
  if((provider.nil?) and (not map_name.start_with? 'Ref('))
    # check if mapping exists on component
    unless ((component.config['mappings'].key? map_name))
      STDERR.puts("Could not resolve mapping value: MapName=#{map_name},Key=#{key_name},Attribute=#{value_name}")
      exit 242
    end
  end

  # both map name and key name could be predefined via intrinsic functions
  if map_name.class == Hash
    map_name = map_name.to_s
  elsif( not map_name.include? 'Ref(')
    map_name = "'#{map_name}'"
  end

  if key_name.class == Hash
    key_name = key_name.to_s
  elsif( not key_name.include? 'Ref(')
    key_name = "'#{key_name}'"
  end

  if value_name.nil?
    STDERR.puts("No value defined for mapping parameter. MapName=#{map_name},Key=#{key_name},Attribute=#{value_name}")
    exit 243
  end
  if value_name.class == Hash
    value_name = value_name.to_s
  elsif( not value_name.include? 'Ref(')
    value_name = "'#{value_name}'"
  end


  return "FnFindInMap(#{map_name},#{key_name},#{value_name})"

end