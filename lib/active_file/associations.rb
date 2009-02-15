module ActiveFile
  # =Associations between ActiveFile and ActiveFile
  #
  # Associations for ActiveFile records, first lets get associations
  # working between ActiveFile records.
  #
  #  has_one :target, :at => :field
  #
  # where :field is the name of an attribute on the object which has
  # the relation.  So for example say you have the following
  # ActiveFile object
  #
  #  class Doc << ActiveFile::Base
  #     self.base_directory = File.join("RAILS_ROOT", "projects")
  #     self.location = [:project_name, :name, :extension]
  #
  #     belongs_to :project, :from => :project_name, :to => :name
  #  end
  #
  # and you have a project ActiveFile::Base which looks something like
  #
  #  class Project << ActiveFile::Base
  #     self.base_directory = File.join("RAILS_ROOT", "projects")
  #     self.location = [:name "/"]
  #
  #     has_many :docs, :from => :name, :to => :project_name
  #  end
  #
  # and you want to relate each :Doc: to it's project, you would then
  # add the following line
  #
  #  belongs_to :project, :from => :project_name, :to => :name
  #
  # ActiveFile will then intercept calls to doc.project, and will call
  # Project.find(:name => doc.project_name) and return the related
  # project.
  #
  # =Association between ActiveFile and ActiveRecord
  #
  # then maybe we can provide an optional argument to association
  # calls inside ActiveRecord objects which will then intercept the
  # call and implement it as an ActiveFile association
  module Associations
    def self.included(base)
      base.extend ActiveFile::Associations
    end

    def has_many(referent, options = {})
      verify_options(options)
      build_relation(referent, false, options)
    end
    alias :has_multiple :has_many

    def has_one(referent, options = {})
      verify_options(options)
      build_relation(referent, true, options)
    end
    alias :belongs_to :has_one
    alias :has_single :has_one

    def build_relation(referent, singular_p, options = {})
      self.class_eval <<DEFUN
def #{singular_p ? referent.to_s : referent.to_s.pluralize}()
  #{(options[:class] or referent).to_s.classify}.
    find(:#{singular_p ? :first : :all}, :conditions => {:#{options[:to]} => self.send(:#{options[:from]})})
end
DEFUN
    end

    private

    def verify_options(options = {})
      raise ActiveFileAssociationError.new("did not specify :from or :to field") unless
        options.keys.include?(:from) and options.keys.include?(:to)
    end
  end
end
