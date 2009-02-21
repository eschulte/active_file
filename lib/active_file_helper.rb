# =ActiveFileHelper
# 
# This module provides helpers for passing ActiveFile records between
# your views and controllers.  For example, with this in your
# view
#
#    <%= link_to(@record.name, af_path(:show, @record)) %>
#
# you can put this in your controller
#
#    def show
#      @record = Klass.find(af_id)
#    end
#
# for these paths to work you will need to place the following into
# config/routes.rb.
#
#    map.connect ':controller/:action/*rest.:format'
#
# *Note*: This will probably conflict with the default rails routes.
# If you use those you will want one line like in your
# config/routes.rb for each ActiveFile controller.  So say the name of
# your ActiveFile controller is <tt>PagesController</tt>, then you
# will want to add the following in your config/routes.rb
#
#    map.connect 'pages/:action/*rest.:format', :controller => 'pages'
#
module ActiveFileHelper

  def af_id()
    params[:rest].join("/")
  end

  def af_path(action, af, options = {})
    options = {:controller => af.class.name.tableize}.merge(options)
    path = ["", options.delete(:controller), action, af].compact.map(&:to_s).join("/")
    path = force_extension(path, options.delete(:format)) if options.keys.include?(:format)
    if options.size > 0
      path + "?" + options.map{ |key, value| "#{key}=#{value}" }.join("&")
    else
      path
    end
  end
  
  # if new_extension is not true, then any existing extension will be stripped
  def force_extension(path, new_extension = nil)
    path = $1 if path.match("^(.+)\\.(.+?)$")
    if new_extension
      "#{path}.#{new_extension}"
    else
      path
    end
  end

end
