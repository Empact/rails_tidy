require 'tidy'
require 'find'

# = RailsTidy
#
# class use to validate html in templates and in http response
class RailsTidy

  private
  IGNORED = [
    /<a> escaping malformed URI reference/,
    /attribute "id" has invalid value "<%=.*?%>"/,
    /<link> escaping malformed URI reference/,
    /<div> anchor "<%=.*?%>" already defined/
  ]
  
  MASK = /\.rhtml$/

  @@path = File.join(RAILS_ROOT, "app", "views")
  os = Config::CONFIG["arch"]
  if os =~ /cygwin/
    @@tidy_path = "/usr/bin/cygtidy-0-99-0.dll"
  elsif os =~ /darwin/
    @@tidy_path = "/usr/lib/libtidy.dylib"
  else
    @@tidy_path = "/usr/lib/libtidy.so"
  end
  @@tidy_configuration = File.join(RAILS_ROOT, "config", "tidy.rc")

  public

  # path of the file or directory to validate
  #
  # if path is a file, it will be validated using tidy,
  # if it is a directory, it will search it for .rhtml file
  # and validate all those files.
  def self.path=(path)
    @@path = path
  end

  # path to the tidy library
  def self.tidy_path=(tidy_path)
    @@tidy_path = tidy_path
  end

  def self.tidy_path
    @@tidy_path
  end

  # path to tidy configuration file, set
  # to config/tidy.rc by default
  def self.tidy_configuration=(tidy_configuration)
    @@tidy_configuration = tidy_configuration
  end

  # validate templates in path
  def self.run
    td = self.new
    td.validate
  end
  
  def initialize
    @tidy = RailsTidy.tidy_factory
  end
  
  # validate all templates in path
  def validate
    if File.directory?(@@path)
      Find.find(@@path) do |file|
        if file.match(MASK) 
          @file = file
          validate_file
        end
      end
    else
      if File.file?(@@path)
        @file = @@path
      elsif File.file?("#{@@path}.rhtml")
        @file = "#{@@path}.rhtml"
      elsif File.file?(File.join(RAILS_ROOT, "app", "views", @@path))
        @file = File.join(RAILS_ROOT, "app", "views", @@path)
      elsif File.file?(File.join(RAILS_ROOT, "app", "views", @@path) + ".rhtml")
        @file = File.join(RAILS_ROOT, "app", "views", @@path) + ".rhtml"
      end
      validate_file
      puts @tidy.errors
      puts @tidy.diagnostics
    end
  end

  # validate a single file
  def validate_file
    printf "%-70s", @file
    
    content = format_content(IO.read(@file))

    # validate
    @tidy.clean(content)

    # and log erros
    log_errors 
  end

  # log tidy output
  def log_errors
    # remove errors that are to be ignored
    @tidy.errors.delete_if do |error|
      IGNORED.inject(false) { |b,r| b ||= error.message.match(r) }
    end

    # display errors
    unless @tidy.errors.empty?
      puts "ERRORS"
      File.open(log_file, "w") do |log|
        log.puts @tidy.errors
        log.puts
        log.puts @tidy.diagnostics
      end
    else
      File.delete(log_file) if File.exists?(log_file)
      puts "OK"
    end
  end

  # format the response
  #
  # this method add doctype and missing tag so that when a
  # a templates miss doctypes or html tag, tidy does not complain
  def format_content(content)
    # add doctype if not found
    validable = ""
    unless content.match(/<!DOCTYPE/)
      validable << "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\" " +
        " \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">"
    end

    # add html, head, title and body 
    unless content.match(/<html/)
      validable << "<html><head><title>rake test_templates</title></head><body>#{content}</body></html>"
    else
      validable << content
    end

    # replace start_form_tag and end_form_tag with <form> and </form>
    validable.gsub!(/<%=\s*start_form_tag.*?%>/, "<form action=\"test\">")
    validable.gsub!(/<%=\s*form_remote_tag.*?%>/, "<form action=\"test\">")
    validable.gsub!(/<%=\s*end_form_tag.*?%>/, "</form>")
    return validable
  end

  # filter the body of a response
  #
  # use this method in an after_filter. 
  # Example:
  #
  #   after_filter :tidy
  #   def tidy
  #     RailsTidy.filter(response)
  #   end
  def self.filter(response)
    tidy = tidy_factory
    response.body = tidy.clean(response.body)
    tidy.errors.each { |error| logger.debug("Tidy: #{error}") }
    tidy.release
  end

  # return a new tidy instance
  def self.tidy_factory
    Tidy.path = @@tidy_path
    tidy = Tidy.new
    tidy.load_config(@@tidy_configuration) if File.exists?(@@tidy_configuration)
    tidy
  end

  private
  def log_file
    "#{@file}.errors"
  end

end

module Test #:nodoc:
  module Unit #:nodoc:
    module Assertions
      def assert_tidy
        if @response.success?
          tidy = RailsTidy.tidy_factory
          tidy.clean(@response.body)
          tidy.errors.each do |error|
            RAILS_DEFAULT_LOGGER.error(error)
          end
          tidy.diagnostics.each do |info|
            RAILS_DEFAULT_LOGGER.info(info)
          end
          unless tidy.errors.size.zero?
            message = ("-" * 40) + $/
            i = 1
            @response.body.each do |line|
              message << sprintf("%4u %s", i, line)
              i += 1
            end
            message << ("-" * 40) + $/
            message << tidy.errors.join($/)
          end
          assert tidy.errors.size.zero?, "Tidy detected html errors in response body: #{$/} #{message}"
          tidy.release
        end
      end
    end
  end
end
      
