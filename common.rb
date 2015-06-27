class Object
  def blank?
    return true if self.nil?
    return true if self.respond_to?(:empty?) && self.empty?
    false
  end
end

class Fixnum
  def hour
    self*3600
  end
end

class HashWithIndifferentAccess < Hash
  def [](key)
    key = key.to_s if key.is_a?(Symbol)
    super(key)
  end
end

