module Ohm
  #module Attributes
  class Model
    include Scrivener::Validations
    class Set
      # Returns an array of Ohm::Models converted to JSON
      def to_json
        [].tap { |array|
          self.each do |object|
            array << object.to_json rescue {}
          end
        }
      end
    
      def find_by_id(id)
        self.select {|object|
          object.id == id.to_s
        }.first
      end
    end
  end
  
  module Validations
  protected
    def assert_confirmation(att, confirmation, error = [att, :confirmation])
      if assert_present(att, error) and assert_present(confirmation, error)
        assert(send(att).to_s.eql?(send(confirmation).to_s), error)
      end
    end
  end
  
  class Model    
    def returning(value)
      yield(value)
      value
    end
    
    # Returns what attributes should return, a hash of the models attributes
    # and their values
    def attributes_with_values
      returning attrs = {} do
        #logger.debug("self.id: #{self.id}")
        attrs[:id] = self.id rescue nil
        self.attributes.each do |attribute|
          logger.debug("attribute: #{attribute.inspect} and class: #{attribute.class}")
          #attrs[attribute] = self.send(attribute)
          attrs[attribute[0]] = attribute[1]
        end
      end
    end
  end
end