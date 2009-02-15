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
module ActiveFile; end

$:.unshift(File.dirname(__FILE__)) unless
  $:.include?(File.dirname(__FILE__)) || $:.include?(File.expand_path(File.dirname(__FILE__)))

require 'active_record/base'
require 'active_record/associations'

ActiveFile::Base.class_eval do
  include ActiveFile::Associations
end
