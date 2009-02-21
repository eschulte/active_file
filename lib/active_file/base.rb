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
        @location_regexp = ("^" +
                            (@location.map do |part|
                               (if maybe
                                  maybe = false
                                  "?"
                                else
                                  ""
                                end) +
                                 (if part.class == Symbol
                                    @location_attributes << part
                                    "([^/]+)"
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
                             end) + "$")
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
        raise ActiveFileError.new("ActiveFile::RecordNotFound: Couldn't find #{self.name} at path=#{path}") unless self.exist?(path)
        object = self.instantiate(path)
        object.new_p = false
        object
      end
      alias :get :instance

      def all() self.find(:all) end
      def first() self.find(:first) end
      def last() self.find(:last) end

      # by hook or by crook return one or all instances located near
      # or at spec.  If neither <tt>:all</tt> or <tt>:first</tt>
      # options are supplied then this is biased towards only
      # returning a single result when there is a clear victor.
      def find(spec, options = {})
        if spec == :all
          self.find_all(options)
        elsif spec == :first
          self.find_all(options).first
        elsif spec == :last
          self.find_all(options).last
        elsif spec.class == Hash
          self.find_all(spec)
        elsif spec.class == String or spec.class == Symbol
          atted = self.at(spec.to_s)
          if atted.size == 1
            atted.first
          elsif spec.to_s.match(self.location_regexp)
            self.get(spec.to_s)
          end
        end
      end

      # Search for *any* files in self.base_directory using Dir.glob
      def glob(path_glob)
        globbed = []
        Dir.chdir(self.base_directory) { globbed = Dir.glob(path_glob + "*") }
        Dir.chdir(self.base_directory) { globbed += Dir.glob(File.join(path_glob, "**", "*")) }
        globbed
      end

      # return all instances which are located at the supplied path
      def at(path)
        self.glob(path).
          select{|path| self.exist?(path)}.
          select{|path| path.match(self.location_regexp)}.
          map{|path| self.instance(path)}
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
      # information stored in attributes, then save the object out to
      # the file system
      def update(path, attributes = {})
        object = self.instantiate(path)
        attributes.each{ |key, value| object.send(key.to_s+"=", value) if object.respond_to?(key) }
        self.save(object)
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
      # and save it to the new path.  This method should only be
      # called if object already has a path.
      def update_path(record)
        # If record doesn't have a path, then try to generate one from
        # it's attributes, if this fails, then raise an error.
        unless old_path = record.path
          new_path = self.generate_path(record)
          unless new_path
            record.errors.add_to_base("This #{record.class} #{record} has no path, and it was "+
                                      "impossible to generate one based upon it's attributes.")
            return false
          end
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

      # save the record to the file system
      def save(record)
        if (record.new_p and self.exist?(record.path))
          record.errors.add_to_base("A #{self.name} already exists at path='#{record.path}'")
          return false
        end
        record.path = self.update_path(record)
        FileUtils.mkdir_p(File.dirname(record.full_path))
        if self.directory?
          if (File.exist?(record.full_path) or FileUtils.mkdir(record.full_path))
            record.new_p = false
            record
          end
        else
          if File.open(record.full_path, "w"){|f| f << record.body}
            record.new_p = false
            record
          end
        end
      end
      alias save! save

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
          raise ActiveFileError.new("ActiveFile::RecordNotFound: Couldn't find #{self.name} with path=#{path}")
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
          object.errors.add_to_base("ActiveFile #{self.name} invalid path #{self.path} "+
                                    "doesn't match #{@location_regexp}")
          false
        end
        object
      end
    end

    #--------------------------------------------------------------------------------
    # Instance Methods
    attr_accessor :body, :attributes, :new_p
    @path
    def path() @path end
    def full_path()
      return nil unless @path
      self.class.expand(@path)
    end

    def path=(new_path)
      raise ActiveFileError.new("path #{new_path} doesn't match the location "+
                                "[#{self.base.location.join(", ")}]") unless
        new_path.match(self.class.location_regexp)
      @path = new_path
      self.attributes = self.class.generate_attributes(@path)
      self
    end

    # define_callbacks :before_save, :after_save

    # create (but don't save) and return a new instance
    def initialize(attributes = {})
      self.new_p = true
      self.attributes = self.class.generate_attributes(attributes[:path])
      self.apply_attributes(attributes)
    end

    def update_attributes(attributes = {})
      old_path = self.path
      self.apply_attributes(attributes)
      self.class.delete(old_path)
      self.save
    end

    def update_attribute(name, value)
      self.send("#{name}=", value) if (self.respond_to?("#{key}=") or
                                       self.class.location_attributes.include?(key.to_s.intern))
    end

    def apply_attributes(attributes = {})
      attributes.each do |key, value|
        self.send("#{key}=", value) if (self.respond_to?("#{key}=") or
                                        self.class.location_attributes.include?(key.to_s.intern))
      end
      self
    end

    def entries(dir = nil)
      directory = File.join(self.class.base_directory,
                            (self.class.directory? ? self.path : File.dirname(self.path)),
                            (dir ? dir : ""))
      Dir.entries(directory) if File.directory?(directory)
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
      else
        super(id, args)
      end
    end

    # return path for id since that is our unique identifier
    def id() self.to_s end

    # save the body of self to the file specified by name
    def save() self.class.save(self) end
    alias :save! :save

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
          $1
        else
          self.path
        end
      end
    end

    # Indicate if self has been saved yet or is new (used by form_for etc...)
    def new_record?() not self.path end

    # error handling like ActiveRecord
    include ActiveRecord::Validations
  end
end
