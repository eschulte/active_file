# require ActiveFile
require 'active_file'

# Add associations to ActiveFile
ActiveFile::Base.send(:include, ActiveFile::Associations)

# Add associations to ActiveRecord
module ActiveRecord::Associations::ClassMethods
    %w{has_many has_one}.each do |meth|
      eval(<<METHOD_OVERRIDE
    # intercepting the #{meth} method to add the :as_active_file option
    alias :orig_#{meth} :#{meth}
    def #{meth}(name, options = {})
      if options.delete(:as_active_file)
        raise ActiveFileAssociationError.new("did not specify :from or :to field") unless
          options.keys.include?(:from) and options.keys.include?(:to)
        self.class_eval <<DEFUN
def #{meth == "has_one" ? "\#{name.to_s}" : "\#{name.to_s.pluralize}"}()
  \#{(options[:class] or name).to_s.classify}.
    find(:#{meth == "has_one" ? :first : :all},
         :conditions => {:\#{options[:to]} => self.send(:\#{options[:from]})})
end
DEFUN
      else
        orig_#{meth}(name, options)
      end
    end
METHOD_OVERRIDE
    )
    end
end

ActionView::Base.send :include, ActiveFileHelper
