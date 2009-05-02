module ActiveFile
  # =Hooks
  #
  # Add 'before' and 'after' hooks to events in the lifecycle of an
  # ActiveFile object.  Hooks can be added to any method.  For example
  # the following will add a hook to be run after an object is saved
  #
  #   add_hooks :save, :destroy
  #    
  #   def after_save
  #     puts "I've been saved '#{self.path}'"
  #   end
  #
  # what happens here is the add_hooks method wraps :save in calls to
  # before_save and after_save methods which will be called if
  # defined.  If the before_save method returns false, then the save
  # will be aborted.  Any number of method names can be passed to the
  # add_hooks method
  module Hooks
    def self.included(base)
      base.extend ActiveFile::Hooks
    end

    # accept any number of method names to be wrapped in before_method
    # and after_method hooks
    def add_hooks(*args) args.each{ |method| add_hooks_to(method) } end
    
    def add_hooks_to(method)
      self.class_eval <<HOOKED
    ## hooks
    def #{method}_with_hooks
      return false if self.hook(:before_#{method})
      result = self.#{method}_without_hooks
      self.hook(:after_#{method})
      result
    end
    alias_method_chain(:#{method}, :hooks)
HOOKED
    end

    def hook(name)
      (self.respond_to?(name) and (self.send(name) == false))
    end
  end
end
