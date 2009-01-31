# = ActiveFile: File persistence for Ruby on Rails Models
#
# Persist Ruby on Rails Models in your files system.  Like
# ActiveRecord or ActiveResource but using files instead of databases
# or REST.
#
# = Usage
#
# For maximum flexibility placement, each instance of this class
# (read: model) will have a placement definition in the form of an
# array of regexps which can be passed to File#join, to construct a
# large multi-directory regexp to search for matching files. (Note:
# all files must live inside of the global +DOCUMENT_ROOT+ constant
# which should be set in your environment.)
#
# for example:
#
# the following configuration will assign all of the files located in
# the code directory which have an rb extension as members of the
# RubyScript class.
#
#  class RubyScript < ActiveFile::Base
#    self.base_directory = File.join("RAILS_ROOT", "files")
#    self.location = %w{scripts * rb}
#
#  end
#
# if no location value is provided then the ActiveFile instance
# location will default to a directory named after the model (using
# the tableize function), with no specific extension.  As in the
# example above if a specific file extension is desired it should be
# packaged into the regexp used in the +location+ specification.  For
# more information on the construction of these regexps see the
# Dir#glob method.
#
# The +location+ can be used to save information into ActiveFile
# instances.  For example the following two location directives are
# the same except that the second will populate an +owner+ field with
# the name of the owning directory.
#
#   location ["models", "*", "*", false]
#
#   location ["models", :owner, "*", false]
#
# Any symbol used in a +location+ specification will be replaced with
# a "*" regexp, and will become the name of an attribute of the
# resulting Model.
#
# = Authinfo
#
# Author:: Eric Schulte (mailto:schulte.eric@gmail.com)
# Copyright:: (c) 2008,2009 Eric Schulte
# Date:: 2009-01-24
# Licence:: GNU General Public License
#
#  This program is free software; you can redistribute it and/or
#  modify it under the terms of the GNU General Public License as
#  published by the Free Software Foundation; either version 2, or (at
#  your option) any later version.
#
#  This program is distributed in the hope that it will be useful, but
#  WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#  General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program ; see the file COPYING.  If not, write to
#  the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
#  Boston, MA 02111-1307, USA.
#
module ActiveFile

  # for acts as stuffs
  module Acts end

  # Generic Active File exception class.
  class ActiveFileError < StandardError
  end

  class ActiveFileAssociationError < StandardError
  end

  class Base
    include ActiveSupport::Callbacks
    
    # used when converting paths to id's for use in url construction
    ACTIVEFILE_EXTENSION_ALT = "_"

    # hook run whenever a new class inherits from ActiveFile::Base
    def self.inherited(base)
      # set the default location (for use if none is specified)
      base.location = [base.name.tableize.to_s, "*"]
      # set the default base_directory (for use if none is specified)
      base.base_directory = (File.join(RAILS_ROOT, "db", "files"))
    end

    # Class methods
    class << self
      # Set the location array for this class.  The location array is
      # parsed into a regexp for Dir.glob and an array of the symbols
      # resulting from matches in this regexp is saved into
      # @location_attributes.
      def location=(location)
        @extension = location.pop
        @location = location
        @location_attributes = []
        @directory_p = false
        # last element of location is the file extension
        @location_glob = ((@location.map do |part|
                             if part.class == Symbol
                               "*"
                             else
                               part
                             end
                           end.join(Regexp.quote(File::SEPARATOR))) +
                          (if @extension.class == Symbol
                             "\\.*"
                           elsif @extension == "/"
                             @directory_p = true
                             ""
                           elsif @extension
                             "\\.#{@extension}"
                           else
                             ""
                           end))
        maybe = false
        @location_regexp = ((@location.map do |part|
                               (if maybe
                                  maybe = false
                                  "?"
                                else
                                  ""
                                end) +
                                 (if part.class == Symbol
                                    @location_attributes << part
                                    "(.+)"
                                  elsif part == "**"
                                    maybe = true
                                    ".*?"
                                  elsif part == "*"
                                    ".*"
                                  else
                                    part
                                  end)
                             end.join(Regexp.quote(File::SEPARATOR))) +
                            (if @extension.class == Symbol
                               @location_attributes << @extension
                               "\\.(.+)"
                             elsif @extension == "/"
                               ""
                             elsif @extension
                               "\\.#{@extension}"
                             else
                               ""
                             end))
      end
      def location() @location end
      def extension() @extension end
      def directory?() @directory_p end
      def location_regexp() @location_regexp end
      def location_glob() @location_glob end
      def location_attributes() @location_attributes end

      # This is used instead of a cattr_accessor because we want to
      # make sure that the directory exists and is a directory
      def base_directory=(directory)
        FileUtils.mkdir_p(directory)
        raise ActiveFileError.new("#{directory} is not a directory") unless FileTest.directory?(directory)
        @base_directory = directory
      end
      def base_directory() @base_directory end

      # Expand path to the absolute path inside of the base_directory.
      # The resulting path is used directly for creating, reading,
      # updating and deleting files.
      def expand(path) File.join(self.base_directory, path) end

      # check if a file exists at location
      def exist?(path) path if File.exist?(self.expand(path)) end

      # return the time the file at path was created
      def ctime(path) File.ctime(self.expand(path)) if self.exist?(path) end

      # return the time the file at path was last modified
      def mtime(path) File.mtime(self.expand(path)) if self.exist?(path) end

      # like ActiveRecord.find, if there is an instance with the given
      # file name then return it, otherwise return false
      def instance(path)
        if self.exist?(path)
          self.instantiate(path)
        elsif path.match("(.+)"+Regexp.quote(ACTIVEFILE_EXTENSION_ALT)+"(.+?)$")
          path = $1 + "." + $2
          self.instantiate(path) if self.exist?(path)
        end
      end
      alias :get :instance

      def all() self.find(:all) end
      def first() self.find(:first) end

      # TODO: document
      def find(spec, options = {})
        if spec == :all
          self.find_all(options)
        elsif spec == :first
          self.find_all(options).first
        elsif spec.class == Hash
          self.find_all(spec)
        elsif spec.class == String
          self.get(spec)
        end
      end

      # return all instances of this class
      def find_all(options = {})
        globbed = []
        Dir.chdir(self.base_directory) do
          globbed = Dir.glob(@location_glob).map{|path| self.instance(path)}
        end
        if conds = options[:conditions]
          matches = conds.keys.size
          globbed.select do |record|
            # matches every key, value pair in the conditions
            conds.keys.select do |key|
              record.send(key) == conds[key]
            end.size == matches
          end
        else
          globbed
        end
      end

      # return the number of instances of this class
      def count() self.find_all.size end

      # create a file at location
      def create(path, attributes = {})
        raise ActiveFileError.new("instance already exists at #{path}") if self.exist?(path)
        self.update(path, attributes)
      end

      # update the contents of the object located at path with the
      # information stored in attributes, then write the object out to
      # the file system
      def update(path, attributes = {})
        object = self.instantiate(path)
        attributes.each{ |key, value| object.send(key.to_s+"=", value) if object.respond_to?(key) }
        self.write(object)
        object
      end

      # update the contents of record based on what is saved in the file system
      def refresh(record)
        if self.directory?
          record.body = ""
        else
          record.body = File.read(self.expand(record.path))
        end
        record
      end

      # Update record's path based on the value of
      # location_attributes.  Will delete record from the old path,
      # and write it to the new path.  This method should only be
      # called if object already has a path.
      def update_path(record)
        # If record doesn't have a path, then try to generate one from
        # it's attributes, if this fails, then raise an error.
        unless old_path = record.path
          new_path = self.generate_path(record)
          raise ActiveFileError.new("This #{record.class} #{record} has no path, and it was "+
                                    "impossible to generate one based upon it's attributes.") unless new_path
        else # if record does have a path then update it
          match = old_path.match(@location_regexp)
          new_path = ""
          previous_end = 0
          @location_attributes.each_with_index do |attribute, index|
            index += 1
            re_start = match.begin(index)
            new_path <<
              if previous_end == re_start
                ""
              else
                old_path[(previous_end..(re_start - 1))]
              end <<
              # if the attributes exists, then use it otherwise take
              # what was in the path
              (record.send(attribute) or old_path[(re_start..(match.end(index) - 1))])
            previous_end = match.end(index)
          end
          new_path << old_path[(previous_end..-1)]
        end
        # move object to the location of the new path
        record.path = new_path
        new_path
      end
      alias :refresh_path :update_path

      # Generate a new path for record based on it's attributes,
      # otherwise return nil if this is not possible.  This method
      # should be overwritten when new behavior is desired.
      def generate_path(record)
        return nil if @location.include?("*") or @location.include?("**")
        new_path = @location.map{|p| if (p.class == Symbol)
                                       if record.send(p)
                                         record.send(p)
                                       else
                                         missing = true
                                         ""
                                       end
                                     elsif p.match("\\*")
                                       nil
                                     else
                                       p
                                     end}.compact.join(File::SEPARATOR)
        new_path << "." << if @extension
                             if @extension.class == Symbol and record.send(@extension)
                               record.send(@extension)
                             else
                               @extension.to_s
                             end
                           end
        new_path
      end

      # write the record to the file system
      def write(record)
        record.path = self.update_path(record)
        FileUtils.mkdir_p(File.dirname(record.path))
        if self.directory?
          FileUtils.mkdir(record.path) unless File.exist?(record.path)
        else
          File.open(self.expand(record.path), "w"){|f| f << record.body}
        end
      end
      alias :save :write

      # delete the file at location
      def delete(path)
        if self.exist?(path)
          object = self.instantiate(path)
          if self.directory?
            FileUtils.rmdir(self.expand(path))
          else
            File.delete(self.expand(path))
          end
          object
        else
          raise ActiveFileError.new("ActiveFile #{self.name} #{path} doesn't exist")
        end
      end

      # return an attributes hash, from the values in @location_attributes
      def generate_attributes(path)
        attributes = {}
        if path
          raise ActiveFileError.new("#{path} doesn't match #{@location_regexp}") unless
            match = path.match(@location_regexp)
          @location_attributes.each_with_index do |attribute, index|
            attributes[attribute] = match[index + 1]
          end
        else
          @location_attributes.each{|attribute| attributes[attribute] = nil}
        end
        # TODO: YAML support add all YAML keys to attributes
        attributes
      end

      # create an actual instance of this class
      def instantiate(path)
        object = self.allocate
        object.attributes = self.generate_attributes(path)
        object.path = path

        if self.exist?(path)
          unless self.directory?
            object.body = File.read(self.expand(path))
          end
        else
          FileUtils.mkdir_p(File.dirname(self.expand(path)))
          if self.directory?
            File.mkdir(self.expand(path))
          else
            FileUtils.touch(self.expand(path))
          end
        end

        ## populate location_attributes of object
        if object.path.match(@location_regexp)
          @location_attributes.each do |key|
            object
          end
        else
          raise ActiveFileError.new("ActiveFile #{self.name} invalid path #{self.path} "+
                                    "doesn't match #{@location_regexp}")
        end

        object
      end

    end

    #--------------------------------------------------------------------------------
    # Instance Methods
    attr_accessor :body, :attributes
    @path
    def path() @path end
    def full_path() self.class.expand(@path) end
    
    def path=(new_path)
      raise ActiveFileError.new("path #{new_path} doesn't match the location "+
                                "[#{self.base.location.join(", ")}]") unless
        new_path.match(self.class.location_regexp)
      @path = new_path
      self.attributes = self.class.generate_attributes(@path)
      self
    end
    
    define_callbacks :before_write, :after_write
    
    # create (but don't save) and return a new instance
    def initialize(attributes = {})
      self.attributes = self.class.generate_attributes(attributes[:path])
      self.apply_attributes(attributes)
    end

    def update_attributes(attributes = {})
      old_path = self.path
      self.apply_attributes(attributes)
      self.class.delete(old_path)
      self.write
    end

    def apply_attributes(attributes = {})
      attributes.each do |key, value|
        self.send("#{key}=", value) if (self.respond_to?("#{key}=") or
                                        self.class.location_attributes.include?(key.to_s.intern))
      end
      self
    end

    # dynamically add methods attr_accessor type methods for every key
    # in the attributes hash
    def method_missing(id, *args)
      set = id.to_s.include?("=")

      if @attributes.keys.include?(id)
        # if we can return an attribute
        @attributes[id]
      elsif (new_id = id.to_s.sub("=","").intern and @attributes.keys.include?(new_id))
        # elsif we can set an attribute
        @attributes[id] = args[0]
        self.path = self.class.refresh_path(self) if
          (self.path or self.class.generate_path(self))
      elsif (self.class.directory? and Dir.public_methods.include?(id))
        # elsif we can call a directory method

      else
        super(id, args)
      end
    end
    
    # return path for id since that is our unique identifier
    def id() self.to_s end

    # write the body of self to the file specified by name
    def write()
      run_callbacks(:before_write)
      self.class.write(self)
      run_callbacks(:after_write)
    end
    alias :save :write

    # delete the file holding self, and return self if successful
    def destroy() self.class.delete(self.path) end

    # re-read self's body from the file system
    def refresh() self.class.refresh(self) end

    # return the time that self was created
    def ctime() self.class.ctime(self.path) end
    alias :created_at :ctime

    # return the time that self was last modified
    def mtime() self.class.mtime(self.path) end
    alias :updated_at :mtime

    # return a pleasant string for introspection
    def inspect
      "#<#{self.class}:'#{self.path}' #{self.attributes.map{|key, value| "#{key}=#{value}"}.join(", ")}>"
    end

    # Used by the Rails url_for url path generation in view helpers
    def to_s()
      # escape an ActiveFile id (which is actually a file path) so
      # that the extension isn't obvious enough for rails to grab it
      # and turn it into the format of the request.
      if self.path
        if self.path.match("(.+)\\.(.+?)$")
          $1 + ACTIVEFILE_EXTENSION_ALT + $2
        else
          self.path
        end
      end
    end

    # Indicate if self has been saved yet or is new (used by form_for etc...)
    def new_record?() not self.path end

  end

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
