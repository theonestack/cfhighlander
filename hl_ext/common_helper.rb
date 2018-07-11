class ::Hash
  def deep_merge(second)
    merger = proc {|key, v1, v2| Hash === v1 && Hash === v2 ? v1.merge(v2, &merger) : Array === v1 && Array === v2 ? v1 | v2 : [:undefined, nil, :nil].include?(v2) ? v1 : v2}
    self.merge(second.to_h, &merger)
  end


  def extend(second)
    second.each {|k, v|

      if ((self.key? k) and (v.is_a? Hash and self[k].is_a? Hash))
        self[k].extend(v)
      else
        self[k] = v
      end

    } if second.is_a? Hash

    self
  end
end
