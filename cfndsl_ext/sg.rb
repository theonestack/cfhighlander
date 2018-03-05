
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
  if ip_block_name == 'stack'
    cidr = [FnJoin( "", [ "10.", Ref('StackOctet'), ".", "0.0/16" ] )]
  elsif ips.has_key? ip_block_name
    cidr = ips[ip_block_name]
  else
    cidr = [ip_block_name]
  end
  cidr
end
