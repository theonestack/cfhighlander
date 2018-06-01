require 'netaddr'

def sg_create_rules (x, ip_blocks={})
  rules = []
  x.each do | group |
    group['ips'].each do |ip|
      group['rules'].each do |rule|
        lookup_ips_for_sg(ip_blocks, ip).each do |cidr|
          rules << { IpProtocol: "#{rule['IpProtocol']}", FromPort: "#{rule['FromPort']}", ToPort: "#{rule['ToPort']}", CidrIp: cidr }
        end
      end
    end
  end
  return rules
end


def lookup_ips_for_sg (ips, ip_block_name={})
  cidr = []
  if ip_block_name == 'stack'
    cidr = [FnJoin( "", [ "10.", Ref('StackOctet'), ".", "0.0/16" ] )]
  elsif ips.has_key? ip_block_name
    ips[ip_block_name].each do |ip|
      if (ips.include?(ip) || ip_block_name == 'stack')
        cidr += lookup_ips_for_sg(ips, ip) unless ip == ip_block_name
      else
        if ip == 'stack'
          cidr << [FnJoin( "", [ "10.", Ref('StackOctet'), ".", "0.0/16" ] )]
        elsif(isCidr(ip))
          cidr << ip
        else
          STDERR.puts("WARN: ip #{ip} is not a valid CIDR. Ignoring IP")
        end
      end
    end
  else
    if isCidr(ip_block_name)
      cidr = [ip_block_name]
    else
      STDERR.puts("WARN: ip #{ip_block_name} is not a valid CIDR. Ignoring IP")
    end
  end
  cidr
end

def isCidr(block)
  begin
    NetAddr::CIDR.create(block)
    return block.include?('/')
  rescue NetAddr::ValidationError
    return false
  end
end